local mod                    = get_mod("AutoMark")

local UIWorkspaceSettings    = mod:original_require("scripts/settings/ui/ui_workspace_settings")
local ScrollbarPassTemplates = mod:original_require("scripts/ui/pass_templates/scrollbar_pass_templates")
local ButtonPassTemplates    = mod:original_require("scripts/ui/pass_templates/button_pass_templates")
local UIFontSettings         = mod:original_require("scripts/managers/ui/ui_font_settings")
local UIWidget               = mod:original_require("scripts/managers/ui/ui_widget")

local _s                     = mod:io_dofile("AutoMark/scripts/mods/AutoMark/view/assignment_view_settings")

local scrollbar_width        = _s.scrollbar_width
local class_grid_size        = _s.class_grid_size
local preset_grid_size       = _s.preset_grid_size
local blur_edge              = _s.grid_blur_edge_size

local CLASS_X                = 140
local PANEL_TOP              = 250
local MID_X                  = 500
local MID_TOP                = 214           -- leaves room for a panel header
local RIGHT_X                = 1020
local SETTING_H              = 44
local ROW_PITCH              = 52
local NUM_SETTINGS           = 14            -- >= sliders + checkboxes used

local scenegraph_definition  = {
    screen = UIWorkspaceSettings.screen,

    title_divider = {
        vertical_alignment = "top", parent = "screen", horizontal_alignment = "left",
        size = { 335, 18 }, position = { CLASS_X, 145, 1 },
    },
    title_text = {
        vertical_alignment = "bottom", parent = "title_divider", horizontal_alignment = "left",
        size = { 1200, 50 }, position = { 0, -35, 1 },
    },

    -- left: class list
    class_panel = {
        vertical_alignment = "top", parent = "screen", horizontal_alignment = "left",
        size = class_grid_size, position = { CLASS_X, PANEL_TOP, 1 },
    },
    class_grid_start = {
        vertical_alignment = "top", parent = "class_panel", horizontal_alignment = "left",
        size = { 0, 0 }, position = { 0, 0, 0 },
    },
    class_grid_content_pivot = {
        vertical_alignment = "top", parent = "class_grid_start", horizontal_alignment = "left",
        size = { 0, 0 }, position = { 0, 0, 1 },
    },
    class_grid_mask = {
        vertical_alignment = "center", parent = "class_panel", horizontal_alignment = "center",
        size = { class_grid_size[1] + blur_edge[1] * 2, class_grid_size[2] + blur_edge[2] * 2 }, position = { 0, 0, 0 },
    },
    class_scrollbar = {
        vertical_alignment = "center", parent = "class_panel", horizontal_alignment = "right",
        size = { scrollbar_width, class_grid_size[2] }, position = { 24, 0, 1 },
    },

    -- middle: settings header + control column for the selected class
    settings_header = {
        vertical_alignment = "top", parent = "screen", horizontal_alignment = "left",
        size = { 440, 32 }, position = { MID_X, MID_TOP - 40, 2 },
    },

    -- right: preset list + buttons
    preset_header = {
        vertical_alignment = "top", parent = "screen", horizontal_alignment = "left",
        size = { preset_grid_size[1], 32 }, position = { RIGHT_X, PANEL_TOP - 40, 2 },
    },
    preset_panel = {
        vertical_alignment = "top", parent = "screen", horizontal_alignment = "left",
        size = preset_grid_size, position = { RIGHT_X, PANEL_TOP, 1 },
    },
    preset_grid_start = {
        vertical_alignment = "top", parent = "preset_panel", horizontal_alignment = "left",
        size = { 0, 0 }, position = { 0, 0, 0 },
    },
    preset_grid_content_pivot = {
        vertical_alignment = "top", parent = "preset_grid_start", horizontal_alignment = "left",
        size = { 0, 0 }, position = { 0, 0, 1 },
    },
    preset_grid_mask = {
        vertical_alignment = "center", parent = "preset_panel", horizontal_alignment = "center",
        size = { preset_grid_size[1] + blur_edge[1] * 2, preset_grid_size[2] + blur_edge[2] * 2 }, position = { 0, 0, 0 },
    },
    preset_scrollbar = {
        vertical_alignment = "center", parent = "preset_panel", horizontal_alignment = "right",
        size = { scrollbar_width, preset_grid_size[2] }, position = { 24, 0, 1 },
    },

    assign_all_button = {
        vertical_alignment = "top", parent = "screen", horizontal_alignment = "left",
        size = { preset_grid_size[1], 44 }, position = { RIGHT_X, PANEL_TOP + preset_grid_size[2] + 12, 2 },
    },
    goto_presets_button = {
        vertical_alignment = "top", parent = "screen", horizontal_alignment = "left",
        size = { preset_grid_size[1], 44 }, position = { RIGHT_X, PANEL_TOP + preset_grid_size[2] + 64, 2 },
    },
}

