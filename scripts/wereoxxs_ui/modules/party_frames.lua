--[[
    party_frames.lua

    The player, target, and group frames for wereoxxs_ui.

    Draws member cells in a small grid, sized for what the local client can
    actually see, yourself and a game group. A cell is a name row with the
    class badge, a health bar, and a power bar under it.

    Health and power bars always share a width, so the cells stay uniform, but
    their heights are set separately, since people want the power bar thicker or
    thinner depending on what they are playing.

    Everything is drawn through the ImGui draw list in screen coordinates, so the
    layout caret is never disturbed and cells land exactly where they are put.
    Hover regions for the tooltips are claimed separately, since draw list output
    is not an ImGui item and has nothing to hang a tooltip off on its own.

    This module never reads game memory. Icons are resolved through callbacks
    the caller supplies, so the same code draws a live group, a solo player,
    and a test roster.
]]

local bit = require("bit")
local Paint = require("paint")
local ClassIcon = require("class_icon")

local PartyFrames = {}

-- Ranges for every sized setting, shared by the settings sliders and the auto
-- fit clamp so the two can never disagree. The upper ends are generous enough
-- for the largest font on offer.
local LIMITS = {
    cell_width        = { 60, 600 },
    cell_height       = { 30, 400 },
    bar_width         = { 40, 590 },
    health_bar_height = { 4, 120 },
    power_bar_height  = { 4, 120 },
    pet_frame_height  = { 8, 90 },
    class_icon_size   = { 8, 64 },
    effect_icon_size  = { 8, 64 },
    exp_bar_thickness = { 1, 60 },
}

local function ClampSetting(key, value)
    local limit = LIMITS[key]
    if limit == nil then
        return value
    end
    return math.max(limit[1], math.min(limit[2], value))
end

--- Everything the user can change. One flat table, so it can be handed straight
--- to the UiForge profile save and load callbacks.
function PartyFrames.DefaultConfig()
    return {
        -- Layout. The client only ever knows about a six member group, so the
        -- grid stays small.
        columns = 1,           -- entries per row
        rows = 6,              -- entries per column
        -- Tall enough for the name row and the health number under it,
        -- without either crowding the other.
        cell_width = 142,
        cell_height = 68,
        cell_spacing = 3,
        cell_rounding = 3,
        fill_down_columns = true,

        -- Grow every size with the font, so raising the font size never leaves
        -- text spilling out of its plate. The new sizes are written back into
        -- these settings rather than forced each frame, so the sliders can be
        -- pulled back down afterwards and stay where they are put.
        auto_fit = true,
        -- The text line height the sizes above were last fitted to.
        fitted_line_h = nil,

        -- Overlay puts the health bar behind the whole entry, with the name
        -- and numbers sitting on top of it and the power bar as a strip
        -- underneath. Stacked draws health and power as two separate bars
        -- below the name instead.
        overlay_style = true,

        -- Bars. In overlay the health bar is the entry, so bar_width and
        -- health_bar_height only apply to the stacked style. The power bar height
        -- applies to both.
        bar_width = 114,
        health_bar_height = 18,
        power_bar_height = 14,
        -- Square. The bars keep straight, crisp edges, and the softening comes from
        -- the cell rounding around them instead.
        bar_rounding = 0,

        -- The box around the whole grid.
        show_frame = true,
        frame_padding = 5,
        frame_rounding = 4,

        -- Text on the bars
        show_health_text = true,
        health_as_percent = false,   -- false shows current / max
        show_power_bar = true,
        show_power_text = true,
        power_as_percent = false,

        -- Class badge
        show_class_icons = true,
        class_icon_size = 14,
        class_icon_scale = 1.0,

        -- Active effects, the local player's buffs and debuffs, tucked into
        -- the bottom right of the cell and filling toward the left. The game
        -- shares nothing about anyone else's effects, so only your own frame
        -- ever has any to show.
        show_effects = true,
        max_effects = 8,
        effect_icon_size = 15,

        color_health_by_class = true,

        -- The member's level, right aligned on the name row.
        show_level = true,

        -- The experience bar. It gets its own strip of the cell, vertical on the
        -- left or right edge, or horizontal above the health bar or under the
        -- power bar, and the cell grows by its thickness so it never covers the
        -- bars or their numbers. Hovering it shows the exact numbers.
        show_exp_bar = true,
        exp_bar_position = "bottom",   -- "left", "right", "top", "bottom"
        exp_bar_thickness = 8,
        -- Text on the bar, horizontal positions only. "none", "numbers",
        -- "percent", or "both". It only fits once the bar is thick enough.
        exp_text_mode = "none",
        color_exp = { 0.98, 0.85, 0.20, 1.00 },

        -- Pets. A small name and health strip attached under the owner's cell.
        -- Every cell reserves the row so the grid stays uniform, and members
        -- without a pet leave it empty.
        show_pets = true,
        pet_frame_height = 14,
        pet_frame_indent = 0,
        color_pet = { 0.45, 0.68, 0.48, 1.00 },

        -- Colors, red green blue alpha from 0 to 1
        color_background    = { 0.09, 0.09, 0.11, 0.94 },
        color_bar_bg        = { 0.00, 0.00, 0.00, 0.55 },
        color_frame_bg      = { 0.05, 0.05, 0.07, 0.72 },
        color_frame_border  = { 0.35, 0.35, 0.42, 0.85 },
        color_health        = { 0.22, 0.72, 0.28, 1.00 },
        color_health_low    = { 0.85, 0.20, 0.20, 1.00 },
        color_power         = { 0.26, 0.48, 0.92, 1.00 },
        color_border        = { 0.28, 0.28, 0.33, 1.00 },
        color_border_self   = { 0.96, 0.86, 0.36, 1.00 },
        color_border_leader = { 0.40, 0.80, 1.00, 1.00 },
        color_border_no_mod = { 0.30, 0.30, 0.34, 0.45 },
        color_text          = { 1.00, 1.00, 1.00, 1.00 },
        color_text_shadow   = { 0.00, 0.00, 0.00, 0.85 },
        color_dead          = { 0.45, 0.13, 0.13, 1.00 },
        color_no_data       = { 0.17, 0.17, 0.20, 1.00 },

        -- Below this fraction the health bar bleeds toward the low color.
        low_health_fraction = 0.35,
    }
