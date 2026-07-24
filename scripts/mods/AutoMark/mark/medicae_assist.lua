--[[
    medicae_assist.lua
    One-press medicae skull order: the keybind wields the servo skull order
    ability (by faking grenade_ability_pressed/hold), steers the camera onto
    the closest valid downed teammate, waits for the game's own target lock,
    then fakes the hold release so the game issues the inject-ally order at
    the locked target. Times out with a clean block-cancel if no lock happens.
--]]

---@class AutoMarkMod:DMFMod
local mod                         = get_mod("AutoMark")
local context                     = mod.context
local mod_settings                = mod.settings

-- Imports
local CompanionServoSkullAbility  = require("scripts/utilities/companion/companion_servo_skull_ability")
local CompanionServoSkullSettings = require("scripts/settings/companion/companion_servo_skull_settings")
local SpecialRulesSettings        = require("scripts/settings/ability/special_rules_settings")
local special_rules               = SpecialRulesSettings.special_rules
local servo_skull_states          = CompanionServoSkullSettings.STATES
local MAX_TARGET_RANGE            = CompanionServoSkullSettings.max_target_distance_range or 25

-- Global Cache
local ALIVE                       = ALIVE
local HEALTH_ALIVE                = HEALTH_ALIVE
local POSITION_LOOKUP             = POSITION_LOOKUP
local Managers                    = Managers
local ScriptUnit                  = ScriptUnit
local Unit                        = Unit
local Vector3                     = Vector3
local GameSession                 = GameSession
local CLASS                       = CLASS
local PI, TWO_PI                  = math.pi, math.pi * 2

-- the game confirms the order when the aim action sees hold == false, and
-- cancels it when action_two is pressed while still holding
local PRESS_WINDOW                = 0.3
local CANCEL_WINDOW               = 0.15
local LAUNCH_MIN_AIM              = 0.5
local LAUNCH_MIN_LOCK             = 0.12
local ASSIST_TIMEOUT              = 5

-- nil | "aim" | "cancel" | "return"
local assist_phase                = nil
local assist_until                = 0
local assist_pressed_until        = 0
local assist_cancel_until         = 0
local assist_started_t            = 0
local assist_aligned_since        = nil
-- camera-return state: the net rotation the snap applied, unwound in reverse
-- after the order fires (player input during snap/return is untouched and
-- therefore preserved automatically)
local return_until                = 0
local snap_delta_yaw              = 0
local snap_delta_pitch            = 0

local RETURN_TIMEOUT              = 1.0

local function main_now()
    return Managers.time and Managers.time:time("main") or 0
end

local function stop_assist()
    assist_phase = nil
    assist_aligned_since = nil
    snap_delta_yaw, snap_delta_pitch = 0, 0
end

-- cancel the forced aim without firing the order (block_cancel input path)
local function cancel_assist()
    if assist_phase == "aim" then
        assist_phase = "cancel"
        assist_cancel_until = main_now() + CANCEL_WINDOW
    else
        stop_assist()
    end
end

local function get_medicae_skull(player_unit)
    local talent_extension = ScriptUnit.has_extension(player_unit, "talent_system")
    if not talent_extension or not talent_extension:has_special_rule(special_rules.cryptic_servo_skull_inject_ally) then
        return nil
    end

    local companion_spawner_extension = context.companion_spawner_extension
    local skull = companion_spawner_extension and companion_spawner_extension:spawned_unit_lookup(special_rules.cryptic_servo_skull_inject_ally)
    if not skull or not ALIVE[skull] then
        return nil
    end

    return skull
end

local function is_skull_reviving(skull)
    local game_session = Managers.state.game_session:game_session()
    local game_object_id = Managers.state.unit_spawner:game_object_id(skull)
    if not game_object_id or not GameSession.game_object_exists(game_session, game_object_id) then
        return false
    end

    local state = GameSession.game_object_field(game_session, game_object_id, "state")
    return state == servo_skull_states.inject_ally
end

