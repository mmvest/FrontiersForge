--[[
    damage_meter.lua

    The damage meter table, drawn as ranked bars.

    One row per source, sorted, with each bar filled relative to whoever is on
    top, so the top bar is always full and anything below reads as a fraction of
    it at a glance. The class badge sits at the far left, the rank and name ride
    on the bar, and the total, the rate, and the share of the table are right
    aligned.

    Four tables share the layout, damage done and taken, healing done and
    received. They differ only in which field they read, so they are one code path
    with a key rather than four.

    This module reads no game memory and never touches the network. It draws
    whatever list of rows it is handed, with the encounter totals already folded
    in. In this mod that list only ever holds the local player, but the ranked
    layout is left intact so more rows would render without change.
]]

local Paint = require("paint")
local Meter = require("meter")
local ClassIcon = require("class_icon")

local DamageMeter = {}

-- The four tables, in tab order. Each is just a field on a member row.
DamageMeter.TABS = {
    { key = "damage_done",   label = "Damage",         unit = "DPS" },
    { key = "damage_taken",  label = "Damage Taken",   unit = "DTPS" },
    { key = "healing_done",  label = "Healing",        unit = "HPS" },
    { key = "healing_taken", label = "Healing Taken",  unit = "HPS" },
}

-- What the window is looking at. The fight in front of you, everything since you
-- logged in, or the fights that are already over. All three draw the same table of
-- the same four fields, so they are one window with a view rather than three
-- windows with three copies of the same bars.
DamageMeter.VIEW = { CURRENT = 1, SESSION = 2, HISTORY = 3 }

DamageMeter.VIEWS = {
    { key = "current", label = "Current Fight" },
    { key = "session", label = "Session Totals" },
    { key = "history", label = "Combat Log" },
}

--- @return table config
function DamageMeter.DefaultConfig()
    return {
        view = DamageMeter.VIEW.CURRENT,
        tab = 1,

        -- Sorting. The key is the total or the per second rate, and either can
        -- run in either direction.
        sort_by_rate = false,
        sort_descending = true,

        row_height = 20,
        row_spacing = 1,
        bar_rounding = 2,

        show_class_icons = true,
        show_rank = true,
        show_rate = true,
        show_percent = true,
        -- Names the two numbers on a row, since a bare number on the right does not
        -- say whether it is a rate or a total.
        show_column_headers = true,
        -- A row that did nothing is just noise, but hiding it also hides a row
        -- that only ever healed, so it is a choice.
        hide_empty_rows = true,

        -- A bar per class reads the way the game does. A bar per row tells two of
        -- the same class apart, which a class colored table cannot.
        unique_colors = false,

        color_row_bg      = { 0.10, 0.10, 0.12, 0.85 },
        color_bar_default = { 0.45, 0.45, 0.52, 1.00 },
        color_text        = { 1.00, 1.00, 1.00, 1.00 },
        color_text_shadow = { 0.00, 0.00, 0.00, 0.85 },
        color_header      = { 0.70, 0.72, 0.78, 1.00 },
    }
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

local function Short(amount)
    if amount >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    end
    if amount >= 1000 then
        return string.format("%.1fK", amount / 1000)
    end
    return string.format("%d", math.floor(amount + 0.5))
end

local function Clock(ms)
    local seconds = math.floor((ms or 0) / 1000)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

DamageMeter.Short = Short
DamageMeter.Clock = Clock

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

-- Stable across sessions, since it is derived from the name rather than from a
-- row order that could change from run to run.
local function HashName(name)
    local hash = 5381
    for i = 1, #name do
        -- Kept well under the range a double holds exactly, so the hash is the
        -- same number on every machine.
        hash = (hash * 33 + name:byte(i)) % 16777216
    end
    return hash
end

local function HueToRgb(hue, saturation, value)
    local sector = (hue % 1) * 6
    local index = math.floor(sector)
    local frac = sector - index
    local p = value * (1 - saturation)
    local q = value * (1 - saturation * frac)
    local t = value * (1 - saturation * (1 - frac))

    if index == 0 then return value, t, p end
    if index == 1 then return q, value, p end
    if index == 2 then return p, value, t end
    if index == 3 then return p, q, value end
    if index == 4 then return t, p, value end
    return value, p, q