end

-- Matches protocol.lua, kept here so the drawing does not need to import it.
local STATUS_DEAD = 0x02

local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- Blends toward the low health color as a member drops, so a cell in trouble
-- reads at a glance rather than only once it crosses a threshold.
local function HealthColor(config, fraction, class_id)
    local base
    if config.color_health_by_class and ClassIcon.GetColor(class_id) ~= nil then
        local r, g, b = ClassIcon.GetColorFloats(class_id)
        base = { r, g, b, 1 }
    else
        base = config.color_health
    end

    local threshold = config.low_health_fraction
    if fraction == nil or threshold <= 0 or fraction >= threshold then
        return base
    end

    local low = config.color_health_low
    local t = 1 - (fraction / threshold)
    return {
        Lerp(base[1], low[1], t),
        Lerp(base[2], low[2], t),
        Lerp(base[3], low[3], t),
        1,
    }
end

local function FormatValue(current, maximum, as_percent)
    if current == nil or maximum == nil or maximum <= 0 then
        return nil
    end
    if as_percent then
        return string.format("%d%%", math.floor(current / maximum * 100 + 0.5))
    end
    return string.format("%d/%d", current, maximum)
end

local ELLIPSIS = "..."

-- Steps back off a UTF-8 continuation byte, so a cut never lands inside a
-- multi byte character and leaves a broken glyph behind.
local function Utf8Floor(text, len)
    while len > 0 and bit.band(text:byte(len + 1) or 0, 0xC0) == 0x80 do
        len = len - 1
    end
    return len
end

--- The most of a string that fits in max_w, ending in an ellipsis when it had
--- to be cut. Returns nil when not even the ellipsis fits.
local function Truncate(text, max_w)
    if text == nil or text == "" then
        return text
    end
    if ImGui.CalcTextSize(text) <= max_w then
        return text
    end
    if ImGui.CalcTextSize(ELLIPSIS) > max_w then
        return nil
    end
    -- Longest prefix that still fits once the ellipsis is on the end.
    local low, high = 0, #text
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        if ImGui.CalcTextSize(text:sub(1, Utf8Floor(text, mid)) .. ELLIPSIS) <= max_w then
            low = mid
        else
            high = mid - 1
        end
    end
    low = Utf8Floor(text, low)
    if low <= 0 then
        -- Room for the ellipsis but not a single character before it, so the
        -- ellipsis alone stands in for the name.
        return ELLIPSIS
    end
    return text:sub(1, low) .. ELLIPSIS
end

--- Grows every size with the font so text keeps its room. Only runs when the
--- line height actually changed, and writes the result back into the config,
--- which leaves the user free to shrink anything afterwards. Safe to call
--- every frame, and must be called with the window's font active.
--- @param config table Edited in place.
function PartyFrames.FitToFont(config)
    local _, line_h = ImGui.CalcTextSize("Ay")
    if line_h == nil or line_h <= 0 then
        return
    end

    local fitted = config.fitted_line_h
    if fitted == nil or fitted <= 0 or config.auto_fit == false then
        -- Nothing to grow from yet, or the user turned growing off, so just
        -- remember where we are and leave the sizes alone.
        config.fitted_line_h = line_h
        return
    end
    if math.abs(line_h - fitted) < 0.5 then
        return
    end

    local scale = line_h / fitted
    for key in pairs(LIMITS) do
        if type(config[key]) == "number" then
            config[key] = ClampSetting(key, math.floor(config[key] * scale + 0.5))
        end
    end
    config.fitted_line_h = line_h
end

-- Text over a bar needs a shadow or it vanishes against the bright part of it.
local function ShadowedText(draw_list, x, y, text, config)
    Paint.Text(draw_list, x + 1, y + 1, text, config.color_text_shadow)
    Paint.Text(draw_list, x, y, text, config.color_text)
end

local function CenteredOnBar(draw_list, x, y, w, h, text, config)
    local text_w, text_h = ImGui.CalcTextSize(text)
    if text_w > w then
        return -- would spill out of the bar, so leave it off
    end
    ShadowedText(draw_list, x + (w - text_w) / 2, y + (h - text_h) / 2, text, config)
