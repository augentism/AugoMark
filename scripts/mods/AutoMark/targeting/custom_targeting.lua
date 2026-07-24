---@class AutoMarkMod:DMFMod
local mod                                              = get_mod("AutoMark")
local context                                          = mod.context
local mark_context                                     = mod.mark_context
local TAG_NAMES                                        = mod.TAG_NAMES
local mod_settings                                     = mod.settings
local noospheric_command_breed_settings                = mod.noospheric_command_breed_settings
local visibility_cache                                 = mod.visibility_cache
local visibility_check_frame                           = mod.visibility_check_frame
local servo_skull_visibility_cache                     = mod.servo_skull_visibility_cache
local servo_skull_visibility_check_frame               = mod.servo_skull_visibility_check_frame

-- Imports
local Breed                                            = require("scripts/utilities/breed")
local BreedActions                                     = require("scripts/settings/breed/breed_actions")
local MainPathQueries                                  = require("scripts/utilities/main_path_queries")
local SpecialRulesSettings                             = require("scripts/settings/ability/special_rules_settings")
local Breed_height                                     = Breed.height
local special_rules                                    = SpecialRulesSettings.special_rules

-- Global Cache
local CLASS                                            = CLASS
local HEALTH_ALIVE                                     = HEALTH_ALIVE
local ALIVE                                            = ALIVE
local Managers                                         = Managers
local GameSession                                      = GameSession
local PhysicsWorld                                     = PhysicsWorld
local Actor_unit                                       = Actor.unit
local Actor_world_bounds                               = Actor.world_bounds
local Unit_box                                         = Unit.box
local Unit_node                                        = Unit.node
local Unit_world_position                              = Unit.world_position
local PhysicsWorld_raycast                             = PhysicsWorld.raycast
local Raycast_cast                                     = Raycast.cast
local ScriptUnit_extension                             = ScriptUnit.extension
local math_abs                                         = math.abs
local math_max                                         = math.max
local Vector3_dot                                      = Vector3.dot
local Vector3_normalize                                = Vector3.normalize
local Vector3_length                                   = Vector3.length

local Vector3_distance                                 = Vector3.distance
local Vector3_distance_squared                         = Vector3.distance_squared
local Matrix4x4_right                                  = Matrix4x4.right
local Matrix4x4_forward                                = Matrix4x4.forward

-- Constants
local INDEX_POSITION                                   = 1
local INDEX_DISTANCE                                   = 2
local INDEX_NORMAL                                     = 3
local INDEX_ACTOR                                      = 4
local COLLISION_FILTER                                 = "filter_player_ping_target_selection"
local EMPTY_TABLE                                      = {}

local DARKNESS_LOS_MODIFIER_NAME                       = "mutator_darkness_los"
local VENTILATION_PURGE_LOS_MODIFIER_NAME              = "mutator_ventilation_purge_los"
local CIRCUMSTANCE_DETECTION_DISTANCE_LOS_REQUIREMENTS = {
    mutator_darkness_los = 15,
    mutator_ventilation_purge_los = 30,
}

local BUFF_KEYWORD_DISTANCE_LOS_REQUIREMENT            = {
    concealed = 5,
}

-- Params
local visibility_raycast_object                        = nil
local servo_skull_visibility_raycast_object            = nil

function mod:init_visibility_raycast_objects()
    local smart_targeting_extension = context.smart_targeting_extension
    local physics_world = smart_targeting_extension and smart_targeting_extension._physics_world
    if physics_world then
        visibility_raycast_object = PhysicsWorld.make_raycast(physics_world, "closest", "types", "both", "collision_filter", "filter_interactable_line_of_sight_marker_check")
        servo_skull_visibility_raycast_object = PhysicsWorld.make_raycast(physics_world, "closest", "types", "both", "collision_filter", "filter_minion_line_of_sight_check")
    end
end

function mod:destroy_visibility_raycast_objects()
    visibility_raycast_object = nil
    servo_skull_visibility_raycast_object = nil
end

local function is_target_aggroed(target_unit)
    local game_session = Managers.state.game_session:game_session()
    local game_object_id = Managers.state.unit_spawner:game_object_id(target_unit)
    local target_unit_id = GameSession.game_object_field(game_session, game_object_id, "target_unit_id")
    return target_unit_id ~= -1
end

