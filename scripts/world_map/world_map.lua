--[[

AUTHORS: Avoids and Wereoxx

world_map.lua

A full-screen world map for EQOA. Shows a map image for every world (Tunaria,
Rathe, Odus, Solusek's Eye, Plane of Sky, and the hidden planes) with zoom, pan,
follow, your position and facing arrow, and city labels, using the same
world<->texture coordinate math as mini_map.lua. Tunaria uses the hand made map
art, the other worlds use maps rendered from the game's own world geometry.

On top of the map it adds an entity search in the side panel. It searches a
shipped entity database (scripts\resources\entity_database.json) by name (fuzzy
or exact) and/or level range, listing matches as "Name (Lvl X-Y)". Every match's
recorded spawns are highlighted on the map with an uncertainty area, since the
recorded positions are old and only approximate, and overlapping areas merge into
one covering ellipse per cluster. Selecting a creature in the list narrows the
highlights to just that creature.

A selected target can also be handed to the minimap for live tracking through the
shared _G.FF_Tracking table. The minimap then guides the player toward the
nearest recorded spawn and pings the creature once it is actually nearby.
]]

local Player = require("frontiers_forge.player")
local Util = require("frontiers_forge.util")
local EntityList = require("frontiers_forge.entity_list")
local EntityDb = require("entity_db")
local EntitySearch = require("entity_search")
local Journal = require("journal")

-- Each ForgeScript runs in a private environment whose _G is itself, so
-- writes to _G stay invisible to other scripts. getfenv(0) is the thread's
-- real global table, the one place all scripts can actually meet.
local shared_globals = getfenv(0)

world_map_state = world_map_state or {
    initialized                 = false,
    callbacks_registered        = false,

    player_indicator_border_texture      = nil,
    player_indicator_fill_texture        = nil,

    -- Which world's map is on screen and the lazily loaded per world textures.
    view_world                   = 0,
    world_textures               = {},
    world_texture_failed         = {},
    map_was_open                 = false,
    last_player_world            = -1,

    -- Bounds and texture size of the world currently on screen, refreshed each
    -- frame from the WORLDS table so all the coordinate math stays one code path.
    world_min_x                  = 0,
    world_min_z                  = 0,
    world_width                  = 28000,
    world_height                 = 34000,
    map_texture_width            = 14784,
    map_texture_height           = 17952,

    default_texture_border_color = ImVec4.new(0, 0, 0, 0),

    show_world_map               = false,
    disable_in_start_menu        = false,

    -- Transient drag state (see Render for why the rect is remembered a frame).
    map_drag_active              = false,
    last_map_origin_x            = nil,
    last_map_origin_y            = nil,
    last_map_display_width       = 0,
    last_map_display_height      = 0,

    -- Control panel
    controls_collapsed           = false,

    -- Zoom / pan
    map_zoom                     = 1.0,
    follow_player                = true,
    pan_center_x                 = 0.5,
    pan_center_z                 = 0.5,
    pan_step                     = 0.05,

    -- Map appearance
    map_tint                     = {1, 1, 1, 1},
    show_map_border              = true,
    map_border_color             = {0, 0, 0, 1},
    map_border_thickness         = 2.0,

    -- Position dot
    show_player_marker_dot            = true,
    player_marker_radius              = 6,
    player_marker_fill_color          = {0, 1, 0, 1},
    show_player_marker_border         = true,
    player_marker_border_color        = {0, 0, 0, 1},
    player_marker_border_thickness    = 1.5,

    -- Facing-direction arrow
    show_facing_arrow            = true,
    show_facing_arrow_border     = true,
    facing_arrow_width           = 24,
    facing_arrow_height          = 24,
    facing_arrow_scale           = 1.0,
    facing_arrow_fill_color      = {0, 1, 0, 1},
    facing_arrow_border_color    = {0, 0, 0, 1},

    -- City labels
    show_city_labels             = true,
    show_estimated_cities        = true,
    city_label_min_zoom          = 2.0,
    font_scale                   = 1.0,
    show_city_dot                = true,
    city_dot_radius              = 3,
    city_label_good_color        = {0.4, 1.0, 0.5, 1.0},
    city_label_evil_color        = {1.0, 0.35, 0.35, 1.0},
    city_label_neutral_color     = {0.5, 0.75, 1.0, 1.0},

    -- Target search / uncertainty overlay
    database_loaded              = false,
    database_status              = "",
    search_input                 = "",
    search_debounce              = 0.25,      -- seconds of quiet before a search runs
    search_pending               = false,
    search_change_time           = 0,
    search_results               = {},        -- entries from the last completed search
    search_max_results           = 100,
    search_show_all              = true,       -- ignore the cap and list every match
    match_exact                  = false,      -- exact whole-name match instead of fuzzy
    selected_entry               = nil,        -- entry whose rings are drawn on the map

    -- Which sources feed the search. The journal is the personal database the
    -- player builds by playing, the database is the shipped baseline.
    search_source_journal        = true,
    search_source_database       = false,

    -- Journal recording and merge UI
    journal_loaded               = false,
    journal_status               = "",
    last_record_scan             = 0,
    journal_merge_files          = {},
    journal_merge_selected       = "",
    journal_merge_status         = "",
    journal_merge_combo_was_open = false,

    -- Last frame's view crop, remembered so the control panel (drawn before the
    -- map) can convert the mouse position into world coordinates.
    last_uv0_x                   = 0,
    last_uv0_z                   = 0,
    last_view_frac_w             = 1,
    last_view_frac_h             = 1,

    -- Level range search. When enabled, the list shows creatures whose level
    -- range touches [level_search_min, level_search_max], and every match's
    -- spawn areas are highlighted on the map as clickable regions.
    level_search_enabled         = false,
    level_search_min             = 1,
    level_search_max             = 10,
    show_search_regions          = true,
    search_regions               = {},         -- built from the last search, see BuildSearchRegions
    region_fill_color            = {0.35, 0.60, 1.0, 0.25},
    region_border_color          = {0.25, 0.45, 0.90, 1.0},
    region_tooltip_max_names     = 12,

    uncertainty_range            = 50,         -- estimated area diameter in world units
    min_marker_pixel_radius      = 6,          -- highlights never draw smaller than this on screen

    -- Minimap hand-off
    tracked_entry                = nil,        -- entry currently published to the minimap
    tracking_revision            = 0,
}

local state = world_map_state

