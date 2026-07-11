--[[
    ability_bars.lua

    A modern hotbar renderer for wereoxxs_ui.

    Draws the game's three ability bars as its own slots. Bars 1 and 2 are five
    slots laid out horizontally or vertically, bar 3 is four slots laid out
    horizontally, vertically, as a square, or as a diamond. Each slot draws the
    ability's plate and art the way the game's own hotbar does, dims while on
    cooldown, and the selected slot of the selected bar carries a highlight
    border and its ability's name in a floating box beside it.

    A slot row looks like:
        {
            empty = boolean,
            fg, fg_w, fg_h = foreground texture and size,
            bg, bg_w, bg_h = background plate texture and size,
            selected = boolean,
            remaining_ms = cooldown left, 0 when ready,
            name = string|nil,
            tooltip = string|nil,
        }
]]

local Paint = require("paint")

local AbilityBars = {}

--- Everything the user can change, per bar. One flat table each so the whole
--- set can be handed to the profile save and load callbacks.
--- @param bar_index integer 0 to 2
function AbilityBars.DefaultBarConfig(bar_index)
    return {
        enabled = true,
        -- The orientation every bar has, "horizontal" or "vertical".
        layout = "horizontal",
        -- The four slot bar's extra shapes, "none" to use the orientation,
        -- or "square" (2 by 2) or "diamond".
        shape = "none",
        slot_size = 34,
        spacing = 4,
        rounding = 4,

        -- The floating box carrying the selected ability's name. Offsets are
        -- from the selected slot's top left corner.
        show_selected_name = true,
        name_offset_x = 0,
        name_offset_y = -26,

        show_cooldown_numbers = true,
        -- Item slots draw the game's fixed per slot glyph by default, this
        -- swaps in the item's own inventory art instead.
        real_item_icons = false,

        color_empty          = { 0.08, 0.08, 0.10, 0.55 },
        color_slot_border    = { 0.00, 0.00, 0.00, 0.80 },
        color_selected       = { 1.00, 1.00, 1.00, 1.00 },
        selected_thickness   = 2,
        color_cooldown_dim   = { 0.00, 0.00, 0.00, 0.62 },
        color_name_bg        = { 0.07, 0.07, 0.10, 0.92 },
        color_name_border    = { 0.45, 0.42, 0.30, 0.90 },
        color_name_text      = { 1.00, 0.95, 0.75, 1.00 },
    }
end

--- Copies every setting from one bar config onto another, except the per bar
--- enabled toggle, for the shared settings mode.
function AbilityBars.CopyConfig(src, dst)
    for key, value in pairs(src) do
        if key ~= "enabled" then
            if type(value) == "table" then
                dst[key] = { value[1], value[2], value[3], value[4] }
            else
                dst[key] = value
            end
        end
    end
end

-- The shape overrides the orientation on the four slot bar.
local function EffectiveLayout(config, count)
    if count == 4 then
        if config.shape ~= nil and config.shape ~= "none" then
            return config.shape
        end
        if config.layout == "square" or config.layout == "diamond" then
            return config.layout
        end
    end
    if config.layout == "vertical" then
        return "vertical"
    end
    return "horizontal"
end

-- Slot positions for a layout, in units of (slot + spacing).
local function SlotOffsets(layout, count)
    local offsets = {}
    if layout == "vertical" then
        for i = 1, count do offsets[i] = { 0, i - 1 } end
    elseif layout == "square" and count == 4 then
        offsets = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }
    elseif layout == "diamond" and count == 4 then
        offsets = { { 1, 0 }, { 0, 1 }, { 2, 1 }, { 1, 2 } }
    else
        for i = 1, count do offsets[i] = { i - 1, 0 } end
    end
    return offsets
end

--- Total size a bar will occupy, so the caller can size a window to fit.
--- @return number width
--- @return number height
function AbilityBars.GetSize(config, count)
    local step = config.slot_size + config.spacing
    local max_x, max_y = 0, 0
    for _, offset in ipairs(SlotOffsets(EffectiveLayout(config, count), count)) do
        max_x = math.max(max_x, offset[1])
        max_y = math.max(max_y, offset[2])
    end
    return max_x * step + config.slot_size, max_y * step + config.slot_size
end

