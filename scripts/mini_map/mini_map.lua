--[[
mini_map.lua

A live top-down minimap rendered from the game's own world geometry, walked out
of EE memory, so it always matches the world, zone, or dungeon the player is in.

Textured mode samples the real world textures through the meshes' UVs, so a
town shows its roofs and streets from above. Flat mode drops the textures and
shades purely by height, which reads better for caves and open terrain.

The map is height aware in both modes. Geometry that starts above the ceiling
cut is removed, so walking into a cave or dungeon renders the cave floor and
walls around you instead of the roof above. The cut can follow the player
automatically, dropping just under a real ceiling indoors and lifting out of the
way under open sky.

The map texture is rebuilt incrementally (a few thousand triangles per frame)
whenever the player moves far enough, changes altitude, or zooms. Entities and
the player arrow are drawn as an overlay on top of the texture, with an optional
tracking layer that highlights, pings, and draws lines to named entities kept in
.entl list files.
]]

local bit           = require("bit")
local UI            = require("frontiers_forge.ui")
local Player        = require("frontiers_forge.player")
local Util          = require("frontiers_forge.util")
local EntityList    = require("frontiers_forge.entity_list")
local WorldGeometry = require("world_geometry")
local MapRender     = require("map_render")

-- Each ForgeScript runs in a private environment whose _G is itself, so the
-- world map's published tracking table never lands in this script's _G.
-- getfenv(0) is the thread's real global table, shared by every script.
local shared_globals = getfenv(0)

-- The cut height used under open sky. Nothing in the world reaches this, so the
-- whole scene, mountain tops included, survives the cut.
local OPEN_SKY_CUT = 1e9

mini_map_state = mini_map_state or {
    initialized         = false,
    settings_registered = false,

    window_flags = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.NoTitleBar,

    -- Render mode: true samples the world's real textures, false shades by height
    textured        = true,

    -- The world's baked vertex lighting follows the time of day, so leaving it
    -- on renders most of the map black at night. Off shows the art unlit.
    world_lighting  = false,
    brightness      = 1.0,

    -- View settings
    view_size       = 220,      -- on-screen minimap size in pixels
    view_radius     = 150,      -- world units shown from center to edge
    min_radius      = 40,
    max_radius      = 600,
    rotate_with_player = false,

    -- Zoom in on its own whenever the ceiling probe says we are inside, since
    -- a room needs far less of the world on screen than a hillside does.
    auto_zoom         = false,
    indoor_view_radius = 60,

    -- Height slicing and shading
    auto_ceiling    = true,     -- find the ceiling instead of using ceiling_offset
    ceiling_offset  = 20,       -- manual cut, geometry starting above player_y + this
    ceiling_margin  = 3,        -- auto cut, how far under the found ceiling to cut
    head_clearance  = 2,        -- auto cut, ignore geometry closer than this overhead
    ceiling_search  = 250,      -- auto cut, stop looking this far overhead
    floor_range     = 80,       -- shade falloff below the player
    above_range     = 120,      -- shade falloff above the player

    -- Rebuild tuning
    tex_size        = 512,
    tris_per_frame  = 8000,
    rebuild_move_frac = 0.35,   -- rebuild when player moved this fraction of build radius
    rebuild_y_delta = 10,       -- rebuild when player altitude changed this much
    rebuild_cut_delta = 5,      -- rebuild when the ceiling cut moved this much

    -- Overlay settings
    show_player     = true,
    show_border     = true,
    border_color    = {0, 0, 0, 1},
    background_color = {0.05, 0.05, 0.08, 0.85},

    -- The circular frame. The zoom and cut height buttons are round buttons
    -- sitting on the rim, and each one can be dragged around it. Angles are in
    -- screen degrees, 0 at the right and growing clockwise.
    -- Defaults put the zoom pair together on the lower left and the cut pair
    -- together on the lower right, either side of the clock.
    circular         = true,
    zoom_plus_angle  = 170,
    zoom_minus_angle = 148,
    cut_up_angle     = 10,
    cut_down_angle   = 32,
    cut_step         = 5,

    -- A clock pinned to the bottom of the rim, showing the machine's local time.
    show_clock       = true,
    clock_24h        = false,

    -- Entity indicator settings
    show_entities           = true,
    entity_radius           = 3,
    entity_y_range          = 60,   -- hide entities more than this far above/below
    show_entity_border      = true,
    entity_border_color     = {0, 0, 0, 1},
    entity_border_thickness = 1,
    entity_red_color        = 0xFF0000FF,
    entity_yellow_color     = 0xFF00FFFF,
    entity_white_color      = 0xFFFFFFFF,
    entity_dark_blue_color  = 0xFF800000,
    entity_light_blue_color = 0xFFFF8080,
    entity_green_color      = 0xFF00FF00,
    entity_gray_color       = 0xFF808080,

    -- Entity tracking
    entity_tracking_enabled     = false,
    ping_tracked_entities       = false,
    line_to_tracked_entities    = false,

    -- World map guidance line, drawn whenever the world map is tracking a
    -- target, independent of the toggles above.
    db_line_color               = {1.0, 0.85, 0.2, 0.9},
    db_line_thickness           = 2.0,
    db_line_speed               = 26,   -- pixels per second the dashes travel
    db_track_seen_revision      = -1,
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
    tracked_entities_combo_was_open = false,

    -- Flat mode colors (rgba tables)
    terrain_low     = {0.10, 0.15, 0.25, 1},
    terrain_mid     = {0.25, 0.55, 0.30, 1},
    terrain_high    = {0.93, 0.91, 0.80, 1},
    actor_tint      = {0.75, 0.55, 0.40, 1},

    disable_compass = false,

    -- Font for the map window (clock, rim buttons, tooltips). Default is
    -- ImGui's built in font, which sizes through the window scale instead.
    font_name = "Default",
    font_size = 13,

    -- Runtime (not saved)
    ring_press_id   = nil,      -- rim button the mouse went down on
    ring_press_deg  = nil,      -- where on the rim the press started
    ring_drag_id    = nil,      -- rim button being dragged around the rim
    texture         = nil,
    built           = nil,      -- view params of the texture currently displayed
    rebuild         = nil,      -- in-progress rebuild job
    probe           = nil,      -- last auto ceiling probe
    indoors         = false,    -- last ceiling probe found a roof overhead
    debug_stats     = { tris = 0, cells = 0 },
}

local state = mini_map_state

-- Auto zoom swaps which radius is live rather than overwriting the outdoor one,
-- so zooming inside a cave never loses the zoom you set out in the world.
local function ViewRadius()
    if state.auto_zoom and state.indoors then
        return state.indoor_view_radius
    end
    return state.view_radius
end

local function SetViewRadius(radius)
    radius = math.max(state.min_radius, math.min(state.max_radius, radius))
    if state.auto_zoom and state.indoors then
        state.indoor_view_radius = radius
    else
        state.view_radius = radius
    end
end

-- ---------------------------------------------------------------------------
-- Entity tracking
--
-- The map always draws every nearby entity. Tracking is an optional layer that
-- highlights a user managed list of entity names (e.g. "Grass Snake"). Entries
-- live in .entl files under resources\mini_map, one CSV row per entity, so a
-- list can be shared or swapped without touching the script.
--
-- tracked_entities is the list itself. tracked_entities_by_key maps a
-- normalized name to its index, so the render loop is a hash lookup per entity
-- instead of a scan.
-- ---------------------------------------------------------------------------

local DEFAULT_LIST_FILE = "minimap_tracked_entities.entl"

local function Trim(str)
    if str == nil then return "" end
    return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NormalizeEntityName(name)
    return Trim(name):lower()
end