end

-- One bar, with its background, fill, and centered label.
local function DrawBar(draw_list, x, y, w, h, fraction, color, label, config, opts)
    Paint.Rect(draw_list, x, y, w, h, config.color_bar_bg, config.bar_rounding)

    if fraction ~= nil and fraction > 0 then
        Paint.Bar(draw_list, x, y, w, h, fraction, color, config.bar_rounding)
    end

    if label ~= nil then
        CenteredOnBar(draw_list, x, y, w, h, label, config)
    end
end

-- One active effect icon, with its name on hover.
local function DrawEffectIcon(draw_list, id, x, y, size, effect, opts)
    local get_icon = opts.get_icon or function() return nil end
    local texture, fg_w, fg_h = get_icon(effect.icon_ref)

    if texture ~= nil then
        -- The art fills the slot on its long side and keeps its aspect.
        local w, h = size, size
        if fg_w ~= nil and fg_h ~= nil and fg_w > 0 and fg_h > 0 then
            local scale = size / math.max(fg_w, fg_h)
            w, h = fg_w * scale, fg_h * scale
        end
        local ox = x + (size - w) / 2
        local oy = y + (size - h) / 2
        draw_list:AddImage(texture, ImVec2.new(ox, oy), ImVec2.new(ox + w, oy + h),
            ImVec2.new(0, 0), ImVec2.new(1, 1), Paint.Color({ 1, 1, 1, 1 }))
    else
        -- Unresolved art still holds its slot, so the name stays hoverable.
        Paint.Rect(draw_list, x, y, size, size, { 0.26, 0.26, 0.31, 1 }, 2)
    end
    Paint.Border(draw_list, x, y, size, size, { 0, 0, 0, 0.75 }, 2, 1)

    if Paint.HitRegion(id, x, y, size, size) then
        local name = opts.get_icon_name and opts.get_icon_name(effect.icon_ref)
        Paint.Tooltip(name or "unknown")
    end
end

-- The effect strip, right aligned and filling toward the left. Returns the x of
-- the leftmost icon drawn, so a caller can keep its text clear of them.
local function DrawEffectStrip(draw_list, right_x, bottom_y, left_limit, member, config, opts)
    if not config.show_effects or member.effects == nil then
        return right_x
    end

    local size = config.effect_icon_size
    local slot_x = right_x - size
    local slot_y = bottom_y - size
    local shown = 0

    for index, effect in ipairs(member.effects) do
        if shown >= config.max_effects or slot_x < left_limit then
            break
        end
        DrawEffectIcon(draw_list, "fx" .. index, slot_x, slot_y, size, effect, opts)
        slot_x = slot_x - size - 2
        shown = shown + 1
    end

    if shown == 0 then
        return right_x
    end
    return slot_x + size + 2
end

-- The class badge's drawn size, its base size times the user's scale.
local function ClassIconSize(config)
    return math.floor(config.class_icon_size * (config.class_icon_scale or 1) + 0.5)
end

-- Name row with the class badge, and the level on the far right when there is
-- one. Returns where the name text started and how tall the row is.
local function DrawNameRow(draw_list, x, y, w, member, config, opts)
    local text_x = x
    if config.show_class_icons and member.class_id ~= nil then
        local size = ClassIconSize(config)
        if ClassIcon.Draw(draw_list, text_x, y, size, member.class_id, opts) then
            if Paint.HitRegion("class", text_x, y, size, size) then
                Paint.Tooltip(ClassIcon.GetName(member.class_id) or "")
            end
            text_x = text_x + size + 4
        end
    end

    -- The level owns the right end of the row, so the name gets whatever is
    -- left and is cut short rather than running under it.
    local level_label, level_w
    if config.show_level and member.level ~= nil and member.level > 0 then
        level_label = tostring(member.level)
        level_w = ImGui.CalcTextSize(level_label) + 6
    end

    local name = member.name or "?"
    local _, name_h = ImGui.CalcTextSize(name)
    local name_w = (x + w) - text_x - (level_w or 0)
    local shown = Truncate(name, name_w)
    if shown ~= nil then
        ShadowedText(draw_list, text_x, y, shown, config)
        -- The full name is worth a hover once it no longer fits.
        if shown ~= name and Paint.HitRegion("name", text_x, y, name_w, name_h) then
            Paint.Tooltip(name)
        end
    end

    if level_label ~= nil then
        ShadowedText(draw_list, x + w - (level_w - 6), y, level_label, config)
    end

    return text_x, math.max(name_h, config.show_class_icons and ClassIconSize(config) or 0)
end

-- Exact health when we have it, and the game's coarse percent when we do not,
-- which is all the game itself knows about someone who is not running the mod.
local function HealthFraction(member)
    if member.hp ~= nil and member.hp_max ~= nil and member.hp_max > 0 then
        return member.hp / member.hp_max
    end
    if member.hp_percent ~= nil then
        return member.hp_percent / 100
    end
    return nil
end