-- One slot. The plate fills the square and the art on top keeps the game's own
-- proportions.
local function DrawSlot(draw_list, id, x, y, slot, config)
    local size = config.slot_size
    local white = Paint.Color({ 1, 1, 1, 1 })
    local uv0, uv1 = ImVec2.new(0, 0), ImVec2.new(1, 1)

    if slot.empty or (slot.fg == nil and slot.bg == nil) then
        Paint.Rect(draw_list, x, y, size, size, config.color_empty, config.rounding)
    else
        if slot.bg ~= nil then
            draw_list:AddImage(slot.bg, ImVec2.new(x, y), ImVec2.new(x + size, y + size),
                uv0, uv1, white)
        end
        if slot.fg ~= nil then
            local w, h = size, size
            if not slot.stretch and slot.fg_w and slot.fg_h and slot.fg_w > 0 and slot.fg_h > 0 then
                if slot.bg ~= nil and slot.bg_w and slot.bg_h and slot.bg_w > 0 and slot.bg_h > 0 then
                    w, h = size * (slot.fg_w / slot.bg_w), size * (slot.fg_h / slot.bg_h)
                else
                    local scale = size / math.max(slot.fg_w, slot.fg_h)
                    w, h = slot.fg_w * scale, slot.fg_h * scale
                end
            end
            local ox, oy = x + (size - w) / 2, y + (size - h) / 2
            draw_list:AddImage(slot.fg, ImVec2.new(ox, oy), ImVec2.new(ox + w, oy + h),
                uv0, uv1, white)
        end
    end

    local remaining = slot.remaining_ms or 0
    if remaining > 0 then
        Paint.Rect(draw_list, x, y, size, size, config.color_cooldown_dim, config.rounding)
        if config.show_cooldown_numbers then
            local label = tostring(math.ceil(remaining / 1000))
            local text_w, text_h = ImGui.CalcTextSize(label)
            Paint.Text(draw_list, x + (size - text_w) / 2 + 1, y + (size - text_h) / 2 + 1,
                label, { 0, 0, 0, 0.9 })
            Paint.Text(draw_list, x + (size - text_w) / 2, y + (size - text_h) / 2,
                label, { 1, 1, 1, 1 })
        end
    end

    if slot.selected then
        Paint.Border(draw_list, x - 1, y - 1, size + 2, size + 2,
            config.color_selected, config.rounding, config.selected_thickness)
    else
        Paint.Border(draw_list, x, y, size, size, config.color_slot_border, config.rounding, 1)
    end

    if slot.tooltip ~= nil and Paint.HitRegion(id, x, y, size, size) then
        Paint.Tooltip(slot.tooltip)
    end
end

