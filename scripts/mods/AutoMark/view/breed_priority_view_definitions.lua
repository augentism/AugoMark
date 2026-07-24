local mod                    = get_mod("AutoMark")

local UIWorkspaceSettings    = mod:original_require("scripts/settings/ui/ui_workspace_settings")
local ScrollbarPassTemplates = mod:original_require("scripts/ui/pass_templates/scrollbar_pass_templates")
local ButtonPassTemplates    = mod:original_require("scripts/ui/pass_templates/button_pass_templates")
local UIFontSettings         = mod:original_require("scripts/managers/ui/ui_font_settings")
local UIWidget               = mod:original_require("scripts/managers/ui/ui_widget")

local _s                     = mod:io_dofile("AutoMark/scripts/mods/AutoMark/view/breed_priority_view_settings")

local scrollbar_width        = _s.scrollbar_width
local class_grid_size        = _s.class_grid_size
local close_grid_size        = _s.close_grid_size
local far_grid_size          = _s.far_grid_size
local blur_edge              = _s.grid_blur_edge_size

-- Panel geometry (slider sizes must match the blueprints file)
local CLASS_X                = 140
local PANEL_TOP              = 250
local CLOSE_X                = 500 -- class panel right edge + gap
local FAR_X                  = CLOSE_X + close_grid_size[1] + 20
local GRID_TOP               = 310 -- below threshold slider + column headers
local SLIDER_H               = 44
local TRACK_W                = 240

local scenegraph_definition  = {
    screen = UIWorkspaceSettings.screen,

    -- left class list
    class_panel = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = class_grid_size,
        position             = { CLASS_X, PANEL_TOP, 1 },
    },

    class_grid_start = {
        vertical_alignment   = "top",
        parent               = "class_panel",
        horizontal_alignment = "left",
        size                 = { 0, 0 },
        position             = { 0, 0, 0 },
    },

    class_grid_content_pivot = {
        vertical_alignment   = "top",
        parent               = "class_grid_start",
        horizontal_alignment = "left",
        size                 = { 0, 0 },
        position             = { 0, 0, 1 },
    },

    class_grid_mask = {
        vertical_alignment   = "center",
        parent               = "class_panel",
        horizontal_alignment = "center",
        size                 = { class_grid_size[1] + blur_edge[1] * 2, class_grid_size[2] + blur_edge[2] * 2 },
        position             = { 0, 0, 0 },
    },

    class_scrollbar = {
        vertical_alignment   = "center",
        parent               = "class_panel",
        horizontal_alignment = "right",
        size                 = { scrollbar_width, class_grid_size[2] },
        position             = { 24, 0, 1 },
    },

    -- sits beside the threshold slider, clear of the class list so clicks
    -- cannot fall through onto a (masked but still interactive) class row
    copy_button = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = { far_grid_size[1], 44 },
        position             = { FAR_X, PANEL_TOP - 40, 2 },
    },

    -- title
    title_divider = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = { 335, 18 },
        position             = { CLASS_X, 145, 1 },
    },

    title_text = {
        vertical_alignment   = "bottom",
        parent               = "title_divider",
        horizontal_alignment = "left",
        size                 = { 1200, 50 },
        position             = { 0, -35, 1 },
    },

    -- right side: selected class label, distance threshold slider,
    -- close/far column headers, then the two synced slider columns
    selected_label = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = { close_grid_size[1], 32 },
        position             = { CLOSE_X, PANEL_TOP - 76, 2 },
    },

    threshold_slider = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = { close_grid_size[1], SLIDER_H },
        position             = { CLOSE_X, PANEL_TOP - 40, 2 },
    },

    close_header = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = { TRACK_W, 30 },
        position             = { CLOSE_X + close_grid_size[1] - TRACK_W, GRID_TOP - 36, 2 },
    },

    far_header = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = { TRACK_W, 30 },
        position             = { FAR_X + far_grid_size[1] - TRACK_W, GRID_TOP - 36, 2 },
    },

    breed_panel = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = close_grid_size,
        position             = { CLOSE_X, GRID_TOP, 1 },
    },

    breed_grid_start = {
        vertical_alignment   = "top",
        parent               = "breed_panel",
        horizontal_alignment = "left",
        size                 = { 0, 0 },
        position             = { 0, 0, 0 },
    },

    breed_grid_content_pivot = {
        vertical_alignment   = "top",
        parent               = "breed_grid_start",
        horizontal_alignment = "left",
        size                 = { 0, 0 },
        position             = { 0, 0, 1 },
    },

    breed_grid_mask = {
        vertical_alignment   = "center",
        parent               = "breed_panel",
        horizontal_alignment = "center",
        size                 = { close_grid_size[1] + blur_edge[1] * 2, close_grid_size[2] + blur_edge[2] * 2 },
        position             = { 0, 0, 0 },
    },

    far_panel = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = far_grid_size,
        position             = { FAR_X, GRID_TOP, 1 },
    },

    far_grid_start = {
        vertical_alignment   = "top",
        parent               = "far_panel",
        horizontal_alignment = "left",
        size                 = { 0, 0 },
        position             = { 0, 0, 0 },
    },

    far_grid_content_pivot = {
        vertical_alignment   = "top",
        parent               = "far_grid_start",
        horizontal_alignment = "left",
        size                 = { 0, 0 },
        position             = { 0, 0, 1 },
    },

    far_grid_mask = {
        vertical_alignment   = "center",
        parent               = "far_panel",
        horizontal_alignment = "center",
        size                 = { far_grid_size[1] + blur_edge[1] * 2, far_grid_size[2] + blur_edge[2] * 2 },
        position             = { 0, 0, 0 },
    },

    -- one wheel-scroll interaction area spanning both slider columns
    breed_scroll_interaction = {
        vertical_alignment   = "top",
        parent               = "screen",
        horizontal_alignment = "left",
        size                 = { FAR_X + far_grid_size[1] - CLOSE_X + scrollbar_width * 2, close_grid_size[2] + blur_edge[2] * 2 },
        position             = { CLOSE_X, GRID_TOP, 0 },
    },

    breed_scrollbar = {
        vertical_alignment   = "center",
        parent               = "far_panel",
        horizontal_alignment = "right",
        size                 = { scrollbar_width, far_grid_size[2] },
        position             = { 24, 0, 1 },
    },
}