local function RebuildTrackedEntitiesIndex()
    state.tracked_entities_by_key = {}
    for index, entry in ipairs(state.tracked_entities) do
        entry.name = Trim(entry.name)
        entry.key = NormalizeEntityName(entry.name)
        state.tracked_entities_by_key[entry.key] = index

        if entry.enabled == nil then entry.enabled = true end
        if entry.fill_color == nil then entry.fill_color = {1, 1, 0, 1} end
        if entry.border_color == nil then entry.border_color = {1, 1, 1, 1} end
    end
    state.tracked_entities_index_dirty = false
end

local function EnsureTrackedEntitiesIndex()
    if state.tracked_entities_index_dirty == true then
        RebuildTrackedEntitiesIndex()
    end
end

local function SanitizeFileName(file_name)
    file_name = Trim(file_name)
    if file_name == "" then
        file_name = DEFAULT_LIST_FILE
    end

    -- Avoid invalid Windows filename characters. This isn't a comprehensive
    -- solution, just don't be dumb with file names.
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
    return UiForge.resources_path .. "\\mini_map\\" .. SanitizeFileName(state.tracked_entities_file_name)
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

    -- Quote anything that would break parsing on the way back in: separators,
    -- newlines, quotes (doubled per CSV rules), and edge whitespace.
    if value:find("[\",\n\r]") or value:find("^%s") or value:find("%s$") then
        value = value:gsub("\"", "\"\"")
        return "\"" .. value .. "\""
    end
    return value
end

local function CsvParseLine(line)
    local parsed_fields = {}
    local current_field = ""
    local is_in_quotes = false
    local position = 1
    local line_length = #line

    while position <= line_length do
        local char = line:sub(position, position)
        if is_in_quotes then
            if char == "\"" then
                -- A doubled quote inside quotes is a literal quote character.
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
    if state.tracked_entities_by_key[key] ~= nil then
        state.tracked_entities_status = "Already tracking: " .. name
        return
    end

    state.tracked_entities[#state.tracked_entities + 1] = {
        name = name,
        key = key,
        enabled = true,
        fill_color = {1, 1, 0, 1},
        border_color = {1, 1, 1, 1},
    }

    RebuildTrackedEntitiesIndex()
    state.tracked_entities_status = "Added: " .. name
end

local function RemoveTrackedEntityAtIndex(index)
    table.remove(state.tracked_entities, index)
    RebuildTrackedEntitiesIndex()
end

local function ClearTrackedEntities()
    state.tracked_entities = {}
    RebuildTrackedEntitiesIndex()
    state.tracked_entities_status = "Cleared all tracked entities"
end

--- Saves the tracked entity list to its .entl file under resources\mini_map.
local function SaveTrackedEntitiesToFile()
    EnsureTrackedEntitiesIndex()

    local path = GetTrackedEntitiesFilePath()
    local file = io.open(path, "w")
    if file == nil then
        state.tracked_entities_status = "Failed to write: " .. path
        return false
    end

    file:write("# " .. DEFAULT_LIST_FILE .. "\n")
    file:write("# One entity per line (CSV): name,enabled,fillR,fillG,fillB,fillA,borderR,borderG,borderB,borderA\n")

    for _, entry in ipairs(state.tracked_entities) do
        local parts = {
            CsvEscapeField(entry.name),
            (entry.enabled and "true" or "false"),
            tostring(entry.fill_color[1]), tostring(entry.fill_color[2]),
            tostring(entry.fill_color[3]), tostring(entry.fill_color[4]),
            tostring(entry.border_color[1]), tostring(entry.border_color[2]),
            tostring(entry.border_color[3]), tostring(entry.border_color[4]),
        }
        file:write(table.concat(parts, ","), "\n")
    end

    file:close()
    state.tracked_entities_status = "Saved: " .. path
    return true
end

--- Loads a tracked entity list from an .entl file under resources\mini_map.
local function LoadTrackedEntitiesFromFile()
    local path = GetTrackedEntitiesFilePath()
    local file = io.open(path, "r")
    if file == nil then
        state.tracked_entities_status = "No tracked entities file found"
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
                    local fill = {1, 1, 0, 1}
                    local border = {1, 1, 1, 1}

                    if #fields >= 10 then
                        local fr, fg, fb, fa = Clamp01(fields[3]), Clamp01(fields[4]),
                                               Clamp01(fields[5]), Clamp01(fields[6])
                        local br, bg, bb, ba = Clamp01(fields[7]), Clamp01(fields[8]),
                                               Clamp01(fields[9]), Clamp01(fields[10])
                        if fr and fg and fb and fa then fill = {fr, fg, fb, fa} end
                        if br and bg and bb and ba then border = {br, bg, bb, ba} end
                    end

                    loaded[#loaded + 1] = {
                        name = name,
                        enabled = ParseBool(fields[2]),
                        fill_color = fill,
                        border_color = border,
                    }
                end
            end
        end
    end
    file:close()

    state.tracked_entities = loaded
    RebuildTrackedEntitiesIndex()
    state.tracked_entities_status = "Loaded: " .. path
    return true
end

local function TryLoadTrackedEntitiesOnce()
    EnsureTrackedEntitiesIndex()
    if state.tracked_entities_loaded == true then return end

    LoadTrackedEntitiesFromFile()
    state.tracked_entities_loaded = true
end

