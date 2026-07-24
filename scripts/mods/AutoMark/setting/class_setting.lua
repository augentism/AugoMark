---@class AutoMarkMod:DMFMod
local mod                    = get_mod("AutoMark")
local auto_mark_settings     = mod.auto_mark_settings
local context                = mod.context
local DEFAULT_CLASS_SETTINGS = mod.DEFAULT_CLASS_SETTINGS
local TAG_NAMES              = mod.TAG_NAMES

-- Imports
local Archetypes             = require("scripts/settings/archetype/archetypes")
local Breed                  = require("scripts/utilities/breed")
local Breeds                 = require("scripts/settings/breed/breeds")

-- Global Cache
local table_clone            = table.clone

-- Constants
local BASE_CLASSES           = {}
for class_name, _ in pairs(Archetypes) do
    BASE_CLASSES[class_name] = true
end
-- Additional Class Name for Arbites and Veteran
local ADAMANT_COMPANION    = "adamant_companion"
local CRYPTIC_SERVO_SKULL  = "cryptic_servo_skull"
local VETERAN_FOCUS_TARGET = "veteran_focus_target"
-- Valid Class Names
local VALID_CLASSES        = {
    [ADAMANT_COMPANION] = true,
    [CRYPTIC_SERVO_SKULL] = true,
    [VETERAN_FOCUS_TARGET] = true,
}
for class_name, _ in pairs(Archetypes) do
    VALID_CLASSES[class_name] = true
end

-- Class settings now hold only behavioral options; breed priorities and the
-- close/far threshold live in shared presets, so every class shares defaults.
local function get_default_class_settings(class_name)
    return DEFAULT_CLASS_SETTINGS
end