-- setting control slots down the middle column
for i = 1, NUM_SETTINGS do
    scenegraph_definition["setting_" .. i] = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = { 440, SETTING_H },
        position             = { MID_X, MID_TOP + (i - 1) * ROW_PITCH, 2 },
    }
end

local function header_text(scenegraph_id, value)
    return UIWidget.create_definition({
        {
            value_id  = "text",
            pass_type = "text",
            value     = value,
            style     = {
                font_type                 = "proxima_nova_bold",
                font_size                 = 22,
                text_color                = { 255, 220, 200, 160 },
                text_horizontal_alignment = "left",
                text_vertical_alignment   = "center",
                offset                    = { 0, 0, 2 },
            },
        }
    }, scenegraph_id)
end

local widget_definitions = {
    background = UIWidget.create_definition({
        { pass_type = "rect", style = { color = { 255, 0, 0, 0 } } }
    }, "screen"),

    title_divider = UIWidget.create_definition({
        { pass_type = "texture", value = "content/ui/materials/dividers/skull_rendered_left_01" }
    }, "title_divider"),

    title_text = UIWidget.create_definition({
        {
            value_id  = "text", style_id = "text", pass_type = "text",
            value     = mod:localize("assignment_view_title"),
            style     = table.clone(UIFontSettings.header_1),
        }
    }, "title_text"),

    settings_header = header_text("settings_header", mod:localize("assignment_settings_header")),
    preset_header   = header_text("preset_header", mod:localize("assignment_preset_header")),

    class_scrollbar  = UIWidget.create_definition(ScrollbarPassTemplates.default_scrollbar, "class_scrollbar"),
    preset_scrollbar = UIWidget.create_definition(ScrollbarPassTemplates.default_scrollbar, "preset_scrollbar"),

    class_grid_mask = UIWidget.create_definition({
        {
            value     = "content/ui/materials/offscreen_masks/ui_overlay_offscreen_vertical_blur",
            pass_type = "texture",
            style     = { color = { 255, 255, 255, 255 } },
        }
    }, "class_grid_mask"),

    preset_grid_mask = UIWidget.create_definition({
        {
            value     = "content/ui/materials/offscreen_masks/ui_overlay_offscreen_vertical_blur",
            pass_type = "texture",
            style     = { color = { 255, 255, 255, 255 } },
        }
    }, "preset_grid_mask"),

    assign_all_button = UIWidget.create_definition(
        table.clone(ButtonPassTemplates.default_button), "assign_all_button",
        { original_text = mod:localize("assign_to_all_classes") }
    ),

    goto_presets_button = UIWidget.create_definition(
        table.clone(ButtonPassTemplates.default_button), "goto_presets_button",
        { original_text = mod:localize("goto_presets") }
    ),
}

local legend_inputs = {
    {
        input_action        = "back",
        on_pressed_callback = "cb_on_back_pressed",
        display_name        = "loc_settings_menu_close_menu",
        alignment           = "left_alignment",
    },
}

return settings("AssignmentViewDefinitions", {
    legend_inputs         = legend_inputs,
    widget_definitions    = widget_definitions,
    scenegraph_definition = scenegraph_definition,
    num_settings          = NUM_SETTINGS,
})