local function find_best_ally(player_unit, skull, from_position)
    local ability_extension = ScriptUnit.has_extension(player_unit, "ability_system")
    if not ability_extension then
        return nil
    end

    local best, best_distance
    for _, player in pairs(Managers.player:players()) do
        local target_unit = player.player_unit
        if target_unit and target_unit ~= player_unit and HEALTH_ALIVE[target_unit] then
            local valid = CompanionServoSkullAbility.validate_target_func_inject_ally_ability(target_unit, ability_extension, skull)
            if valid then
                local target_position = POSITION_LOOKUP[target_unit]
                local distance = target_position and Vector3.distance(from_position, target_position)
                if distance and distance <= MAX_TARGET_RANGE and (not best_distance or distance < best_distance) then
                    best, best_distance = target_unit, distance
                end
            end
        end
    end

    return best
end

-- Keybind entry
mod.medicae_assist = function()
    if assist_phase then
        cancel_assist()
        mod:notify(mod:localize("medicae_assist_canceled"))
        return
    end

    if not context.mod_enabled or not context.game_mode_valid or context.class_name ~= "cryptic" then
        return
    end

    local player = context.player
    local player_unit = player and player.player_unit
    if not player_unit or not HEALTH_ALIVE[player_unit] then
        return
    end

    local skull = get_medicae_skull(player_unit)
    if not skull then
        mod:notify(mod:localize("medicae_assist_no_skull"))
        return
    end

    if is_skull_reviving(skull) then
        mod:notify(mod:localize("medicae_assist_busy"))
        return
    end

    local from_position = POSITION_LOOKUP[player_unit] or Unit.world_position(player_unit, 1)
    local ally = find_best_ally(player_unit, skull, from_position)
    if not ally then
        mod:notify(mod:localize("medicae_assist_no_target"))
        return
    end

    local t = main_now()
    assist_phase = "aim"
    snap_delta_yaw, snap_delta_pitch = 0, 0
    assist_started_t = t
    assist_until = t + ASSIST_TIMEOUT
    assist_pressed_until = t + PRESS_WINDOW
    assist_aligned_since = nil
end

-- ===== Camera steering =====

local function angle_delta(a, b)
    return (a - b + PI) % TWO_PI - PI
end

local function step_angle(current, wanted, max_step)
    local delta = math.clamp(angle_delta(wanted, current), -max_step, max_step)
    return math.mod_two_pi(current + delta)
end

local function is_target_locked(unit_data_extension, ally)
    local target_finder = unit_data_extension:read_component("action_module_ability_target_finder")
    return target_finder and target_finder.target_unit_1 == ally or false
end

local function assist_aim_body(self, main_dt)
    local t = main_now()
    if t > assist_until then
        cancel_assist()
        return
    end

    local player = self._player
    local player_unit = player and player.player_unit
    if not player_unit or not HEALTH_ALIVE[player_unit] or not context.game_mode_valid then
        cancel_assist()
        return
    end

    local skull = get_medicae_skull(player_unit)
    if not skull then
        cancel_assist()
        return
    end

    local first_person_component = self._first_person_component
    local cam_position = first_person_component and first_person_component.position
    if not cam_position then
        return
    end

    local ally = find_best_ally(player_unit, skull, cam_position)
    if not ally then
        cancel_assist()
        return
    end

    local target_position
    if Unit.has_node(ally, "j_spine") then
        target_position = Unit.world_position(ally, Unit.node(ally, "j_spine"))
    else
        target_position = POSITION_LOOKUP[ally] + Vector3(0, 0, 0.3)
    end

    local orientation = self._orientation
    local direction = Vector3.normalize(target_position - cam_position)
    local wanted_yaw = math.mod_two_pi(math.atan2(direction.y, direction.x) - PI * 0.5)
    local wanted_pitch = math.mod_two_pi(math.asin(direction.z))
    local max_step = math.rad(mod_settings.medicae_snap_speed or 900) * (main_dt or 0.016)

    local old_yaw, old_pitch = orientation.yaw, orientation.pitch
    orientation.yaw = step_angle(orientation.yaw, wanted_yaw, max_step)
    local new_pitch = step_angle(orientation.pitch, wanted_pitch, max_step)
    local min_pitch, max_pitch = self._min_pitch, self._max_pitch
    if min_pitch and max_pitch then
        new_pitch = math.clamp((new_pitch + PI) % TWO_PI - PI, min_pitch, max_pitch) % TWO_PI
    end
    orientation.pitch = new_pitch
    -- accumulate what the snap itself applied (post-clamp), for the unwind
    snap_delta_yaw = snap_delta_yaw + angle_delta(orientation.yaw, old_yaw)
    snap_delta_pitch = snap_delta_pitch + angle_delta(orientation.pitch, old_pitch)

    -- release the order once the game's own targeting locked the ally
    local unit_data_extension = ScriptUnit.has_extension(player_unit, "unit_data_system")
    local locked_ok, locked = pcall(is_target_locked, unit_data_extension, ally)
    if locked_ok and locked then
        assist_aligned_since = assist_aligned_since or t
        if t - assist_started_t >= LAUNCH_MIN_AIM and t - assist_aligned_since >= LAUNCH_MIN_LOCK then
            -- stop forcing the hold; the real (unpressed) input reads false,
            -- which is exactly the aim_released confirm
            mod:print_debug("medicae assist: target locked, releasing order")
            if mod_settings.medicae_return_camera then
                assist_phase = "return"
                assist_aligned_since = nil
                return_until = t + RETURN_TIMEOUT
            else
                stop_assist()
            end
        end
    else
        assist_aligned_since = nil
    end
