local UI = require("frontiers_forge.ui")                    -- Access UI elements
local Player = require("frontiers_forge.player")            -- Access Player attributes and functions
local Util = require("frontiers_forge.util")                -- Access Utility functions
local EntityList = require("frontiers_forge.entity_list")   -- Access EntityList functions

mini_map_state = mini_map_state or {
    window_flags                = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.NoTitleBar,
    initialized                 = false,
    settings_registered         = false,

    -- Textures
    map_texture                         = nil,
    player_indicator_border_texture     = nil,
    player_indicator_fill_texture       = nil,
    
    -- Constants
    world_width         = 28000,
    world_height        = 34000,
    map_texture_width   = 14784,
    map_texture_height  = 17952,
    mini_map_width      = 150,
    mini_map_height     = 150,


    default_uv1                     = ImVec2.new(0,0),
    default_uv2                     = ImVec2.new(1,1),
    default_texture_border_color    = ImVec4.new(0,0,0,0),

    -- General Settings
    disable_compass             = true,

    -- Map Settings
    map_scale                   = 1,
    map_zoom                    = 1,
    map_texture_offset_x        = 175,
    map_texture_offset_y        = 145,
    map_border_color            = {0, 0, 0, 1}, -- Black
    map_border_thickness        = 1.0,
    show_map_border             = true,
    map_texture_tint            = {1, 1, 1, 1},

    -- Player Indicator settings
    player_indicator_width  = 24,
    player_indicator_height = 24,
    player_indicator_scale  = 1,
    player_indicator_border_color   = {0, 0, 0, 1}, -- Black
    show_player_indicator_border    = true,
    player_indicator_fill_color     = {0, 1, 0, 1}, -- Green
    show_player_indicator_fill      = true,

    -- Entity Indicator settings
    show_entities               = true,
    entity_border_color         = {0, 0, 0, 1}, -- Black
    entity_border_thickness     = 1,
    show_entity_border          = true,
    entity_radius               = 3,
    entity_red_color            = 0xFF0000FF,
    entity_yellow_color         = 0xFF00FFFF,
    entity_white_color          = 0xFFFFFFFF,
    entity_dark_blue_color      = 0xFF800000,
    entity_light_blue_color     = 0xFFFF8080,
    entity_green_color          = 0xFF00FF00,
    entity_gray_color           = 0xFF808080,
    
}

local function ScaleVec2(width, height, scale)
    return width * scale, height * scale
end

local function ToggleCompass()
    if mini_map_state.disable_compass == true then
        UI.DisableCompass()
        return
    end

    UI.EnableCompass()
end

local function DebugWindow()

end

local function DrawRotatedImage(texture, center, dimensions, angle_of_orientation, target_angle, tint)
    -- Get the draw list from ImGui
    local draw_list = ImGui.GetWindowDrawList()

    -- Calculate the relative rotation needed
    local rotation_angle = target_angle + angle_of_orientation

    -- Calculate sine and cosine of the relative rotation angle
    local cos_theta = math.cos(rotation_angle)
    local sin_theta = math.sin(rotation_angle)

    -- Half-width and half-height of the image
    local half_width = dimensions.x * 0.5
    local half_height = dimensions.y * 0.5

    -- Define the four corners of the image before rotation
    local corners = {
        ImVec2.new(-half_width, -half_height), -- Top-left
        ImVec2.new(half_width, -half_height),  -- Top-right
        ImVec2.new(half_width, half_height),   -- Bottom-right
        ImVec2.new(-half_width, half_height)  -- Bottom-left
    }

    -- Rotate each corner around the center
    for i, corner in ipairs(corners) do
        local rotated_x = corner.x * sin_theta - corner.y * cos_theta
        local rotated_y = corner.x * cos_theta + corner.y * sin_theta
        corners[i] = ImVec2.new(center.x + rotated_x, center.y + rotated_y)
    end

    -- Define UV coordinates for the image (static, as the image is not clipped here)
    local uv0 = ImVec2.new(0.0, 0.0) -- Top-left UV
    local uv1 = ImVec2.new(1.0, 0.0) -- Top-right UV
    local uv2 = ImVec2.new(1.0, 1.0) -- Bottom-right UV
    local uv3 = ImVec2.new(0.0, 1.0) -- Bottom-left UV

    -- Convert the tint color to ImGui's format
    local image_tint = ImGui.GetColorU32(tint[1], tint[2], tint[3], tint[4])

    -- Draw the image as a quad with rotation applied
    draw_list:AddImageQuad(texture, corners[1], corners[2], corners[3], corners[4], uv0, uv1, uv2, uv3, image_tint)
