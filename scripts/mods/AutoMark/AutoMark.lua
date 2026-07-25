---@class AutoMarkMod:DMFMod
local mod          = get_mod("AutoMark")
local breeds       = require("scripts/settings/breed/breeds")
local Breed        = require("scripts/utilities/breed")
-- Noospheric Command's shooting buff duration doubles as the re-mark cadence.
local NOOSPHERIC_COMMAND_DURATION = require("scripts/settings/talent/talent_settings").cryptic.servo_skull_shooting_tagging.duration

-- Global Cache
local CLASS        = CLASS
local table_clear  = table.clear

-- Smart Tag Names
local TAG_NAMES    = {
    ENEMY_TAG       = "enemy_over_here",
    VETERAN_TAG     = "enemy_over_here_veteran",
    COMPANION_TAG   = "enemy_companion_target",
    SERVO_SKULL_TAG = "servo_skull_enemy_companion_target",
}
mod.TAG_NAMES      = TAG_NAMES

-- Mod Settings
---@class AutoMarkModSettings
local mod_settings = {
    toggle_mod                               = mod:get("toggle_mod") or false,
    toggle_mod_keybind                       = mod:get("toggle_mod_keybind") or {},
    toggle_mod_notify                        = mod:get("toggle_mod_notify") or false,
    debug_mode                               = mod:get("debug_mode") or false,
    companion_mark_keybind                   = mod:get("companion_mark_keybind") or {},
    companion_mark_ignore_unaggroed          = mod:get("companion_mark_ignore_unaggroed") or false,
    execution_order_priority                 = mod:get("execution_order_priority") or false,
    companion_range_limitation               = mod:get("companion_range_limitation") or 0,
    companion_cancel_mark                    = mod:get("companion_cancel_mark") or false,
    companion_cancel_mark_human              = mod:get("companion_cancel_mark_human") or false,
    companion_cancel_mark_non_human          = mod:get("companion_cancel_mark_non_human") or false,
    companion_health_threshold               = mod:get("companion_health_threshold") or 0,
    companion_time_threshold                 = mod:get("companion_time_threshold") or 0,
    companion_distance_threshold             = mod:get("companion_distance_threshold") or 0,
    servo_skull_mark_keybind                 = mod:get("servo_skull_mark_keybind") or {},
    servo_skull_mark_ignore_unaggroed        = mod:get("servo_skull_mark_ignore_unaggroed") or false,
    servo_skull_burster_forbidden_range      = mod:get("servo_skull_burster_forbidden_range") or 0,
    servo_skull_mark_without_los             = mod:get("servo_skull_mark_without_los") or false,
    medicae_snap_speed                       = mod:get("medicae_snap_speed") or 900,
    medicae_return_camera                    = mod:get("medicae_return_camera") or false,
    servo_skull_cancel_mark_time_threshold   = mod:get("servo_skull_cancel_mark_time_threshold") or 0,
    hack_mark_keybind                        = mod:get("hack_mark_keybind") or {},
    auto_hack                                = mod:get("auto_hack") or false,
    disable_auto_hack_for_noospheric_command = mod:get("disable_auto_hack_for_noospheric_command") or false,
    capacitance_retention                    = mod:get("capacitance_retention") or false,
    capacitance_retention_elite_threshold    = mod:get("capacitance_retention_elite_threshold") or 0,
    capacitance_retention_special_threshold  = mod:get("capacitance_retention_special_threshold") or 0,
    capacitance_retention_boss_threshold     = mod:get("capacitance_retention_boss_threshold") or 0,
    noospheric_command_boost                 = mod:get("noospheric_command_boost") or false,
    noospheric_command_boost_elite           = mod:get("noospheric_command_boost_elite") or false,
    noospheric_command_boost_special         = mod:get("noospheric_command_boost_special") or false,
    noospheric_command_boost_boss            = mod:get("noospheric_command_boost_boss") or false,
    focus_target_overwrite                   = mod:get("focus_target_overwrite") or false,
    focus_target_overwrite_delta             = mod:get("focus_target_overwrite_delta") or 5,
    focus_target_ignore_unaggroed            = mod:get("focus_target_ignore_unaggroed") or false,
    focus_target_switch                      = mod:get("focus_target_switch") or false,
    focus_target_switch_melee                = mod:get("focus_target_switch_melee") or false,
    focus_target_switch_range                = mod:get("focus_target_switch_range") or false,
}
mod.settings       = mod_settings
if mod:get("capacitance_retention_elite_threshold_negative_zero") then
    mod_settings.capacitance_retention_elite_threshold = -0
    mod:set("capacitance_retention_elite_threshold", -0, false)
