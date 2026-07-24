local breed_priority_view_settings = {
    scrollbar_width     = 10,
    -- left class list
    class_grid_size     = { 300, 660 },
    -- middle close-slider column and right far-slider column
    close_grid_size     = { 600, 560 },
    far_grid_size       = { 320, 560 },
    grid_spacing        = { 0, 8 },
    grid_blur_edge_size = { 8, 8 },
    shading_environment = "content/shading_environments/ui/system_menu",
}

return settings("BreedPriorityViewSettings", breed_priority_view_settings)
