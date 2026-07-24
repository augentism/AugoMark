--[[
    breed_priority_view.lua
    Left: scrollable list of class contexts (select). Right: the selected
    class's distance threshold slider plus two scroll-synced columns of
    per-breed priority sliders (0-20) — close on the left, far on the right,
    one line per breed, grouped by category. Mutator variants share their
    base breed's sliders (except the Dreg Ritualist mutator). Persists to
    mod:set("auto_mark_settings", ...) on every change.
--]]

local mod          = get_mod("AutoMark")

local Breed        = mod:original_require("scripts/utilities/breed")
local Breeds       = mod:original_require("scripts/settings/breed/breeds")
local ScriptWorld  = mod:original_require("scripts/foundation/utilities/script_world")
local UIRenderer   = mod:original_require("scripts/managers/ui/ui_renderer")
local UIWidget     = mod:original_require("scripts/managers/ui/ui_widget")
local UIWidgetGrid = mod:original_require("scripts/ui/widget_logic/ui_widget_grid")
local ViewElementInputLegend = mod:original_require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")

local VIEW_NAME    = "automark_breed_priority_view"

local PRIORITY_MIN, PRIORITY_MAX   = 0, 20
local THRESHOLD_MIN, THRESHOLD_MAX = 1, 60

-- Mutator variants that keep their own sliders instead of sharing the base
-- breed's (the Havoc Dreg Ritualist behaves differently enough to tune apart)
local MUTATOR_ALIAS_EXCEPTIONS     = { chaos_mutator_ritualist = true }

-- Extra per-state priority entries shown as their own rows after the base breed
local EXTRA_PRIORITY_VARIANTS      = {
    chaos_mutator_ritualist = { "chaos_mutator_ritualist_half", "chaos_mutator_ritualist_full" },
}

local BreedPriorityView = class("BreedPriorityView", "BaseView")

-- ===== Breed list =====

-- A priority key is a breed name or a witch "<breed>_passive" variant.
-- Returns the base key a mutator variant should share sliders with, or nil.
local function mutator_alias_base(key, all_keys)
    local breed_key = key:gsub("_passive$", "")
    if MUTATOR_ALIAS_EXCEPTIONS[breed_key] or not key:find("mutator") then
        return nil
    end
    for _, pattern in ipairs({ "_mutator", "mutator_" }) do
        local base = key:gsub(pattern, "")
        if base ~= key and all_keys[base] then
            return base
        end
    end
    return nil
end