end
if mod:get("capacitance_retention_special_threshold_negative_zero") then
    mod_settings.capacitance_retention_special_threshold = -0
    mod:set("capacitance_retention_special_threshold", -0, false)
end
if mod:get("capacitance_retention_boss_threshold_negative_zero") then
    mod_settings.capacitance_retention_boss_threshold = -0
    mod:set("capacitance_retention_boss_threshold", -0, false)
end

local noospheric_command_breed_settings = mod:get("noospheric_command_breed_settings") or {}
mod.noospheric_command_breed_settings   = noospheric_command_breed_settings
for _, breed_settings in pairs(noospheric_command_breed_settings) do
    if breed_settings.threshold_negative_zero then
        breed_settings.threshold = -0
    end
end

do
    local breed_name = mod:get("noospheric_command_boost_breed_name")
    local breed_settings = noospheric_command_breed_settings[breed_name]
    mod:set("noospheric_command_boost_breed_override", breed_settings and breed_settings.override or false, false)
    mod:set("noospheric_command_boost_breed_toggle", breed_settings and breed_settings.toggle or false, false)
    mod:set("capacitance_retention_breed_threshold", breed_settings and breed_settings.threshold or 0, false)
end

local companion_cancel_mark_breed_settings = mod:get("companion_cancel_mark_breed_settings") or {}
mod.companion_cancel_mark_breed_settings = companion_cancel_mark_breed_settings

-- Default Class Settings (behavioral only; breed priorities and the close/far
-- distance threshold live in shared presets, see breed_priority_presets)
local DEFAULT_CLASS_SETTINGS = {
    toggle_class    = true,
    cooldown        = 25,
    reset_cooldown  = true,
    mark_limit      = true,
    min_range       = 0,
    max_range       = 100,
    override_manual = false,
    priority_switch = false,
    toggle_elite    = true,
    toggle_special  = true,
    toggle_boss     = true,
    toggle_other    = true,
}
mod.DEFAULT_CLASS_SETTINGS               = DEFAULT_CLASS_SETTINGS

-- Default preset content: every taggable breed at priority 12, close and far
-- entries are { close = 0-20, far = 0-20 }, selected by comparing target
-- distance against the preset's distance_threshold.
local DEFAULT_BREED_PRIORITY             = 12
local DEFAULT_PRESET_THRESHOLD           = 15
local DEFAULT_PRESET_PRIORITIES          = {}
for breed_name, breed_data in pairs(breeds) do
    if Breed.is_minion(breed_data) and breed_data.smart_tag_target_type == "breed" then
        if breed_data.tags.elite or breed_data.tags.special or breed_data.is_boss or breed_data.faction_name ~= "imperium" then
            DEFAULT_PRESET_PRIORITIES[breed_name] = { close = DEFAULT_BREED_PRIORITY, far = DEFAULT_BREED_PRIORITY }
            if breed_data.tags.witch then
                DEFAULT_PRESET_PRIORITIES[breed_name .. "_passive"] = { close = DEFAULT_BREED_PRIORITY, far = DEFAULT_BREED_PRIORITY }
            end
        end
    end
end
-- Mutator ritualists channeling a daemonhost ritual at half/full speed have
-- their own priority entries (detected at scan time from synced game state)
if DEFAULT_PRESET_PRIORITIES["chaos_mutator_ritualist"] then
    DEFAULT_PRESET_PRIORITIES["chaos_mutator_ritualist_half"] = { close = DEFAULT_BREED_PRIORITY, far = DEFAULT_BREED_PRIORITY }
    DEFAULT_PRESET_PRIORITIES["chaos_mutator_ritualist_full"] = { close = DEFAULT_BREED_PRIORITY, far = DEFAULT_BREED_PRIORITY }
end
mod.DEFAULT_PRESET_PRIORITIES            = DEFAULT_PRESET_PRIORITIES
mod.DEFAULT_PRESET_THRESHOLD             = DEFAULT_PRESET_THRESHOLD

