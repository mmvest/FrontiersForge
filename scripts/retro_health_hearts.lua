local UI = require("frontiers_forge.ui")                -- Access UI elements
local Player = require("frontiers_forge.player")        -- Access Player attributes and functions
local Util = require("frontiers_forge.util")            -- Access Utility functions

-- Creating a long, specific table name so that I (hopefully) avoid naming collisions
retro_health_hearts_state = retro_health_hearts_state or {
    window_flags                = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.NoTitleBar,
    initialized                 = false,
    callbacks_registered         = false,

    -- textures
    heart_accent_texture        = nil,
    heart_border_texture        = nil,
    heart_fill_texture          = nil,
    heart_highlight_texture     = nil,

    -- settings
    heart_accent_tint           = {1, 1, 1, 1},                     -- white
    heart_border_tint           = {0, 0, 0, 1},                     -- black
    heart_fill_tint             = {0.9059, 0.0039, 0.0157, 1.0},    -- deep red
    heart_highlight_tint        = {1, 1, 1, 1},                     -- white

    show_accent                 = false,
    show_border                 = true,

    heart_count                 = 5,
    heart_scale                 = 1,
    heart_spacing               = 8,
    heart_width                 = 32,
    heart_height                = 32,

    disable_default_health_bar  = true,

    -- default values for displaying textures
    default_uv1                     = ImVec2.new(0,0),
    default_uv2                     = ImVec2.new(1,1),
    default_texture_border_color    = ImVec4.new(0,0,0,0),
}

local function ScaleDimensions(width, height, scale)
    return width * scale, height * scale
end

local function ToggleDefaultHealthBar()
    if retro_health_hearts_state.disable_default_health_bar == true then
        UI.DisableHealthBar()
        return
    end

    UI.EnableHealthBar()
end

local function Initialize()
    -- Original image textures from https://i.pinimg.com/originals/e4/e0/0c/e4e00c436088960d185455d8751af322.jpg
    -- I split it apart into separate components using GIMP
    if retro_health_hearts_state.heart_accent_texture == nil then retro_health_hearts_state.heart_accent_texture = UiForge.IGraphicsApi.CreateTextureFromFile(UiForge.resources_path .. "\\retro_health_hearts\\heart_accent.png") end
    
    if retro_health_hearts_state.heart_border_texture == nil then retro_health_hearts_state.heart_border_texture = UiForge.IGraphicsApi.CreateTextureFromFile(UiForge.resources_path .. "\\retro_health_hearts\\heart_border.png") end
    
    if retro_health_hearts_state.heart_fill_texture == nil then retro_health_hearts_state.heart_fill_texture = UiForge.IGraphicsApi.CreateTextureFromFile(UiForge.resources_path .. "\\retro_health_hearts\\heart_fill.png") end
    
    if retro_health_hearts_state.heart_highlight_texture == nil then retro_health_hearts_state.heart_highlight_texture = UiForge.IGraphicsApi.CreateTextureFromFile(UiForge.resources_path .. "\\retro_health_hearts\\heart_highlight.png") end
    
    ToggleDefaultHealthBar()

    retro_health_hearts_state.initialized = true
end

local function Settings()

    retro_health_hearts_state.heart_count           = ImGui.SliderInt("Count", retro_health_hearts_state.heart_count, 1, 25, tostring(retro_health_hearts_state.heart_count))
    retro_health_hearts_state.heart_scale           = ImGui.SliderFloat("Scale", retro_health_hearts_state.heart_scale, 0.1, 5.0, tostring(retro_health_hearts_state.heart_scale))
    retro_health_hearts_state.heart_spacing         = ImGui.SliderInt("Spacing", retro_health_hearts_state.heart_spacing, 0, 50, tostring(retro_health_hearts_state.heart_spacing))

    retro_health_hearts_state.show_accent           = ImGui.Checkbox("Show Accent", retro_health_hearts_state.show_accent)
    retro_health_hearts_state.heart_accent_tint     = ImGui.ColorEdit4("Accent Tint", retro_health_hearts_state.heart_accent_tint)

    retro_health_hearts_state.show_border           = ImGui.Checkbox("Show Border", retro_health_hearts_state.show_border)
    retro_health_hearts_state.heart_border_tint     = ImGui.ColorEdit4("Border Tint", retro_health_hearts_state.heart_border_tint)

    retro_health_hearts_state.heart_fill_tint       = ImGui.ColorEdit4("Fill Tint", retro_health_hearts_state.heart_fill_tint)

    retro_health_hearts_state.heart_highlight_tint  = ImGui.ColorEdit4("Highlight Tint", retro_health_hearts_state.heart_highlight_tint)

    local new_val, pressed = ImGui.Checkbox("Disable Default Health Bar", retro_health_hearts_state.disable_default_health_bar)
    if pressed then
        retro_health_hearts_state.disable_default_health_bar = new_val
        ToggleDefaultHealthBar();
    end