local function HealthLabel(config, member)
    if not config.show_health_text then
        return nil
    end
    local label
    if member.hp ~= nil and member.hp_max ~= nil and member.hp_max > 0 then
        label = FormatValue(member.hp, member.hp_max, config.health_as_percent)
    elseif member.hp_percent ~= nil then
        -- There is no maximum behind a borrowed percent, so there is no exact
        -- number to show even when the user asked for one.
        label = string.format("%d%%", math.floor(member.hp_percent + 0.5))
    end
    -- A caller with extra knowledge, like an estimated total, rides along here.
    if label ~= nil and member.health_label_suffix ~= nil then
        label = label .. " " .. member.health_label_suffix
    end
    return label
end

local function PowerLabel(config, member)
    if not config.show_power_text then
        return nil
    end
    return FormatValue(member.pwr, member.pwr_max, config.power_as_percent)
end

-- The health bar is the entry. Everything else sits on top of it, and the power
-- bar is a strip along the bottom.
local function DrawOverlayCell(draw_list, x, y, w, h, member, config, opts, now_ms, dead)
    local pad = 4
    local power_h = config.show_power_bar and config.power_bar_height or 0
    local health_h = h - power_h
    local rounding = config.cell_rounding
    local fraction = HealthFraction(member)

    -- Whatever the health bar does not cover shows through as the bar background.
    Paint.Rect(draw_list, x, y, w, health_h, config.color_bar_bg, rounding)

    if dead then
        Paint.Rect(draw_list, x, y, w, health_h, config.color_dead, rounding)
    elseif fraction ~= nil then
        Paint.Bar(draw_list, x, y, w, health_h, fraction,
            HealthColor(config, fraction, member.class_id), rounding)
    else
        -- Shared nothing is not the same as at zero health, so it gets a flat fill
        -- rather than an empty bar.
        Paint.Rect(draw_list, x, y, w, health_h, config.color_no_data, rounding)
    end

    local _, row_h = DrawNameRow(draw_list, x + pad, y + 3, w - pad * 2, member, config, opts)

    -- Effects tuck into the bottom right of the health area, just above the
    -- power strip.
    local strip_left = DrawEffectStrip(draw_list, x + w - 3, y + health_h - 3,
        x + pad, member, config, opts)

    local label = dead and "DEAD" or HealthLabel(config, member)
    if label ~= nil then
        local text_w, text_h = ImGui.CalcTextSize(label)
        local text_y = y + 3 + row_h + 1

        -- The number gets its own row under the name, centered across the whole
        -- entry, so the effects never squeeze it out. Only when the entry is
        -- too short for that does it fall back to centering in whatever space
        -- the effects left beside them.
        local strip_top = (strip_left < x + w - 3) and (y + health_h - 3 - config.effect_icon_size)
            or (y + health_h)

        if text_y + text_h <= strip_top then
            ShadowedText(draw_list, x + (w - text_w) / 2, text_y, label, config)
        else
            local free_left = x + pad
            local free_w = (strip_left - 3) - free_left
            if text_w <= free_w then
                local fallback_y = math.max(text_y,
                    (y + 3 + row_h) + ((y + health_h - 2) - (y + 3 + row_h) - text_h) / 2)
                ShadowedText(draw_list, free_left + (free_w - text_w) / 2, fallback_y, label, config)
            end
        end
    end

    if power_h > 0 then
        local power_y = y + health_h
        Paint.Rect(draw_list, x, power_y, w, power_h, config.color_bar_bg, 0)
        if member.pwr ~= nil and member.pwr_max ~= nil and member.pwr_max > 0 then
            Paint.Bar(draw_list, x, power_y, w, power_h, member.pwr / member.pwr_max,
                config.color_power, 0)
            local power_label = PowerLabel(config, member)
            if power_label ~= nil then
                CenteredOnBar(draw_list, x, power_y, w, power_h, power_label, config)
            end
        end
    end
end

-- Health and power as two separate bars below the name.
local function DrawStackedCell(draw_list, x, y, w, h, member, config, opts, now_ms, dead)
    local pad = 4
    Paint.Rect(draw_list, x, y, w, h, config.color_background, config.cell_rounding)

    local _, row_h = DrawNameRow(draw_list, x + pad, y + 3, w - pad * 2, member, config, opts)

    -- The bars share a width so cells stay uniform, and are centered when the
    -- width is set narrower than the cell.
    local bar_w = math.min(config.bar_width, w - pad * 2)
    local bar_x = x + (w - bar_w) / 2
    local bar_y = y + 3 + row_h + 3
    local health_h = config.health_bar_height
    local fraction = HealthFraction(member)

    if dead then
        Paint.Rect(draw_list, bar_x, bar_y, bar_w, health_h, config.color_bar_bg, config.bar_rounding)
        Paint.Rect(draw_list, bar_x, bar_y, bar_w, health_h, config.color_dead, config.bar_rounding)
        CenteredOnBar(draw_list, bar_x, bar_y, bar_w, health_h, "DEAD", config)
    elseif fraction ~= nil then
        DrawBar(draw_list, bar_x, bar_y, bar_w, health_h, fraction,
            HealthColor(config, fraction, member.class_id), HealthLabel(config, member), config, opts)
    else
        Paint.Rect(draw_list, bar_x, bar_y, bar_w, health_h, config.color_no_data, config.bar_rounding)
    end

    if config.show_power_bar then
        local power_y = bar_y + health_h + 2
        local power_h = config.power_bar_height
        if member.pwr ~= nil and member.pwr_max ~= nil and member.pwr_max > 0 then
            DrawBar(draw_list, bar_x, power_y, bar_w, power_h, member.pwr / member.pwr_max,
                config.color_power, PowerLabel(config, member), config, opts)
        else
            Paint.Rect(draw_list, bar_x, power_y, bar_w, power_h,
                config.color_bar_bg, config.bar_rounding)
        end
    end

    DrawEffectStrip(draw_list, x + w - 3, y + h - 3, x + pad, member, config, opts)
