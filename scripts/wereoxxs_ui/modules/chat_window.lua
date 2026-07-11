--[[
    chat_window.lua

    A tabbed chat window for wereoxxs_ui with a deep scrollback.

    The game's own chat keeps around 32 lines. This window keeps thousands. An
    All tab shows every message, prefixed with its time and its type, one tab
    per chat type shows just that type, and every tell conversation gets a tab
    of its own named after the other person. Messages are color coded by type,
    and the colors are configurable.
]]

local Paint = require("paint")

local ChatWindow = {}

--- Everything the user can change.
function ChatWindow.DefaultConfig()
    return {
        max_messages = 2000,
        show_timestamps = true,

        -- The translucent panel behind the log and the input line. The window
        -- itself has no background, so this is all the box there is.
        color_background = { 0.00, 0.00, 0.00, 0.55 },

        -- The tabs above the log, idle, hovered, and selected.
        color_tab          = { 0.09, 0.09, 0.09, 0.85 },
        color_tab_hovered  = { 0.24, 0.24, 0.24, 0.90 },
        color_tab_selected = { 0.16, 0.16, 0.16, 0.95 },

        color_say   = { 1.00, 1.00, 1.00, 1.00 },
        color_shout = { 0.35, 0.90, 0.35, 1.00 },
        color_tell  = { 0.80, 0.45, 0.95, 1.00 },
        color_party = { 0.40, 0.75, 1.00, 1.00 },
        color_guild = { 0.95, 0.75, 0.30, 1.00 },
        color_other = { 0.70, 0.70, 0.70, 1.00 },
    }
end

--- A fresh window state. Kept apart from the config so the scrollback is never
--- written into a profile.
function ChatWindow.new()
    return {
        messages = {},      -- every message, oldest first
        partners = {},      -- tell partners, in the order they first appeared
        partner_seen = {},
        types_seen = {},    -- which chat types have appeared, for the tabs
        type_order = {},
        input = "",
        stick_to_bottom = true,
        -- Set by the top layer when Enter is pressed outside the window, so the
        -- next drawn input line grabs the keyboard.
        focus_requested = false,
    }
end

local function ColorFor(config, type_name)
    if type_name == "Say" then return config.color_say end
    if type_name == "Shout" then return config.color_shout end
    if type_name == "Tell" then return config.color_tell end
    if type_name == "Party" then return config.color_party end
    if type_name == "Guild" then return config.color_guild end
    return config.color_other
end

-- Who the other side of a tell is, from the message text itself. The game
-- renders tells as "Name tells you, ..." and "You tell Name, ...".
local function TellPartner(text)
    local partner = text:match("^(%S+) tells you")
    if partner == nil then
        partner = text:match("^[Yy]ou tell (%S+)")
    end
    if partner ~= nil then
        partner = partner:gsub("[,:%.]+$", "")
    end
    return partner
end