-- Mutator ritualists channel a ritual that wakes a mutator daemonhost. The
-- ritual's half/full speed is server-side only, so reconstruct it the way the
-- server decides it (bt_chaos_mutator_daemonhost_passive_action): full when
-- the daemonhost took damage or the party's ahead unit passed
-- close_distance_offset along the main path, half past far_distance_offset.
local RITUALIST_BREED_NAME = "chaos_mutator_ritualist"
local ritual_passive_action = BreedActions.chaos_mutator_daemonhost and BreedActions.chaos_mutator_daemonhost.passive
local RITUAL_CLOSE_OFFSET  = ritual_passive_action and ritual_passive_action.close_distance_offset or 15
local RITUAL_FAR_OFFSET    = ritual_passive_action and ritual_passive_action.far_distance_offset or 30

local function _ritual_speed(daemonhost_unit)
    local health_extension = ScriptUnit.has_extension(daemonhost_unit, "health_system")
    if health_extension and health_extension:damage_taken() > 0 then
        return "full"
    end

    local _, ahead_travel_distance = Managers.state.main_path:ahead_unit(1)
    if not ahead_travel_distance then
        return nil
    end

    local position = POSITION_LOOKUP[daemonhost_unit] or Unit_world_position(daemonhost_unit, 1)
    local _, monster_travel_distance = MainPathQueries.closest_position(position)
    if not monster_travel_distance then
        return nil
    end

    local close_position = MainPathQueries.position_from_distance(monster_travel_distance - RITUAL_CLOSE_OFFSET)
    local _, close_distance = MainPathQueries.closest_position(close_position)
    if close_distance and close_distance < ahead_travel_distance then
        return "full"
    end

    local far_position = MainPathQueries.position_from_distance(monster_travel_distance - RITUAL_FAR_OFFSET)
    local _, far_distance = MainPathQueries.closest_position(far_position)
    if far_distance and far_distance < ahead_travel_distance then
        return "half"
    end

    return nil
end

local function _ritualist_priority_name(target_unit)
    local game_session = Managers.state.game_session:game_session()
    local game_object_id = Managers.state.unit_spawner:game_object_id(target_unit)
    if not game_object_id then
        return RITUALIST_BREED_NAME
    end

    -- -1 = not chanting (staggered/idle)
    local variation_id = GameSession.game_object_field(game_session, game_object_id, "effect_template_variation_id")
    if not variation_id or variation_id == -1 then
        return RITUALIST_BREED_NAME
    end

    -- the daemonhost this ritualist is channeling into (game object id)
    local daemonhost_id = GameSession.game_object_field(game_session, game_object_id, "level_unit_id")
    if not daemonhost_id or daemonhost_id == NetworkConstants.invalid_level_unit_id then
        return RITUALIST_BREED_NAME
    end

    local daemonhost_unit = Managers.state.unit_spawner:unit(daemonhost_id, false)
    if not daemonhost_unit or not HEALTH_ALIVE[daemonhost_unit] then
        return RITUALIST_BREED_NAME
    end

    local speed = _ritual_speed(daemonhost_unit)
    if speed then
        return RITUALIST_BREED_NAME .. "_" .. speed
    end

    return RITUALIST_BREED_NAME
end

local function get_breed_priority(target_unit, breed_data, breed_priorities, distance, distance_threshold)
    local breed_name = breed_data and breed_data.name
    local entry
    if breed_name == RITUALIST_BREED_NAME then
        local ok, priority_name = pcall(_ritualist_priority_name, target_unit)
        entry = ok and breed_priorities[priority_name] or nil
        entry = entry or breed_priorities[breed_name]
    elseif breed_data.tags.witch then
        if is_target_aggroed(target_unit) then
            entry = breed_priorities[breed_name]
        else
            entry = breed_priorities[breed_name .. "_passive"]
        end
    else
        entry = breed_priorities[breed_name]
    end

    if type(entry) ~= "table" then
        return entry
    end

    if distance and distance_threshold and distance <= distance_threshold then
        return entry.close
    end

    return entry.far
end

local BURSTER_BREEDS = { chaos_poxwalker_bomber = true }

-- servo skull only: never mark a burster close enough to hurt someone when popped
local function is_burster_forbidden(target_position)
    local radius = mod_settings.servo_skull_burster_forbidden_range
    if not radius or radius <= 0 or not target_position then
        return false
    end

    local radius_squared = radius * radius
    for _, player in pairs(Managers.player:players()) do
        local player_unit = player.player_unit
        if player_unit and HEALTH_ALIVE[player_unit] then
            local player_position = POSITION_LOOKUP[player_unit]
            if player_position and Vector3_distance_squared(target_position, player_position) < radius_squared then
                return true
            end
        end
    end

    return false