end

-- How much the exp bar adds to a cell on each side. The bar owns that strip, so
-- it never covers the bars or their numbers.
local function ExpInsets(config)
    if not config.show_exp_bar then
        return 0, 0
    end
    local t = config.exp_bar_thickness
    local position = config.exp_bar_position
    if position == "left" or position == "right" then
        return t, 0
    end
    return 0, t
end

-- The pet row adds to every cell when pets are on, so the grid stays uniform.
-- When nobody in the roster has a pet the row is dropped entirely.
local function PetRowHeight(config, has_pet)
    if not config.show_pets or has_pet == false then
        return 0
    end
    -- The bar never goes shorter than its label, whatever the font.
    local _, text_h = ImGui.CalcTextSize("Ay")
    return math.max(config.pet_frame_height, text_h + 4) + 2
end

local function RosterHasPet(roster)
    for _, member in ipairs(roster) do
        if member.pet_hp_percent ~= nil
            or (member.pet_name ~= nil and member.pet_name ~= "") then
            return true
        end
    end
    return false
end

local function ExpText(config, member, needed, fraction)
    local mode = config.exp_text_mode
    if mode == "numbers" then
        return string.format("%d / %d", member.exp, needed)
    elseif mode == "percent" then
        return string.format("%.1f%%", fraction * 100)
    elseif mode == "both" then
        return string.format("%d / %d  (%.1f%%)", member.exp, needed, fraction * 100)
    end
    return nil
end

-- The experience bar in its own strip beside or above the cell content. Vertical
-- fills bottom to top, horizontal fills left to right and can carry the numbers
-- once it is thick enough. Hovering it shows the exact numbers either way.
local function DrawExpBar(draw_list, bx, by, bw, bh, vertical, member, config, opts)
    Paint.Rect(draw_list, bx, by, bw, bh, config.color_bar_bg, 0)

    if member.exp == nil then
        return
    end
    local needed = opts.get_exp_required and opts.get_exp_required(member.level)
    if needed == nil or needed <= 0 then
        return
    end

    local fraction = math.min(1, math.max(0, member.exp / needed))
    if vertical then
        local fill_h = math.max(1, bh * fraction)
        Paint.Rect(draw_list, bx, by + bh - fill_h, bw, fill_h, config.color_exp, 0)
    else
        Paint.Bar(draw_list, bx, by, bw, bh, fraction, config.color_exp, 0)
        local label = ExpText(config, member, needed, fraction)
        if label ~= nil then
            local _, text_h = ImGui.CalcTextSize(label)
            if text_h <= bh + 2 then
                CenteredOnBar(draw_list, bx, by, bw, bh, label, config)
            end
        end
    end

    if Paint.HitRegion("exp", bx, by, bw, bh) then
        Paint.Tooltip(string.format("Experience  %d / %d  (%.1f%%)",
            member.exp, needed, fraction * 100))
    end
end

-- The pet strip under the owner's cell. A name over a health fill, sized from
-- the percent, which is all the game knows about a pet.
local function DrawPetFrame(draw_list, x, y, w, h, member, config)
    if member.pet_hp_percent == nil and member.pet_name == nil then
        return
    end

    local indent = math.min(config.pet_frame_indent, w / 2)
    local px, pw = x + indent, w - indent
    local percent = member.pet_hp_percent
    local name = member.pet_name or "Pet"

    Paint.Rect(draw_list, px, y, pw, h, config.color_bar_bg, 2)
    if percent ~= nil and percent > 0 then
        Paint.Bar(draw_list, px, y, pw, h, percent / 100, config.color_pet, 2)
    end
    Paint.Border(draw_list, px, y, pw, h, { 0, 0, 0, 0.7 }, 2, 1)

    -- Name on the left and percent on the right, inside the bar the way the
    -- owner's name sits inside the cell. The percent keeps its room, so a long
    -- name is cut short rather than running under it.
    local pad_x = 4
    local _, text_h = ImGui.CalcTextSize(name)
    local text_y = y + (h - text_h) / 2

    local label, label_w
    if percent ~= nil then
        label = string.format("%d%%", percent)
        label_w = ImGui.CalcTextSize(label) + 6
    end

    Paint.PushClip(draw_list, px, y, pw, h)
    local shown = Truncate(name, pw - pad_x * 2 - (label_w or 0))
    if shown ~= nil then
        ShadowedText(draw_list, px + pad_x, text_y, shown, config)
    end
    if label ~= nil then
        ShadowedText(draw_list, px + pw - pad_x - (label_w - 6), text_y, label, config)
    end
    Paint.PopClip(draw_list)

    if Paint.HitRegion("pet", px, y, pw, h) then
        if percent ~= nil then
            Paint.Tooltip(string.format("%s\n%d%% health", name, percent))
        else
            Paint.Tooltip(name)
        end
    end