-- Context
---@class AutoMarkContext
local context                            = {
    mod_enabled                 = false,
    game_mode_valid             = false,
    player                      = nil,
    class_name                  = nil,
    talent_resource_component   = nil,
    has_companion               = false,
    has_execution_order         = false,
    has_focus_target            = false,
    focus_target_max_stacks     = 0,
    has_servo_skull             = false,
    has_noospheric_command      = false,
    smart_targeting_extension   = nil,
    companion_spawner_extension = nil,
    player_ability_extension    = nil,
    smart_tag_system            = nil,
    outline_system              = nil,
    smoke_fog_system            = nil,
    hud_element_smart_tagging   = nil,
    companion_command_tap       = "double"
}
mod.context                              = context

-- Auto Mark Settings
local auto_mark_settings                 = mod:get("auto_mark_settings") or {}
mod.auto_mark_settings                   = auto_mark_settings
-- Migrate legacy flat 0-5 priorities to { close, far } on the 0-20 scale.
-- Must happen before init_auto_mark_settings, whose type check against the
-- new table-shaped defaults would otherwise reset legacy numeric values.
for _, class_settings in pairs(auto_mark_settings) do
    local breed_priorities = type(class_settings) == "table" and class_settings.breed_priorities
    if type(breed_priorities) == "table" then
        for breed_name, priority in pairs(breed_priorities) do
            if type(priority) == "number" then
                local value = math.clamp(priority * 4, 0, 20)
                breed_priorities[breed_name] = { close = value, far = value }
            end
        end
    end
end

-- Breed Priority Presets
-- Presets hold { name, distance_threshold, breed_priorities }; assignments
-- map class keys to preset ids. Class settings keep only behavioral options.
local breed_priority_presets     = mod:get("breed_priority_presets") or nil
local breed_priority_assignments = mod:get("breed_priority_assignments") or {}

local function make_preset_id()
    return string.format("preset_%d_%d", math.random(100000, 999999), math.random(100000, 999999))
end

local function build_default_preset(name)
    local breed_priorities = {}
    for breed_name, entry in pairs(DEFAULT_PRESET_PRIORITIES) do
        breed_priorities[breed_name] = { close = entry.close, far = entry.far }
    end
    return {
        name               = name,
        distance_threshold = DEFAULT_PRESET_THRESHOLD,
        breed_priorities   = breed_priorities,
    }
end

mod.make_preset_id       = make_preset_id
mod.build_default_preset = build_default_preset