end

-- Check if Target Unit's Breed is Valid for Auto-Mark
local function is_breed_valid(breed_data, class_settings)
    if not breed_data or not class_settings then
        return false
    end

    -- toggle enemy by type
    if breed_data.tags.elite then
        return class_settings.toggle_elite
    elseif breed_data.tags.special then
        return class_settings.toggle_special
    elseif breed_data.is_boss then
        return class_settings.toggle_boss
    else
        return class_settings.toggle_other
    end
end

-- Check if Tagged Target Unit can be Marked with Current Tag
local function is_target_valid(tag_name, target_tag, target_unit, target_position, target_breed_data)
    if tag_name == TAG_NAMES.COMPANION_TAG then
        -- allow re-marking over teammates' companion/servo-skull marks for all enemies, but never over veteran's prey
        local target_tag_name = target_tag and target_tag._template.name
        if target_tag_name == TAG_NAMES.VETERAN_TAG then
            return false
        end

        if mod_settings.companion_mark_ignore_unaggroed and not is_target_aggroed(target_unit) then
            return false
        end

        local companion_range_limitation = mod_settings.companion_range_limitation
        if companion_range_limitation <= 0 then
            return true
        end

        local companion_spawner_extension = context.companion_spawner_extension
        local companion_units = companion_spawner_extension and companion_spawner_extension:companion_units()
        local companion_unit = companion_units and companion_units[1]
        if not companion_unit then
            return false
        end

        local companion_unit_position = POSITION_LOOKUP[companion_unit] or Unit_world_position(companion_unit, 1)
        if not companion_unit_position or not target_position then
            return false
        end

        if Vector3_distance_squared(companion_unit_position, target_position) < companion_range_limitation * companion_range_limitation then
            return true
        end
    elseif tag_name == TAG_NAMES.VETERAN_TAG then
        local target_buff_extension = ScriptUnit_extension(target_unit, "buff_system")
        if not target_buff_extension then
            return false
        end

        local focus_target_debuff = target_buff_extension._stacking_buffs["veteran_improved_tag_debuff"]
        local target_stack_count = focus_target_debuff and focus_target_debuff:stack_count() or 0
        local target_tag_name = target_tag and target_tag._template.name
        -- target does not have focus target debuff
        if target_tag_name ~= TAG_NAMES.VETERAN_TAG and target_stack_count <= 0 then
            return true
        end

        -- latency bug
        if target_tag_name == TAG_NAMES.VETERAN_TAG and target_stack_count <= 0 then
            return false
        end

        -- focus_target_overwrite not enabled
        if not mod_settings.focus_target_overwrite then
            return false
        end

        local talent_resource_component = context.talent_resource_component
        if not talent_resource_component then
            return false
        end

        -- check if player's buff stacks greater than target's debuff stacks
        local player_stack_count = talent_resource_component.current_resource or 0
        if player_stack_count <= target_stack_count then
            return false
        end

        if player_stack_count == context.focus_target_max_stacks or player_stack_count - target_stack_count >= mod_settings.focus_target_overwrite_delta then
            return true
        end
    elseif tag_name == TAG_NAMES.SERVO_SKULL_TAG then
        -- servo skull marks can overwrite any existing mark; only another focus target vet can overwrite a focus target
        if mod_settings.servo_skull_mark_ignore_unaggroed and not is_target_aggroed(target_unit) then
            return false
        end

        if not mod_settings.capacitance_retention or not context.has_noospheric_command then
            return true
        end

        local player_ability_extension = context.player_ability_extension
        if not player_ability_extension then
            return false
        end

        local unit_data_extension = ScriptUnit_extension(target_unit, "unit_data_system")
        local breed_data = unit_data_extension and unit_data_extension._breed
        if not breed_data then
            return false
        end

        local breed_name = breed_data.name
        local breed_settings = noospheric_command_breed_settings[breed_name]
        local capacitance_retention_threshold
        if breed_settings and breed_settings.override then
            capacitance_retention_threshold = breed_settings.threshold or 0
        end

        if capacitance_retention_threshold == nil then
            if breed_data.is_boss then
                capacitance_retention_threshold = mod_settings.capacitance_retention_boss_threshold
            elseif breed_data.tags.special then
                capacitance_retention_threshold = mod_settings.capacitance_retention_special_threshold
            else
                capacitance_retention_threshold = mod_settings.capacitance_retention_elite_threshold
            end
        end

        local max_ability_charges = player_ability_extension:max_ability_charges("combat_ability")
        local remaining_ability_charges = player_ability_extension:remaining_ability_charges("combat_ability")
        local max_ability_cooldown = player_ability_extension:max_ability_cooldown("combat_ability")
        local remaining_ability_cooldown = player_ability_extension:remaining_ability_cooldown("combat_ability")

        if 1 / capacitance_retention_threshold < 0 then
            capacitance_retention_threshold = max_ability_charges + capacitance_retention_threshold
        end

        if remaining_ability_charges >= max_ability_charges then
            return remaining_ability_charges >= capacitance_retention_threshold
        else
            if remaining_ability_cooldown == 0 then
                return false
            end

            return remaining_ability_charges + (max_ability_cooldown - remaining_ability_cooldown) / max_ability_cooldown >= capacitance_retention_threshold
        end
    elseif tag_name == TAG_NAMES.ENEMY_TAG then
        if not target_tag then
            return true
        end
    end

    return false