local function RefreshTrackedEntitiesAvailableLists()
    local dir = tostring(UiForge.resources_path) .. "\\mini_map"

    local ok, files = pcall(Util.ListFilesInDir, dir, "*.entl")
    if not ok then
        state.tracked_entities_lists_status = tostring(files or "Unable to list .entl files")
        state.tracked_entities_available_lists = { SanitizeFileName(state.tracked_entities_file_name) }
        return
    end

    local results, seen = {}, {}
    for _, file_name in ipairs(files or {}) do
        local name = Trim(file_name)
        if name ~= "" then
            local sanitized = SanitizeFileName(name)
            if not seen[sanitized] then
                seen[sanitized] = true
                results[#results + 1] = sanitized
            end
        end
    end

    local active = SanitizeFileName(state.tracked_entities_file_name)
    if not seen[active] then
        results[#results + 1] = active
    end

    table.sort(results)
    state.tracked_entities_available_lists = results
    state.tracked_entities_lists_status = ""
end

local function OpenSaveTrackedEntitiesAsPopup()
    state.tracked_entities_file_name_buffer = state.tracked_entities_file_name
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

    local enter_returns_true_flag = (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0
    local new_text, enter_pressed = ImGui.InputTextWithHint("File name", "e.g. bosses.entl",
        state.tracked_entities_file_name_buffer, enter_returns_true_flag)
    if new_text ~= nil then
        state.tracked_entities_file_name_buffer = new_text
    end

    local sanitized = SanitizeFileName(state.tracked_entities_file_name_buffer)
    ImGui.TextDisabled("Will use:")
    ImGui.SameLine()
    ImGui.TextUnformatted(sanitized)

    if ImGui.Button("Save") or enter_pressed then
        state.tracked_entities_file_name = sanitized
        SaveTrackedEntitiesToFile()

        ImGui.CloseCurrentPopup()
        ImGui.EndPopup()
        return
    end

    ImGui.SameLine()
    if ImGui.Button("Use Default") then
        state.tracked_entities_file_name_buffer = DEFAULT_LIST_FILE
    end

    ImGui.SameLine()
    if ImGui.Button("Cancel") then
        ImGui.CloseCurrentPopup()
        ImGui.EndPopup()
        return
    end

    ImGui.EndPopup()
end

-- ---------------------------------------------------------------------------
-- Height slicing
-- ---------------------------------------------------------------------------

--- The height to cut the world at this frame. In auto mode the geometry decides:
--- a ceiling overhead means we are inside, so cut just below it and reveal the
--- room, and open sky means cut nothing so mountains and rooftops survive.
--- The probe walks room geometry, so its result is reused until the player has
--- moved or enough time has passed for the scene to have streamed in.
local function CeilingCut(px, py, pz)
    if not state.auto_ceiling then
        state.indoors = false
        return py + state.ceiling_offset
    end

    local now = ImGui.GetTime()
    local probe = state.probe
    local stale = probe == nil
    if not stale then
        local dx, dz = px - probe.x, pz - probe.z
        stale = dx * dx + dz * dz > 4
             or math.abs(py - probe.y) > 2
             or now - probe.time > 0.5
    end

    if stale then
        local ceiling = WorldGeometry.CeilingAbove(px, py, pz, state.head_clearance,
                                                   state.ceiling_search, 3)
        probe = { x = px, y = py, z = pz, time = now, ceiling = ceiling }
        state.probe = probe
    end

    state.indoors = probe.ceiling ~= nil
    if probe.ceiling == nil then
        return py + OPEN_SKY_CUT
    end
    return probe.ceiling - state.ceiling_margin
end

-- ---------------------------------------------------------------------------
-- Incremental texture rebuild
-- ---------------------------------------------------------------------------

local function StartRebuild(px, py, pz, cut_y)
    local build_radius = ViewRadius() * 1.5
    local job = MapRender.Start({
        center_x = px, center_z = pz,
        radius = build_radius,
        size = state.tex_size,
        ref_y = py,
        cut_y = cut_y,
        floor_range = state.floor_range,
        above_range = state.above_range,
        textured = state.textured,
        lighting = state.world_lighting,
        brightness = state.brightness,
        colors = {
            low = state.terrain_low,
            mid = state.terrain_mid,
            high = state.terrain_high,
            actor_tint = state.actor_tint,
            background = state.background_color,
        },
    })
    WorldGeometry.EachRoomInRadius(px, pz, build_radius, function(room)
        job.cells[#job.cells + 1] = room
    end)
    state.rebuild = job
end

local function StepRebuild()
    local job = state.rebuild
    if job == nil then return end
    if MapRender.Step(job, state.tris_per_frame) then
        local new_texture = MapRender.Upload(job)
        if state.texture ~= nil then
            UiForge.ReleaseTexture(state.texture)
        end
        state.texture = new_texture
        state.built = {
            center_x = job.center_x, center_z = job.center_z,
            player_y = job.ref_y,
            cut_y = job.cut_y,
            radius = job.radius, size = job.size,
            textured = job.textured,
        }
        state.debug_stats.tris = job.tris_done
        state.debug_stats.cells = #job.cells
        state.rebuild = nil
    end
end

local function NeedsRebuild(px, py, pz, cut_y)
    local built = state.built
    if built == nil then return true end
    if built.textured ~= state.textured then return true end
    if math.abs(built.radius - ViewRadius() * 1.5) > 1 then return true end
    local dx, dz = px - built.center_x, pz - built.center_z
    local max_move = built.radius * state.rebuild_move_frac
    if dx * dx + dz * dz > max_move * max_move then return true end
    if math.abs(py - built.player_y) > state.rebuild_y_delta then return true end
    if math.abs(cut_y - built.cut_y) > state.rebuild_cut_delta then return true end
    return false
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

local function DrawMapTexture(draw_list, origin, view_px, px, pz, heading)
    local built = state.built
    if built == nil or state.texture == nil then return end

    -- The texture covers a square of built.radius around built.center. Show
    -- the view_radius window centered on the live player position so the map
    -- pans smoothly between rebuilds.
    local tex_world = built.radius * 2
    local u_center = (px - (built.center_x - built.radius)) / tex_world
    local v_center = (pz - (built.center_z - built.radius)) / tex_world
    local half_uv = ViewRadius() / tex_world

    local cx = origin.x + view_px * 0.5
    local cy = origin.y + view_px * 0.5
    local half = view_px * 0.5
    local tint = ImGui.GetColorU32(1, 1, 1, 1)

    if state.rotate_with_player then
        local ang = heading
        local cos_a, sin_a = math.cos(ang), math.sin(ang)
        local function rot_uv(du, dv)
            return ImVec2.new(u_center + (du * cos_a - dv * sin_a) * half_uv,
                              v_center + (du * sin_a + dv * cos_a) * half_uv)
        end
        draw_list:AddImageQuad(state.texture,
            ImVec2.new(cx - half, cy - half), ImVec2.new(cx + half, cy - half),
            ImVec2.new(cx + half, cy + half), ImVec2.new(cx - half, cy + half),
            rot_uv(-1, -1), rot_uv(1, -1), rot_uv(1, 1), rot_uv(-1, 1), tint)
    elseif state.circular then
        -- Rounding by half the size turns the image into a disc, which is the
        -- whole circular frame. A rotated quad cannot be rounded, which is why
        -- Rotate With Player falls back to the square above.
        draw_list:AddImageRounded(state.texture,
            ImVec2.new(cx - half, cy - half), ImVec2.new(cx + half, cy + half),
            ImVec2.new(u_center - half_uv, v_center - half_uv),
            ImVec2.new(u_center + half_uv, v_center + half_uv), tint, half)
    else
        draw_list:AddImage(state.texture,
            ImVec2.new(cx - half, cy - half), ImVec2.new(cx + half, cy + half),
            ImVec2.new(u_center - half_uv, v_center - half_uv),
            ImVec2.new(u_center + half_uv, v_center + half_uv), tint)
    end
end

local function WorldToScreen(wx, wz, px, pz, center, scale, heading)
    local dx, dz = wx - px, wz - pz
    if state.rotate_with_player then
        local cos_a, sin_a = math.cos(-heading), math.sin(-heading)
        dx, dz = dx * cos_a - dz * sin_a, dx * sin_a + dz * cos_a
    end
    return ImVec2.new(center.x + dx * scale, center.y + dz * scale)
end

local function EntityConColor(entity_level, player_level)
    if     entity_level - 2 >  player_level then return state.entity_red_color
    elseif entity_level - 1 >= player_level then return state.entity_yellow_color
    elseif entity_level     == player_level then return state.entity_white_color
    elseif entity_level + 1 == player_level then return state.entity_dark_blue_color
    elseif entity_level + 2 == player_level then return state.entity_light_blue_color
    elseif entity_level + 5 <= player_level then return state.entity_gray_color
    else return state.entity_green_color end
end

-- The ping is a ring that expands and fades out of a tracked entity on a fixed
-- cycle. Returns the phase (0 to 1) and its color, or nil between pings.
local function PingPulse()
    -- A target pushed from the world map counts as tracking too, so its pings
    -- fire even when the .entl tracking layer is switched off.
    if not ((state.entity_tracking_enabled or state.db_track_active) and state.ping_tracked_entities) then
        return nil, nil
    end
    local ping_period = 1.5
    local ping_duration = 0.35
    local ping_t = ImGui.GetTime() % ping_period
    if ping_t > ping_duration then return nil, nil end

    local phase = ping_t / ping_duration
    return phase, ImGui.GetColorU32(1, 1, 1, 1.0 - phase)
end

local function DrawEntities(draw_list, center, px, py, pz, scale, heading, view_px, origin)
    EnsureTrackedEntitiesIndex()

    local entities = EntityList.GetAllEntities()
    local player_level = Player.GetLevel()
    local default_border = ImGui.GetColorU32(state.entity_border_color[1],
        state.entity_border_color[2], state.entity_border_color[3],
        state.entity_border_color[4])
    local line_color = ImGui.GetColorU32(1, 1, 1, 0.75)
    local tracking = state.entity_tracking_enabled and state.tracked_entities_by_key ~= nil
    local ping_phase, ping_color = PingPulse()

    -- A world-map search target: a normalized name that should be treated as
    -- tracked even when it is not in the .entl list, so its live entity pings and
    -- draws a line once it comes into view.
    local db_track_name = state.db_track_active and state.db_track_name or nil
    local db_track_fill = ImGui.GetColorU32(1.0, 0.85, 0.2, 1.0)
    local db_track_border = ImGui.GetColorU32(0, 0, 0, 1)

    -- Slot 1 is always the player.
    for i = 2, #entities do
        local entity = entities[i]
        local id = entity:GetId()
        local name = entity:GetName()
        -- Despawned slots transiently hold empty data, skip them.
        if id ~= 0 and name ~= "" then
            local ex, ey, ez = entity:GetPosition()
            -- Entities on another floor of a dungeon are noise, fade them out
            -- and skip them entirely once far above/below.
            local dy = math.abs(ey - py)
            if dy <= state.entity_y_range then
                local p = WorldToScreen(ex, ez, px, pz, center, scale, heading)
                -- On the disc an entity is visible inside the rim, on the square
                -- inside the rect.
                local visible
                if state.circular and not state.rotate_with_player then
                    local dcx, dcy = p.x - center.x, p.y - center.y
                    local rim = view_px * 0.5 - state.entity_radius
                    visible = dcx * dcx + dcy * dcy <= rim * rim
                else
                    visible = p.x >= origin.x and p.x <= origin.x + view_px
                        and p.y >= origin.y and p.y <= origin.y + view_px
                end
                if visible then
                    local level = entity:GetLevel()
                    local fill = EntityConColor(level, player_level)
                    local border = default_border

                    local is_tracked = false
                    local normalized_name = NormalizeEntityName(name)
                    if tracking then
                        local index = state.tracked_entities_by_key[normalized_name]
                        local entry = index and state.tracked_entities[index] or nil
                        if entry ~= nil and entry.enabled ~= false then
                            is_tracked = true
                            fill = ImGui.GetColorU32(entry.fill_color[1], entry.fill_color[2],
                                                     entry.fill_color[3], entry.fill_color[4])
                            border = ImGui.GetColorU32(entry.border_color[1], entry.border_color[2],
                                                       entry.border_color[3], entry.border_color[4])
                        end
                    end

                    -- Fall back to the world-map target when the .entl layer did not
                    -- already claim this entity.
                    if not is_tracked and db_track_name ~= nil and normalized_name == db_track_name then
                        is_tracked = true
                        fill = db_track_fill
                        border = db_track_border
                    end

                    if not is_tracked and dy > state.entity_y_range * 0.5 then
                        fill = bit.band(fill, 0x60FFFFFF)
                    end

                    if is_tracked and state.line_to_tracked_entities then
                        draw_list:AddLine(center, p, line_color, 1.0)
                    end

                    draw_list:AddCircleFilled(p, state.entity_radius, fill)

                    if state.show_entity_border or is_tracked then
                        draw_list:AddCircle(p, state.entity_radius, border, 0,
                                            state.entity_border_thickness)
                    end

                    if is_tracked and ping_color ~= nil then
                        local ping_radius = state.entity_radius + 4 + (ping_phase * 18)
                        draw_list:AddCircle(p, ping_radius, ping_color, 0, 2.0)
                    end

                    local mx, my = ImGui.GetMousePos()
                    local dsq = (mx - p.x) ^ 2 + (my - p.y) ^ 2
                    if dsq <= state.entity_radius ^ 2 then
                        ImGui.BeginTooltip()
                        -- Entity names are untrusted, render them unformatted.
                        ImGui.TextUnformatted(string.format("%s (%d)\nID: %d\n%.1f, %.1f, %.1f",
                            name, level, id, ex, ey, ez))
                        ImGui.EndTooltip()
                    end
                end
            end
        end
    end
end

local function DrawPlayerArrow(draw_list, center, heading)
    -- Compass heading increases opposite to screen-space rotation, negate it.
    local ang = state.rotate_with_player and 0 or -heading
    local size = 7
    local cos_a, sin_a = math.cos(ang), math.sin(ang)
    local function pt(dx, dz)
        return ImVec2.new(center.x + (dx * cos_a - dz * sin_a),
                          center.y + (dx * sin_a + dz * cos_a))
    end
    local tip   = pt(0, -size * 1.4)
    local left  = pt(-size * 0.7, size)
    local right = pt(size * 0.7, size)
    draw_list:AddTriangleFilled(tip, left, right, ImGui.GetColorU32(0.2, 1, 0.2, 1))
    draw_list:AddTriangle(tip, left, right, ImGui.GetColorU32(0, 0, 0, 1), 1.5)
end

-- Explains the control that was just drawn, on hover.
local function Tooltip(text)
    if not ImGui.IsItemHovered() then return end
    ImGui.BeginTooltip()
    ImGui.TextUnformatted(text)
    ImGui.EndTooltip()
end

-- Shortest angular distance between two screen angles, in degrees.
local function AngularDiff(a, b)
    return math.abs(((a - b + 180) % 360) - 180)
end

-- Keeps a rim button off the clock's stretch of the rim, snapping to whichever
-- edge of the reserved arc is closer.
local function ClampRingAngle(deg)
    deg = deg % 360
    if not state.show_clock then
        return deg
    end
    local reserve = 34
    if AngularDiff(deg, 90) < reserve then
        local off = ((deg - 90 + 180) % 360) - 180
        deg = (off < 0) and (90 - reserve) or (90 + reserve)
    end
    return deg % 360
end

--- Moves the height cut by one step. Which knob that turns depends on the mode,
--- auto cutting indoors moves the margin under the found ceiling, manual moves
--- the fixed offset. Outdoors under auto there is no cut to move.
local function AdjustCutHeight(direction)
    local step = state.cut_step * direction
    if state.auto_ceiling then
        if state.indoors then
            -- Raising the cut means cutting closer to the ceiling.
            state.ceiling_margin = math.max(0, math.min(60, state.ceiling_margin - step))
            state.built = nil
        end
    else
        state.ceiling_offset = math.max(0, math.min(600, state.ceiling_offset + step))
        state.built = nil
    end
end

local function CutTooltip(direction)
    if state.auto_ceiling and not state.indoors then
        return "Cut height (open sky, nothing overhead to cut)"
    end
    local what = state.auto_ceiling and "auto indoor cut" or "cut height"
    return string.format("%s the %s by %d\nDrag to move this button around the rim",
        direction > 0 and "Raise" or "Lower", what, state.cut_step)
end

-- A round button pinned to the rim of the circular map. A click fires it, and
-- dragging slides it around the rim instead. The invisible button underneath is
-- what keeps a drag from moving the whole window.
local function RingButton(draw_list, id, label, center, rim_radius, angle_key, tooltip)
    local btn_r = 10
    local ang = math.rad(state[angle_key])
    local bx = center.x + math.cos(ang) * rim_radius
    local by = center.y + math.sin(ang) * rim_radius

    ImGui.SetCursorScreenPos(bx - btn_r, by - btn_r)
    local pressed = ImGui.InvisibleButton(id, btn_r * 2, btn_r * 2)
    local hovered = ImGui.IsItemHovered()
    local active = ImGui.IsItemActive()

    if active then
        local mx, my = ImGui.GetMousePos()
        local deg = (math.deg(math.atan2(my - center.y, mx - center.x))) % 360
        if state.ring_drag_id ~= id then
            -- The drag only starts once the press strays, so a click stays a click.
            if state.ring_press_id ~= id then
                state.ring_press_id = id
                state.ring_press_deg = deg
            elseif AngularDiff(deg, state.ring_press_deg or deg) > 6 then
                state.ring_drag_id = id
            end
        end
        if state.ring_drag_id == id then
            state[angle_key] = ClampRingAngle(deg)
        end
    end

    -- A release that ended a drag is not a click.
    local clicked = pressed and state.ring_drag_id ~= id
    if not active then
        if state.ring_press_id == id then state.ring_press_id = nil end
        if state.ring_drag_id == id then state.ring_drag_id = nil end
    end

    local fill = (hovered or active) and ImGui.GetColorU32(0.28, 0.28, 0.34, 1)
        or ImGui.GetColorU32(0.10, 0.10, 0.13, 0.95)
    local rim = ImGui.GetColorU32(state.border_color[1], state.border_color[2],
        state.border_color[3], state.border_color[4])
    draw_list:AddCircleFilled(ImVec2.new(bx, by), btn_r, fill)
    draw_list:AddCircle(ImVec2.new(bx, by), btn_r, rim, 0, 1.5)

    local text_w, text_h = ImGui.CalcTextSize(label)
    draw_list:AddText(ImVec2.new(bx - text_w * 0.5, by - text_h * 0.5),
        ImGui.GetColorU32(1, 1, 1, 1), label)

    if hovered and tooltip ~= nil then
        ImGui.BeginTooltip()
        ImGui.TextUnformatted(tooltip)
        ImGui.EndTooltip()
    end
    return clicked
end

-- The local time in a rounded box pinned to the bottom of the rim. The rim
-- buttons are clamped away from this stretch, so nothing lands on top of it.
local function DrawClock(draw_list, center, rim_radius)
    local text = os.date(state.clock_24h and "%H:%M" or "%I:%M %p")
    if not state.clock_24h then
        text = text:gsub("^0", "")
    end
    local text_w, text_h = ImGui.CalcTextSize(text)
    local w, h = text_w + 16, text_h + 6
    local cx, cy = center.x, center.y + rim_radius

    local rim = ImGui.GetColorU32(state.border_color[1], state.border_color[2],
        state.border_color[3], state.border_color[4])
    draw_list:AddRectFilled(ImVec2.new(cx - w / 2, cy - h / 2),
        ImVec2.new(cx + w / 2, cy + h / 2), ImGui.GetColorU32(0.08, 0.08, 0.11, 0.95), h / 2)
    draw_list:AddRect(ImVec2.new(cx - w / 2, cy - h / 2),
        ImVec2.new(cx + w / 2, cy + h / 2), rim, h / 2, 0, 1.5)
    draw_list:AddText(ImVec2.new(cx - text_w / 2, cy - text_h / 2),
        ImGui.GetColorU32(1, 1, 1, 1), text)
end

-- The fonts on offer, from the shared resources folder.
local MAP_FONTS = {
    { name = "Default" },
    { name = "Cinzel", path = "fonts/Cinzel/static/Cinzel-Regular.ttf" },
    { name = "Libre Baskerville", path = "fonts/Libre_Baskerville/static/LibreBaskerville-Regular.ttf" },
    { name = "Merriweather Sans", path = "fonts/Merriweather_Sans/static/MerriweatherSans-Regular.ttf" },
}
local DEFAULT_FONT_SIZE = 13

-- Pushes the chosen font for the map window. The host caches fonts per file
-- and size, so pushing every frame is cheap. Returns whether a pop is owed.
local function PushMapFont()
    for _, font in ipairs(MAP_FONTS) do
        if font.name == state.font_name and font.path ~= nil then
            ImGui.PushFont(UiForge.LoadFont(font.path, state.font_size))
            return true
        end
    end
    return false
end

-- Call inside the window. Sizes the default font, which has no file to
-- reload at another size. A file backed font is already at its size.
local function ApplyMapFontScale()
    if state.font_name == "Default" then
        ImGui.SetWindowFontScale(state.font_size / DEFAULT_FONT_SIZE)
    else
        ImGui.SetWindowFontScale(1)
    end
end

-- Reads the shared tracking table published by the world map. Returns the
-- normalized name and the list of candidate spawn zones, or nil when nothing is
-- being tracked. The contract is intentionally small so the two mods stay
-- decoupled, see world_map.lua PublishTracking.
local function ReadDatabaseTracking()
    local shared = shared_globals.FF_Tracking
    if type(shared) ~= "table" or shared.active ~= true then return nil end
    if type(shared.name) ~= "string" or type(shared.zones) ~= "table" or #shared.zones == 0 then
        return nil
    end
    return shared
end

-- Picks the spawn zone closest to the player, since a creature can have many
-- recorded spawns and the guidance line should point at the nearest one.
local function NearestZone(zones, px, pz)
    local best, best_dsq
    for _, zone in ipairs(zones) do
        if type(zone) == "table" and zone.x ~= nil and zone.z ~= nil then
            local dx, dz = zone.x - px, zone.z - pz
            local dsq = dx * dx + dz * dz
            if best_dsq == nil or dsq < best_dsq then
                best_dsq = dsq
                best = zone
            end
        end
    end
    return best
end

-- A dashed line whose dashes travel from p0 toward p1 over time, giving the
-- guidance line a sense of direction.
local function DrawAnimatedDashedLine(draw_list, p0, p1, color, thickness)
    local dx, dz = p1.x - p0.x, p1.y - p0.y
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 1 then return end
    local ux, uy = dx / length, dz / length

    local dash = 8
    local gap = 6
    local period = dash + gap
    local phase = (ImGui.GetTime() * state.db_line_speed) % period

    -- Dashes sit at phase mod period, and start one period early so the
    -- segment at p0 is covered. Growing phase slides them p0 toward p1.
    local d = phase - period
    while d < length do
        local start = math.max(0, d)
        local finish = math.min(length, d + dash)
        if finish > start then
            draw_list:AddLine(
                ImVec2.new(p0.x + ux * start, p0.y + uy * start),
                ImVec2.new(p0.x + ux * finish, p0.y + uy * finish),
                color, thickness)
        end
        d = d + period
    end
end

-- Draws the guidance line from the player to the nearest tracked spawn zone. When
-- the zone falls inside the minimap it also draws the zone marker circle the line
-- terminates at, otherwise the line stops at the rim pointing the right way.
local function DrawTrackingGuidance(draw_list, center, px, pz, scale, heading, view_px, origin, circular)
    if not state.db_track_active then return end
    local zone = NearestZone(state.db_track_zones, px, pz)
    if zone == nil then return end

    local target = WorldToScreen(zone.x, zone.z, px, pz, center, scale, heading)
    local dx, dy = target.x - center.x, target.y - center.y
    local dist = math.sqrt(dx * dx + dy * dy)

    local rim = view_px * 0.5
    local marker_margin = 8
    local c = state.db_line_color
    local line_color = ImGui.GetColorU32(c[1], c[2], c[3], c[4])

    local inside
    if circular then
        inside = dist <= (rim - marker_margin)
    else
        inside = target.x >= origin.x and target.x <= origin.x + view_px
             and target.y >= origin.y and target.y <= origin.y + view_px
    end

    if inside then
        DrawAnimatedDashedLine(draw_list, center, target, line_color, state.db_line_thickness)
        -- The "you are here / it is here" zone marker at the center of the zone.
        draw_list:AddCircleFilled(target, 4, ImGui.GetColorU32(c[1], c[2], c[3], c[4] * 0.55))
        draw_list:AddCircle(target, 6, line_color, 0, 2.0)
    else
        -- Clip the endpoint to the rim so the line never renders outside the map.
        local endpoint
        if dist > 0 then
            local reach = rim - marker_margin
            endpoint = ImVec2.new(center.x + (dx / dist) * reach, center.y + (dy / dist) * reach)
        else
            endpoint = center
        end
        DrawAnimatedDashedLine(draw_list, center, endpoint, line_color, state.db_line_thickness)
        -- A small arrowhead nub at the rim, pointing the way to go.
        draw_list:AddCircleFilled(endpoint, 3, line_color)
    end
end

local function Render()
    if Util.IsInGame() == 0 then return end
    -- An overlay floating over the pause screen is just in the way.
    if Util.IsStartMenuOpen() ~= 0 then return end
    if not WorldGeometry.IsAvailable() then return end

    TryLoadTrackedEntitiesOnce()

    local pos = Player.GetCoordinates()
    local heading = Util.GetCompassRadians()

    -- Pick up any target the world map published this frame.
    local db_track = ReadDatabaseTracking()
    if db_track ~= nil then
        state.db_track_active = true
        state.db_track_name = NormalizeEntityName(db_track.name)
        state.db_track_display = db_track.name
        state.db_track_zones = db_track.zones
        -- A freshly pushed target switches the tracking layer on so the
        -- creature highlights and pings without a trip to the settings.
        local revision = tonumber(db_track.revision) or 0
        if revision ~= state.db_track_seen_revision then
            state.db_track_seen_revision = revision
            state.entity_tracking_enabled = true
            state.ping_tracked_entities = true
        end
    else
        state.db_track_active = false
        state.db_track_name = nil
        state.db_track_display = nil
        state.db_track_zones = nil
    end

    if state.rebuild == nil then
        local cut_y = CeilingCut(pos.x, pos.y, pos.z)
        if NeedsRebuild(pos.x, pos.y, pos.z, cut_y) then
            StartRebuild(pos.x, pos.y, pos.z, cut_y)
        end
    end
    StepRebuild()

    local font_pushed = PushMapFont()
    if ImGui.Begin("mini map window", true, state.window_flags) then
        ApplyMapFontScale()
        local view_px = state.view_size
        local circular = state.circular and not state.rotate_with_player

        -- The disc's rim buttons and clock hang past the map square, so the
        -- window claims a padded square and the map sits centered in it.
        local pad = circular and 18 or 0
        ImGui.Dummy(view_px + pad * 2, view_px + pad * 2)
        local draw_list = ImGui.GetWindowDrawList()
        local wx, wy = ImGui.GetItemRectMin()
        local origin = { x = wx + pad, y = wy + pad }
        local center = ImVec2.new(origin.x + view_px * 0.5, origin.y + view_px * 0.5)
        local scale = view_px / (2 * ViewRadius())
        local half = view_px * 0.5

        ImGui.PushClipRect(origin.x, origin.y, origin.x + view_px, origin.y + view_px, true)

        if circular then
            -- The backing disc, for the stretch of rim the texture has not
            -- reached yet and for the see-through background color.
            draw_list:AddCircleFilled(center, half,
                ImGui.GetColorU32(state.background_color[1], state.background_color[2],
                                  state.background_color[3], state.background_color[4]))
        end

        DrawMapTexture(draw_list, origin, view_px, pos.x, pos.z, heading)

        if state.show_entities then
            DrawEntities(draw_list, center, pos.x, pos.y, pos.z, scale, heading, view_px, origin)
        end
        DrawTrackingGuidance(draw_list, center, pos.x, pos.z, scale, heading, view_px, origin, circular)
        if state.show_player then
            DrawPlayerArrow(draw_list, center, heading)
        end

        ImGui.PopClipRect()

        local border_color = ImGui.GetColorU32(state.border_color[1], state.border_color[2],
            state.border_color[3], state.border_color[4])

        if circular then
            if state.show_border then
                draw_list:AddCircle(center, half, border_color, 0, 2.0)
            end
            if state.show_clock then
                DrawClock(draw_list, center, half)
            end
            if RingButton(draw_list, "ring_zoom_in", "+", center, half, "zoom_plus_angle",
                "Zoom in\nDrag to move this button around the rim") then
                SetViewRadius(ViewRadius() / 1.25)
            end
            if RingButton(draw_list, "ring_zoom_out", "-", center, half, "zoom_minus_angle",
                "Zoom out\nDrag to move this button around the rim") then
                SetViewRadius(ViewRadius() * 1.25)
            end
            if RingButton(draw_list, "ring_cut_up", "^", center, half, "cut_up_angle",
                CutTooltip(1)) then
                AdjustCutHeight(1)
            end
            if RingButton(draw_list, "ring_cut_down", "v", center, half, "cut_down_angle",
                CutTooltip(-1)) then
                AdjustCutHeight(-1)
            end
        else
            if state.show_border then
                draw_list:AddRect(ImVec2.new(origin.x, origin.y),
                    ImVec2.new(origin.x + view_px, origin.y + view_px),
                    border_color, 0, 0, 1.5)
            end

            -- Zoom and cut controls in the window corner
            ImGui.SetCursorScreenPos(origin.x + 4, origin.y + view_px - 24)
            if ImGui.SmallButton("-") then
                SetViewRadius(ViewRadius() * 1.25)
            end
            ImGui.SameLine()
            if ImGui.SmallButton("+") then
                SetViewRadius(ViewRadius() / 1.25)
            end
            ImGui.SameLine()
            if ImGui.SmallButton("^") then
                AdjustCutHeight(1)
            end
            Tooltip(CutTooltip(1))
            ImGui.SameLine()
            if ImGui.SmallButton("v") then
                AdjustCutHeight(-1)
            end
            Tooltip(CutTooltip(-1))
        end
    end
    ImGui.End()
    if font_pushed then
        ImGui.PopFont()
    end
end

-- ---------------------------------------------------------------------------
-- Settings / persistence
-- ---------------------------------------------------------------------------

-- The group member markers ride the compass ring, so they go with it, or
-- they would keep orbiting an empty spot on the screen.
local function ToggleCompass()
    if state.disable_compass then
        UI.DisableCompass()
        UI.DisableGroupCompassMarkers()
    else
        UI.EnableCompass()
        UI.EnableGroupCompassMarkers()
    end
end

local function TrackedEntitiesSettings()
    ImGui.Separator()
    ImGui.Text("Entity Tracking")
    state.entity_tracking_enabled  = ImGui.Checkbox("Enable Entity Tracking", state.entity_tracking_enabled)
    state.ping_tracked_entities    = ImGui.Checkbox("Ping Tracked Entities", state.ping_tracked_entities)
    state.line_to_tracked_entities = ImGui.Checkbox("Line to Tracked Entities", state.line_to_tracked_entities)

    -- The world map's pushed target lives outside the .entl list, shown here
    -- so it is obvious the two maps are talking.
    if state.db_track_active then
        ImGui.Text("World Map Target: " .. (state.db_track_display or state.db_track_name or "?"))
        ImGui.SameLine()
        -- The world map owns the target, so this only raises a stop request
        -- that it honors on its next frame.
        if ImGui.Button("Stop Tracking##dbtrack") then
            shared_globals.FF_Tracking_Stop = true
        end
    end
    ImGui.Text("Guidance Line")
    state.db_line_color = ImGui.ColorEdit4("Line Color", state.db_line_color, ImGuiColorEditFlags.NoInputs)
    state.db_line_thickness = ImGui.SliderFloat("Line Thickness", state.db_line_thickness, 1.0, 6.0)
    state.db_line_speed = ImGui.SliderFloat("Dash Speed", state.db_line_speed, 0, 120)

    ImGui.TextDisabled("Type a name and press Enter to track")
    local enter_returns_true_flag = (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0
    local new_text, enter_pressed = ImGui.InputText("Track Entity", state.tracked_entity_input, enter_returns_true_flag)
    state.tracked_entity_input = new_text
    if enter_pressed then
        AddTrackedEntity(state.tracked_entity_input)
        state.tracked_entity_input = ""
    end

    if state.tracked_entities_status ~= "" then
        ImGui.TextDisabled(state.tracked_entities_status)
    end

    if not ImGui.CollapsingHeader("Tracked Entities") then return end

    local active_file = SanitizeFileName(state.tracked_entities_file_name)

    ImGui.Text("Active List:")
    ImGui.SameLine()
    if ImGui.BeginCombo("##trackedEntitiesList", active_file) then
        if state.tracked_entities_combo_was_open ~= true then
            RefreshTrackedEntitiesAvailableLists()
        end
        state.tracked_entities_combo_was_open = true

        local lists = state.tracked_entities_available_lists or {}
        local active_key = active_file:lower()
        if #lists == 0 then
            ImGui.TextDisabled("(no .entl files found)")
        else
            for _, file_name in ipairs(lists) do
                local is_selected = (file_name:lower() == active_key)
                if ImGui.Selectable(file_name, is_selected) then
                    state.tracked_entities_file_name = SanitizeFileName(file_name)
                    LoadTrackedEntitiesFromFile()
                    state.tracked_entities_loaded = true
                    active_key = state.tracked_entities_file_name:lower()
                end
                if is_selected then
                    ImGui.SetItemDefaultFocus()
                end
            end
        end

        if state.tracked_entities_lists_status ~= "" then
            ImGui.Separator()
            ImGui.TextDisabled(state.tracked_entities_lists_status)
        end

        ImGui.EndCombo()
    else
        state.tracked_entities_combo_was_open = false
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

    for i = 1, #state.tracked_entities do
        local entry = state.tracked_entities[i]
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

--- A float slider that reads and types in hundredths. Ctrl+click turns it into
--- a text box, and whatever comes back (dragged or typed) is rounded to two
--- decimals and clamped to the range, so a typed 1000 cannot blow past the max.
local function SliderFloat(label, value, min, max)
    local new_value = ImGui.SliderFloat(label, value, min, max, "%.2f",
                                        ImGuiSliderFlags.AlwaysClamp)
    if new_value < min then new_value = min end
    if new_value > max then new_value = max end
    return math.floor(new_value * 100 + 0.5) / 100
end

local function Settings()
    TryLoadTrackedEntitiesOnce()

    ImGui.TextDisabled("Ctrl+click a slider to type an exact value")

    local mode = state.textured and "Textured" or "Flat"
    if ImGui.BeginCombo("Render Mode", mode) then
        if ImGui.Selectable("Textured", state.textured) and not state.textured then
            state.textured = true
            state.built = nil
        end
        if ImGui.Selectable("Flat", not state.textured) and state.textured then
            state.textured = false
            state.built = nil
        end
        ImGui.EndCombo()
    end
    Tooltip("Textured: draws the world's real textures from above, so roofs,\n"
        .. "roads, and terrain look like the world does.\n\n"
        .. "Flat: ignores textures and colors surfaces by height alone, low to\n"
        .. "high. Reads better in caves and open terrain, and builds faster.")

    if state.textured then
        local lighting = ImGui.Checkbox("World Lighting", state.world_lighting)
        if lighting ~= state.world_lighting then
            state.world_lighting = lighting
            state.built = nil
        end
        Tooltip("Tints the map with the world's own lighting, which follows the\n"
            .. "time of day. Torches and campfires glow, but at night most of\n"
            .. "the map goes black. Off shows the art unlit at full strength.")

        local brightness = SliderFloat("Brightness", state.brightness, 0.5, 3.0)
        if brightness ~= state.brightness then
            state.brightness = brightness
            state.built = nil
        end
        Tooltip("Multiplies the sampled texture colors. Raise it to lift dark\n"
            .. "dungeon art out of the murk, lower it to tone the map down.\n"
            .. "Colors are clamped, so pushing it high flattens toward white.")
    end

    local compass_disabled, compass_pressed = ImGui.Checkbox("Disable Compass", state.disable_compass)
    if compass_pressed then
        state.disable_compass = compass_disabled
        ToggleCompass()
    end

    state.view_size   = ImGui.SliderInt("Map Size (px)", state.view_size, 100, 600, "%d")
    state.view_radius = SliderFloat("Zoom (world radius)", state.view_radius,
                                    state.min_radius, state.max_radius)
    Tooltip("How much of the world the map covers, from the center to the edge,\n"
        .. "in world units. Smaller zooms in.")

    state.auto_zoom = ImGui.Checkbox("Auto Zoom Indoors", state.auto_zoom)
    Tooltip("Switches to the indoor zoom below whenever the ceiling probe finds\n"
        .. "a roof overhead, and back to the outdoor zoom under open sky.\n"
        .. "Needs Auto Ceiling Cut on, since that is what detects the roof.\n"
        .. "The two zooms are kept apart, so zooming while inside a cave does\n"
        .. "not disturb the zoom you set out in the world.")

    if state.auto_zoom then
        state.indoor_view_radius = SliderFloat("Indoor Zoom (world radius)",
            state.indoor_view_radius, state.min_radius, state.max_radius)
        Tooltip("The zoom used while a ceiling is overhead. Rooms and corridors\n"
            .. "want far less of the world on screen than a hillside does.")
        if not state.auto_ceiling then
            ImGui.TextDisabled("Auto Ceiling Cut is off, so no ceiling is ever detected")
        end
    end

    state.rotate_with_player = ImGui.Checkbox("Rotate With Player", state.rotate_with_player)

    if ImGui.BeginCombo("Map Font", state.font_name) then
        for _, font in ipairs(MAP_FONTS) do
            if ImGui.Selectable(font.name, font.name == state.font_name) then
                state.font_name = font.name
            end
        end
        ImGui.EndCombo()
    end
    state.font_size = ImGui.SliderInt("Font Size (px)", state.font_size, 8, 32, "%d")
    Tooltip("The font for the clock, the rim buttons, and the map's tooltips.")

    ImGui.Separator()
    ImGui.Text("Height Slicing")
    local auto = ImGui.Checkbox("Auto Ceiling Cut", state.auto_ceiling)
    if auto ~= state.auto_ceiling then
        state.auto_ceiling = auto
        state.probe = nil
        state.built = nil
    end

    if state.auto_ceiling then
        ImGui.TextDisabled(state.indoors and "under a ceiling, cutting below it"
                           or "open sky, showing everything")
        local margin = SliderFloat("Cut Below Ceiling", state.ceiling_margin, 0, 20)
        if margin ~= state.ceiling_margin then
            state.ceiling_margin = margin
            state.built = nil
        end
        Tooltip("How far under the ceiling the map slices once a ceiling is\n"
            .. "found. Raise it if the roof itself bleeds into the map, lower\n"
            .. "it to keep rafters, lofts, and upper shelves visible.")

        local clearance = SliderFloat("Head Clearance", state.head_clearance, 0, 60)
        if clearance ~= state.head_clearance then
            state.head_clearance = clearance
            state.probe = nil
            state.built = nil
        end
        Tooltip("Geometry closer than this above you is ignored when looking for\n"
            .. "a ceiling, so a low doorframe or an overhang you are brushing\n"
            .. "does not count as a roof. Raise it if the map keeps cutting low\n"
            .. "when you are actually outdoors.")

        local search = SliderFloat("Ceiling Search Height", state.ceiling_search, 20, 600)
        if search ~= state.ceiling_search then
            state.ceiling_search = search
            state.probe = nil
            state.built = nil
        end
        Tooltip("How far overhead to look before giving up and calling it open\n"
            .. "sky. Raise it for tall cathedral rooms and big cave ceilings,\n"
            .. "lower it so distant overhead terrain (a bridge, a cliff you are\n"
            .. "under) stops reading as indoors.")
    else
        local ceiling = SliderFloat("Ceiling Cut", state.ceiling_offset, 0, 600)
        if ceiling ~= state.ceiling_offset then
            state.ceiling_offset = ceiling
            state.built = nil
        end
        Tooltip("Cuts away geometry that starts higher than this above you, so a\n"
            .. "roof or the terrain overhead stops hiding the room you are in.")
    end

    if not state.textured then
        state.floor_range = SliderFloat("Shade Range Below", state.floor_range, 20, 400)
        local above = SliderFloat("Shade Range Above", state.above_range, 20, 600)
        if above ~= state.above_range then
            state.above_range = above
            state.built = nil
        end
    end

    ImGui.Separator()
    ImGui.Text("Overlay")
    state.circular = ImGui.Checkbox("Circular Frame", state.circular)
    Tooltip("Draws the map as a disc with the zoom and cut height buttons\n"
        .. "sitting on the rim. Drag a rim button to slide it around the\n"
        .. "circumference. Rotate With Player still uses the square map,\n"
        .. "since a rotated image cannot be clipped to a circle.")
    if state.circular and state.rotate_with_player then
        ImGui.TextDisabled("Rotate With Player is on, so the square map is shown")
    end
    if state.circular then
        state.show_clock = ImGui.Checkbox("Clock On The Rim", state.show_clock)
        Tooltip("Your machine's local time, in a rounded box pinned to the\n"
            .. "bottom of the rim. The rim buttons cannot be dragged onto it.")
        if state.show_clock then
            state.clock_24h = ImGui.Checkbox("24 Hour Clock", state.clock_24h)
        end
    end
    state.show_player   = ImGui.Checkbox("Show Player Arrow", state.show_player)
    state.show_border   = ImGui.Checkbox("Show Border", state.show_border)
    state.border_color  = ImGui.ColorEdit4("Border Color", state.border_color)
    state.background_color = ImGui.ColorEdit4("Background", state.background_color)

    ImGui.Separator()
    ImGui.Text("Entities")
    state.show_entities  = ImGui.Checkbox("Show Entities", state.show_entities)
    state.entity_radius  = SliderFloat("Entity Size", state.entity_radius, 1, 6)
    state.entity_y_range = SliderFloat("Entity Height Range", state.entity_y_range, 10, 300)
    state.show_entity_border      = ImGui.Checkbox("Show Entity Border", state.show_entity_border)
    state.entity_border_thickness = SliderFloat("Entity Border Thickness",
        state.entity_border_thickness, 0, math.max(1, state.entity_radius - 1))
    state.entity_border_color     = ImGui.ColorEdit4("Entity Border Color", state.entity_border_color)

    TrackedEntitiesSettings()

    ImGui.Separator()
    ImGui.Text("Performance")
    state.tris_per_frame = ImGui.SliderInt("Triangles / Frame", state.tris_per_frame, 1000, 40000, "%d")
    Tooltip("How much of the map is drawn each frame. The map rebuilds over\n"
        .. "several frames as you move, and the old one stays on screen until\n"
        .. "the new one is done. Raise it so the map keeps up while running,\n"
        .. "lower it if rebuilding costs you frames in game.")

    state.tex_size = ImGui.SliderInt("Texture Size", state.tex_size, 256, 1024, "%d")
    Tooltip("Resolution of the map image, in pixels per side. Higher is sharper\n"
        .. "when zoomed in, but every rebuild costs more to rasterize and\n"
        .. "upload. 512 is a good balance.")

    ImGui.TextDisabled(string.format("last build: %d tris, %d rooms",
        state.debug_stats.tris, state.debug_stats.cells))
end

-- Returns a plain data table of every user customizable option. The tracked
-- entity entries themselves live in .entl files, so only the active list file
-- name and the tracking toggles are saved here.
local function Save()
    return {
        textured = state.textured,
        world_lighting = state.world_lighting,
        brightness = state.brightness,
        view_size = state.view_size,
        view_radius = state.view_radius,
        auto_zoom = state.auto_zoom,
        indoor_view_radius = state.indoor_view_radius,
        rotate_with_player = state.rotate_with_player,
        auto_ceiling = state.auto_ceiling,
        ceiling_offset = state.ceiling_offset,
        ceiling_margin = state.ceiling_margin,
        head_clearance = state.head_clearance,
        ceiling_search = state.ceiling_search,
        floor_range = state.floor_range,
        above_range = state.above_range,
        tex_size = state.tex_size,
        tris_per_frame = state.tris_per_frame,
        show_player = state.show_player,
        show_border = state.show_border,
        border_color = state.border_color,
        background_color = state.background_color,

        circular = state.circular,
        zoom_plus_angle = state.zoom_plus_angle,
        zoom_minus_angle = state.zoom_minus_angle,
        cut_up_angle = state.cut_up_angle,
        cut_down_angle = state.cut_down_angle,
        show_clock = state.show_clock,
        clock_24h = state.clock_24h,

        show_entities = state.show_entities,
        entity_radius = state.entity_radius,
        entity_y_range = state.entity_y_range,
        show_entity_border = state.show_entity_border,
        entity_border_color = state.entity_border_color,
        entity_border_thickness = state.entity_border_thickness,
        entity_red_color = state.entity_red_color,
        entity_yellow_color = state.entity_yellow_color,
        entity_white_color = state.entity_white_color,
        entity_dark_blue_color = state.entity_dark_blue_color,
        entity_light_blue_color = state.entity_light_blue_color,
        entity_green_color = state.entity_green_color,
        entity_gray_color = state.entity_gray_color,

        entity_tracking_enabled = state.entity_tracking_enabled,
        ping_tracked_entities = state.ping_tracked_entities,
        line_to_tracked_entities = state.line_to_tracked_entities,
        tracked_entities_file_name = state.tracked_entities_file_name,
        db_line_color = state.db_line_color,
        db_line_thickness = state.db_line_thickness,
        db_line_speed = state.db_line_speed,

        disable_compass = state.disable_compass,

        font_name = state.font_name,
        font_size = state.font_size,
    }
end

local function Load(saved)
    if type(saved) ~= "table" then return end

    -- Copy a saved value only when its type matches the current one, so a hand
    -- edited or stale profile cannot corrupt the state table.
    for key, value in pairs(saved) do
        if key ~= "disable_compass" and key ~= "tracked_entities_file_name"
           and state[key] ~= nil and type(value) == type(state[key]) then
            state[key] = value
        end
    end

    -- Reapply the compass patch unconditionally. Disabling the script restores
    -- the game compass without changing this setting, so the game UI can be out
    -- of sync with the saved value even when the two compare equal.
    if type(saved.disable_compass) == "boolean" then
        state.disable_compass = saved.disable_compass
    end
    ToggleCompass()

    if type(saved.tracked_entities_file_name) == "string" and saved.tracked_entities_file_name ~= "" then
        state.tracked_entities_file_name = SanitizeFileName(saved.tracked_entities_file_name)
        state.tracked_entities_file_name_buffer = state.tracked_entities_file_name
        LoadTrackedEntitiesFromFile()
        state.tracked_entities_loaded = true
    end

    state.probe = nil
    state.built = nil
end

local function Cleanup()
    UI.EnableCompass()
    UI.EnableGroupCompassMarkers()
    if state.texture ~= nil then
        UiForge.ReleaseTexture(state.texture)
        state.texture = nil
    end
    state.built = nil
    state.rebuild = nil
    state.probe = nil
    WorldGeometry.ClearCache()
    state.initialized = false
end

local function Initialize()
    ToggleCompass()
    TryLoadTrackedEntitiesOnce()
    state.initialized = true
end

local function RegisterSettings()
    UiForge.RegisterCallback(UiForge.CallbackType.Settings, Settings)
    UiForge.RegisterCallback(UiForge.CallbackType.Save, Save)
    UiForge.RegisterCallback(UiForge.CallbackType.Load, Load)
    UiForge.RegisterCallback(UiForge.CallbackType.DisableScript, Cleanup)
    UiForge.RegisterCallback(UiForge.CallbackType.OnEject, Cleanup)
    state.settings_registered = true
end

if state.initialized == false then Initialize() end
if state.settings_registered == false then RegisterSettings() end
if state.initialized then Render() end