-- One-time migration: fold the per-class priority tables into deduplicated
-- presets. Must read auto_mark_settings before init_auto_mark_settings prunes
-- the now-removed breed_priorities/distance_threshold keys.
if breed_priority_presets == nil then
    breed_priority_presets = {}

    local function canonical_key(distance_threshold, breed_priorities)
        local parts = {}
        for breed_name, entry in pairs(breed_priorities) do
            if type(entry) == "table" then
                parts[#parts + 1] = string.format("%s:%d:%d", breed_name, entry.close or 0, entry.far or 0)
            end
        end
        table.sort(parts)
        return tostring(distance_threshold or DEFAULT_PRESET_THRESHOLD) .. "|" .. table.concat(parts, ";")
    end

    local preset_id_by_key = {}
    local num_presets = 0
    for class_name, class_settings in pairs(auto_mark_settings) do
        if type(class_settings) == "table" and type(class_settings.breed_priorities) == "table" then
            local key = canonical_key(class_settings.distance_threshold, class_settings.breed_priorities)
            local preset_id = preset_id_by_key[key]
            if not preset_id then
                num_presets = num_presets + 1
                preset_id = make_preset_id() .. "_" .. num_presets
                local breed_priorities = {}
                for breed_name, entry in pairs(class_settings.breed_priorities) do
                    if type(entry) == "table" then
                        breed_priorities[breed_name] = { close = entry.close or 0, far = entry.far or 0 }
                    end
                end
                breed_priority_presets[preset_id] = {
                    name               = "Preset " .. num_presets,
                    distance_threshold = class_settings.distance_threshold or DEFAULT_PRESET_THRESHOLD,
                    breed_priorities   = breed_priorities,
                }
                preset_id_by_key[key] = preset_id
            end
            breed_priority_assignments[class_name] = preset_id
        end
    end
end

-- always keep at least one preset
if next(breed_priority_presets) == nil then
    breed_priority_presets[make_preset_id()] = build_default_preset("Preset 1")
end

-- drop assignments pointing at deleted/unknown presets
for class_name, preset_id in pairs(breed_priority_assignments) do
    if not breed_priority_presets[preset_id] then
        breed_priority_assignments[class_name] = nil
    end
end

mod.breed_priority_presets     = breed_priority_presets
mod.breed_priority_assignments = breed_priority_assignments
mod:set("breed_priority_presets", breed_priority_presets, false)
mod:set("breed_priority_assignments", breed_priority_assignments, false)

-- Mark States
---@class AutoMarkMarkContext
local mark_context                       = {
    auto_mark_interval          = 0,
    execution_order_units       = setmetatable({}, { __mode = "k" }),
    [TAG_NAMES.ENEMY_TAG]       = setmetatable(
        {
            tag         = nil,
            cooldown    = 0,
            delay       = 0,
            manual_unit = nil,
            is_manual   = false,
        },
        { __mode = "v" }
    ),
    [TAG_NAMES.VETERAN_TAG]     = setmetatable(
        {
            tag         = nil,
            cooldown    = 0,
            delay       = 0,
            manual_unit = nil,
            is_manual   = false,
        },
        { __mode = "v" }
    ),
    [TAG_NAMES.COMPANION_TAG]   = setmetatable(
        {
            tag               = nil,
            cooldown          = 0,
            delay             = 0,
            manual_unit       = nil,
            is_manual         = false,
            pounce_start_time = nil,
            is_cancelable     = false,
            canceled_unit     = nil,
        },
        { __mode = "v" }
    ),
    [TAG_NAMES.SERVO_SKULL_TAG] = setmetatable(
        {
            tag                          = nil,
            cooldown                     = 0,
            delay                        = 0,
            manual_unit                  = nil,
            is_manual                    = false,
            noospheric_command_next_time = math.huge,
            servo_skull_lose_sight_time  = nil,
        },
        { __mode = "v" }
    ),
}
mod.mark_context                         = mark_context

-- Enemy Visbility Check
local visibility_cache                   = setmetatable({}, { __mode = "k" })
local visibility_check_frame             = setmetatable({}, { __mode = "k" })
mod.visibility_cache                     = visibility_cache
mod.visibility_check_frame               = visibility_check_frame
local servo_skull_visibility_cache       = setmetatable({}, { __mode = "k" })
local servo_skull_visibility_check_frame = setmetatable({}, { __mode = "k" })
mod.servo_skull_visibility_cache         = servo_skull_visibility_cache
mod.servo_skull_visibility_check_frame   = servo_skull_visibility_check_frame

-- Reset all params
local function reset_context()
    -- Reset Mark Params
    mark_context.auto_mark_interval = 0
    table_clear(mark_context.execution_order_units)
    table_clear(visibility_cache)
    table_clear(visibility_check_frame)
    table_clear(servo_skull_visibility_cache)
    table_clear(servo_skull_visibility_check_frame)
    for _, tag_name in pairs(TAG_NAMES) do
        local tag_context = mark_context[tag_name]
        tag_context.tag = nil
        tag_context.cooldown = 0
        tag_context.delay = 0
        tag_context.manual_unit = nil
        tag_context.is_manual = false
    end
    local companion_tag_context = mark_context[TAG_NAMES.COMPANION_TAG]
    companion_tag_context.pounce_start_time = nil
    companion_tag_context.is_cancelable = false
    companion_tag_context.canceled_unit = nil
    local servo_skull_tag_context = mark_context[TAG_NAMES.SERVO_SKULL_TAG]
    servo_skull_tag_context.noospheric_command_next_time = math.huge
    servo_skull_tag_context.servo_skull_lose_sight_time = nil
end

local function destroy_references()
    context.player                      = nil
    context.talent_resource_component   = nil
    context.smart_targeting_extension   = nil
    context.companion_spawner_extension = nil
    context.player_ability_extension    = nil
    context.smart_tag_system            = nil
    context.outline_system              = nil
    context.smoke_fog_system            = nil
    context.hud_element_smart_tagging   = nil
    mod:destroy_visibility_raycast_objects()
end

-- Load Other Files
mod:io_dofile("AutoMark/scripts/mods/AutoMark/utils/utils")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/context/context")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/setting/class_setting")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/setting/option_setting")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/targeting/targeting")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/targeting/custom_targeting")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/mark/base_mark")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/mark/companion_mark")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/mark/focus_target_mark")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/mark/servo_skull_mark")
mod:io_dofile("AutoMark/scripts/mods/AutoMark/mark/medicae_assist")

