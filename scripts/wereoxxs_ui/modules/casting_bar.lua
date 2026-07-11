--[[
    casting_bar.lua

    The casting bar for wereoxxs_ui.

    The spell's icon sits on the left with its plate and art, a fill bar runs
    to the right of it filling as the cast completes, the spell's name sits
    centered in the bar, and an optional countdown in parentheses ticks down in
    tenths of a second. The bar disappears when the cast ends.

    While the settings panel is open the bar draws itself with placeholder data
    counting down on repeat, so it can be placed and styled without waiting for
    a real cast.

        {
            name = string,
            fg, fg_w, fg_h, bg, bg_w, bg_h = icon textures and sizes,
            duration_ms = total cast time,
            started_ms = when the cast began, on the caller's clock,
        }
]]

local Paint = require("paint")

local CastingBar = {}

--- Everything the user can change.
function CastingBar.DefaultConfig()
    return {
        width = 260,
        height = 26,
        rounding = 5,
        show_countdown = true,

        color_background = { 0.06, 0.06, 0.08, 0.90 },
        color_fill       = { 0.85, 0.65, 0.18, 1.00 },
        color_border     = { 0.30, 0.30, 0.36, 0.90 },
        color_text       = { 1.00, 1.00, 1.00, 1.00 },
    }
end

--- The looping placeholder shown while the settings panel is open.
--- @param now_ms integer
function CastingBar.PreviewCast(now_ms)
    local duration = 5000
    return {
        name = "Example Spell",
        duration_ms = duration,
        started_ms = now_ms - (now_ms % duration),
    }
end

--- Total size the bar occupies, icon included.
function CastingBar.GetSize(config)
    return config.width + config.height, config.height
end

--- Draws the casting bar at the current cursor position.
--- @param cast table The active cast row, see the file header.
--- @param config table From DefaultConfig, with the user's changes applied.
--- @param now_ms integer The caller's frame clock.
--- @return boolean finished True once the cast has run its full duration.
function CastingBar.Draw(cast, config, now_ms)
    local draw_list = ImGui.GetWindowDrawList()
    local x, y = ImGui.GetCursorScreenPos()
    local h = config.height
    local w = config.width

    local elapsed = now_ms - (cast.started_ms or now_ms)
    local duration = math.max(1, cast.duration_ms or 1)
    local fraction = math.max(0, math.min(1, elapsed / duration))

    -- The icon square on the left, plate first, art on top in the game's own
    -- proportions.
    Paint.Rect(draw_list, x, y, h, h, config.color_background, config.rounding)
    local white = Paint.Color({ 1, 1, 1, 1 })
    local uv0, uv1 = ImVec2.new(0, 0), ImVec2.new(1, 1)
    if cast.bg ~= nil then
        draw_list:AddImage(cast.bg, ImVec2.new(x, y), ImVec2.new(x + h, y + h), uv0, uv1, white)
    end
    if cast.fg ~= nil then
        local fw, fh = h, h
        if cast.fg_w and cast.fg_h and cast.fg_w > 0 and cast.fg_h > 0 then
            if cast.bg ~= nil and cast.bg_w and cast.bg_h and cast.bg_w > 0 and cast.bg_h > 0 then
                fw, fh = h * (cast.fg_w / cast.bg_w), h * (cast.fg_h / cast.bg_h)
            else
                local scale = h / math.max(cast.fg_w, cast.fg_h)
                fw, fh = cast.fg_w * scale, cast.fg_h * scale
            end
        end
        draw_list:AddImage(cast.fg,
            ImVec2.new(x + (h - fw) / 2, y + (h - fh) / 2),
            ImVec2.new(x + (h + fw) / 2, y + (h + fh) / 2), uv0, uv1, white)
    end
    Paint.Border(draw_list, x, y, h, h, config.color_border, config.rounding, 1)

    -- The fill bar directly after the icon.
    local bar_x = x + h
    Paint.Rect(draw_list, bar_x, y, w, h, config.color_background, config.rounding)
    if fraction > 0 then
        Paint.Bar(draw_list, bar_x, y, w, h, fraction, config.color_fill, config.rounding)
    end
    Paint.Border(draw_list, bar_x, y, w, h, config.color_border, config.rounding, 1)

    local label = cast.name or ""
    if config.show_countdown then
        local left = math.max(0, duration - elapsed) / 1000
        label = string.format("%s  (%.1fs)", label, left)
    end
    local text_w, text_h = ImGui.CalcTextSize(label)
    if text_w <= w - 8 then
        Paint.Text(draw_list, bar_x + (w - text_w) / 2 + 1, y + (h - text_h) / 2 + 1,
            label, { 0, 0, 0, 0.85 })
        Paint.Text(draw_list, bar_x + (w - text_w) / 2, y + (h - text_h) / 2,
            label, config.color_text)
    end

    local total_w, total_h = CastingBar.GetSize(config)
    ImGui.SetCursorScreenPos(x, y)
    ImGui.Dummy(total_w, total_h)

    return elapsed >= duration
end

--- The settings panel.
--- @param config table Edited in place.
function CastingBar.DrawSettings(config)
    ImGui.Text("While this panel is open the bar shows a looping preview, so it")
    ImGui.Text("can be dragged into place and styled without casting anything.")
    ImGui.Separator()
    config.width = ImGui.SliderInt("Bar width", config.width, 100, 600)
    config.height = ImGui.SliderInt("Bar height", config.height, 16, 48)
    config.rounding = ImGui.SliderInt("Corner rounding", config.rounding, 0, 12)
    config.show_countdown = ImGui.Checkbox("Countdown in tenths of a second",
        config.show_countdown)

    ImGui.Separator()
    ImGui.Text("Colors")
    config.color_fill = ImGui.ColorEdit4("Fill", config.color_fill)
    config.color_background = ImGui.ColorEdit4("Background", config.color_background)
    config.color_border = ImGui.ColorEdit4("Border", config.color_border)
    config.color_text = ImGui.ColorEdit4("Text", config.color_text)
end

return CastingBar
