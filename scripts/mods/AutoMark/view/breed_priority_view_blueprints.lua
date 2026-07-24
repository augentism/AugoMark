local mod                 = get_mod("AutoMark")

local UISoundEvents       = mod:original_require("scripts/settings/ui/ui_sound_events")
local UIFontSettings      = mod:original_require("scripts/managers/ui/ui_font_settings")
local ButtonPassTemplates = mod:original_require("scripts/ui/pass_templates/button_pass_templates")
local SliderPassTemplates = mod:original_require("scripts/ui/pass_templates/slider_pass_templates")

-- Engine drag-slider passes. The area left of the track shows `value_text`
-- ("Breed Name  12"). Geometry must match the definitions file.
-- Close sliders carry the breed label; far sliders sit next to them on the
-- same line and only show the number.
-- value_slider's third arg is the LABEL area width; the track gets the
-- remainder. Both columns end up with a 240px track.
local CLOSE_SLIDER_W      = 600
local FAR_SLIDER_W        = 320
local SLIDER_H            = 44
local CLOSE_LABEL_W       = 360
local FAR_LABEL_W         = 80

local close_slider_passes = SliderPassTemplates.value_slider(CLOSE_SLIDER_W, SLIDER_H, CLOSE_LABEL_W, true)
local far_slider_passes   = SliderPassTemplates.value_slider(FAR_SLIDER_W, SLIDER_H, FAR_LABEL_W, true)

local CLASS_ROW_W         = 300
local HEADER_H            = 36

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

local blueprints          = {
    -- Selectable class row in the left list.
    class_row = {
        size = { CLASS_ROW_W, 64 },

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
    },

    -- Category header row in the close-slider column.
    category_header = {
        size = { CLOSE_SLIDER_W, HEADER_H },

        pass_template = {
            {
                pass_type = "texture",
                value     = "content/ui/materials/dividers/skull_rendered_left_01",
                style     = {
                    vertical_alignment = "bottom",
                    size               = { 335, 18 },
                    offset             = { 0, 0, 1 },
                },
            },
            {
                pass_type = "text",
                value_id  = "text",
                value     = "",
                style     = {
                    font_type                 = "proxima_nova_bold",
                    font_size                 = 22,
                    text_color                = { 255, 255, 200, 120 },
                    text_horizontal_alignment = "left",
                    text_vertical_alignment   = "center",
                    offset                    = { 10, -6, 2 },
                },
            },
        },
    },

    -- Invisible spacer row keeping the far-slider column aligned with a
    -- category header in the close column.
    row_spacer = {
        size = { FAR_SLIDER_W, HEADER_H },

        pass_template = {
            { pass_type = "rect", style = { color = { 0, 0, 0, 0 } } },
        },
    },
}

return settings("BreedPriorityViewBlueprints", {
    blueprints          = blueprints,
    close_slider_passes = close_slider_passes,
    far_slider_passes   = far_slider_passes,
    close_slider_size   = { CLOSE_SLIDER_W, SLIDER_H },
    far_slider_size     = { FAR_SLIDER_W, SLIDER_H },
    header_size         = { CLOSE_SLIDER_W, HEADER_H },
    spacer_size         = { FAR_SLIDER_W, HEADER_H },
})
