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
    disable_compass             = false,
    disable_in_start_menu       = false,

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

    -- Entity Tracking
    entity_tracking_enabled     = false,
    ping_tracked_entities       = false,
    line_to_tracked_entities    = false,
    tracked_entity_input        = "",
    tracked_entities            = {},
    tracked_entities_by_key     = {},
    tracked_entities_index_dirty= true,
    tracked_entities_loaded     = false,
    tracked_entities_status     = "",
    tracked_entities_file_name  = "minimap_tracked_entities.entl",
    tracked_entities_file_name_buffer = "minimap_tracked_entities.entl",
    tracked_entities_available_lists = {},
    tracked_entities_lists_status = "",
    _tracked_entities_combo_was_open = false,
    
}

--[[
Entity tracking system

The mini-map always renders "all nearby entities" from the game. Entity tracking is an *optional* layer on top that
lets you highlight a small, user-managed list of entity names (e.g., "Grass Snake", "Hatchling", "Lionwere").

- `tracked_entities` is the saved list (array) of entries the user is tracking. Each entry stores its display `name`,
a normalized `key` (lowercased name + trimmed), an `enabled` flag, and optional per-entity colors.

- `tracked_entities_by_key` is a fast lookup table: normalized name -> index in `tracked_entities`. This avoids scanning
  the list every frame and prevents duplicates.

- When tracking is enabled, each rendered entity name is normalized and looked up in `tracked_entities_by_key` to decide
  whether it should be highlighted / pinged / have a line drawn to it.
]]
mini_map_state.entity_tracking_enabled  = mini_map_state.entity_tracking_enabled or false
mini_map_state.ping_tracked_entities    = mini_map_state.ping_tracked_entities or false
mini_map_state.line_to_tracked_entities = mini_map_state.line_to_tracked_entities or false
mini_map_state.tracked_entity_input     = mini_map_state.tracked_entity_input or ""
mini_map_state.tracked_entities         = mini_map_state.tracked_entities or {}
mini_map_state.tracked_entities_by_key  = mini_map_state.tracked_entities_by_key or {}
mini_map_state.tracked_entities_index_dirty = (mini_map_state.tracked_entities_index_dirty ~= false)
mini_map_state.tracked_entities_loaded  = mini_map_state.tracked_entities_loaded or false
mini_map_state.tracked_entities_status  = mini_map_state.tracked_entities_status or ""
mini_map_state.tracked_entities_file_name = mini_map_state.tracked_entities_file_name or "minimap_tracked_entities.entl"
mini_map_state.tracked_entities_file_name_buffer = mini_map_state.tracked_entities_file_name_buffer or mini_map_state.tracked_entities_file_name
mini_map_state.tracked_entities_available_lists = mini_map_state.tracked_entities_available_lists or {}
mini_map_state.tracked_entities_lists_status = mini_map_state.tracked_entities_lists_status or ""
mini_map_state._tracked_entities_combo_was_open = mini_map_state._tracked_entities_combo_was_open or false

local function ScaleVec2(width, height, scale)
    return width * scale, height * scale
end

local function Trim(str)
    if str == nil then return "" end

    -- Convert to string, then strip leading (^%s+) and trailing (%s+$) whitespace via gsub.
    return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NormalizeEntityName(name)
    return Trim(name):lower()
end