--- Draws one bar at the current cursor position.
--- @param slots table[] Prepared slot rows, see the file header.
--- @param config table From DefaultBarConfig, with the user's changes applied.
--- @param bar_is_selected boolean Whether this bar is the game's selected bar.
--- @return number|nil x Screen x of the selected slot, when its name should show.
--- @return number|nil y Screen y of the selected slot.
--- @return string|nil name The selected ability's name.
function AbilityBars.Draw(slots, config, bar_is_selected)
    local draw_list = ImGui.GetWindowDrawList()
    local x, y = ImGui.GetCursorScreenPos()
    local step = config.slot_size + config.spacing
    local offsets = SlotOffsets(EffectiveLayout(config, #slots), #slots)
    local selected_x, selected_y, selected_name

    for index, slot in ipairs(slots) do
        local offset = offsets[index]
        local sx = x + offset[1] * step
        local sy = y + offset[2] * step
        DrawSlot(draw_list, "slot" .. index, sx, sy, slot, config)
        if slot.selected and bar_is_selected and not slot.empty then
            selected_x, selected_y, selected_name = sx, sy, slot.name
        end
    end

    local w, h = AbilityBars.GetSize(config, #slots)
    ImGui.SetCursorScreenPos(x, y)
    ImGui.Dummy(w, h)

    -- The name box lives in its own window so it never clips against the bar's
    -- edges. The caller places it from these.
    if config.show_selected_name and selected_name ~= nil and selected_name ~= "" then
        return selected_x, selected_y, selected_name
    end
end

--- The floating name box, drawn as its own window so it can sit anywhere
--- around the bar without being clipped by it.
--- @param id string A window name unique to the bar.
--- @param name string The ability name to show.
--- @param x number Screen position of the box's top left.
--- @param y number Screen position of the box's top left.
--- @param config table From DefaultBarConfig.
function AbilityBars.DrawNameWindow(id, name, x, y, config, font_scale)
    ImGui.SetNextWindowPos(x, y)
    local flags = ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoResize
        + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground
        + ImGuiWindowFlags.NoFocusOnAppearing + (ImGuiWindowFlags.NoMove or 0)
        + (ImGuiWindowFlags.NoInputs or 0)
    if ImGui.Begin(id, true, flags) then
        -- Sized inside the window so the caller's font scale is in effect.
        ImGui.SetWindowFontScale(font_scale or 1)
        local text_w, text_h = ImGui.CalcTextSize(name)
        local w, h = text_w + 14, text_h + 6
        local draw_list = ImGui.GetWindowDrawList()
        local bx, by = ImGui.GetCursorScreenPos()
        Paint.Rect(draw_list, bx, by, w, h, config.color_name_bg, h / 2)
        Paint.Border(draw_list, bx, by, w, h, config.color_name_border, h / 2, 1)
        Paint.Text(draw_list, bx + 7, by + 3, name, config.color_name_text)
        ImGui.Dummy(w, h)
    end
    ImGui.End()
end

--- The settings panel for one bar.
--- @param config table Edited in place.
--- @param four_slots boolean Whether this is the four slot bar with the extra layouts.
function AbilityBars.DrawSettings(config, four_slots, hide_enabled)
    if not hide_enabled then
        config.enabled = ImGui.Checkbox("Show this bar", config.enabled)
    end

    -- Older saves stored square and diamond in the orientation itself.
    if config.layout == "square" or config.layout == "diamond" then
        config.shape = config.layout
        config.layout = "horizontal"
    end

    ImGui.Text("Layout")
    for _, entry in ipairs({
        { key = "horizontal", label = "Horizontal" },
        { key = "vertical",   label = "Vertical" },
    }) do
        if ImGui.RadioButton(entry.label, config.layout == entry.key) then
            config.layout = entry.key
        end
    end

    if four_slots then
        ImGui.Text("Additional four slot bar layouts")
        for _, entry in ipairs({
            { key = "none",    label = "Use the orientation above" },
            { key = "square",  label = "Square, 2 by 2" },
            { key = "diamond", label = "Diamond" },
        }) do
            if ImGui.RadioButton(entry.label, (config.shape or "none") == entry.key) then
                config.shape = entry.key
            end
        end
    end

    config.slot_size = ImGui.SliderInt("Slot size", config.slot_size, 20, 72)
    config.spacing = ImGui.SliderInt("Spacing", config.spacing, 0, 16)
    config.rounding = ImGui.SliderInt("Corner rounding", config.rounding, 0, 10)
    config.show_cooldown_numbers = ImGui.Checkbox("Seconds over a cooling slot",
        config.show_cooldown_numbers)
    config.real_item_icons = ImGui.Checkbox("Item slots show the item's own icon",
        config.real_item_icons)

    ImGui.Separator()
    ImGui.Text("Selected ability")
    config.selected_thickness = ImGui.SliderInt("Highlight thickness",
        config.selected_thickness, 1, 5)
    config.color_selected = ImGui.ColorEdit4("Highlight color", config.color_selected)
    config.show_selected_name = ImGui.Checkbox("Name box beside the selected slot",
        config.show_selected_name)
    if config.show_selected_name then
        config.name_offset_x = ImGui.SliderInt("Name box offset X", config.name_offset_x, -200, 200)
        config.name_offset_y = ImGui.SliderInt("Name box offset Y", config.name_offset_y, -200, 200)
        ImGui.Text("The name only shows on the selected slot of the selected bar.")
    end

    ImGui.Separator()
    ImGui.Text("Colors")
    config.color_empty = ImGui.ColorEdit4("Empty slot", config.color_empty)
    config.color_slot_border = ImGui.ColorEdit4("Slot border", config.color_slot_border)
    config.color_cooldown_dim = ImGui.ColorEdit4("Cooldown dim", config.color_cooldown_dim)
    config.color_name_bg = ImGui.ColorEdit4("Name box background", config.color_name_bg)
    config.color_name_border = ImGui.ColorEdit4("Name box border", config.color_name_border)
    config.color_name_text = ImGui.ColorEdit4("Name box text", config.color_name_text)
end

return AbilityBars