-- Custom Views (preset editor + preset-to-class assignment)
local function register_automark_view(base, view_name, class_name, display_name)
    mod:add_require_path(base)
    mod:add_require_path(base .. "_definitions")
    mod:add_require_path(base .. "_blueprints")
    mod:add_require_path(base .. "_settings")

    mod:register_view({
        view_name = view_name,
        view_settings = {
            init_view_function = function(_) return true end,
            class               = class_name,
            disable_game_world  = false,
            display_name        = display_name,
            game_world_blur     = 1.1,
            load_always         = true,
            load_in_hub         = true,
            package             = "packages/ui/views/options_view/options_view",
            path                = base,
            state_bound         = true,
            enter_sound_events  = { "wwise/events/ui/play_ui_enter_short" },
            exit_sound_events   = { "wwise/events/ui/play_ui_back_short" },
            wwise_states        = { options = "ingame_menu" },
        },
        view_transitions = {},
        view_options = {
            close_all             = true,
            close_previous        = true,
            close_transition_time = nil,
            transition_time       = nil,
        },
    })
    mod:io_dofile(base)
end

register_automark_view(
    "AutoMark/scripts/mods/AutoMark/view/breed_priority_view",
    "automark_breed_priority_view", "BreedPriorityView", "Auto Mark Breed Priorities"
)
register_automark_view(
    "AutoMark/scripts/mods/AutoMark/view/assignment_view",
    "automark_assignment_view", "AssignmentView", "Auto Mark Preset Assignment"
)

--  Mod Enabled
mod.on_enabled            = function(initial_call)
    context.mod_enabled = true
    mod:check_game_mode()
    mod:init_auto_mark_settings()
    -- init cache after mod enabled since all hooks were disabled
    mod:init_context()
    mod:init_execution_order_units()
    mod:init_visibility_raycast_objects()
end

--  Mod Disabled
mod.on_disabled           = function(initial_call)
    context.mod_enabled = false
    -- mark info rest
    reset_context()
    destroy_references()
end

-- Enter/Exit GameplayStateRun
mod.on_game_state_changed = function(status, state_name)
    if state_name == "GameplayStateRun" then
        if status == "enter" then
            mod:check_game_mode()
            -- game settings cache
            mod:init_game_settings()
        elseif status == "exit" then
            context.game_mode_valid = false
            -- menu mark info rest
            reset_context()
        end
    end
end

