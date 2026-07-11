--[[
    class_icon.lua

    Class badges and class colors for eqoa_tools.

    The game's own class emblem is drawn when it can be resolved, which is the
    same crest the pause menu shows. The emblems are wide rather than square, so
    they are fitted to the badge box with their aspect kept.

    A PNG at resources/class_icons/<lowercase class name>.png overrides the game's
    art. Failing both, a badge is drawn instead, a rounded rect in the class color
    carrying a two letter code, which is what shows before the game is loaded and
    its textures can be read.
]]

local Paint = require("paint")

local ClassIcon = {}

ClassIcon.names = {
    [0] = "Warrior", [1] = "Ranger", [2] = "Paladin", [3] = "Shadowknight",
    [4] = "Monk", [5] = "Bard", [6] = "Rogue", [7] = "Druid",
    [8] = "Shaman", [9] = "Cleric", [10] = "Magician", [11] = "Necromancer",
    [12] = "Enchanter", [13] = "Wizard", [14] = "Alchemist",
}

-- Color is the load bearing part of the badge, since at party frame sizes it reads
-- long before the letters do. Kept far apart in hue.
ClassIcon.colors = {
    [0]  = { 0.77, 0.65, 0.43 }, -- Warrior
    [1]  = { 0.67, 0.83, 0.45 }, -- Ranger
    [2]  = { 0.96, 0.55, 0.73 }, -- Paladin
    [3]  = { 0.62, 0.25, 0.57 }, -- Shadowknight
    [4]  = { 0.00, 0.80, 0.59 }, -- Monk
    [5]  = { 0.77, 0.43, 0.86 }, -- Bard
    [6]  = { 1.00, 0.96, 0.41 }, -- Rogue
    [7]  = { 1.00, 0.49, 0.04 }, -- Druid
    [8]  = { 0.00, 0.44, 0.87 }, -- Shaman
    [9]  = { 0.94, 0.94, 0.94 }, -- Cleric
    [10] = { 0.89, 0.35, 0.24 }, -- Magician
    [11] = { 0.24, 0.55, 0.31 }, -- Necromancer
    [12] = { 0.67, 0.51, 0.94 }, -- Enchanter
    [13] = { 0.41, 0.80, 0.94 }, -- Wizard
    [14] = { 0.27, 0.78, 0.75 }, -- Alchemist
}

ClassIcon.codes = {
    [0] = "WA", [1] = "RA", [2] = "PA", [3] = "SK", [4] = "MO",
    [5] = "BA", [6] = "RO", [7] = "DR", [8] = "SH", [9] = "CL",
    [10] = "MA", [11] = "NE", [12] = "EN", [13] = "WI", [14] = "AL",
}

local overrides = {}
local override_tried = {}

--- @param class_id integer
--- @return table|nil color Three numbers from 0 to 1.
function ClassIcon.GetColor(class_id)
    return ClassIcon.colors[class_id]
end

--- @return number r
--- @return number g
--- @return number b
function ClassIcon.GetColorFloats(class_id)
    local color = ClassIcon.colors[class_id] or { 0.78, 0.78, 0.78 }
    return color[1], color[2], color[3]
end

--- @return string|nil name
function ClassIcon.GetName(class_id)
    return ClassIcon.names[class_id]
end

-- Real art wins over the badge when it is there. Looked up once per class.
local function GetOverride(class_id)
    if override_tried[class_id] then
        return overrides[class_id]
    end
    override_tried[class_id] = true

    local name = ClassIcon.names[class_id]
    if name ~= nil then
        overrides[class_id] = Paint.ValidTexture(
            UiForge.LoadTexture("class_icons/" .. name:lower() .. ".png"))
    end
    return overrides[class_id]
end

-- Dark letters on a bright badge, light on a dark one, so the code stays readable
-- whatever the class color is.
local function TextColor(color)
    local luminance = 0.299 * color[1] + 0.587 * color[2] + 0.114 * color[3]
    if luminance > 0.55 then
        return { 0.08, 0.08, 0.10, 1 }
    end
    return { 1, 1, 1, 1 }
end

-- The emblem, fitted inside the badge box and centered. The emblems are far wider
-- than they are tall, so fitting the long side and letting the other follow from
-- the aspect is what keeps a wide crest from coming out squashed.
local function DrawArt(draw_list, x, y, size, texture, width, height)
    local white = Paint.Color({ 1, 1, 1, 1 })
    local uv0, uv1 = ImVec2.new(0, 0), ImVec2.new(1, 1)

    local draw_w, draw_h = size, size
    if width ~= nil and height ~= nil and width > 0 and height > 0 then
        local scale = size / math.max(width, height)
        draw_w, draw_h = width * scale, height * scale
    end

    local ox = x + (size - draw_w) / 2
    local oy = y + (size - draw_h) / 2
    draw_list:AddImage(texture, ImVec2.new(ox, oy), ImVec2.new(ox + draw_w, oy + draw_h),
        uv0, uv1, white)
end

--- Draws the badge for a class at a screen position.
--- Prefers the game's own emblem, and falls back to a colored badge with a two
--- letter code when the art cannot be resolved, which is what happens before the
--- game is loaded.
--- @param draw_list userdata From ImGui.GetWindowDrawList.
--- @param size number Side length of the square badge.
--- @param opts table|nil get_class_icon, supplied by the caller so this module
---   never reads game memory itself.
--- @return boolean drawn False for an unknown class id, so callers can skip the slot.
function ClassIcon.Draw(draw_list, x, y, size, class_id, opts)
    local color = ClassIcon.colors[class_id]
    if color == nil then
        return false
    end

    if opts ~= nil and opts.get_class_icon ~= nil then
        local texture, width, height = opts.get_class_icon(class_id)
        if texture ~= nil then
            DrawArt(draw_list, x, y, size, texture, width, height)
            return true
        end
    end

    local texture = GetOverride(class_id)
    if texture ~= nil then
        DrawArt(draw_list, x, y, size, texture)
        return true
    end

    local rounding = math.max(2, size * 0.25)
    Paint.Rect(draw_list, x, y, size, size,
        { color[1], color[2], color[3], 1 }, rounding)
    Paint.Border(draw_list, x, y, size, size,
        { color[1] * 0.35, color[2] * 0.35, color[3] * 0.35, 1 }, rounding, 1)

    -- The code only fits once the badge is big enough to hold two glyphs.
    local code = ClassIcon.codes[class_id]
    if code ~= nil and size >= 14 then
        local text_w, text_h = ImGui.CalcTextSize(code)
        Paint.Text(draw_list, x + (size - text_w) / 2, y + (size - text_h) / 2,
            code, TextColor(color))
    end
    return true
end

return ClassIcon