end

local function is_target_visible(ray_origin, up, hit_unit_center_pos, half_height, hit_unit, fixed_frame)
    if not visibility_raycast_object then
        return false
    end

    local cached_visibility = visibility_cache[hit_unit]
    local last_check_frame = visibility_check_frame[hit_unit]
    if cached_visibility ~= nil and fixed_frame - last_check_frame <= 5 then
        return cached_visibility
    end

    local ray_to_target_center = hit_unit_center_pos - ray_origin
    local ray_to_target_top = ray_to_target_center + up * half_height * 2 / 3
    local hit_top = Raycast_cast(visibility_raycast_object, ray_origin, Vector3_normalize(ray_to_target_top), Vector3_length(ray_to_target_top))
    if not hit_top then
        visibility_cache[hit_unit] = true
        visibility_check_frame[hit_unit] = fixed_frame
        return true
    end

    local hit_center = Raycast_cast(visibility_raycast_object, ray_origin, Vector3_normalize(ray_to_target_center), Vector3_length(ray_to_target_center))
    visibility_cache[hit_unit] = not hit_center
    visibility_check_frame[hit_unit] = fixed_frame
    return not hit_center
end

local function is_force_field_blocked(from_position, to_position)
    local force_field_system = Managers.state.extension:system("force_field_system")
    local unit_to_extension_map = force_field_system and force_field_system._unit_to_extension_map
    if not unit_to_extension_map or not next(unit_to_extension_map) then
        return false
    end

    local to_target = to_position - from_position
    local length = Vector3_length(to_target)
    if length < 0.05 then
        return false
    end

    local direction = to_target / length
    local steps = math.clamp(math.ceil(length / 0.5), 2, 120)

    for unit, extension in pairs(unit_to_extension_map) do
        if ALIVE[unit] and extension.is_unit_colliding then
            if extension:is_unit_colliding(from_position, 0.3, true) or extension:is_unit_colliding(to_position, 0.3, true) then
                return true
            end

            for i = 1, steps - 1 do
                local point = from_position + direction * (length * i / steps)
                if extension:is_unit_colliding(point, 0.3, true) then
                    return true
                end
            end
        end
    end

    return false
end

