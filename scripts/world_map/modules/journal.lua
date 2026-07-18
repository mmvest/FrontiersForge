--[[
journal.lua

The player's personal creature journal. As the player encounters NPCs, each
one is recorded by name, then by unique entity id, with the world, level, and
position at the moment of discovery. The journal grows into a personal entity
database that the world map searches alongside (or instead of) the shipped one.

File format (scripts\resources\journal.json):

    { "Grass Snake": { "1234567": { "world": 0, "level": 3, "pos": [x, y, z] } } }

Recording is memory only. The file is flushed after discoveries have been
quiet for a while (Flush), and on demand (Save), so the hot path never
touches disk. An id already recorded is never rewritten, and a new id is
skipped when the same creature at the same level was already recorded close
by, so transient ids cannot bloat the file with duplicate spawns.

Merging a friend's journal adds only names and ids the player does not
already have. The player's own data always wins on a conflicting id.
]]

local Json = require("json")

local Journal = {}

-- name -> { ids = { [id_key] = { world, level, x, y, z } }, count }
local records = {}
local loaded = false
local dirty = false
local last_change_time = nil
local status = ""
local journal_path = nil
local name_count = 0
local id_count = 0

-- Search entries in the entity_db shape, rebuilt lazily on change.
local entries = {}
local sorted_entries = {}
local entries_stale = true

local SAVE_QUIET_SECONDS = 30
local DEDUPE_RANGE_SQ = 30 * 30

local function AddToRecords(name, id_key, info)
    local record = records[name]
    if record == nil then
        record = { ids = {}, count = 0 }
        records[name] = record
        name_count = name_count + 1
    end
    if record.ids[id_key] ~= nil then return false end
    record.ids[id_key] = info
    record.count = record.count + 1
    id_count = id_count + 1
    entries_stale = true
    return true
end

--- Load the journal file. Safe to call repeatedly, only reads once. A missing
--- file is a fresh journal, not an error.
function Journal.Load(file_path)
    if loaded then return true end
    journal_path = file_path

    local file = io.open(file_path, "r")
    if file == nil then
        loaded = true
        status = "new journal"
        return true
    end
    local text = file:read("*a")
    file:close()

    local data, decode_error = Json.Decode(text)
    if type(data) ~= "table" then
        -- Never overwrite a file we could not read, the player may want to
        -- recover it by hand.
        status = "failed to parse journal: " .. tostring(decode_error)
        return false
    end

    for name, ids in pairs(data) do
        if type(name) == "string" and type(ids) == "table" then
            for id_key, info in pairs(ids) do
                if type(info) == "table" and type(info.pos) == "table" then
                    AddToRecords(name, tostring(id_key), {
                        world = tonumber(info.world) or 0,
                        level = tonumber(info.level) or 0,
                        x = tonumber(info.pos[1]) or 0,
                        y = tonumber(info.pos[2]) or 0,
                        z = tonumber(info.pos[3]) or 0,
                    })
                end
            end
        end
    end

    loaded = true
    dirty = false
    status = string.format("%d creatures, %d spawns", name_count, id_count)
    return true
end

function Journal.IsLoaded()
    return loaded
end

function Journal.Status()
    return status
end

function Journal.Counts()
    return name_count, id_count
end

--- Record a discovered NPC. Returns true when something new was written.
--- A known id is skipped, and so is a new id when the same name at the same
--- level was already recorded within the dedupe range.
function Journal.Record(name, id, world, level, x, y, z, now)
    if not loaded or name == nil or name == "" or id == nil or id == 0 then
        return false
    end

    local id_key = string.format("%.0f", id)
    local record = records[name]
    if record ~= nil then
        if record.ids[id_key] ~= nil then return false end
        for _, info in pairs(record.ids) do
            if info.level == level then
                local dx, dz = info.x - x, info.z - z
                if dx * dx + dz * dz <= DEDUPE_RANGE_SQ then return false end
            end
        end
    end

    AddToRecords(name, id_key, { world = world or 0, level = level or 0, x = x, y = y, z = z })
    dirty = true
    last_change_time = now
    status = string.format("%d creatures, %d spawns", name_count, id_count)
    return true