-- Mod Setting Change
mod.on_setting_changed    = function(setting_id)
    local result = mod:get(setting_id)
    -- Normal Mod Settings
    if mod_settings[setting_id] ~= nil then
        mod_settings[setting_id] = result
        if setting_id == "capacitance_retention_elite_threshold" or setting_id == "capacitance_retention_special_threshold" or setting_id == "capacitance_retention_boss_threshold" then
            if result == -0 and 1 / result < 0 then
                mod:set(setting_id .. "_negative_zero", true, false)
            else
                mod:set(setting_id .. "_negative_zero", false, false)
            end
        end
        -- Reset Noospheric Command Breed Settings
    elseif setting_id == "noospheric_command_boost_reset" then
        if result == "reset" then
            table_clear(noospheric_command_breed_settings)
            mod:set("noospheric_command_breed_settings", noospheric_command_breed_settings, false)
            mod:set("noospheric_command_boost_breed_name", mod:get("noospheric_command_boost_breed_name"), true)
        end
        mod:set("noospheric_command_boost_reset", "blank", false)
        -- Select Noospheric Command Breed Name
    elseif setting_id == "noospheric_command_boost_breed_name" then
        local breed_settings = noospheric_command_breed_settings[result]
        mod:set("noospheric_command_boost_breed_override", breed_settings and breed_settings.override or false, false)
        mod:set("noospheric_command_boost_breed_toggle", breed_settings and breed_settings.toggle or false, false)
        mod:set("capacitance_retention_breed_threshold", breed_settings and breed_settings.threshold or 0, false)
        -- Set Noospheric Command Breed Settings
    elseif setting_id == "noospheric_command_boost_breed_override" or setting_id == "noospheric_command_boost_breed_toggle" or setting_id == "capacitance_retention_breed_threshold" then
        local breed_name = mod:get("noospheric_command_boost_breed_name")
        if noospheric_command_breed_settings[breed_name] == nil then
            noospheric_command_breed_settings[breed_name] = { override = false, toggle = false, threshold = 0, threshold_negative_zero = false }
        end
        if setting_id == "noospheric_command_boost_breed_override" then
            noospheric_command_breed_settings[breed_name].override = result
        elseif setting_id == "noospheric_command_boost_breed_toggle" then
            noospheric_command_breed_settings[breed_name].toggle = result
        elseif setting_id == "capacitance_retention_breed_threshold" then
            noospheric_command_breed_settings[breed_name].threshold = result
            if result == -0 and 1 / result < 0 then
                noospheric_command_breed_settings[breed_name].threshold_negative_zero = true
            else
                noospheric_command_breed_settings[breed_name].threshold_negative_zero = false
            end
        end
        mod:set("noospheric_command_breed_settings", noospheric_command_breed_settings, false)
        -- Reset Companion Cancel Mark Breed Settings
    elseif setting_id == "companion_cancel_mark_reset" then
        if result == "reset" then
            table_clear(companion_cancel_mark_breed_settings)
            mod:set("companion_cancel_mark_breed_settings", companion_cancel_mark_breed_settings, false)
            mod:set("companion_cancel_mark_breed_name", mod:get("companion_cancel_mark_breed_name"), true)
        end
        mod:set("companion_cancel_mark_reset", "blank", false)
        -- Select Companion Cancel Mark Breed Name
    elseif setting_id == "companion_cancel_mark_breed_name" then
        local breed_settings = companion_cancel_mark_breed_settings[result]
        mod:set("companion_cancel_mark_breed_override", breed_settings and breed_settings.override or false, false)
        mod:set("companion_cancel_mark_breed_health_threshold", breed_settings and breed_settings.health_threshold or 0, false)
        mod:set("companion_cancel_mark_breed_time_threshold", breed_settings and breed_settings.time_threshold or 0, false)
        mod:set("companion_cancel_mark_breed_distance_threshold", breed_settings and breed_settings.distance_threshold or 0, false)
        -- Set Companion Cancel Mark Breed Settings
    elseif setting_id == "companion_cancel_mark_breed_override" or setting_id == "companion_cancel_mark_breed_health_threshold" or setting_id == "companion_cancel_mark_breed_time_threshold" or setting_id == "companion_cancel_mark_breed_distance_threshold" then
        local breed_name = mod:get("companion_cancel_mark_breed_name")
        if companion_cancel_mark_breed_settings[breed_name] == nil then
            companion_cancel_mark_breed_settings[breed_name] = { override = false, health_threshold = 0, time_threshold = 0, distance_threshold = 0 }
        end
        if setting_id == "companion_cancel_mark_breed_override" then
            companion_cancel_mark_breed_settings[breed_name].override = result
        elseif setting_id == "companion_cancel_mark_breed_health_threshold" then
            companion_cancel_mark_breed_settings[breed_name].health_threshold = result
        elseif setting_id == "companion_cancel_mark_breed_time_threshold" then
            companion_cancel_mark_breed_settings[breed_name].time_threshold = result
        elseif setting_id == "companion_cancel_mark_breed_distance_threshold" then
            companion_cancel_mark_breed_settings[breed_name].distance_threshold = result
        end
        mod:set("companion_cancel_mark_breed_settings", companion_cancel_mark_breed_settings, false)
    end
end

-- Toggle Mod Enabled/Disabled
mod.toggle_mod            = function()
    if mod_settings.toggle_mod_notify then
        mod:notify("Auto Mark " .. (not mod_settings.toggle_mod and "Enabled" or "Disabled"))
    end
    mod:set("toggle_mod", not mod_settings.toggle_mod, true)