local function is_servo_skull_target_visible(target_unit, fixed_frame)
    if not servo_skull_visibility_raycast_object then
        return false
    end

    local smoke_fog_system = context.smoke_fog_system
    if not smoke_fog_system then
        return false
    end

    local cached_visibility = servo_skull_visibility_cache[target_unit]
    local last_check_frame = servo_skull_visibility_check_frame[target_unit]
    if cached_visibility ~= nil and fixed_frame - last_check_frame <= 5 then
        return cached_visibility
    end

    local companion_spawner_extension = context.companion_spawner_extension
    local servo_skull_unit = companion_spawner_extension and companion_spawner_extension:spawned_unit_lookup(special_rules.cryptic_servo_skull_hack)
    if not servo_skull_unit then
        return false
    end

    local mutator_manager = Managers.state.mutator
    local los_modifier = mutator_manager:mutator(DARKNESS_LOS_MODIFIER_NAME) and DARKNESS_LOS_MODIFIER_NAME or mutator_manager:mutator(VENTILATION_PURGE_LOS_MODIFIER_NAME) and VENTILATION_PURGE_LOS_MODIFIER_NAME
    local detection_los_requirement

    if los_modifier then
        detection_los_requirement = CIRCUMSTANCE_DETECTION_DISTANCE_LOS_REQUIREMENTS[los_modifier]
    end

    for keyword, distance_requirement in pairs(BUFF_KEYWORD_DISTANCE_LOS_REQUIREMENT) do
        local target_buff_extension = ScriptUnit_extension(target_unit, "buff_system")
        if target_buff_extension and target_buff_extension:has_keyword(keyword) then
            detection_los_requirement = distance_requirement
        end
    end

    local POSITION_LOOKUP = POSITION_LOOKUP
    local servo_skull_position = POSITION_LOOKUP[servo_skull_unit] or Unit_world_position(servo_skull_unit, 1)
    local target_position = POSITION_LOOKUP[target_unit] or Unit_world_position(target_unit, 1)
    local is_within_range = not detection_los_requirement or detection_los_requirement >= Vector3_distance(servo_skull_position, target_position)
    if not is_within_range then
        servo_skull_visibility_cache[target_unit] = false
        servo_skull_visibility_check_frame[target_unit] = fixed_frame
        return false
    end

    local is_looking_trough_fog = smoke_fog_system:check_fog_los(servo_skull_position, target_position, servo_skull_unit, true)
    if is_looking_trough_fog then
        mod:print_debug("servo skull visibility blocked by smoke/fog")
        servo_skull_visibility_cache[target_unit] = false
        servo_skull_visibility_check_frame[target_unit] = fixed_frame
        return false
    end

    local force_field_ok, force_field_blocked = pcall(is_force_field_blocked, servo_skull_position, target_position + Vector3(0, 0, 1.3))
    if force_field_ok and force_field_blocked then
        mod:print_debug("servo skull visibility blocked by force field")
        servo_skull_visibility_cache[target_unit] = false
        servo_skull_visibility_check_frame[target_unit] = fixed_frame
        return false
    end

    local servo_skull_data_extension = ScriptUnit_extension(servo_skull_unit, "unit_data_system")
    local servo_skull_breed_data = servo_skull_data_extension and servo_skull_data_extension._breed
    if not servo_skull_breed_data then
        return false
    end

    local line_of_sight_data = servo_skull_breed_data.line_of_sight_data
    local first_line_of_sight_data = line_of_sight_data[1]
    local from_node, to_node = first_line_of_sight_data.from_node, first_line_of_sight_data.to_node
    local los_from_node = Unit_node(servo_skull_unit, from_node)
    local los_to_node = Unit_node(target_unit, to_node)
    local los_from_position = Unit_world_position(servo_skull_unit, los_from_node)
    local los_to_position = Unit_world_position(target_unit, los_to_node)
    local to_los_position = los_to_position - los_from_position
    local los_direction = Vector3_normalize(to_los_position)
    local los_distance = Vector3_length(to_los_position)

    local hit = Raycast_cast(servo_skull_visibility_raycast_object, los_from_position, los_direction, los_distance)
    servo_skull_visibility_cache[target_unit] = not hit
    servo_skull_visibility_check_frame[target_unit] = fixed_frame
    return not hit
end

