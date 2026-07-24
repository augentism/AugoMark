local mod                 = get_mod("AutoMark")

local UISoundEvents       = mod:original_require("scripts/settings/ui/ui_sound_events")
local UIFontSettings      = mod:original_require("scripts/managers/ui/ui_font_settings")
local ButtonPassTemplates = mod:original_require("scripts/ui/pass_templates/button_pass_templates")
local SliderPassTemplates = mod:original_require("scripts/ui/pass_templates/slider_pass_templates")

-- Selectable-row geometry (class list and preset list share this blueprint)
local ROW_W               = 300
local ROW_H               = 64

-- Class-settings panel controls
local SETTING_W           = 440
local SETTING_H           = 44
local SLIDER_LABEL_W      = 260
local CHECKBOX_BOX        = 28

local setting_slider_passes = SliderPassTemplates.value_slider(SETTING_W, SETTING_H, SLIDER_LABEL_W, true)

local hotspot_style       = {
    on_hover_sound   = UISoundEvents.default_mouse_hover,
    on_pressed_sound = UISoundEvents.default_click,
}

local text_style          = table.clone(UIFontSettings.list_button)
text_style.offset[1]      = 10
text_style.offset[2]      = -10
text_style.font_size      = 20

local text_style2         = table.clone(UIFontSettings.list_button_second_row)
text_style2.offset[1]     = 10
text_style2.offset[2]     = 22

local checkbox_label_style = {
    font_type                 = "proxima_nova_bold",
    font_size                 = 20,
    text_color                = { 255, 220, 200, 200 },
    text_horizontal_alignment = "left",
    text_vertical_alignment   = "center",
    offset                    = { CHECKBOX_BOX + 16, 0, 2 },
}

local selectable_row = {
    size = { ROW_W, ROW_H },

    pass_template = {
        {
            style_id   = "hotspot",
            pass_type  = "hotspot",
            content_id = "hotspot",
            content    = { use_is_focused = true },
            style      = hotspot_style,
        },
        {
            pass_type = "texture",
            style_id  = "background_selected",
            value     = "content/ui/materials/buttons/background_selected",
            style     = { color = Color.ui_terminal(0, true), offset = { 0, 0, 0 } },
            change_function = function(content, style)
                local base = 255 * content.hotspot.anim_select_progress
                style.color[1] = content.is_selected and 255 or base
            end,
            visibility_function = ButtonPassTemplates.list_button_focused_visibility_function,
        },
        {
            pass_type = "texture",
            style_id  = "highlight",
            value     = "content/ui/materials/frames/hover",
            style     = {
                hdr = true, scale_to_material = true,
                color = Color.ui_terminal(255, true), offset = { 0, 0, 3 }, size_addition = { 0, 0 },
            },
            change_function     = ButtonPassTemplates.list_button_highlight_change_function,
            visibility_function = ButtonPassTemplates.list_button_focused_visibility_function,
        },
        {
            pass_type = "text", style_id = "text", value_id = "text",
            style = table.clone(text_style),
            change_function = ButtonPassTemplates.list_button_label_change_function,
        },
        {
            pass_type = "text", style_id = "text2", value_id = "text2",
            style = table.clone(text_style2),
            change_function = ButtonPassTemplates.list_button_label_change_function,
        },
    },

    init = function(parent, widget, entry, callback_name)
        local content = widget.content
        content.hotspot.pressed_callback = function()
            callback(parent, callback_name, widget, entry)()
        end
        content.text  = entry.title
        content.text2 = entry.subtitle
        content.entry = entry
    end,
}

-- Checkbox: clickable box + inner fill (content.value) + label
local checkbox = {
    size = { SETTING_W, SETTING_H },

    pass_template = {
        {
            style_id   = "hotspot",
            pass_type  = "hotspot",
            content_id = "hotspot",
            style      = hotspot_style,
        },
        {
            pass_type = "texture",
            value     = "content/ui/materials/buttons/background_selected",
            style     = {
                horizontal_alignment = "left",
                vertical_alignment   = "center",
                size                 = { CHECKBOX_BOX, CHECKBOX_BOX },
                offset               = { 0, 0, 1 },
                color                = { 120, 40, 30, 20 },
            },
        },
        {
            pass_type = "texture",
            value     = "content/ui/materials/buttons/background_selected",
            style     = {
                horizontal_alignment = "left",
                vertical_alignment   = "center",
                size                 = { CHECKBOX_BOX - 8, CHECKBOX_BOX - 8 },
                offset               = { 4, 0, 2 },
                color                = { 255, 220, 170, 90 },
            },
            visibility_function = function(content)
                return content.value == true
            end,
        },
        {
            pass_type = "text", value_id = "text",
            value = "",
            style = table.clone(checkbox_label_style),
        },
    },

    init = function(parent, widget, entry, callback_name)
        local content = widget.content
        content.value = entry.value
        content.text  = entry.title
        content.entry = entry
        content.hotspot.pressed_callback = function()
            callback(parent, callback_name, widget, entry)()
        end
    end,
}

local blueprints = {
    selectable_row = selectable_row,
    checkbox       = checkbox,
}

return settings("AssignmentViewBlueprints", {
    blueprints            = blueprints,
    setting_slider_passes = setting_slider_passes,
    setting_size          = { SETTING_W, SETTING_H },
    row_size              = { ROW_W, ROW_H },
})