local header_text_style = {
    font_type                 = "proxima_nova_bold",
    font_size                 = 20,
    text_color                = { 255, 220, 200, 160 },
    text_horizontal_alignment = "center",
    text_vertical_alignment   = "center",
    offset                    = { 0, 0, 2 },
}

local widget_definitions = {
    background = UIWidget.create_definition({
        { pass_type = "rect", style = { color = { 255, 0, 0, 0 } } }
    }, "screen"),

    title_divider = UIWidget.create_definition({
        { pass_type = "texture", value = "content/ui/materials/dividers/skull_rendered_left_01" }
    }, "title_divider"),

    title_text = UIWidget.create_definition({
        {
            value_id  = "text",
            style_id  = "text",
            pass_type = "text",
            value     = mod:localize("breed_priority_view_title"),
            style     = table.clone(UIFontSettings.header_1),
        }
    }, "title_text"),

    selected_label = UIWidget.create_definition({
        {
            value_id  = "text",
            pass_type = "text",
            value     = "",
            style     = {
                font_type                 = "proxima_nova_bold",
                font_size                 = 22,
                text_color                = { 255, 220, 200, 160 },
                text_horizontal_alignment = "left",
                text_vertical_alignment   = "center",
                size                      = { close_grid_size[1], 32 },
                offset                    = { 0, 0, 2 },
            },
        }
    }, "selected_label"),

    close_header = UIWidget.create_definition({
        {
            value_id  = "text",
            pass_type = "text",
            value     = mod:localize("priority_close"),
            style     = table.clone(header_text_style),
        }
    }, "close_header"),

    far_header = UIWidget.create_definition({
        {
            value_id  = "text",
            pass_type = "text",
            value     = mod:localize("priority_far"),
            style     = table.clone(header_text_style),
        }
    }, "far_header"),

    class_scrollbar = UIWidget.create_definition(ScrollbarPassTemplates.default_scrollbar, "class_scrollbar"),

    copy_button = UIWidget.create_definition(
        table.clone(ButtonPassTemplates.default_button), "copy_button",
        { original_text = mod:localize("copy_to_all_classes") }
    ),

    class_grid_mask = UIWidget.create_definition({
        {
            value     = "content/ui/materials/offscreen_masks/ui_overlay_offscreen_vertical_blur",
            pass_type = "texture",
            style     = { color = { 255, 255, 255, 255 } },
        }
    }, "class_grid_mask"),

    breed_scrollbar = UIWidget.create_definition(ScrollbarPassTemplates.default_scrollbar, "breed_scrollbar"),

    breed_grid_mask = UIWidget.create_definition({
        {
            value     = "content/ui/materials/offscreen_masks/ui_overlay_offscreen_vertical_blur",
            pass_type = "texture",
            style     = { color = { 255, 255, 255, 255 } },
        }
    }, "breed_grid_mask"),

    far_grid_mask = UIWidget.create_definition({
        {
            value     = "content/ui/materials/offscreen_masks/ui_overlay_offscreen_vertical_blur",
            pass_type = "texture",
            style     = { color = { 255, 255, 255, 255 } },
        }
    }, "far_grid_mask"),

    breed_scroll_interaction = UIWidget.create_definition({
        { pass_type = "hotspot", content_id = "hotspot" }
    }, "breed_scroll_interaction"),
}

local legend_inputs = {
    {
        input_action        = "back",
        on_pressed_callback = "cb_on_back_pressed",
        display_name        = "loc_settings_menu_close_menu",
        alignment           = "left_alignment",
    },
}

local BreedPriorityViewDefinitions = {
    legend_inputs         = legend_inputs,
    widget_definitions    = widget_definitions,
    scenegraph_definition = scenegraph_definition,
}

return settings("BreedPriorityViewDefinitions", BreedPriorityViewDefinitions)