function mod:find_target_unit_custom(type, min_range, max_range, tag_name, tag_context, class_settings, use_filter, is_execution_order_priority, marked_tag)
    local player = context.player
    local player_unit = player and player.player_unit
    local smart_targeting_extension = context.smart_targeting_extension
    local precision_target_finder = smart_targeting_extension and smart_targeting_extension._precision_target_aim_assist
    local smart_tag_system = context.smart_tag_system
    if not player_unit or not smart_targeting_extension or not precision_target_finder or not smart_tag_system then
        return nil
    end

    local ray_origin, forward, right, up = smart_targeting_extension:_targeting_parameters()
    local fixed_frame = smart_targeting_extension._latest_fixed_frame
    local canceled_unit = tag_context and tag_context.canceled_unit
    local breed_priorities = class_settings and class_settings.breed_priorities or EMPTY_TABLE
    local distance_threshold = class_settings and class_settings.distance_threshold
    local execution_order_units = mark_context.execution_order_units
    local best_unit = nil
    local best_unit_tag = nil
    local best_unit_priority = -math.huge
    local best_unit_marked_by_execution_order = false
    local best_unit_distance = math.huge
    -- init best unit for switch logic
    local marked_unit = marked_tag and marked_tag._target_unit
    if marked_unit then
        best_unit = marked_unit
        local unit_data_extension = ScriptUnit_extension(best_unit, "unit_data_system")
        local breed_data = unit_data_extension and unit_data_extension._breed
        local marked_position = POSITION_LOOKUP[best_unit] or Unit_world_position(best_unit, 1)
        local marked_distance = marked_position and Vector3_distance(marked_position, ray_origin)
        best_unit_priority = breed_data and get_breed_priority(best_unit, breed_data, breed_priorities, marked_distance, distance_threshold) or 0
        best_unit_marked_by_execution_order = not not execution_order_units[best_unit]
    end

    if type == "auto" then
        -- omnidirectional lookup: every alive enemy in range, regardless of where the player is aiming
        local side_system = Managers.state.extension and Managers.state.extension:system("side_system")
        local player_side = side_system and side_system:get_side_from_name("heroes")
        local enemy_units = player_side and player_side:relation_units("enemy")
        if not enemy_units then
            return nil
        end

        for i = 1, #enemy_units do
            local hit_unit = enemy_units[i]
            -- ignore player unit, already marked unit and dead unit
            if hit_unit == player_unit or hit_unit == marked_unit or hit_unit == canceled_unit or not HEALTH_ALIVE[hit_unit] then
                goto continue
            end

            local unit_data_extension = ScriptUnit_extension(hit_unit, "unit_data_system")
            local breed_data = unit_data_extension and unit_data_extension._breed
            -- ignore untaggable unit
            if not breed_data or breed_data.smart_tag_target_type ~= "breed" then
                goto continue
            end

            local half_height = Breed_height(hit_unit, breed_data) * 0.5
            local hit_unit_center_pos = Unit_world_position(hit_unit, 1) + Vector3(0, 0, 1) * half_height
            local distance = Vector3_distance(hit_unit_center_pos, ray_origin)
            -- filter unit by range
            if distance < min_range or distance > max_range then
                goto continue
            end

            -- priority depends on distance (close/far split around distance_threshold)
            local hit_unit_priority = get_breed_priority(hit_unit, breed_data, breed_priorities, distance, distance_threshold) or 0
            -- filter unit by type and priority
            if use_filter and (hit_unit_priority <= 0 or not is_breed_valid(breed_data, class_settings)) then
                goto continue
            end

            -- never servo-skull-mark a burster near the player or a teammate
            if tag_name == TAG_NAMES.SERVO_SKULL_TAG and BURSTER_BREEDS[breed_data.name] and is_burster_forbidden(POSITION_LOOKUP[hit_unit] or Unit_world_position(hit_unit, 1)) then
                goto continue
            end

            local hit_unit_marked_by_execution_order = not not execution_order_units[hit_unit]
            if is_execution_order_priority then
                if hit_unit_marked_by_execution_order == best_unit_marked_by_execution_order then
                    if hit_unit_priority <= best_unit_priority then
                        goto continue
                    end
                elseif best_unit_marked_by_execution_order then
                    goto continue
                end
            else
                if hit_unit_priority <= best_unit_priority then
                    goto continue
                end
            end

            local hit_unit_tag = smart_tag_system:unit_tag(hit_unit)
            -- filter unit by tag
            if not is_target_valid(tag_name, hit_unit_tag, hit_unit, hit_unit_center_pos, breed_data) then
                goto continue
            end

            local visible
            if tag_name == TAG_NAMES.SERVO_SKULL_TAG then
                visible = is_servo_skull_target_visible(hit_unit, fixed_frame)
            else
                visible = is_target_visible(ray_origin, up, hit_unit_center_pos, half_height, hit_unit, fixed_frame)
            end

            if not visible then
                goto continue
            end

            best_unit = hit_unit
            best_unit_tag = hit_unit_tag
            best_unit_priority = hit_unit_priority
            best_unit_marked_by_execution_order = hit_unit_marked_by_execution_order

            ::continue::
        end

        if best_unit ~= marked_unit then
            return best_unit, best_unit_tag
        end

        return nil
    end

    -- raycast for hit unit list (focus_target_melee: pick the centered target along the crosshair ray)
    local hits, num_hits = PhysicsWorld_raycast(smart_targeting_extension._physics_world, ray_origin, forward, max_range, "all", "collision_filter", COLLISION_FILTER)
    if num_hits <= 0 then
        return nil
    end

    for i = 1, num_hits do
        local hit = hits[i]
        local hit_actor = hit[INDEX_ACTOR]
        if not hit_actor then
            goto continue
        end

        local hit_unit = Actor_unit(hit_actor)
        -- ignore player unit, already marked unit and dead unit
        if hit_unit == player_unit or hit_unit == marked_unit or hit_unit == canceled_unit or not HEALTH_ALIVE[hit_unit] then
            goto continue
        end

        local unit_data_extension = ScriptUnit_extension(hit_unit, "unit_data_system")
        local breed_data = unit_data_extension and unit_data_extension._breed
        -- ignore untaggable unit
        if not breed_data or breed_data.smart_tag_target_type ~= "breed" then
            goto continue
        end

        local hit_unit_pose, _ = Unit_box(hit_unit, true)
        local hit_unit_center_pos, _ = Actor_world_bounds(hit_actor)
        local object_right = Matrix4x4_right(hit_unit_pose)
        local object_forward = Matrix4x4_forward(hit_unit_pose)
        local world_extents_right = object_right * (breed_data.half_extent_right or 0.3)
        local world_extents_forward = object_forward * (breed_data.half_extent_forward or 0.3)
        local half_width = math_max(
            math_abs(Vector3_dot(right, world_extents_right + world_extents_forward)),
            math_abs(Vector3_dot(right, world_extents_right - world_extents_forward))
        )
        local half_height = Breed_height(hit_unit, breed_data) * 0.5
        local distance = Vector3_distance(hit_unit_center_pos, ray_origin) - half_width
        -- filter unit by range
        if distance < min_range or distance > max_range then
            goto continue
        end

        -- priority depends on distance (close/far split around distance_threshold)
        local hit_unit_priority = get_breed_priority(hit_unit, breed_data, breed_priorities, distance, distance_threshold) or 0
        -- filter unit by type and priority
        if use_filter and (hit_unit_priority <= 0 or not is_breed_valid(breed_data, class_settings)) then
            goto continue
        end

        if best_unit and best_unit_distance <= 3.5 and distance > 3.5 then
            goto continue
        end

        if not is_target_visible(ray_origin, up, hit_unit_center_pos, half_height, hit_unit, fixed_frame) then
            goto continue
        end

        best_unit = hit_unit
        best_unit_tag = smart_tag_system:unit_tag(hit_unit)
        best_unit_distance = distance

        ::continue::
    end

    if best_unit ~= marked_unit then
        return best_unit, best_unit_tag
    end

    return nil