end

-- One member cell, at a screen position. The exp strip and the pet row sit
-- outside the content, so x and y are the top left of the whole footprint.
local function DrawCell(draw_list, x, y, member, config, opts, now_ms)
    local w, h = config.cell_width, config.cell_height
    local exp_w, exp_h = ExpInsets(config)
    local dead = member.status ~= nil and bit.band(member.status, STATUS_DEAD) ~= 0

    -- Where the content lands once the exp strip has claimed its edge.
    local cx, cy = x, y
    local position = config.exp_bar_position
    if config.show_exp_bar then
        if position == "left" then
            cx = x + exp_w
        elseif position == "top" then
            cy = y + exp_h
        end
    end

    if config.overlay_style then
        -- The health bar is the backing plate here, so no separate one is drawn.
        DrawOverlayCell(draw_list, cx, cy, w, h, member, config, opts, now_ms, dead)
    else
        DrawStackedCell(draw_list, cx, cy, w, h, member, config, opts, now_ms, dead)
    end

    if config.show_exp_bar then
        if position == "left" then
            DrawExpBar(draw_list, x, cy, exp_w, h, true, member, config, opts)
        elseif position == "right" then
            DrawExpBar(draw_list, cx + w, cy, exp_w, h, true, member, config, opts)
        elseif position == "top" then
            DrawExpBar(draw_list, cx, y, w, exp_h, false, member, config, opts)
        else
            DrawExpBar(draw_list, cx, cy + h, w, exp_h, false, member, config, opts)
        end
    end

    -- One border wraps the content and the exp strip together, so the strip
    -- reads as part of the cell rather than a stray line beside it.
    local border = config.color_border
    local thickness = 1
    if member.is_self then
        border, thickness = config.color_border_self, 2
    elseif member.is_leader then
        border, thickness = config.color_border_leader, 2
    elseif member.no_mod then
        -- Faded, so a pane the game is guessing at never reads as solid data.
        border = config.color_border_no_mod
    end
    Paint.Border(draw_list, x, y, w + exp_w, h + exp_h, border, config.cell_rounding, thickness)

    if config.show_pets then
        DrawPetFrame(draw_list, x, y + h + exp_h + 2, w + exp_w,
            PetRowHeight(config) - 2, member, config)
    end
end

-- How much of the configured grid a given number of members actually uses. The
-- grid is a ceiling on the shape, not a promise to reserve all of it, so a party
-- of four does not sit in a box sized for a sixty man party.
local function GridFor(config, count)
    local capacity = config.columns * config.rows
    count = math.max(1, math.min(count, capacity))

    if config.fill_down_columns then
        local rows = math.min(config.rows, count)
        return math.ceil(count / config.rows), rows
    end
    local columns = math.min(config.columns, count)
    return columns, math.ceil(count / config.columns)
end

--- Total size the frames will occupy, so a caller can size a window to fit.
--- @param count integer|nil How many members will be drawn. Defaults to a full grid.
--- @param has_pet boolean|nil False drops the pet row. Defaults to reserving it.
--- @return number width
--- @return number height
function PartyFrames.GetSize(config, count, has_pet)
    local columns, rows = GridFor(config, count or (config.columns * config.rows))
    local spacing = config.cell_spacing
    local pad = config.show_frame and config.frame_padding or 0
    local exp_w, exp_h = ExpInsets(config)
    local cell_w = config.cell_width + exp_w
    local cell_h = config.cell_height + exp_h + PetRowHeight(config, has_pet)

    return columns * (cell_w + spacing) + spacing + pad * 2,
           rows * (cell_h + spacing) + spacing + pad * 2
end