end

local function BarColor(member, config)
    if config.unique_colors then
        local hue = (HashName(member.name or "?") % 360) / 360
        local r, g, b = HueToRgb(hue, 0.62, 0.88)
        return { r, g, b, 1 }
    end

    if ClassIcon.GetColor(member.class_id) ~= nil then
        local r, g, b = ClassIcon.GetColorFloats(member.class_id)
        return { r, g, b, 1 }
    end
    return config.color_bar_default
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

-- Builds the sorted table for one field. The share is against the table total,
-- and the bar is filled against the top row, which is what makes the top bar
-- always full.
local function BuildRows(roster, key, duration_ms, config)
    local rows = {}
    local sum = 0

    for _, member in ipairs(roster) do
        local amount = member[key] or 0
        if amount > 0 or not config.hide_empty_rows then
            sum = sum + amount
            rows[#rows + 1] = {
                member = member,
                name = member.name or "?",
                class_id = member.class_id,
                amount = amount,
                rate = Meter.PerSecond(amount, duration_ms),
            }
        end
    end

    local descending = config.sort_descending
    local by_rate = config.sort_by_rate
    table.sort(rows, function(a, b)
        local left = by_rate and a.rate or a.amount
        local right = by_rate and b.rate or b.amount
        if left == right then
            return a.name < b.name -- so equal rows do not shuffle every frame
        end
        if descending then
            return left > right
        end
        return left < right
    end)

    local peak = 0
    for _, row in ipairs(rows) do
        peak = math.max(peak, row.amount)
    end

    for index, row in ipairs(rows) do
        row.rank = index
        row.fraction = peak > 0 and (row.amount / peak) or 0
        row.share = sum > 0 and (row.amount / sum * 100) or 0
    end

    return rows, sum
end

local function ShadowedText(draw_list, x, y, text, config)
    Paint.Text(draw_list, x + 1, y + 1, text, config.color_text_shadow)
    Paint.Text(draw_list, x, y, text, config.color_text)
end