--[[
City label data. CONFIRMED entries are live in-game "Raw coords" readings.
ESTIMATED entries are IDW-corrected from the confirmed anchors and are only
approximate. See avoids_modern_ui_mods.lua for the full derivation notes.
]]
local CITY_LABELS = {
    { name = "Freeport", fraction_x = 0.9059, fraction_z = 0.4550, alignment = "neutral", estimated = false },
    { name = "Oggok", fraction_x = 0.3121, fraction_z = 0.2160, alignment = "evil", estimated = false },
    { name = "Neriak, Nektulos", fraction_x = 0.8929, fraction_z = 0.2571, alignment = "evil", estimated = false },
    { name = "Halas", fraction_x = 0.4749, fraction_z = 0.1268, alignment = "good", estimated = false },
    { name = "Qeynos", fraction_x = 0.1627, fraction_z = 0.5032, alignment = "good", estimated = false },
    { name = "Grobb", fraction_x = 0.9024, fraction_z = 0.9243, alignment = "evil", estimated = false },
    { name = "Temby", fraction_x = 0.9139, fraction_z = 0.3923, alignment = "neutral", estimated = false },

    { name = "Klick'Anon", fraction_x = 0.8400, fraction_z = 0.1776, alignment = "neutral", estimated = true },
    { name = "Zentar's Keep", fraction_x = 0.2239, fraction_z = 0.1597, alignment = "evil", estimated = true },
    { name = "Fayspire", fraction_x = 0.6989, fraction_z = 0.1855, alignment = "good", estimated = true },
    { name = "Tethelin", fraction_x = 0.6609, fraction_z = 0.1955, alignment = "good", estimated = true },
    { name = "Bobble-by-Water", fraction_x = 0.8811, fraction_z = 0.3260, alignment = "good", estimated = true },
    { name = "Castle Lightwolf", fraction_x = 0.3538, fraction_z = 0.1675, alignment = "good", estimated = true },
    { name = "Moradhim", fraction_x = 0.5532, fraction_z = 0.2366, alignment = "good", estimated = true },
    { name = "Castle Felstar", fraction_x = 0.7853, fraction_z = 0.2271, alignment = "evil", estimated = true },
    { name = "Rivervale", fraction_x = 0.6609, fraction_z = 0.2936, alignment = "good", estimated = true },
    { name = "Wyndhaven", fraction_x = 0.1682, fraction_z = 0.3663, alignment = "neutral", estimated = true },
    { name = "Murnf", fraction_x = 0.3283, fraction_z = 0.2662, alignment = "good", estimated = true },
    { name = "Mt. Hatespike", fraction_x = 0.4958, fraction_z = 0.2829, alignment = "evil", estimated = true },
    { name = "Surefall Glade", fraction_x = 0.3205, fraction_z = 0.3315, alignment = "good", estimated = true },
    { name = "Honjour", fraction_x = 0.3390, fraction_z = 0.3758, alignment = "evil", estimated = true },
    { name = "Darvar Manor", fraction_x = 0.4808, fraction_z = 0.3474, alignment = "neutral", estimated = true },
    { name = "Highpass Hold", fraction_x = 0.5981, fraction_z = 0.3721, alignment = "neutral", estimated = true },
    { name = "Muniel's Tea Garden", fraction_x = 0.8319, fraction_z = 0.5263, alignment = "neutral", estimated = true },
    { name = "Highbourne", fraction_x = 0.1642, fraction_z = 0.5123, alignment = "good", estimated = true },
    { name = "Forkwatch", fraction_x = 0.4256, fraction_z = 0.3825, alignment = "good", estimated = true },
    { name = "Dark Solace", fraction_x = 0.4157, fraction_z = 0.3501, alignment = "evil", estimated = true },
    { name = "Hazinak", fraction_x = 0.8808, fraction_z = 0.7853, alignment = "good", estimated = true },
    { name = "Hazinak", fraction_x = 0.8872, fraction_z = 0.7669, alignment = "evil", estimated = true },
    { name = "Blackwater", fraction_x = 0.4987, fraction_z = 0.3711, alignment = "good", estimated = true },
    { name = "Oasis", fraction_x = 0.7364, fraction_z = 0.6148, alignment = "neutral", estimated = true },
    { name = "Gerntar Mines", fraction_x = 0.3857, fraction_z = 0.2677, alignment = "good", estimated = true },
    { name = "Kerplunk Outpost", fraction_x = 0.4656, fraction_z = 0.4235, alignment = "evil", estimated = true },
}

--[[
Per world map configuration, indexed by the game's world id. Each entry gives
the texture file (relative to resources) plus the world-space rectangle that
texture covers, so any recorded position maps onto its pixel. Tunaria keeps the
hand made map art. The other maps are rendered from the world geometry in the
game's .esf files, and their bounds are the geometry bounds of that render.
]]
local WORLDS = {
    [0] = { name = "Tunaria",       file = "tunaria.jpg",
            min_x = 0, min_z = 0, width = 28000, height = 34000,
            tex_w = 6746, tex_h = 8192 },
    [1] = { name = "Rathe Mountains", file = "rathe.jpg",
            min_x = 2000, min_z = 0, width = 8000, height = 12000,
            tex_w = 4001, tex_h = 6001 },
    [2] = { name = "Odus",          file = "odus.jpg",
            min_x = 2000, min_z = 0, width = 12000, height = 14000,
            tex_w = 6001, tex_h = 7001 },
    [3] = { name = "Solusek's Eye", file = "lavastm.jpg",
            min_x = 4357, min_z = 4000, width = 3643, height = 2000,
            tex_w = 1822, tex_h = 1001 },
    [4] = { name = "Plane of Sky",  file = "planesky.jpg",
            min_x = 4055, min_z = 4062, width = 1930, height = 3876,
            tex_w = 965, tex_h = 1939 },
    [5] = { name = "Hidden Planes", file = "secrets.jpg",
            min_x = 2000, min_z = 2000, width = 6000, height = 8000,
            tex_w = 3001, tex_h = 4001 },
}
local WORLD_ORDER = { 0, 1, 2, 3, 4, 5 }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Clamp01(value)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

-- Old database entries carry no world, they are all Tunaria-era data.
local function SpawnWorld(spawn)
    return spawn.world or 0
end

local function GetWorldConfig(world_id)
    return WORLDS[world_id] or WORLDS[0]
end

-- This package's own resources folder, scripts\world_map\resources.
local RESOURCES_DIR = UiForge.scripts_path .. "\\world_map\\resources"
local SHARED_RESOURCES_DIR = UiForge.scripts_path .. "\\resources"

-- Loads a world's map texture on first use. A failed load is remembered so a
-- missing file does not retry every frame.
local function GetWorldTexture(world_id)
    if WORLDS[world_id] == nil then world_id = 0 end
    if state.world_textures[world_id] == nil and not state.world_texture_failed[world_id] then
        local texture = UiForge.IGraphicsApi.CreateTextureFromFile(
            RESOURCES_DIR .. "\\" .. WORLDS[world_id].file)
        if texture ~= nil then
            state.world_textures[world_id] = texture
        else
            state.world_texture_failed[world_id] = true
        end
    end
    return state.world_textures[world_id]
end

local function GetCityLabelColor(state, alignment)
    if alignment == "good" then return state.city_label_good_color end
    if alignment == "evil" then return state.city_label_evil_color end
    return state.city_label_neutral_color
end

-- Same rotation math as mini_map.lua's DrawRotatedImage.
local function DrawRotatedImage(texture, center, dimensions, angle_of_orientation, target_angle, tint)
    local draw_list = ImGui.GetWindowDrawList()

    local rotation_angle = target_angle + angle_of_orientation
    local cos_theta = math.cos(rotation_angle)
    local sin_theta = math.sin(rotation_angle)

    local half_width = dimensions.x * 0.5
    local half_height = dimensions.y * 0.5

    local corners = {
        ImVec2.new(-half_width, -half_height),
        ImVec2.new(half_width, -half_height),
        ImVec2.new(half_width, half_height),
        ImVec2.new(-half_width, half_height)
    }

    for i, corner in ipairs(corners) do
        local rotated_x = corner.x * sin_theta - corner.y * cos_theta
        local rotated_y = corner.x * cos_theta + corner.y * sin_theta
        corners[i] = ImVec2.new(center.x + rotated_x, center.y + rotated_y)
    end

    local uv0 = ImVec2.new(0.0, 0.0)
    local uv1 = ImVec2.new(1.0, 0.0)
    local uv2 = ImVec2.new(1.0, 1.0)
    local uv3 = ImVec2.new(0.0, 1.0)

    local image_tint = ImGui.GetColorU32(tint[1], tint[2], tint[3], tint[4])

    draw_list:AddImageQuad(texture, corners[1], corners[2], corners[3], corners[4], uv0, uv1, uv2, uv3, image_tint)
end