local function init_table(dest, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(dest[key]) == "table" then
                dest[key] = init_table(dest[key], value)
            else
                dest[key] = table_clone(value)
            end
        else
            if dest[key] == nil or type(dest[key]) ~= type(value) then
                dest[key] = value
            end
        end
    end

    for key, _ in pairs(dest) do
        if source[key] == nil then
            dest[key] = nil
        end
    end

    return dest
end

-- Init Auto Mark Settings
function mod:init_auto_mark_settings()
    for class_name, _ in pairs(VALID_CLASSES) do
        if auto_mark_settings[class_name] == nil then
            auto_mark_settings[class_name] = {}
        end
        local class_settings = auto_mark_settings[class_name]
        init_table(class_settings, get_default_class_settings(class_name))
    end

    for class_name, _ in pairs(auto_mark_settings) do
        if not VALID_CLASSES[class_name] then
            auto_mark_settings[class_name] = nil
        end
    end

    mod:set("auto_mark_settings", auto_mark_settings, false)

    -- backfill: every valid class should point at a preset (fresh installs,
    -- or classes added since the presets were first created)
    local presets = mod.breed_priority_presets
    local assignments = mod.breed_priority_assignments
    local fallback_id = next(presets)
    if fallback_id then
        local changed = false
        for class_name, _ in pairs(VALID_CLASSES) do
            if not assignments[class_name] or not presets[assignments[class_name]] then
                assignments[class_name] = fallback_id
                changed = true
            end
        end
        if changed then
            mod:set("breed_priority_assignments", assignments, false)
        end
    end
end

-- ===== Breed priority presets =====

local breed_priority_presets     = mod.breed_priority_presets
local breed_priority_assignments = mod.breed_priority_assignments

local function persist_presets()
    mod:set("breed_priority_presets", breed_priority_presets, false)
end

local function persist_assignments()
    mod:set("breed_priority_assignments", breed_priority_assignments, false)
end

-- any existing preset id, for use as a fallback assignment
local function any_preset_id()
    return (next(breed_priority_presets))
end

function mod:get_presets()
    return breed_priority_presets
end

-- ordered list of { id, preset } for list display, sorted by name
function mod:get_ordered_presets()
    local order = {}
    for id, preset in pairs(breed_priority_presets) do
        order[#order + 1] = { id = id, preset = preset }
    end
    table.sort(order, function(a, b) return (a.preset.name or "") < (b.preset.name or "") end)
    return order
end

function mod:get_preset(preset_id)
    return preset_id and breed_priority_presets[preset_id]
end

-- number of class contexts assigned to a preset (for the list subtitle)
function mod:count_preset_assignments(preset_id)
    local count = 0
    for _, assigned_id in pairs(breed_priority_assignments) do
        if assigned_id == preset_id then
            count = count + 1
        end
    end
    return count
end

function mod:get_preset_for_class(class_name)
    local preset_id = breed_priority_assignments[class_name]
    return preset_id, preset_id and breed_priority_presets[preset_id]
end

function mod:assign_preset(class_name, preset_id)
    if not breed_priority_presets[preset_id] then
        return
    end
    breed_priority_assignments[class_name] = preset_id
    persist_assignments()
end

function mod:assign_preset_to_all(preset_id)
    if not breed_priority_presets[preset_id] then
        return
    end
    for _, class_name in ipairs(mod:get_priority_class_names()) do
        breed_priority_assignments[class_name] = preset_id
    end
    persist_assignments()
end

function mod:create_preset()
    -- next "Preset N" number not already taken
    local max_n = 0
    for _, preset in pairs(breed_priority_presets) do
        local n = tonumber(tostring(preset.name):match("Preset (%d+)"))
        if n and n > max_n then
            max_n = n
        end
    end
    local preset_id = mod.make_preset_id()
    breed_priority_presets[preset_id] = mod.build_default_preset("Preset " .. (max_n + 1))
    persist_presets()
    return preset_id
end

-- returns true if deleted; refuses to delete the final preset
function mod:delete_preset(preset_id)
    if not breed_priority_presets[preset_id] then
        return false
    end
    local remaining = 0
    for _ in pairs(breed_priority_presets) do
        remaining = remaining + 1
    end
    if remaining <= 1 then
        return false
    end

    breed_priority_presets[preset_id] = nil
    local fallback = any_preset_id()
    for class_name, assigned_id in pairs(breed_priority_assignments) do
        if assigned_id == preset_id then
            breed_priority_assignments[class_name] = fallback
        end
    end
    persist_presets()
    persist_assignments()
    return true
end

function mod:save_presets()
    persist_presets()
end

-- Resolve the assigned preset for a tag; falls back to any preset, then a
-- freshly built default, so scoring always has priorities to read.
function mod:get_assigned_preset(tag_name)
    local class_name
    if tag_name == TAG_NAMES.ENEMY_TAG then
        class_name = context.class_name
    elseif tag_name == TAG_NAMES.VETERAN_TAG then
        class_name = VETERAN_FOCUS_TARGET
    elseif tag_name == TAG_NAMES.COMPANION_TAG then
        class_name = ADAMANT_COMPANION
    elseif tag_name == TAG_NAMES.SERVO_SKULL_TAG then
        class_name = CRYPTIC_SERVO_SKULL
    end

    local preset_id = class_name and breed_priority_assignments[class_name]
    local preset = preset_id and breed_priority_presets[preset_id]
    if preset then
        return preset
    end

    local fallback_id = any_preset_id()
    if fallback_id then
        return breed_priority_presets[fallback_id]
    end

    return mod.build_default_preset("Preset 1")
end

-- Ordered class list for the breed priority view: special tag contexts first,
-- then base classes alphabetically
function mod:get_priority_class_names()
    local special = { ADAMANT_COMPANION, CRYPTIC_SERVO_SKULL, VETERAN_FOCUS_TARGET }
    local base = {}
    for class_name, _ in pairs(BASE_CLASSES) do
        base[#base + 1] = class_name
    end
    table.sort(base)
    local names = {}
    for _, class_name in ipairs(special) do
        names[#names + 1] = class_name
    end
    for _, class_name in ipairs(base) do
        names[#names + 1] = class_name
    end
    return names
end

function mod:get_class_settings_by_name(class_name)
    return auto_mark_settings[class_name]
end

-- Get Class Settings by Tag Name
function mod:get_class_settings(tag_name)
    if tag_name == TAG_NAMES.ENEMY_TAG then
        return auto_mark_settings[context.class_name]
    elseif tag_name == TAG_NAMES.VETERAN_TAG then
        return auto_mark_settings[VETERAN_FOCUS_TARGET]
    elseif tag_name == TAG_NAMES.COMPANION_TAG then
        return auto_mark_settings[ADAMANT_COMPANION]
    elseif tag_name == TAG_NAMES.SERVO_SKULL_TAG then
        return auto_mark_settings[CRYPTIC_SERVO_SKULL]
    end
end

-- Get Class Name
function mod:get_menu_class_name()
    if context.class_name == "adamant" and context.has_companion then
        return ADAMANT_COMPANION
    elseif context.class_name == "veteran" and context.has_focus_target then
        return VETERAN_FOCUS_TARGET
    elseif context.class_name == "cryptic" and context.has_servo_skull then
        return CRYPTIC_SERVO_SKULL
    else
        return context.class_name or "adamant"
    end
end