local function DrawRow(draw_list, x, y, w, row, tab, config, opts)
    local h = config.row_height
    local rounding = config.bar_rounding

    Paint.Rect(draw_list, x, y, w, h, config.color_row_bg, rounding)

    if row.fraction > 0 then
        Paint.Bar(draw_list, x, y, w, h, row.fraction, BarColor(row.member, config),
            rounding)
    end

    local text_x = x + 4
    if config.show_class_icons and row.class_id ~= nil then
        local size = h - 4
        if ClassIcon.Draw(draw_list, x + 2, y + 2, size, row.class_id, opts) then
            text_x = x + 2 + size + 4
        end
    end

    -- Icon, rank, name, then the total, then a wide gap, then the rate hard right.
    -- The gap is the point: the totals and the rates each line up in their own
    -- column, so the table can be read down rather than across.
    local label = row.name
    if config.show_rank then
        label = string.format("%d. %s", row.rank, row.name)
    end

    local total = Short(row.amount)
    if config.show_percent then
        total = string.format("%s (%.0f%%)", total, row.share)
    end
    label = label .. "  " .. total

    local _, text_h = ImGui.CalcTextSize(label)
    local text_y = y + (h - text_h) / 2

    -- The rate is placed first so the name can be clipped against it rather than
    -- run underneath it.
    local right_x = x + w
    if config.show_rate then
        local rate = Short(row.rate)
        local rate_w = ImGui.CalcTextSize(rate)
        right_x = x + w - 4 - rate_w
        ShadowedText(draw_list, right_x, text_y, rate, config)
    end

    Paint.PushClip(draw_list, text_x, y, (right_x - 8) - text_x, h)
    ShadowedText(draw_list, text_x, text_y, label, config)
    Paint.PopClip(draw_list)

    -- The share is against the total of the table being shown, so it says what it
    -- is a share of rather than leaving that to be guessed at.
    if Paint.HitRegion("row", x, y, w, h) then
        Paint.Tooltip(string.format("%s\n%d total\n%.1f %s\n%.1f%% of the table's %s",
            row.name, row.amount, row.rate, tab.unit, row.share, tab.label:lower()))
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- The view name on the left, a gear on the right. Everything that used to be a
-- row of tabs and checkboxes above the table now lives behind the gear, so the
-- meter itself is just the bars.
--- @return string|nil action What the gear popup asked for, "export" or "clear".
local function DrawHeader(config, opts)
    local draw_list = ImGui.GetWindowDrawList()

    local origin_x, origin_y = ImGui.GetCursorScreenPos()
    local avail_w = ImGui.GetContentRegionAvail()
    local size = ImGui.GetTextLineHeight()

    -- The plain meter is named for the table it is showing. The other two views
    -- are named for themselves, since which table they show is a detail of them.
    local title
    if config.view == DamageMeter.VIEW.CURRENT then
        title = (DamageMeter.TABS[config.tab] or DamageMeter.TABS[1]).label
    else
        title = (DamageMeter.VIEWS[config.view] or DamageMeter.VIEWS[1]).label
    end
    Paint.Text(draw_list, origin_x, origin_y, title, config.color_header)

    local gear_x = origin_x + avail_w - size
    if opts.gear ~= nil then
        draw_list:AddImage(opts.gear, ImVec2.new(gear_x, origin_y),
            ImVec2.new(gear_x + size, origin_y + size),
            ImVec2.new(0, 0), ImVec2.new(1, 1), Paint.Color({ 0.85, 0.85, 0.9, 1 }))
    else
        Paint.Rect(draw_list, gear_x, origin_y, size, size, { 0.5, 0.5, 0.55, 1 }, 2)
    end

    if Paint.HitButton("meter_gear", gear_x, origin_y, size, size) then
        ImGui.OpenPopup("meter_options")
    end

    -- The header is draw list output, so the caret has to be walked past it by
    -- hand before the table below can claim its own space.
    ImGui.SetCursorScreenPos(origin_x, origin_y)
    ImGui.Dummy(avail_w, size)

    local action = nil
    if ImGui.BeginPopup("meter_options") then
        ImGui.Text("View")
        for index, entry in ipairs(DamageMeter.VIEWS) do
            if ImGui.RadioButton(entry.label, config.view == index) then
                config.view = index
            end
        end

        ImGui.Separator()
        ImGui.Text("Show")
        for index, entry in ipairs(DamageMeter.TABS) do
            if ImGui.RadioButton(entry.label, config.tab == index) then
                config.tab = index
            end
        end

        ImGui.Separator()
        ImGui.Text("Sort")
        DamageMeter.DrawSortControls(config)
        config.show_percent = ImGui.Checkbox("Percent after the total", config.show_percent)
        config.show_rate = ImGui.Checkbox("Per second rate", config.show_rate)
        config.show_column_headers = ImGui.Checkbox("Header over the rate column",
            config.show_column_headers)

        if config.view == DamageMeter.VIEW.HISTORY then
            ImGui.Separator()
            if ImGui.Button("Export CSV") then
                action = "export"
            end
            ImGui.SameLine()
            if ImGui.Button("Clear Log") then
                action = "clear"
            end
        end
        ImGui.EndPopup()
    end

    return action
end

