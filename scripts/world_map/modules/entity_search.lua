--[[
entity_search.lua

Name and level searches over entity entries, shared by the shipped database
and the player's journal so both sources score and sort identically. An entry
is { name, name_lower, level_min, level_max, spawns }, where spawns is a list
of { world, x, z } points. Aggregate merges same-named entries from multiple
sources into one combined entry per creature.
]]

local EntitySearch = {}

-- Subsequence match. Returns a score (higher is better) when every character of
-- query appears in name in order, or nil when it does not. Contiguous runs and
-- an early first match score higher, so "stone" ranks "Stone Golem" above a name
-- that merely happens to contain those letters scattered around.
function EntitySearch.FuzzyScore(name_lower, query_lower)
    local name_length = #name_lower
    local query_length = #query_lower
    if query_length == 0 then return 0 end

    local name_index = 1
    local query_index = 1
    local score = 0
    local run = 0
    local first_match

    while name_index <= name_length and query_index <= query_length do
        if name_lower:sub(name_index, name_index) == query_lower:sub(query_index, query_index) then
            if first_match == nil then first_match = name_index end
            run = run + 1
            score = score + 1 + run          -- reward contiguous runs
            query_index = query_index + 1
        else
            run = 0
        end
        name_index = name_index + 1
    end

    if query_index <= query_length then return nil end   -- ran out before matching all of query

    -- Prefer earlier matches and shorter names (a tighter fit to the query).
    score = score - (first_match - 1) * 0.5
    score = score - name_length * 0.05
    return score
end

local function SortAndCap(results, max_results)
    table.sort(results, function(a, b)
        if a.score == b.score then return a.entry.name_lower < b.entry.name_lower end
        return a.score > b.score
    end)

    local capped = {}
    local limit = #results
    if max_results ~= nil and max_results > 0 and max_results < limit then
        limit = max_results
    end
    for index = 1, limit do
        capped[index] = results[index].entry
    end
    return capped
end

--- Search entries by name. Returns matches sorted best first. A max_results of
--- nil or 0 returns everything. When exact is true, fuzzy matching is off and
--- only a case-insensitive whole-name match counts.
function EntitySearch.Search(entries, query, max_results, exact)
    local results = {}
    if query == nil then return results end

    local query_lower = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query_lower == "" then return results end

    for _, entry in ipairs(entries) do
        local score
        if exact then
            if entry.name_lower == query_lower then score = 0 end
        else
            score = EntitySearch.FuzzyScore(entry.name_lower, query_lower)
        end
        if score ~= nil then
            results[#results + 1] = { entry = entry, score = score }
        end
    end

    return SortAndCap(results, max_results)
end

--- Search entries by level range. An entry matches when its level_min or
--- level_max falls inside [min_level, max_level] inclusive. A non-empty name
--- query narrows the matches further with the same scoring as Search. Results
--- sort by name score when a query is given, otherwise by level then name.
function EntitySearch.SearchByLevel(entries, min_level, max_level, name_query, max_results, exact)
    local results = {}
    if min_level == nil or max_level == nil or min_level > max_level then return results end

    local query_lower
    if name_query ~= nil then
        query_lower = name_query:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if query_lower == "" then query_lower = nil end
    end

    for _, entry in ipairs(entries) do
        local lo, hi = entry.level_min, entry.level_max
        local in_range = lo ~= nil and
            ((lo >= min_level and lo <= max_level) or (hi >= min_level and hi <= max_level))
        if in_range then
            if query_lower ~= nil then
                local score
                if exact then
                    if entry.name_lower == query_lower then score = 0 end
                else
                    score = EntitySearch.FuzzyScore(entry.name_lower, query_lower)
                end
                if score ~= nil then
                    results[#results + 1] = { entry = entry, score = score }
                end
            else
                results[#results + 1] = { entry = entry, score = -(lo or 0) }
            end
        end
    end

    return SortAndCap(results, max_results)
end

--- Merge multiple entry lists into one, combining same-named creatures into a
--- single entry whose level range covers both and whose spawns are the union.
--- Later lists never override earlier data, they only extend it.
function EntitySearch.Aggregate(entry_lists)
    local combined = {}
    local by_key = {}

    for _, entries in ipairs(entry_lists) do
        for _, entry in ipairs(entries) do
            local existing = by_key[entry.name_lower]
            if existing == nil then
                local copy = {
                    name = entry.name,
                    name_lower = entry.name_lower,
                    level_min = entry.level_min,
                    level_max = entry.level_max,
                    spawns = {},
                }
                for _, spawn in ipairs(entry.spawns) do
                    copy.spawns[#copy.spawns + 1] = spawn
                end
                by_key[entry.name_lower] = copy
                combined[#combined + 1] = copy
            else
                if entry.level_min ~= nil and (existing.level_min == nil or entry.level_min < existing.level_min) then
                    existing.level_min = entry.level_min
                end
                if entry.level_max ~= nil and (existing.level_max == nil or entry.level_max > existing.level_max) then
                    existing.level_max = entry.level_max
                end
                for _, spawn in ipairs(entry.spawns) do
                    existing.spawns[#existing.spawns + 1] = spawn
                end
            end
        end
    end

    return combined
end

return EntitySearch
