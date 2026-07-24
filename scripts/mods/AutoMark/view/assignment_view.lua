--[[
    assignment_view.lua
    Assign breed-priority presets to class contexts, and edit each class's
    behavioral settings. Left: class list. Middle: the selected class's
    settings (cooldown / ranges sliders + toggles). Right: preset list; click
    a preset to assign it to the selected class. Persists on every change.
--]]

local mod          = get_mod("AutoMark")

local ScriptWorld  = mod:original_require("scripts/foundation/utilities/script_world")
local UIRenderer   = mod:original_require("scripts/managers/ui/ui_renderer")
local UIWidget     = mod:original_require("scripts/managers/ui/ui_widget")
local UIWidgetGrid = mod:original_require("scripts/ui/widget_logic/ui_widget_grid")
local ViewElementInputLegend = mod:original_require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")

local VIEW_NAME    = "automark_assignment_view"
local PRESET_VIEW_NAME = "automark_breed_priority_view"

-- Class settings shown in the middle panel, in display order.
local SETTING_CONTROLS = {
    { kind = "slider",   key = "cooldown",   min = 1, max = 50 },
    { kind = "slider",   key = "min_range",  min = 0, max = 100 },
    { kind = "slider",   key = "max_range",  min = 1, max = 100 },
    { kind = "checkbox", key = "toggle_class" },
    { kind = "checkbox", key = "priority_switch" },
    { kind = "checkbox", key = "override_manual" },
    { kind = "checkbox", key = "reset_cooldown" },
    { kind = "checkbox", key = "mark_limit" },
    { kind = "checkbox", key = "toggle_elite" },
    { kind = "checkbox", key = "toggle_special" },
    { kind = "checkbox", key = "toggle_boss" },
    { kind = "checkbox", key = "toggle_other" },
}

local AssignmentView = class("AssignmentView", "BaseView")

-- ===== slider helpers (shared shape with the preset editor) =====

local function slider_label(label, value)
    return string.format("%s  %d", label, value)
end

local function init_slider_content(widget, label, min_value, max_value, value)
    local content         = widget.content
    content.min_value     = min_value
    content.max_value     = max_value
    content.label         = label
    content.step_size     = 1 / (max_value - min_value)
    content.slider_value  = (value - min_value) / (max_value - min_value)
    content.applied_value = value
    content.value_text    = slider_label(label, value)
end

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

-- ===== init =====

AssignmentView.init = function(self, settings_arg)
    self._definitions    = mod:io_dofile("AutoMark/scripts/mods/AutoMark/view/assignment_view_definitions")
    self._blueprint_data = mod:io_dofile("AutoMark/scripts/mods/AutoMark/view/assignment_view_blueprints")
    self._blueprints     = self._blueprint_data.blueprints
    self._view_settings  = mod:io_dofile("AutoMark/scripts/mods/AutoMark/view/assignment_view_settings")

    self._selected_class     = nil
    self._class_row_widgets  = {}
    self._class_rows_by_name = {}
    self._class_grid         = nil
    self._preset_row_widgets = {}
    self._preset_rows_by_id  = {}
    self._preset_grid        = nil
    self._setting_widgets    = {}   -- { control, widget }

    AssignmentView.super.init(self, self._definitions, settings_arg)
    self._pass_draw = false
    self:_setup_offscreen_gui()
end

AssignmentView._setup_offscreen_gui = function(self)
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

AssignmentView.on_enter = function(self)
    AssignmentView.super.on_enter(self)

    self._input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 10)
    for _, leg in ipairs(self._definitions.legend_inputs) do
        local cb = leg.on_pressed_callback and callback(self, leg.on_pressed_callback)
        self._input_legend_element:add_entry(leg.display_name, leg.input_action, nil, cb, leg.alignment)
    end

    local assign_all_button = self._widgets_by_name.assign_all_button
    if assign_all_button then
        assign_all_button.content.hotspot.pressed_callback = callback(self, "cb_assign_all")
    end
    local goto_presets_button = self._widgets_by_name.goto_presets_button
    if goto_presets_button then
        goto_presets_button.content.hotspot.pressed_callback = callback(self, "cb_goto_presets")
    end

    self:_build_settings()
    self:_build_class_list()
    self:_load_presets()

    local class_names = mod:get_priority_class_names()
    local default_class = mod:get_menu_class_name()
    if not self._class_rows_by_name[default_class] then
        default_class = class_names[1]
    end
    self:_select_class(default_class)