-- Ordered categories of priority keys plus the alias map
-- (base key -> array of mutator variant keys that mirror it).
local function build_breed_categories()
    local groups = { elite = {}, special = {}, boss = {}, other = {} }
    local all_keys = {}

    for breed_name, breed_data in pairs(Breeds) do
        if Breed.is_minion(breed_data) and breed_data.smart_tag_target_type == "breed" then
            if breed_data.tags.elite then
                groups.elite[#groups.elite + 1] = breed_name
                all_keys[breed_name] = true
            elseif breed_data.tags.special then
                groups.special[#groups.special + 1] = breed_name
                all_keys[breed_name] = true
            elseif breed_data.is_boss then
                groups.boss[#groups.boss + 1] = breed_name
                all_keys[breed_name] = true
                if breed_data.tags.witch then
                    all_keys[breed_name .. "_passive"] = true
                end
            elseif breed_data.faction_name ~= "imperium" then
                groups.other[#groups.other + 1] = breed_name
                all_keys[breed_name] = true
            end
        end
    end

    local alias_map = {}
    local is_aliased = {}
    for key, _ in pairs(all_keys) do
        local base = mutator_alias_base(key, all_keys)
        if base then
            alias_map[base] = alias_map[base] or {}
            table.insert(alias_map[base], key)
            is_aliased[key] = true
        end
    end

    local by_localized_name = function(a, b)
        return mod:localize(a) < mod:localize(b)
    end

    local categories = {}
    for _, group in ipairs({
        { label = "category_elite", names = groups.elite },
        { label = "category_special", names = groups.special },
        { label = "category_boss", names = groups.boss },
        { label = "category_other", names = groups.other },
    }) do
        table.sort(group.names, by_localized_name)
        local entries = {}
        for _, breed_name in ipairs(group.names) do
            if not is_aliased[breed_name] then
                entries[#entries + 1] = breed_name
                local passive = breed_name .. "_passive"
                if all_keys[passive] and not is_aliased[passive] then
                    entries[#entries + 1] = passive
                end
                for _, variant in ipairs(EXTRA_PRIORITY_VARIANTS[breed_name] or {}) do
                    entries[#entries + 1] = variant
                end
            end
        end
        if #entries > 0 then
            categories[#categories + 1] = { label = group.label, entries = entries }
        end
    end

    return categories, alias_map
end

-- ===== Init =====

BreedPriorityView.init = function(self, settings_arg)
    self._definitions   = mod:io_dofile("AutoMark/scripts/mods/AutoMark/view/breed_priority_view_definitions")
    self._blueprint_data = mod:io_dofile("AutoMark/scripts/mods/AutoMark/view/breed_priority_view_blueprints")
    self._blueprints    = self._blueprint_data.blueprints
    self._view_settings = mod:io_dofile("AutoMark/scripts/mods/AutoMark/view/breed_priority_view_settings")

    self._selected_class     = nil
    self._class_row_widgets  = {}
    self._class_rows_by_name = {}
    self._class_grid         = nil
    -- parallel widget lists: index i in both columns is the same visual line
    self._close_widgets      = {}
    self._far_widgets        = {}
    -- { breed_name, close_widget, far_widget } per slider line
    self._entry_sliders      = {}
    self._close_grid         = nil
    self._far_grid           = nil
    self._threshold_widget   = nil
    self._alias_map          = {}

    BreedPriorityView.super.init(self, self._definitions, settings_arg)
    self._pass_draw = false
    self:_setup_offscreen_gui()
end

BreedPriorityView._setup_offscreen_gui = function(self)
    local ui_manager      = Managers.ui
    local class_name      = self.__class_name
    self._offscreen_world = ui_manager:create_world(class_name .. "_world", 10, "ui", self.view_name)
    local viewport_name   = class_name .. "_viewport"
    self._offscreen_viewport = ui_manager:create_viewport(
        self._offscreen_world, viewport_name, "overlay_offscreen", 1, self._view_settings.shading_environment
    )
    self._offscreen_viewport_name = viewport_name
    self._ui_offscreen_renderer   = ui_manager:create_renderer(class_name .. "_renderer", self._offscreen_world)
end

-- ===== on_enter =====

BreedPriorityView.on_enter = function(self)
    BreedPriorityView.super.on_enter(self)

    self._input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 10)
    for _, leg in ipairs(self._definitions.legend_inputs) do
        local cb = leg.on_pressed_callback and callback(self, leg.on_pressed_callback)
        self._input_legend_element:add_entry(leg.display_name, leg.input_action, nil, cb, leg.alignment)
    end

    local copy_button = self._widgets_by_name.copy_button
    if copy_button then
        copy_button.content.hotspot.pressed_callback = callback(self, "cb_copy_to_all_pressed")
    end

    self:_build_threshold_slider()
    self:_build_class_list()
    self:_build_breed_sliders()

    -- default to the class the player is currently using
    local default_class = mod:get_menu_class_name()
    if not self._class_rows_by_name[default_class] then
        local class_names = mod:get_priority_class_names()
        default_class = class_names[1]
    end
    self:_select(default_class)
end

-- ===== Sliders =====

local function slider_label(label, value)
    if label == "" then
        return tostring(value)
    end
    return string.format("%s  %d", label, value)
end

local function init_slider_content(widget, label, min_value, max_value)
    local content         = widget.content
    content.min_value     = min_value
    content.max_value     = max_value
    content.label         = label
    content.step_size     = 1 / (max_value - min_value)  -- normalized, quantizes drag
    content.slider_value  = 0
    content.applied_value = min_value
    content.value_text    = slider_label(label, min_value)
end

local function sync_slider_value(widget, value)
    local content         = widget.content
    content.slider_value  = (value - content.min_value) / (content.max_value - content.min_value)
    content.applied_value = value
    content.value_text    = slider_label(content.label, value)
end

-- Returns the quantized integer if the slider moved this frame, else nil.
local function read_slider_change(widget)
    local content = widget.content
    local range   = content.max_value - content.min_value
    local raw     = content.min_value + (content.slider_value or 0) * range
    local value   = math.min(content.max_value, math.max(content.min_value, math.floor(raw + 0.5)))
    if value ~= content.applied_value then
        content.applied_value = value
        content.value_text    = slider_label(content.label, value)
        return value
    end
    return nil
end

BreedPriorityView._build_threshold_slider = function(self)
    local def    = UIWidget.create_definition(self._blueprint_data.close_slider_passes, "threshold_slider")
    local widget = self:_create_widget("threshold_slider", def)
    self._widgets[#self._widgets + 1] = widget   -- drawn by the normal renderer
    init_slider_content(widget, mod:localize("distance_threshold"), THRESHOLD_MIN, THRESHOLD_MAX)
    self._threshold_widget = widget
end

BreedPriorityView._build_breed_sliders = function(self)
    local categories, alias_map = build_breed_categories()
    self._alias_map = alias_map

    local bp             = self._blueprint_data
    local header_template = self._blueprints.category_header
    local spacer_template = self._blueprints.row_spacer

    local close_def  = UIWidget.create_definition(bp.close_slider_passes, "breed_grid_content_pivot", nil, bp.close_slider_size)
    local far_def    = UIWidget.create_definition(bp.far_slider_passes, "far_grid_content_pivot", nil, bp.far_slider_size)
    local header_def = UIWidget.create_definition(header_template.pass_template, "breed_grid_content_pivot", nil, header_template.size)
    local spacer_def = UIWidget.create_definition(spacer_template.pass_template, "far_grid_content_pivot", nil, spacer_template.size)

    local line = 0
    for _, category in ipairs(categories) do
        line = line + 1
        local header = self:_create_widget("breed_header_" .. line, header_def)
        header.content.text = mod:localize(category.label)
        self._close_widgets[#self._close_widgets + 1] = header
        self._far_widgets[#self._far_widgets + 1] = self:_create_widget("breed_spacer_" .. line, spacer_def)

        for _, breed_name in ipairs(category.entries) do
            line = line + 1
            local close_widget = self:_create_widget("breed_close_" .. line, close_def)
            local far_widget   = self:_create_widget("breed_far_" .. line, far_def)
            init_slider_content(close_widget, mod:localize(breed_name), PRIORITY_MIN, PRIORITY_MAX)
            init_slider_content(far_widget, "", PRIORITY_MIN, PRIORITY_MAX)
            self._close_widgets[#self._close_widgets + 1] = close_widget
            self._far_widgets[#self._far_widgets + 1] = far_widget
            self._entry_sliders[#self._entry_sliders + 1] = {
                breed_name   = breed_name,
                close_widget = close_widget,
                far_widget   = far_widget,
            }
        end
    end

    local spacing = self._view_settings.grid_spacing
    local scrollbar = self._widgets_by_name.breed_scrollbar

    -- Two grids share one scrollbar: both columns have identical row heights,
    -- so reading the same scroll value keeps their lines aligned. The far grid
    -- is assigned first; the close grid's assignment (last) sets the shared
    -- wheel-scroll area spanning both columns.
    self._far_grid = UIWidgetGrid:new(
        self._far_widgets, self._far_widgets, self._ui_scenegraph,
        "far_panel", "down", spacing, nil, true
    )
    self._far_grid:set_render_scale(self._render_scale)
    if scrollbar then
        self._far_grid:assign_scrollbar(scrollbar, "far_grid_content_pivot", "breed_scroll_interaction")
    end

    self._close_grid = UIWidgetGrid:new(
        self._close_widgets, self._close_widgets, self._ui_scenegraph,
        "breed_panel", "down", spacing, nil, true
    )
    self._close_grid:set_render_scale(self._render_scale)
    if scrollbar then
        self._close_grid:assign_scrollbar(scrollbar, "breed_grid_content_pivot", "breed_scroll_interaction")
        self._close_grid:set_scrollbar_progress(0)
    end
end

BreedPriorityView._selected_class_settings = function(self)
    return self._selected_class and mod:get_class_settings_by_name(self._selected_class)
end

BreedPriorityView._sync_sliders = function(self)
    local class_settings = self:_selected_class_settings()
    local visible        = class_settings ~= nil

    if self._threshold_widget then
        self._threshold_widget.visible = visible
        if class_settings then
            sync_slider_value(self._threshold_widget, class_settings.distance_threshold or THRESHOLD_MIN)
        end
    end

    local breed_priorities = class_settings and class_settings.breed_priorities or {}
    for _, entry in ipairs(self._entry_sliders) do
        local priorities = breed_priorities[entry.breed_name]
        sync_slider_value(entry.close_widget, priorities and priorities.close or 0)
        sync_slider_value(entry.far_widget, priorities and priorities.far or 0)
    end

    local label = self._widgets_by_name.selected_label
    if label then
        label.visible = visible
        label.content.text = self._selected_class and mod:localize(self._selected_class) or ""
    end
end

-- Writes a value to the breed's entry and every mutator variant sharing it.
BreedPriorityView._apply_priority = function(self, breed_priorities, breed_name, kind, value)
    local names = { breed_name }
    for _, variant in ipairs(self._alias_map[breed_name] or {}) do
        names[#names + 1] = variant
    end
    for _, name in ipairs(names) do
        local entry = breed_priorities[name]
        if not entry then
            entry = { close = 0, far = 0 }
            breed_priorities[name] = entry
        end
        entry[kind] = value
    end
end

-- Called every frame: applies quantized slider movement to the class settings.
BreedPriorityView._update_sliders = function(self)
    local class_settings = self:_selected_class_settings()
    if not class_settings then
        return
    end

    local changed = false

    if self._threshold_widget then
        local value = read_slider_change(self._threshold_widget)
        if value then
            class_settings.distance_threshold = value
            changed = true
        end
    end

    local breed_priorities = class_settings.breed_priorities
    for _, entry in ipairs(self._entry_sliders) do
        local close_value = read_slider_change(entry.close_widget)
        if close_value then
            self:_apply_priority(breed_priorities, entry.breed_name, "close", close_value)
            changed = true
        end
        local far_value = read_slider_change(entry.far_widget)
        if far_value then
            self:_apply_priority(breed_priorities, entry.breed_name, "far", far_value)
            changed = true
        end
    end

    if changed then
        mod:set("auto_mark_settings", mod.auto_mark_settings, false)
    end
end

-- ===== Class list =====

BreedPriorityView._build_class_list = function(self)
    local class_names = mod:get_priority_class_names()
    local template    = self._blueprints.class_row
    local def         = UIWidget.create_definition(template.pass_template, "class_grid_content_pivot", nil, template.size)

    for i, class_name in ipairs(class_names) do
        local widget = self:_create_widget("class_row_" .. i, def)
        template.init(self, widget, {
            title    = mod:localize(class_name),
            subtitle = "",
            id       = class_name,
        }, "cb_on_class_pressed")
        self._class_row_widgets[#self._class_row_widgets + 1] = widget
        self._class_rows_by_name[class_name] = widget
    end

    if #self._class_row_widgets > 0 then
        self._class_grid = UIWidgetGrid:new(
            self._class_row_widgets, self._class_row_widgets, self._ui_scenegraph,
            "class_panel", "down", self._view_settings.grid_spacing, nil, true
        )
        self._class_grid:set_render_scale(self._render_scale)
        local scrollbar = self._widgets_by_name.class_scrollbar
        if scrollbar then
            self._class_grid:assign_scrollbar(scrollbar, "class_grid_content_pivot", "class_panel")
            self._class_grid:set_scrollbar_progress(0)
        end
    end
end

BreedPriorityView._select = function(self, class_name)
    self._selected_class = class_name
    for row_class_name, widget in pairs(self._class_rows_by_name) do
        widget.content.is_selected = (row_class_name == class_name)
    end
    self:_sync_sliders()
end

-- ===== Callbacks =====

BreedPriorityView.cb_on_class_pressed = function(self, widget, entry)
    self:_select(entry.id)
end

-- Copies the selected class's distance threshold and breed priorities to
-- every other class context. Other class settings (cooldown, ranges,
-- toggles) are left alone; the DMF options apply button covers those.
BreedPriorityView.cb_copy_to_all_pressed = function(self)
    local source = self:_selected_class_settings()
    if not source then
        return
    end

    for _, class_name in ipairs(mod:get_priority_class_names()) do
        if class_name ~= self._selected_class then
            local dest = mod:get_class_settings_by_name(class_name)
            if dest then
                dest.distance_threshold = source.distance_threshold
                dest.breed_priorities = table.clone(source.breed_priorities)
            end
        end
    end

    mod:set("auto_mark_settings", mod.auto_mark_settings, false)
    mod:echo(mod:localize("copied_to_all_classes") .. ": " .. mod:localize(self._selected_class))
end

BreedPriorityView.cb_on_back_pressed = function(self)
    Managers.ui:close_view(VIEW_NAME)
end

-- ===== Update / Draw =====

BreedPriorityView.update = function(self, dt, t, input_service)
    if self._class_grid then
        self._class_grid:update(dt, t, input_service)
    end
    if self._close_grid then
        self._close_grid:update(dt, t, input_service)
    end
    if self._far_grid then
        self._far_grid:update(dt, t, input_service)
    end
    self:_update_sliders()
    return BreedPriorityView.super.update(self, dt, t, input_service)
end

BreedPriorityView.draw = function(self, dt, t, input_service, layer)
    self:_draw_elements(dt, t, self._ui_renderer, self._render_settings, input_service)

    if #self._class_row_widgets > 0 then
        self:_draw_grid(self._class_grid, self._class_row_widgets, dt, t, input_service)
    end
    if #self._close_widgets > 0 then
        self:_draw_grid(self._close_grid, self._close_widgets, dt, t, input_service)
    end
    if #self._far_widgets > 0 then
        self:_draw_grid(self._far_grid, self._far_widgets, dt, t, input_service)
    end

    BreedPriorityView.super.draw(self, dt, t, input_service, layer)
end

BreedPriorityView._draw_grid = function(self, grid, widgets, dt, t, input_service)
    local ui_renderer = self._ui_offscreen_renderer
    UIRenderer.begin_pass(ui_renderer, self._ui_scenegraph, input_service, dt, self._render_settings)
    for _, widget in ipairs(widgets) do
        local visible = widget.visible ~= false and (not grid or grid:is_widget_visible(widget))
        if visible then
            UIWidget.draw(widget, ui_renderer)
        end
    end
    UIRenderer.end_pass(ui_renderer)
end

-- ===== on_exit =====

BreedPriorityView.on_exit = function(self)
    if self._input_legend_element then
        self:_remove_element("input_legend")
        self._input_legend_element = nil
    end
    if self._ui_offscreen_renderer then
        Managers.ui:destroy_renderer(self.__class_name .. "_renderer")
        ScriptWorld.destroy_viewport(self._offscreen_world, self._offscreen_viewport_name)
        Managers.ui:destroy_world(self._offscreen_world)
        self._ui_offscreen_renderer   = nil
        self._offscreen_viewport      = nil
        self._offscreen_viewport_name = nil
        self._offscreen_world         = nil
    end
    BreedPriorityView.super.on_exit(self)
end

return BreedPriorityView