end

--- Write the journal to disk now. Returns true on success.
function Journal.Save()
    if not loaded or journal_path == nil then return false end

    local data = {}
    for name, record in pairs(records) do
        local ids = {}
        for id_key, info in pairs(record.ids) do
            ids[id_key] = { world = info.world, level = info.level, pos = { info.x, info.y, info.z } }
        end
        data[name] = ids
    end

    local text, encode_error = Json.Encode(data)
    if text == nil then
        status = "failed to encode journal: " .. tostring(encode_error)
        return false
    end

    local file = io.open(journal_path, "w")
    if file == nil then
        status = "cannot write " .. tostring(journal_path)
        return false
    end
    file:write(text)
    file:close()

    dirty = false
    status = string.format("%d creatures, %d spawns", name_count, id_count)
    return true
end

--- Flush to disk once discoveries have been quiet for a while. Call every
--- frame, it is a no-op unless there are unsaved changes past the quiet time.
function Journal.Flush(now)
    if dirty and last_change_time ~= nil and (now - last_change_time) >= SAVE_QUIET_SECONDS then
        Journal.Save()
    end
end

function Journal.HasUnsavedChanges()
    return dirty
end

--- Merge another journal file into this one. Only names and ids not already
--- present are added, existing data is never touched. Returns the number of
--- spawns added, or nil plus an error message.
function Journal.Merge(file_path, now)
    if not loaded then return nil, "journal not loaded" end

    local file = io.open(file_path, "r")
    if file == nil then return nil, "cannot open " .. tostring(file_path) end
    local text = file:read("*a")
    file:close()

    local data, decode_error = Json.Decode(text)
    if type(data) ~= "table" then
        return nil, "failed to parse: " .. tostring(decode_error)
    end

    local added = 0
    for name, ids in pairs(data) do
        if type(name) == "string" and type(ids) == "table" then
            for id_key, info in pairs(ids) do
                if type(info) == "table" and type(info.pos) == "table" then
                    local ok = AddToRecords(name, tostring(id_key), {
                        world = tonumber(info.world) or 0,
                        level = tonumber(info.level) or 0,
                        x = tonumber(info.pos[1]) or 0,
                        y = tonumber(info.pos[2]) or 0,
                        z = tonumber(info.pos[3]) or 0,
                    })
                    if ok then added = added + 1 end
                end
            end
        end
    end

    if added > 0 then
        dirty = true
        last_change_time = now
        status = string.format("%d creatures, %d spawns", name_count, id_count)
    end
    return added
end

local function RebuildEntries()
    entries = {}
    for name, record in pairs(records) do
        local level_min, level_max
        local spawns = {}
        for _, info in pairs(record.ids) do
            if info.level > 0 then
                if level_min == nil or info.level < level_min then level_min = info.level end
                if level_max == nil or info.level > level_max then level_max = info.level end
            end
            spawns[#spawns + 1] = { world = info.world, x = info.x, z = info.z }
        end
        entries[#entries + 1] = {
            name = name,
            name_lower = name:lower(),
            level_min = level_min,
            level_max = level_max,
            spawns = spawns,
        }
    end

    sorted_entries = {}
    for index, entry in ipairs(entries) do sorted_entries[index] = entry end
    table.sort(sorted_entries, function(a, b) return a.name_lower < b.name_lower end)

    entries_stale = false
end

--- Search entries in the entity_db shape, for aggregation with the database.
function Journal.GetEntries()
    if entries_stale then RebuildEntries() end
    return entries
end

--- The same entries in alphabetical order, for the Journal browse tab.
function Journal.GetSortedEntries()
    if entries_stale then RebuildEntries() end
    return sorted_entries
end

return Journal
