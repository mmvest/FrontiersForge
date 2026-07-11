--[[
    paint.lua

    Drawing helpers for eqoa_tools, built on the ImGui draw list.

    Everything is in screen coordinates and goes straight into the draw list, so
    nothing here disturbs the ImGui layout caret.

    Colors are passed around as tables of four numbers from 0 to 1, red green blue
    alpha, and converted to the packed value ImGui wants at the point of use.
]]

local Paint = {}

--- Sifts out a texture that failed to load.
--- A texture handle is a raw pointer, and a failed load comes back as a null one
--- rather than as nil. A null pointer is truthy in Lua, so without this a missing
--- file reads as real art and draws an empty image where the art should be.
--- @return userdata|nil texture nil when there is nothing usable to draw.
function Paint.ValidTexture(texture)
    if texture == nil then
        return nil
    end
    local address = tostring(texture)
    if address:find("NULL") or address:find("0x0+$") or address:find(":%s0+$") then
        return nil
    end
    return texture
end

--- Packs a color table into the value the draw list expects.
--- @param color table Four numbers from 0 to 1. Alpha defaults to 1.
--- @return integer packed
function Paint.Color(color)
    return ImGui.GetColorU32(color[1], color[2], color[3], color[4] or 1)
end

--- A filled rectangle.
--- @param draw_list userdata From ImGui.GetWindowDrawList.
--- @param rounding number|nil Corner radius, 0 for square.
function Paint.Rect(draw_list, x, y, w, h, color, rounding)
    if w <= 0 or h <= 0 then
        return
    end
    draw_list:AddRectFilled(ImVec2.new(x, y), ImVec2.new(x + w, y + h),
        Paint.Color(color), rounding or 0)
end

--- An outline.
function Paint.Border(draw_list, x, y, w, h, color, rounding, thickness)
    if w <= 0 or h <= 0 then
        return
    end
    draw_list:AddRect(ImVec2.new(x, y), ImVec2.new(x + w, y + h),
        Paint.Color(color), rounding or 0, 0, thickness or 1)
end

--- A horizontally filled bar.
--- @param fraction number From 0 to 1, clamped.
function Paint.Bar(draw_list, x, y, w, h, fraction, color, rounding)
    if w <= 0 or h <= 0 or fraction == nil or fraction <= 0 then
        return
    end
    if fraction > 1 then
        fraction = 1
    end

    local fill_w = w * fraction
    if fill_w < 1 then
        fill_w = 1
    end

    Paint.Rect(draw_list, x, y, fill_w, h, color, rounding)
end

--- Text at an exact spot, which the draw list does without touching the caret.
function Paint.Text(draw_list, x, y, text, color)
    draw_list:AddText(ImVec2.new(x, y), Paint.Color(color), text)
end

--- Text pushed right so it ends at the given edge.
function Paint.TextRight(draw_list, right_x, y, text, color)
    local width = ImGui.CalcTextSize(text)
    Paint.Text(draw_list, right_x - width, y, text, color)
end

--- Text centered on a span.
function Paint.TextCentered(draw_list, x, y, w, text, color)
    local width = ImGui.CalcTextSize(text)
    Paint.Text(draw_list, x + (w - width) / 2, y, text, color)
end

--- Confines the next draw list calls to a rectangle, so long text is cut off at
--- an edge rather than running past it. Always pair with PopClip.
function Paint.PushClip(draw_list, x, y, w, h)
    draw_list:PushClipRect(ImVec2.new(x, y), ImVec2.new(x + math.max(0, w), y + h), true)
end

function Paint.PopClip(draw_list)
    draw_list:PopClipRect()
end

--- A tooltip carrying text we already built.
--- SetTooltip runs what it is given through printf, so a percent sign in the text
--- reads as the start of a format spec and swallows whatever follows it. Doubling
--- them puts the literal percent back.
--- @param text string
function Paint.Tooltip(text)
    ImGui.SetTooltip((text:gsub("%%", "%%%%")))
end

--- Hover test for a region of draw list art. A plain rectangle test rather than
--- an invisible item, so the art never captures the mouse and the window stays
--- draggable from anywhere on it.
--- @param id string Unique within the current id scope, kept for callers.
--- @return boolean hovered
function Paint.HitRegion(id, x, y, w, h)
    if w <= 0 or h <= 0 then
        return false
    end
    return ImGui.IsWindowHovered() and ImGui.IsMouseHoveringRect(x, y, x + w, y + h)
end

--- The same thing, but for art that is meant to be clicked. ImageButton is not
--- bound by the host, so a picture that acts like a button is a draw list image
--- with an invisible button claimed over the top of it.
--- @return boolean pressed
function Paint.HitButton(id, x, y, w, h)
    if w <= 0 or h <= 0 then
        return false
    end
    ImGui.SetCursorScreenPos(x, y)
    return ImGui.InvisibleButton(id, w, h)
end

return Paint
