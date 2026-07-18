--[[
entity_db.lua

Loads the consolidated entity database (a JSON file shipped in the shared
resources folder) and answers fuzzy name searches against it. Each database
entry is a creature name mapping to parallel world, level, and pos arrays, one
element per recorded spawn. This module flattens each into a level range and a
list of {world, x, z} spawn points, then scores names against a search query.

The recorded positions are old and approximate, so callers treat each spawn as
the center of an uncertainty area rather than an exact location.

Scoring and search live in entity_search.lua, shared with the journal so both
sources rank identically.
]]

local Json = require("json")
local EntitySearch = require("entity_search")

local EntityDb = {}

-- Filled by Load(). Array of { name, name_lower, level_min, level_max, spawns }.
local entries = {}
local loaded = false
local load_status = ""

--- Load and index the database file. Safe to call repeatedly, only reads once.
function EntityDb.Load(file_path)
    if loaded then return true end

    local file = io.open(file_path, "r")
    if file == nil then
        load_status = "database not found: " .. tostring(file_path)
        return false
    end
    local text = file:read("*a")
    file:close()

    local data, decode_error = Json.Decode(text)
    if data == nil then
        load_status = "failed to parse database: " .. tostring(decode_error)
        return false
    end

    for name, record in pairs(data) do
        local levels = record.level or {}
        local level_min, level_max
        for _, level in ipairs(levels) do
            if level_min == nil or level < level_min then level_min = level end
            if level_max == nil or level > level_max then level_max = level end
        end

        local spawns = {}
        local positions = record.pos or {}
        local worlds = record.world or {}
        for index, position in ipairs(positions) do
            if type(position) == "table" and position[1] ~= nil and position[3] ~= nil then
                spawns[#spawns + 1] = {
                    world = worlds[index],
                    x = position[1],
                    z = position[3],
                }
            end
        end

        entries[#entries + 1] = {
            name = name,
            name_lower = name:lower(),
            level_min = level_min,
            level_max = level_max,
            spawns = spawns,
        }
    end

    loaded = true
    load_status = string.format("loaded %d entities", #entries)
    return true
end

function EntityDb.IsLoaded()
    return loaded
end

function EntityDb.Status()
    return load_status
end

--- The raw entry list, for callers that aggregate sources themselves.
function EntityDb.GetEntries()
    return entries
end

--- Search the database. Returns an array of matching entries sorted best-first,
--- capped at max_results (nil or 0 returns everything). An empty query returns
--- nothing. When exact is true, only a case-insensitive whole-name match counts.
function EntityDb.Search(query, max_results, exact)
    return EntitySearch.Search(entries, query, max_results, exact)
end

--- Search by level range, see EntitySearch.SearchByLevel.
function EntityDb.SearchByLevel(min_level, max_level, name_query, max_results, exact)
    return EntitySearch.SearchByLevel(entries, min_level, max_level, name_query, max_results, exact)
end

--- Look up a single entry by exact (case-insensitive) name, or nil.
function EntityDb.Find(name)
    if name == nil then return nil end
    local target = name:lower()
    for _, entry in ipairs(entries) do
        if entry.name_lower == target then return entry end
    end
    return nil
end

return EntityDb
