---@class AutoMarkMod:DMFMod
local mod                         = get_mod("AutoMark")
local context                     = mod.context
local mark_context                = mod.mark_context
local TAG_NAMES                   = mod.TAG_NAMES

-- Imports
local SpecialRulesSettings        = require("scripts/settings/ability/special_rules_settings")
local CompanionServoSkullSettings = require("scripts/settings/companion/companion_servo_skull_settings")
local special_rules               = SpecialRulesSettings.special_rules
local servo_skull_states          = CompanionServoSkullSettings.STATES

-- Global Cache
local Managers                    = Managers
local callback                    = callback

local HACK_TAG_NAME               = "hacking_over_here_companion"

local function servo_skull_mark_callback()
    local smart_tag_system = context.smart_tag_system
    if not smart_tag_system then
        return
    end

    local target_unit = mod:find_target_unit()
    if not target_unit then
        return
    end

    local target_tag = smart_tag_system:unit_tag(target_unit)
    local tag_name = TAG_NAMES.SERVO_SKULL_TAG
    mod:on_manual_mark(mark_context[tag_name], target_unit)
    mod:mark(tag_name, target_unit, target_tag)
end

local function enemy_mark_callback()
    local smart_tag_system = context.smart_tag_system
    if not smart_tag_system then
        return
    end

    local target_unit = mod:find_target_unit()
    if not target_unit then
        return
    end

    local target_tag = smart_tag_system:unit_tag(target_unit)
    if target_tag then
        return
    end

    local tag_name = TAG_NAMES.ENEMY_TAG
    mod:on_manual_mark(mark_context[tag_name], target_unit)
    mod:mark(tag_name, target_unit, target_tag)
end

mod.servo_skull_mark = function()
    if not context.mod_enabled or not context.game_mode_valid or context.class_name ~= "cryptic" or not context.has_servo_skull then
        return
    end

    local companion_command_tap = context.companion_command_tap
    if companion_command_tap == "double" then
        local cb = callback(servo_skull_mark_callback)
        Managers.state.game_mode:register_physics_safe_callback(cb)
    elseif companion_command_tap == "single" then
        local cb = callback(enemy_mark_callback)
        Managers.state.game_mode:register_physics_safe_callback(cb)
    end
end

local function hack_mark_callback()
    local smart_tag_system = context.smart_tag_system
    if not smart_tag_system then
        return
    end

    local hud_element_smart_tagging = context.hud_element_smart_tagging
    if not hud_element_smart_tagging then
        return
    end

    local player = context.player
    local player_unit = player and player.player_unit
    if not player_unit then
        return
    end

    local target_marker, _ = hud_element_smart_tagging:_find_world_marker_target()
    local target_unit = target_marker and target_marker.unit
    if not target_unit then
        return
    end

    local target_extension = smart_tag_system._unit_extension_data[target_unit]
    local template_name = target_extension
        and target_extension:_contextual_tag_template_name(player_unit, "companion_order")

    if template_name ~= HACK_TAG_NAME then
        return
    end

    local target_tag = smart_tag_system:unit_tag(target_unit)
    local tagger_player = target_tag and target_tag._tagger_player
    local tagger_player_unit = tagger_player and tagger_player.player_unit
    if tagger_player_unit then
        smart_tag_system:cancel_tag(target_tag._id, tagger_player_unit, true)
    end
    smart_tag_system:set_tag(HACK_TAG_NAME, player_unit, target_unit)
end

mod.hack_mark = function()
    if not context.mod_enabled or not context.game_mode_valid or context.class_name ~= "cryptic" or not context.has_servo_skull then
        return
    end

    local cb = callback(hack_mark_callback)
    Managers.state.game_mode:register_physics_safe_callback(cb)
end

function mod:can_servo_skull_shoot()
    local companion_spawner_extension = context.companion_spawner_extension
    local companion_unit = companion_spawner_extension and companion_spawner_extension:spawned_unit_lookup(special_rules.cryptic_servo_skull_hack)
    if not ALIVE[companion_unit] then
        return false
    end

    local game_session = Managers.state.game_session:game_session()
    local game_object_id = Managers.state.unit_spawner:game_object_id(companion_unit)
    local game_object_exists = GameSession.game_object_exists(game_session, game_object_id)

    if not game_object_exists then
        return false
    end

    local state = GameSession.game_object_field(game_session, game_object_id, "state")

    if state == servo_skull_states.hacking then
        return false
    end

    return true
end
