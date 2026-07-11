--[[
    tape_compass.lua

    A compass bar for wereoxxs_ui, drawn as a horizontal heading tape.

    The tape scrolls as the camera turns, with the current heading centered
    under a caret. Cardinal points draw as letters, the degrees between them as
    numbers, and group members with a known position draw as dots at their
    bearing. Positions come from the game's own group data, read locally by the
    caller and passed in. A member you are facing sits centered under the caret,
    and one outside the visible arc clamps to the nearest edge, dimmed.
]]

local Paint = require("paint")
local ClassIcon = require("class_icon")

local TapeCompass = {}

--- Everything the user can change. One flat table, so it can be handed straight
--- to the UiForge profile save and load callbacks.
function TapeCompass.DefaultConfig()
    return {
        width = 420,
        height = 30,
        rounding = 4,
        -- How much of the horizon the bar shows at once. Smaller reads finer,
        -- larger keeps more of the group on the tape.
        degrees_visible = 120,

        show_degree_numbers = true,
        show_heading_number = true,
        show_party_dots = true,
        dot_size = 5,
        -- A member outside the visible arc clamps to the edge, dimmed, rather
        -- than dropping off the bar entirely.
        clamp_offscreen_dots = true,

        -- Turning this compass on hides the game's own compass, unless the
        -- user would rather keep both.
        hide_game_compass = true,

        color_background = { 0.07, 0.07, 0.09, 0.88 },
        color_border     = { 0.30, 0.30, 0.36, 0.85 },
        color_tick       = { 0.55, 0.55, 0.60, 0.90 },
        color_cardinal   = { 1.00, 1.00, 1.00, 1.00 },
        color_degrees    = { 0.72, 0.72, 0.78, 1.00 },
        color_caret      = { 1.00, 1.00, 1.00, 1.00 },
        color_dot        = { 0.40, 0.80, 1.00, 1.00 },
    }
end

local CARDINALS = {
    [0] = "N", [45] = "NE", [90] = "E", [135] = "SE",
    [180] = "S", [225] = "SW", [270] = "W", [315] = "NW",
}

-- Shortest signed distance from one angle to another, in degrees.
local function SignedDiff(from_deg, to_deg)
    return (to_deg - from_deg + 180) % 360 - 180
end

local function Distance(a, b)
    local dx, dy, dz = b.x - a.x, (b.y or 0) - (a.y or 0), b.z - a.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- One group member's dot. Members off the visible arc clamp to the edge, dimmed,
-- so somebody behind you still registers as a direction to turn.
local function DrawDot(draw_list, index, member, offset, x, y, half_w, config, opts)
    local w = half_w * 2
    local center_x = x + half_w
    local clamped = math.abs(offset) > config.degrees_visible / 2

    if clamped and not config.clamp_offscreen_dots then
        return
    end

    local fraction = offset / (config.degrees_visible / 2)
    fraction = math.max(-1, math.min(1, fraction))
    local dot_x = center_x + fraction * (half_w - config.dot_size - 2)
    local dot_y = y + config.height - config.dot_size - 3

    local color = config.color_dot
    if member.class_id ~= nil and ClassIcon.GetColor(member.class_id) ~= nil then
        local r, g, b = ClassIcon.GetColorFloats(member.class_id)
        color = { r, g, b, 1 }
    end
    if clamped then
        color = { color[1], color[2], color[3], 0.45 }
    end

    local size = config.dot_size
    draw_list:AddCircleFilled(ImVec2.new(dot_x, dot_y), size, Paint.Color(color))
    draw_list:AddCircle(ImVec2.new(dot_x, dot_y), size, Paint.Color({ 0, 0, 0, 0.8 }))

    if Paint.HitRegion("dot" .. index, dot_x - size, dot_y - size, size * 2, size * 2) then
        local text = member.name or "?"
        if member.distance ~= nil then
            text = string.format("%s\n%.0f away, %.0f degrees", text, member.distance, offset)
        end
        Paint.Tooltip(text)
    end
end