-- Draws an axis-aligned ellipse. The binding has no ellipse primitive, so the
-- fill is a triangle fan from the center and the outline is a closed polyline.
local function DrawEllipse(draw_list, center_x, center_y, radius_x, radius_y, outline_u32, fill_u32, thickness)
    local segments = 40
    local points = {}
    for i = 0, segments - 1 do
        local angle = (2 * math.pi) * i / segments
        points[i + 1] = ImVec2.new(center_x + radius_x * math.cos(angle), center_y + radius_y * math.sin(angle))
    end

    if fill_u32 ~= nil then
        local center = ImVec2.new(center_x, center_y)
        for i = 1, segments do
            local next_index = (i % segments) + 1
            draw_list:AddTriangleFilled(center, points[i], points[next_index], fill_u32)
        end
    end

    if outline_u32 ~= nil then
        for i = 1, segments do
            local next_index = (i % segments) + 1
            draw_list:AddLine(points[i], points[next_index], outline_u32, thickness or 1.5)
        end
    end
end

--------------------------------------------------------------------------------
-- Settings persistence (UiForge Save/Load callbacks)
--------------------------------------------------------------------------------

local PERSISTED_SETTINGS = {
    "show_world_map",
    "disable_in_start_menu",
    "view_world",
    "controls_collapsed",

    "map_zoom",
    "follow_player",
    "pan_step",

    "map_tint",
    "show_map_border",
    "map_border_color",
    "map_border_thickness",

    "show_player_marker_dot",
    "player_marker_radius",
    "player_marker_fill_color",
    "show_player_marker_border",
    "player_marker_border_color",
    "player_marker_border_thickness",

    "show_facing_arrow",
    "show_facing_arrow_border",
    "facing_arrow_scale",
    "facing_arrow_fill_color",
    "facing_arrow_border_color",

    "show_city_labels",
    "show_estimated_cities",
    "city_label_min_zoom",
    "font_scale",
    "show_city_dot",
    "city_dot_radius",
    "city_label_good_color",
    "city_label_evil_color",
    "city_label_neutral_color",

    "match_exact",
    "search_source_journal",
    "search_source_database",
    "search_show_all",
    "search_max_results",
    "level_search_enabled",
    "level_search_min",
    "level_search_max",
    "show_search_regions",
    "region_fill_color",
    "region_border_color",

    "uncertainty_range",
}

local function Save()
    local saved = {}
    for _, key in ipairs(PERSISTED_SETTINGS) do
        saved[key] = state[key]
    end
    return saved
end

local function Load(saved)
    if type(saved) ~= "table" then return end
    -- Copy a saved value only when its type matches the current one, so a hand
    -- edited or stale profile cannot corrupt the state table.
    for _, key in ipairs(PERSISTED_SETTINGS) do
        local value = saved[key]
        if value ~= nil and type(value) == type(state[key]) then
            state[key] = value
        end
    end
end

--------------------------------------------------------------------------------
-- Target search + minimap hand-off
--------------------------------------------------------------------------------