--- One table of ranked bars, at the current cursor. The header belongs to the
--- window, not to the table, so a fight in the combat log can reuse this.
--- @param roster table[] Rows carrying the totals to rank.
--- @param duration_ms integer What the rates divide by.
--- @param config table From DefaultConfig.
--- @param opts table|nil gear and the icon resolvers.
function DamageMeter.Draw(roster, duration_ms, config, opts)
    opts = opts or {}

    local tab = DamageMeter.TABS[config.tab] or DamageMeter.TABS[1]
    local rows = BuildRows(roster, tab.key, duration_ms, config)

    if #rows == 0 then
        ImGui.TextColored(0.6, 0.6, 0.65, 1, "Nothing recorded yet.")
        return
    end

    local draw_list = ImGui.GetWindowDrawList()
    local origin_x, origin_y = ImGui.GetCursorScreenPos()
    -- Returns a pair, and only the width matters, so it is bound before use.
    local avail_w = ImGui.GetContentRegionAvail()
    local width = math.max(120, avail_w)
    local step = config.row_height + config.row_spacing

    -- Only the rate gets named. The totals column is already named by the meter
    -- title above it, so labelling it again would just say Damage twice.
    local head_h = 0
    if config.show_column_headers and config.show_rate then
        head_h = ImGui.GetTextLineHeight() + 2
        Paint.TextRight(draw_list, origin_x + width - 4, origin_y, tab.unit,
            config.color_header)
    end

    for index, row in ipairs(rows) do
        local y = origin_y + head_h + (index - 1) * step
        ImGui.PushID(tostring(row.member.client_id or row.name))
        DrawRow(draw_list, origin_x, y, width, row, tab, config, opts)
        ImGui.PopID()
    end

    -- The draw list leaves the caret where it was, so claim the space by hand.
    ImGui.SetCursorScreenPos(origin_x, origin_y)
    ImGui.Dummy(width, head_h + #rows * step)
end

--- The whole meter, header and body, at the current cursor. Which body it draws is
--- the view, chosen behind the gear, so the current fight, the session totals, and
--- the combat log are one window rather than three that look the same.
--- @param data table roster, duration_ms, session_roster, fighting_ms, history.
--- @param config table From DefaultConfig, edited in place by the gear popup.
--- @param opts table|nil gear and the icon resolvers.
--- @return string|nil action "export" or "clear", for the caller to carry out.
function DamageMeter.DrawWindow(data, config, opts)
    opts = opts or {}
    local action = DrawHeader(config, opts)

    if config.view == DamageMeter.VIEW.SESSION then
        local history = data.history or {}
        ImGui.TextColored(0.7, 0.72, 0.78, 1, string.format("%d fights, %s spent fighting",
            #history, Clock(data.fighting_ms or 0)))
        DamageMeter.Draw(data.session_roster or {}, data.fighting_ms or 0, config, opts)

    elseif config.view == DamageMeter.VIEW.HISTORY then
        DamageMeter.DrawHistory(data.history or {}, config, opts)

    else
        DamageMeter.Draw(data.roster or {}, data.duration_ms or 0, config, opts)
    end

    return action
end

--- Every finished fight, newest first, each expandable into its table.
--- @param history table[] From session.GetHistory.
--- @param config table
--- @param opts table|nil
function DamageMeter.DrawHistory(history, config, opts)
    if #history == 0 then
        ImGui.TextColored(0.6, 0.6, 0.65, 1, "No fights recorded yet.")
        return
    end

    -- Newest first, since that is the fight anybody actually wants to look at.
    for index = #history, 1, -1 do
        local encounter = history[index]

        local damage = 0
        for _, member in ipairs(encounter.members) do
            damage = damage + (member.damage_done or 0)
        end

        local label = string.format("#%d   %s   %s damage, %s DPS###enc%d",
            encounter.id, Clock(encounter.duration_ms), Short(damage),
            Short(Meter.PerSecond(damage, encounter.duration_ms)), encounter.id)

        if ImGui.TreeNode(label) then
            DamageMeter.Draw(encounter.members, encounter.duration_ms, config, opts)
            ImGui.TreePop()
        end
    end
end

--- Everything each row has done all session, fights and the gaps between them.
--- Built from the session totals rather than by adding the fights up, so healing
--- done out of combat, which belongs to no fight, is still in here.
--- @param roster table[] Carrying the all_ prefixed session totals.
--- @return table[] rows Rows shaped like a roster, for Draw to render.
function DamageMeter.OverallRoster(roster)
    local rows = {}
    for _, member in ipairs(roster) do
        rows[#rows + 1] = {
            client_id = member.client_id,
            name = member.name,
            class_id = member.class_id,
            damage_done = member.all_damage_done or 0,
            damage_taken = member.all_damage_taken or 0,
            healing_done = member.all_healing_done or 0,
            healing_taken = member.all_healing_taken or 0,
        }
    end
    return rows
end

--- The time every rate in the session totals divides by, which is the time spent
--- fighting rather than the time played. Standing in town does not count against
--- anybody's damage per second.
--- @return integer duration_ms
function DamageMeter.FightingMs(history, encounter)
    -- Every fight counts for at least the floor its own rate divides by. A one hit
    -- kill lasts no time at all, and letting it contribute its damage while
    -- contributing no time would quietly inflate every rate in the session totals.
    local floor_ms = Meter.MIN_DURATION_MS
    local total = 0
    for _, past in ipairs(history) do
        total = total + math.max(past.duration_ms or 0, floor_ms)
    end
    if encounter ~= nil and encounter.active then
        total = total + math.max(encounter.duration_ms or 0, floor_ms)
    end
    return total
end

--- The whole session as a spreadsheet, one row per source per fight.
--- @return string csv
function DamageMeter.ToCsv(history)
    local lines = {
        "encounter,duration_seconds,name,class,damage_done,dps,damage_taken," ..
        "healing_done,hps,healing_taken",
    }

    for _, encounter in ipairs(history) do
        local seconds = (encounter.duration_ms or 0) / 1000
        for _, member in ipairs(encounter.members) do
            lines[#lines + 1] = string.format(
                "%d,%.1f,%s,%s,%d,%.1f,%d,%d,%.1f,%d",
                encounter.id, seconds,
                -- A name with a comma in it would otherwise split the row.
                '"' .. tostring(member.name or "?"):gsub('"', '""') .. '"',
                ClassIcon.GetName(member.class_id) or "",
                member.damage_done or 0,
                Meter.PerSecond(member.damage_done or 0, encounter.duration_ms),
                member.damage_taken or 0,
                member.healing_done or 0,
                Meter.PerSecond(member.healing_done or 0, encounter.duration_ms),
                member.healing_taken or 0)
        end
    end

    return table.concat(lines, "\n") .. "\n"
end

--- The sort controls, small enough to sit in the meter window itself.
--- @param config table Edited in place.
function DamageMeter.DrawSortControls(config)
    config.sort_by_rate = ImGui.Checkbox("Sort by rate", config.sort_by_rate)
    ImGui.SameLine()
    config.sort_descending = ImGui.Checkbox("Highest first", config.sort_descending)
end

--- @param config table Edited in place.
function DamageMeter.DrawSettings(config)
    ImGui.Text("Sorting")
    DamageMeter.DrawSortControls(config)
    ImGui.Text(config.sort_by_rate
        and "Ranked by the per second rate."
        or "Ranked by the running total.")

    ImGui.Separator()
    ImGui.Text("Rows")
    config.row_height = ImGui.SliderInt("Row height", config.row_height, 12, 40)
    config.row_spacing = ImGui.SliderInt("Row spacing", config.row_spacing, 0, 8)
    config.bar_rounding = ImGui.SliderInt("Bar rounding", config.bar_rounding, 0, 8)
    config.show_class_icons = ImGui.Checkbox("Class icon on the left", config.show_class_icons)
    config.show_rank = ImGui.Checkbox("Rank numbers", config.show_rank)
    config.show_rate = ImGui.Checkbox("Per second rate", config.show_rate)
    config.show_percent = ImGui.Checkbox("Share of the table", config.show_percent)
    config.show_column_headers = ImGui.Checkbox("Header over the rate column",
        config.show_column_headers)
    config.hide_empty_rows = ImGui.Checkbox("Hide rows with nothing", config.hide_empty_rows)

    ImGui.Separator()
    ImGui.Text("Colors")
    config.unique_colors = ImGui.Checkbox("A color per name, not per class",
        config.unique_colors)
    ImGui.Text(config.unique_colors
        and "Derived from the name, so a color stays the same across sessions."
        or "Two rows of the same class share a bar color.")

    config.color_row_bg = ImGui.ColorEdit4("Row background", config.color_row_bg)
    config.color_text = ImGui.ColorEdit4("Text", config.color_text)
end

return DamageMeter
