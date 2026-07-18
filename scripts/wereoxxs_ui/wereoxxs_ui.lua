--[[
    wereoxxs_ui.lua

    A modern replacement for the game's own UI.

    Modern ability bars with a casting bar, a player frame with buffs, a target
    frame, group panes, a compass, a damage meter, and a tabbed chat window with
    a deep scrollback.
]]

local Player      = require("frontiers_forge.player")
local EntityList  = require("frontiers_forge.entity_list")
local AbilityBar  = require("frontiers_forge.ability_bar")
local Effects     = require("frontiers_forge.effects")
local Combat      = require("frontiers_forge.combat")
local Chat        = require("frontiers_forge.chat")
local Group       = require("frontiers_forge.group")
local Input       = require("frontiers_forge.input")
local Icon        = require("frontiers_forge.icon")
local UI          = require("frontiers_forge.ui")
local Util        = require("frontiers_forge.util")

local Paint        = require("paint")
local ClassArt     = require("class_art")
local PartyFrames  = require("party_frames")
local TapeCompass = require("tape_compass")
local DamageMeter  = require("damage_meter")
local AbilityBars  = require("ability_bars")
local CastingBar   = require("casting_bar")
local ChatWindow   = require("chat_window")
local SoloMeter    = require("solo_meter")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- A ForgeScript body reruns every frame, so anything that must survive across
-- frames is kept in globals rather than locals.
bar_configs = bar_configs or {
    AbilityBars.DefaultBarConfig(0),
    AbilityBars.DefaultBarConfig(1),
    AbilityBars.DefaultBarConfig(2),
}
cast_config = cast_config or CastingBar.DefaultConfig()
-- The player frame stands alone, so it skips the surrounding grid box.
frame_config = frame_config or (function()
    local config = PartyFrames.DefaultConfig()
    config.show_frame = false
    return config
end)()
-- The target frame borrows the player frame's settings but is one plain health
-- bar, no power strip, no exp, no pets, no box.
target_frame_config = target_frame_config or setmetatable({
    show_frame = false,
    show_power_bar = false,
    show_exp_bar = false,
    show_pets = false,
}, { __index = frame_config })
-- Group rows carry a name and a health percent, so the group cells default
-- to just that, no exp bar, no pets.
group_frame_config = group_frame_config or (function()
    local config = PartyFrames.DefaultConfig()
    config.show_exp_bar = false
    config.show_pets = false
    config.columns = 1
    config.rows = 5
    config.fill_down_columns = true
    return config
end)()
compass_config = compass_config or TapeCompass.DefaultConfig()
meter_config = meter_config or DamageMeter.DefaultConfig()
chat_config = chat_config or ChatWindow.DefaultConfig()
chat_state = chat_state or ChatWindow.new()
solo_meter = solo_meter or SoloMeter.new()
gear_texture = gear_texture or nil
gear_tried = gear_tried or false

windows = windows or {
    bars = false,
    casting = false,
    player = false,
    target = false,
    group = false,
    compass = false,
    meter = false,
    chat = false,
    -- The game panels these replace, restored when the script goes.
    hide_ability_bars = false,
    hide_player_bars = false,
    hide_active_effects = false,
    hide_game_group = false,
    hide_pet_panel = false,
    hide_game_compass = false,
    hide_game_chat = false,
    hide_target_nameplate = false,
    -- An estimate of the target's real health under the target frame.
    target_hp_estimate = false,
}
game_ui_hidden = game_ui_hidden or {}

combat_totals = combat_totals or {
    damage_done = 0, damage_taken = 0, healing_done = 0, healing_taken = 0,
}

-- The last raw combat events, for the debug panel in the settings. Diagnosing
-- attribution needs the ids exactly as the hook recorded them.
combat_event_log = combat_event_log or {}
local EVENT_LOG_SIZE = 16

-- Cooldown countdowns per ability id. The game stores a whole lockout and never
-- counts it down, so the countdown runs off the rising edge here.
cooldown_running = cooldown_running or {}

-- Entities carry only a health percent, so the target's real health is
-- estimated from the damage dealt against how far the percent moved.
target_estimate = target_estimate or nil

active_cast = active_cast or nil
cast_preview_ms = cast_preview_ms or 0
-- The bars share one set of settings until the user splits them apart.
bars_split = bars_split or false
send_hook_tried = send_hook_tried or false
key_hook_next_try_ms = key_hook_next_try_ms or 0
initialized = initialized or false

-- Window layout editing while the settings panel is open. Windows snap to a
-- grid as they are dragged, and the drag shows the top left position.
grid_config = grid_config or { enabled = true, size = 10 }
settings_open_ms = settings_open_ms or 0

-- The fonts on offer, from the shared resources folder. Default is ImGui's own
-- built in font, which has no file and only sizes through the window scale.
local FONTS = {
    { name = "Default" },
    { name = "Cinzel", path = "fonts/Cinzel/static/Cinzel-Regular.ttf" },
    { name = "Libre Baskerville", path = "fonts/Libre_Baskerville/static/LibreBaskerville-Regular.ttf" },
    { name = "Merriweather Sans", path = "fonts/Merriweather_Sans/static/MerriweatherSans-Regular.ttf" },
}
local DEFAULT_FONT_SIZE = 13