local function RebuildTrackedEntitiesIndex()
    mini_map_state.tracked_entities_by_key = {}
    
    -- We want O(1) lookups from entity name to tracked entry while rendering (so we don't scan the list every frame).
    -- We also normalize names (trim/lowercase) so " Goblin " and "goblin" point to the same tracked entry.
    for tracked_list_index, entry in ipairs(mini_map_state.tracked_entities) do
        entry.name = Trim(entry.name)
        entry.key = NormalizeEntityName(entry.name)
        mini_map_state.tracked_entities_by_key[entry.key] = tracked_list_index

        if entry.enabled == nil then entry.enabled = true end
        if entry.fill_color == nil then entry.fill_color = {1, 1, 0, 1} end
        if entry.border_color == nil then entry.border_color = {1, 1, 1, 1} end
    end

    mini_map_state.tracked_entities_index_dirty = false
end

-- We want to avoid rebuilding the tracked entities list every frame, so we check if
-- the tracked entities index is dirty. If it is, then we rebuild the index.
local function EnsureTrackedEntitiesIndex()
    if mini_map_state.tracked_entities_index_dirty == true then
        RebuildTrackedEntitiesIndex()
    end
end

local function SanitizeFileName(file_name)
    file_name = Trim(file_name)
    if file_name == "" then
        file_name = "minimap_tracked_entities.entl"
    end

    -- Avoid invalid Windows filename characters. This isn't a comprehensive solution...
    -- just don't be dumb with file names
    file_name = file_name:gsub("[\\\\/:%*%?\"<>|]", "_")

    local lower = file_name:lower()
    if lower:match("%.entl$") then
        return file_name
    end

    -- If the user types ".txt" out of habit, normalize it.
    if lower:match("%.txt$") then
        return file_name:sub(1, #file_name - 4) .. ".entl"
    end

    return file_name .. ".entl"
end

local function GetTrackedEntitiesFilePath()
    local file_name = SanitizeFileName(mini_map_state.tracked_entities_file_name)
    return UiForge.resources_path .. "\\mini_map\\" .. file_name
end

local function Clamp01(value)
    value = tonumber(value)
    if value == nil then return nil end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function ParseBool(value)
    value = Trim(value):lower()
    return (value == "true" or value == "1" or value == "yes" or value == "on")
end

local function CsvEscapeField(value)
    value = tostring(value or "")

    -- When saving to CSV we must quote fields that could break parsing:
    -- - commas/newlines (they would look like separators/extra rows)
    -- - quotes (they must be escaped as doubled quotes per CSV rules)
    -- - leading/trailing spaces
    if value:find("[\",\n\r]") or value:find("^%s") or value:find("%s$") then
        value = value:gsub("\"", "\"\"")
        return "\"" .. value .. "\""
    end
    return value
end

local function CsvParseLine(line)
    -- Minimal CSV parser that:
    -- - splits on commas, except when inside quotes
    -- - supports escaped quotes ("") inside quoted fields
    local parsed_fields = {}
    local current_field = ""
    local is_in_quotes = false
    local position = 1
    local line_length = #line

    while position <= line_length do
        local char = line:sub(position, position)
        if is_in_quotes then
            if char == "\"" then
                -- If we see a doubled quote ("") while in quotes, that represents a literal quote character.
                if position < line_length and line:sub(position + 1, position + 1) == "\"" then
                    current_field = current_field .. "\""
                    position = position + 1
                else
                    is_in_quotes = false
                end
            else
                current_field = current_field .. char
            end
        else
            if char == "," then
                parsed_fields[#parsed_fields + 1] = current_field
                current_field = ""
            elseif char == "\"" then
                is_in_quotes = true
            else
                current_field = current_field .. char
            end
        end
        position = position + 1
    end

    parsed_fields[#parsed_fields + 1] = current_field
    return parsed_fields
end

local function AddTrackedEntity(name)
    EnsureTrackedEntitiesIndex()

    name = Trim(name)
    if name == "" then return end

    local key = NormalizeEntityName(name)
    if mini_map_state.tracked_entities_by_key[key] ~= nil then
        mini_map_state.tracked_entities_status = "Already tracking: " .. name
        return
    end

    mini_map_state.tracked_entities[#mini_map_state.tracked_entities + 1] = {
        name = name,
        key = key,
        enabled = true,
        fill_color = {1, 1, 0, 1},
        border_color = {1, 1, 1, 1},
    }

    mini_map_state.tracked_entities_index_dirty = true
    RebuildTrackedEntitiesIndex()
    mini_map_state.tracked_entities_status = "Added: " .. name
end

local function RemoveTrackedEntityAtIndex(index)
    table.remove(mini_map_state.tracked_entities, index)
    mini_map_state.tracked_entities_index_dirty = true
    RebuildTrackedEntitiesIndex()
end

local function ClearTrackedEntities()
    mini_map_state.tracked_entities = {}
    mini_map_state.tracked_entities_index_dirty = true
    RebuildTrackedEntitiesIndex()
    mini_map_state.tracked_entities_status = "Cleared all tracked entities"
end

-- Saves the current tracked entity list to an `.entl` file under `resources\\mini_map`.
local function SaveTrackedEntitiesToFile()
    EnsureTrackedEntitiesIndex()

    local path = GetTrackedEntitiesFilePath()
    local file = io.open(path, "w")
    if file == nil then
        mini_map_state.tracked_entities_status = "Failed to write: " .. path
        return false
    end

    file:write("# minimap_tracked_entities.entl\n")
    file:write("# One entity per line (CSV): name,enabled,fillR,fillG,fillB,fillA,borderR,borderG,borderB,borderA\n")

    for _, entry in ipairs(mini_map_state.tracked_entities) do
        local parts = {
            CsvEscapeField(entry.name),
            (entry.enabled and "true" or "false"),
            tostring(entry.fill_color[1]), tostring(entry.fill_color[2]), tostring(entry.fill_color[3]), tostring(entry.fill_color[4]),
            tostring(entry.border_color[1]), tostring(entry.border_color[2]), tostring(entry.border_color[3]), tostring(entry.border_color[4]),
        }
        file:write(table.concat(parts, ","), "\n")
    end

    file:close()
    mini_map_state.tracked_entities_status = "Saved: " .. path
    return true
end

-- Loads a tracked entity list from an `.entl` file under `resources\\mini_map`.
local function LoadTrackedEntitiesFromFile()
    local path = GetTrackedEntitiesFilePath()
    local file = io.open(path, "r")
    if file == nil then
        mini_map_state.tracked_entities_status = "No tracked entities file found"
        return false
    end

    local loaded = {}

    for line in file:lines() do
        local trimmed = Trim(line)
        if trimmed ~= "" and not trimmed:match("^#") then
            local fields = CsvParseLine(trimmed)
            if #fields >= 2 then
                local name = Trim(fields[1])
                if name ~= "" then
                    local enabled = ParseBool(fields[2])
                    local fill = {1, 1, 0, 1}
                    local border = {1, 1, 1, 1}

                    if #fields >= 10 then
                        local fr = Clamp01(fields[3]); local fg = Clamp01(fields[4]); local fb = Clamp01(fields[5]); local fa = Clamp01(fields[6])
                        local br = Clamp01(fields[7]); local bg = Clamp01(fields[8]); local bb = Clamp01(fields[9]); local ba = Clamp01(fields[10])

                        if fr and fg and fb and fa then fill = {fr, fg, fb, fa} end
                        if br and bg and bb and ba then border = {br, bg, bb, ba} end
                    end

                    loaded[#loaded + 1] = {
                        name = name,
                        enabled = enabled,
                        fill_color = fill,
                        border_color = border,
                    }
                end
            end
        end
    end

    file:close()

    mini_map_state.tracked_entities = loaded
    mini_map_state.tracked_entities_index_dirty = true
    RebuildTrackedEntitiesIndex()
    mini_map_state.tracked_entities_status = "Loaded: " .. path
    return true
end

local function TryLoadTrackedEntitiesOnce()
    EnsureTrackedEntitiesIndex()
    if mini_map_state.tracked_entities_loaded == true then return end

    LoadTrackedEntitiesFromFile()
    mini_map_state.tracked_entities_loaded = true
end

local function RefreshTrackedEntitiesAvailableLists()
    local dir = tostring(UiForge.resources_path) .. "\\mini_map"

    local ok, lines_or_err = pcall(Util.ListFilesInDir, dir, "*.entl")
    if not ok then
        mini_map_state.tracked_entities_lists_status = tostring(lines_or_err or "Unable to list .entl files")
        mini_map_state.tracked_entities_available_lists = { SanitizeFileName(mini_map_state.tracked_entities_file_name) }
        return
    end

    local lines = lines_or_err or {}

    local results = {}
    local seen = {}

    for _, line in ipairs(lines) do
        local name = Trim(line)
        if name ~= "" then
            local sanitized = SanitizeFileName(name)
            if not seen[sanitized] then
                seen[sanitized] = true
                results[#results + 1] = sanitized
            end
        end
    end

    local active = SanitizeFileName(mini_map_state.tracked_entities_file_name)
    if not seen[active] then
        results[#results + 1] = active
    end

    table.sort(results)
    mini_map_state.tracked_entities_available_lists = results
    mini_map_state.tracked_entities_lists_status = ""
end

local function OpenSaveTrackedEntitiesAsPopup()
    mini_map_state.tracked_entities_file_name_buffer = mini_map_state.tracked_entities_file_name
    ImGui.OpenPopup("Save Tracked Entities As")
end

local function RenderSaveTrackedEntitiesAsPopup()
    local always_auto_resize = (ImGuiWindowFlags and ImGuiWindowFlags.AlwaysAutoResize) or 0
    if not ImGui.BeginPopupModal("Save Tracked Entities As", true, always_auto_resize) then
        return
    end

    ImGui.Text("Save tracked entities list")
    ImGui.Separator()

    ImGui.TextDisabled("Folder:")
    ImGui.SameLine()
    ImGui.TextUnformatted(tostring(UiForge.resources_path) .. "\\mini_map\\")

    local hint = "e.g. bosses.entl"
    local enter_returns_true_flag = (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0
    local new_text, enter_pressed = ImGui.InputTextWithHint("File name", hint, mini_map_state.tracked_entities_file_name_buffer, enter_returns_true_flag)
    if new_text ~= nil then
        mini_map_state.tracked_entities_file_name_buffer = new_text
    end

    local sanitized = SanitizeFileName(mini_map_state.tracked_entities_file_name_buffer)
    ImGui.TextDisabled("Will use:")
    ImGui.SameLine()
    ImGui.TextUnformatted(sanitized)

    if ImGui.Button("Save") or enter_pressed then
        mini_map_state.tracked_entities_file_name = sanitized
        SaveTrackedEntitiesToFile()

        ImGui.CloseCurrentPopup()
        ImGui.EndPopup()
        return
    end

    ImGui.SameLine()
    if ImGui.Button("Use Default") then
        mini_map_state.tracked_entities_file_name_buffer = "minimap_tracked_entities.entl"
    end

    ImGui.SameLine()
    if ImGui.Button("Cancel") then
        ImGui.CloseCurrentPopup()
        ImGui.EndPopup()
        return
    end

    ImGui.EndPopup()
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

    -- If we have a saved tracked entity file, try to load it
    TryLoadTrackedEntitiesOnce()

    mini_map_state.initialized = true
end

local function Settings()
    TryLoadTrackedEntitiesOnce()
    
    local is_compass_disabled, compass_check_pressed = ImGui.Checkbox("Disable Compass", mini_map_state.disable_compass)
    -- We perform this check here so we do not write NOP to the compass code every single frame.
    if compass_check_pressed then
        mini_map_state.disable_compass = is_compass_disabled
        ToggleCompass()
    end

    -- mini_map_state.disable_in_start_menu = ImGui.CheckBox("Hide When Start Menu is Open", mini_map_state.disable_in_start_menu)

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

    ImGui.Separator()
    ImGui.Text("Entity Tracking")
    mini_map_state.entity_tracking_enabled  = ImGui.Checkbox("Enable Entity Tracking", mini_map_state.entity_tracking_enabled)
    mini_map_state.ping_tracked_entities    = ImGui.Checkbox("Ping Tracked Entities", mini_map_state.ping_tracked_entities)
    mini_map_state.line_to_tracked_entities = ImGui.Checkbox("Line to Tracked Entities", mini_map_state.line_to_tracked_entities)

    ImGui.TextDisabled("Type a name and press Enter to track")
    local enter_returns_true_flag = (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0
    local new_text, enter_pressed = ImGui.InputText("Track Entity", mini_map_state.tracked_entity_input, enter_returns_true_flag)
    mini_map_state.tracked_entity_input = new_text
    if enter_pressed then
        AddTrackedEntity(mini_map_state.tracked_entity_input)
        mini_map_state.tracked_entity_input = ""
    end

    if mini_map_state.tracked_entities_status ~= "" then
        ImGui.TextDisabled(mini_map_state.tracked_entities_status)
    end

    if ImGui.CollapsingHeader("Tracked Entities") then
        local active_file = SanitizeFileName(mini_map_state.tracked_entities_file_name)

        ImGui.Text("Active List:")
        ImGui.SameLine()
        local combo_open = ImGui.BeginCombo("##trackedEntitiesList", active_file)
        if combo_open then
            if mini_map_state._tracked_entities_combo_was_open ~= true then
                RefreshTrackedEntitiesAvailableLists()
            end
            mini_map_state._tracked_entities_combo_was_open = true

            local lists = mini_map_state.tracked_entities_available_lists or {}
            local active_key = active_file:lower()
            if #lists == 0 then
                ImGui.TextDisabled("(no .entl files found)")
            else
                for _, file_name in ipairs(lists) do
                    local is_selected = (file_name:lower() == active_key)
                    if ImGui.Selectable(file_name, is_selected) then
                        local selected_file = SanitizeFileName(file_name)
                        mini_map_state.tracked_entities_file_name = selected_file
                        LoadTrackedEntitiesFromFile()
                        mini_map_state.tracked_entities_loaded = true
                        active_key = selected_file:lower()
                    end
                    if is_selected then
                        ImGui.SetItemDefaultFocus()
                    end
                end
            end

            if mini_map_state.tracked_entities_lists_status ~= "" then
                ImGui.Separator()
                ImGui.TextDisabled(mini_map_state.tracked_entities_lists_status)
            end

            ImGui.EndCombo()
        else
            mini_map_state._tracked_entities_combo_was_open = false
        end

        if ImGui.Button("Clear All Tracked") then
            ClearTrackedEntities()
        end
        ImGui.SameLine()
        if ImGui.Button("Save") then
            SaveTrackedEntitiesToFile()
        end
        ImGui.SameLine()
        if ImGui.Button("Save As...") then
            OpenSaveTrackedEntitiesAsPopup()
        end

        RenderSaveTrackedEntitiesAsPopup()

        for i = 1, #mini_map_state.tracked_entities do
            local entry = mini_map_state.tracked_entities[i]
            ImGui.PushID(entry.key or i)

            entry.enabled = ImGui.Checkbox("##enabled", entry.enabled)
            ImGui.SameLine()
            ImGui.TextUnformatted(entry.name)
            ImGui.SameLine()
            if ImGui.Button("X##remove") then
                ImGui.PopID()
                RemoveTrackedEntityAtIndex(i)
                break
            end

            ImGui.SameLine()
            entry.fill_color = ImGui.ColorEdit4("Fill Color", entry.fill_color, ImGuiColorEditFlags.NoInputs)
            ImGui.SameLine()
            entry.border_color = ImGui.ColorEdit4("Border Color", entry.border_color, ImGuiColorEditFlags.NoInputs)

            ImGui.Separator()
            ImGui.PopID()
        end
    end
    -- ImGui.Text("If the mini-map seems a a little bit off,\nuse these sliders to adjust your position on the map.")
    -- mini_map_state.map_texture_offset_x    = ImGui.SliderInt("X offset", mini_map_state.map_texture_offset_x, 0, 300, tostring(mini_map_state.map_texture_offset_x))
    -- mini_map_state.map_texture_offset_y    = ImGui.SliderInt("Y offset", mini_map_state.map_texture_offset_y, 0, 300, tostring(mini_map_state.map_texture_offset_y))
end

local function RegisterSettings()
    UiForge.RegisterScriptSettings(Settings)
    mini_map_state.settings_registered = true
end

local function Render()

    local state = mini_map_state -- Shortcut for readability

    -- If we are not in game or if the start menu is open, don't display minimap
    if Util.IsInGame() == 0 or (state.disable_in_start_menu and Util.IsStartMenuOpen() == 1) then return end

    TryLoadTrackedEntitiesOnce()

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

        if state.show_entities == true then
            local default_border_color = ImGui.GetColorU32(
                state.entity_border_color[1],
                state.entity_border_color[2],
                state.entity_border_color[3],
                state.entity_border_color[4]
            )

            local tracking_enabled = (state.entity_tracking_enabled == true and state.tracked_entities_by_key ~= nil)
            local line_color = ImGui.GetColorU32(1, 1, 1, 0.75)

            local ping_phase = nil
            if tracking_enabled and state.ping_tracked_entities == true then
                local ping_period = 1.5
                local ping_duration = 0.35
                local ping_t = ImGui.GetTime() % ping_period
                if ping_t <= ping_duration then
                    ping_phase = ping_t / ping_duration
                end
            end

            local ping_color = nil
            if ping_phase ~= nil then
                ping_color = ImGui.GetColorU32(1, 1, 1, 1.0 - ping_phase)
            end

            ImGui.PushClipRect(window_pos.x, window_pos.y, window_pos.x + scaled_mini_map_width, window_pos.y + scaled_mini_map_height, true)
            -- EntityList.GetAllEntities() always includes the player in slot 1.
            for entity_index = 2, #entity_list do
                local entity = entity_list[entity_index]

                -- When entities despawn, memory can transiently contain "empty slot" data.
                -- Skip obviously-invalid entries to avoid rendering artifacts and tooltip issues.
                if entity ~= nil and entity.id ~= 0 and entity.name ~= "" then
                    -- Calculate the entity's position on the mini-map
                    local entity_map_x = entity.x * world_to_map_texture_scale_factor_x
                    local entity_map_z = entity.z * world_to_map_texture_scale_factor_z
                    local distance = {x = entity_map_x - player_map_texture_x, z = entity_map_z - player_map_texture_z }
                    local circle_center = ImVec2.new(mini_map_center.x + distance.x, mini_map_center.y + distance.z)

                local player_level = Player.GetLevel()
                local fill_color_u32 = state.entity_white_color
                if      entity.level - 2    >   player_level then fill_color_u32 = state.entity_red_color
                elseif  entity.level - 1    >=  player_level then fill_color_u32 = state.entity_yellow_color
                elseif  entity.level        ==  player_level then fill_color_u32 = state.entity_white_color
                elseif  entity.level + 1    ==  player_level then fill_color_u32 = state.entity_dark_blue_color
                elseif  entity.level + 2    ==  player_level then fill_color_u32 = state.entity_light_blue_color
                elseif  entity.level + 5    <=  player_level then fill_color_u32 = state.entity_gray_color
                elseif  entity.level + 3    <=  player_level then fill_color_u32 = state.entity_green_color
                end

                local is_tracked = false
                local tracked_border_color = default_border_color
                if tracking_enabled then
                    local tracked_index = state.tracked_entities_by_key[NormalizeEntityName(entity.name)]
                    if tracked_index ~= nil then
                        local tracked_entry = state.tracked_entities[tracked_index]
                        if tracked_entry ~= nil and tracked_entry.enabled ~= false then
                            is_tracked = true
                            fill_color_u32 = ImGui.GetColorU32(
                                tracked_entry.fill_color[1],
                                tracked_entry.fill_color[2],
                                tracked_entry.fill_color[3],
                                tracked_entry.fill_color[4]
                            )
                            tracked_border_color = ImGui.GetColorU32(
                                tracked_entry.border_color[1],
                                tracked_entry.border_color[2],
                                tracked_entry.border_color[3],
                                tracked_entry.border_color[4]
                            )
                        end
                    end
                end

                if is_tracked and state.line_to_tracked_entities == true then
                    draw_list:AddLine(mini_map_center, circle_center, line_color, 1.0)
                end

                draw_list:AddCircleFilled(circle_center, state.entity_radius, fill_color_u32)

                if state.show_entity_border == true or is_tracked then
                    draw_list:AddCircle(circle_center, state.entity_radius, (is_tracked and tracked_border_color or default_border_color), 0, state.entity_border_thickness)
                end

                if is_tracked and ping_color ~= nil then
                    local ping_radius = state.entity_radius + 4 + (ping_phase * 18)
                    draw_list:AddCircle(circle_center, ping_radius, ping_color, 0, 2.0)
                end

                -- Render a tooltip when mousing over an entity
                local mouse_x, mouse_y = ImGui.GetMousePos()
                    local distance_squared = (mouse_x - circle_center.x)^2 + (mouse_y - circle_center.y)^2
                    if distance_squared <= state.entity_radius^2 then
                        ImGui.BeginTooltip()
                        -- ImGui.Text() is printf-style: treat entity names as untrusted and render unformatted.
                        ImGui.TextUnformatted(entity.name .. "(" .. entity.level .. ")\n" ..
                                "ID: " .. entity.id .. "\n" ..
                                string.format("Coordinates: %.2f, %.2f, %.2f", entity.x, entity.y, entity.z))
                        ImGui.EndTooltip()
                    end
                end
            end
            ImGui.PopClipRect()
        end

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