--- Draws the frames at the current cursor position.
--- @param roster table[] Member rows, as session.GetRoster returns them.
--- @param config table From DefaultConfig, with the user's changes applied.
--- @param opts table|nil get_icon, get_icon_name, get_class_icon, get_exp_required, now_ms.
function PartyFrames.Draw(roster, config, opts)
    opts = opts or {}
    local now_ms = opts.now_ms

    -- Before anything is measured, so a font change is already accounted for
    -- in this frame's sizes rather than the next one's.
    PartyFrames.FitToFont(config)

    local draw_list = ImGui.GetWindowDrawList()
    local origin_x, origin_y = ImGui.GetCursorScreenPos()
    local spacing = config.cell_spacing
    local capacity = config.columns * config.rows
    local has_pet = RosterHasPet(roster)
    local width, height = PartyFrames.GetSize(config, #roster, has_pet)

    -- The box around the whole thing, drawn first so every cell lands on top of it.
    local pad = 0
    if config.show_frame then
        pad = config.frame_padding
        Paint.Rect(draw_list, origin_x, origin_y, width, height,
            config.color_frame_bg, config.frame_rounding)
        Paint.Border(draw_list, origin_x, origin_y, width, height,
            config.color_frame_border, config.frame_rounding, 1)
    end

    local exp_w, exp_h = ExpInsets(config)
    local cell_w = config.cell_width + exp_w
    local cell_h = config.cell_height + exp_h + PetRowHeight(config, has_pet)

    for index, member in ipairs(roster) do
        if index > capacity then
            break -- the grid is full, the rest simply do not fit
        end

        local slot = index - 1
        local column, row
        if config.fill_down_columns then
            column = math.floor(slot / config.rows)
            row = slot % config.rows
        else
            row = math.floor(slot / config.columns)
            column = slot % config.columns
        end

        local x = origin_x + pad + spacing + column * (cell_w + spacing)
        local y = origin_y + pad + spacing + row * (cell_h + spacing)

        -- Each cell needs its own id scope, or every cell's hit regions collide
        -- and only the first cell is hoverable.
        ImGui.PushID(tostring(member.client_id or index))
        DrawCell(draw_list, x, y, member, config, opts, now_ms)
        ImGui.PopID()
    end

    -- The draw list does not move the caret, so reserve the space by hand,
    -- otherwise anything drawn afterwards lands on top of the frames.
    ImGui.SetCursorScreenPos(origin_x, origin_y)
    ImGui.Dummy(width, height)
end

--- The settings panel for the grid.
--- @param config table Edited in place.
--- @param opts table|nil Which sections apply to this frame:
---   single    one frame rather than a grid, so the grid layout controls are
---             dropped and the wording says frame instead of entry
---   no_exp    hide the experience bar section
---   no_pets   hide the pet section
---   no_effects hide the buffs and debuffs section
function PartyFrames.DrawSettings(config, opts)
    opts = opts or {}
    -- A single frame is a frame, only a grid has entries in it.
    local noun = opts.single and "Frame" or "Entry"
    local noun_lower = opts.single and "frame" or "entry"

    -- A slider bound to a size the auto fit also drives, so the two always
    -- agree on the range.
    local function SizeSlider(label, key)
        config[key] = ImGui.SliderInt(label, config[key], LIMITS[key][1], LIMITS[key][2])
    end

    ImGui.Text("Layout")
    config.auto_fit = ImGui.Checkbox("Grow to fit the font", config.auto_fit ~= false)
    ImGui.Text("Raising the font size grows these sizes to match. They are")
    ImGui.Text("ordinary settings afterwards, so anything can be pulled back")
    ImGui.Text("down and it stays there until the font changes again.")
    if not opts.single then
        config.columns = ImGui.SliderInt("Entries per row", config.columns, 1, 6)
        config.rows = ImGui.SliderInt("Entries per column", config.rows, 1, 6)
    end
    SizeSlider(noun .. " width", "cell_width")
    SizeSlider(noun .. " height", "cell_height")
    if not opts.single then
        config.cell_spacing = ImGui.SliderInt("Spacing", config.cell_spacing, 0, 12)
    end
    config.cell_rounding = ImGui.SliderInt("Corner rounding", config.cell_rounding, 0, 12)
    if not opts.single then
        config.fill_down_columns = ImGui.Checkbox("Fill down columns first", config.fill_down_columns)
    end

    ImGui.Separator()
    ImGui.Text("Style")
    config.overlay_style = ImGui.Checkbox("Overlay, health bar fills the " .. noun_lower,
        config.overlay_style)
    if config.overlay_style then
        ImGui.Text("The name and numbers sit on the health bar, with the power")
        ImGui.Text("bar as a strip along the bottom.")
    else
        ImGui.Text("Health and power are drawn as two separate bars below the name.")
    end

    ImGui.Separator()
    ImGui.Text("Surrounding box")
    config.show_frame = ImGui.Checkbox(
        opts.single and "Box around the frame" or "Box around the frames", config.show_frame)
    config.frame_padding = ImGui.SliderInt("Box padding", config.frame_padding, 0, 20)
    config.frame_rounding = ImGui.SliderInt("Box rounding", config.frame_rounding, 0, 12)

    ImGui.Separator()
    ImGui.Text("Bars")
    SizeSlider("Power bar height", "power_bar_height")
    config.bar_rounding = ImGui.SliderInt("Bar rounding", config.bar_rounding, 0, 8)
    ImGui.Text("Square bars keep the fill edges straight. The softer look comes")
    ImGui.Text("from the " .. noun_lower .. " corners rounding around them.")
    config.color_health_by_class = ImGui.Checkbox("Color health bars by class",
        config.color_health_by_class)

    if not config.overlay_style then
        -- In overlay the health bar is the cell, so these have nothing to act on.
        -- One width for both, otherwise the cells stop lining up with each other.
        SizeSlider("Bar width, both bars", "bar_width")
        SizeSlider("Health bar height", "health_bar_height")

        if config.bar_width > config.cell_width - 8 then
            ImGui.TextColored(1, 0.75, 0.35, 1,
                "The bars are wider than the " .. noun_lower .. ", so they are clipped.")
        end
    end

    ImGui.Separator()
    ImGui.Text("Numbers")
    config.show_level = ImGui.Checkbox("Level on the name row", config.show_level)
    config.show_health_text = ImGui.Checkbox("Show health numbers", config.show_health_text)
    config.health_as_percent = ImGui.Checkbox("Health as a percent", config.health_as_percent)
    config.show_power_bar = ImGui.Checkbox("Show the power bar", config.show_power_bar)
    config.show_power_text = ImGui.Checkbox("Show power numbers", config.show_power_text)
    config.power_as_percent = ImGui.Checkbox("Power as a percent", config.power_as_percent)

    ImGui.Separator()
    ImGui.Text("Class icons")
    config.show_class_icons = ImGui.Checkbox("Class icons", config.show_class_icons)
    SizeSlider("Class icon size", "class_icon_size")
    config.class_icon_scale = ImGui.SliderFloat("Class icon scale", config.class_icon_scale, 0.5, 3.0)

    if not opts.no_effects then
        ImGui.Separator()
        ImGui.Text("Buffs and debuffs")
        config.show_effects = ImGui.Checkbox("Your active effects on the frame", config.show_effects)
        -- The game itself holds at most 8 effects, the deserializer clamps there.
        config.max_effects = ImGui.SliderInt("Most effects to draw", config.max_effects, 1, 8)
        SizeSlider("Effect icon size", "effect_icon_size")
        ImGui.Text("Hover an icon for the effect's name. The client only knows your")
        ImGui.Text("own effects, so other frames never have any to show.")
    end

    if not opts.no_exp then
        ImGui.Separator()
        ImGui.Text("Experience")
        config.show_exp_bar = ImGui.Checkbox(
            opts.single and "Experience bar on the frame" or "Experience bar on the entries",
            config.show_exp_bar)
        if config.show_exp_bar then
            local positions = {
                { key = "left",   label = "Vertical, left edge" },
                { key = "right",  label = "Vertical, right edge" },
                { key = "top",    label = "Horizontal, above the health bar" },
                { key = "bottom", label = "Horizontal, under the power bar" },
            }
            for _, entry in ipairs(positions) do
                if ImGui.RadioButton(entry.label, config.exp_bar_position == entry.key) then
                    config.exp_bar_position = entry.key
                end
            end
            SizeSlider("Bar thickness", "exp_bar_thickness")
            ImGui.Text("The bar gets its own strip of the " .. noun_lower .. ", which grows")
            ImGui.Text("by the thickness rather than covering the other bars.")

            local horizontal = config.exp_bar_position == "top"
                or config.exp_bar_position == "bottom"
            if horizontal then
                ImGui.Text("Text on the bar")
                local modes = {
                    { key = "none",    label = "No text" },
                    { key = "numbers", label = "Current / needed" },
                    { key = "percent", label = "Percent" },
                    { key = "both",    label = "Both" },
                }
                for _, entry in ipairs(modes) do
                    if ImGui.RadioButton(entry.label, config.exp_text_mode == entry.key) then
                        config.exp_text_mode = entry.key
                    end
                end
                if config.exp_text_mode ~= "none" then
                    ImGui.Text("The text only fits once the bar is thick enough to hold it.")
                end
            end

            config.color_exp = ImGui.ColorEdit4("Experience color", config.color_exp)
            ImGui.Text("Hover the bar for the exact experience numbers.")
        end
    end

    if not opts.no_pets then
        ImGui.Separator()
        ImGui.Text("Pets")
        config.show_pets = ImGui.Checkbox(
            opts.single and "Pet frame under your own" or "Pet frames under their owners",
            config.show_pets)
        if config.show_pets then
            SizeSlider("Pet frame height", "pet_frame_height")
            config.pet_frame_indent = ImGui.SliderInt("Pet frame indent", config.pet_frame_indent, 0, 40)
            config.color_pet = ImGui.ColorEdit4("Pet health color", config.color_pet)
            ImGui.Text("A pet is a name and a health percent, which is everything the")
            ImGui.Text("game exposes about one.")
        end
    end

    ImGui.Separator()
    ImGui.Text("Colors")
    local swatches = {
        { key = "color_health",     label = "Health" },
        { key = "color_health_low", label = "Health when low" },
        { key = "color_power",      label = "Power" },
        { key = "color_bar_bg",     label = "Bar background" },
        { key = "color_background", label = noun .. " background" },
    }

    -- Who leads and who is running the mod only mean something across a
    -- roster. A single frame draws one border, the self one on your own frame
    -- and the plain one on the target, so only that is worth offering.
    if opts.single then
        swatches[#swatches + 1] = {
            key = opts.self_border and "color_border_self" or "color_border",
            label = "Border",
        }
    else
        swatches[#swatches + 1] = { key = "color_border",        label = "Border" }
        swatches[#swatches + 1] = { key = "color_border_self",   label = "Border, you" }
        swatches[#swatches + 1] = { key = "color_border_leader", label = "Border, leader" }
        swatches[#swatches + 1] = { key = "color_border_no_mod", label = "Border, no mod" }
    end

    for _, swatch in ipairs({
        { key = "color_frame_bg",     label = "Box background" },
        { key = "color_frame_border", label = "Box border" },
        { key = "color_dead",         label = "Dead" },
        { key = "color_text",         label = "Text" },
    }) do
        swatches[#swatches + 1] = swatch
    end

    for _, swatch in ipairs(swatches) do
        config[swatch.key] = ImGui.ColorEdit4(swatch.label, config[swatch.key])
    end
    if config.color_health_by_class then
        ImGui.Text("Health bars are using class colors, so the health color is unused.")
    end
end

return PartyFrames