end

-- Check if Tag is Valid for Current Class
local function is_tag_valid(tag_name)
    if tag_name == TAG_NAMES.COMPANION_TAG then
        return context.class_name == "adamant" and context.has_companion
    elseif tag_name == TAG_NAMES.VETERAN_TAG then
        return context.class_name == "veteran" and context.has_focus_target
    elseif tag_name == TAG_NAMES.ENEMY_TAG then
        return context.class_name ~= "veteran" or not context.has_focus_target
    elseif tag_name == TAG_NAMES.SERVO_SKULL_TAG then
        return context.class_name == "cryptic" and context.has_servo_skull and not mod:is_servo_skull_hacking()
    end
    return false
end

-- Auto-Mark Target Unit with the Tag
local function auto_mark_by_tag(tag_name, t, fixed_frame)
    if not is_tag_valid(tag_name) then
        if mod_settings.debug_mode and tag_name == TAG_NAMES.SERVO_SKULL_TAG
            and context.class_name == "cryptic" and context.has_servo_skull then
            mod:print_debug("servo skull tag unavailable (skull hacking) - will fall back to a plain mark")
        end
        return false
    end

    local tag_context = mark_context[tag_name]
    local class_settings = mod:get_class_settings(tag_name)
    local marked_tag = tag_context.tag
    local marked_tag_is_manual = tag_context.is_manual
    -- mark when cooldown is zero
    local is_cooldown_ready = tag_context.cooldown <= 0 and (not class_settings.mark_limit or not marked_tag)
    -- mark when priority switch is on
    local is_priority_switch = class_settings.priority_switch and marked_tag
    -- mark when execution order priority is on
    local is_execution_order_priority = mod_settings.execution_order_priority and tag_name == TAG_NAMES.COMPANION_TAG and context.has_execution_order

    local target_unit, target_tag, target_breed_name, target_priority, target_band, target_no_los
    if class_settings.toggle_class and (class_settings.override_manual or not marked_tag_is_manual) then
        if is_cooldown_ready then
            target_unit, target_tag, target_breed_name, target_priority, target_band, target_no_los = mod:find_target_unit_custom("auto", class_settings.min_range, class_settings.max_range, tag_name, tag_context, class_settings, true, is_execution_order_priority, nil)
        elseif is_priority_switch or is_execution_order_priority and marked_tag then
            target_unit, target_tag, target_breed_name, target_priority, target_band, target_no_los = mod:find_target_unit_custom("auto", class_settings.min_range, class_settings.max_range, tag_name, tag_context, class_settings, true, is_execution_order_priority, marked_tag)
        end
    end
    -- mark when focus target overwrite is on
    if not target_unit and mod_settings.focus_target_overwrite and tag_name == TAG_NAMES.VETERAN_TAG and marked_tag then
        local marked_unit = marked_tag._target_unit
        if mod:is_target_valid(tag_name, marked_tag, marked_unit) then
            mod:print_debug("Focus target overwrite")
            target_unit = marked_unit
            if marked_tag_is_manual then
                mod:on_manual_mark(tag_context, target_unit)
            end
        end
    end

    if not target_unit and mod_settings.noospheric_command_boost and context.has_noospheric_command and tag_name == TAG_NAMES.SERVO_SKULL_TAG and marked_tag and t >= tag_context.noospheric_command_next_time then
        local marked_unit = marked_tag._target_unit
        local breed_ok = mod:is_noospheric_command_boost_breed_valid(marked_unit)
        local valid_ok = breed_ok and mod:is_target_valid(tag_name, nil, marked_unit)
        local visible_ok = valid_ok and mod:is_servo_skull_target_visible(marked_unit, fixed_frame)
        if visible_ok then
            mod:print_debug("Noospheric command boost")
            target_unit = marked_unit
            if marked_tag_is_manual then
                mod:on_manual_mark(tag_context, target_unit)
            end
        elseif mod_settings.debug_mode and t - (tag_context.noospheric_debug_time or 0) > 1 then
            tag_context.noospheric_debug_time = t
            mod:print_debug("noospheric boost blocked: breed", breed_ok, "valid", valid_ok, "visible", visible_ok)
        end
    end

    if not target_unit then
        return false
    end

    -- A mark on a target the skull cannot see still pings the team and still
    -- grants the noospheric fire-rate buff (the skull shoots whatever it can
    -- reach meanwhile), so re-issue it exactly on the buff's own cadence
    -- instead of every tick. Targeting is still evaluated every tick, so the
    -- normal path takes over the instant the skull gains sight.
    if target_no_los then
        local next_time = tag_context.no_los_next_time
        if next_time and t < next_time and target_unit == tag_context.no_los_unit then
            return false
        end
        tag_context.no_los_unit = target_unit
        tag_context.no_los_next_time = t + NOOSPHERIC_COMMAND_DURATION
    else
        tag_context.no_los_unit = nil
        tag_context.no_los_next_time = nil
    end

    if mod_settings.debug_mode then
        local action = tag_name == TAG_NAMES.SERVO_SKULL_TAG and "Auto Attack" or "Auto Mark"
        mod:print_debug(action, tag_name, tostring(target_unit), "breed:", target_breed_name or "?",
            "prio:", target_priority or "?", "band:", target_band or "-",
            target_no_los and "(no LOS - ping only until skull can see it)" or "")
    end
    mod:mark(tag_name, target_unit, target_tag)
    -- set after mod:mark: the SmartTag init hook rebuilds the tag context
    tag_context.is_no_los = not not target_no_los
    return true