end

local function Initialize()
    if mini_map_state.map_texture == nil then mini_map_state.map_texture = UiForge.IGraphicsApi.CreateTextureFromFile(UiForge.resources_path .. "\\mini_map\\tunaria.jpg") end
    
    -- Original indicator image from https://cdn0.iconfinder.com/data/icons/maps-navigation-filled-line/614/3719_-_Pointer_I-512.png
    if mini_map_state.player_indicator_border_texture == nil then mini_map_state.player_indicator_border_texture = UiForge.IGraphicsApi.CreateTextureFromFile(UiForge.resources_path .. "\\mini_map\\player_indicator_border.png") end
    if mini_map_state.player_indicator_fill_texture == nil then mini_map_state.player_indicator_fill_texture = UiForge.IGraphicsApi.CreateTextureFromFile(UiForge.resources_path .. "\\mini_map\\player_indicator_fill.png") end
    ToggleCompass()

    mini_map_state.initialized = true
end

local function Settings()

    mini_map_state.map_scale    = ImGui.SliderFloat("Map Scale", mini_map_state.map_scale, 0.1, 5.0, tostring(mini_map_state.map_scale))
    mini_map_state.map_zoom     = ImGui.SliderInt("Map Zoom", mini_map_state.map_zoom, 1, 5, tostring(mini_map_state.map_zoom))
    mini_map_state.map_texture_tint     = ImGui.ColorEdit4("Map Tint", mini_map_state.map_texture_tint)

    mini_map_state.show_map_border      = ImGui.Checkbox("Show Map Border", mini_map_state.show_map_border)
    mini_map_state.map_border_color     = ImGui.ColorEdit4("Map Border Color", mini_map_state.map_border_color)
    mini_map_state.map_border_thickness = ImGui.SliderFloat("Map Border Thickness", mini_map_state.map_border_thickness, 0.1, 2, tostring(mini_map_state.map_border_thickness))

    mini_map_state.player_indicator_scale = ImGui.SliderFloat("Player Scale", mini_map_state.player_indicator_scale, 0.1, 5.0, tostring(mini_map_state.player_indicator_scale))

    mini_map_state.show_player_indicator_border    = ImGui.Checkbox("Show Player Indicator Border", mini_map_state.show_player_indicator_border)
    mini_map_state.player_indicator_border_color   = ImGui.ColorEdit4("Player Indicator Border Color", mini_map_state.player_indicator_border_color)

    mini_map_state.show_player_indicator_fill   = ImGui.Checkbox("Show Player Indicator Fill", mini_map_state.show_player_indicator_fill)
    mini_map_state.player_indicator_fill_color  = ImGui.ColorEdit4("Player Indicator Fill Color", mini_map_state.player_indicator_fill_color)

    mini_map_state.show_entities            = ImGui.Checkbox("Show Entities", mini_map_state.show_entities)
    mini_map_state.entity_radius            = ImGui.SliderFloat("Entity Size", mini_map_state.entity_radius, 1, 6, tostring(mini_map_state.entity_radius))
    
    mini_map_state.show_entity_border       = ImGui.Checkbox("Show Entity Border", mini_map_state.show_entity_border)
    mini_map_state.entity_border_thickness  = ImGui.SliderFloat("Entity Border Thickness", mini_map_state.entity_border_thickness, 0, mini_map_state.entity_radius - 1, tostring(mini_map_state.entity_border_thickness))
    mini_map_state.entity_border_color      = ImGui.ColorEdit4("Entity Border Color", mini_map_state.entity_border_color)
    -- ImGui.Text("If the mini-map seems a a little bit off,\nuse these sliders to adjust your position on the map.")
    -- mini_map_state.map_texture_offset_x    = ImGui.SliderInt("X offset", mini_map_state.map_texture_offset_x, 0, 300, tostring(mini_map_state.map_texture_offset_x))
    -- mini_map_state.map_texture_offset_y    = ImGui.SliderInt("Y offset", mini_map_state.map_texture_offset_y, 0, 300, tostring(mini_map_state.map_texture_offset_y))
    local new_val, pressed = ImGui.Checkbox("Disable Compass", mini_map_state.disable_compass)
    if pressed then
        mini_map_state.disable_compass = new_val
        ToggleCompass()
    end