end

function mod:is_target_valid(tag_name, target_tag, target_unit, target_position, target_breed_data)
    return is_target_valid(tag_name, target_tag, target_unit, target_position, target_breed_data)
end

function mod:is_servo_skull_target_visible(target_unit, fixed_frame)
    return is_servo_skull_target_visible(target_unit, fixed_frame)
end

function mod:is_noospheric_command_boost_breed_valid(target_unit)
    local unit_data_extension = ScriptUnit_extension(target_unit, "unit_data_system")
    local breed_data = unit_data_extension and unit_data_extension._breed
    if not breed_data then
        return false
    end

    if breed_data.tags.witch and not is_target_aggroed(target_unit) then
        return false
    end

    local breed_name = breed_data.name
    if BURSTER_BREEDS[breed_name] and is_burster_forbidden(POSITION_LOOKUP[target_unit] or Unit_world_position(target_unit, 1)) then
        return false
    end

    local breed_settings = noospheric_command_breed_settings[breed_name]
    if breed_settings and breed_settings.override then
        return breed_settings.toggle
    end

    if breed_data.is_boss then
        return mod_settings.noospheric_command_boost_boss
    elseif breed_data.tags.special then
        return mod_settings.noospheric_command_boost_special
    else
        return mod_settings.noospheric_command_boost_elite
    end
end

mod:hook_safe(CLASS.PrecisionTargetFinder, "init",
    function(self, is_server, is_local_unit, player, physics_world, unit)
        visibility_raycast_object = PhysicsWorld.make_raycast(physics_world, "closest", "types", "both", "collision_filter", "filter_interactable_line_of_sight_marker_check")
        servo_skull_visibility_raycast_object = PhysicsWorld.make_raycast(physics_world, "closest", "types", "both", "collision_filter", "filter_minion_line_of_sight_check")
    end)