end

-- ===== middle settings panel =====

AssignmentView._build_settings = function(self)
    for i, control in ipairs(SETTING_CONTROLS) do
        local node = "setting_" .. i
        local widget
        if control.kind == "slider" then
            local def = UIWidget.create_definition(self._blueprint_data.setting_slider_passes, node)
            widget = self:_create_widget(node, def)
            init_slider_content(widget, mod:localize(control.key), control.min, control.max, control.min)
        else
            local template = self._blueprints.checkbox
            local def = UIWidget.create_definition(template.pass_template, node, nil, template.size)
            widget = self:_create_widget(node, def)
            widget.content.text = mod:localize(control.key)
            widget.content.value = false
            widget.content.hotspot.pressed_callback = callback(self, "cb_toggle_setting", widget, control)
        end
        self._widgets[#self._widgets + 1] = widget
        self._setting_widgets[i] = { control = control, widget = widget }
    end
end

AssignmentView._class_settings = function(self)
    return self._selected_class and mod:get_class_settings_by_name(self._selected_class)
end

AssignmentView._sync_settings = function(self)
    local class_settings = self:_class_settings()
    local visible = class_settings ~= nil
    for _, item in ipairs(self._setting_widgets) do
        local control = item.control
        local widget = item.widget
        widget.visible = visible
        if class_settings then
            local value = class_settings[control.key]
            if control.kind == "slider" then
                value = value or control.min
                widget.content.slider_value  = (value - control.min) / (control.max - control.min)
                widget.content.applied_value = value
                widget.content.value_text    = slider_label(widget.content.label, value)
            else
                widget.content.value = value and true or false
            end
        end
    end
end

AssignmentView._update_settings = function(self)
    local class_settings = self:_class_settings()
    if not class_settings then
        return
    end
    local changed = false
    for _, item in ipairs(self._setting_widgets) do
        if item.control.kind == "slider" then
            local value = read_slider_change(item.widget)
            if value then
                class_settings[item.control.key] = value
                changed = true
            end
        end
    end
    if changed then
        mod:set("auto_mark_settings", mod.auto_mark_settings, false)
    end
end

AssignmentView.cb_toggle_setting = function(self, widget, control)
    local class_settings = self:_class_settings()
    if not class_settings then
        return
    end
    local new_value = not class_settings[control.key]
    class_settings[control.key] = new_value
    widget.content.value = new_value
    mod:set("auto_mark_settings", mod.auto_mark_settings, false)
end

-- ===== class list =====

AssignmentView._build_class_list = function(self)
    local template = self._blueprints.selectable_row
    local def = UIWidget.create_definition(template.pass_template, "class_grid_content_pivot", nil, template.size)

    for i, class_name in ipairs(mod:get_priority_class_names()) do
        local preset_id, preset = mod:get_preset_for_class(class_name)
        local widget = self:_create_widget("class_row_" .. i, def)
        template.init(self, widget, {
            title    = mod:localize(class_name),
            subtitle = preset and (preset.name or "") or mod:localize("assignment_none"),
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

-- refresh class-row subtitles (assigned preset names) after any assignment
AssignmentView._refresh_class_subtitles = function(self)
    for class_name, widget in pairs(self._class_rows_by_name) do
        local _, preset = mod:get_preset_for_class(class_name)
        widget.content.text2 = preset and (preset.name or "") or mod:localize("assignment_none")
    end
end

-- ===== preset list =====

AssignmentView._clear_presets = function(self)
    for _, widget in ipairs(self._preset_row_widgets) do
        pcall(function() self:_unregister_widget_name(widget.name) end)
    end
    self._preset_row_widgets = {}
    self._preset_rows_by_id  = {}
    self._preset_grid        = nil
end

AssignmentView._load_presets = function(self)
    self:_clear_presets()

    local template = self._blueprints.selectable_row
    local def = UIWidget.create_definition(template.pass_template, "preset_grid_content_pivot", nil, template.size)

    for i, item in ipairs(mod:get_ordered_presets()) do
        local count = mod:count_preset_assignments(item.id)
        local widget = self:_create_widget("preset_row_" .. i, def)
        template.init(self, widget, {
            title    = item.preset.name or "Preset",
            subtitle = mod:localize("preset_assignment_count", count),
            id       = item.id,
        }, "cb_on_preset_pressed")
        self._preset_row_widgets[#self._preset_row_widgets + 1] = widget
        self._preset_rows_by_id[item.id] = widget
    end

    if #self._preset_row_widgets > 0 then
        self._preset_grid = UIWidgetGrid:new(
            self._preset_row_widgets, self._preset_row_widgets, self._ui_scenegraph,
            "preset_panel", "down", self._view_settings.grid_spacing, nil, true
        )
        self._preset_grid:set_render_scale(self._render_scale)
        local scrollbar = self._widgets_by_name.preset_scrollbar
        if scrollbar then
            self._preset_grid:assign_scrollbar(scrollbar, "preset_grid_content_pivot", "preset_panel")
            self._preset_grid:set_scrollbar_progress(0)
        end
    end
end

-- highlight the preset assigned to the selected class
AssignmentView._sync_preset_highlight = function(self)
    local assigned_id = self._selected_class and mod:get_preset_for_class(self._selected_class)
    for preset_id, widget in pairs(self._preset_rows_by_id) do
        widget.content.is_selected = (preset_id == assigned_id)
    end
end

-- refresh preset-row subtitles (assignment counts) after any assignment
AssignmentView._refresh_preset_subtitles = function(self)
    for preset_id, widget in pairs(self._preset_rows_by_id) do
        widget.content.text2 = mod:localize("preset_assignment_count", mod:count_preset_assignments(preset_id))
    end
end

-- ===== selection =====

AssignmentView._select_class = function(self, class_name)
    self._selected_class = class_name
    for row_class_name, widget in pairs(self._class_rows_by_name) do
        widget.content.is_selected = (row_class_name == class_name)
    end
    self:_sync_settings()
    self:_sync_preset_highlight()
end

-- ===== callbacks =====

AssignmentView.cb_on_class_pressed = function(self, widget, entry)
    self:_select_class(entry.id)
end

AssignmentView.cb_on_preset_pressed = function(self, widget, entry)
    if not self._selected_class then
        return
    end
    mod:assign_preset(self._selected_class, entry.id)
    self:_sync_preset_highlight()
    self:_refresh_class_subtitles()
    self:_refresh_preset_subtitles()
end

AssignmentView.cb_assign_all = function(self)
    local assigned_id = self._selected_class and mod:get_preset_for_class(self._selected_class)
    if not assigned_id then
        return
    end
    mod:assign_preset_to_all(assigned_id)
    self:_sync_preset_highlight()
    self:_refresh_class_subtitles()
    self:_refresh_preset_subtitles()
end

AssignmentView.cb_goto_presets = function(self)
    Managers.ui:close_view(VIEW_NAME)
    Managers.ui:open_view(PRESET_VIEW_NAME)
end

AssignmentView.cb_on_back_pressed = function(self)
    Managers.ui:close_view(VIEW_NAME)
end

-- ===== update / draw =====

AssignmentView.update = function(self, dt, t, input_service)
    if self._class_grid then
        self._class_grid:update(dt, t, input_service)
    end
    if self._preset_grid then
        self._preset_grid:update(dt, t, input_service)
    end
    self:_update_settings()
    return AssignmentView.super.update(self, dt, t, input_service)
end

AssignmentView.draw = function(self, dt, t, input_service, layer)
    self:_draw_elements(dt, t, self._ui_renderer, self._render_settings, input_service)

    if #self._class_row_widgets > 0 then
        self:_draw_grid(self._class_grid, self._class_row_widgets, dt, t, input_service)
    end
    if #self._preset_row_widgets > 0 then
        self:_draw_grid(self._preset_grid, self._preset_row_widgets, dt, t, input_service)
    end

    AssignmentView.super.draw(self, dt, t, input_service, layer)
end

AssignmentView._draw_grid = function(self, grid, widgets, dt, t, input_service)
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

AssignmentView.on_exit = function(self)
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
    AssignmentView.super.on_exit(self)
end

return AssignmentView