end

local function RegisterSettings()
    UiForge.RegisterScriptSettings(Settings)
    mini_map_state.settings_registered = true
end

local function Render()
    -- If we are not in game or if the start menu is open, don't display minimap
    if Util.IsInGame() == 0 or Util.IsStartMenuOpen() == 1 then return end

    local state = mini_map_state -- Shortcut for readability

    if ImGui.Begin("mini map window", true, state.window_flags) then
        local cursor_x, cursor_y = ImGui.GetCursorPos()

        local scaled_mini_map_width, scaled_mini_map_height = ScaleVec2(state.mini_map_width, state.mini_map_height, state.map_scale)
        local draw_list = ImGui.GetWindowDrawList()

        -- Draw the border of the mini map
        if state.show_map_border then
            -- local line_color = ImGui.GetColorU32(state.map_border_color[1], state.map_border_color[2], state.map_border_color[3], state.map_border_color[4])
            -- local map_start_pos = ImVec2.new(cursor_x, cursor_y)
            -- local map_end_pos = ImVec2.new(cursor_x + scaled_mini_map_width, cursor_y + scaled_mini_map_height)
            -- draw_list:AddRect(map_start_pos, map_end_pos, line_color, 0, 0, state.map_border_thickness)
            -- ImGui.SetCursorPos(cursor_x, cursor_y)
        end

        -- Calculate map texture size based on zoom
        local zoomed_map_texture_width = state.map_texture_width * state.map_zoom
        local zoomed_map_texture_height = state.map_texture_height * state.map_zoom

        -- Calculate scaling factors
        local world_to_map_texture_scale_factor_x = zoomed_map_texture_width / state.world_width
        local world_to_map_texture_scale_factor_z = zoomed_map_texture_height / state.world_height

        -- Get the player's coordinates in the world
        local player_coordinates = Player.GetCoordinates()

        -- This one is harder to explain... but if there are discrepencies between the image and the 
        -- world in terms of origin point, we have to apply an offset to fix it.
        -- Currently not in use, but keeping it here just in case I want to add the feature back in
        -- to offset the map ever.
        local zoomed_map_texture_offset_x = 0
        local zoomed_map_texture_offset_y = 0

        -- Convert the player's world coordinates to map texture coordinates
        local player_map_texture_x = player_coordinates.x * world_to_map_texture_scale_factor_x - zoomed_map_texture_offset_x
        local player_map_texture_z = player_coordinates.z * world_to_map_texture_scale_factor_z - zoomed_map_texture_offset_y

        -- Calculate the portion of the map to display, centering around the player
        local half_mini_map_width = scaled_mini_map_width / 2
        local half_mini_map_height = scaled_mini_map_height / 2
        local map_clip_x_start = player_map_texture_x - half_mini_map_width
        local map_clip_y_start = player_map_texture_z - half_mini_map_height

        -- Calculate UV coordinates for the map texture
        local uv0_x = map_clip_x_start / zoomed_map_texture_width
        local uv0_y = map_clip_y_start / zoomed_map_texture_height
        local uv1_x = (map_clip_x_start + scaled_mini_map_width) / zoomed_map_texture_width
        local uv1_y = (map_clip_y_start + scaled_mini_map_height) / zoomed_map_texture_height

        -- Render the map image within the mini map
        local map_tint = ImVec4.new(state.map_texture_tint[1], state.map_texture_tint[2], state.map_texture_tint[3], state.map_texture_tint[4])
        ImGui.SetCursorPos(cursor_x, cursor_y)
        ImGui.Image(state.map_texture, ImVec2.new(scaled_mini_map_width, scaled_mini_map_height),
                    ImVec2.new(uv0_x, uv0_y), ImVec2.new(uv1_x, uv1_y), map_tint, state.default_texture_border_color)

        
        -- Render entities
        ImGui.SetCursorPos(cursor_x, cursor_y)
        local window_pos = {}
        window_pos.x, window_pos.y = ImGui.GetCursorScreenPos()

        local mini_map_center = ImVec2.new(window_pos.x + half_mini_map_width, window_pos.y + half_mini_map_height)
        local entity_list = EntityList.GetAllEntities()
        table.remove(entity_list, 1) -- The first entity is the player -- toss it

        ImGui.PushClipRect(window_pos.x, window_pos.y, window_pos.x + scaled_mini_map_width, window_pos.y + scaled_mini_map_height, true)
        for _, entity in pairs(entity_list) do
            -- Calculate the entity's position on the mini-map
            local entity_map_x = entity.x * world_to_map_texture_scale_factor_x
            local entity_map_z = entity.z * world_to_map_texture_scale_factor_z
            local distance = {x = entity_map_x - player_map_texture_x, z = entity_map_z - player_map_texture_z }
            local circle_center = ImVec2.new(mini_map_center.x + distance.x, mini_map_center.y + distance.z)
            local entity_color = state.entity_white_color
            local player_level = Player.GetLevel()
            if      entity.level - 2    >   player_level then entity_color = state.entity_red_color
            elseif  entity.level - 1    >=  player_level then entity_color = state.entity_yellow_color
            elseif  entity.level        ==  player_level then entity_color = state.entity_white_color
            elseif  entity.level + 1    ==  player_level then entity_color = state.entity_dark_blue_color
            elseif  entity.level + 2    ==  player_level then entity_color = state.entity_light_blue_color
            elseif  entity.level + 5    <=  player_level then entity_color = state.entity_gray_color
            elseif  entity.level + 3    <=  player_level then entity_color = state.entity_green_color
            end

            draw_list:AddCircleFilled(circle_center, state.entity_radius, entity_color)
            if state.show_entity_border == true then 
                local border_color = ImGui.GetColorU32( state.entity_border_color[1],
                                                        state.entity_border_color[2],
                                                        state.entity_border_color[3],
                                                        state.entity_border_color[4])
                draw_list:AddCircle(circle_center, state.entity_radius, border_color, 0, state.entity_border_thickness)
            end
            
            -- Render a tooltip when mousing over an entity
            local mouse_x, mouse_y = ImGui.GetMousePos()
            local distance_squared = (mouse_x - circle_center.x)^2 + (mouse_y - circle_center.y)^2
            if distance_squared <= state.entity_radius^2 then
                ImGui.BeginTooltip()
                ImGui.Text(entity.name .. "(" .. entity.level .. ")\n" ..
                        "ID: " .. entity.id .. "\n" ..
                        string.format("Coordinates: %.2f, %.2f, %.2f", entity.x, entity.y, entity.z))
                ImGui.EndTooltip()
            end
        end
        ImGui.PopClipRect()

        -- Render player
        ImGui.SetCursorPos(cursor_x, cursor_y)
        local player_indicator_dimensions = ImVec2.new(state.player_indicator_width * state.player_indicator_scale, state.player_indicator_height * state.player_indicator_scale)
        if state.show_player_indicator_border then
            local angle_of_texture_orientation = (math.pi / 2) -- The arrow is pointing up, so we need to account for that when drawing it
            DrawRotatedImage(state.player_indicator_border_texture, mini_map_center, player_indicator_dimensions, angle_of_texture_orientation, Util.GetCompassRadians(), state.player_indicator_border_color)
        end

        if state.show_player_indicator_fill then
            local angle_of_texture_orientation = (math.pi / 2) -- The arrow is pointing up, so we need to account for that when drawing it
            DrawRotatedImage(state.player_indicator_fill_texture, mini_map_center, player_indicator_dimensions, angle_of_texture_orientation, Util.GetCompassRadians(), state.player_indicator_fill_color)
        end

        -- Uncomment this if you want to see an extra debug window
        -- if ImGui.Begin("mini_map debug") then
        --     ImGui.Text("World Dimensions:               " .. state.world_width .. " x " .. state.world_height)
        --     ImGui.Text("World Center Coord:             " .. tostring(state.world_width / 2) .. ", " .. tostring(state.world_height / 2))
        --     ImGui.Text("World to map scale factor x:    " .. tostring(world_to_map_texture_scale_factor_x))
        --     ImGui.Text("World to map scale factor y:    " .. tostring(world_to_map_texture_scale_factor_z))
        --     ImGui.Spacing()
        --     ImGui.Text("Player World Coords:            " .. tostring(player_coordinates.x) .. ", " .. tostring(player_coordinates.z))
        --     ImGui.Text("Player Map Coords:              " .. tostring(player_map_texture_x) .. ", " .. tostring(player_map_texture_z))
        --     ImGui.Spacing()
        --     ImGui.Text("Map Texture Center Coord:       " .. tostring(zoomed_map_texture_width / 2) .. ", " .. tostring(zoomed_map_texture_height / 2))
        --     ImGui.Text("Map Clip Coords:                " .. tostring(map_clip_x_start) .. ", " .. tostring(map_clip_y_start))
        --     ImGui.Text("UV0:                            " .. tostring(uv0_x) .. ", " .. tostring(uv0_y))
        --     ImGui.Text("UV1:                            " .. tostring(uv1_x) .. ", " .. tostring(uv1_y))
        --     ImGui.Text("UV0 Coords:                     " .. tostring(zoomed_map_texture_width * uv0_x) .. ", " .. tostring(zoomed_map_texture_height * uv0_y))
        --     ImGui.Text("UV1 Coords:                     " .. tostring(zoomed_map_texture_width * uv1_x) .. ", " .. tostring(zoomed_map_texture_height * uv1_y))
        --     ImGui.Spacing()
        --     ImGui.Text("Mini Map Dimensions:            " .. tostring(scaled_mini_map_width) .. " x " .. tostring(scaled_mini_map_height))
        --     ImGui.Text("Half Mini Map Dimensions:       " .. tostring(half_mini_map_width) .. " x " .. tostring(half_mini_map_height))
        --     for _, entity in pairs(entity_list) do
        --         -- Display the tree node with the entity name and ID
        --         if ImGui.TreeNode(entity.name .. " (ID: " .. entity.id .. ")") then
        --             -- Inside the tree node, show the entity stats
        --             ImGui.Text("Name: " .. entity.name)
        --             ImGui.Text("ID: " .. entity.id)
        --             ImGui.Text("Level: " .. entity.level)
        --             ImGui.Text("HP: " .. entity.percent_hp .. "%")
        --             ImGui.Text(string.format("Coordinates: x = %.2f, y = %.2f, z = %.2f", entity.x, entity.y, entity.z))
        --             -- End the tree node
        --             ImGui.TreePop()
        --         end
        --     end
        -- end
        -- ImGui.End()
        -- Additional logic for rendering entities can be added here...
    end
    ImGui.End()
end



-- Creating a local variable to interact with the global table so that the name is shorter/easier to use
local state = mini_map_state

if state.initialized == false then Initialize() end

if state.settings_registered == false then RegisterSettings() end

if state.initialized then Render() end