local FONT_WINDOWS = {
    { key = "bars", label = "Ability bars" },
    { key = "casting", label = "Casting bar" },
    { key = "player", label = "Player frame" },
    { key = "target", label = "Target frame" },
    { key = "group", label = "Group frames" },
    { key = "compass", label = "Compass" },
    { key = "meter", label = "Damage meter" },
    { key = "chat", label = "Chat window" },
}

font_configs = font_configs or {}
for _, entry in ipairs(FONT_WINDOWS) do
    font_configs[entry.key] = font_configs[entry.key]
        or { font = "Default", size = DEFAULT_FONT_SIZE }
end

local function NowMs()
    return math.floor(ImGui.GetTime() * 1000)
end

--------------------------------------------------------------------------------
-- Sampling the game
--------------------------------------------------------------------------------

local function UpdateCombatTotals()
    if not Combat.IsHookInstalled() then
        return
    end
    for _, event in ipairs(Combat.PollEvents()) do
        combat_event_log[#combat_event_log + 1] = event
        while #combat_event_log > EVENT_LOG_SIZE do
            table.remove(combat_event_log, 1)
        end
        if event.outgoing or event.incoming or event.from_pet then
            local amount = math.abs(event.amount)
            local done = event.is_heal and "healing_done" or "damage_done"
            local taken = event.is_heal and "healing_taken" or "damage_taken"
            -- The pet's damage counts as the player's, by choice.
            if event.outgoing or event.from_pet then
                combat_totals[done] = combat_totals[done] + amount
                -- Damage landing on the current target feeds its health estimate.
                if not event.is_heal and target_estimate ~= nil
                    and event.defender_id == target_estimate.id then
                    target_estimate.damage = target_estimate.damage + amount
                end
            end
            if event.incoming then
                combat_totals[taken] = combat_totals[taken] + amount
            end
        end
    end
end

-- The remaining time on an ability, run down locally from the lockout's rising
-- edge, since the game itself never counts it down.
local function CooldownRemaining(ability, now_ms)
    local id = ability:GetId()
    if id == nil then
        return 0
    end

    local lockout = ability:GetCooldownLockoutMs() or 0
    if lockout <= 0 or not ability:IsOnCooldown() then
        cooldown_running[id] = nil
        return 0
    end

    local running = cooldown_running[id]
    if running == nil or running.lockout ~= lockout then
        running = { lockout = lockout, started_ms = now_ms }
        cooldown_running[id] = running

        -- A fresh lockout is also the signal that the ability was just used,
        -- which is what starts the casting bar.
        local cast_time = ability:GetCastTime() or 0
        if cast_time > 0 then
            local fg, fg_w, fg_h = Icon.GetTexture(ability:GetIconForegroundRef(),
                { trim_transparent = true, trim_color = true })
            local bg, bg_w, bg_h = Icon.GetTexture(ability:GetIconBackgroundRef(),
                { trim_transparent = true, trim_color = true })
            active_cast = {
                name = ability:GetName(),
                duration_ms = cast_time * 1000,
                started_ms = now_ms,
                fg = fg, fg_w = fg_w, fg_h = fg_h,
                bg = bg, bg_w = bg_w, bg_h = bg_h,
            }
        end
    end

    return math.max(0, lockout - (now_ms - running.started_ms))
end

-- One prepared slot row for the bars module.
local function BuildSlot(bar, index, selected, now_ms, config)
    local slot = { empty = true }
    local ability = AbilityBar.GetAbility(bar, index)
    local item = ability == nil and AbilityBar.GetItem(bar, index) or nil

    if ability ~= nil then
        slot.empty = false
        slot.name = ability:GetName()
        slot.fg, slot.fg_w, slot.fg_h = Icon.GetTexture(ability:GetIconForegroundRef(),
            { trim_transparent = true, trim_color = true })
        slot.bg, slot.bg_w, slot.bg_h = Icon.GetTexture(ability:GetIconBackgroundRef(),
            { trim_transparent = true, trim_color = true })
        slot.remaining_ms = CooldownRemaining(ability, now_ms)
        local cost = ability:GetPwrCost() or 0
        slot.tooltip = string.format("%s\n%s\nPower  %d",
            slot.name or "?", ability:GetDescription() or "", cost)
    elseif item ~= nil then
        slot.empty = false
        slot.name = item:GetName()
        -- The game's compact hotbar draws a fixed glyph per slot position, not
        -- the item's own art, so that is the default look here too.
        if config ~= nil and config.real_item_icons then
            slot.fg, slot.fg_w, slot.fg_h = Icon.GetTexture(item:GetIconRef(),
                { trim_transparent = true, trim_color = true })
        else
            local glyph_id = AbilityBar.GetSlotUITexId(index)
            if glyph_id ~= nil then
                slot.fg, slot.fg_w, slot.fg_h = Icon.GetUITexture(glyph_id)
            end
        end
        -- Item art fills the whole slot square rather than keeping the game's
        -- plate proportions.
        slot.stretch = true
        slot.remaining_ms = 0
        slot.tooltip = string.format("%s\n%s", slot.name or "?", item:GetDescription() or "")
    end

    slot.selected = selected
    return slot
end

--------------------------------------------------------------------------------
-- Windows
--------------------------------------------------------------------------------

local OVERLAY_FLAGS = ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoResize
    + ImGuiWindowFlags.NoScrollbar + ImGuiWindowFlags.NoScrollWithMouse
    + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground
    + ImGuiWindowFlags.NoFocusOnAppearing

local draw_opts = {
    get_icon = function(icon_ref)
        if icon_ref == nil or icon_ref == 0 then
            return nil
        end
        return Icon.GetTexture(icon_ref, { trim_transparent = true, trim_color = true })
    end,
    get_icon_name = function(icon_ref)
        return effect_names ~= nil and effect_names[icon_ref] or nil
    end,
    get_class_icon = function(class_id)
        return ClassArt.GetTexture(class_id)
    end,
    get_exp_required = function(level)
        return Util.GetExpRequiredForLevel(level)
    end,
    get_bearing = function(from, to)
        return Util.GetBearingToPoint(from, to)
    end,
}

effect_names = effect_names or {}

-- Grid snapping for our windows, active while the settings panel is open. Call
-- right after a window's Begin. While the focused window is dragged its
-- position locks to the grid and a tooltip shows the top left corner.
local function GridEdit(now_ms)
    if not grid_config.enabled or now_ms - settings_open_ms > 250 then
        return
    end
    if not (ImGui.IsWindowFocused() and ImGui.IsMouseDragging(0)) then
        return
    end
    local x, y = ImGui.GetWindowPos()
    local step = math.max(1, grid_config.size)
    local sx = math.floor(x / step + 0.5) * step
    local sy = math.floor(y / step + 0.5) * step
    if sx ~= x or sy ~= y then
        ImGui.SetWindowPos(sx, sy)
    end
    ImGui.SetTooltip(string.format("%d, %d", sx, sy))
end

-- Pushes a window's chosen font for everything drawn until the matching pop.
-- The host caches fonts per file and size, so pushing every frame is cheap.
local function PushWindowFont(key)
    local fc = font_configs[key]
    for _, entry in ipairs(FONTS) do
        if entry.name == fc.font and entry.path ~= nil then
            ImGui.PushFont(UiForge.LoadFont(entry.path, fc.size))
            return true
        end
    end
    return false
end

local function PopWindowFont(pushed)
    if pushed then
        ImGui.PopFont()
    end
end

-- The window scale that sizes the default font, which has no file to reload
-- at another size. A file backed font is already loaded at its size.
local function WindowFontScale(key)
    local fc = font_configs[key]
    if fc.font == "Default" then
        return fc.size / DEFAULT_FONT_SIZE
    end
    return 1
end

-- Call inside the window, right after Begin.
local function ApplyWindowFont(key)
    ImGui.SetWindowFontScale(WindowFontScale(key))
end

local function DrawAbilityBarWindows(now_ms)
    local selected_bar = AbilityBar.GetSelectedBarIndex()
    local selected_slot = AbilityBar.GetSelectedSlotIndex(selected_bar or 0)
    local pushed = PushWindowFont("bars")

    for bar = 0, 2 do
        local config = bar_configs[bar + 1]
        if config.enabled then
            local count = AbilityBar.GetSlotCount(bar) or 0
            if count > 0 then
                local slots = {}
                for i = 0, count - 1 do
                    slots[#slots + 1] = BuildSlot(bar, i,
                        bar == selected_bar and i == selected_slot, now_ms, config)
                end
                local name_x, name_y, name
                if ImGui.Begin("wereoxxs bar " .. (bar + 1), true, OVERLAY_FLAGS) then
                    GridEdit(now_ms)
                    ApplyWindowFont("bars")
                    name_x, name_y, name = AbilityBars.Draw(slots, config, bar == selected_bar)
                end
                ImGui.End()

                -- The name box is its own window so it never clips against the
                -- bar window's edges, wherever the offsets put it.
                if name ~= nil then
                    AbilityBars.DrawNameWindow("wereoxxs bar name " .. (bar + 1), name,
                        name_x + config.name_offset_x, name_y + config.name_offset_y, config,
                        WindowFontScale("bars"))
                end
            end
        end
    end
    PopWindowFont(pushed)
end

local function DrawCastingBar(now_ms)
    -- While the settings panel is open the bar previews a looping five second
    -- cast, so it can be placed and styled without casting anything.
    local cast = active_cast
    if now_ms - cast_preview_ms < 250 then
        cast = CastingBar.PreviewCast(now_ms)
    elseif cast == nil then
        return
    end

    local pushed = PushWindowFont("casting")
    if ImGui.Begin("wereoxxs casting bar", true, OVERLAY_FLAGS) then
        GridEdit(now_ms)
        ApplyWindowFont("casting")
        if CastingBar.Draw(cast, cast_config, now_ms) and cast == active_cast then
            active_cast = nil
        end
    end
    ImGui.End()
    PopWindowFont(pushed)
end

-- The local player as a one cell roster, with buffs and debuffs riding the
-- effect strip in the frame's corner, each named on hover.
local function BuildPlayerRow()
    local hp, hp_max = Player.GetCurrentHp() or 0, Player.GetMaxHp() or 0

    local effects = {}
    for _, effect in Effects.All() do
        if effect.icon_ref ~= nil and effect.icon_ref ~= 0 then
            effects[#effects + 1] = { icon_ref = effect.icon_ref }
            effect_names[effect.icon_ref] = effect.name
        end
    end

    local pet_name, pet_hp
    local pet_id = Player.GetPetEntityId()
    if pet_id ~= nil then
        local pet = EntityList.GetEntityById(pet_id)
        if pet ~= nil then
            pet_name = pet:GetName()
            -- Entity health is a 0 to 1 fraction, the frames speak whole percent.
            pet_hp = math.floor((pet:GetHealthPercent() or 0) * 100 + 0.5)
        end
    end

    return {
        name = Player.GetName() or "?",
        class_id = Player.GetClassId(),
        level = Player.GetLevel(),
        hp = hp, hp_max = hp_max,
        pwr = Player.GetCurrentPwr() or 0,
        pwr_max = Player.GetMaxPwr() or 0,
        exp = Player.GetExp(),
        status = (hp == 0 and hp_max > 0) and 0x02 or 0,
        effects = effects,
        pet_name = pet_name,
        pet_hp_percent = pet_hp,
        is_self = true,
    }
end

local function DrawPlayerFrame(now_ms)
    local pushed = PushWindowFont("player")
    if ImGui.Begin("wereoxxs player frame", true, OVERLAY_FLAGS) then
        GridEdit(now_ms)
        ApplyWindowFont("player")
        draw_opts.now_ms = now_ms
        PartyFrames.Draw({ BuildPlayerRow() }, frame_config, draw_opts)
    end
    ImGui.End()
    PopWindowFont(pushed)
end

local function DrawTargetFrame(now_ms)
    local target_id = Player.GetTargetEntityId()
    if target_id == nil or target_id == 0 then
        return
    end
    local target = EntityList.GetEntityById(target_id)
    if target == nil then
        return
    end

    local row = {
        name = target:GetName(),
        level = target:GetLevel(),
        -- Entity health is a 0 to 1 fraction, the frames speak whole percent.
        hp_percent = (target:GetHealthPercent() or 0) * 100,
        no_mod = true,
    }
    if row.name == nil or row.name == "" then
        return
    end

    -- The estimate rests on a baseline percent and the damage dealt since. A
    -- new target starts fresh, and a heal or regen moves the baseline up so
    -- earlier damage cannot drag the estimate low.
    local percent = row.hp_percent
    if target_estimate == nil or target_estimate.id ~= target_id then
        target_estimate = { id = target_id, base_percent = percent,
            last_percent = percent, damage = 0 }
    elseif percent > target_estimate.last_percent then
        target_estimate.base_percent = percent
        target_estimate.damage = 0
        target_estimate.last_percent = percent
    elseif percent < target_estimate.last_percent then
        local dropped = target_estimate.base_percent - percent
        if dropped > 0 and target_estimate.damage > 0 then
            target_estimate.max_hp = target_estimate.damage * 100 / dropped
        end
        target_estimate.last_percent = percent
    end
    if windows.target_hp_estimate and target_estimate.max_hp ~= nil then
        row.health_label_suffix = string.format("(~%d / %d)",
            math.floor(target_estimate.max_hp * percent / 100 + 0.5),
            math.floor(target_estimate.max_hp + 0.5))
    end

    local pushed = PushWindowFont("target")
    if ImGui.Begin("wereoxxs target frame", true, OVERLAY_FLAGS) then
        GridEdit(now_ms)
        ApplyWindowFont("target")
        local x, y = ImGui.GetCursorScreenPos()
        draw_opts.now_ms = now_ms
        PartyFrames.Draw({ row }, target_frame_config, draw_opts)

        -- The game's own disposition face in the bottom right corner of the
        -- bar, so hostile reads at a glance.
        local face_id = UI.GetDispositionFaceTexId(target:GetDisposition())
        if face_id ~= nil then
            local face, fw, fh = Icon.GetUITexture(face_id)
            if face ~= nil and fw ~= nil and fh ~= nil and fh > 0 then
                local w, h = PartyFrames.GetSize(target_frame_config, 1)
                local size = 16
                local face_w = size * (fw / fh)
                local draw_list = ImGui.GetWindowDrawList()
                draw_list:AddImage(face,
                    ImVec2.new(x + w - face_w - 4, y + h - size - 4),
                    ImVec2.new(x + w - 4, y + h - 4),
                    ImVec2.new(0, 0), ImVec2.new(1, 1),
                    Paint.Color({ 1, 1, 1, 1 }))
            end
        end
    end
    ImGui.End()
    PopWindowFont(pushed)
end

-- One row per active member of the in game group. Health is the game's coarse
-- percent, so the cells draw in the percent only style. The game's member
-- array includes the local player, who already has a dedicated frame, so that
-- entry is filtered out by entity id.
local function BuildGroupRoster()
    if not Group.IsInGroup() then
        return {}
    end
    local player_id = Player.GetEntityId()
    local roster = {}
    for _, member in Group.Members() do
        if member:IsActive() and member:GetEntityId() ~= player_id then
            local coords = member:GetCoordinates()
            roster[#roster + 1] = {
                name = member:GetName(),
                hp_percent = member:GetHealthPercent(),
                x = coords and coords.x, y = coords and coords.y, z = coords and coords.z,
                no_mod = true,
            }
        end
    end
    return roster
end

local function DrawGroupFrames(now_ms)
    local roster = BuildGroupRoster()
    if #roster == 0 then
        return
    end
    local pushed = PushWindowFont("group")
    if ImGui.Begin("wereoxxs group frames", true, OVERLAY_FLAGS) then
        GridEdit(now_ms)
        ApplyWindowFont("group")
        draw_opts.now_ms = now_ms
        PartyFrames.Draw(roster, group_frame_config, draw_opts)
    end
    ImGui.End()
    PopWindowFont(pushed)
end

local function DrawCompass()
    local heading = Util.GetCompassDegrees() or 0
    local origin = Player.GetCoordinates()

    local pushed = PushWindowFont("compass")
    if ImGui.Begin("wereoxxs compass", true, OVERLAY_FLAGS) then
        GridEdit(NowMs())
        ApplyWindowFont("compass")
        TapeCompass.Draw(heading, origin, BuildGroupRoster(), compass_config, draw_opts)
    end
    ImGui.End()
    PopWindowFont(pushed)
end

local METER_FLAGS = ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoFocusOnAppearing

local meter_data = {}

-- The gear the meter hangs its options off, from the shared resources folder.
-- Without it the meter falls back to drawing a plain gray block.
local function GetGear()
    if gear_texture == nil and not gear_tried then
        gear_tried = true
        gear_texture = Paint.ValidTexture(
            UiForge.LoadTexture(UiForge.resources_path .. "\\gear-icon.png"))
    end
    return gear_texture
end

local function DrawMeter(now_ms)
    solo_meter:SetIdentity(Player.GetName(), Player.GetClassId())
    solo_meter:Update(now_ms, combat_totals, nil)

    local encounter = solo_meter:GetEncounter()
    local totals = solo_meter:GetTotals()
    local overall = solo_meter:GetOverall()
    local roster = {
        {
            client_id = 1,
            name = Player.GetName() or "You",
            class_id = Player.GetClassId(),
            damage_done = totals.damage_done, damage_taken = totals.damage_taken,
            healing_done = totals.healing_done, healing_taken = totals.healing_taken,
            all_damage_done = overall.damage_done, all_damage_taken = overall.damage_taken,
            all_healing_done = overall.healing_done, all_healing_taken = overall.healing_taken,
        },
    }

    ImGui.SetNextWindowSize(320, 160, ImGuiCond.FirstUseEver)
    local pushed = PushWindowFont("meter")
    if ImGui.Begin("wereoxxs damage meter", true, METER_FLAGS) then
        GridEdit(now_ms)
        ApplyWindowFont("meter")
        meter_data.roster = roster
        meter_data.duration_ms = encounter.duration_ms
        meter_data.history = solo_meter:GetHistory()
        meter_data.session_roster = DamageMeter.OverallRoster(roster)
        meter_data.fighting_ms = DamageMeter.FightingMs(meter_data.history, encounter)

        draw_opts.now_ms = now_ms
        draw_opts.active = encounter.active
        draw_opts.gear = GetGear()

        local action = DamageMeter.DrawWindow(meter_data, meter_config, draw_opts)
        if action == "clear" then
            solo_meter:ClearHistory()
        end
    end
    ImGui.End()
    PopWindowFont(pushed)
end

local function PumpChat()
    -- Every new game message lands in the scrollback, whatever tab is up.
    for _ = 1, 8 do
        local text, msg_type = Chat.GetNextMessage()
        if text == nil or text == "" then
            break
        end
        ChatWindow.Add(chat_state, chat_config, text, Chat.GetMessageTypeString(msg_type))
    end
end

-- Enter is swallowed before the game sees it, so the game's typing window never
-- opens, and the press lands in the chat window's own input field instead.
local function PumpEnterKey(now_ms, paused)
    if not Input.IsKeyHookInstalled() then
        -- A failed install can fall back to a memory scan, so retry on a slow
        -- clock rather than every frame.
        if now_ms < key_hook_next_try_ms then
            return
        end
        key_hook_next_try_ms = now_ms + 2000
        if not Input.InstallKeyHook() then
            return
        end
    end
    -- Enter stays with the game while paused, since the chat window is not up.
    local capture = windows.chat and not paused
    Input.SetKeySuppressed(Input.Key.Enter, capture)
    for _, event in ipairs(Input.PollKeyEvents()) do
        if capture and event.key == Input.Key.Enter and event.is_down then
            chat_state.focus_requested = true
        end
    end
end

local CHAT_FLAGS = ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoBackground

local function DrawChat()
    PumpChat()
    ImGui.SetNextWindowSize(420, 240, ImGuiCond.FirstUseEver)
    local pushed = PushWindowFont("chat")
    if ImGui.Begin("wereoxxs chat", true, CHAT_FLAGS) then
        GridEdit(NowMs())
        ApplyWindowFont("chat")
        ChatWindow.Draw(chat_state, chat_config, {
            send = function(text, partner)
                Chat.SendMessage(0, text, partner)
            end,
            -- The message list is a child window, which keeps its own scale.
            font_scale = WindowFontScale("chat"),
        })
    end
    ImGui.End()
    PopWindowFont(pushed)
end

--------------------------------------------------------------------------------
-- The game's own UI
--------------------------------------------------------------------------------

-- The health, power, and both exp bars hide and return together.
local function DisablePlayerBars()
    local hp = UI.DisableHealthBar()
    local pwr = UI.DisablePowerBar()
    local exp = UI.DisableExperienceBars()
    return hp and pwr and exp
end

local function EnablePlayerBars()
    local hp = UI.EnableHealthBar()
    local pwr = UI.EnablePowerBar()
    local exp = UI.EnableExperienceBars()
    return hp and pwr and exp
end

-- show_while_paused panels come back up under the pause menu, so the game
-- stays usable there.
local GAME_PANELS = {
    { key = "hide_ability_bars", disable = UI.DisableAbilityBar, enable = UI.EnableAbilityBar },
    { key = "hide_player_bars", disable = DisablePlayerBars, enable = EnablePlayerBars },
    { key = "hide_active_effects", disable = UI.DisableActiveEffectsDisplay,
        enable = UI.EnableActiveEffectsDisplay },
    { key = "hide_game_group", disable = UI.DisableGroupDisplay, enable = UI.EnableGroupDisplay },
    { key = "hide_pet_panel", disable = UI.DisablePetPanel, enable = UI.EnablePetPanel },
    { key = "hide_game_compass", disable = UI.DisableCompass, enable = UI.EnableCompass },
    { key = "hide_game_chat", disable = UI.DisableChatWindow, enable = UI.EnableChatWindow,
        show_while_paused = true },
    { key = "hide_target_nameplate", disable = UI.DisableTargetNameplate,
        enable = UI.EnableTargetNameplate, show_while_paused = true },
}

-- The tracked state only flips once the write lands, so a toggle set before the
-- game UI exists retries every frame until it takes. A panel we never hid is
-- never written to, so the game keeps managing its own visibility.
local function ApplyGameUiState(paused)
    for _, panel in ipairs(GAME_PANELS) do
        local desired = windows[panel.key]
        if desired and paused and panel.show_while_paused then
            desired = false
        end
        if desired ~= (game_ui_hidden[panel.key] == true) then
            local applied
            if desired then
                applied = panel.disable()
            else
                applied = panel.enable()
            end
            if applied then
                game_ui_hidden[panel.key] = desired
            end
        end
    end
end

local function RestoreGameUi()
    for _, panel in ipairs(GAME_PANELS) do
        if game_ui_hidden[panel.key] then
            windows[panel.key] = false
            panel.enable()
        end
    end
    game_ui_hidden = {}
end

--------------------------------------------------------------------------------
-- Settings and persistence
--------------------------------------------------------------------------------

local function Settings()
    settings_open_ms = NowMs()
    ImGui.Text("Everything here is client side only. Nothing is sent anywhere.")
    ImGui.Separator()

    if ImGui.TreeNode("Window layout") then
        grid_config.enabled = ImGui.Checkbox("Snap windows to a grid while settings are open",
            grid_config.enabled)
        grid_config.size = ImGui.SliderInt("Grid spacing", grid_config.size, 1, 64)
        ImGui.Text("Dragging a window shows its top left position, and it locks")
        ImGui.Text("to the grid. Spacing 1 places windows freely.")
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Fonts") then
        for _, entry in ipairs(FONT_WINDOWS) do
            local fc = font_configs[entry.key]
            if ImGui.BeginCombo(entry.label, fc.font) then
                for _, font in ipairs(FONTS) do
                    if ImGui.Selectable(font.name, font.name == fc.font) then
                        fc.font = font.name
                    end
                end
                ImGui.EndCombo()
            end
            fc.size = ImGui.SliderInt(entry.label .. " size", fc.size, 8, 32)
        end
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Windows") then
        windows.bars = ImGui.Checkbox("Ability bars", windows.bars)
        windows.casting = ImGui.Checkbox("Casting bar", windows.casting)
        windows.player = ImGui.Checkbox("Player frame", windows.player)
        windows.target = ImGui.Checkbox("Target frame", windows.target)
        windows.group = ImGui.Checkbox("Group frames", windows.group)
        windows.compass = ImGui.Checkbox("Compass", windows.compass)
        windows.meter = ImGui.Checkbox("Damage meter", windows.meter)
        windows.chat = ImGui.Checkbox("Chat window", windows.chat)
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Hide the game's own UI") then
        windows.hide_ability_bars = ImGui.Checkbox("Hide the game's ability bars",
            windows.hide_ability_bars)
        windows.hide_player_bars = ImGui.Checkbox("Hide the game's health, power, and exp bars",
            windows.hide_player_bars)
        windows.hide_active_effects = ImGui.Checkbox("Hide the game's active effects display (buffs/debuffs)",
            windows.hide_active_effects)
        windows.hide_game_group = ImGui.Checkbox("Hide the game's group panel",
            windows.hide_game_group)
        windows.hide_pet_panel = ImGui.Checkbox("Hide the game's pet panel",
            windows.hide_pet_panel)
        windows.hide_game_compass = ImGui.Checkbox("Hide the game's compass",
            windows.hide_game_compass)
        windows.hide_game_chat = ImGui.Checkbox("Hide the game's chat window",
            windows.hide_game_chat)
        if windows.hide_game_chat then
            ImGui.Text("The game's chat comes back while the pause menu is up.")
        end
        windows.hide_target_nameplate = ImGui.Checkbox("Hide the game's target nameplate",
            windows.hide_target_nameplate)
        if windows.hide_target_nameplate then
            ImGui.Text("The nameplate comes back while the pause menu is up.")
        end
        ImGui.Text("Everything goes back up when the script is turned off.")
        ImGui.TreePop()
    end

    bars_split = ImGui.Checkbox("Each ability bar keeps its own settings", bars_split)
    if bars_split then
        for bar = 1, 3 do
            if ImGui.TreeNode(string.format("Ability bar %d", bar)) then
                AbilityBars.DrawSettings(bar_configs[bar], bar == 3)
                ImGui.TreePop()
            end
        end
    else
        if ImGui.TreeNode("Ability bars") then
            bar_configs[1].enabled = ImGui.Checkbox("Show bar 1", bar_configs[1].enabled)
            bar_configs[2].enabled = ImGui.Checkbox("Show bar 2", bar_configs[2].enabled)
            bar_configs[3].enabled = ImGui.Checkbox("Show bar 3", bar_configs[3].enabled)
            AbilityBars.DrawSettings(bar_configs[1], true, true)
            ImGui.TreePop()
        end
        -- One bar's settings drive all three, each bar keeps only its own toggle.
        for bar = 2, 3 do
            AbilityBars.CopyConfig(bar_configs[1], bar_configs[bar])
        end
    end

    if ImGui.TreeNode("Casting bar") then
        cast_preview_ms = NowMs()
        CastingBar.DrawSettings(cast_config)
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Player and target frames") then
        PartyFrames.DrawSettings(frame_config)

        ImGui.Separator()
        ImGui.Text("Target frame")
        windows.target_hp_estimate = ImGui.Checkbox(
            "Estimate the target's health next to its percent", windows.target_hp_estimate)
        if windows.target_hp_estimate then
            ImGui.TextColored(0.95, 0.35, 0.35, 1.0,
                "Best used solo. Damage from other players is invisible to the")
            ImGui.TextColored(0.95, 0.35, 0.35, 1.0,
                "client, so on shared kills the estimate reads high.")
        end
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Group frames") then
        PartyFrames.DrawSettings(group_frame_config)
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Compass") then
        TapeCompass.DrawSettings(compass_config)
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Damage meter") then
        DamageMeter.DrawSettings(meter_config)
        ImGui.TreePop()
    end

    -- Everything needed to diagnose event attribution: what the hook resolved,
    -- which ids the game reports for the player and the pet, and the raw events
    -- exactly as they came off the wire.
    if ImGui.TreeNode("Combat debug") then
        local info = Combat.GetHookInfo()
        ImGui.Text(string.format("hook installed: %s", tostring(info.installed)))
        ImGui.Text(string.format("patch site: %s  holds: %s",
            info.patch_site and string.format("0x%08X", info.patch_site) or "-",
            info.site_word and string.format("0x%08X", info.site_word) or "-"))
        ImGui.Text(string.format("restore word: %s  chain target: %s",
            info.restore_word and string.format("0x%08X", info.restore_word) or "-",
            info.chain_target and string.format("0x%08X", info.chain_target) or "none"))
        ImGui.Text(string.format("player id: %s  pet id (+0x2BE50): %s",
            info.player_id and string.format("0x%X", info.player_id) or "-",
            info.pet_id and string.format("0x%X", info.pet_id) or "none"))
        local pet = info.pet_id and EntityList.GetEntityById(info.pet_id) or nil
        ImGui.Text(string.format("pet entity: %s",
            pet and (pet:GetName() or "?") or "not in entity list"))
        ImGui.Text(string.format("events: %d  dropped: %d", info.event_count, info.dropped))

        ImGui.Separator()
        ImGui.Text("Raw events, newest last")
        for _, event in ipairs(combat_event_log) do
            ImGui.Text(string.format("#%d atk 0x%X def 0x%X clr %s amt %d%s%s%s%s",
                event.seq, event.attacker_id, event.defender_id,
                event.color and string.format("0x%X", event.color) or "-",
                event.amount,
                event.outgoing and " OUT" or "", event.incoming and " IN" or "",
                event.from_pet and " PET" or "", event.to_pet and " TOPET" or ""))
        end

        ImGui.Separator()
        -- The foreign patch's cave, printed so it can be copied out of a
        -- screenshot and disassembled offline.
        if ImGui.TreeNode("Foreign cave code") then
            local rows = Combat.ReadForeignCave()
            if rows == nil then
                ImGui.Text("not chained onto a foreign hook")
            else
                for _, row in ipairs(rows) do
                    ImGui.Text(string.format("0x%08X: 0x%08X", row.addr, row.word))
                end
            end
            ImGui.TreePop()
        end
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Chat") then
        ChatWindow.DrawSettings(chat_config)
        ImGui.TreePop()
    end
end

local function Save()
    return {
        windows = windows,
        bars_split = bars_split,
        grid_config = grid_config,
        font_configs = font_configs,
        bar_configs = bar_configs,
        cast_config = cast_config,
        frame_config = frame_config,
        group_frame_config = group_frame_config,
        compass_config = compass_config,
        meter_config = meter_config,
        chat_config = chat_config,
    }
end

local function Load(saved)
    if type(saved) ~= "table" then
        return
    end
    local function merge(into, from)
        if type(from) ~= "table" then return end
        for key, value in pairs(from) do
            if into[key] ~= nil and type(value) == type(into[key]) and type(value) ~= "table" then
                into[key] = value
            elseif type(value) == "table" and type(into[key]) == "table" then
                merge(into[key], value)
            end
        end
    end
    merge(windows, saved.windows)
    if type(saved.bars_split) == "boolean" then
        bars_split = saved.bars_split
    end
    merge(grid_config, saved.grid_config)
    merge(font_configs, saved.font_configs)
    for bar = 1, 3 do
        merge(bar_configs[bar], saved.bar_configs and saved.bar_configs[bar])
    end
    merge(cast_config, saved.cast_config)
    merge(frame_config, saved.frame_config)
    merge(group_frame_config, saved.group_frame_config)
    merge(compass_config, saved.compass_config)
    merge(meter_config, saved.meter_config)
    merge(chat_config, saved.chat_config)
end

local function Cleanup()
    RestoreGameUi()
    if Combat.IsHookInstalled() then
        Combat.UninstallHook()
    end
    if Chat.IsSendHookInstalled() then
        Chat.UninstallSendHook()
    end
    if Input.IsKeyHookInstalled() then
        Input.UninstallKeyHook()
    end
    Icon.ReleaseAll()
    if gear_texture ~= nil then
        UiForge.ReleaseTexture(gear_texture)
        gear_texture = nil
        gear_tried = false
    end
    initialized = false
    send_hook_tried = false
    key_hook_next_try_ms = 0
end

if not initialized then
    UiForge.RegisterCallback(UiForge.CallbackType.Settings, Settings)
    UiForge.RegisterCallback(UiForge.CallbackType.Save, Save)
    UiForge.RegisterCallback(UiForge.CallbackType.Load, Load)
    UiForge.RegisterCallback(UiForge.CallbackType.DisableScript, Cleanup)
    UiForge.RegisterCallback(UiForge.CallbackType.OnEject, Cleanup)
    initialized = true
end

--------------------------------------------------------------------------------
-- Per frame
--------------------------------------------------------------------------------

if Util.IsInGame() ~= 0 then
    -- The hooks feed the meter and the chat send, so bring them up once in game.
    if not Combat.IsHookInstalled() then
        Combat.InstallHook()
    end
    if not send_hook_tried and not Chat.IsSendHookInstalled() then
        send_hook_tried = true
        Chat.InstallSendHook()
    end

    local now_ms = NowMs()
    local paused = Util.IsStartMenuOpen() ~= 0

    ApplyGameUiState(paused)
    UpdateCombatTotals()
    PumpEnterKey(now_ms, paused)

    if not paused then
        if windows.bars then DrawAbilityBarWindows(now_ms) end
        if windows.casting then DrawCastingBar(now_ms) end
        if windows.player then DrawPlayerFrame(now_ms) end
        if windows.target then DrawTargetFrame(now_ms) end
        if windows.group then DrawGroupFrames(now_ms) end
        if windows.compass then DrawCompass() end
        if windows.meter then DrawMeter(now_ms) end
        if windows.chat then DrawChat() end
    end
end