end

local function OnDisable()
    UI.EnableHealthBar()
end

local function RegisterCallbacks()
    UiForge.RegisterCallback(UiForge.CallbackType.Settings, Settings)
    UiForge.RegisterCallback(UiForge.CallbackType.DisableScript, OnDisable)
    retro_health_hearts_state.callbacks_registered = true
end

local function Render()
    -- If we are not in game or if the start menu is open, don't display the hearts
    if Util.IsInGame() == 0 or Util.IsStartMenuOpen() == 1 then return end

    local state = retro_health_hearts_state     -- Makes code easier to read by cutting down the clutter caused by using a large variable name a bunch

    if ImGui.Begin("retro health hearts window", true, state.window_flags) then
        local scaled_width, scaled_height = ScaleDimensions(state.heart_width, state.heart_height, state.heart_scale)
        local dimensions = ImVec2.new(scaled_width, scaled_height)
        local start_cursor_x, start_cursor_y = ImGui.GetCursorPos() -- Get the original cursor position

        -- Draw Accents, Borders, Highlights
        for idx = 1, state.heart_count do
            local cursor_x, cursor_y = ImGui.GetCursorPos()
            if state.show_accent then
                local tint = ImVec4.new(state.heart_accent_tint[1], state.heart_accent_tint[2], state.heart_accent_tint[3], state.heart_accent_tint[4])
                ImGui.Image(state.heart_accent_texture, dimensions, state.default_uv1, state.default_uv2, tint, state.default_texture_border_color)
            end

            if state.show_border then
                ImGui.SetCursorPos(cursor_x, cursor_y)
                local tint = ImVec4.new(state.heart_border_tint[1], state.heart_border_tint[2], state.heart_border_tint[3], state.heart_border_tint[4])
                ImGui.Image(state.heart_border_texture, dimensions, state.default_uv1, state.default_uv2, tint, state.default_texture_border_color)
            end

            ImGui.SetCursorPos(cursor_x, cursor_y)
            local tint = ImVec4.new(state.heart_highlight_tint[1], state.heart_highlight_tint[2], state.heart_highlight_tint[3], state.heart_highlight_tint[4])
            ImGui.Image(state.heart_highlight_texture, dimensions, state.default_uv1, state.default_uv2, tint, state.default_texture_border_color)

            ImGui.SameLine(0, state.heart_spacing)
        end

        -- Percentage per heart
        local health_percent = Player.GetCurrentHp() / Player.GetMaxHp()
        local total_width = (scaled_width * state.heart_count) + (state.heart_spacing * state.heart_count)
        local percentage_health_per_heart = 1 / state.heart_count
        local percentage_width_per_heart = scaled_width / total_width
        local percentage_width_per_space = state.heart_spacing / total_width
        local hearts_to_fill = health_percent / percentage_health_per_heart
        local full_hearts = math.floor(hearts_to_fill)
        local partial_heart = hearts_to_fill % 1 -- This will give us the percentage of the partial heart
        local fill_percent = (full_hearts * (percentage_width_per_heart + percentage_width_per_space)) -- Full hearts + spaces
        if partial_heart > 0 then
            fill_percent = fill_percent + (partial_heart * percentage_width_per_heart) -- Add the partial heart width
        end
        
        

        ImGui.SetCursorPos(start_cursor_x, start_cursor_y)
        local clip_start_x, clip_start_y    = ImGui.GetCursorScreenPos()
        local clip_end_x                    = clip_start_x + (scaled_width + state.heart_spacing) * state.heart_count * fill_percent
        local clip_end_y                    = clip_start_y + scaled_height

        ImGui.PushClipRect(clip_start_x, clip_start_y, clip_end_x, clip_end_y, true)

        -- Render fill textures
        for idx = 1, state.heart_count do
            local cursor_x, cursor_y = ImGui.GetCursorPos()
            ImGui.SetCursorPos(cursor_x, cursor_y)
            local tint = ImVec4.new(state.heart_fill_tint[1], state.heart_fill_tint[2], state.heart_fill_tint[3], state.heart_fill_tint[4])
            ImGui.Image(state.heart_fill_texture, dimensions, state.default_uv1, state.default_uv2, tint, state.default_texture_border_color)
            ImGui.SameLine(0, state.heart_spacing)
        end

        ImGui.PopClipRect()
    end
    ImGui.End()
end


-- Creating a local variable to interact with the global table so that the name is shorter/easier to use
local state = retro_health_hearts_state

if state.initialized == false then Initialize() end

if state.callbacks_registered == false then RegisterCallbacks() end

if state.initialized then Render() end