end

-- Unwinds the exact rotation the snap applied, in reverse. Player input
-- during snap or return is separate movement, so it is preserved as-is.
local function assist_return_body(self, main_dt)
    local t = main_now()
    if t > return_until then
        stop_assist()
        return
    end

    local orientation = self._orientation
    local max_step = math.rad(mod_settings.medicae_snap_speed or 900) * (main_dt or 0.016)

    local yaw_step = math.clamp(-snap_delta_yaw, -max_step, max_step)
    orientation.yaw = math.mod_two_pi(orientation.yaw + yaw_step)
    snap_delta_yaw = snap_delta_yaw + yaw_step

    local old_pitch = orientation.pitch
    local pitch_step = math.clamp(-snap_delta_pitch, -max_step, max_step)
    local new_pitch = math.mod_two_pi(orientation.pitch + pitch_step)
    local min_pitch, max_pitch = self._min_pitch, self._max_pitch
    if min_pitch and max_pitch then
        new_pitch = math.clamp((new_pitch + PI) % TWO_PI - PI, min_pitch, max_pitch) % TWO_PI
    end
    orientation.pitch = new_pitch
    -- credit only what was actually applied after the clamp
    snap_delta_pitch = snap_delta_pitch + angle_delta(orientation.pitch, old_pitch)

    if math.abs(snap_delta_yaw) < 0.005 and math.abs(snap_delta_pitch) < 0.005 then
        stop_assist()
    end
end

mod:hook_safe("DefaultPlayerOrientation", "pre_update", function(self, main_t, main_dt)
    if not assist_phase then
        return
    end
    if assist_phase == "aim" then
        pcall(assist_aim_body, self, main_dt)
    elseif assist_phase == "return" then
        pcall(assist_return_body, self, main_dt)
    elseif assist_phase == "cancel" and main_now() > assist_cancel_until then
        stop_assist()
    end
end)

-- ===== Forced ability input =====

mod:hook(CLASS.InputService, "_get", function(func, self, action_name)
    if not assist_phase then
        return func(self, action_name)
    end

    if assist_phase == "aim" then
        if action_name == "grenade_ability_pressed" then
            if main_now() < assist_pressed_until then
                return true
            end
        elseif action_name == "grenade_ability_hold" then
            return true
        end
    elseif assist_phase == "cancel" then
        -- block_cancel: action_two while the hold is still down aborts the aim
        if main_now() > assist_cancel_until then
            stop_assist()
            return func(self, action_name)
        end
        if action_name == "grenade_ability_hold" then
            return true
        elseif action_name == "action_two_pressed" then
            return true
        end
    end

    return func(self, action_name)
end)