-- Groups every spawn of every search result into map regions. Spawns whose
-- uncertainty rings would touch are merged with union-find, using a spatial grid
-- so a broad level search (a thousand plus spawns) stays cheap. Each region
-- remembers its world bounding box and the creatures inside it. When a creature
-- is selected in the list, only its own spawns are highlighted.
local function BuildSearchRegions()
    state.search_regions = {}

    local source = state.search_results
    if state.selected_entry ~= nil then
        source = { state.selected_entry }
    end
    if #source == 0 then return end

    -- Only spawns on the world being viewed, coordinates from different worlds
    -- share nothing and would merge into nonsense regions.
    local spawns = {}
    for _, entry in ipairs(source) do
        for _, spawn in ipairs(entry.spawns) do
            if SpawnWorld(spawn) == state.view_world then
                spawns[#spawns + 1] = { x = spawn.x, z = spawn.z, entry = entry }
            end
        end
    end
    if #spawns == 0 then return end

    local overlap = state.uncertainty_range   -- rings touch when centers are within one diameter
    local overlap_sq = overlap * overlap

    local parent = {}
    for i = 1, #spawns do parent[i] = i end
    local function Find(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end
        return i
    end

    -- Bucket spawns into overlap-sized cells, then only compare each spawn against
    -- the spawns in its own and neighboring cells.
    local grid = {}
    local cell_of = {}
    for i, spawn in ipairs(spawns) do
        local cell_x = math.floor(spawn.x / overlap)
        local cell_z = math.floor(spawn.z / overlap)
        local key = cell_x .. ":" .. cell_z
        cell_of[i] = { cell_x, cell_z }
        local bucket = grid[key]
        if bucket == nil then bucket = {}; grid[key] = bucket end
        bucket[#bucket + 1] = i
    end

    for i, spawn in ipairs(spawns) do
        local cell_x, cell_z = cell_of[i][1], cell_of[i][2]
        for dx = -1, 1 do
            for dz = -1, 1 do
                local bucket = grid[(cell_x + dx) .. ":" .. (cell_z + dz)]
                if bucket ~= nil then
                    for _, j in ipairs(bucket) do
                        if j > i then
                            local ddx = spawn.x - spawns[j].x
                            local ddz = spawn.z - spawns[j].z
                            if (ddx * ddx + ddz * ddz) < overlap_sq then
                                parent[Find(i)] = Find(j)
                            end
                        end
                    end
                end
            end
        end
    end

    local regions_by_root = {}
    for i, spawn in ipairs(spawns) do
        local root = Find(i)
        local region = regions_by_root[root]
        if region == nil then
            region = {
                min_x = math.huge, max_x = -math.huge,
                min_z = math.huge, max_z = -math.huge,
                entries = {}, entry_seen = {}, names = {},
            }
            regions_by_root[root] = region
        end
        if spawn.x < region.min_x then region.min_x = spawn.x end
        if spawn.x > region.max_x then region.max_x = spawn.x end
        if spawn.z < region.min_z then region.min_z = spawn.z end
        if spawn.z > region.max_z then region.max_z = spawn.z end
        if not region.entry_seen[spawn.entry] then
            region.entry_seen[spawn.entry] = true
            region.entries[#region.entries + 1] = spawn.entry
            region.names[#region.names + 1] = spawn.entry.name
        end
    end

    for _, region in pairs(regions_by_root) do
        region.entry_seen = nil
        region.center_x = (region.min_x + region.max_x) / 2
        region.center_z = (region.min_z + region.max_z) / 2
        region.half_x = (region.max_x - region.min_x) / 2
        region.half_z = (region.max_z - region.min_z) / 2
        table.sort(region.names)
        state.search_regions[#state.search_regions + 1] = region
    end
end

-- Switches the map to another world and rebuilds the highlight regions, which
-- only ever hold spawns on the viewed world.
local function SetViewWorld(world_id)
    if WORLDS[world_id] == nil then world_id = 0 end
    if world_id ~= state.view_world then
        state.view_world = world_id
        BuildSearchRegions()
    end
end

-- The world to show for a just-selected creature. Stays put when the creature
-- has spawns on the current world, otherwise jumps to its first spawn's world.
local function ViewWorldForEntry(entry)
    for _, spawn in ipairs(entry.spawns) do
        if SpawnWorld(spawn) == state.view_world then return state.view_world end
    end
    local first = entry.spawns[1]
    if first ~= nil then return SpawnWorld(first) end
    return state.view_world
end

-- One combined entry list from whichever sources are enabled, same-named
-- creatures merged so a rat known to both shows as a single entry whose level
-- range and spawn list cover both sources.
local function ActiveSearchEntries()
    local lists = {}
    if state.search_source_journal and state.journal_loaded then
        lists[#lists + 1] = Journal.GetEntries()
    end
    if state.search_source_database and state.database_loaded then
        lists[#lists + 1] = EntityDb.GetEntries()
    end
    return EntitySearch.Aggregate(lists)
end

local function RunSearch()
    local entries = ActiveSearchEntries()
    local max_results = state.search_show_all and 0 or state.search_max_results
    if state.level_search_enabled then
        state.search_results = EntitySearch.SearchByLevel(entries,
            state.level_search_min, state.level_search_max,
            state.search_input, max_results, state.match_exact)
    else
        state.search_results = EntitySearch.Search(entries,
            state.search_input, max_results, state.match_exact)
    end
    -- A new search replaces the old context, so any previous selection goes too.
    state.selected_entry = nil
    BuildSearchRegions()
end

-- Publishes the current tracked target to the shared table the minimap reads.
-- Only the fields the minimap needs are written, so the two mods stay decoupled
-- behind a small, stable contract.
local function PublishTracking()
    local entry = state.tracked_entry
    if entry == nil then
        shared_globals.FF_Tracking = nil
        return
    end

    local zones = {}
    for _, spawn in ipairs(entry.spawns) do
        zones[#zones + 1] = { world = spawn.world, x = spawn.x, z = spawn.z }
    end

    shared_globals.FF_Tracking = {
        revision   = state.tracking_revision,
        name       = entry.name,
        level_min  = entry.level_min,
        level_max  = entry.level_max,
        active     = true,
        zones      = zones,
    }
end

local function SetTrackedEntry(entry)
    if state.tracked_entry ~= entry then
        state.tracking_revision = state.tracking_revision + 1
    end
    state.tracked_entry = entry
    PublishTracking()
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local function Initialize()
    if state.player_indicator_border_texture == nil then
        state.player_indicator_border_texture = UiForge.IGraphicsApi.CreateTextureFromFile(SHARED_RESOURCES_DIR .. "\\player_indicator_border.png")
    end
    if state.player_indicator_fill_texture == nil then
        state.player_indicator_fill_texture = UiForge.IGraphicsApi.CreateTextureFromFile(SHARED_RESOURCES_DIR .. "\\player_indicator_fill.png")
    end

    if not state.database_loaded then
        state.database_loaded = EntityDb.Load(UiForge.resources_path .. "\\entity_database.json")
        state.database_status = EntityDb.Status()
    end

    if not state.journal_loaded then
        state.journal_loaded = Journal.Load(UiForge.resources_path .. "\\journal.json")
        state.journal_status = Journal.Status()
    end

    state.initialized = true
end

--------------------------------------------------------------------------------
-- Journal recording
--------------------------------------------------------------------------------

local RECORD_SCAN_INTERVAL = 1.0

-- Walks the live entity list on a slow tick and journals every NPC in sight.
-- The scan itself is a few dozen reads a second at most, and everything else
-- is memory only, the journal file flushes on its own quiet timer.
local function RecordNearbyEntities()
    if not state.journal_loaded then return end
    if Util.IsInGame() == 0 then return end

    local now = ImGui.GetTime()
    if now - state.last_record_scan >= RECORD_SCAN_INTERVAL then
        state.last_record_scan = now
        local world = Util.GetWorldId()
        local entities = EntityList.GetAllEntities()
        -- Slot 1 is always the local player.
        for index = 2, #entities do
            local entity = entities[index]
            local id = entity:GetId()
            local name = entity:GetName()
            if id ~= 0 and name ~= "" and entity:IsNpc() then
                local x, y, z = entity:GetPosition()
                Journal.Record(name, id, world, entity:GetLevel(), x, y, z, now)
            end
        end
        state.journal_status = Journal.Status()
    end

    Journal.Flush(now)
end

--------------------------------------------------------------------------------
-- Settings tab
--------------------------------------------------------------------------------

-- The level range label for a search or journal entry.
local function EntryLabel(entry)
    local label
    if entry.level_min == nil then
        label = entry.name
    elseif entry.level_min == entry.level_max then
        label = string.format("%s (Lvl %d)", entry.name, entry.level_min)
    else
        label = string.format("%s (Lvl %d-%d)", entry.name, entry.level_min, entry.level_max)
    end
    return string.format("%s  [%d]", label, #entry.spawns)
end

-- The selected entry actions and active tracking status, shared by the Search
-- and Journal tabs since both can select and track a creature.
local function SelectionAndTrackingFooter()
    if state.selected_entry ~= nil then
        ImGui.Separator()
        ImGui.Text("Selected: " .. state.selected_entry.name)

        local is_tracked = (state.tracked_entry == state.selected_entry)
        if is_tracked then
            if ImGui.Button("Stop Tracking") then
                SetTrackedEntry(nil)
            end
        else
            if ImGui.Button("Track On Minimap") then
                SetTrackedEntry(state.selected_entry)
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Deselect") then
            state.selected_entry = nil
            BuildSearchRegions()
        end
    end

    if state.tracked_entry ~= nil then
        ImGui.TextColored(0.6, 1.0, 0.6, 1.0, "Tracking: " .. state.tracked_entry.name)
        ImGui.SameLine()
        if ImGui.Button("Stop Tracking##active") then
            SetTrackedEntry(nil)
        end
    end

    ImGui.Separator()
    local new_range = ImGui.SliderFloat("Est. Range", state.uncertainty_range, 10, 1000, string.format("%.0f units", state.uncertainty_range))
    if new_range ~= state.uncertainty_range then
        state.uncertainty_range = new_range
        BuildSearchRegions()   -- regroup the highlight regions to the new ring size
    end
end

-- The entity search UI, shown in the control panel beside the map. Searches the
-- enabled sources by name and/or level range, lists matches, and manages the
-- selected and tracked target.
local function EntitySearchSection()
    local function MarkSearchDirty()
        state.search_pending = true
        state.search_change_time = ImGui.GetTime()
    end

    ImGui.Text("Search Source:")
    ImGui.SameLine()
    local new_journal_source = ImGui.Checkbox("Journal##source", state.search_source_journal)
    if new_journal_source ~= state.search_source_journal then
        state.search_source_journal = new_journal_source
        MarkSearchDirty()
    end
    ImGui.SameLine()
    local new_database_source = ImGui.Checkbox("Database##source", state.search_source_database)
    if new_database_source ~= state.search_source_database then
        state.search_source_database = new_database_source
        MarkSearchDirty()
    end

    if state.search_source_database and not state.database_loaded then
        ImGui.TextColored(1.0, 0.5, 0.5, 1.0, "Database unavailable: " .. tostring(state.database_status))
    end
    if state.search_source_journal and not state.journal_loaded then
        ImGui.TextColored(1.0, 0.5, 0.5, 1.0, "Journal unavailable: " .. tostring(state.journal_status))
    end
    if not state.search_source_journal and not state.search_source_database then
        ImGui.TextColored(1.0, 0.8, 0.4, 1.0, "No source selected, nothing to search")
    end

    local new_input = ImGui.InputTextWithHint("##entity_search", "creature name", state.search_input)
    if new_input ~= state.search_input then
        state.search_input = new_input
        MarkSearchDirty()
    end
    ImGui.SameLine()
    if ImGui.Button("Clear") then
        state.search_input = ""
        state.search_pending = false
        state.search_results = {}
        state.selected_entry = nil
        state.search_regions = {}
    end

    local new_exact = ImGui.Checkbox("Match Exact", state.match_exact)
    if new_exact ~= state.match_exact then
        state.match_exact = new_exact
        MarkSearchDirty()
    end

    local new_level_enabled = ImGui.Checkbox("Level Range", state.level_search_enabled)
    if new_level_enabled ~= state.level_search_enabled then
        state.level_search_enabled = new_level_enabled
        MarkSearchDirty()
    end

    if state.level_search_enabled then
        local new_min = ImGui.InputInt("Min", state.level_search_min)
        local new_max = ImGui.InputInt("Max", state.level_search_max)
        if new_min < 0 then new_min = 0 end
        if new_max > 127 then new_max = 127 end
        -- Keep the pair ordered by dragging the other bound along.
        if new_min ~= state.level_search_min and new_min > new_max then new_max = new_min end
        if new_max ~= state.level_search_max and new_max < new_min then new_min = new_max end
        if new_min ~= state.level_search_min or new_max ~= state.level_search_max then
            state.level_search_min = new_min
            state.level_search_max = new_max
            MarkSearchDirty()
        end
    end

    -- Debounce: only run the search once typing has been quiet for a moment, so
    -- fast typing does not scan the whole database on every keystroke.
    if state.search_pending and (ImGui.GetTime() - state.search_change_time) >= state.search_debounce then
        RunSearch()
        state.search_pending = false
    end

    local new_show_all = ImGui.Checkbox("Show All Results", state.search_show_all)
    if new_show_all ~= state.search_show_all then
        state.search_show_all = new_show_all
        MarkSearchDirty()
    end
    if not state.search_show_all then
        local new_max = ImGui.InputInt("Max Results", state.search_max_results)
        if new_max < 1 then new_max = 1 end
        if new_max ~= state.search_max_results then
            state.search_max_results = new_max
            MarkSearchDirty()
        end
    end

    ImGui.Text(string.format("%d match%s", #state.search_results, (#state.search_results == 1) and "" or "es"))

    ImGui.BeginChild("target_search_results", 0, 180)
    for _, entry in ipairs(state.search_results) do
        local label = EntryLabel(entry)
        local is_selected = (state.selected_entry == entry)
        -- Clicking toggles: selecting narrows the highlights to this creature's
        -- spawns, clicking again brings the full result set back.
        if ImGui.Selectable(label, is_selected) then
            state.selected_entry = is_selected and nil or entry
            if state.selected_entry ~= nil then
                SetViewWorld(ViewWorldForEntry(state.selected_entry))
            end
            BuildSearchRegions()
        end
    end
    ImGui.EndChild()

    SelectionAndTrackingFooter()
end

local function RefreshJournalMergeFiles()
    local dir = tostring(UiForge.resources_path) .. "\\journals"
    local ok, files = pcall(Util.ListFilesInDir, dir, "*.json")
    if not ok or type(files) ~= "table" then
        state.journal_merge_files = {}
        state.journal_merge_status = "Put shared journals in resources\\journals\\"
        return
    end
    state.journal_merge_files = files
    if #files == 0 then
        state.journal_merge_status = "No .json files in resources\\journals\\"
    else
        state.journal_merge_status = ""
    end
end

-- The Journal tab: every creature the player has discovered, alphabetical,
-- selectable and trackable just like a search result, plus saving and merging.
local function JournalBrowseSection()
    if not state.journal_loaded then
        ImGui.TextColored(1.0, 0.5, 0.5, 1.0, "Journal unavailable: " .. tostring(state.journal_status))
        return
    end

    local creature_count, spawn_count = Journal.Counts()
    ImGui.Text(string.format("%d creature%s, %d recorded spawn%s",
        creature_count, creature_count == 1 and "" or "s",
        spawn_count, spawn_count == 1 and "" or "s"))
    if Journal.HasUnsavedChanges() then
        ImGui.SameLine()
        ImGui.TextDisabled("(unsaved)")
    end
    if ImGui.Button("Save Journal Now") then
        Journal.Save()
        state.journal_status = Journal.Status()
    end

    ImGui.BeginChild("journal_browse_list", 0, 220)
    for _, entry in ipairs(Journal.GetSortedEntries()) do
        local is_selected = (state.selected_entry == entry)
        if ImGui.Selectable(EntryLabel(entry), is_selected) then
            state.selected_entry = is_selected and nil or entry
            if state.selected_entry ~= nil then
                SetViewWorld(ViewWorldForEntry(state.selected_entry))
            end
            BuildSearchRegions()
        end
    end
    ImGui.EndChild()

    ImGui.Separator()
    ImGui.Text("Merge a Shared Journal")
    ImGui.TextDisabled("Drop a friend's journal .json into resources\\journals\\")

    if ImGui.BeginCombo("##journal_merge_file", state.journal_merge_selected ~= "" and state.journal_merge_selected or "(choose file)") then
        if not state.journal_merge_combo_was_open then
            RefreshJournalMergeFiles()
        end
        state.journal_merge_combo_was_open = true
        for _, file_name in ipairs(state.journal_merge_files) do
            if ImGui.Selectable(file_name, file_name == state.journal_merge_selected) then
                state.journal_merge_selected = file_name
            end
        end
        ImGui.EndCombo()
    else
        state.journal_merge_combo_was_open = false
    end

    ImGui.SameLine()
    if ImGui.Button("Merge") and state.journal_merge_selected ~= "" then
        local path = tostring(UiForge.resources_path) .. "\\journals\\" .. state.journal_merge_selected
        local added, merge_error = Journal.Merge(path, ImGui.GetTime())
        if added == nil then
            state.journal_merge_status = "Merge failed: " .. tostring(merge_error)
        else
            state.journal_merge_status = string.format("Merged %d new spawn%s from %s",
                added, added == 1 and "" or "s", state.journal_merge_selected)
            state.journal_status = Journal.Status()
        end
    end

    if state.journal_merge_status ~= "" then
        ImGui.TextDisabled(state.journal_merge_status)
    end

    SelectionAndTrackingFooter()
end

local function TargetSearchSettings()
    ImGui.Text("Search Highlights")
    state.show_search_regions = ImGui.Checkbox("Highlight Results On Map", state.show_search_regions)
    state.region_fill_color = ImGui.ColorEdit4("Highlight Fill", state.region_fill_color)
    state.region_border_color = ImGui.ColorEdit4("Highlight Border", state.region_border_color)
    local new_range = ImGui.SliderFloat("Estimated Range (world units)", state.uncertainty_range, 10, 1000, string.format("%.0f", state.uncertainty_range))
    if new_range ~= state.uncertainty_range then
        state.uncertainty_range = new_range
        BuildSearchRegions()   -- regroup the highlight regions to the new ring size
    end
end

local function Settings()
    state.show_world_map = ImGui.Checkbox("Show World Map", state.show_world_map)
    state.disable_in_start_menu = ImGui.Checkbox("Hide While Start Menu Is Open", state.disable_in_start_menu)

    ImGui.Separator()
    TargetSearchSettings()

    ImGui.Separator()
    ImGui.Text("Map Appearance")
    state.map_tint            = ImGui.ColorEdit4("Map Tint", state.map_tint)
    state.show_map_border     = ImGui.Checkbox("Show Border", state.show_map_border)
    state.map_border_color    = ImGui.ColorEdit4("Border Color", state.map_border_color)
    state.map_border_thickness = ImGui.SliderFloat("Border Thickness", state.map_border_thickness, 0.5, 6.0, tostring(state.map_border_thickness))

    ImGui.Separator()
    ImGui.Text("Position Dot")
    state.show_player_marker_dot = ImGui.Checkbox("Show Position Dot", state.show_player_marker_dot)
    state.player_marker_radius = ImGui.SliderInt("Dot Radius", state.player_marker_radius, 2, 20, tostring(state.player_marker_radius))
    state.player_marker_fill_color = ImGui.ColorEdit4("Dot Color", state.player_marker_fill_color)
    state.show_player_marker_border = ImGui.Checkbox("Show Dot Border", state.show_player_marker_border)
    state.player_marker_border_color = ImGui.ColorEdit4("Dot Border Color", state.player_marker_border_color)
    state.player_marker_border_thickness = ImGui.SliderFloat("Dot Border Thickness", state.player_marker_border_thickness, 0.5, 5.0, tostring(state.player_marker_border_thickness))

    ImGui.Separator()
    ImGui.Text("Facing Direction Arrow")
    state.show_facing_arrow = ImGui.Checkbox("Show Facing Arrow", state.show_facing_arrow)
    state.facing_arrow_scale = ImGui.SliderFloat("Arrow Scale", state.facing_arrow_scale, 0.25, 4.0, tostring(state.facing_arrow_scale))
    state.facing_arrow_fill_color = ImGui.ColorEdit4("Arrow Color", state.facing_arrow_fill_color)
    state.show_facing_arrow_border = ImGui.Checkbox("Show Arrow Border", state.show_facing_arrow_border)
    state.facing_arrow_border_color = ImGui.ColorEdit4("Arrow Border Color", state.facing_arrow_border_color)

    ImGui.Separator()
    ImGui.Text("City Labels")
    state.show_city_labels = ImGui.Checkbox("Show City Labels", state.show_city_labels)
    state.show_estimated_cities = ImGui.Checkbox("Show Estimated (Unverified) Cities", state.show_estimated_cities)
    state.city_label_min_zoom = ImGui.SliderFloat("Min Zoom To Show Labels", state.city_label_min_zoom, 1.0, 10.0, string.format("%.1fx", state.city_label_min_zoom))
    state.font_scale = ImGui.SliderFloat("Font Scale (whole window)", state.font_scale, 0.5, 3.0, tostring(state.font_scale))
    state.show_city_dot = ImGui.Checkbox("Show City Dot", state.show_city_dot)
    state.city_dot_radius = ImGui.SliderInt("City Dot Radius", state.city_dot_radius, 1, 10, tostring(state.city_dot_radius))
    state.city_label_good_color = ImGui.ColorEdit4("Good-Aligned Color", state.city_label_good_color)
    state.city_label_evil_color = ImGui.ColorEdit4("Evil-Aligned Color", state.city_label_evil_color)
    state.city_label_neutral_color = ImGui.ColorEdit4("Neutral-Aligned Color", state.city_label_neutral_color)
end

local function OnDisable()
    state.show_world_map = false
    SetTrackedEntry(nil)
    if Journal.HasUnsavedChanges() then Journal.Save() end
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

-- Wide enough for the longest control-panel text (the journal drop hint).
local CONTROL_PANEL_WIDTH = 320
local COLLAPSE_BUTTON_RADIUS = 11

-- The control panel that sits to the left of the map: view controls with the
-- player/mouse coordinate readouts, then the entity search. Drawn with a border
-- (child flag 1) so the collapse button visibly sits on the panel edge.
local function DrawControlPanel(player_fraction_x, player_fraction_z, player_coordinates, player_world, player_on_map)
    ImGui.BeginChild("world_map_controls", CONTROL_PANEL_WIDTH, 0, 1)
    ImGui.PushItemWidth(140)

    ImGui.Text("View")
    if ImGui.BeginCombo("World", GetWorldConfig(state.view_world).name) then
        for _, world_id in ipairs(WORLD_ORDER) do
            if ImGui.Selectable(WORLDS[world_id].name, world_id == state.view_world) then
                SetViewWorld(world_id)
            end
        end
        ImGui.EndCombo()
    end
    if not player_on_map then
        ImGui.TextDisabled("You are in " .. GetWorldConfig(player_world).name)
        ImGui.SameLine()
        if ImGui.Button("Show") then
            SetViewWorld(player_world)
        end
    end

    state.map_zoom = ImGui.SliderFloat("Zoom", state.map_zoom, 1.0, 20.0, string.format("%.1fx", state.map_zoom))
    state.follow_player = ImGui.Checkbox("Follow Player", state.follow_player)

    if not state.follow_player then
        if ImGui.Button("Center On Player") then
            state.pan_center_x = player_fraction_x
            state.pan_center_z = player_fraction_z
        end
        state.pan_step = ImGui.SliderFloat("Pan Step", state.pan_step, 0.01, 0.25, "%.2f")

        -- Pan buttons in a diamond. All four share one fixed width, and Up/Down
        -- sit over the middle column, so they center between Left and Right.
        local button_width = 48
        ImGui.Dummy(button_width, 0)
        ImGui.SameLine()
        if ImGui.Button("Up", button_width, 0) then state.pan_center_z = Clamp01(state.pan_center_z - state.pan_step) end
        if ImGui.Button("Left", button_width, 0) then state.pan_center_x = Clamp01(state.pan_center_x - state.pan_step) end
        ImGui.SameLine()
        ImGui.Dummy(button_width, 0)
        ImGui.SameLine()
        if ImGui.Button("Right", button_width, 0) then state.pan_center_x = Clamp01(state.pan_center_x + state.pan_step) end
        ImGui.Dummy(button_width, 0)
        ImGui.SameLine()
        if ImGui.Button("Down", button_width, 0) then state.pan_center_z = Clamp01(state.pan_center_z + state.pan_step) end
    end

    -- Mouse position on the map, converted back to world coordinates through
    -- last frame's view crop (the map itself draws after this panel).
    local mouse_world_x, mouse_world_z
    if state.last_map_origin_x ~= nil and state.last_map_display_width > 0 and state.last_map_display_height > 0 then
        local mouse_x, mouse_y = ImGui.GetMousePos()
        local fraction_x = (mouse_x - state.last_map_origin_x) / state.last_map_display_width
        local fraction_z = (mouse_y - state.last_map_origin_y) / state.last_map_display_height
        if fraction_x >= 0 and fraction_x <= 1 and fraction_z >= 0 and fraction_z <= 1 then
            mouse_world_x = state.world_min_x + (state.last_uv0_x + fraction_x * state.last_view_frac_w) * state.world_width
            mouse_world_z = state.world_min_z + (state.last_uv0_z + fraction_z * state.last_view_frac_h) * state.world_height
        end
    end

    ImGui.Text(string.format("Player coords: %.0f, %.0f", player_coordinates.x, player_coordinates.z))
    if mouse_world_x ~= nil then
        ImGui.Text(string.format("Mouse coords: %.0f, %.0f", mouse_world_x, mouse_world_z))
        if player_on_map then
            local dx = mouse_world_x - player_coordinates.x
            local dz = mouse_world_z - player_coordinates.z
            ImGui.Text(string.format("Distance from player: %.0f", math.sqrt(dx * dx + dz * dz)))
        else
            ImGui.Text("Distance from player: -")
        end
    else
        ImGui.Text("Mouse coords: -")
        ImGui.Text("Distance from player: -")
    end

    ImGui.Separator()
    if ImGui.BeginTabBar("world_map_panel_tabs") then
        if ImGui.BeginTabItem("Search") then
            EntitySearchSection()
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem("Journal") then
            JournalBrowseSection()
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end

    ImGui.PopItemWidth()
    ImGui.EndChild()
end

-- The circular collapse/expand toggle centered on the panel's right border
-- (or on the window's left content edge while collapsed). Submitted after the
-- map so it wins hover over the map image it overlaps when collapsed.
local function DrawPanelCollapseButton(border_x, center_y)
    local radius = COLLAPSE_BUTTON_RADIUS
    ImGui.SetCursorScreenPos(border_x - radius, center_y - radius)
    local clicked = ImGui.InvisibleButton("world_map_controls_collapse", radius * 2, radius * 2)
    local hovered = ImGui.IsItemHovered()

    local draw_list = ImGui.GetWindowDrawList()
    local center = ImVec2.new(border_x, center_y)
    local fill = hovered and ImGui.GetColorU32(0.36, 0.36, 0.40, 1.0)
        or ImGui.GetColorU32(0.20, 0.20, 0.23, 1.0)
    draw_list:AddCircleFilled(center, radius, fill)
    draw_list:AddCircle(center, radius, ImGui.GetColorU32(0.62, 0.62, 0.66, 1.0), 0, 1.5)

    local glyph = state.controls_collapsed and ">" or "<"
    local text_width, text_height = ImGui.CalcTextSize(glyph)
    ImGui.SetCursorScreenPos(border_x - text_width / 2, center_y - text_height / 2)
    ImGui.Text(glyph)

    if clicked then
        state.controls_collapsed = not state.controls_collapsed
    end
end

-- Draws the highlighted regions for the current search results. Hovering a
-- region lists the creatures inside it, clicking one narrows the result list to
-- just those creatures and rebuilds the regions around them.
local function DrawSearchRegions(draw_list, project, world_to_pixels)
    if not state.show_search_regions then return end
    if #state.search_regions == 0 then return end

    local radius_world = state.uncertainty_range * 0.5
    local fill = state.region_fill_color
    local border = state.region_border_color
    local fill_u32 = ImGui.GetColorU32(fill[1], fill[2], fill[3], fill[4])
    local border_u32 = ImGui.GetColorU32(border[1], border[2], border[3], border[4])

    local mouse_x, mouse_y = ImGui.GetMousePos()
    local hovered_region = nil
    local min_px = state.min_marker_pixel_radius

    for _, region in ipairs(state.search_regions) do
        local screen_x, screen_y, visible = project(region.center_x, region.center_z)
        if visible then
            -- Clamp to a minimum on-screen size so regions stay visible and
            -- hoverable when zoomed all the way out, where a real-scale region
            -- would shrink below a pixel.
            local radius_x = math.max((region.half_x + radius_world) * world_to_pixels, min_px)
            local radius_y = math.max((region.half_z + radius_world) * world_to_pixels, min_px)
            DrawEllipse(draw_list, screen_x, screen_y, radius_x, radius_y, border_u32, fill_u32, 2.0)

            -- Ellipse hit test in normalized space. The last hovered region wins,
            -- which matches draw order (later regions render on top).
            if radius_x > 0 and radius_y > 0 then
                local nx = (mouse_x - screen_x) / radius_x
                local ny = (mouse_y - screen_y) / radius_y
                if (nx * nx + ny * ny) <= 1 then
                    hovered_region = region
                end
            end
        end
    end

    if hovered_region ~= nil then
        ImGui.BeginTooltip()
        local max_names = state.region_tooltip_max_names
        for index, name in ipairs(hovered_region.names) do
            if index > max_names then
                ImGui.TextUnformatted(string.format("... and %d more", #hovered_region.names - max_names))
                break
            end
            ImGui.TextUnformatted(name)
        end
        ImGui.EndTooltip()

        if ImGui.IsMouseClicked(0, false) then
            state.search_results = hovered_region.entries
            BuildSearchRegions()
        end
    end
end

local function Render()
    if Util.IsInGame() == 0 then return end
    if state.disable_in_start_menu and Util.IsStartMenuOpen() == 1 then return end
    if state.show_world_map ~= true then
        state.map_was_open = false
        return
    end

    local mouse_x, mouse_y = ImGui.GetMousePos()
    local mouse_down = ImGui.IsMouseDown(0)

    if mouse_down and state.last_map_origin_x ~= nil
        and mouse_x >= state.last_map_origin_x and mouse_x <= state.last_map_origin_x + state.last_map_display_width
        and mouse_y >= state.last_map_origin_y and mouse_y <= state.last_map_origin_y + state.last_map_display_height then
        state.map_drag_active = true
    elseif not mouse_down then
        state.map_drag_active = false
    end

    local extra_window_flags = 0
    if state.map_drag_active then extra_window_flags = ImGuiWindowFlags.NoMove end

    if ImGui.Begin("World Map", true, extra_window_flags) then
        ImGui.SetWindowFontScale(state.font_scale)

        -- Opening the map jumps to the world the player is in, and while
        -- following, a world change (zoning, porting) drags the map along.
        local current_world = Util.GetWorldId()
        if not state.map_was_open then
            state.map_was_open = true
            SetViewWorld(current_world)
        elseif state.follow_player and current_world ~= state.last_player_world then
            SetViewWorld(current_world)
        end
        state.last_player_world = current_world

        -- Publish the viewed world's bounds so every coordinate conversion in
        -- this frame, panel included, works against the same rectangle.
        local cfg = GetWorldConfig(state.view_world)
        state.world_min_x = cfg.min_x
        state.world_min_z = cfg.min_z
        state.world_width = cfg.width
        state.world_height = cfg.height
        state.map_texture_width = cfg.tex_w
        state.map_texture_height = cfg.tex_h

        local player_world = current_world
        local player_on_map = (player_world == state.view_world)
        local map_texture = GetWorldTexture(state.view_world)

        local player_coordinates = Player.GetCoordinates()
        local player_fraction_x = Clamp01((player_coordinates.x - state.world_min_x) / state.world_width)
        local player_fraction_z = Clamp01((player_coordinates.z - state.world_min_z) / state.world_height)

        -- Remembered before the panel draws so the collapse button can center
        -- itself on the panel border afterwards.
        local content_origin_x, content_origin_y = ImGui.GetCursorScreenPos()
        local _, content_avail_height = ImGui.GetContentRegionAvail()

        if not state.controls_collapsed then
            DrawControlPanel(player_fraction_x, player_fraction_z, player_coordinates, player_world, player_on_map)
            ImGui.SameLine()
        end

        if map_texture == nil then
            ImGui.Text(string.format("Map image for %s failed to load.", cfg.name))
        else
            local avail_width, avail_height = ImGui.GetContentRegionAvail()
            if avail_width < 50 then avail_width = 50 end
            if avail_height < 50 then avail_height = 50 end

            local scale = math.min(avail_width / state.map_texture_width, avail_height / state.map_texture_height)
            local display_width = state.map_texture_width * scale
            local display_height = state.map_texture_height * scale

            local cursor_x, cursor_y = ImGui.GetCursorPos()
            local offset_x = (avail_width - display_width) / 2
            local offset_y = (avail_height - display_height) / 2
            ImGui.SetCursorPos(cursor_x + offset_x, cursor_y + offset_y)

            local origin_x, origin_y = ImGui.GetCursorScreenPos()

            -- Following only makes sense while the player is on the viewed map.
            if state.follow_player and player_on_map then
                state.pan_center_x = player_fraction_x
                state.pan_center_z = player_fraction_z
            end

            local view_fraction = 1 / state.map_zoom
            local half_view = view_fraction / 2

            local uv0_x = state.pan_center_x - half_view
            local uv1_x = state.pan_center_x + half_view
            if uv0_x < 0 then uv1_x = uv1_x - uv0_x; uv0_x = 0 end
            if uv1_x > 1 then uv0_x = uv0_x - (uv1_x - 1); uv1_x = 1 end
            uv0_x = Clamp01(uv0_x)
            uv1_x = Clamp01(uv1_x)

            local uv0_z = state.pan_center_z - half_view
            local uv1_z = state.pan_center_z + half_view
            if uv0_z < 0 then uv1_z = uv1_z - uv0_z; uv0_z = 0 end
            if uv1_z > 1 then uv0_z = uv0_z - (uv1_z - 1); uv1_z = 1 end
            uv0_z = Clamp01(uv0_z)
            uv1_z = Clamp01(uv1_z)

            local map_tint = ImVec4.new(state.map_tint[1], state.map_tint[2], state.map_tint[3], state.map_tint[4])
            ImGui.Image(map_texture, ImVec2.new(display_width, display_height),
                ImVec2.new(uv0_x, uv0_z), ImVec2.new(uv1_x, uv1_z), map_tint, state.default_texture_border_color)

            state.last_map_origin_x = origin_x
            state.last_map_origin_y = origin_y
            state.last_map_display_width = display_width
            state.last_map_display_height = display_height
            -- The view crop too, so the panel can convert mouse to world coords.
            state.last_uv0_x = uv0_x
            state.last_uv0_z = uv0_z
            state.last_view_frac_w = uv1_x - uv0_x
            state.last_view_frac_h = uv1_z - uv0_z

            if state.map_drag_active then
                local drag_dx, drag_dy = ImGui.GetMouseDragDelta(0, 0.0)
                if drag_dx ~= 0 or drag_dy ~= 0 then
                    state.follow_player = false
                    state.pan_center_x = Clamp01(state.pan_center_x - (drag_dx / display_width) * view_fraction)
                    state.pan_center_z = Clamp01(state.pan_center_z - (drag_dy / display_height) * view_fraction)
                    ImGui.ResetMouseDragDelta(0)
                end
            end

            local draw_list = ImGui.GetWindowDrawList()

            if state.show_map_border then
                local border_color_u32 = ImGui.GetColorU32(state.map_border_color[1], state.map_border_color[2], state.map_border_color[3], state.map_border_color[4])
                draw_list:AddRect(ImVec2.new(origin_x, origin_y), ImVec2.new(origin_x + display_width, origin_y + display_height), border_color_u32, 0, 0, state.map_border_thickness)
            end

            local view_width = uv1_x - uv0_x
            local view_height = uv1_z - uv0_z

            -- Maps a world position to a screen point, plus whether it lands inside
            -- the visible crop. Shared by the player marker, cities, and rings.
            local function project(world_x, world_z)
                if view_width <= 0 or view_height <= 0 then return 0, 0, false end
                local fraction_x = Clamp01((world_x - state.world_min_x) / state.world_width)
                local fraction_z = Clamp01((world_z - state.world_min_z) / state.world_height)
                local marker_fraction_x = (fraction_x - uv0_x) / view_width
                local marker_fraction_z = (fraction_z - uv0_z) / view_height
                local visible = marker_fraction_x >= 0 and marker_fraction_x <= 1 and marker_fraction_z >= 0 and marker_fraction_z <= 1
                return origin_x + marker_fraction_x * display_width, origin_y + marker_fraction_z * display_height, visible
            end

            -- World units to on-screen pixels. The map texture aspect matches the
            -- world aspect, so one factor works for both axes.
            local world_to_pixels = 0
            if view_width > 0 then
                world_to_pixels = (display_width / state.world_width) / view_width
            end

            if player_on_map and view_width > 0 and view_height > 0 then
                local marker_fraction_x = (player_fraction_x - uv0_x) / view_width
                local marker_fraction_z = (player_fraction_z - uv0_z) / view_height

                if marker_fraction_x >= 0 and marker_fraction_x <= 1 and marker_fraction_z >= 0 and marker_fraction_z <= 1 then
                    local marker_center = ImVec2.new(origin_x + marker_fraction_x * display_width, origin_y + marker_fraction_z * display_height)

                    if state.show_player_marker_dot then
                        local fill_color_u32 = ImGui.GetColorU32(state.player_marker_fill_color[1], state.player_marker_fill_color[2], state.player_marker_fill_color[3], state.player_marker_fill_color[4])
                        draw_list:AddCircleFilled(marker_center, state.player_marker_radius, fill_color_u32)

                        if state.show_player_marker_border then
                            local dot_border_color_u32 = ImGui.GetColorU32(state.player_marker_border_color[1], state.player_marker_border_color[2], state.player_marker_border_color[3], state.player_marker_border_color[4])
                            draw_list:AddCircle(marker_center, state.player_marker_radius, dot_border_color_u32, 0, state.player_marker_border_thickness)
                        end
                    end

                    if state.show_facing_arrow and state.player_indicator_fill_texture ~= nil then
                        local arrow_dimensions = ImVec2.new(state.facing_arrow_width * state.facing_arrow_scale, state.facing_arrow_height * state.facing_arrow_scale)
                        local angle_of_texture_orientation = (math.pi / 2)

                        if state.show_facing_arrow_border and state.player_indicator_border_texture ~= nil then
                            DrawRotatedImage(state.player_indicator_border_texture, marker_center, arrow_dimensions, angle_of_texture_orientation, Util.GetCompassRadians(), state.facing_arrow_border_color)
                        end

                        DrawRotatedImage(state.player_indicator_fill_texture, marker_center, arrow_dimensions, angle_of_texture_orientation, Util.GetCompassRadians(), state.facing_arrow_fill_color)
                    end
                end
            end

            -- Highlighted regions, either the whole result set or just the
            -- selected creature's spawns (see BuildSearchRegions).
            DrawSearchRegions(draw_list, project, world_to_pixels)

            -- The city labels are Tunaria positions, they mean nothing elsewhere.
            if state.view_world == 0 and state.show_city_labels and state.map_zoom >= state.city_label_min_zoom and view_width > 0 and view_height > 0 then
                for _, city in ipairs(CITY_LABELS) do
                    local skip_this_city = city.estimated and not state.show_estimated_cities

                    if not skip_this_city then
                        local city_marker_fraction_x = (city.fraction_x - uv0_x) / view_width
                        local city_marker_fraction_z = (city.fraction_z - uv0_z) / view_height

                        if city_marker_fraction_x >= 0 and city_marker_fraction_x <= 1 and city_marker_fraction_z >= 0 and city_marker_fraction_z <= 1 then
                            local city_center = ImVec2.new(origin_x + city_marker_fraction_x * display_width, origin_y + city_marker_fraction_z * display_height)
                            local city_color = GetCityLabelColor(state, city.alignment)

                            local display_alpha = city.estimated and (city_color[4] * 0.55) or city_color[4]
                            local city_color_u32 = ImGui.GetColorU32(city_color[1], city_color[2], city_color[3], display_alpha)

                            if state.show_city_dot then
                                if city.estimated then
                                    draw_list:AddCircle(city_center, state.city_dot_radius, city_color_u32, 0, 1.5)
                                else
                                    draw_list:AddCircleFilled(city_center, state.city_dot_radius, city_color_u32)
                                end
                            end

                            local label_text = city.estimated and (city.name .. " (est.)") or city.name

                            local label_text_width, label_text_height = ImGui.CalcTextSize(label_text)
                            local label_x = city_center.x - label_text_width / 2
                            local label_y = city_center.y + state.city_dot_radius + 2

                            local chip_padding = 2
                            local chip_color_u32 = ImGui.GetColorU32(0, 0, 0, city.estimated and 0.4 or 0.6)
                            draw_list:AddRectFilled(
                                ImVec2.new(label_x - chip_padding, label_y - chip_padding),
                                ImVec2.new(label_x + label_text_width + chip_padding, label_y + label_text_height + chip_padding),
                                chip_color_u32, 2)

                            draw_list:AddText(ImVec2.new(label_x, label_y), city_color_u32, label_text)
                        end
                    end
                end
            end

        end

        -- On the panel's right border when open, on the content edge when
        -- collapsed, always vertically centered on the panel column.
        local border_x = content_origin_x
        if not state.controls_collapsed then
            border_x = border_x + CONTROL_PANEL_WIDTH
        end
        DrawPanelCollapseButton(border_x, content_origin_y + content_avail_height / 2)
    end
    ImGui.End()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function Cleanup()
    SetTrackedEntry(nil)
    if Journal.HasUnsavedChanges() then Journal.Save() end
    state.initialized = false
end

local function RegisterCallbacks()
    UiForge.RegisterCallback(UiForge.CallbackType.Settings, Settings)
    UiForge.RegisterCallback(UiForge.CallbackType.Save, Save)
    UiForge.RegisterCallback(UiForge.CallbackType.Load, Load)
    UiForge.RegisterCallback(UiForge.CallbackType.DisableScript, OnDisable)
    UiForge.RegisterCallback(UiForge.CallbackType.OnEject, Cleanup)
    state.callbacks_registered = true
end

if state.initialized == false then Initialize() end
if state.callbacks_registered == false then RegisterCallbacks() end

-- The minimap raises this flag when its Stop Tracking button is pressed,
-- since only this script owns the tracked target.
if shared_globals.FF_Tracking_Stop then
    shared_globals.FF_Tracking_Stop = nil
    SetTrackedEntry(nil)
end

-- Keep the shared table fresh each frame so a minimap reload re-discovers the
-- current target, and so revision changes propagate.
if state.tracked_entry ~= nil then PublishTracking() end

-- The journal records whether or not the map window is open.
RecordNearbyEntities()

Render()