--- Draws the compass bar at the current cursor position.
--- @param heading_deg number The camera's compass heading, degrees.
--- @param origin table|nil The local player's position, with x, y, z.
--- @param roster table[] Member rows, dots drawn for anyone with a position.
--- @param config table From DefaultConfig, with the user's changes applied.
--- @param opts table|nil get_bearing(from, to) in compass degrees.
function TapeCompass.Draw(heading_deg, origin, roster, config, opts)
    opts = opts or {}
    local draw_list = ImGui.GetWindowDrawList()
    local x, y = ImGui.GetCursorScreenPos()

    local label_h = config.show_heading_number and (ImGui.GetTextLineHeight() + 1) or 0
    y = y + label_h
    local w, h = config.width, config.height
    local half_w = w / 2
    local center_x = x + half_w
    local half_arc = config.degrees_visible / 2

    Paint.Rect(draw_list, x, y, w, h, config.color_background, config.rounding)
    Paint.Border(draw_list, x, y, w, h, config.color_border, config.rounding, 1)
    Paint.PushClip(draw_list, x + 1, y, w - 2, h)

    -- The tape. Ticks every 5 degrees, numbers every 15, letters on the
    -- cardinals and intercardinals.
    local first = math.ceil((heading_deg - half_arc) / 5) * 5
    for deg = first, heading_deg + half_arc, 5 do
        local offset = SignedDiff(heading_deg, deg)
        local tick_x = center_x + (offset / half_arc) * half_w
        local wrapped = deg % 360
        local cardinal = CARDINALS[wrapped]

        if cardinal ~= nil then
            Paint.Rect(draw_list, tick_x - 0.5, y + 2, 1, 5, config.color_tick, 0)
            Paint.TextCentered(draw_list, tick_x - 20, y + 8, 40, cardinal, config.color_cardinal)
        elseif wrapped % 15 == 0 and config.show_degree_numbers then
            Paint.Rect(draw_list, tick_x - 0.5, y + 2, 1, 4, config.color_tick, 0)
            Paint.TextCentered(draw_list, tick_x - 20, y + 9, 40, tostring(wrapped),
                config.color_degrees)
        else
            Paint.Rect(draw_list, tick_x - 0.5, y + 2, 1, 3,
                { config.color_tick[1], config.color_tick[2], config.color_tick[3], 0.5 }, 0)
        end
    end

    -- Group member dots ride the bottom of the bar.
    if config.show_party_dots and origin ~= nil and opts.get_bearing ~= nil then
        for index, member in ipairs(roster) do
            if not member.is_self and member.x ~= nil and member.z ~= nil then
                local bearing = opts.get_bearing(origin, member)
                member.distance = Distance(origin, member)
                DrawDot(draw_list, index, member, SignedDiff(heading_deg, bearing),
                    x, y, half_w, config, opts)
            end
        end
    end

    Paint.PopClip(draw_list)

    -- The caret marking the current heading, with the number above it.
    draw_list:AddTriangleFilled(
        ImVec2.new(center_x - 4, y),
        ImVec2.new(center_x + 4, y),
        ImVec2.new(center_x, y + 5),
        Paint.Color(config.color_caret))
    if config.show_heading_number then
        Paint.TextCentered(draw_list, center_x - 20, y - ImGui.GetTextLineHeight() - 1, 40,
            tostring(math.floor(heading_deg % 360 + 0.5) % 360), config.color_caret)
    end

    -- The draw list does not move the cursor, so reserve the space by hand. The
    -- heading number above the bar is part of the claim, so the window sizes to it.
    ImGui.SetCursorScreenPos(x, y - label_h)
    ImGui.Dummy(w, h + label_h)
end

--- Total size the bar will occupy, so a caller can size a window to fit.
--- @return number width
--- @return number height
function TapeCompass.GetSize(config)
    local label_h = config.show_heading_number and (ImGui.GetTextLineHeight() + 1) or 0
    return config.width, config.height + label_h
end

--- The settings panel for the compass bar.
--- @param config table Edited in place.
function TapeCompass.DrawSettings(config)
    config.hide_game_compass = ImGui.Checkbox("Hide the game's compass while this is on",
        config.hide_game_compass)

    ImGui.Separator()
    ImGui.Text("Bar")
    config.width = ImGui.SliderInt("Width", config.width, 150, 900)
    config.height = ImGui.SliderInt("Height", config.height, 20, 60)
    config.rounding = ImGui.SliderInt("Corner rounding", config.rounding, 0, 12)
    config.degrees_visible = ImGui.SliderInt("Degrees shown", config.degrees_visible, 60, 360)
    config.show_degree_numbers = ImGui.Checkbox("Degree numbers between the letters",
        config.show_degree_numbers)
    config.show_heading_number = ImGui.Checkbox("Current heading above the caret",
        config.show_heading_number)

    ImGui.Separator()
    ImGui.Text("Group dots")
    config.show_party_dots = ImGui.Checkbox("Dots for group members", config.show_party_dots)
    config.dot_size = ImGui.SliderInt("Dot size", config.dot_size, 2, 12)
    config.clamp_offscreen_dots = ImGui.Checkbox("Pin members behind you to the edges",
        config.clamp_offscreen_dots)
    ImGui.Text("A member you are facing sits centered under the caret. Dots use")
    ImGui.Text("class colors, and hovering one shows the name and distance.")

    ImGui.Separator()
    ImGui.Text("Colors")
    local swatches = {
        { key = "color_background", label = "Background" },
        { key = "color_border",     label = "Border" },
        { key = "color_cardinal",   label = "Cardinal letters" },
        { key = "color_degrees",    label = "Degree numbers" },
        { key = "color_tick",       label = "Ticks" },
        { key = "color_caret",      label = "Caret" },
        { key = "color_dot",        label = "Dot, class unknown" },
    }
    for _, swatch in ipairs(swatches) do
        config[swatch.key] = ImGui.ColorEdit4(swatch.label, config[swatch.key])
    end
end

return TapeCompass