end

-- Auto-Mark
local function auto_mark(dt, t, fixed_frame)
    -- calculate interval
    if mark_context.auto_mark_interval > 0 then
        mark_context.auto_mark_interval = mark_context.auto_mark_interval - dt
    end
    -- calculate cooldown and delay for all tags
    for _, tag_name in pairs(TAG_NAMES) do
        local tag_context = mark_context[tag_name]
        if tag_context.delay > 0 then
            tag_context.delay = tag_context.delay - dt
        end
        if tag_context.cooldown > 0 then
            tag_context.cooldown = tag_context.cooldown - dt
        end
    end
    -- skip if auto mark is disabled
    if not mod_settings.toggle_mod then
        return
    end
    -- pause auto mark for a period of time after it is executed.
    if mark_context.auto_mark_interval > 0 then
        return
    end
    for _, tag_name in pairs(TAG_NAMES) do
        local tag_context = mark_context[tag_name]
        if tag_context.delay > 0 then
            return
        end
    end

    -- three kinds of tag to mark
    if auto_mark_by_tag(TAG_NAMES.COMPANION_TAG, t, fixed_frame) then
        return
    end

    if auto_mark_by_tag(TAG_NAMES.SERVO_SKULL_TAG, t, fixed_frame) then
        return
    end

    if auto_mark_by_tag(TAG_NAMES.VETERAN_TAG, t, fixed_frame) then
        return
    end

    if auto_mark_by_tag(TAG_NAMES.ENEMY_TAG, t, fixed_frame) then
        return
    end
end

local function clean_visibility_cache(fixed_frame)
    -- caches are weak-keyed, so this sweep is just a slow backstop
    if fixed_frame % 3120 == 0 then
        local frame_threshold = fixed_frame - 5
        for cached_unit, check_frame in pairs(visibility_check_frame) do
            if check_frame < frame_threshold then
                visibility_cache[cached_unit] = nil
                visibility_check_frame[cached_unit] = nil
            end
        end
        for cached_unit, check_frame in pairs(servo_skull_visibility_check_frame) do
            if check_frame < frame_threshold then
                servo_skull_visibility_cache[cached_unit] = nil
                servo_skull_visibility_check_frame[cached_unit] = nil
            end
        end
    end
end

-- Main Entry For Auto Mark
mod:hook_safe(CLASS.PlayerUnitSmartTargetingExtension, "fixed_update",
    function(self, unit, dt, t, fixed_frame)
        if self._player.viewport_name ~= "player1" then
            return
        end

        if context.game_mode_valid then
            clean_visibility_cache(fixed_frame)
            if mod_settings.debug_mode then
                mod:update_burster_watch()
            end
            mod:auto_cancel_companion_mark(t)
            mod:auto_cancel_servo_skull_mark(t, fixed_frame)
            mod:auto_hack(dt, t, fixed_frame)
            auto_mark(dt, t, fixed_frame)
        end
    end)