--- Feeds one message in.
--- @param state table From ChatWindow.new.
--- @param config table From DefaultConfig.
--- @param text string The full message text as the game rendered it.
--- @param type_name string "Say", "Shout", "Tell", "Party", "Guild", or anything else.
function ChatWindow.Add(state, config, text, type_name)
    local message = {
        text = text,
        type_name = type_name,
        time = os.date("%H:%M"),
    }

    if type_name == "Tell" then
        local partner = TellPartner(text)
        if partner ~= nil then
            message.partner = partner
            if not state.partner_seen[partner] then
                state.partner_seen[partner] = true
                state.partners[#state.partners + 1] = partner
            end
        end
    end

    if not state.types_seen[type_name] then
        state.types_seen[type_name] = true
        state.type_order[#state.type_order + 1] = type_name
    end

    state.messages[#state.messages + 1] = message

    -- The scrollback is deep. Dropping from the front in one
    -- splice keeps the trim cheap even at the cap.
    local cap = config.max_messages
    local over = #state.messages - cap
    if over > 0 then
        local kept = {}
        for i = over + 1, #state.messages do
            kept[#kept + 1] = state.messages[i]
        end
        state.messages = kept
    end
end

-- One message line, colored by type. The All tab carries the type prefix,
-- the filtered tabs do not need it.
local function DrawMessage(message, config, with_prefix)
    local color = ColorFor(config, message.type_name)
    local line = message.text
    if with_prefix then
        line = string.format("[%s] %s", message.type_name, line)
    end
    if config.show_timestamps then
        line = string.format("%s %s", message.time, line)
    end
    ImGui.PushStyleColor(ImGuiCol.Text, color[1], color[2], color[3], color[4])
    ImGui.TextWrapped(line)
    ImGui.PopStyleColor(1)
end

-- The scrolling message region for one tab. Sticks to the bottom while the
-- user is at the bottom, and stays put while they are reading back.
local function DrawMessageList(state, config, opts, filter, with_prefix, input_h)
    ImGui.BeginChild("messages", 0, -input_h)
    -- A child window keeps its own font scale, so the parent's is reapplied.
    ImGui.SetWindowFontScale(opts.font_scale or 1)
    for _, message in ipairs(state.messages) do
        if filter == nil or filter(message) then
            DrawMessage(message, config, with_prefix)
        end
    end
    if ImGui.GetScrollY() >= ImGui.GetScrollMaxY() - 4 then
        ImGui.SetScrollHereY(1.0)
    end
    ImGui.EndChild()
end

-- The input line under the messages, filling the whole row and drawn without a
-- frame so it blends into the panel. Enter sends, and a tell tab routes the
-- send back to that conversation on its own.
local function DrawInputLine(state, opts, partner)
    local hint = partner ~= nil and ("Tell " .. partner) or "Press Enter to chat"
    local enter_flag = (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0

    if state.focus_requested then
        ImGui.SetKeyboardFocusHere()
        state.focus_requested = false
    end

    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 1, 1, 1, 0.06)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 1, 1, 1, 0.10)
    ImGui.SetNextItemWidth(-1)
    local text, entered = ImGui.InputTextWithHint("##chat_input", hint, state.input, enter_flag)
    ImGui.PopStyleColor(3)

    if text ~= nil then
        state.input = text
    end
    if entered and state.input ~= "" and opts.send ~= nil then
        opts.send(state.input, partner)
        state.input = ""
    end
end

-- The body of one tab, a translucent panel behind the log and the input line
-- together, so the pair reads as one box while the tabs stay bare.
local function DrawTabBody(state, config, opts, partner, filter, with_prefix)
    local draw_list = ImGui.GetWindowDrawList()
    local x, y = ImGui.GetCursorScreenPos()
    local avail_w, avail_h = ImGui.GetContentRegionAvail()
    Paint.Rect(draw_list, x, y, avail_w, avail_h, config.color_background, 4)

    local input_h = ImGui.GetFrameHeight() + 4
    DrawMessageList(state, config, opts, filter, with_prefix, input_h)
    DrawInputLine(state, opts, partner)
end

--- Draws the tab bar, the messages, and the input line. Call inside a window.
--- @param state table From ChatWindow.new.
--- @param config table From DefaultConfig, with the user's changes applied.
--- @param opts table send(text, partner_or_nil) called when the user submits.
local function PushTabColors(config)
    local tab, hovered, selected =
        config.color_tab, config.color_tab_hovered, config.color_tab_selected
    ImGui.PushStyleColor(ImGuiCol.Tab, tab[1], tab[2], tab[3], tab[4])
    ImGui.PushStyleColor(ImGuiCol.TabDimmed, tab[1], tab[2], tab[3], tab[4])
    ImGui.PushStyleColor(ImGuiCol.TabHovered,
        hovered[1], hovered[2], hovered[3], hovered[4])
    ImGui.PushStyleColor(ImGuiCol.TabSelected,
        selected[1], selected[2], selected[3], selected[4])
    ImGui.PushStyleColor(ImGuiCol.TabDimmedSelected,
        selected[1], selected[2], selected[3], selected[4])
    return 5
end

function ChatWindow.Draw(state, config, opts)
    opts = opts or {}
    local pushed = PushTabColors(config)
    if not ImGui.BeginTabBar("chat_tabs") then
        ImGui.PopStyleColor(pushed)
        return
    end

    if ImGui.BeginTabItem("All") then
        DrawTabBody(state, config, opts, nil, nil, true)
        ImGui.EndTabItem()
    end

    for _, type_name in ipairs(state.type_order) do
        -- Tells live in their per conversation tabs instead.
        if type_name ~= "Tell" and ImGui.BeginTabItem(type_name) then
            DrawTabBody(state, config, opts, nil, function(message)
                return message.type_name == type_name
            end, false)
            ImGui.EndTabItem()
        end
    end

    for _, partner in ipairs(state.partners) do
        if ImGui.BeginTabItem(partner) then
            DrawTabBody(state, config, opts, partner, function(message)
                return message.partner == partner
            end, false)
            ImGui.EndTabItem()
        end
    end

    ImGui.EndTabBar()
    ImGui.PopStyleColor(pushed)
end

--- The settings panel.
--- @param config table Edited in place.
function ChatWindow.DrawSettings(config)
    config.max_messages = ImGui.SliderInt("Scrollback size", config.max_messages, 100, 10000)
    config.show_timestamps = ImGui.Checkbox("Timestamps", config.show_timestamps)
    config.color_background = ImGui.ColorEdit4("Panel background", config.color_background)
    config.color_tab = ImGui.ColorEdit4("Tab", config.color_tab)
    config.color_tab_hovered = ImGui.ColorEdit4("Tab hovered", config.color_tab_hovered)
    config.color_tab_selected = ImGui.ColorEdit4("Tab selected", config.color_tab_selected)
    ImGui.Text("Press Enter to start typing, and Enter again to send.")

    ImGui.Separator()
    ImGui.Text("Message colors")
    config.color_say = ImGui.ColorEdit4("Say", config.color_say)
    config.color_shout = ImGui.ColorEdit4("Shout", config.color_shout)
    config.color_tell = ImGui.ColorEdit4("Tell", config.color_tell)
    config.color_party = ImGui.ColorEdit4("Party", config.color_party)
    config.color_guild = ImGui.ColorEdit4("Guild", config.color_guild)
    config.color_other = ImGui.ColorEdit4("Everything else", config.color_other)
end

return ChatWindow
