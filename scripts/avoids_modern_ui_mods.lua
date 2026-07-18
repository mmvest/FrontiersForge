--[[
================================================================================
 Modern UI Mods
================================================================================
 Author - Avoids
================================================================================

A single combined pack containing every "modern" UI script: Health Bar, Mana Bar, Experience
Bars, Ability Bar, Chat Log, Group Frames, Pet Frame, Quest Log, Effects
(Buffs/Debuffs), and Target Level. The World Map now lives in its own package
at scripts\world_map. Each one has its own Enable checkbox and full settings panel,
all inside this one file's Settings tab.

ARCHITECTURE NOTES (read this before touching the structure below):

1. Each mod's original code is wrapped in its own `do...end` block. This matters because every
   mod independently defines identically-named local functions (Settings, Render, Initialize,
   OnDisable, Update -- literally every mod has all of these). Without separate scoping, the
   LAST mod's definitions would silently shadow every earlier mod's same-named functions,
   breaking everything before it. Each `do...end` block keeps its own functions private to
   itself.

2. Each mod exposes a small table -- { Update, Settings, OnDisable, Save?, Load? } -- into a
   shared global `ModPack` table (e.g. `ModPack.HealthBar = {...}`) right before its `do...end`
   block closes. This is how the master dispatcher below reaches into each mod without needing
   to know its internals.

3. UiForge only allows ONE callback registration per type (Settings, DisableScript, Save, Load)
   for an entire script file. Previously each mod was its own separate file with its own
   callbacks; now there's exactly one master Settings/DisableScript/Save/Load callback here,
   which fans out to whichever mods need it.

4. Each mod's own global state table (e.g. modern_health_bar_state) and settings file path are
   COMPLETELY UNCHANGED from when it was a standalone script. This means upgrading from the
   separate scripts to this combined pack preserves every existing setting automatically --
   nothing needs to be reconfigured.

5. Per-mod enable/disable is a NEW concept this pack introduces (UiForge itself has no notion of
   "sub-scripts" within one file). It's tracked in modern_ui_mods_state.mod_enabled and persisted
   to its own small settings file. Turning a mod off calls its OnDisable() immediately --
   restoring whatever native UI it was hiding -- the same way UiForge used to do automatically
   when you unchecked an individual script in the old per-file setup.

6. Like every script in this project, the WHOLE file re-executes every frame (UiForge has no
   separate "per-frame" callback type -- the file's own top-level execution IS the per-frame
   hook). All the "or {}" state-table idioms and "if not already done" guards exist because of
   this, exactly as in the original standalone scripts.
================================================================================
]]

modern_ui_mods_state = modern_ui_mods_state or {
    initialized          = false,
    callbacks_registered = false,

    settings_file_loaded = false,
    _settings_snapshot   = "",

    mod_enabled = {
        HealthBar    = true,
        ManaBar      = true,
        ExpBars      = true,
        AbilityBar   = true,
        ChatLog      = true,
        GroupFrames  = true,
        PetFrame     = true,
        QuestLog     = true,
        Effects      = true,
        TargetLevel  = true,
    },
}

-- Display/settings-panel order. Also the canonical list of valid mod keys.
local MOD_ORDER = {
    "HealthBar", "ManaBar", "ExpBars", "AbilityBar", "ChatLog",
    "GroupFrames", "PetFrame", "QuestLog", "Effects", "TargetLevel",
}

ModPack = ModPack or {}

-- ============================================================================
-- MOD: Health Bar
-- ============================================================================
do
    local UI = require("frontiers_forge.ui")                -- Access UI elements
    local Player = require("frontiers_forge.player")        -- Access Player attributes and functions
    local Util = require("frontiers_forge.util")            -- Access Utility functions

    -- Creating a long, specific table name so that I (hopefully) avoid naming collisions
    modern_health_bar_state = modern_health_bar_state or {
        window_flags                = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.NoTitleBar,
        initialized                 = false,
        callbacks_registered         = false,
        native_toggle_confirmed      = false, -- v0.1.1: tracks whether the native-bar disable/enable write has actually landed yet

        -- Settings persistence (so your sizing/colors survive a relaunch)
        settings_file_loaded        = false,
        _settings_snapshot          = "",

        -- Bar dimensions
        bar_width                   = 200,
        bar_height                  = 24,
        bar_scale                   = 1,

        -- Colors
        background_color            = {0.08, 0.08, 0.08, 0.85},   -- near-black, semi-transparent
        fill_color                  = {0.80, 0.05, 0.05, 1.0},     -- red
        use_low_health_color        = true,
        fill_color_low              = {0.95, 0.55, 0.05, 1.0},     -- amber, shown below the threshold
        low_health_threshold        = 0.25,

        -- Border
        show_border                 = true,
        border_color                = {0, 0, 0, 1},
        border_thickness            = 1.5,
        corner_rounding              = 4,

        -- Text overlay
        show_text                   = true,
        text_color                  = {1, 1, 1, 1},
        text_format                 = "current_max",   -- "current_max" -> "138/158"  |  "percent" -> "87%"
        font_scale                  = 1.0,             -- text size, relative to the default UI font
        bold_text                   = false,           -- simulates bold by drawing the text with a slight offset stroke

        disable_default_health_bar  = true,
    }

    local function Trim(str)
        if str == nil then return "" end
        return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseBool(value)
        value = Trim(value):lower()
        return (value == "true" or value == "1" or value == "yes" or value == "on")
    end

    --[[
    Settings persistence

    Saves/loads the settings below to "resources\\retro_health_hearts\\health_bar_settings.cfg"
    as simple "key=value" lines, so the bar's size/colors/format are remembered across launches
    instead of resetting to defaults every time.
    ]]
    local PERSISTED_SETTINGS = {
        { key = "bar_width",              type = "number" },
        { key = "bar_height",             type = "number" },
        { key = "bar_scale",              type = "number" },
        { key = "background_color",       type = "color" },
        { key = "fill_color",             type = "color" },
        { key = "use_low_health_color",   type = "bool" },
        { key = "fill_color_low",         type = "color" },
        { key = "low_health_threshold",   type = "number" },
        { key = "show_border",            type = "bool" },
        { key = "border_color",           type = "color" },
        { key = "border_thickness",       type = "number" },
        { key = "corner_rounding",        type = "number" },
        { key = "show_text",              type = "bool" },
        { key = "text_color",             type = "color" },
        { key = "text_format",            type = "string" },
        { key = "font_scale",             type = "number" },
        { key = "bold_text",              type = "bool" },
        { key = "disable_default_health_bar", type = "bool" },
    }

    local function GetHealthBarSettingsFilePath()
        return UiForge.resources_path .. "\\retro_health_hearts\\health_bar_settings.cfg"
    end

    local function SerializeSettingsValue(value, value_type)
        if value_type == "color" then
            return table.concat({ tostring(value[1]), tostring(value[2]), tostring(value[3]), tostring(value[4]) }, ",")
        elseif value_type == "bool" then
            return value and "true" or "false"
        else -- "number" or "string" (text_format has no special characters, so no CSV escaping needed here)
            return tostring(value)
        end
    end

    local function ParseSettingsValue(raw_value, value_type)
        if value_type == "color" then
            local components = {}
            for field in tostring(raw_value):gmatch("[^,]+") do
                components[#components + 1] = tonumber(field)
            end
            if #components == 4 and components[1] and components[2] and components[3] and components[4] then
                return components
            end
            return nil
        elseif value_type == "bool" then
            return ParseBool(raw_value)
        elseif value_type == "string" then
            return Trim(raw_value)
        else -- "number"
            return tonumber(raw_value)
        end
    end

    local function BuildSettingsSnapshot()
        local lines = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            lines[#lines + 1] = def.key .. "=" .. SerializeSettingsValue(modern_health_bar_state[def.key], def.type)
        end
        return table.concat(lines, "\n")
    end

    local function WriteSettingsSnapshotToFile(snapshot)
        local path = GetHealthBarSettingsFilePath()
        local file = io.open(path, "w")
        if file == nil then
            return false
        end

        file:write("# health_bar_settings.cfg -- auto-generated. Delete this file to reset the health bar to defaults.\n")
        file:write(snapshot)
        file:write("\n")
        file:close()
        return true
    end

    -- Call this after any setting-editing widget runs. It only touches disk if a value actually changed.
    local function SaveHealthBarSettingsIfChanged()
        local snapshot = BuildSettingsSnapshot()
        if snapshot ~= modern_health_bar_state._settings_snapshot then
            if WriteSettingsSnapshotToFile(snapshot) then
                modern_health_bar_state._settings_snapshot = snapshot
            end
        end
    end

    local function LoadHealthBarSettingsFromFile()
        local path = GetHealthBarSettingsFilePath()
        local file = io.open(path, "r")
        if file == nil then
            return false -- No saved settings yet; keep the defaults.
        end

        local defs_by_key = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            defs_by_key[def.key] = def.type
        end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
                if key ~= nil and defs_by_key[key] ~= nil then
                    local parsed = ParseSettingsValue(raw_value, defs_by_key[key])
                    if parsed ~= nil then
                        modern_health_bar_state[key] = parsed
                    end
                end
            end
        end

        file:close()
        modern_health_bar_state._settings_snapshot = BuildSettingsSnapshot()
        return true
    end

    local function TryLoadHealthBarSettingsOnce()
        if modern_health_bar_state.settings_file_loaded == true then return end
        LoadHealthBarSettingsFromFile()
        modern_health_bar_state.settings_file_loaded = true
    end

    local function ToggleDefaultHealthBar()
        if modern_health_bar_state.disable_default_health_bar == true then
            return UI.DisableHealthBar()
        end

        return UI.EnableHealthBar()
    end

    local function Initialize()
        -- Load saved size/colors/format first so everything below reflects your last session.
        TryLoadHealthBarSettingsOnce()

        modern_health_bar_state.initialized = true
    end

    local function Settings()
        local state = modern_health_bar_state

        ImGui.Text("Size")
        state.bar_width  = ImGui.SliderInt("Width", state.bar_width, 50, 400, tostring(state.bar_width))
        state.bar_height = ImGui.SliderInt("Height", state.bar_height, 10, 80, tostring(state.bar_height))
        state.bar_scale  = ImGui.SliderFloat("Scale", state.bar_scale, 0.1, 5.0, tostring(state.bar_scale))

        ImGui.Separator()
        ImGui.Text("Colors")
        state.background_color = ImGui.ColorEdit4("Background Color", state.background_color)
        state.fill_color       = ImGui.ColorEdit4("Fill Color", state.fill_color)

        state.use_low_health_color = ImGui.Checkbox("Use Low Health Color", state.use_low_health_color)
        state.fill_color_low       = ImGui.ColorEdit4("Low Health Fill Color", state.fill_color_low)
        state.low_health_threshold = ImGui.SliderFloat("Low Health Threshold", state.low_health_threshold, 0.05, 0.9,
            string.format("%d%%", math.floor(state.low_health_threshold * 100)))

        ImGui.Separator()
        ImGui.Text("Border")
        state.show_border      = ImGui.Checkbox("Show Border", state.show_border)
        state.border_color     = ImGui.ColorEdit4("Border Color", state.border_color)
        state.border_thickness = ImGui.SliderFloat("Border Thickness", state.border_thickness, 0.5, 5.0, tostring(state.border_thickness))
        state.corner_rounding  = ImGui.SliderFloat("Corner Rounding", state.corner_rounding, 0, 20, tostring(state.corner_rounding))

        ImGui.Separator()
        ImGui.Text("Text")
        state.show_text  = ImGui.Checkbox("Show Text", state.show_text)
        state.text_color = ImGui.ColorEdit4("Text Color", state.text_color)

        if ImGui.RadioButton("Current / Max  (e.g. 138/158)", state.text_format == "current_max") then
            state.text_format = "current_max"
        end
        if ImGui.RadioButton("Percentage  (e.g. 87%)", state.text_format == "percent") then
            state.text_format = "percent"
        end
        state.font_scale = ImGui.SliderFloat("Font Scale", state.font_scale, 0.5, 3.0, tostring(state.font_scale))
        state.bold_text  = ImGui.Checkbox("Bold Text", state.bold_text)

        ImGui.Separator()
        local new_val, pressed = ImGui.Checkbox("Disable Default Health Bar", state.disable_default_health_bar)
        if pressed then
            state.disable_default_health_bar = new_val
            state.native_toggle_confirmed = ToggleDefaultHealthBar()
        end

        -- Persist any changes made above; only writes to disk when something actually changed.
        SaveHealthBarSettingsIfChanged()
    end

    local function OnDisable()
        -- v0.06: fires when this script is unchecked in the UiForge menu. Without this, disabling
        -- the script would leave the default health bar hidden with no way to bring it back short
        -- of restarting the game -- so always restore the native UI here, regardless of the
        -- "Disable Default Health Bar" setting.
        UI.EnableHealthBar()
    end

    -- Returns a plain data table of every user customizable option, built directly from
    -- PERSISTED_SETTINGS so the profile save and the on-disk .cfg file can never drift apart.
    -- UiForge captures this into the profile on File > Save Profile and hands it back to Load
    -- when a profile is applied.
    local function Save()
        local state = modern_health_bar_state
        local saved = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            saved[def.key] = state[def.key]
        end
        return saved
    end

    -- Copies a saved value into state only when its type matches the current value,
    -- so a hand edited or stale profile cannot corrupt the state table.
    local function ApplySavedValue(saved, key)
        local state = modern_health_bar_state
        if saved[key] ~= nil and type(saved[key]) == type(state[key]) then
            state[key] = saved[key]
        end
    end

    local function Load(saved)
        if type(saved) ~= "table" then return end

        for _, def in ipairs(PERSISTED_SETTINGS) do
            ApplySavedValue(saved, def.key)
        end

        -- Reapply the health bar patch unconditionally. Disabling the script (or applying
        -- another profile) restores the game health bar via OnDisable WITHOUT changing this
        -- setting, so the in-game UI can be out of sync with the saved value even when the two
        -- compare equal. Resetting the confirmed flag lets Update's per-frame retry (below)
        -- reapply it -- v0.1.1's UI.Disable*/Enable* functions now return whether the write
        -- actually landed, so retrying only until confirmed is safe (no risk of interfering with
        -- anything else the way retrying forever used to).
        modern_health_bar_state.native_toggle_confirmed = false

        -- Keep the on-disk .cfg file in sync with whatever profile was just applied, so the two
        -- persistence systems (profile vs. per-launch file) never disagree.
        SaveHealthBarSettingsIfChanged()
    end

    local function Render()
        -- If we are not in game or if the start menu is open, don't display the bar
        if Util.IsInGame() == 0 or Util.IsStartMenuOpen() == 1 then return end

        local state = modern_health_bar_state

        if ImGui.Begin("modern health bar window", true, state.window_flags) then
            -- Scales all text drawn in this window (both ImGui.Text and draw_list:AddText).
            -- Must be set before any text is measured/drawn below.
            ImGui.SetWindowFontScale(state.font_scale)

            local scaled_width  = state.bar_width * state.bar_scale
            local scaled_height = state.bar_height * state.bar_scale

            local current_hp = Player.GetCurrentHp()
            local max_hp = Player.GetMaxHp()
            if max_hp <= 0 then max_hp = 1 end -- guard against a divide-by-zero if max HP ever reads 0

            local health_percent = current_hp / max_hp
            if health_percent < 0 then health_percent = 0 end
            if health_percent > 1 then health_percent = 1 end

            local draw_list = ImGui.GetWindowDrawList()
            local origin_x, origin_y = ImGui.GetCursorScreenPos()
            local p0 = ImVec2.new(origin_x, origin_y)
            local p1 = ImVec2.new(origin_x + scaled_width, origin_y + scaled_height)

            -- Background track
            local background_color_u32 = ImGui.GetColorU32(state.background_color[1], state.background_color[2], state.background_color[3], state.background_color[4])
            draw_list:AddRectFilled(p0, p1, background_color_u32, state.corner_rounding)

            -- Fill, clipped to the current health percentage. Clipping (rather than resizing the
            -- rect itself) keeps the left corners rounded to match the background at any fill amount.
            if health_percent > 0 then
                local active_fill_color = state.fill_color
                if state.use_low_health_color and health_percent <= state.low_health_threshold then
                    active_fill_color = state.fill_color_low
                end
                local fill_color_u32 = ImGui.GetColorU32(active_fill_color[1], active_fill_color[2], active_fill_color[3], active_fill_color[4])

                local fill_end_x = origin_x + (scaled_width * health_percent)
                ImGui.PushClipRect(p0.x, p0.y, fill_end_x, p1.y, true)
                draw_list:AddRectFilled(p0, p1, fill_color_u32, state.corner_rounding)
                ImGui.PopClipRect()
            end

            -- Border
            if state.show_border then
                local border_color_u32 = ImGui.GetColorU32(state.border_color[1], state.border_color[2], state.border_color[3], state.border_color[4])
                draw_list:AddRect(p0, p1, border_color_u32, state.corner_rounding, 0, state.border_thickness)
            end

            -- Text overlay, e.g. "138/158" or "87%"
            if state.show_text then
                local display_text
                if state.text_format == "percent" then
                    display_text = string.format("%d%%", math.floor(health_percent * 100 + 0.5))
                else
                    display_text = string.format("%d/%d", math.floor(current_hp + 0.5), math.floor(max_hp + 0.5))
                end

                -- NOTE: ImGui.CalcTextSize is used here to center the text within the bar.
                -- If your UiForge build doesn't expose it, replace the two lines below with a
                -- fixed offset, e.g.: local text_x, text_y = p0.x + 6, p0.y + (scaled_height - 14) / 2
                local text_width, text_height = ImGui.CalcTextSize(display_text)
                local text_x = p0.x + (scaled_width - text_width) / 2
                local text_y = p0.y + (scaled_height - text_height) / 2

                local text_color_u32 = ImGui.GetColorU32(state.text_color[1], state.text_color[2], state.text_color[3], state.text_color[4])

                if state.bold_text then
                    -- No bold font is available to load from Lua, so this fakes it by drawing the
                    -- same text a pixel to the right and a pixel down first, thickening the strokes.
                    local bold_offset = 1 * state.font_scale
                    draw_list:AddText(ImVec2.new(text_x + bold_offset, text_y), text_color_u32, display_text)
                    draw_list:AddText(ImVec2.new(text_x, text_y + bold_offset), text_color_u32, display_text)
                    draw_list:AddText(ImVec2.new(text_x + bold_offset, text_y + bold_offset), text_color_u32, display_text)
                end
                draw_list:AddText(ImVec2.new(text_x, text_y), text_color_u32, display_text)
            end

            -- Reserve layout space matching the bar so the auto-resize window sizes correctly
            -- (drawing directly to the draw list, like above, doesn't move the ImGui cursor on its own)
            ImGui.Dummy(scaled_width, scaled_height)
        end
        ImGui.End()
    end

    local function Update()
        if modern_health_bar_state.initialized == false then Initialize() end

        -- v0.1.1: UI.DisableHealthBar()/EnableHealthBar() now return whether the write actually
        -- landed (false when the game UI isn't ready yet, e.g. right at login). Retrying every
        -- frame ONLY until confirmed is safe and precise -- unlike retrying forever, it stops
        -- the instant it succeeds, so there's no ongoing risk of interfering with anything else.
        if modern_health_bar_state.native_toggle_confirmed ~= true then
            modern_health_bar_state.native_toggle_confirmed = ToggleDefaultHealthBar()
        end

        if modern_health_bar_state.initialized then Render() end
    end

    ModPack = ModPack or {}
    ModPack.HealthBar = {
        display_name = "Health Bar",
        Update = Update,
        Settings = Settings,
        OnDisable = OnDisable,
        Save = Save,
        Load = Load,
    }
end
-- ============================================================================
-- MOD: Mana Bar
-- ============================================================================
do
    local UI = require("frontiers_forge.ui")                -- Access UI elements
    local Player = require("frontiers_forge.player")        -- Access Player attributes and functions
    local Util = require("frontiers_forge.util")            -- Access Utility functions

    -- Creating a long, specific table name so that I (hopefully) avoid naming collisions
    modern_mana_bar_state = modern_mana_bar_state or {
        window_flags                = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.NoTitleBar,
        initialized                 = false,
        callbacks_registered         = false,
        native_toggle_confirmed      = false, -- v0.1.1: tracks whether the native-bar disable/enable write has actually landed yet

        -- Settings persistence (so your sizing/colors survive a relaunch)
        settings_file_loaded        = false,
        _settings_snapshot          = "",

        -- Bar dimensions
        bar_width                   = 200,
        bar_height                  = 24,
        bar_scale                   = 1,

        -- Colors
        background_color            = {0.08, 0.08, 0.08, 0.85},   -- near-black, semi-transparent
        fill_color                  = {0.10, 0.35, 0.90, 1.0},     -- blue
        use_low_mana_color          = true,
        fill_color_low              = {0.55, 0.15, 0.80, 1.0},     -- violet, shown below the threshold
        low_mana_threshold           = 0.25,

        -- Border
        show_border                 = true,
        border_color                = {0, 0, 0, 1},
        border_thickness            = 1.5,
        corner_rounding              = 4,

        -- Text overlay
        show_text                   = true,
        text_color                  = {1, 1, 1, 1},
        text_format                 = "current_max",   -- "current_max" -> "138/158"  |  "percent" -> "87%"
        font_scale                  = 1.0,             -- text size, relative to the default UI font
        bold_text                   = false,           -- simulates bold by drawing the text with a slight offset stroke

        disable_default_power_bar   = true,
    }

    local function Trim(str)
        if str == nil then return "" end
        return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseBool(value)
        value = Trim(value):lower()
        return (value == "true" or value == "1" or value == "yes" or value == "on")
    end

    --[[
    Settings persistence

    Saves/loads the settings below to "resources\\mana_pool\\mana_bar_settings.cfg"
    as simple "key=value" lines, so the bar's size/colors/format are remembered across launches
    instead of resetting to defaults every time.
    ]]
    local PERSISTED_SETTINGS = {
        { key = "bar_width",              type = "number" },
        { key = "bar_height",             type = "number" },
        { key = "bar_scale",              type = "number" },
        { key = "background_color",       type = "color" },
        { key = "fill_color",             type = "color" },
        { key = "use_low_mana_color",     type = "bool" },
        { key = "fill_color_low",         type = "color" },
        { key = "low_mana_threshold",     type = "number" },
        { key = "show_border",            type = "bool" },
        { key = "border_color",           type = "color" },
        { key = "border_thickness",       type = "number" },
        { key = "corner_rounding",        type = "number" },
        { key = "show_text",              type = "bool" },
        { key = "text_color",             type = "color" },
        { key = "text_format",            type = "string" },
        { key = "font_scale",             type = "number" },
        { key = "bold_text",              type = "bool" },
        { key = "disable_default_power_bar", type = "bool" },
    }

    local function GetManaBarSettingsFilePath()
        return UiForge.resources_path .. "\\mana_pool\\mana_bar_settings.cfg"
    end

    local function SerializeSettingsValue(value, value_type)
        if value_type == "color" then
            return table.concat({ tostring(value[1]), tostring(value[2]), tostring(value[3]), tostring(value[4]) }, ",")
        elseif value_type == "bool" then
            return value and "true" or "false"
        else -- "number" or "string" (text_format has no special characters, so no CSV escaping needed here)
            return tostring(value)
        end
    end

    local function ParseSettingsValue(raw_value, value_type)
        if value_type == "color" then
            local components = {}
            for field in tostring(raw_value):gmatch("[^,]+") do
                components[#components + 1] = tonumber(field)
            end
            if #components == 4 and components[1] and components[2] and components[3] and components[4] then
                return components
            end
            return nil
        elseif value_type == "bool" then
            return ParseBool(raw_value)
        elseif value_type == "string" then
            return Trim(raw_value)
        else -- "number"
            return tonumber(raw_value)
        end
    end

    local function BuildSettingsSnapshot()
        local lines = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            lines[#lines + 1] = def.key .. "=" .. SerializeSettingsValue(modern_mana_bar_state[def.key], def.type)
        end
        return table.concat(lines, "\n")
    end

    local function WriteSettingsSnapshotToFile(snapshot)
        local path = GetManaBarSettingsFilePath()
        local file = io.open(path, "w")
        if file == nil then
            return false
        end

        file:write("# mana_bar_settings.cfg -- auto-generated. Delete this file to reset the mana bar to defaults.\n")
        file:write(snapshot)
        file:write("\n")
        file:close()
        return true
    end

    -- Call this after any setting-editing widget runs. It only touches disk if a value actually changed.
    local function SaveManaBarSettingsIfChanged()
        local snapshot = BuildSettingsSnapshot()
        if snapshot ~= modern_mana_bar_state._settings_snapshot then
            if WriteSettingsSnapshotToFile(snapshot) then
                modern_mana_bar_state._settings_snapshot = snapshot
            end
        end
    end

    local function LoadManaBarSettingsFromFile()
        local path = GetManaBarSettingsFilePath()
        local file = io.open(path, "r")
        if file == nil then
            return false -- No saved settings yet; keep the defaults.
        end

        local defs_by_key = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            defs_by_key[def.key] = def.type
        end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
                if key ~= nil and defs_by_key[key] ~= nil then
                    local parsed = ParseSettingsValue(raw_value, defs_by_key[key])
                    if parsed ~= nil then
                        modern_mana_bar_state[key] = parsed
                    end
                end
            end
        end

        file:close()
        modern_mana_bar_state._settings_snapshot = BuildSettingsSnapshot()
        return true
    end

    local function TryLoadManaBarSettingsOnce()
        if modern_mana_bar_state.settings_file_loaded == true then return end
        LoadManaBarSettingsFromFile()
        modern_mana_bar_state.settings_file_loaded = true
    end

    local function ToggleDefaultPowerBar()
        if modern_mana_bar_state.disable_default_power_bar == true then
            return UI.DisablePowerBar()
        end

        return UI.EnablePowerBar()
    end

    local function Initialize()
        -- Load saved size/colors/format first so everything below reflects your last session.
        TryLoadManaBarSettingsOnce()

        modern_mana_bar_state.initialized = true
    end

    local function Settings()
        local state = modern_mana_bar_state

        ImGui.Text("Size")
        state.bar_width  = ImGui.SliderInt("Width", state.bar_width, 50, 400, tostring(state.bar_width))
        state.bar_height = ImGui.SliderInt("Height", state.bar_height, 10, 80, tostring(state.bar_height))
        state.bar_scale  = ImGui.SliderFloat("Scale", state.bar_scale, 0.1, 5.0, tostring(state.bar_scale))

        ImGui.Separator()
        ImGui.Text("Colors")
        state.background_color = ImGui.ColorEdit4("Background Color", state.background_color)
        state.fill_color       = ImGui.ColorEdit4("Fill Color", state.fill_color)

        state.use_low_mana_color = ImGui.Checkbox("Use Low Mana Color", state.use_low_mana_color)
        state.fill_color_low     = ImGui.ColorEdit4("Low Mana Fill Color", state.fill_color_low)
        state.low_mana_threshold = ImGui.SliderFloat("Low Mana Threshold", state.low_mana_threshold, 0.05, 0.9,
            string.format("%d%%", math.floor(state.low_mana_threshold * 100)))

        ImGui.Separator()
        ImGui.Text("Border")
        state.show_border      = ImGui.Checkbox("Show Border", state.show_border)
        state.border_color     = ImGui.ColorEdit4("Border Color", state.border_color)
        state.border_thickness = ImGui.SliderFloat("Border Thickness", state.border_thickness, 0.5, 5.0, tostring(state.border_thickness))
        state.corner_rounding  = ImGui.SliderFloat("Corner Rounding", state.corner_rounding, 0, 20, tostring(state.corner_rounding))

        ImGui.Separator()
        ImGui.Text("Text")
        state.show_text  = ImGui.Checkbox("Show Text", state.show_text)
        state.text_color = ImGui.ColorEdit4("Text Color", state.text_color)

        if ImGui.RadioButton("Current / Max  (e.g. 138/158)", state.text_format == "current_max") then
            state.text_format = "current_max"
        end
        if ImGui.RadioButton("Percentage  (e.g. 87%)", state.text_format == "percent") then
            state.text_format = "percent"
        end
        state.font_scale = ImGui.SliderFloat("Font Scale", state.font_scale, 0.5, 3.0, tostring(state.font_scale))
        state.bold_text  = ImGui.Checkbox("Bold Text", state.bold_text)

        ImGui.Separator()
        local new_val, pressed = ImGui.Checkbox("Disable Default Power Bar", state.disable_default_power_bar)
        if pressed then
            state.disable_default_power_bar = new_val
            state.native_toggle_confirmed = ToggleDefaultPowerBar()
        end

        -- Persist any changes made above; only writes to disk when something actually changed.
        SaveManaBarSettingsIfChanged()
    end

    local function OnDisable()
        -- v0.06: fires when this script is unchecked in the UiForge menu. Without this, disabling
        -- the script would leave the default power bar hidden with no way to bring it back short
        -- of restarting the game -- so always restore the native UI here, regardless of the
        -- "Disable Default Power Bar" setting.
        UI.EnablePowerBar()
    end

    -- Returns a plain data table of every user customizable option, built directly from
    -- PERSISTED_SETTINGS so the profile save and the on-disk .cfg file can never drift apart.
    -- UiForge captures this into the profile on File > Save Profile and hands it back to Load
    -- when a profile is applied.
    local function Save()
        local state = modern_mana_bar_state
        local saved = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            saved[def.key] = state[def.key]
        end
        return saved
    end

    -- Copies a saved value into state only when its type matches the current value,
    -- so a hand edited or stale profile cannot corrupt the state table.
    local function ApplySavedValue(saved, key)
        local state = modern_mana_bar_state
        if saved[key] ~= nil and type(saved[key]) == type(state[key]) then
            state[key] = saved[key]
        end
    end

    local function Load(saved)
        if type(saved) ~= "table" then return end

        for _, def in ipairs(PERSISTED_SETTINGS) do
            ApplySavedValue(saved, def.key)
        end

        -- Reapply the power bar patch unconditionally. Disabling the script (or applying
        -- another profile) restores the game power bar via OnDisable WITHOUT changing this
        -- setting, so the in-game UI can be out of sync with the saved value even when the two
        -- compare equal. Resetting the confirmed flag lets Update's per-frame retry reapply it.
        modern_mana_bar_state.native_toggle_confirmed = false

        -- Keep the on-disk .cfg file in sync with whatever profile was just applied, so the two
        -- persistence systems (profile vs. per-launch file) never disagree.
        SaveManaBarSettingsIfChanged()
    end

    local function Render()
        -- If we are not in game or if the start menu is open, don't display the bar
        if Util.IsInGame() == 0 or Util.IsStartMenuOpen() == 1 then return end

        local state = modern_mana_bar_state

        if ImGui.Begin("modern mana bar window", true, state.window_flags) then
            -- Scales all text drawn in this window (both ImGui.Text and draw_list:AddText).
            -- Must be set before any text is measured/drawn below.
            ImGui.SetWindowFontScale(state.font_scale)

            local scaled_width  = state.bar_width * state.bar_scale
            local scaled_height = state.bar_height * state.bar_scale

            local current_pwr = Player.GetCurrentPwr()
            local max_pwr = Player.GetMaxPwr()
            if max_pwr <= 0 then max_pwr = 1 end -- guard against a divide-by-zero if max power ever reads 0

            local mana_percent = current_pwr / max_pwr
            if mana_percent < 0 then mana_percent = 0 end
            if mana_percent > 1 then mana_percent = 1 end

            local draw_list = ImGui.GetWindowDrawList()
            local origin_x, origin_y = ImGui.GetCursorScreenPos()
            local p0 = ImVec2.new(origin_x, origin_y)
            local p1 = ImVec2.new(origin_x + scaled_width, origin_y + scaled_height)

            -- Background track
            local background_color_u32 = ImGui.GetColorU32(state.background_color[1], state.background_color[2], state.background_color[3], state.background_color[4])
            draw_list:AddRectFilled(p0, p1, background_color_u32, state.corner_rounding)

            -- Fill, clipped to the current mana percentage. Clipping (rather than resizing the
            -- rect itself) keeps the left corners rounded to match the background at any fill amount.
            if mana_percent > 0 then
                local active_fill_color = state.fill_color
                if state.use_low_mana_color and mana_percent <= state.low_mana_threshold then
                    active_fill_color = state.fill_color_low
                end
                local fill_color_u32 = ImGui.GetColorU32(active_fill_color[1], active_fill_color[2], active_fill_color[3], active_fill_color[4])

                local fill_end_x = origin_x + (scaled_width * mana_percent)
                ImGui.PushClipRect(p0.x, p0.y, fill_end_x, p1.y, true)
                draw_list:AddRectFilled(p0, p1, fill_color_u32, state.corner_rounding)
                ImGui.PopClipRect()
            end

            -- Border
            if state.show_border then
                local border_color_u32 = ImGui.GetColorU32(state.border_color[1], state.border_color[2], state.border_color[3], state.border_color[4])
                draw_list:AddRect(p0, p1, border_color_u32, state.corner_rounding, 0, state.border_thickness)
            end

            -- Text overlay, e.g. "138/158" or "87%"
            if state.show_text then
                local display_text
                if state.text_format == "percent" then
                    display_text = string.format("%d%%", math.floor(mana_percent * 100 + 0.5))
                else
                    display_text = string.format("%d/%d", math.floor(current_pwr + 0.5), math.floor(max_pwr + 0.5))
                end

                -- NOTE: ImGui.CalcTextSize is used here to center the text within the bar.
                -- If your UiForge build doesn't expose it, replace the two lines below with a
                -- fixed offset, e.g.: local text_x, text_y = p0.x + 6, p0.y + (scaled_height - 14) / 2
                local text_width, text_height = ImGui.CalcTextSize(display_text)
                local text_x = p0.x + (scaled_width - text_width) / 2
                local text_y = p0.y + (scaled_height - text_height) / 2

                local text_color_u32 = ImGui.GetColorU32(state.text_color[1], state.text_color[2], state.text_color[3], state.text_color[4])

                if state.bold_text then
                    -- No bold font is available to load from Lua, so this fakes it by drawing the
                    -- same text a pixel to the right and a pixel down first, thickening the strokes.
                    local bold_offset = 1 * state.font_scale
                    draw_list:AddText(ImVec2.new(text_x + bold_offset, text_y), text_color_u32, display_text)
                    draw_list:AddText(ImVec2.new(text_x, text_y + bold_offset), text_color_u32, display_text)
                    draw_list:AddText(ImVec2.new(text_x + bold_offset, text_y + bold_offset), text_color_u32, display_text)
                end
                draw_list:AddText(ImVec2.new(text_x, text_y), text_color_u32, display_text)
            end

            -- Reserve layout space matching the bar so the auto-resize window sizes correctly
            -- (drawing directly to the draw list, like above, doesn't move the ImGui cursor on its own)
            ImGui.Dummy(scaled_width, scaled_height)
        end
        ImGui.End()
    end

    local function Update()
        if modern_mana_bar_state.initialized == false then Initialize() end

        if modern_mana_bar_state.native_toggle_confirmed ~= true then
            modern_mana_bar_state.native_toggle_confirmed = ToggleDefaultPowerBar()
        end

        if modern_mana_bar_state.initialized then Render() end
    end

    ModPack = ModPack or {}
    ModPack.ManaBar = {
        display_name = "Mana Bar",
        Update = Update,
        Settings = Settings,
        OnDisable = OnDisable,
        Save = Save,
        Load = Load,
    }
end
-- ============================================================================
-- MOD: Experience Bars
-- ============================================================================
do
    local UI = require("frontiers_forge.ui")                -- Access UI elements
    local Player = require("frontiers_forge.player")        -- Access Player attributes and functions
    local Util = require("frontiers_forge.util")            -- Access Utility functions

    -- Creating a long, specific table name so that I (hopefully) avoid naming collisions
    modern_exp_bars_state = modern_exp_bars_state or {
        window_flags                = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.NoTitleBar,
        initialized                 = false,
        callbacks_registered         = false,
        main_toggle_confirmed        = false, -- v0.1.1: tracks whether each native-bar write has actually landed yet
        secondary_toggle_confirmed   = false,

        -- Settings persistence (so your sizing/colors survive a relaunch)
        settings_file_loaded        = false,
        _settings_snapshot          = "",

        -- Shared dimensions (both bars use the same width/scale so they line up)
        bar_width                   = 200,
        bar_height                  = 20,
        bar_scale                   = 1,
        bar_spacing                 = 4,     -- vertical gap between the two bars
        font_scale                  = 1.0,   -- text size for both bars, relative to the default UI font
        bold_text                   = false, -- simulates bold by drawing the text with a slight offset stroke

        -- Main (gold) exp bar -- fills toward your next level
        main_background_color       = {0.08, 0.08, 0.08, 0.85},
        main_fill_color              = {0.85, 0.65, 0.05, 1.0},   -- gold
        main_show_border            = true,
        main_border_color           = {0, 0, 0, 1},
        main_border_thickness       = 1.5,
        main_corner_rounding         = 4,
        main_show_text               = true,
        main_text_color              = {1, 1, 1, 1},
        main_text_format             = "percent",   -- "percent" -> "42%"  |  "current_max" -> "1234/5000"

        -- Secondary (pink/CM) bar -- fills a bonus pool that feeds into the main bar
        secondary_background_color  = {0.08, 0.08, 0.08, 0.85},
        secondary_fill_color        = {0.90, 0.20, 0.55, 1.0},    -- pink
        secondary_show_border       = true,
        secondary_border_color      = {0, 0, 0, 1},
        secondary_border_thickness  = 1.5,
        secondary_corner_rounding    = 4,
        secondary_show_text          = true,
        secondary_text_color         = {1, 1, 1, 1},
        pink_fills_per_level         = 4,   -- how many full pink-bar fills make up one gold-bar level

        disable_default_main_exp_bar      = true,
        disable_default_secondary_exp_bar = true,
    }

    local function Trim(str)
        if str == nil then return "" end
        return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseBool(value)
        value = Trim(value):lower()
        return (value == "true" or value == "1" or value == "yes" or value == "on")
    end

    --[[
    Settings persistence

    Saves/loads the settings below to "resources\\exp_bars\\exp_bars_settings.cfg"
    as simple "key=value" lines, so the bars' sizing/colors/format are remembered across
    launches instead of resetting to defaults every time.
    ]]
    local PERSISTED_SETTINGS = {
        { key = "bar_width",                        type = "number" },
        { key = "bar_height",                       type = "number" },
        { key = "bar_scale",                        type = "number" },
        { key = "bar_spacing",                      type = "number" },
        { key = "pink_fills_per_level",              type = "number" },
        { key = "font_scale",                       type = "number" },
        { key = "bold_text",                        type = "bool" },

        { key = "main_background_color",            type = "color" },
        { key = "main_fill_color",                  type = "color" },
        { key = "main_show_border",                 type = "bool" },
        { key = "main_border_color",                type = "color" },
        { key = "main_border_thickness",            type = "number" },
        { key = "main_corner_rounding",              type = "number" },
        { key = "main_show_text",                    type = "bool" },
        { key = "main_text_color",                   type = "color" },
        { key = "main_text_format",                  type = "string" },

        { key = "secondary_background_color",       type = "color" },
        { key = "secondary_fill_color",              type = "color" },
        { key = "secondary_show_border",             type = "bool" },
        { key = "secondary_border_color",            type = "color" },
        { key = "secondary_border_thickness",        type = "number" },
        { key = "secondary_corner_rounding",          type = "number" },
        { key = "secondary_show_text",                type = "bool" },
        { key = "secondary_text_color",               type = "color" },

        { key = "disable_default_main_exp_bar",             type = "bool" },
        { key = "disable_default_secondary_exp_bar",        type = "bool" },
    }

    local function GetExpBarsSettingsFilePath()
        return UiForge.resources_path .. "\\exp_bars\\exp_bars_settings.cfg"
    end

    local function SerializeSettingsValue(value, value_type)
        if value_type == "color" then
            return table.concat({ tostring(value[1]), tostring(value[2]), tostring(value[3]), tostring(value[4]) }, ",")
        elseif value_type == "bool" then
            return value and "true" or "false"
        else -- "number" or "string"
            return tostring(value)
        end
    end

    local function ParseSettingsValue(raw_value, value_type)
        if value_type == "color" then
            local components = {}
            for field in tostring(raw_value):gmatch("[^,]+") do
                components[#components + 1] = tonumber(field)
            end
            if #components == 4 and components[1] and components[2] and components[3] and components[4] then
                return components
            end
            return nil
        elseif value_type == "bool" then
            return ParseBool(raw_value)
        elseif value_type == "string" then
            return Trim(raw_value)
        else -- "number"
            return tonumber(raw_value)
        end
    end

    local function BuildSettingsSnapshot()
        local lines = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            lines[#lines + 1] = def.key .. "=" .. SerializeSettingsValue(modern_exp_bars_state[def.key], def.type)
        end
        return table.concat(lines, "\n")
    end

    local function WriteSettingsSnapshotToFile(snapshot)
        local path = GetExpBarsSettingsFilePath()
        local file = io.open(path, "w")
        if file == nil then
            return false
        end

        file:write("# exp_bars_settings.cfg -- auto-generated. Delete this file to reset the exp bars to defaults.\n")
        file:write(snapshot)
        file:write("\n")
        file:close()
        return true
    end

    -- Call this after any setting-editing widget runs. It only touches disk if a value actually changed.
    local function SaveExpBarsSettingsIfChanged()
        local snapshot = BuildSettingsSnapshot()
        if snapshot ~= modern_exp_bars_state._settings_snapshot then
            if WriteSettingsSnapshotToFile(snapshot) then
                modern_exp_bars_state._settings_snapshot = snapshot
            end
        end
    end

    local function LoadExpBarsSettingsFromFile()
        local path = GetExpBarsSettingsFilePath()
        local file = io.open(path, "r")
        if file == nil then
            return false -- No saved settings yet; keep the defaults.
        end

        local defs_by_key = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            defs_by_key[def.key] = def.type
        end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
                if key ~= nil and defs_by_key[key] ~= nil then
                    local parsed = ParseSettingsValue(raw_value, defs_by_key[key])
                    if parsed ~= nil then
                        modern_exp_bars_state[key] = parsed
                    end
                end
            end
        end

        file:close()
        modern_exp_bars_state._settings_snapshot = BuildSettingsSnapshot()
        return true
    end

    local function TryLoadExpBarsSettingsOnce()
        if modern_exp_bars_state.settings_file_loaded == true then return end
        LoadExpBarsSettingsFromFile()
        modern_exp_bars_state.settings_file_loaded = true
    end

    local function ToggleDefaultMainExpBar()
        if modern_exp_bars_state.disable_default_main_exp_bar == true then
            return UI.DisableMainExpBar()
        end
        return UI.EnableMainExpBar()
    end

    local function ToggleDefaultSecondaryExpBar()
        if modern_exp_bars_state.disable_default_secondary_exp_bar == true then
            return UI.DisableSecondaryExpBar()
        end
        return UI.EnableSecondaryExpBar()
    end

    local function Initialize()
        -- Load saved size/colors/format first so everything below reflects your last session.
        TryLoadExpBarsSettingsOnce()

        modern_exp_bars_state.initialized = true
    end

    local function Settings()
        local state = modern_exp_bars_state

        ImGui.Text("Shared Size")
        state.bar_width   = ImGui.SliderInt("Width", state.bar_width, 50, 400, tostring(state.bar_width))
        state.bar_height  = ImGui.SliderInt("Height", state.bar_height, 10, 60, tostring(state.bar_height))
        state.bar_scale   = ImGui.SliderFloat("Scale", state.bar_scale, 0.1, 5.0, tostring(state.bar_scale))
        state.bar_spacing = ImGui.SliderInt("Spacing Between Bars", state.bar_spacing, 0, 30, tostring(state.bar_spacing))
        state.pink_fills_per_level = ImGui.SliderInt("Pink Fills Per Level", state.pink_fills_per_level, 1, 20, tostring(state.pink_fills_per_level))
        state.font_scale = ImGui.SliderFloat("Font Scale", state.font_scale, 0.5, 3.0, tostring(state.font_scale))
        state.bold_text  = ImGui.Checkbox("Bold Text", state.bold_text)

        ImGui.Separator()
        ImGui.Text("Main Exp Bar (Gold)")
        state.main_background_color = ImGui.ColorEdit4("Background##main", state.main_background_color)
        state.main_fill_color       = ImGui.ColorEdit4("Fill Color##main", state.main_fill_color)
        state.main_show_border      = ImGui.Checkbox("Show Border##main", state.main_show_border)
        state.main_border_color     = ImGui.ColorEdit4("Border Color##main", state.main_border_color)
        state.main_border_thickness = ImGui.SliderFloat("Border Thickness##main", state.main_border_thickness, 0.5, 5.0, tostring(state.main_border_thickness))
        state.main_corner_rounding  = ImGui.SliderFloat("Corner Rounding##main", state.main_corner_rounding, 0, 20, tostring(state.main_corner_rounding))
        state.main_show_text        = ImGui.Checkbox("Show Text##main", state.main_show_text)
        state.main_text_color       = ImGui.ColorEdit4("Text Color##main", state.main_text_color)
        if ImGui.RadioButton("Percentage  (e.g. 42%)##main", state.main_text_format == "percent") then
            state.main_text_format = "percent"
        end
        if ImGui.RadioButton("Current / Max  (e.g. 1234/5000)##main", state.main_text_format == "current_max") then
            state.main_text_format = "current_max"
        end

        local new_val_main, pressed_main = ImGui.Checkbox("Disable Default Main Exp Bar", state.disable_default_main_exp_bar)
        if pressed_main then
            state.disable_default_main_exp_bar = new_val_main
            state.main_toggle_confirmed = ToggleDefaultMainExpBar()
        end

        ImGui.Separator()
        ImGui.Text("Secondary Exp Bar (Pink / CM)")
        state.secondary_background_color = ImGui.ColorEdit4("Background##secondary", state.secondary_background_color)
        state.secondary_fill_color       = ImGui.ColorEdit4("Fill Color##secondary", state.secondary_fill_color)
        state.secondary_show_border      = ImGui.Checkbox("Show Border##secondary", state.secondary_show_border)
        state.secondary_border_color     = ImGui.ColorEdit4("Border Color##secondary", state.secondary_border_color)
        state.secondary_border_thickness = ImGui.SliderFloat("Border Thickness##secondary", state.secondary_border_thickness, 0.5, 5.0, tostring(state.secondary_border_thickness))
        state.secondary_corner_rounding  = ImGui.SliderFloat("Corner Rounding##secondary", state.secondary_corner_rounding, 0, 20, tostring(state.secondary_corner_rounding))
        state.secondary_show_text        = ImGui.Checkbox("Show Text##secondary", state.secondary_show_text)
        state.secondary_text_color       = ImGui.ColorEdit4("Text Color##secondary", state.secondary_text_color)

        local new_val_secondary, pressed_secondary = ImGui.Checkbox("Disable Default Secondary Exp Bar", state.disable_default_secondary_exp_bar)
        if pressed_secondary then
            state.disable_default_secondary_exp_bar = new_val_secondary
            state.secondary_toggle_confirmed = ToggleDefaultSecondaryExpBar()
        end

        -- Persist any changes made above; only writes to disk when something actually changed.
        SaveExpBarsSettingsIfChanged()
    end

    local function OnDisable()
        -- v0.06: fires when this script is unchecked in the UiForge menu. Without this, disabling
        -- the script would leave both default exp bars hidden with no way to bring them back short
        -- of restarting the game -- so always restore the native UI here, regardless of the
        -- "Disable Default Main/Secondary Exp Bar" settings.
        UI.EnableMainExpBar()
        UI.EnableSecondaryExpBar()
    end

    -- Returns a plain data table of every user customizable option, built directly from
    -- PERSISTED_SETTINGS so the profile save and the on-disk .cfg file can never drift apart.
    -- UiForge captures this into the profile on File > Save Profile and hands it back to Load
    -- when a profile is applied.
    local function Save()
        local state = modern_exp_bars_state
        local saved = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            saved[def.key] = state[def.key]
        end
        return saved
    end

    -- Copies a saved value into state only when its type matches the current value,
    -- so a hand edited or stale profile cannot corrupt the state table.
    local function ApplySavedValue(saved, key)
        local state = modern_exp_bars_state
        if saved[key] ~= nil and type(saved[key]) == type(state[key]) then
            state[key] = saved[key]
        end
    end

    local function Load(saved)
        if type(saved) ~= "table" then return end

        for _, def in ipairs(PERSISTED_SETTINGS) do
            ApplySavedValue(saved, def.key)
        end

        -- Reapply both exp bar patches unconditionally. Disabling the script (or applying
        -- another profile) restores the game bars via OnDisable WITHOUT changing these settings,
        -- so the in-game UI can be out of sync with the saved values even when they compare equal.
        -- Resetting the confirmed flags lets Update's per-frame retry reapply both.
        modern_exp_bars_state.main_toggle_confirmed = false
        modern_exp_bars_state.secondary_toggle_confirmed = false

        -- Keep the on-disk .cfg file in sync with whatever profile was just applied, so the two
        -- persistence systems (profile vs. per-launch file) never disagree.
        SaveExpBarsSettingsIfChanged()
    end

    -- Draws a single bar at the current cursor position and reserves layout space for it.
    -- percent must already be clamped to [0, 1]. Returns nothing; advances the ImGui cursor.
    local function DrawBar(scaled_width, scaled_height, percent, background_color, fill_color, show_border, border_color, border_thickness, corner_rounding, display_text, show_text, text_color, bold_text, font_scale)
        local draw_list = ImGui.GetWindowDrawList()
        local origin_x, origin_y = ImGui.GetCursorScreenPos()
        local p0 = ImVec2.new(origin_x, origin_y)
        local p1 = ImVec2.new(origin_x + scaled_width, origin_y + scaled_height)

        local background_color_u32 = ImGui.GetColorU32(background_color[1], background_color[2], background_color[3], background_color[4])
        draw_list:AddRectFilled(p0, p1, background_color_u32, corner_rounding)

        if percent > 0 then
            local fill_color_u32 = ImGui.GetColorU32(fill_color[1], fill_color[2], fill_color[3], fill_color[4])
            local fill_end_x = origin_x + (scaled_width * percent)
            ImGui.PushClipRect(p0.x, p0.y, fill_end_x, p1.y, true)
            draw_list:AddRectFilled(p0, p1, fill_color_u32, corner_rounding)
            ImGui.PopClipRect()
        end

        if show_border then
            local border_color_u32 = ImGui.GetColorU32(border_color[1], border_color[2], border_color[3], border_color[4])
            draw_list:AddRect(p0, p1, border_color_u32, corner_rounding, 0, border_thickness)
        end

        if show_text and display_text ~= nil then
            -- NOTE: ImGui.CalcTextSize is used here to center the text within the bar.
            -- If your UiForge build doesn't expose it, replace the two lines below with a
            -- fixed offset, e.g.: local text_x, text_y = p0.x + 6, p0.y + (scaled_height - 14) / 2
            local text_width, text_height = ImGui.CalcTextSize(display_text)
            local text_x = p0.x + (scaled_width - text_width) / 2
            local text_y = p0.y + (scaled_height - text_height) / 2
            local text_color_u32 = ImGui.GetColorU32(text_color[1], text_color[2], text_color[3], text_color[4])

            if bold_text then
                -- No bold font is available to load from Lua, so this fakes it by drawing the
                -- same text a pixel to the right and a pixel down first, thickening the strokes.
                local bold_offset = 1 * font_scale
                draw_list:AddText(ImVec2.new(text_x + bold_offset, text_y), text_color_u32, display_text)
                draw_list:AddText(ImVec2.new(text_x, text_y + bold_offset), text_color_u32, display_text)
                draw_list:AddText(ImVec2.new(text_x + bold_offset, text_y + bold_offset), text_color_u32, display_text)
            end
            draw_list:AddText(ImVec2.new(text_x, text_y), text_color_u32, display_text)
        end

        -- Reserve layout space matching the bar so the auto-resize window sizes correctly
        -- (drawing directly to the draw list, like above, doesn't move the ImGui cursor on its own)
        ImGui.Dummy(scaled_width, scaled_height)
    end

    local function Render()
        -- If we are not in game or if the start menu is open, don't display the bars
        if Util.IsInGame() == 0 or Util.IsStartMenuOpen() == 1 then return end

        local state = modern_exp_bars_state

        if ImGui.Begin("modern exp bars window", true, state.window_flags) then
            -- Scales all text drawn in this window (both ImGui.Text and draw_list:AddText).
            -- Must be set before any text is measured/drawn below.
            ImGui.SetWindowFontScale(state.font_scale)

            local scaled_width  = state.bar_width * state.bar_scale
            local scaled_height = state.bar_height * state.bar_scale

            -- Main (gold) bar: current exp progress toward the next level
            local current_exp = Player.GetExp()
            local required_exp = Util.GetExpRequiredForLevel(Player.GetLevel())
            if required_exp <= 0 then required_exp = 1 end -- guard against a divide-by-zero

            local main_percent = current_exp / required_exp
            if main_percent < 0 then main_percent = 0 end
            if main_percent > 1 then main_percent = 1 end

            local main_text
            if state.main_text_format == "current_max" then
                main_text = string.format("%d/%d", math.floor(current_exp + 0.5), math.floor(required_exp + 0.5))
            else
                main_text = string.format("%d%%", math.floor(main_percent * 100 + 0.5))
            end

            DrawBar(scaled_width, scaled_height, main_percent,
                state.main_background_color, state.main_fill_color,
                state.main_show_border, state.main_border_color, state.main_border_thickness, state.main_corner_rounding,
                main_text, state.main_show_text, state.main_text_color, state.bold_text, state.font_scale)

            ImGui.Dummy(scaled_width, state.bar_spacing)

            -- Secondary (pink) bar: per the dev notes, filling this bar once = 25% of the gold bar
            -- (i.e. it takes 4 full pink fills to level up). Rather than pull this from a separate
            -- API value, we derive it directly from the same exp progress driving the gold bar:
            -- take the gold percent, multiply by how many pink fills make up a full level, and
            -- keep only the fractional part -- that's how far through the *current* pink fill you are.
            local pink_raw = main_percent * state.pink_fills_per_level
            local secondary_percent = pink_raw - math.floor(pink_raw)
            if main_percent >= 1 then secondary_percent = 1 end -- edge case: fully leveled, show the pink bar full too

            local secondary_text = string.format("%d%%", math.floor(secondary_percent * 100 + 0.5))

            DrawBar(scaled_width, scaled_height, secondary_percent,
                state.secondary_background_color, state.secondary_fill_color,
                state.secondary_show_border, state.secondary_border_color, state.secondary_border_thickness, state.secondary_corner_rounding,
                secondary_text, state.secondary_show_text, state.secondary_text_color, state.bold_text, state.font_scale)
        end
        ImGui.End()
    end

    local function Update()
        if modern_exp_bars_state.initialized == false then Initialize() end

        if modern_exp_bars_state.main_toggle_confirmed ~= true then
            modern_exp_bars_state.main_toggle_confirmed = ToggleDefaultMainExpBar()
        end
        if modern_exp_bars_state.secondary_toggle_confirmed ~= true then
            modern_exp_bars_state.secondary_toggle_confirmed = ToggleDefaultSecondaryExpBar()
        end

        if modern_exp_bars_state.initialized then Render() end
    end

    ModPack = ModPack or {}
    ModPack.ExpBars = {
        display_name = "Experience Bars",
        Update = Update,
        Settings = Settings,
        OnDisable = OnDisable,
        Save = Save,
        Load = Load,
    }
end
-- ============================================================================
-- MOD: Ability Bar
-- ============================================================================
do
    local UI = require("frontiers_forge.ui")                -- Access UI elements
    local Icon = require("frontiers_forge.icon")             -- Decode game icons into ImGui textures
    local Util = require("frontiers_forge.util")            -- Access Utility functions
    local AbilityBar = require("frontiers_forge.ability_bar") -- Access ability bar slots
    local Player = require("frontiers_forge.player")        -- Own coordinates, current target -- for range checking
    local EntityList = require("frontiers_forge.entity_list") -- Resolve target entity for range checking

    --[[
    Modern Ability Bar v3

    Rebuilt on the v1.0 FrontiersForge API. Two major upgrades from v2:

    1. Navigation now reads the GAME'S OWN real selection state (AbilityBar.GetSelectedBarIndex()/
       GetSelectedSlotIndex()), instead of us tracking D-Pad presses ourselves in a parallel system.
       This is a genuine mirror of what the game will actually cast, not a guess -- and it also
       means this script no longer reads the D-Pad at all, so it can't conflict with anything else
       that does (e.g. the native quick-chat menu).

    2. Cooldown tracking is back on by default. The crash this used to cause is fixed at the
       source in v1.0 -- every pointer-chain read across the whole framework now validates each hop
       against EE_RAM_SIZE before touching it, which is exactly the class of bug that was crashing
       the emulator. See the "Enable Cooldown Tracking" setting for details.

    Toolbelt/item slots (a different source_type than the ability list) can now show a REAL icon
    via AbilityBar.GetSlotUITexId() + Icon.GetUITexture() -- the same lookup the game's own compact
    HUD uses for the special-items bar. Still no name available for these slots anywhere in the API.

    Icon rendering for ability slots uses the same Icon.GetTexture() pipeline as before.
    ]]
    modern_ability_bar_state = modern_ability_bar_state or {
        initialized                 = false,
        callbacks_registered         = false,
        native_toggle_confirmed      = false, -- v0.1.1: tracks whether the native-bar disable/enable write has actually landed yet

        -- Settings persistence
        settings_file_loaded        = false,
        _settings_snapshot          = "",

        -- Layout
        bar_scale                    = 1.0,
        slot_size                    = 40,
        slot_spacing                 = 4,
        bar_spacing                  = 10,
        info_panel_top_spacing        = 12,  -- gap between the bars and the highlighted-ability info panel below them

        -- Slot appearance
        background_color              = {0.12, 0.12, 0.12, 0.9},
        empty_slot_color               = {0.05, 0.05, 0.05, 0.6},
        item_slot_color                 = {0.35, 0.28, 0.05, 0.9},  -- distinct color for non-ability (toolbelt/item) slots -- see notes in DrawSlot
        show_icon_background_layer      = true,  -- draws the ability's background icon layer beneath the foreground, matching how the game composites them
        show_border                   = true,
        border_color                  = {0, 0, 0, 1},
        border_thickness              = 1.5,
        corner_rounding                = 6,

        -- Navigation highlight
        show_navigation_highlight      = true,
        enable_cooldown_tracking         = true,  -- fixed at the source in v1.0 -- see header notes
        active_bar_color               = {1.0, 0.85, 0.2, 0.9},   -- outline around the currently active bar
        active_bar_thickness           = 2.5,
        active_bar_padding              = 8,  -- gap between the active-bar outline and the slots themselves (scales with Bar Scale)
        selected_slot_color            = {1.0, 1.0, 1.0, 1.0},    -- highlight around the currently selected slot
        selected_slot_thickness        = 2.5,

        -- Cooldown overlay
        show_cooldown_overlay          = true,
        cooldown_dim_color             = {0, 0, 0, 0.55},
        cooldown_text_color            = {1, 1, 1, 1},

        -- Info overlays
        show_power_cost                = true,
        power_cost_text_color          = {0.55, 0.85, 1.0, 1.0},
        show_slot_number                = true,
        slot_number_color               = {1, 1, 1, 0.6},

        -- Text
        font_scale                     = 1.0,
        bold_text                      = false,

        show_debug_info                = false, -- shows raw errors/status on slots, for troubleshooting icon rendering etc.

        -- Out-of-range indicator: uses the v1.0 Ability:IsInRange() range utility. Only shown
        -- when you actually have a target selected -- with no target there's nothing to check
        -- range against, so abilities just render normally.
        show_range_indicator             = true,
        out_of_range_color                = {0.9, 0.15, 0.15, 0.45},

        -- Removes the window's own default fill, so only the slot backgrounds (drawn explicitly,
        -- always visible regardless of this) show -- empty space around/between bars becomes see-
        -- through instead of a big black rectangle.
        window_transparent              = true,

        -- Name banner: a separate, big-font window showing the currently-highlighted ability's name
        -- and power cost, similar to how the base game displays this. Independent, moveable window
        -- (position it above the ability bar yourself, drag to taste).
        show_name_banner                 = true,
        name_banner_font_scale           = 2.2,
        name_banner_show_power_cost      = true,
        name_banner_text_color            = {1, 1, 1, 1},
        name_banner_power_cost_color      = {0.55, 0.85, 1.0, 1.0},
        name_banner_background_color      = {0.08, 0.08, 0.08, 0.85},
        name_banner_window_transparent    = true,
        name_banner_show_border          = true,
        name_banner_border_color          = {0, 0, 0, 1},
        name_banner_border_thickness      = 1.5,
        name_banner_corner_rounding        = 6,

        disable_default_ability_bar    = true,
    }

    local function Trim(str)
        if str == nil then return "" end
        return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseBool(value)
        value = Trim(value):lower()
        return (value == "true" or value == "1" or value == "yes" or value == "on")
    end

    -- Generic safe method-call helper: TryCall(obj, "MethodName", ...) never throws, even if obj
    -- is nil or the method doesn't exist. Returns (true, result) on success, (false, error) otherwise.
    local function TryCall(obj, method_name, ...)
        if obj == nil then return false, "object was nil" end
        local method = obj[method_name]
        if type(method) ~= "function" then return false, "no method named " .. tostring(method_name) end
        return pcall(method, obj, ...)
    end

    --[[
    Settings persistence

    Saves/loads the settings below to "resources\\ability_bar_settings.cfg".
    ]]
    local PERSISTED_SETTINGS = {
        { key = "bar_scale",                    type = "number" },
        { key = "slot_size",                    type = "number" },
        { key = "slot_spacing",                 type = "number" },
        { key = "bar_spacing",                  type = "number" },
        { key = "info_panel_top_spacing",        type = "number" },

        { key = "background_color",             type = "color" },
        { key = "empty_slot_color",             type = "color" },
        { key = "item_slot_color",               type = "color" },
        { key = "show_icon_background_layer",    type = "bool" },
        { key = "show_border",                  type = "bool" },
        { key = "border_color",                 type = "color" },
        { key = "border_thickness",             type = "number" },
        { key = "corner_rounding",               type = "number" },

        { key = "show_navigation_highlight",     type = "bool" },
        { key = "enable_cooldown_tracking",        type = "bool" },
        { key = "active_bar_color",              type = "color" },
        { key = "active_bar_thickness",          type = "number" },
        { key = "active_bar_padding",             type = "number" },
        { key = "selected_slot_color",           type = "color" },
        { key = "selected_slot_thickness",       type = "number" },

        { key = "show_cooldown_overlay",          type = "bool" },
        { key = "cooldown_dim_color",             type = "color" },
        { key = "cooldown_text_color",            type = "color" },

        { key = "show_power_cost",                type = "bool" },
        { key = "power_cost_text_color",          type = "color" },
        { key = "show_slot_number",                type = "bool" },
        { key = "slot_number_color",               type = "color" },

        { key = "font_scale",                     type = "number" },
        { key = "bold_text",                      type = "bool" },

        { key = "show_debug_info",                 type = "bool" },
        { key = "show_range_indicator",              type = "bool" },
        { key = "out_of_range_color",                type = "color" },
        { key = "window_transparent",               type = "bool" },

        { key = "show_name_banner",                  type = "bool" },
        { key = "name_banner_font_scale",             type = "number" },
        { key = "name_banner_show_power_cost",        type = "bool" },
        { key = "name_banner_text_color",             type = "color" },
        { key = "name_banner_power_cost_color",       type = "color" },
        { key = "name_banner_background_color",       type = "color" },
        { key = "name_banner_window_transparent",     type = "bool" },
        { key = "name_banner_show_border",            type = "bool" },
        { key = "name_banner_border_color",           type = "color" },
        { key = "name_banner_border_thickness",       type = "number" },
        { key = "name_banner_corner_rounding",          type = "number" },
        { key = "disable_default_ability_bar",     type = "bool" },
    }

    local function GetAbilityBarSettingsFilePath()
        return UiForge.resources_path .. "\\ability_bar_settings.cfg"
    end

    local function SerializeSettingsValue(value, value_type)
        if value_type == "color" then
            return table.concat({ tostring(value[1]), tostring(value[2]), tostring(value[3]), tostring(value[4]) }, ",")
        elseif value_type == "bool" then
            return value and "true" or "false"
        else -- "number" or "string"
            return tostring(value)
        end
    end

    local function ParseSettingsValue(raw_value, value_type)
        if value_type == "color" then
            local components = {}
            for field in tostring(raw_value):gmatch("[^,]+") do
                components[#components + 1] = tonumber(field)
            end
            if #components == 4 and components[1] and components[2] and components[3] and components[4] then
                return components
            end
            return nil
        elseif value_type == "bool" then
            return ParseBool(raw_value)
        elseif value_type == "string" then
            return Trim(raw_value)
        else -- "number"
            return tonumber(raw_value)
        end
    end

    local function BuildSettingsSnapshot()
        local lines = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            lines[#lines + 1] = def.key .. "=" .. SerializeSettingsValue(modern_ability_bar_state[def.key], def.type)
        end
        return table.concat(lines, "\n")
    end

    local function WriteSettingsSnapshotToFile(snapshot)
        local path = GetAbilityBarSettingsFilePath()
        local file = io.open(path, "w")
        if file == nil then
            return false
        end

        file:write("# ability_bar_settings.cfg -- auto-generated. Delete this file to reset to defaults.\n")
        file:write(snapshot)
        file:write("\n")
        file:close()
        return true
    end

    local function SaveAbilityBarSettingsIfChanged()
        local snapshot = BuildSettingsSnapshot()
        if snapshot ~= modern_ability_bar_state._settings_snapshot then
            if WriteSettingsSnapshotToFile(snapshot) then
                modern_ability_bar_state._settings_snapshot = snapshot
            end
        end
    end

    local function LoadAbilityBarSettingsFromFile()
        local path = GetAbilityBarSettingsFilePath()
        local file = io.open(path, "r")
        if file == nil then
            return false -- No saved settings yet; keep the defaults.
        end

        local defs_by_key = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            defs_by_key[def.key] = def.type
        end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
                if key ~= nil and defs_by_key[key] ~= nil then
                    local parsed = ParseSettingsValue(raw_value, defs_by_key[key])
                    if parsed ~= nil then
                        modern_ability_bar_state[key] = parsed
                    end
                end
            end
        end

        file:close()
        modern_ability_bar_state._settings_snapshot = BuildSettingsSnapshot()
        return true
    end

    local function TryLoadAbilityBarSettingsOnce()
        if modern_ability_bar_state.settings_file_loaded == true then return end
        LoadAbilityBarSettingsFromFile()
        modern_ability_bar_state.settings_file_loaded = true
    end

    local function ToggleDefaultAbilityBar()
        if modern_ability_bar_state.disable_default_ability_bar == true then
            return UI.DisableAbilityBar()
        end
        return UI.EnableAbilityBar()
    end

    --[[
    v0.1.1 UPDATE: the elaborate "enable, wait, then disable" startup sequence that used to be
    here is REMOVED. It existed only because UI.DisableAbilityBar()/EnableAbilityBar() gave no
    way to know whether the write actually landed -- so we mimicked the manual "uncheck then
    recheck" workaround with a timed delay as a guess. v0.1.1 fixes this properly: these
    functions now return true/false for whether the write landed, and also cover all THREE
    hotbar windows (compact and expanded) together, which mmvest's release notes say was the
    actual source of "ability bar not disabling properly." Retrying every frame ONLY until
    confirmed true (below, same pattern as every other mod in this pack) replaces the whole
    workaround with something both simpler and more precise.
    ]]

    local function OnDisable()
        -- v0.06+: fires when this script is unchecked in the UiForge menu. Always restore the
        -- native ability bar here, regardless of the "Disable Default Ability Bar" setting.
        UI.EnableAbilityBar()

        -- icon.lua's own documentation recommends releasing cached textures on disable, so they
        -- aren't leaked across script reloads.
        pcall(Icon.ReleaseAll)
    end

    local function Initialize()
        TryLoadAbilityBarSettingsOnce()
        modern_ability_bar_state.initialized = true
    end

    local function Settings()
        local state = modern_ability_bar_state

        ImGui.Text("Layout")
        state.bar_scale = ImGui.SliderFloat("Bar Scale", state.bar_scale, 0.5, 3.0, tostring(state.bar_scale))
        state.slot_size = ImGui.SliderInt("Slot Size", state.slot_size, 20, 100, tostring(state.slot_size))
        state.slot_spacing = ImGui.SliderInt("Slot Spacing", state.slot_spacing, 0, 20, tostring(state.slot_spacing))
        state.bar_spacing = ImGui.SliderInt("Spacing Between Bars", state.bar_spacing, 0, 40, tostring(state.bar_spacing))
        state.info_panel_top_spacing = ImGui.SliderInt("Space Above Info Panel", state.info_panel_top_spacing, 0, 40, tostring(state.info_panel_top_spacing))

        ImGui.Separator()
        ImGui.Text("Slot Appearance")
        state.background_color = ImGui.ColorEdit4("Background Color", state.background_color)
        state.empty_slot_color = ImGui.ColorEdit4("Empty Slot Color", state.empty_slot_color)
        state.item_slot_color = ImGui.ColorEdit4("Item/Toolbelt Slot Color", state.item_slot_color)
        state.show_icon_background_layer = ImGui.Checkbox("Show Icon Background Layer", state.show_icon_background_layer)
        state.show_border = ImGui.Checkbox("Show Border", state.show_border)
        state.border_color = ImGui.ColorEdit4("Border Color", state.border_color)
        state.border_thickness = ImGui.SliderFloat("Border Thickness", state.border_thickness, 0.5, 5.0, tostring(state.border_thickness))
        state.corner_rounding = ImGui.SliderFloat("Corner Rounding", state.corner_rounding, 0, 20, tostring(state.corner_rounding))

        ImGui.Separator()
        ImGui.Text("Navigation")
        ImGui.TextUnformatted("Mirrors the game's own real selection (AbilityBar.GetSelectedBarIndex/")
        ImGui.TextUnformatted("GetSelectedSlotIndex) -- this always matches what will actually cast.")
        state.show_navigation_highlight = ImGui.Checkbox("Show Navigation Highlight", state.show_navigation_highlight)
        state.enable_cooldown_tracking = ImGui.Checkbox("Enable Cooldown Tracking", state.enable_cooldown_tracking)
        ImGui.TextUnformatted("The crash this used to cause is fixed at the source in v1.0 --")
        ImGui.TextUnformatted("every pointer-chain read now validates against EE_RAM_SIZE. Safe")
        ImGui.TextUnformatted("to leave on; the toggle is kept here just in case.")
        state.active_bar_color = ImGui.ColorEdit4("Active Bar Color", state.active_bar_color)
        state.active_bar_thickness = ImGui.SliderFloat("Active Bar Thickness", state.active_bar_thickness, 1.0, 6.0, tostring(state.active_bar_thickness))
        state.active_bar_padding = ImGui.SliderFloat("Active Bar Padding", state.active_bar_padding, 0, 25, tostring(state.active_bar_padding))
        state.selected_slot_color = ImGui.ColorEdit4("Selected Slot Color", state.selected_slot_color)
        state.selected_slot_thickness = ImGui.SliderFloat("Selected Slot Thickness", state.selected_slot_thickness, 1.0, 6.0, tostring(state.selected_slot_thickness))

        ImGui.Separator()
        ImGui.Text("Cooldown")
        state.show_cooldown_overlay = ImGui.Checkbox("Show Cooldown Overlay", state.show_cooldown_overlay)
        state.cooldown_dim_color = ImGui.ColorEdit4("Cooldown Dim Color", state.cooldown_dim_color)
        state.cooldown_text_color = ImGui.ColorEdit4("Cooldown Text Color", state.cooldown_text_color)
        ImGui.TextUnformatted("Countdown is an ESTIMATE (started the moment cooldown begins),")
        ImGui.TextUnformatted("not a live value from the server -- see script notes.")

        ImGui.Separator()
        ImGui.Text("Info Overlays")
        state.show_power_cost = ImGui.Checkbox("Show Power Cost", state.show_power_cost)
        state.power_cost_text_color = ImGui.ColorEdit4("Power Cost Color", state.power_cost_text_color)
        state.show_slot_number = ImGui.Checkbox("Show Slot Number", state.show_slot_number)
        state.slot_number_color = ImGui.ColorEdit4("Slot Number Color", state.slot_number_color)

        ImGui.Separator()
        ImGui.Text("Text")
        state.font_scale = ImGui.SliderFloat("Font Scale", state.font_scale, 0.5, 3.0, tostring(state.font_scale))
        state.bold_text = ImGui.Checkbox("Bold Text", state.bold_text)

        ImGui.Separator()
        state.show_debug_info = ImGui.Checkbox("Show Debug Info (troubleshooting)", state.show_debug_info)

        ImGui.Separator()
        ImGui.Text("Out-of-Range Indicator")
        ImGui.TextUnformatted("Only shown when you have a target selected -- uses Ability:IsInRange()")
        ImGui.TextUnformatted("(new in v1.0). No target means nothing to check range against.")
        state.show_range_indicator = ImGui.Checkbox("Show Out-of-Range Tint", state.show_range_indicator)
        state.out_of_range_color = ImGui.ColorEdit4("Out-of-Range Color", state.out_of_range_color)

        state.window_transparent = ImGui.Checkbox("Window Transparent (only slots have background)", state.window_transparent)

        ImGui.Separator()
        ImGui.Text("Ability Name Banner")
        ImGui.TextUnformatted("A separate, big-font window showing the highlighted ability's name")
        ImGui.TextUnformatted("and power cost. Drag it to position above the ability bar yourself.")
        state.show_name_banner = ImGui.Checkbox("Show Name Banner", state.show_name_banner)
        state.name_banner_font_scale = ImGui.SliderFloat("Banner Font Scale", state.name_banner_font_scale, 1.0, 5.0, tostring(state.name_banner_font_scale))
        state.name_banner_show_power_cost = ImGui.Checkbox("Show Power Cost In Banner", state.name_banner_show_power_cost)
        state.name_banner_text_color = ImGui.ColorEdit4("Banner Text Color", state.name_banner_text_color)
        state.name_banner_power_cost_color = ImGui.ColorEdit4("Banner Power Cost Color", state.name_banner_power_cost_color)
        state.name_banner_background_color = ImGui.ColorEdit4("Banner Background Color", state.name_banner_background_color)
        state.name_banner_window_transparent = ImGui.Checkbox("Banner Window Transparent", state.name_banner_window_transparent)
        state.name_banner_show_border = ImGui.Checkbox("Show Banner Border", state.name_banner_show_border)
        state.name_banner_border_color = ImGui.ColorEdit4("Banner Border Color", state.name_banner_border_color)
        state.name_banner_border_thickness = ImGui.SliderFloat("Banner Border Thickness", state.name_banner_border_thickness, 0.5, 5.0, tostring(state.name_banner_border_thickness))
        state.name_banner_corner_rounding = ImGui.SliderFloat("Banner Corner Rounding", state.name_banner_corner_rounding, 0, 20, tostring(state.name_banner_corner_rounding))

        local new_val, pressed = ImGui.Checkbox("Disable Default Ability Bar", state.disable_default_ability_bar)
        if pressed then
            state.disable_default_ability_bar = new_val
            state.native_toggle_confirmed = ToggleDefaultAbilityBar()
        end

        SaveAbilityBarSettingsIfChanged()
    end

    -- ============================================================================
    -- Navigation (now reads the game's REAL selection state -- see header notes)
    -- ============================================================================

    -- Returns the game's actual selected bar/slot indices, or nil, nil when the UI isn't loaded.
    -- Cache this ONCE per frame at the top of Render() rather than calling it repeatedly --
    -- it's cheap, but there's no reason to re-resolve the same pointer chain many times a frame.
    local function GetRealSelection()
        local bar_index = AbilityBar.GetSelectedBarIndex()
        if bar_index == nil then
            return nil, nil
        end
        local slot_index = AbilityBar.GetSelectedSlotIndex(bar_index)
        return bar_index, slot_index
    end

    -- Returns (player_coords, target_coords) for range checking, or (coords, nil) if you have
    -- no target selected -- computed once per frame and passed down, rather than re-resolved
    -- for every single slot.
    local function GetRangeCheckCoordinates()
        local ok_player, player_coords = pcall(Player.GetCoordinates)
        if not ok_player or player_coords == nil then return nil, nil end

        local ok_target_id, target_id = pcall(Player.GetTargetEntityId)
        if not ok_target_id or target_id == nil or target_id == 0 then return player_coords, nil end

        local ok_target, target_entity = pcall(EntityList.GetEntityById, target_id)
        if not ok_target or target_entity == nil then return player_coords, nil end

        return player_coords, { x = target_entity.x, y = target_entity.y, z = target_entity.z }
    end

    -- ============================================================================
    -- Cooldown tracking (mirrors the pattern from the updated ff_example.lua)
    -- ============================================================================

    cooldown_watch_state = cooldown_watch_state or {}

    local function UpdateCooldownTracking()
        if Util.IsInGame() == 0 then return end

        local now = os.clock()
        for bar_index = 0, AbilityBar.num_bars - 1 do
            for slot_index = 0, AbilityBar.GetSlotCount(bar_index) - 1 do
                local ok, ability = pcall(AbilityBar.GetAbility, bar_index, slot_index)
                if ok and ability ~= nil then
                    local id = ability:GetId()
                    if not ability:IsOnCooldown() then
                        cooldown_watch_state[id] = nil
                    elseif cooldown_watch_state[id] == nil then
                        cooldown_watch_state[id] = now
                    end
                end
            end
        end
    end

    -- Returns remaining seconds (estimated) for an ability on cooldown, or nil if not on cooldown
    -- or we never observed it starting.
    local function GetEstimatedCooldownRemaining(ability)
        if not ability:IsOnCooldown() then return nil end
        local started = cooldown_watch_state[ability:GetId()]
        if started == nil then return nil end
        local elapsed = os.clock() - started
        local remaining = (ability:GetCooldownLockoutMs() / 1000) - elapsed
        if remaining < 0 then remaining = 0 end
        return remaining
    end

    local function BuildAbilityTooltip(ability)
        local ok_name, name = TryCall(ability, "GetName")
        local ok_desc, description = TryCall(ability, "GetDescription")
        local ok_range, range = TryCall(ability, "GetRange")
        local ok_cast, cast_time = TryCall(ability, "GetCastTime")
        local ok_cost, pwr_cost = TryCall(ability, "GetPwrCost")
        local ok_cd, cooldown = TryCall(ability, "GetCooldown")
        local ok_on_cd, on_cooldown = TryCall(ability, "IsOnCooldown")

        local lines = { ok_name and name or "Unknown Ability" }
        if ok_desc and description ~= nil and description ~= "" then
            lines[#lines + 1] = description
        end
        lines[#lines + 1] = "Power Cost: " .. (ok_cost and tostring(pwr_cost) or "?")
        lines[#lines + 1] = "Cast Time: " .. (ok_cast and tostring(cast_time) or "?")
        lines[#lines + 1] = "Range: " .. (ok_range and tostring(range) or "?")
        lines[#lines + 1] = "Base Cooldown: " .. (ok_cd and tostring(cooldown) or "?")

        if ok_on_cd and on_cooldown then
            local remaining = GetEstimatedCooldownRemaining(ability)
            if remaining ~= nil then
                lines[#lines + 1] = string.format("On Cooldown: ~%.1fs remaining (estimated)", remaining)
            else
                lines[#lines + 1] = "On Cooldown (remaining time not yet observed)"
            end
        end

        return table.concat(lines, "\n")
    end

    -- ============================================================================
    -- Rendering
    -- ============================================================================

    local function DrawSlot(state, bar_index, slot_index, scaled_slot_size, selected_bar_index, selected_slot_index, player_coords, target_coords)
        local is_selected = state.show_navigation_highlight
            and selected_bar_index == bar_index
            and selected_slot_index == slot_index

        local draw_list = ImGui.GetWindowDrawList()
        local slot_origin_x, slot_origin_y = ImGui.GetCursorScreenPos()
        local slot_p0 = ImVec2.new(slot_origin_x, slot_origin_y)
        local slot_p1 = ImVec2.new(slot_origin_x + scaled_slot_size, slot_origin_y + scaled_slot_size)

        local ok_slot, ability_slot = pcall(AbilityBar.GetAbilitySlot, bar_index, slot_index)
        if not ok_slot then ability_slot = nil end

        local ability = nil
        local bg_texture, fg_texture = nil, nil
        local debug_text = nil
        local is_non_ability_item = false -- true for slots holding something OTHER than an ability (e.g. a toolbelt item/weapon) -- see notes below

        -- Bar index 2 (the third bar) is the toolbelt/special-items bar. Its slot icons are a
        -- STATIC PER-POSITION PLACEHOLDER (the game's own "this slot accepts potions" glyph) shown
        -- regardless of whether anything is assigned -- unlike ability slots, which only ever show
        -- an icon once something occupies them. So this lookup deliberately runs BEFORE and
        -- independent of the IsEmpty() check below, only for this one bar.
        --
        -- NOTE: an earlier attempt tried resolving the SPECIFIC assigned item (reading source_index
        -- as an inventory slot number) to override this placeholder with the item's own icon.
        -- CONFIRMED WRONG by testing -- it resolved to a real item, just not the correct one, which
        -- is worse than the honest placeholder. Reverted; this placeholder-only version is the
        -- confirmed-correct state.
        if bar_index == 2 then
            local ok_tex_id, tex_id = pcall(AbilityBar.GetSlotUITexId, slot_index)
            if ok_tex_id and tex_id ~= nil then
                local ok_ui_tex, ui_tex = pcall(Icon.GetUITexture, tex_id)
                if ok_ui_tex and ui_tex ~= nil then
                    fg_texture = ui_tex
                elseif debug_text == nil then
                    debug_text = "Icon.GetUITexture failed: " .. tostring(ui_tex)
                end
            elseif debug_text == nil then
                debug_text = "AbilityBar.GetSlotUITexId returned nil for this slot position"
            end
        end

        if ability_slot ~= nil then
            local ok_empty, is_empty = TryCall(ability_slot, "IsEmpty")
            if ok_empty and not is_empty then
                local ok_ability, ability_result = TryCall(ability_slot, "GetAbility")
                if ok_ability then
                    ability = ability_result
                elseif debug_text == nil then
                    debug_text = "GetAbility failed: " .. tostring(ability_result)
                end

                -- A slot can hold something (not IsEmpty) while GetAbility() still returns nil --
                -- this happens for toolbelt/item slots, which use a different source_type than the
                -- ability list. Still no NAME available for these anywhere in the API (the
                -- source_index -> inventory-slot mapping was tested and confirmed wrong).
                if ability == nil then
                    is_non_ability_item = true
                end

                -- Icons are decoded straight from game memory via the Icon module and are layered:
                -- a background piece plus a foreground piece drawn on top, matching how the game
                -- itself composites hotbar/spellbook icons. Both refs live on the resolved Ability
                -- object.
                if ability ~= nil then
                    local ok_bg_ref, bg_ref = TryCall(ability, "GetIconBackgroundRef")
                    local ok_fg_ref, fg_ref = TryCall(ability, "GetIconForegroundRef")

                    if ok_bg_ref then
                        local ok_bg_tex, bg_tex = pcall(Icon.GetTexture, bg_ref, { trim_transparent = true, trim_color = true })
                        if ok_bg_tex then
                            bg_texture = bg_tex
                        elseif debug_text == nil then
                            debug_text = "Icon.GetTexture (background) failed: " .. tostring(bg_tex)
                        end
                    end

                    if ok_fg_ref then
                        local ok_fg_tex, fg_tex = pcall(Icon.GetTexture, fg_ref, { trim_transparent = true, trim_color = true })
                        if ok_fg_tex then
                            fg_texture = fg_tex
                        elseif debug_text == nil then
                            debug_text = "Icon.GetTexture (foreground) failed: " .. tostring(fg_tex)
                        end
                    end
                elseif fg_texture == nil then
                    -- Toolbelt/item slot and the bar-2 lookup above didn't get a texture (e.g. this
                    -- somehow isn't bar 2, or that lookup failed) -- fall back to the per-slot ref.
                    local ok_slot_ref, slot_ref = TryCall(ability_slot, "GetIconRef")
                    if ok_slot_ref then
                        local ok_tex, tex = pcall(Icon.GetTexture, slot_ref, { trim_transparent = true, trim_color = true })
                        if ok_tex then
                            fg_texture = tex
                        elseif debug_text == nil then
                            debug_text = "Icon.GetTexture (slot) failed: " .. tostring(tex)
                        end
                    end
                end
            end
        else
            debug_text = "GetAbilitySlot returned nil or errored"
        end

        -- Background
        local bg_color = state.empty_slot_color
        if ability ~= nil then
            bg_color = state.background_color
        elseif is_non_ability_item then
            bg_color = state.item_slot_color
        end
        local bg_color_u32 = ImGui.GetColorU32(bg_color[1], bg_color[2], bg_color[3], bg_color[4])
        draw_list:AddRectFilled(slot_p0, slot_p1, bg_color_u32, state.corner_rounding)

        -- Icon layers, both stretched to fill the slot uniformly (falls back to an invisible
        -- placeholder of the same size if neither layer is available).
        local drew_icon = false
        if state.show_icon_background_layer and bg_texture ~= nil then
            local cursor_x, cursor_y = ImGui.GetCursorPos()
            local ok_draw = pcall(ImGui.Image, bg_texture, scaled_slot_size, scaled_slot_size)
            if ok_draw then
                drew_icon = true
                ImGui.SetCursorPos(cursor_x, cursor_y)
            elseif debug_text == nil then
                debug_text = "ImGui.Image failed on the background texture"
            end
        end
        if fg_texture ~= nil then
            local ok_draw = pcall(ImGui.Image, fg_texture, scaled_slot_size, scaled_slot_size)
            if ok_draw then
                drew_icon = true
            elseif debug_text == nil then
                debug_text = "ImGui.Image failed on the foreground texture"
            end
        end
        if not drew_icon then
            ImGui.Dummy(scaled_slot_size, scaled_slot_size)
        end

        -- Cooldown overlay: dims the icon and shows an estimated countdown
        if state.show_cooldown_overlay and ability ~= nil then
            local ok_on_cd, on_cooldown = TryCall(ability, "IsOnCooldown")
            if ok_on_cd and on_cooldown then
                local dim_color_u32 = ImGui.GetColorU32(state.cooldown_dim_color[1], state.cooldown_dim_color[2], state.cooldown_dim_color[3], state.cooldown_dim_color[4])
                draw_list:AddRectFilled(slot_p0, slot_p1, dim_color_u32, state.corner_rounding)

                local remaining = GetEstimatedCooldownRemaining(ability)
                if remaining ~= nil then
                    local cd_text = remaining >= 10 and string.format("%.0f", remaining) or string.format("%.1f", remaining)
                    local cd_text_width, cd_text_height = ImGui.CalcTextSize(cd_text)
                    local cd_color_u32 = ImGui.GetColorU32(state.cooldown_text_color[1], state.cooldown_text_color[2], state.cooldown_text_color[3], state.cooldown_text_color[4])
                    draw_list:AddText(ImVec2.new(slot_origin_x + (scaled_slot_size - cd_text_width) / 2, slot_origin_y + (scaled_slot_size - cd_text_height) / 2), cd_color_u32, cd_text)
                end
            end
        end

        -- Out-of-range overlay: only shown when you actually have a target selected -- with no
        -- target there's nothing to check range against, so abilities render normally.
        local is_out_of_range = false
        if state.show_range_indicator and ability ~= nil and player_coords ~= nil and target_coords ~= nil then
            local ok_range, in_range = pcall(function() return ability:IsInRange(player_coords, target_coords) end)
            if ok_range and in_range == false then
                is_out_of_range = true
            end
        end
        if is_out_of_range then
            local range_color_u32 = ImGui.GetColorU32(state.out_of_range_color[1], state.out_of_range_color[2], state.out_of_range_color[3], state.out_of_range_color[4])
            draw_list:AddRectFilled(slot_p0, slot_p1, range_color_u32, state.corner_rounding)
        end

        if ImGui.IsItemHovered() then
            if ability ~= nil then
                local tooltip_text = BuildAbilityTooltip(ability)
                if is_out_of_range then
                    tooltip_text = tooltip_text .. "\nOut of range"
                end
                ImGui.SetTooltip(tooltip_text)
            elseif state.show_debug_info and debug_text ~= nil then
                ImGui.SetTooltip(debug_text)
            elseif state.show_debug_info and is_non_ability_item then
                -- Debug info IS on, there just wasn't an error to report -- the icon lookup
                -- succeeded (that's why fg_texture is set and drew_icon is true). Previously this
                -- fell through to a message telling you to "enable Show Debug Info" even though it
                -- was already on, which was confusing/wrong. Report the actual status instead.
                ImGui.SetTooltip(drew_icon and "Item/Toolbelt Slot -- icon resolved fine, no error" or "Item/Toolbelt Slot -- no icon and no error recorded (unexpected)")
            elseif is_non_ability_item then
                ImGui.SetTooltip("Item/Toolbelt Slot (not empty -- enable Show Debug Info for details)")
            else
                ImGui.SetTooltip("Empty Slot")
            end
        end

        if state.show_border then
            local border_color_u32 = ImGui.GetColorU32(state.border_color[1], state.border_color[2], state.border_color[3], state.border_color[4])
            draw_list:AddRect(slot_p0, slot_p1, border_color_u32, state.corner_rounding, 0, state.border_thickness)
        end

        -- Navigation cursor highlight, drawn on top of the normal border
        if is_selected then
            local sel_color_u32 = ImGui.GetColorU32(state.selected_slot_color[1], state.selected_slot_color[2], state.selected_slot_color[3], state.selected_slot_color[4])
            draw_list:AddRect(slot_p0, slot_p1, sel_color_u32, state.corner_rounding, 0, state.selected_slot_thickness)
        end

        if state.show_slot_number then
            local label = tostring(slot_index + 1)
            local label_color_u32 = ImGui.GetColorU32(state.slot_number_color[1], state.slot_number_color[2], state.slot_number_color[3], state.slot_number_color[4])
            draw_list:AddText(ImVec2.new(slot_p0.x + 2, slot_p0.y + 2), label_color_u32, label)
        end

        if is_non_ability_item and not drew_icon then
            -- Only shown as a last-resort fallback now -- v1.0's AbilityBar.GetSlotUITexId() +
            -- Icon.GetUITexture() usually gets a real icon for these slots (see the icon-fetching
            -- section above), so this text label only appears if that somehow didn't resolve.
            local item_label = "ITEM"
            local item_text_width, item_text_height = ImGui.CalcTextSize(item_label)
            local item_color_u32 = ImGui.GetColorU32(1, 1, 1, 0.85)
            draw_list:AddText(ImVec2.new(slot_origin_x + (scaled_slot_size - item_text_width) / 2, slot_origin_y + (scaled_slot_size - item_text_height) / 2), item_color_u32, item_label)
        end

        if state.show_power_cost and ability ~= nil then
            local ok_cost, pwr_cost = TryCall(ability, "GetPwrCost")
            if ok_cost and pwr_cost ~= nil then
                local cost_text = tostring(pwr_cost)
                local text_width, text_height = ImGui.CalcTextSize(cost_text)
                local cost_color_u32 = ImGui.GetColorU32(state.power_cost_text_color[1], state.power_cost_text_color[2], state.power_cost_text_color[3], state.power_cost_text_color[4])
                draw_list:AddText(ImVec2.new(slot_p1.x - text_width - 2, slot_p1.y - text_height - 2), cost_color_u32, cost_text)
            end
        end

        if state.show_debug_info and debug_text ~= nil then
            local warning_color_u32 = ImGui.GetColorU32(1, 0.3, 0.3, 1)
            draw_list:AddText(ImVec2.new(slot_p0.x + 2, slot_p1.y - 14), warning_color_u32, "!")
        end
    end

    local function DrawBar(state, bar_index, scaled_slot_size, selected_bar_index, selected_slot_index, player_coords, target_coords)
        local slot_count = AbilityBar.GetSlotCount(bar_index)
        local is_active_bar = state.show_navigation_highlight and selected_bar_index == bar_index

        local bar_origin_x, bar_origin_y = ImGui.GetCursorScreenPos()

        ImGui.BeginGroup()
        for slot_index = 0, slot_count - 1 do
            if slot_index > 0 and state.slot_spacing > 0 then
                ImGui.Dummy(1, state.slot_spacing)
            end
            DrawSlot(state, bar_index, slot_index, scaled_slot_size, selected_bar_index, selected_slot_index, player_coords, target_coords)
        end
        ImGui.EndGroup()
        local _, bar_end_y = ImGui.GetCursorScreenPos()

        if is_active_bar then
            local draw_list = ImGui.GetWindowDrawList()
            local active_color_u32 = ImGui.GetColorU32(state.active_bar_color[1], state.active_bar_color[2], state.active_bar_color[3], state.active_bar_color[4])
            local bar_width = scaled_slot_size
            -- Measured directly from the cursor's actual position after drawing, rather than
            -- calculated from slot_count * scaled_slot_size + gaps -- that formula didn't account
            -- for ImGui's own automatic spacing between widgets (added on top of our explicit
            -- gaps), which made the border fall short of the last slot.
            local bar_height = bar_end_y - bar_origin_y
            local vertical_pad = state.active_bar_padding * state.bar_scale
            -- Horizontal padding is capped separately from vertical: active_bar_padding scales with
            -- bar_scale, but the gap between bars (bar_spacing) does NOT -- at larger icon sizes the
            -- padding could exceed that gap entirely, making the border spill into the neighboring
            -- bar's icons. Capping to half the gap (minus a small margin) guarantees it never does,
            -- while top/bottom keep the full requested padding since there's no neighbor there.
            local horizontal_pad = math.min(vertical_pad, math.max(state.bar_spacing / 2 - 1, 0))
            draw_list:AddRect(
                ImVec2.new(bar_origin_x - horizontal_pad, bar_origin_y - vertical_pad),
                ImVec2.new(bar_origin_x + bar_width + horizontal_pad, bar_origin_y + bar_height + vertical_pad),
                active_color_u32, state.corner_rounding + 2, 0, state.active_bar_thickness)
        end
    end

    -- Builds a plain-text (not tooltip) description of whatever the D-pad cursor is currently on,
    -- since hover tooltips are useless for controller-only navigation -- there's no mouse to hover
    -- with. This is shown as a permanent panel in the window instead.
    local function BuildHighlightedSlotInfo(state, bar_index, slot_index)
        if bar_index == nil or slot_index == nil then
            return "(game UI not loaded)"
        end

        local ok_slot, ability_slot = pcall(AbilityBar.GetAbilitySlot, bar_index, slot_index)
        if not ok_slot or ability_slot == nil then
            return "Bar " .. (bar_index + 1) .. ", Slot " .. (slot_index + 1) .. ": (no data)"
        end

        local ok_empty, is_empty = TryCall(ability_slot, "IsEmpty")
        if ok_empty and is_empty then
            return "Bar " .. (bar_index + 1) .. ", Slot " .. (slot_index + 1) .. ": Empty"
        end

        local ok_ability, ability = TryCall(ability_slot, "GetAbility")
        if ok_ability and ability ~= nil then
            return BuildAbilityTooltip(ability)
        end

        -- Known limitation: toolbelt/item slots (a different source_type than the ability list)
        -- don't currently expose a name anywhere in the API. (An earlier attempt tried reading
        -- source_index as an inventory slot number -- confirmed wrong by testing, removed.)
        local base_text = "Bar " .. (bar_index + 1) .. ", Slot " .. (slot_index + 1) .. ": Item/Toolbelt slot (name not yet available)"

        if not state.show_debug_info then
            return base_text
        end

        -- Same diagnostic DrawSlot runs for the mouse-hover tooltip, duplicated here so it's
        -- readable by following the D-Pad cursor alone -- this whole bar is controller-navigated,
        -- so a mouse-only diagnostic is a poor fit.
        local ok_tex_id, tex_id = pcall(AbilityBar.GetSlotUITexId, slot_index)
        if not ok_tex_id or tex_id == nil then
            return base_text .. "\nDEBUG: AbilityBar.GetSlotUITexId returned nil for this slot position"
        end
        local ok_ui_tex, ui_tex = pcall(Icon.GetUITexture, tex_id)
        if not ok_ui_tex or ui_tex == nil then
            return base_text .. string.format("\nDEBUG: GetSlotUITexId=%s, but Icon.GetUITexture failed: %s", tostring(tex_id), tostring(ui_tex))
        end
        return base_text .. string.format("\nDEBUG: GetSlotUITexId=%s resolved fine -- if no icon is showing, the issue is in ImGui.Image itself", tostring(tex_id))
    end

    -- Just the name + power cost, for the big banner (as opposed to BuildHighlightedSlotInfo's
    -- full multi-line tooltip-style text used in the bottom info panel).
    local function GetHighlightedNameAndCost(bar_index, slot_index)
        if bar_index == nil or slot_index == nil then
            return "(game UI not loaded)", nil
        end

        local ok_slot, ability_slot = pcall(AbilityBar.GetAbilitySlot, bar_index, slot_index)
        if not ok_slot or ability_slot == nil then
            return "(no data)", nil
        end

        local ok_empty, is_empty = TryCall(ability_slot, "IsEmpty")
        if ok_empty and is_empty then
            return "Empty", nil
        end

        local ok_ability, ability = TryCall(ability_slot, "GetAbility")
        if ok_ability and ability ~= nil then
            local ok_name, name = TryCall(ability, "GetName")
            local ok_cost, cost = TryCall(ability, "GetPwrCost")
            return (ok_name and name or "Unknown Ability"), (ok_cost and cost or nil)
        end

        -- Known limitation: same as BuildHighlightedSlotInfo -- toolbelt/item slots have no name
        -- exposed anywhere in the API yet.
        return "Item/Toolbelt (name not yet available)", nil
    end

    local function DrawNameBanner(state)
        if Util.IsInGame() == 0 or Util.IsStartMenuOpen() == 1 then return end
        if state.show_name_banner ~= true then return end

        local window_flags = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoTitleBar
        if state.name_banner_window_transparent then window_flags = window_flags + ImGuiWindowFlags.NoBackground end

        if ImGui.Begin("Ability Name Banner", true, window_flags) then
            local selected_bar_index, selected_slot_index = GetRealSelection()
            local name, cost = GetHighlightedNameAndCost(selected_bar_index, selected_slot_index)

            local origin_x, origin_y = ImGui.GetCursorScreenPos()
            local draw_list = ImGui.GetWindowDrawList()

            ImGui.SetWindowFontScale(state.name_banner_font_scale)
            local name_width, name_height = ImGui.CalcTextSize(name)

            local cost_text = nil
            local cost_width, cost_height = 0, 0
            if state.name_banner_show_power_cost and cost ~= nil then
                cost_text = "Power Cost: " .. tostring(cost)
                cost_width, cost_height = ImGui.CalcTextSize(cost_text)
            end

            local content_width = math.max(name_width, cost_width)
            local content_height = name_height + (cost_text ~= nil and cost_height or 0)
            local padding = 10

            if state.name_banner_background_color[4] > 0 or state.name_banner_show_border then
                local bg_color_u32 = ImGui.GetColorU32(state.name_banner_background_color[1], state.name_banner_background_color[2], state.name_banner_background_color[3], state.name_banner_background_color[4])
                draw_list:AddRectFilled(
                    ImVec2.new(origin_x - padding, origin_y - padding),
                    ImVec2.new(origin_x + content_width + padding, origin_y + content_height + padding),
                    bg_color_u32, state.name_banner_corner_rounding)

                if state.name_banner_show_border then
                    local border_color_u32 = ImGui.GetColorU32(state.name_banner_border_color[1], state.name_banner_border_color[2], state.name_banner_border_color[3], state.name_banner_border_color[4])
                    draw_list:AddRect(
                        ImVec2.new(origin_x - padding, origin_y - padding),
                        ImVec2.new(origin_x + content_width + padding, origin_y + content_height + padding),
                        border_color_u32, state.name_banner_corner_rounding, 0, state.name_banner_border_thickness)
                end
            end

            local name_color_u32 = ImGui.GetColorU32(state.name_banner_text_color[1], state.name_banner_text_color[2], state.name_banner_text_color[3], state.name_banner_text_color[4])
            draw_list:AddText(ImVec2.new(origin_x, origin_y), name_color_u32, name)

            if cost_text ~= nil then
                local cost_color_u32 = ImGui.GetColorU32(state.name_banner_power_cost_color[1], state.name_banner_power_cost_color[2], state.name_banner_power_cost_color[3], state.name_banner_power_cost_color[4])
                draw_list:AddText(ImVec2.new(origin_x, origin_y + name_height), cost_color_u32, cost_text)
            end

            -- Reserve the actual space so the window sizes itself correctly around the manually-
            -- drawn text above (draw_list calls don't advance the layout cursor on their own).
            ImGui.Dummy(content_width, content_height)
        end
        ImGui.End()
    end

    local function Render()
        local state = modern_ability_bar_state

        if Util.IsInGame() == 0 or Util.IsStartMenuOpen() == 1 then return end

        -- Removes the window's own default fill when "Window Transparent" is on -- our own slot
        -- backgrounds are drawn explicitly regardless and stay visible either way.
        local window_flags = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoTitleBar
        if state.window_transparent then window_flags = window_flags + ImGuiWindowFlags.NoBackground end

        if ImGui.Begin("modern ability bar window", true, window_flags) then
            ImGui.SetWindowFontScale(state.font_scale)

            local scaled_slot_size = state.slot_size * state.bar_scale
            local selected_bar_index, selected_slot_index = GetRealSelection()
            local player_coords, target_coords = GetRangeCheckCoordinates()

            -- The active-bar border (drawn in DrawBar) extends active_bar_padding pixels above
            -- the topmost icon and below the bottom icon of whichever bar is currently active.
            -- Since this window uses AlwaysAutoResize (sizes tightly to the normal widget
            -- layout), that overhang isn't accounted for on its own -- the top portion gets
            -- clipped by the window's own edge, and the bottom edge looks disconnected from the
            -- content. Reserving this space explicitly, once, fixes both.
            local border_overhang = 0
            if state.show_navigation_highlight then
                border_overhang = state.active_bar_padding * state.bar_scale
            end
            if border_overhang > 0 then
                ImGui.Dummy(1, border_overhang)
            end

            for bar_index = 0, AbilityBar.num_bars - 1 do
                if bar_index > 0 then
                    ImGui.SameLine(0, state.bar_spacing)
                end
                DrawBar(state, bar_index, scaled_slot_size, selected_bar_index, selected_slot_index, player_coords, target_coords)
            end

            if border_overhang > 0 then
                ImGui.Dummy(1, border_overhang)
            end

            if state.show_navigation_highlight then
                if state.info_panel_top_spacing > 0 then
                    ImGui.Dummy(1, state.info_panel_top_spacing)
                end
                ImGui.Separator()
                ImGui.PushTextWrapPos(0.0)
                ImGui.TextUnformatted(BuildHighlightedSlotInfo(state, selected_bar_index, selected_slot_index))
                ImGui.PopTextWrapPos()
            end
        end
        ImGui.End()
    end


    -- Creating a local variable to interact with the global table so that the name is shorter/easier to use

    local function Update()
        if modern_ability_bar_state.initialized == false then Initialize() end

        -- Cooldown tracking still runs regardless of window visibility, so estimates stay correct
        -- even if you're not looking at the bar. v1.0: the crash this used to cause is fixed at the
        -- source (every pointer-chain read in the framework now validates against EE_RAM_SIZE before
        -- touching it). Back on by default; the toggle is kept just in case.
        if modern_ability_bar_state.enable_cooldown_tracking then
            UpdateCooldownTracking()
        end

        -- v0.1.1: retry only until confirmed (see the note on ToggleDefaultAbilityBar above) --
        -- replaces the old startup-sequence workaround now that we have a real success signal.
        if modern_ability_bar_state.native_toggle_confirmed ~= true then
            modern_ability_bar_state.native_toggle_confirmed = ToggleDefaultAbilityBar()
        end

        if modern_ability_bar_state.initialized then Render() end
        if modern_ability_bar_state.initialized then DrawNameBanner(modern_ability_bar_state) end
    end

    ModPack = ModPack or {}
    ModPack.AbilityBar = {
        display_name = "Ability Bar",
        Update = Update,
        Settings = Settings,
        OnDisable = OnDisable,
    }
end
-- ============================================================================
-- MOD: Chat Log
-- ============================================================================
do
    local UI = require("frontiers_forge.ui")                -- Access UI elements
    local Util = require("frontiers_forge.util")            -- Access Utility functions
    local Chat = require("frontiers_forge.chat")            -- Access chat messages
    local Input = require("frontiers_forge.input")           -- Intercept Enter + suppress it -- for typing directly into this window (v0.1.1 pattern)

    --[[
    Modern Chat Log

    Chat.GetNextMessage() is non-blocking and only ever returns the newest message once (it
    internally tracks the last-returned message ID), so this script polls it every frame and
    builds its own scrollback history in memory, capped at max_messages entries.

    This window has a normal title bar (movable/resizable) and, since it doesn't have a close (X)
    button, "Show Chat Log" in the settings tab is the on/off toggle -- defaulting to visible,
    since a chat log is normally something you want up at all times.

    Channel visibility/colors are controlled per-channel (Say/Shout/Party/Tell/Guild/Unknown).
    Quick toggles live directly in the chat window itself; colors and other appearance options
    live in the settings tab.
    ]]
    modern_chat_log_state = modern_chat_log_state or {
        initialized                 = false,
        callbacks_registered         = false,
        native_toggle_confirmed      = false, -- v0.1.1: tracks whether the native chat window disable/enable write has actually landed yet

        -- Custom chat input: mirrors mmvest's own ff_example.lua demo pattern exactly (Enter
        -- suppressed via Input's key hook, typed text sent through Chat.SendChatText so it goes
        -- through the game's own send path, slash commands and all). Off by default -- this
        -- takes over your Enter key, so it's an explicit opt-in, not an automatic behavior change.
        enable_custom_chat_input       = false,
        chat_input_mode_index           = 0, -- index into CHAT_INPUT_MODES below

        -- Settings persistence (message HISTORY itself is intentionally not persisted -- a fresh
        -- log each session is expected, same as the game's own chat window)
        settings_file_loaded        = false,
        _settings_snapshot          = "",

        messages                    = {},   -- accumulated {text, type_string, timestamp} entries
        max_messages                = 200,

        show_chat_log                = true,
        disable_in_start_menu        = false,
        -- Default true: hides the native chat window (avoiding duplicate chat displays), since the
        -- underlying rendering glitch this used to cause is fixed as of the corrected ui.lua that
        -- properly skips BeginDraw/EndDraw together via a branch instruction, instead of NOP'ing
        -- BeginDraw alone. If you're on an older/unpatched ui.lua, set this to false instead -- see
        -- the note in the settings panel below.
        disable_default_chat_window  = true,

        -- Display options
        show_timestamps              = true,
        word_wrap                    = true,
        auto_scroll                  = true,   -- step 1: always snaps to newest message (not yet "smart" about manual scroll-up -- see Render())
        font_scale                   = 1.0,
        bold_text                    = false,

        -- Panel appearance
        background_color             = {0.05, 0.05, 0.05, 0.75},
        show_border                  = true,
        window_transparent           = false,   -- removes the window's own default opaque fill (title bar stays visible/movable)
        border_color                 = {0, 0, 0, 1},
        border_thickness             = 1.5,
        corner_rounding               = 4,

        -- Per-channel visibility
        show_say                    = true,
        show_shout                  = true,
        show_party                  = true,
        show_tell                   = true,
        show_guild                  = true,
        show_unknown                 = true,

        -- Per-channel colors
        say_color                   = {1.0, 1.0, 1.0, 1.0},     -- white
        shout_color                  = {1.0, 0.35, 0.2, 1.0},   -- orange-red
        party_color                  = {0.4, 0.7, 1.0, 1.0},    -- blue
        tell_color                   = {0.9, 0.4, 0.9, 1.0},    -- pink/purple
        guild_color                  = {0.4, 1.0, 0.5, 1.0},    -- green
        unknown_color                 = {0.7, 0.7, 0.7, 1.0},   -- gray
    }

    local function Trim(str)
        if str == nil then return "" end
        return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseBool(value)
        value = Trim(value):lower()
        return (value == "true" or value == "1" or value == "yes" or value == "on")
    end

    --[[
    Settings persistence

    Saves/loads the settings below to "resources\\chat_log_settings.cfg" (directly under the
    resources folder, since we don't ship a dedicated resources subfolder for this script).
    ]]
    local PERSISTED_SETTINGS = {
        { key = "max_messages",                 type = "number" },
        { key = "show_chat_log",                type = "bool" },
        { key = "disable_in_start_menu",         type = "bool" },
        { key = "disable_default_chat_window",  type = "bool" },
        { key = "enable_custom_chat_input",       type = "bool" },
        { key = "chat_input_mode_index",           type = "number" },

        { key = "show_timestamps",              type = "bool" },
        { key = "word_wrap",                    type = "bool" },
        { key = "auto_scroll",                  type = "bool" },
        { key = "font_scale",                   type = "number" },
        { key = "bold_text",                    type = "bool" },

        { key = "background_color",             type = "color" },
        { key = "show_border",                  type = "bool" },
        { key = "window_transparent",           type = "bool" },
        { key = "border_color",                 type = "color" },
        { key = "border_thickness",             type = "number" },
        { key = "corner_rounding",               type = "number" },

        { key = "show_say",                     type = "bool" },
        { key = "show_shout",                   type = "bool" },
        { key = "show_party",                   type = "bool" },
        { key = "show_tell",                    type = "bool" },
        { key = "show_guild",                   type = "bool" },
        { key = "show_unknown",                  type = "bool" },

        { key = "say_color",                    type = "color" },
        { key = "shout_color",                   type = "color" },
        { key = "party_color",                   type = "color" },
        { key = "tell_color",                    type = "color" },
        { key = "guild_color",                   type = "color" },
        { key = "unknown_color",                  type = "color" },
    }

    local function GetChatLogSettingsFilePath()
        return UiForge.resources_path .. "\\chat_log_settings.cfg"
    end

    local function SerializeSettingsValue(value, value_type)
        if value_type == "color" then
            return table.concat({ tostring(value[1]), tostring(value[2]), tostring(value[3]), tostring(value[4]) }, ",")
        elseif value_type == "bool" then
            return value and "true" or "false"
        else -- "number"
            return tostring(value)
        end
    end

    local function ParseSettingsValue(raw_value, value_type)
        if value_type == "color" then
            local components = {}
            for field in tostring(raw_value):gmatch("[^,]+") do
                components[#components + 1] = tonumber(field)
            end
            if #components == 4 and components[1] and components[2] and components[3] and components[4] then
                return components
            end
            return nil
        elseif value_type == "bool" then
            return ParseBool(raw_value)
        else -- "number"
            return tonumber(raw_value)
        end
    end

    local function BuildSettingsSnapshot()
        local lines = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            lines[#lines + 1] = def.key .. "=" .. SerializeSettingsValue(modern_chat_log_state[def.key], def.type)
        end
        return table.concat(lines, "\n")
    end

    local function WriteSettingsSnapshotToFile(snapshot)
        local path = GetChatLogSettingsFilePath()
        local file = io.open(path, "w")
        if file == nil then
            return false
        end

        file:write("# chat_log_settings.cfg -- auto-generated. Delete this file to reset the chat log to defaults.\n")
        file:write(snapshot)
        file:write("\n")
        file:close()
        return true
    end

    local function SaveChatLogSettingsIfChanged()
        local snapshot = BuildSettingsSnapshot()
        if snapshot ~= modern_chat_log_state._settings_snapshot then
            if WriteSettingsSnapshotToFile(snapshot) then
                modern_chat_log_state._settings_snapshot = snapshot
            end
        end
    end

    local function LoadChatLogSettingsFromFile()
        local path = GetChatLogSettingsFilePath()
        local file = io.open(path, "r")
        if file == nil then
            return false -- No saved settings yet; keep the defaults.
        end

        local defs_by_key = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            defs_by_key[def.key] = def.type
        end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
                if key ~= nil and defs_by_key[key] ~= nil then
                    local parsed = ParseSettingsValue(raw_value, defs_by_key[key])
                    if parsed ~= nil then
                        modern_chat_log_state[key] = parsed
                    end
                end
            end
        end

        file:close()
        modern_chat_log_state._settings_snapshot = BuildSettingsSnapshot()
        return true
    end

    local function TryLoadChatLogSettingsOnce()
        if modern_chat_log_state.settings_file_loaded == true then return end
        LoadChatLogSettingsFromFile()
        modern_chat_log_state.settings_file_loaded = true
    end

    -- Real wall-clock time if the OS clock is reachable from this Lua environment; otherwise falls
    -- back to a session-relative "minutes:seconds since script start" using ImGui's own clock.
    local function GetTimestampString()
        local ok_date, ts = pcall(os.date, "%H:%M:%S")
        if ok_date and ts ~= nil then return ts end

        local ok_time, elapsed = pcall(ImGui.GetTime)
        if ok_time and type(elapsed) == "number" then
            local total_seconds = math.floor(elapsed)
            local minutes = math.floor(total_seconds / 60)
            local seconds = total_seconds % 60
            return string.format("%d:%02d", minutes, seconds)
        end

        return "??:??"
    end

    local function ChannelVisible(state, type_string)
        if type_string == "Say" then return state.show_say end
        if type_string == "Shout" then return state.show_shout end
        if type_string == "Party" then return state.show_party end
        if type_string == "Tell" then return state.show_tell end
        if type_string == "Guild" then return state.show_guild end
        return state.show_unknown
    end

    local function GetColorForType(state, type_string)
        if type_string == "Say" then return state.say_color end
        if type_string == "Shout" then return state.shout_color end
        if type_string == "Party" then return state.party_color end
        if type_string == "Tell" then return state.tell_color end
        if type_string == "Guild" then return state.guild_color end
        return state.unknown_color
    end

    local function ToggleDefaultChatWindow()
        if modern_chat_log_state.disable_default_chat_window == true then
            return UI.DisableChatWindow()
        end
        return UI.EnableChatWindow()
    end

    --[[
    Custom chat input -- mirrors mmvest's own ff_example.lua demo pattern exactly (his own
    stated motivation for building the input-hook system in the first place: typing into a
    mod's own window instead of the game's native chat popup). This is copied as closely as
    possible to his tested version rather than reimplemented independently, since it involves
    keyboard hooks and a send hook -- not the place to improvise.

    Two hooks make this work:
      * Input.InstallKeyHook() lets us observe keys and suppress Enter specifically, so the
        game's own typing window never opens.
      * Chat.InstallSendHook() lets Chat.SendChatText hand the message to the game's own chat
        sender on the next frame, so the outbound packet is exactly what typing in the native
        chat window would produce (slash commands and all).
    ]]
    custom_chat_input_state = custom_chat_input_state or {
        capturing = false,          -- key hook installed and Enter owned by us
        box_active = false,         -- our ImGui chat box is open
        focus_pending = false,      -- give the box keyboard focus on the next drawn frame
        text = "",                  -- message being composed
        last_sent = nil,
        last_error = nil,
        next_retry_time = 0,        -- os.clock() value; don't retry a failed install before this
    }

    -- Selectable chat modes, same as the demo. Typing an explicit /command in the message
    -- overrides this, exactly like typing into the native chat box would.
    local CHAT_INPUT_MODES = {
        { name = "Default", prefix = Chat.ChatMode.Default },
        { name = "Say",     prefix = Chat.ChatMode.Say },
        { name = "Group",   prefix = Chat.ChatMode.Group },
        { name = "Guild",   prefix = Chat.ChatMode.Guild },
        { name = "Shout",   prefix = Chat.ChatMode.Shout },
    }

    local function SendCustomChatText()
        local text = custom_chat_input_state.text
        if text == "" then return end

        local mode = CHAT_INPUT_MODES[modern_chat_log_state.chat_input_mode_index + 1].prefix
        local ok, err = Chat.SendChatText(text, mode)
        if ok then
            custom_chat_input_state.last_sent = text
            custom_chat_input_state.last_error = nil
            custom_chat_input_state.text = ""
        else
            custom_chat_input_state.last_error = err
        end
    end

    -- Forward-declared: UpdateCustomChatCapture (below) needs to call StartCustomChatCapture
    -- (defined further below) to retry a failed hook install -- this keeps it a proper local
    -- instead of accidentally leaking a global.
    local StartCustomChatCapture

    -- Runs every frame while capturing so the key ring buffer never overruns, even when the
    -- chat log window itself is hidden. The only key acted on is Enter: it opens the box and
    -- moves keyboard focus to it -- everything else is ImGui's own text-editing job.
    local function UpdateCustomChatCapture()
        if not custom_chat_input_state.capturing then
            -- Found by comparing against another mod's implementation of this same pattern:
            -- our first attempt at installing the key hook could fail silently (e.g. the game
            -- isn't fully ready yet) with no retry at all, leaving the setting showing "enabled"
            -- while nothing was actually capturing. Retry on a slow clock (not every frame,
            -- since a failing install shouldn't be hammered constantly) whenever the setting
            -- wants capturing on but it hasn't actually started yet.
            if modern_chat_log_state.enable_custom_chat_input and os.clock() >= custom_chat_input_state.next_retry_time then
                StartCustomChatCapture()
            end
            return
        end
        if not Input.IsKeyHookInstalled() then
            return
        end

        for _, event in ipairs(Input.PollKeyEvents()) do
            if event.is_down and event.key == Input.Key.Enter and not custom_chat_input_state.box_active then
                custom_chat_input_state.box_active = true
                custom_chat_input_state.focus_pending = true
            end
        end
    end

    function StartCustomChatCapture()
        local ok, err = Input.InstallKeyHook()
        if not ok then
            custom_chat_input_state.last_error = err
            custom_chat_input_state.next_retry_time = os.clock() + 2
            return
        end
        ok, err = Chat.InstallSendHook()
        if not ok then
            custom_chat_input_state.last_error = err
            custom_chat_input_state.next_retry_time = os.clock() + 2
            return
        end

        Input.SetKeySuppressed(Input.Key.Enter, true)
        custom_chat_input_state.capturing = true
        custom_chat_input_state.last_error = nil
    end

    local function StopCustomChatCapture()
        -- Give the keyboard back to the game entirely: unsuppress Enter, then remove both
        -- hooks so the patched instructions are restored and the caves zeroed.
        if Input.IsKeyHookInstalled() then
            Input.SetKeySuppressed(Input.Key.Enter, false)
        end
        Input.UninstallKeyHook()
        Chat.UninstallSendHook()
        custom_chat_input_state.capturing = false
        custom_chat_input_state.box_active = false
        custom_chat_input_state.focus_pending = false
    end

    -- Draws the input box (and mode selector) at the bottom of the chat window, only while a
    -- message is actively being composed.
    local function DrawCustomChatInput()
        if not modern_chat_log_state.enable_custom_chat_input then return end

        ImGui.Separator()

        for i, m in ipairs(CHAT_INPUT_MODES) do
            if i > 1 then ImGui.SameLine() end
            modern_chat_log_state.chat_input_mode_index = ImGui.RadioButton(m.name, modern_chat_log_state.chat_input_mode_index, i - 1)
        end

        if not custom_chat_input_state.box_active then
            ImGui.TextUnformatted("Press Enter to type a message.")
        else
            if custom_chat_input_state.focus_pending then
                ImGui.SetKeyboardFocusHere()
                custom_chat_input_state.focus_pending = false
            end
            local entered
            custom_chat_input_state.text, entered = ImGui.InputText("##custom_chat_message",
                custom_chat_input_state.text, ImGuiInputTextFlags.EnterReturnsTrue)
            if entered then
                SendCustomChatText()
                custom_chat_input_state.box_active = false
            end
            ImGui.SameLine()
            if ImGui.Button("Cancel") then
                custom_chat_input_state.text = ""
                custom_chat_input_state.box_active = false
            end
        end

        if custom_chat_input_state.last_error ~= nil then
            ImGui.TextUnformatted("error: " .. tostring(custom_chat_input_state.last_error))
        end
    end

    local function Initialize()
        TryLoadChatLogSettingsOnce()
        modern_chat_log_state.initialized = true
    end

    local function Settings()
        local state = modern_chat_log_state

        state.show_chat_log = ImGui.Checkbox("Show Chat Log", state.show_chat_log)
        state.disable_in_start_menu = ImGui.Checkbox("Hide While Start Menu Is Open", state.disable_in_start_menu)

        ImGui.Separator()
        ImGui.Text("History")
        state.max_messages = ImGui.SliderInt("Max Stored Messages", state.max_messages, 20, 500, tostring(state.max_messages))

        ImGui.Separator()
        ImGui.Text("Display")
        state.show_timestamps = ImGui.Checkbox("Show Timestamps", state.show_timestamps)
        state.word_wrap = ImGui.Checkbox("Word Wrap", state.word_wrap)
        state.auto_scroll = ImGui.Checkbox("Auto-Scroll To Newest", state.auto_scroll)
        state.font_scale = ImGui.SliderFloat("Font Scale", state.font_scale, 0.5, 3.0, tostring(state.font_scale))
        state.bold_text = ImGui.Checkbox("Bold Text", state.bold_text)

        ImGui.Separator()
        ImGui.Text("Panel Appearance")
        state.background_color = ImGui.ColorEdit4("Background Color", state.background_color)
        state.show_border = ImGui.Checkbox("Show Border", state.show_border)
        state.window_transparent = ImGui.Checkbox("Window Transparent", state.window_transparent)
        state.border_color = ImGui.ColorEdit4("Border Color", state.border_color)
        state.border_thickness = ImGui.SliderFloat("Border Thickness", state.border_thickness, 0.5, 6.0, tostring(state.border_thickness))
        state.corner_rounding = ImGui.SliderFloat("Corner Rounding", state.corner_rounding, 0, 20, tostring(state.corner_rounding))

        ImGui.Separator()
        ImGui.Text("Channels")
        state.show_say = ImGui.Checkbox("Show Say", state.show_say)
        state.say_color = ImGui.ColorEdit4("Say Color", state.say_color)
        state.show_shout = ImGui.Checkbox("Show Shout", state.show_shout)
        state.shout_color = ImGui.ColorEdit4("Shout Color", state.shout_color)
        state.show_party = ImGui.Checkbox("Show Party", state.show_party)
        state.party_color = ImGui.ColorEdit4("Party Color", state.party_color)
        state.show_tell = ImGui.Checkbox("Show Tell", state.show_tell)
        state.tell_color = ImGui.ColorEdit4("Tell Color", state.tell_color)
        state.show_guild = ImGui.Checkbox("Show Guild", state.show_guild)
        state.guild_color = ImGui.ColorEdit4("Guild Color", state.guild_color)
        state.show_unknown = ImGui.Checkbox("Show Unknown", state.show_unknown)
        state.unknown_color = ImGui.ColorEdit4("Unknown Color", state.unknown_color)

        ImGui.Separator()
        ImGui.TextUnformatted("NOTE: This requires the corrected ui.lua (fixed BeginDraw/EndDraw")
        ImGui.TextUnformatted("handling for the chat window). If shout messages render as a")
        ImGui.TextUnformatted("floating panel near your target, uncheck this and update ui.lua.")
        local new_val, pressed = ImGui.Checkbox("Disable Default Chat Window", state.disable_default_chat_window)
        if pressed then
            state.disable_default_chat_window = new_val
            state.native_toggle_confirmed = ToggleDefaultChatWindow()
        end

        ImGui.Separator()
        ImGui.Text("Custom Chat Input")
        ImGui.TextUnformatted("Type directly into this window instead of opening the game's own")
        ImGui.TextUnformatted("chat popup -- press Enter in-game to compose, Enter again to send.")
        ImGui.TextUnformatted("This takes over your Enter key while enabled.")
        local input_new_val, input_pressed = ImGui.Checkbox("Enable Custom Chat Input", state.enable_custom_chat_input)
        if input_pressed then
            state.enable_custom_chat_input = input_new_val
            if input_new_val then
                StartCustomChatCapture()
            else
                StopCustomChatCapture()
            end
        end
        if state.enable_custom_chat_input then
            ImGui.TextUnformatted("Capturing: " .. tostring(custom_chat_input_state.capturing))
        end

        SaveChatLogSettingsIfChanged()
    end

    local function OnDisable()
        -- v0.06: fires when this script is unchecked in the UiForge menu. Without this, disabling
        -- the script would leave the default chat window hidden with no way to bring it back short
        -- of restarting the game -- so always restore it here, regardless of the
        -- "Disable Default Chat Window" setting.
        UI.EnableChatWindow()

        -- Critical: if custom chat input is active, this releases the keyboard hook and gives
        -- Enter back to the game. Without this, disabling the mod would leave Enter permanently
        -- suppressed for the rest of the session.
        if custom_chat_input_state.capturing then
            StopCustomChatCapture()
        end
    end

    -- Returns a plain data table of every user customizable option, built directly from
    -- PERSISTED_SETTINGS so the profile save and the on-disk .cfg file can never drift apart.
    -- UiForge captures this into the profile on File > Save Profile and hands it back to Load
    -- when a profile is applied. Message history itself is intentionally never saved -- a fresh
    -- log each session is expected, same as the game's own chat window.
    local function Save()
        local state = modern_chat_log_state
        local saved = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            saved[def.key] = state[def.key]
        end
        return saved
    end

    -- Copies a saved value into state only when its type matches the current value,
    -- so a hand edited or stale profile cannot corrupt the state table.
    local function ApplySavedValue(saved, key)
        local state = modern_chat_log_state
        if saved[key] ~= nil and type(saved[key]) == type(state[key]) then
            state[key] = saved[key]
        end
    end

    local function Load(saved)
        if type(saved) ~= "table" then return end

        for _, def in ipairs(PERSISTED_SETTINGS) do
            ApplySavedValue(saved, def.key)
        end

        -- Reapply the chat window patch unconditionally. Disabling the script (or applying
        -- another profile) restores the game's chat window via OnDisable WITHOUT changing this
        -- setting, so the in-game UI can be out of sync with the saved value even when the two
        -- compare equal. Resetting the confirmed flag lets Update's per-frame retry reapply it.
        modern_chat_log_state.native_toggle_confirmed = false

        -- Keep the on-disk .cfg file in sync with whatever profile was just applied, so the two
        -- persistence systems (profile vs. per-launch file) never disagree.
        SaveChatLogSettingsIfChanged()
    end

    local function Render()
        local state = modern_chat_log_state

        if Util.IsInGame() == 0 then return end
        if state.disable_in_start_menu and Util.IsStartMenuOpen() == 1 then return end

        -- Poll for new messages every frame regardless of window visibility, so history keeps
        -- accumulating even while the log is hidden.
        local msg_contents, msg_type = Chat.GetNextMessage()
        if msg_contents ~= "" then
            table.insert(state.messages, {
                text = msg_contents,
                type_string = Chat.GetMessageTypeString(msg_type),
                timestamp = GetTimestampString(),
            })
            while #state.messages > state.max_messages do
                table.remove(state.messages, 1)
            end
        end

        if state.show_chat_log ~= true then return end

        -- Removes the window's own default opaque fill when "Window Transparent" is on. Title bar
        -- stays visible/movable either way since NoTitleBar isn't part of this flag.
        local chat_window_flags = 0
        if state.window_transparent then chat_window_flags = ImGuiWindowFlags.NoBackground end

        if ImGui.Begin("Chat Log", true, chat_window_flags) then
            ImGui.SetWindowFontScale(state.font_scale)

            -- Quick per-channel toggles, right in the window for fast access
            state.show_say = ImGui.Checkbox("Say", state.show_say)
            ImGui.SameLine()
            state.show_shout = ImGui.Checkbox("Shout", state.show_shout)
            ImGui.SameLine()
            state.show_party = ImGui.Checkbox("Party", state.show_party)
            ImGui.SameLine()
            state.show_tell = ImGui.Checkbox("Tell", state.show_tell)
            ImGui.SameLine()
            state.show_guild = ImGui.Checkbox("Guild", state.show_guild)

            ImGui.Separator()

            -- Messages are drawn directly in the main window (no BeginChild/EndChild -- an earlier
            -- version used a scrollable child region here, but it triggered a native ImGui
            -- assertion crash on first use, so this sticks to the same plain Begin/End pattern
            -- already proven stable in every other script). The window scrolls on its own once
            -- content overflows it -- resize the window if you want to see more lines at once.
            --
            -- Background is drawn per-line (a band behind each message, sized to that line's own
            -- height) rather than as one panel measured upfront. An earlier version measured the
            -- background once at the top of the window, before any messages were laid out -- once
            -- the chat log grew taller than that one-time measurement, everything past it had no
            -- background at all, causing a visible "solid background fades to fully transparent"
            -- seam partway down the window. Drawing it fresh behind each line avoids that entirely,
            -- since it always matches however much content actually exists.
            local avail_width = ImGui.GetContentRegionAvail()
            local draw_list = ImGui.GetWindowDrawList()

            for _, msg in ipairs(state.messages) do
                if ChannelVisible(state, msg.type_string) then
                    local color = GetColorForType(state, msg.type_string)

                    local line = ""
                    if state.show_timestamps then
                        line = "[" .. msg.timestamp .. "] "
                    end
                    line = line .. "[" .. msg.type_string .. "] " .. msg.text

                    if state.show_border or state.background_color[4] > 0 then
                        local line_origin_x, line_origin_y = ImGui.GetCursorScreenPos()
                        -- NOTE: deliberately NOT passing a wrap_width here. An earlier attempt at
                        -- that used ImGui.CalcTextSize(line, nil, false, wrap_width) to also account
                        -- for wrapped multi-line height, but passing nil for the "ending" parameter
                        -- triggered a hard crash (a Begin/End window-stack assertion, meaning the
                        -- call errored out mid-frame before reaching ImGui.End()) -- the same failure
                        -- class as the earlier BeginChild/Begin(nil, ...) issues elsewhere in this
                        -- project. This single-argument form is the same safe pattern used
                        -- everywhere else. Tradeoff: wrapped (multi-line) messages may get a
                        -- background band that's a bit short -- cosmetic only, not a crash risk.
                        local _, line_text_height = ImGui.CalcTextSize(line)
                        local bg_color_u32 = ImGui.GetColorU32(state.background_color[1], state.background_color[2], state.background_color[3], state.background_color[4])
                        draw_list:AddRectFilled(ImVec2.new(line_origin_x, line_origin_y), ImVec2.new(line_origin_x + avail_width, line_origin_y + line_text_height), bg_color_u32, state.corner_rounding)
                        if state.show_border then
                            local border_color_u32 = ImGui.GetColorU32(state.border_color[1], state.border_color[2], state.border_color[3], state.border_color[4])
                            draw_list:AddRect(ImVec2.new(line_origin_x, line_origin_y), ImVec2.new(line_origin_x + avail_width, line_origin_y + line_text_height), border_color_u32, state.corner_rounding, 0, state.border_thickness)
                        end
                    end

                    ImGui.PushStyleColor(ImGuiCol.Text, color[1], color[2], color[3], color[4])
                    if state.word_wrap then ImGui.PushTextWrapPos(0.0) end

                    if state.bold_text then
                        -- No bold font is available to load from Lua, so this fakes it by
                        -- drawing the line a second time, one pixel over, to thicken it.
                        local cursor_x, cursor_y = ImGui.GetCursorPos()
                        ImGui.SetCursorPos(cursor_x + state.font_scale, cursor_y)
                        ImGui.TextUnformatted(line)
                        ImGui.SetCursorPos(cursor_x, cursor_y)
                    end
                    ImGui.TextUnformatted(line)

                    if state.word_wrap then ImGui.PopTextWrapPos() end
                    ImGui.PopStyleColor()
                end
            end

            -- Step 1 of auto-scroll: always snap to the newest message every frame, using only
            -- SetScrollHereY (deliberately not yet combined with GetScrollY/GetScrollMaxY, so this
            -- introduces exactly one new, previously-untested function at a time after the earlier
            -- BeginChild-related crash). This always follows the bottom -- it doesn't yet respect
            -- you having manually scrolled up to read history. Once confirmed stable, step 2 will
            -- add that "only follow if you were already at the bottom" behavior back in.
            if state.auto_scroll then
                ImGui.SetScrollHereY(1.0)
            end

            DrawCustomChatInput()
        end
        ImGui.End()
    end

    local function Update()
        if modern_chat_log_state.initialized == false then Initialize() end

        if modern_chat_log_state.native_toggle_confirmed ~= true then
            modern_chat_log_state.native_toggle_confirmed = ToggleDefaultChatWindow()
        end

        -- Runs every frame regardless of window visibility, same as the official demo, so the
        -- key ring buffer never overruns even while the chat log window itself is hidden.
        UpdateCustomChatCapture()

        if modern_chat_log_state.initialized then Render() end
    end

    ModPack = ModPack or {}
    ModPack.ChatLog = {
        display_name = "Chat Log",
        Update = Update,
        Settings = Settings,
        OnDisable = OnDisable,
        Save = Save,
        Load = Load,
    }
end
-- ============================================================================
-- MOD: Group Frames
-- ============================================================================
do
    local UI = require("frontiers_forge.ui")                -- Access UI elements
    local Util = require("frontiers_forge.util")            -- Access Utility functions
    local Player = require("frontiers_forge.player")        -- Identify "self" among group members, own coordinates
    local Group = require("frontiers_forge.group")          -- Access group member data

    --[[
    Modern Group Frames

    HONEST LIMITATION: group members only expose a HEALTH PERCENTAGE (0-255 raw, converted to
    0-100 here), not real current/max HP numbers -- there's no equivalent to Player.GetCurrentHp()/
    GetMaxHp() for other group members anywhere in the API. So "80/100" for a member here is really
    their percentage scaled to 100, not a true max-HP value, unlike your own health bar script which
    has real numbers. Styled to match visually (bar + fraction text), just built on different data.

    Also per group.lua's own comment: the member array includes the local player as one of its
    entries. This script filters "yourself" out of the list by default (identified by name match
    against Player.GetName(), since there's no direct entity-id cross-reference exposed) since you
    already have a dedicated health bar -- toggle "Include Myself In List" to show yourself too.

    Pets: there's no separate pet module anywhere in the API -- but per your own observation, a
    summoned pet occupies a regular group member slot, so it's already covered here with no extra
    work needed.
    ]]
    modern_group_frames_state = modern_group_frames_state or {
        initialized                 = false,
        callbacks_registered         = false,

        -- Settings persistence
        settings_file_loaded        = false,
        _settings_snapshot          = "",

        show_group_frames             = true,  -- master toggle -- the panel only actually shows when this AND Group.IsInGroup() are both true
        disable_in_start_menu         = false,
        include_self_in_list          = false,

        -- Appearance
        background_color              = {0.08, 0.08, 0.08, 0.85},
        show_border                   = true,
        border_color                  = {0, 0, 0, 1},
        border_thickness              = 1.5,
        corner_rounding                 = 6,
        font_scale                    = 1.0,
        bold_text                     = false,

        -- Health bar
        bar_width                     = 180,
        bar_height                    = 22,
        health_fill_color              = {0.2, 0.85, 0.2, 1.0},
        low_health_color                = {0.9, 0.2, 0.2, 1.0},
        low_health_threshold_percent     = 30,
        health_bar_bg_color             = {0.15, 0.15, 0.15, 1.0},
        show_health_text                = true,
        health_text_format               = "percent_100", -- "percent_100" shows "80/100", "percent" shows "80%"

        -- Inactive (out of range / not currently tracked) members
        show_inactive_members            = true,
        inactive_alpha                  = 0.4,

        -- Distance
        show_distance                  = true,
        far_away_threshold              = 500, -- beyond this, just show "Far Away" instead of a specific number
        distance_text_color              = {0.7, 0.7, 0.7, 1.0},

        -- Leader
        show_leader_indicator            = true,
        leader_indicator_color            = {1.0, 0.85, 0.2, 1.0},

        -- Header
        show_member_count_header          = true,

        show_debug_info                 = false, -- shows raw Group.IsInGroup()/GetMemberCount() even when the panel would otherwise auto-hide, for troubleshooting

        disable_default_group_display     = true,
        window_transparent                = true,  -- removes the window's own background; name/health bar keep their own dark backing
    }

    local function Trim(str)
        if str == nil then return "" end
        return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseBool(value)
        value = Trim(value):lower()
        return (value == "true" or value == "1" or value == "yes" or value == "on")
    end

    --[[
    Settings persistence
    ]]
    local PERSISTED_SETTINGS = {
        { key = "show_group_frames",              type = "bool" },
        { key = "disable_in_start_menu",           type = "bool" },
        { key = "include_self_in_list",            type = "bool" },

        { key = "background_color",               type = "color" },
        { key = "show_border",                    type = "bool" },
        { key = "border_color",                   type = "color" },
        { key = "border_thickness",               type = "number" },
        { key = "corner_rounding",                  type = "number" },
        { key = "font_scale",                     type = "number" },
        { key = "bold_text",                      type = "bool" },

        { key = "bar_width",                      type = "number" },
        { key = "bar_height",                     type = "number" },
        { key = "health_fill_color",               type = "color" },
        { key = "low_health_color",                 type = "color" },
        { key = "low_health_threshold_percent",       type = "number" },
        { key = "health_bar_bg_color",               type = "color" },
        { key = "show_health_text",                  type = "bool" },
        { key = "health_text_format",                type = "string" },

        { key = "show_inactive_members",             type = "bool" },
        { key = "inactive_alpha",                   type = "number" },

        { key = "show_distance",                   type = "bool" },
        { key = "far_away_threshold",                type = "number" },
        { key = "distance_text_color",               type = "color" },

        { key = "show_leader_indicator",             type = "bool" },
        { key = "leader_indicator_color",             type = "color" },

        { key = "show_member_count_header",           type = "bool" },
        { key = "show_debug_info",                   type = "bool" },

        { key = "disable_default_group_display",      type = "bool" },
        { key = "window_transparent",                  type = "bool" },
    }

    local function GetGroupFramesSettingsFilePath()
        return UiForge.resources_path .. "\\group_frames_settings.cfg"
    end

    local function SerializeSettingsValue(value, value_type)
        if value_type == "color" then
            return table.concat({ tostring(value[1]), tostring(value[2]), tostring(value[3]), tostring(value[4]) }, ",")
        elseif value_type == "bool" then
            return value and "true" or "false"
        else -- "number" or "string"
            return tostring(value)
        end
    end

    local function ParseSettingsValue(raw_value, value_type)
        if value_type == "color" then
            local components = {}
            for field in tostring(raw_value):gmatch("[^,]+") do
                components[#components + 1] = tonumber(field)
            end
            if #components == 4 and components[1] and components[2] and components[3] and components[4] then
                return components
            end
            return nil
        elseif value_type == "bool" then
            return ParseBool(raw_value)
        elseif value_type == "string" then
            return Trim(raw_value)
        else -- "number"
            return tonumber(raw_value)
        end
    end

    local function BuildSettingsSnapshot()
        local lines = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            lines[#lines + 1] = def.key .. "=" .. SerializeSettingsValue(modern_group_frames_state[def.key], def.type)
        end
        return table.concat(lines, "\n")
    end

    local function WriteSettingsSnapshotToFile(snapshot)
        local file = io.open(GetGroupFramesSettingsFilePath(), "w")
        if file == nil then return false end
        file:write("# group_frames_settings.cfg -- auto-generated. Delete this file to reset to defaults.\n")
        file:write(snapshot)
        file:write("\n")
        file:close()
        return true
    end

    local function SaveGroupFramesSettingsIfChanged()
        local snapshot = BuildSettingsSnapshot()
        if snapshot ~= modern_group_frames_state._settings_snapshot then
            if WriteSettingsSnapshotToFile(snapshot) then
                modern_group_frames_state._settings_snapshot = snapshot
            end
        end
    end

    local function LoadGroupFramesSettingsFromFile()
        local file = io.open(GetGroupFramesSettingsFilePath(), "r")
        if file == nil then return false end

        local defs_by_key = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            defs_by_key[def.key] = def.type
        end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
                if key ~= nil and defs_by_key[key] ~= nil then
                    local parsed = ParseSettingsValue(raw_value, defs_by_key[key])
                    if parsed ~= nil then
                        modern_group_frames_state[key] = parsed
                    end
                end
            end
        end

        file:close()
        modern_group_frames_state._settings_snapshot = BuildSettingsSnapshot()
        return true
    end

    local function TryLoadGroupFramesSettingsOnce()
        if modern_group_frames_state.settings_file_loaded == true then return end
        LoadGroupFramesSettingsFromFile()
        modern_group_frames_state.settings_file_loaded = true
    end

    local function ToggleDefaultGroupDisplay()
        if modern_group_frames_state.disable_default_group_display == true then
            UI.DisableGroupDisplay()
            return
        end
        UI.EnableGroupDisplay()
    end

    local function OnDisable()
        -- v0.06+: fires when this script is unchecked in the UiForge menu. Always restore the
        -- native group display here, regardless of the "Disable Default Group Display" setting.
        UI.EnableGroupDisplay()
    end

    local function Initialize()
        TryLoadGroupFramesSettingsOnce()
        modern_group_frames_state.initialized = true
    end

    local function Settings()
        local state = modern_group_frames_state

        state.show_group_frames = ImGui.Checkbox("Show Group Frames", state.show_group_frames)
        ImGui.TextUnformatted("(Only actually shows while you're in a group, regardless of this.)")
        state.disable_in_start_menu = ImGui.Checkbox("Hide While Start Menu Is Open", state.disable_in_start_menu)
        state.include_self_in_list = ImGui.Checkbox("Include Myself In List", state.include_self_in_list)

        ImGui.Separator()
        ImGui.Text("Appearance")
        state.background_color = ImGui.ColorEdit4("Background Color", state.background_color)
        state.show_border = ImGui.Checkbox("Show Border", state.show_border)
        state.border_color = ImGui.ColorEdit4("Border Color", state.border_color)
        state.border_thickness = ImGui.SliderFloat("Border Thickness", state.border_thickness, 0.5, 5.0, tostring(state.border_thickness))
        state.corner_rounding = ImGui.SliderFloat("Corner Rounding", state.corner_rounding, 0, 20, tostring(state.corner_rounding))
        state.font_scale = ImGui.SliderFloat("Font Scale", state.font_scale, 0.5, 3.0, tostring(state.font_scale))
        state.bold_text = ImGui.Checkbox("Bold Text", state.bold_text)

        ImGui.Separator()
        ImGui.Text("Health Bar")
        ImGui.TextUnformatted("NOTE: group members only expose a health PERCENTAGE, not real HP")
        ImGui.TextUnformatted("numbers -- \"X/100\" below means X percent, scaled to 100, not a")
        ImGui.TextUnformatted("true max HP value like your own health bar has.")
        state.bar_width = ImGui.SliderInt("Bar Width", state.bar_width, 80, 400, tostring(state.bar_width))
        state.bar_height = ImGui.SliderInt("Bar Height", state.bar_height, 10, 50, tostring(state.bar_height))
        state.health_fill_color = ImGui.ColorEdit4("Health Fill Color", state.health_fill_color)
        state.low_health_color = ImGui.ColorEdit4("Low Health Color", state.low_health_color)
        state.low_health_threshold_percent = ImGui.SliderInt("Low Health Threshold (%)", state.low_health_threshold_percent, 0, 100, tostring(state.low_health_threshold_percent))
        state.health_bar_bg_color = ImGui.ColorEdit4("Health Bar Background", state.health_bar_bg_color)
        state.show_health_text = ImGui.Checkbox("Show Health Text", state.show_health_text)

        if ImGui.RadioButton("Format: 80/100", state.health_text_format == "percent_100") then
            state.health_text_format = "percent_100"
        end
        ImGui.SameLine()
        if ImGui.RadioButton("Format: 80%", state.health_text_format == "percent") then
            state.health_text_format = "percent"
        end

        ImGui.Separator()
        ImGui.Text("Inactive Members")
        ImGui.TextUnformatted("A member is \"inactive\" when the game isn't currently tracking them")
        ImGui.TextUnformatted("(e.g. out of range) -- their health/position may be stale.")
        state.show_inactive_members = ImGui.Checkbox("Show Inactive Members", state.show_inactive_members)
        state.inactive_alpha = ImGui.SliderFloat("Inactive Opacity", state.inactive_alpha, 0.1, 1.0, tostring(state.inactive_alpha))

        ImGui.Separator()
        ImGui.Text("Distance")
        state.show_distance = ImGui.Checkbox("Show Distance", state.show_distance)
        state.far_away_threshold = ImGui.SliderInt("Far Away Threshold", state.far_away_threshold, 50, 2000, tostring(state.far_away_threshold))
        state.distance_text_color = ImGui.ColorEdit4("Distance Text Color", state.distance_text_color)

        ImGui.Separator()
        ImGui.Text("Leader")
        state.show_leader_indicator = ImGui.Checkbox("Show Leader Indicator (only detects if YOU are leader)", state.show_leader_indicator)
        state.leader_indicator_color = ImGui.ColorEdit4("Leader Indicator Color", state.leader_indicator_color)

        ImGui.Separator()
        state.show_member_count_header = ImGui.Checkbox("Show Member Count Header", state.show_member_count_header)
        state.show_debug_info = ImGui.Checkbox("Show Debug Info (troubleshooting)", state.show_debug_info)

        ImGui.Separator()
        state.window_transparent = ImGui.Checkbox("Window Transparent (only text/bars have background)", state.window_transparent)
        local new_val, pressed = ImGui.Checkbox("Disable Default Group Display", state.disable_default_group_display)
        if pressed then
            state.disable_default_group_display = new_val
            ToggleDefaultGroupDisplay()
        end

        SaveGroupFramesSettingsIfChanged()
    end

    local function GetHealthColor(state, health_percent)
        if health_percent ~= nil and health_percent <= state.low_health_threshold_percent then
            return state.low_health_color
        end
        return state.health_fill_color
    end

    local function DrawHealthBar(state, health_percent, alpha_multiplier)
        local draw_list = ImGui.GetWindowDrawList()
        local origin_x, origin_y = ImGui.GetCursorScreenPos()
        local p0 = ImVec2.new(origin_x, origin_y)
        local p1 = ImVec2.new(origin_x + state.bar_width, origin_y + state.bar_height)

        local bg_color = state.health_bar_bg_color
        local bg_color_u32 = ImGui.GetColorU32(bg_color[1], bg_color[2], bg_color[3], bg_color[4] * alpha_multiplier)
        draw_list:AddRectFilled(p0, p1, bg_color_u32, state.corner_rounding)

        if health_percent ~= nil then
            local fill_color = GetHealthColor(state, health_percent)
            local fill_color_u32 = ImGui.GetColorU32(fill_color[1], fill_color[2], fill_color[3], fill_color[4] * alpha_multiplier)
            local fill_width = state.bar_width * math.max(math.min(health_percent, 100), 0) / 100
            if fill_width > 0 then
                draw_list:AddRectFilled(p0, ImVec2.new(origin_x + fill_width, origin_y + state.bar_height), fill_color_u32, state.corner_rounding)
            end
        end

        if state.show_border then
            local border_color_u32 = ImGui.GetColorU32(state.border_color[1], state.border_color[2], state.border_color[3], state.border_color[4] * alpha_multiplier)
            draw_list:AddRect(p0, p1, border_color_u32, state.corner_rounding, 0, state.border_thickness)
        end

        if state.show_health_text then
            local text
            if health_percent == nil then
                text = "?"
            elseif state.health_text_format == "percent" then
                text = string.format("%.0f%%", health_percent)
            else
                text = string.format("%.0f/100", health_percent)
            end
            local text_width, text_height = ImGui.CalcTextSize(text)
            local text_color_u32 = ImGui.GetColorU32(1, 1, 1, alpha_multiplier)
            draw_list:AddText(ImVec2.new(origin_x + (state.bar_width - text_width) / 2, origin_y + (state.bar_height - text_height) / 2), text_color_u32, text)
        end

        ImGui.Dummy(state.bar_width, state.bar_height)
    end

    local function GetDistanceText(state, member)
        local ok_coords, member_coords = pcall(function() return member:GetCoordinates() end)
        if not ok_coords or member_coords == nil then return nil end

        local ok_player_coords, player_coords = pcall(Player.GetCoordinates)
        if not ok_player_coords or player_coords == nil then return nil end

        local dx = member_coords.x - player_coords.x
        local dz = member_coords.z - player_coords.z
        local distance = math.sqrt(dx * dx + dz * dz)

        if distance > state.far_away_threshold then
            return "Far Away"
        end
        return string.format("%.0fm", distance)
    end

    local function Render()
        local state = modern_group_frames_state

        if Util.IsInGame() == 0 then return end
        if state.disable_in_start_menu and Util.IsStartMenuOpen() == 1 then return end

        -- Shown regardless of the auto-hide logic below, specifically to troubleshoot cases where
        -- the main panel isn't appearing when you expect it to (e.g. with a pet summoned but no
        -- other real party member) -- this tells us exactly what the game itself is reporting.
        if state.show_debug_info then
            if ImGui.Begin("Group Frames Debug") then
                local ok_in_group, in_group = pcall(Group.IsInGroup)
                local ok_count, count = pcall(Group.GetMemberCount)
                local ok_leader, is_leader = pcall(Group.IsSelfLeader)
                ImGui.TextUnformatted("IsInGroup(): " .. (ok_in_group and tostring(in_group) or "ERROR: " .. tostring(in_group)))
                ImGui.TextUnformatted("GetMemberCount(): " .. (ok_count and tostring(count) or "ERROR: " .. tostring(count)))
                ImGui.TextUnformatted("IsSelfLeader(): " .. (ok_leader and tostring(is_leader) or "ERROR: " .. tostring(is_leader)))
            end
            ImGui.End()
        end

        if state.show_group_frames ~= true then return end
        if not Group.IsInGroup() then return end -- auto-hide entirely when not grouped

        local self_name = nil
        if not state.include_self_in_list then
            local ok_name, name = pcall(Player.GetName)
            if ok_name then self_name = name end
        end

        local window_flags = 0
        if state.window_transparent then window_flags = ImGuiWindowFlags.NoBackground end

        if ImGui.Begin("Group Frames", true, window_flags) then
            ImGui.SetWindowFontScale(state.font_scale)

            local draw_list = ImGui.GetWindowDrawList()

            if state.show_member_count_header then
                local count = Group.GetMemberCount()
                local header = "Group (" .. count .. ")"
                if state.show_leader_indicator and Group.IsSelfLeader() then
                    header = header .. "  [You are the Leader]"
                end

                -- Drawn manually (not ImGui.Text) so it gets its own dark background chip -- needed
                -- since the window itself has no background when window_transparent is on.
                local header_origin_x, header_origin_y = ImGui.GetCursorScreenPos()
                local header_width, header_height = ImGui.CalcTextSize(header)
                local chip_padding = 3
                local chip_color_u32 = ImGui.GetColorU32(0, 0, 0, 0.7)
                draw_list:AddRectFilled(
                    ImVec2.new(header_origin_x - chip_padding, header_origin_y - chip_padding),
                    ImVec2.new(header_origin_x + header_width + chip_padding, header_origin_y + header_height + chip_padding),
                    chip_color_u32, state.corner_rounding)
                draw_list:AddText(ImVec2.new(header_origin_x, header_origin_y), ImGui.GetColorU32(1, 1, 1, 1), header)
                ImGui.Dummy(header_width, header_height)
                ImGui.Separator()
            end

            local drew_any = false
            for _, member in Group.Members() do
                local ok_name, name = pcall(function() return member:GetName() end)
                name = (ok_name and name ~= nil and name ~= "") and name or "(unknown)"

                local is_self = (self_name ~= nil and name == self_name)
                if not is_self then
                    local ok_active, is_active = pcall(function() return member:IsActive() end)
                    is_active = ok_active and is_active

                    if is_active or state.show_inactive_members then
                        drew_any = true
                        local alpha_multiplier = is_active and 1.0 or state.inactive_alpha

                        local distance_text = nil
                        if state.show_distance then
                            distance_text = GetDistanceText(state, member)
                        end

                        -- Name + distance drawn manually as one combined chip, same reasoning as
                        -- the header above -- gives the whole line one dark background regardless
                        -- of window transparency, while keeping distance in its own color.
                        local line_origin_x, line_origin_y = ImGui.GetCursorScreenPos()
                        local name_width, name_height = ImGui.CalcTextSize(name)
                        local gap = 6
                        local distance_width = 0
                        local distance_display = nil
                        if distance_text ~= nil then
                            distance_display = "(" .. distance_text .. ")"
                            distance_width = (ImGui.CalcTextSize(distance_display))
                        end
                        local combined_width = name_width + (distance_text ~= nil and (gap + distance_width) or 0)

                        local chip_padding = 3
                        local chip_color_u32 = ImGui.GetColorU32(0, 0, 0, 0.7 * alpha_multiplier)
                        draw_list:AddRectFilled(
                            ImVec2.new(line_origin_x - chip_padding, line_origin_y - chip_padding),
                            ImVec2.new(line_origin_x + combined_width + chip_padding, line_origin_y + name_height + chip_padding),
                            chip_color_u32, state.corner_rounding)

                        draw_list:AddText(ImVec2.new(line_origin_x, line_origin_y), ImGui.GetColorU32(1, 1, 1, alpha_multiplier), name)
                        if distance_display ~= nil then
                            local dc = state.distance_text_color
                            draw_list:AddText(ImVec2.new(line_origin_x + name_width + gap, line_origin_y), ImGui.GetColorU32(dc[1], dc[2], dc[3], dc[4] * alpha_multiplier), distance_display)
                        end
                        ImGui.Dummy(combined_width, name_height)

                        local ok_hp, health_percent = pcall(function() return member:GetHealthPercent() end)
                        DrawHealthBar(state, ok_hp and health_percent or nil, alpha_multiplier)

                        ImGui.Separator()
                    end
                end
            end

            if not drew_any then
                ImGui.TextUnformatted("(no other group members to show)")
            end
        end
        ImGui.End()
    end

    local function Update()
        if modern_group_frames_state.initialized == false then Initialize() end

        -- Re-applied every frame (not just once at Initialize) since the ability bar script taught us
        -- the first attempt can silently fail if the script loads before the relevant game UI object is
        -- ready -- retrying every frame is cheap and guarantees it sticks once the game catches up.
        if Util.IsInGame() ~= 0 then
            ToggleDefaultGroupDisplay()
        end

        if modern_group_frames_state.initialized then Render() end
    end

    ModPack = ModPack or {}
    ModPack.GroupFrames = {
        display_name = "Group Frames",
        Update = Update,
        Settings = Settings,
        OnDisable = OnDisable,
    }
end
-- ============================================================================
-- MOD: Pet Frame
-- ============================================================================
do
    local Util = require("frontiers_forge.util")
    local UI = require("frontiers_forge.ui")
    local Player = require("frontiers_forge.player")
    local EntityList = require("frontiers_forge.entity_list")
    local AbilityList = require("frontiers_forge.ability_list")

    --[[
    Modern Pet Frame

    There's no dedicated pet module or "is this entity my pet" flag anywhere in the API. Instead,
    this detects your pet by cross-referencing nearby entity names against your own known ability
    names -- confirmed working because a summoned pet's entity name exactly matches the name of the
    ability that summoned it (e.g. casting "Walking Bones" creates an entity ALSO named "Walking
    Bones"). This is a real observed pattern, not a guess, but it does rest on an assumption: that
    EVERY summon-type ability in this game follows the same naming convention. If you ever summon a
    pet and this frame doesn't detect it, that assumption may not hold for that specific summon --
    let me know and we can look into it further.

    A distance cutoff is also applied (default 30 units) so a coincidental name match on some faraway
    NPC doesn't get mistaken for your pet.
    ]]
    modern_pet_frame_state = modern_pet_frame_state or {
        initialized                 = false,
        callbacks_registered         = false,

        settings_file_loaded        = false,
        _settings_snapshot          = "",

        show_pet_frame                = true,
        disable_in_start_menu         = false,
        max_pet_distance               = 75,  -- increased from 30 -- pets pathing around terrain can realistically fall this far behind during normal play
        pet_grace_period_seconds        = 5,   -- if the pet isn't confirmed for a moment (lag, desync, briefly out of range), keep showing its last known state for this long instead of vanishing

        window_transparent              = true,  -- removes the window's own background; only the health bar and name chip keep their own dark backing
        disable_default_pet_panel       = true,

        background_color              = {0.08, 0.08, 0.08, 0.85},
        show_border                   = true,
        border_color                  = {0, 0, 0, 1},
        border_thickness              = 1.5,
        corner_rounding                 = 6,
        font_scale                    = 1.0,
        bold_text                     = false,

        bar_width                     = 180,
        bar_height                    = 22,
        health_fill_color              = {0.2, 0.85, 0.2, 1.0},
        low_health_color                = {0.9, 0.2, 0.2, 1.0},
        low_health_threshold_percent     = 30,
        health_bar_bg_color             = {0.15, 0.15, 0.15, 1.0},
        show_health_text                = true,

        show_debug_info                 = false, -- shows every candidate name match considered, for troubleshooting
    }

    local function Trim(str)
        if str == nil then return "" end
        return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseBool(value)
        value = Trim(value):lower()
        return (value == "true" or value == "1" or value == "yes" or value == "on")
    end

    local PERSISTED_SETTINGS = {
        { key = "show_pet_frame",                type = "bool" },
        { key = "disable_in_start_menu",          type = "bool" },
        { key = "max_pet_distance",               type = "number" },
        { key = "pet_grace_period_seconds",         type = "number" },
        { key = "window_transparent",              type = "bool" },
        { key = "disable_default_pet_panel",        type = "bool" },

        { key = "background_color",              type = "color" },
        { key = "show_border",                   type = "bool" },
        { key = "border_color",                  type = "color" },
        { key = "border_thickness",              type = "number" },
        { key = "corner_rounding",                 type = "number" },
        { key = "font_scale",                    type = "number" },
        { key = "bold_text",                     type = "bool" },

        { key = "bar_width",                     type = "number" },
        { key = "bar_height",                    type = "number" },
        { key = "health_fill_color",              type = "color" },
        { key = "low_health_color",                type = "color" },
        { key = "low_health_threshold_percent",      type = "number" },
        { key = "health_bar_bg_color",              type = "color" },
        { key = "show_health_text",                 type = "bool" },

        { key = "show_debug_info",                type = "bool" },
    }

    local function GetPetFrameSettingsFilePath()
        return UiForge.resources_path .. "\\pet_frame_settings.cfg"
    end

    local function SerializeSettingsValue(value, value_type)
        if value_type == "color" then
            return table.concat({ tostring(value[1]), tostring(value[2]), tostring(value[3]), tostring(value[4]) }, ",")
        elseif value_type == "bool" then
            return value and "true" or "false"
        else
            return tostring(value)
        end
    end

    local function ParseSettingsValue(raw_value, value_type)
        if value_type == "color" then
            local components = {}
            for field in tostring(raw_value):gmatch("[^,]+") do
                components[#components + 1] = tonumber(field)
            end
            if #components == 4 and components[1] and components[2] and components[3] and components[4] then
                return components
            end
            return nil
        elseif value_type == "bool" then
            return ParseBool(raw_value)
        else
            return tonumber(raw_value)
        end
    end

    local function BuildSettingsSnapshot()
        local lines = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            lines[#lines + 1] = def.key .. "=" .. SerializeSettingsValue(modern_pet_frame_state[def.key], def.type)
        end
        return table.concat(lines, "\n")
    end

    local function WriteSettingsSnapshotToFile(snapshot)
        local file = io.open(GetPetFrameSettingsFilePath(), "w")
        if file == nil then return false end
        file:write("# pet_frame_settings.cfg -- auto-generated. Delete this file to reset to defaults.\n")
        file:write(snapshot)
        file:write("\n")
        file:close()
        return true
    end

    local function SavePetFrameSettingsIfChanged()
        local snapshot = BuildSettingsSnapshot()
        if snapshot ~= modern_pet_frame_state._settings_snapshot then
            if WriteSettingsSnapshotToFile(snapshot) then
                modern_pet_frame_state._settings_snapshot = snapshot
            end
        end
    end

    local function LoadPetFrameSettingsFromFile()
        local file = io.open(GetPetFrameSettingsFilePath(), "r")
        if file == nil then return false end

        local defs_by_key = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            defs_by_key[def.key] = def.type
        end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
                if key ~= nil and defs_by_key[key] ~= nil then
                    local parsed = ParseSettingsValue(raw_value, defs_by_key[key])
                    if parsed ~= nil then
                        modern_pet_frame_state[key] = parsed
                    end
                end
            end
        end

        file:close()
        modern_pet_frame_state._settings_snapshot = BuildSettingsSnapshot()
        return true
    end

    local function TryLoadPetFrameSettingsOnce()
        if modern_pet_frame_state.settings_file_loaded == true then return end
        LoadPetFrameSettingsFromFile()
        modern_pet_frame_state.settings_file_loaded = true
    end

    --[[
    Known ability names, built once at Initialize() and refreshable via a Settings button (in case
    you learn new abilities later). Used as the cross-reference set for pet detection.
    ]]
    known_ability_names = known_ability_names or {}
    local known_ability_names_populated = false

    local function RefreshKnownAbilityNames()
        known_ability_names = {}
        local ok, count = pcall(AbilityList.GetCount)
        if not ok then return end

        for index = 1, count do
            local ok_ability, ability = pcall(AbilityList.GetAbilityByIndex, index)
            if ok_ability and ability ~= nil then
                local ok_name, name = pcall(function() return ability:GetName() end)
                if ok_name and name ~= nil and name ~= "" then
                    known_ability_names[name] = true
                    known_ability_names_populated = true
                end
            end
        end
    end

    local function ToggleDefaultPetPanel()
        if modern_pet_frame_state.disable_default_pet_panel == true then
            UI.DisablePetPanel()
            return
        end
        UI.EnablePetPanel()
    end

    local function OnDisable()
        modern_pet_frame_state.show_pet_frame = false
        -- Always restore the native pet panel here, regardless of the "Disable Default Pet Panel"
        -- setting.
        UI.EnablePetPanel()
    end

    local function Initialize()
        TryLoadPetFrameSettingsOnce()
        RefreshKnownAbilityNames()
        modern_pet_frame_state.initialized = true
    end

    local function Settings()
        local state = modern_pet_frame_state

        state.show_pet_frame = ImGui.Checkbox("Show Pet Frame", state.show_pet_frame)
        ImGui.TextUnformatted("(Only actually shows when a pet is detected nearby, regardless of this.)")
        state.disable_in_start_menu = ImGui.Checkbox("Hide While Start Menu Is Open", state.disable_in_start_menu)
        state.max_pet_distance = ImGui.SliderInt("Max Pet Detection Distance", state.max_pet_distance, 5, 200, tostring(state.max_pet_distance))
        state.pet_grace_period_seconds = ImGui.SliderInt("Grace Period If Briefly Lost (seconds)", state.pet_grace_period_seconds, 0, 30, tostring(state.pet_grace_period_seconds))
        ImGui.TextUnformatted("(Keeps showing the pet's last known state briefly if it falls out")
        ImGui.TextUnformatted("of range/lags, instead of the frame vanishing immediately.)")
        state.window_transparent = ImGui.Checkbox("Window Transparent (only text/bar have background)", state.window_transparent)

        local new_val, pressed = ImGui.Checkbox("Disable Default Pet Panel", state.disable_default_pet_panel)
        if pressed then
            state.disable_default_pet_panel = new_val
            ToggleDefaultPetPanel()
        end

        if ImGui.Button("Refresh Known Ability Names") then
            RefreshKnownAbilityNames()
        end
        ImGui.TextUnformatted("(Run this if you've learned new abilities since loading this script.)")

        ImGui.Separator()
        ImGui.Text("Appearance")
        state.background_color = ImGui.ColorEdit4("Background Color", state.background_color)
        state.show_border = ImGui.Checkbox("Show Border", state.show_border)
        state.border_color = ImGui.ColorEdit4("Border Color", state.border_color)
        state.border_thickness = ImGui.SliderFloat("Border Thickness", state.border_thickness, 0.5, 5.0, tostring(state.border_thickness))
        state.corner_rounding = ImGui.SliderFloat("Corner Rounding", state.corner_rounding, 0, 20, tostring(state.corner_rounding))
        state.font_scale = ImGui.SliderFloat("Font Scale", state.font_scale, 0.5, 3.0, tostring(state.font_scale))
        state.bold_text = ImGui.Checkbox("Bold Text", state.bold_text)

        ImGui.Separator()
        ImGui.Text("Health Bar")
        state.bar_width = ImGui.SliderInt("Bar Width", state.bar_width, 80, 400, tostring(state.bar_width))
        state.bar_height = ImGui.SliderInt("Bar Height", state.bar_height, 10, 50, tostring(state.bar_height))
        state.health_fill_color = ImGui.ColorEdit4("Health Fill Color", state.health_fill_color)
        state.low_health_color = ImGui.ColorEdit4("Low Health Color", state.low_health_color)
        state.low_health_threshold_percent = ImGui.SliderInt("Low Health Threshold (%)", state.low_health_threshold_percent, 0, 100, tostring(state.low_health_threshold_percent))
        state.health_bar_bg_color = ImGui.ColorEdit4("Health Bar Background", state.health_bar_bg_color)
        state.show_health_text = ImGui.Checkbox("Show Health Text", state.show_health_text)

        ImGui.Separator()
        state.show_debug_info = ImGui.Checkbox("Show Debug Info (troubleshooting)", state.show_debug_info)

        SavePetFrameSettingsIfChanged()
    end

    -- Finds the nearby entity most likely to be your pet: a name matching a known ability, within
    -- max_pet_distance, picking the CLOSEST match if somehow more than one qualifies.
    local function FindPetEntity(state, player_coords)
        local best_entity = nil
        local best_distance = nil
        local candidates_checked = {}

        local entities = EntityList.GetAllEntities()
        for _, entity in ipairs(entities) do
            if entity.name ~= nil and entity.name ~= "" and known_ability_names[entity.name] then
                local dx = entity.x - player_coords.x
                local dz = entity.z - player_coords.z
                local distance = math.sqrt(dx * dx + dz * dz)

                table.insert(candidates_checked, entity.name .. " (dist=" .. string.format("%.0f", distance) .. ")")

                if distance <= state.max_pet_distance then
                    if best_distance == nil or distance < best_distance then
                        best_entity = entity
                        best_distance = distance
                    end
                end
            end
        end

        return best_entity, best_distance, candidates_checked
    end

    local function DrawHealthBar(state, health_percent)
        local draw_list = ImGui.GetWindowDrawList()
        local origin_x, origin_y = ImGui.GetCursorScreenPos()
        local p0 = ImVec2.new(origin_x, origin_y)
        local p1 = ImVec2.new(origin_x + state.bar_width, origin_y + state.bar_height)

        local bg_color_u32 = ImGui.GetColorU32(state.health_bar_bg_color[1], state.health_bar_bg_color[2], state.health_bar_bg_color[3], state.health_bar_bg_color[4])
        draw_list:AddRectFilled(p0, p1, bg_color_u32, state.corner_rounding)

        local fill_color = (health_percent <= state.low_health_threshold_percent) and state.low_health_color or state.health_fill_color
        local fill_color_u32 = ImGui.GetColorU32(fill_color[1], fill_color[2], fill_color[3], fill_color[4])
        local fill_width = state.bar_width * math.max(math.min(health_percent, 100), 0) / 100
        if fill_width > 0 then
            draw_list:AddRectFilled(p0, ImVec2.new(origin_x + fill_width, origin_y + state.bar_height), fill_color_u32, state.corner_rounding)
        end

        if state.show_border then
            local border_color_u32 = ImGui.GetColorU32(state.border_color[1], state.border_color[2], state.border_color[3], state.border_color[4])
            draw_list:AddRect(p0, p1, border_color_u32, state.corner_rounding, 0, state.border_thickness)
        end

        if state.show_health_text then
            local text = string.format("%.0f/100", health_percent)
            local text_width, text_height = ImGui.CalcTextSize(text)
            local text_color_u32 = ImGui.GetColorU32(1, 1, 1, 1)
            draw_list:AddText(ImVec2.new(origin_x + (state.bar_width - text_width) / 2, origin_y + (state.bar_height - text_height) / 2), text_color_u32, text)
        end

        ImGui.Dummy(state.bar_width, state.bar_height)
    end

    local function Render()
        local state = modern_pet_frame_state

        if Util.IsInGame() == 0 then return end
        if state.disable_in_start_menu and Util.IsStartMenuOpen() == 1 then return end

        local ok_player_coords, player_coords = pcall(Player.GetCoordinates)
        if not ok_player_coords or player_coords == nil then return end

        local pet_entity, pet_distance, candidates = FindPetEntity(state, player_coords)

        -- Sticky cache: a pet naturally lags behind while pathing around terrain, and can
        -- temporarily fall outside max_pet_distance or briefly desync from the entity list for a
        -- frame or two. Without this, the frame would flicker or vanish every time that happens,
        -- even though the pet is still alive and following you. Instead, keep showing its last
        -- known name/level/HP for a grace period before actually treating it as gone (dismissed,
        -- died, or genuinely out of range for a sustained time).
        pet_sticky_cache = pet_sticky_cache or { snapshot = nil, last_seen_time = nil }

        local display_entity = nil
        if pet_entity ~= nil then
            pet_sticky_cache.snapshot = { name = pet_entity.name, level = pet_entity.level, percent_hp = pet_entity.percent_hp }
            pet_sticky_cache.last_seen_time = os.clock()
            display_entity = pet_entity
        elseif pet_sticky_cache.snapshot ~= nil and pet_sticky_cache.last_seen_time ~= nil then
            if os.clock() - pet_sticky_cache.last_seen_time <= state.pet_grace_period_seconds then
                display_entity = pet_sticky_cache.snapshot
            end
        end

        if state.show_debug_info then
            if ImGui.Begin("Pet Frame Debug") then
                ImGui.TextUnformatted("Known ability names loaded: " .. (function()
                    local n = 0
                    for _ in pairs(known_ability_names) do n = n + 1 end
                    return n
                end)())
                ImGui.TextUnformatted("Candidate name matches this frame:")
                if #candidates == 0 then
                    ImGui.TextUnformatted("  (none)")
                end
                for _, c in ipairs(candidates) do
                    ImGui.TextUnformatted("  " .. c)
                end
                if pet_entity == nil and display_entity ~= nil then
                    local age = os.clock() - pet_sticky_cache.last_seen_time
                    ImGui.TextUnformatted(string.format("Showing cached data (last confirmed %.1fs ago)", age))
                end
            end
            ImGui.End()
        end

        if state.show_pet_frame ~= true then return end
        if display_entity == nil then return end -- auto-hide entirely when no pet detected AND the grace period has elapsed

        local window_flags = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoTitleBar
        if state.window_transparent then window_flags = window_flags + ImGuiWindowFlags.NoBackground end

        if ImGui.Begin("Pet Frame", true, window_flags) then
            ImGui.SetWindowFontScale(state.font_scale)

            -- Drawn manually (not as plain ImGui.Text widgets) so we can give the text its own dark
            -- background chip -- needed since the window itself has no background when
            -- window_transparent is on, and floating text with nothing behind it can be hard to read
            -- over bright/busy game scenery.
            local name_line = display_entity.name .. "  (Lvl " .. display_entity.level .. ")"
            local origin_x, origin_y = ImGui.GetCursorScreenPos()
            local draw_list = ImGui.GetWindowDrawList()
            local text_width, text_height = ImGui.CalcTextSize(name_line)

            local chip_padding = 3
            local chip_color_u32 = ImGui.GetColorU32(0, 0, 0, 0.7)
            draw_list:AddRectFilled(
                ImVec2.new(origin_x - chip_padding, origin_y - chip_padding),
                ImVec2.new(origin_x + text_width + chip_padding, origin_y + text_height + chip_padding),
                chip_color_u32, state.corner_rounding)

            local name_color_u32 = ImGui.GetColorU32(1, 1, 1, 1)
            draw_list:AddText(ImVec2.new(origin_x, origin_y), name_color_u32, name_line)
            ImGui.Dummy(text_width, text_height)

            DrawHealthBar(state, display_entity.percent_hp * 100)
        end
        ImGui.End()
    end

    local function Update()
        if modern_pet_frame_state.initialized == false then Initialize() end

        -- Both retried every frame while not yet successful/while in-game -- the ability bar taught us
        -- the first attempt at reading game data or applying a native UI toggle can silently fail if it
        -- runs before the game is fully ready, with nothing to retry it afterward otherwise.
        if Util.IsInGame() ~= 0 then
            if not known_ability_names_populated then
                RefreshKnownAbilityNames()
            end
            ToggleDefaultPetPanel()
        end

        if modern_pet_frame_state.initialized then Render() end
    end

    ModPack = ModPack or {}
    ModPack.PetFrame = {
        display_name = "Pet Frame",
        Update = Update,
        Settings = Settings,
        OnDisable = OnDisable,
    }
end
-- ============================================================================
-- MOD: Quest Log
-- ============================================================================
do
    local Util = require("frontiers_forge.util")            -- Access Utility functions
    local Chat = require("frontiers_forge.chat")            -- Cross-reference chat messages against quest names
    local QuestLog = require("frontiers_forge.quest_log")   -- Access the active quest list

    --[[
    Modern Quest Log

    HONEST LIMITATION (please read before expecting more from this): the game only ever exposes
    quest TITLES to the client -- QuestLog.GetCount()/GetQuestByIndex()/Quests(), and Quest:GetName()
    is the only field Quest objects have. IDs, descriptions, and objective/completion state are all
    server-side and only ever arrive as transient dialogue text -- they are never stored anywhere
    the client (and therefore this script) can read afterward. This is not a gap in what's been
    reverse-engineered yet; the data genuinely isn't kept anywhere on the client at all.

    So instead of a real objective tracker (which isn't possible from what's exposed), this does
    three honest things with what IS available:
      1. A clean, modern-styled list of your active quest titles (capped at 8, with a "log full"
         warning at 8/8, matching the real in-game cap).
      2. Chat cross-referencing: since we DO have full chat access, this watches incoming messages
         for any that mention a quest title currently in your log, and flags that quest with a
         "recently mentioned" badge + timestamp for a while afterward. This can't tell you WHAT
         changed (no objective data exists to read), only THAT something related showed up in chat --
         a reasonable stand-in given the constraints, not a full replacement for real objective text.
      3. Personal notes: since the game keeps none, you can type your own reminder next to each
         quest title. These are saved keyed by quest NAME (the only stable identifier available --
         there's no numeric quest ID exposed), so two simultaneously active quests that happen to
         share the exact same name would share a note. Rare, but worth knowing.
    ]]
    modern_quest_log_state = modern_quest_log_state or {
        initialized                 = false,
        callbacks_registered         = false,

        -- Settings persistence
        settings_file_loaded        = false,
        _settings_snapshot          = "",

        show_quest_log               = true,
        disable_in_start_menu        = false,

        -- Appearance
        background_color             = {0.08, 0.08, 0.08, 0.85},
        show_border                  = true,
        border_color                 = {0, 0, 0, 1},
        border_thickness             = 1.5,
        corner_rounding                = 6,
        font_scale                   = 1.0,
        bold_text                    = false,

        quest_name_color              = {1, 1, 1, 1},
        log_full_warning_color        = {1, 0.4, 0.3, 1},

        -- Chat cross-referencing
        show_recent_activity_badge     = true,
        recent_activity_color          = {1.0, 0.85, 0.2, 1.0},
        recent_activity_duration_seconds = 300, -- how long the "recently mentioned" badge stays lit

        -- Notes
        show_notes                   = true,
    }

    local function Trim(str)
        if str == nil then return "" end
        return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseBool(value)
        value = Trim(value):lower()
        return (value == "true" or value == "1" or value == "yes" or value == "on")
    end

    --[[
    Settings persistence (fixed-schema settings only -- see further below for the separate,
    free-form notes storage, which doesn't fit this key=value scheme).
    ]]
    local PERSISTED_SETTINGS = {
        { key = "show_quest_log",                type = "bool" },
        { key = "disable_in_start_menu",          type = "bool" },

        { key = "background_color",              type = "color" },
        { key = "show_border",                   type = "bool" },
        { key = "border_color",                  type = "color" },
        { key = "border_thickness",              type = "number" },
        { key = "corner_rounding",                 type = "number" },
        { key = "font_scale",                    type = "number" },
        { key = "bold_text",                     type = "bool" },

        { key = "quest_name_color",               type = "color" },
        { key = "log_full_warning_color",          type = "color" },

        { key = "show_recent_activity_badge",      type = "bool" },
        { key = "recent_activity_color",           type = "color" },
        { key = "recent_activity_duration_seconds", type = "number" },

        { key = "show_notes",                    type = "bool" },
    }

    local function GetQuestLogSettingsFilePath()
        return UiForge.resources_path .. "\\quest_log_settings.cfg"
    end

    local function GetQuestNotesFilePath()
        return UiForge.resources_path .. "\\quest_log_notes.cfg"
    end

    local function SerializeSettingsValue(value, value_type)
        if value_type == "color" then
            return table.concat({ tostring(value[1]), tostring(value[2]), tostring(value[3]), tostring(value[4]) }, ",")
        elseif value_type == "bool" then
            return value and "true" or "false"
        else -- "number"
            return tostring(value)
        end
    end

    local function ParseSettingsValue(raw_value, value_type)
        if value_type == "color" then
            local components = {}
            for field in tostring(raw_value):gmatch("[^,]+") do
                components[#components + 1] = tonumber(field)
            end
            if #components == 4 and components[1] and components[2] and components[3] and components[4] then
                return components
            end
            return nil
        elseif value_type == "bool" then
            return ParseBool(raw_value)
        else -- "number"
            return tonumber(raw_value)
        end
    end

    local function BuildSettingsSnapshot()
        local lines = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            lines[#lines + 1] = def.key .. "=" .. SerializeSettingsValue(modern_quest_log_state[def.key], def.type)
        end
        return table.concat(lines, "\n")
    end

    local function WriteSettingsSnapshotToFile(snapshot)
        local file = io.open(GetQuestLogSettingsFilePath(), "w")
        if file == nil then return false end
        file:write("# quest_log_settings.cfg -- auto-generated. Delete this file to reset to defaults.\n")
        file:write(snapshot)
        file:write("\n")
        file:close()
        return true
    end

    local function SaveQuestLogSettingsIfChanged()
        local snapshot = BuildSettingsSnapshot()
        if snapshot ~= modern_quest_log_state._settings_snapshot then
            if WriteSettingsSnapshotToFile(snapshot) then
                modern_quest_log_state._settings_snapshot = snapshot
            end
        end
    end

    local function LoadQuestLogSettingsFromFile()
        local file = io.open(GetQuestLogSettingsFilePath(), "r")
        if file == nil then return false end

        local defs_by_key = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            defs_by_key[def.key] = def.type
        end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
                if key ~= nil and defs_by_key[key] ~= nil then
                    local parsed = ParseSettingsValue(raw_value, defs_by_key[key])
                    if parsed ~= nil then
                        modern_quest_log_state[key] = parsed
                    end
                end
            end
        end

        file:close()
        modern_quest_log_state._settings_snapshot = BuildSettingsSnapshot()
        return true
    end

    local function TryLoadQuestLogSettingsOnce()
        if modern_quest_log_state.settings_file_loaded == true then return end
        LoadQuestLogSettingsFromFile()
        modern_quest_log_state.settings_file_loaded = true
    end

    --[[
    Notes storage: a separate file, since arbitrary quest-name keys with free-form text don't fit
    the fixed-schema key=value format above. One line per note: "<quest name>|<note text>".
    Pipe characters and newlines are stripped from both the name and note text when saving, since
    they'd break this simple line format -- good enough for short personal reminders.
    ]]
    quest_notes = quest_notes or {}
    local quest_notes_loaded = false
    local quest_notes_snapshot = ""

    local function SanitizeForNotesFile(str)
        return (tostring(str):gsub("[|\r\n]", " "))
    end

    local function BuildNotesSnapshot()
        local lines = {}
        for name, note in pairs(quest_notes) do
            if note ~= nil and note ~= "" then
                lines[#lines + 1] = SanitizeForNotesFile(name) .. "|" .. SanitizeForNotesFile(note)
            end
        end
        table.sort(lines) -- stable ordering, so the file doesn't churn every save just from table iteration order
        return table.concat(lines, "\n")
    end

    local function SaveQuestNotesIfChanged()
        local snapshot = BuildNotesSnapshot()
        if snapshot ~= quest_notes_snapshot then
            local file = io.open(GetQuestNotesFilePath(), "w")
            if file ~= nil then
                file:write("# quest_log_notes.cfg -- auto-generated. One line per note: name|note text\n")
                file:write(snapshot)
                file:write("\n")
                file:close()
                quest_notes_snapshot = snapshot
            end
        end
    end

    local function LoadQuestNotesOnce()
        if quest_notes_loaded then return end
        quest_notes_loaded = true

        local file = io.open(GetQuestNotesFilePath(), "r")
        if file == nil then return end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local name, note = trimmed:match("^(.-)|(.*)$")
                if name ~= nil then
                    quest_notes[name] = note
                end
            end
        end
        file:close()
        quest_notes_snapshot = BuildNotesSnapshot()
    end

    --[[
    Chat cross-referencing: tracks the last time (os.clock()) each active quest's title was seen
    mentioned in a chat message, so we can show a "recently mentioned" badge for a while afterward.
    ]]
    quest_last_mentioned = quest_last_mentioned or {}

    local function UpdateChatCrossReference(state)
        local msg_contents = Chat.GetNextMessage()
        if msg_contents == "" or msg_contents == nil then return end

        local now = os.clock()
        local count = QuestLog.GetCount()
        for i = 0, count - 1 do
            local ok, quest = pcall(QuestLog.GetQuestByIndex, i)
            if ok and quest ~= nil then
                local ok_name, name = pcall(function() return quest:GetName() end)
                if ok_name and name ~= nil and name ~= "" then
                    if msg_contents:find(name, 1, true) then -- plain substring search, no pattern-matching surprises
                        quest_last_mentioned[name] = now
                    end
                end
            end
        end
    end

    local function GetRecentActivitySecondsAgo(state, quest_name)
        local last_seen = quest_last_mentioned[quest_name]
        if last_seen == nil then return nil end
        local elapsed = os.clock() - last_seen
        if elapsed > state.recent_activity_duration_seconds then return nil end
        return elapsed
    end

    local function OnDisable()
        -- No native quest log toggle exists to restore (there's nothing in ui.lua for this), so
        -- just hide our own window.
        modern_quest_log_state.show_quest_log = false
    end

    local function Initialize()
        TryLoadQuestLogSettingsOnce()
        LoadQuestNotesOnce()
        modern_quest_log_state.initialized = true
    end

    local function Settings()
        local state = modern_quest_log_state

        state.show_quest_log = ImGui.Checkbox("Show Quest Log", state.show_quest_log)
        state.disable_in_start_menu = ImGui.Checkbox("Hide While Start Menu Is Open", state.disable_in_start_menu)

        ImGui.Separator()
        ImGui.Text("Appearance")
        state.background_color = ImGui.ColorEdit4("Background Color", state.background_color)
        state.show_border = ImGui.Checkbox("Show Border", state.show_border)
        state.border_color = ImGui.ColorEdit4("Border Color", state.border_color)
        state.border_thickness = ImGui.SliderFloat("Border Thickness", state.border_thickness, 0.5, 5.0, tostring(state.border_thickness))
        state.corner_rounding = ImGui.SliderFloat("Corner Rounding", state.corner_rounding, 0, 20, tostring(state.corner_rounding))
        state.font_scale = ImGui.SliderFloat("Font Scale", state.font_scale, 0.5, 3.0, tostring(state.font_scale))
        state.bold_text = ImGui.Checkbox("Bold Text", state.bold_text)
        state.quest_name_color = ImGui.ColorEdit4("Quest Name Color", state.quest_name_color)
        state.log_full_warning_color = ImGui.ColorEdit4("Log Full Warning Color", state.log_full_warning_color)

        ImGui.Separator()
        ImGui.Text("Chat Cross-Referencing")
        ImGui.TextUnformatted("Flags a quest when its title is mentioned in chat. Can't show WHAT")
        ImGui.TextUnformatted("changed (no objective data exists to read) -- just THAT something did.")
        state.show_recent_activity_badge = ImGui.Checkbox("Show Recent Activity Badge", state.show_recent_activity_badge)
        state.recent_activity_color = ImGui.ColorEdit4("Recent Activity Color", state.recent_activity_color)
        state.recent_activity_duration_seconds = ImGui.SliderInt("Badge Duration (seconds)", state.recent_activity_duration_seconds, 30, 1800, tostring(state.recent_activity_duration_seconds))

        ImGui.Separator()
        ImGui.Text("Notes")
        ImGui.TextUnformatted("The game keeps no notes of its own -- these are saved by this script")
        ImGui.TextUnformatted("only, keyed by quest name.")
        state.show_notes = ImGui.Checkbox("Show Personal Notes", state.show_notes)

        SaveQuestLogSettingsIfChanged()
    end

    local function Render()
        local state = modern_quest_log_state

        if Util.IsInGame() == 0 then return end
        if state.disable_in_start_menu and Util.IsStartMenuOpen() == 1 then return end

        -- Cross-reference chat every frame regardless of window visibility, so activity flags stay
        -- accurate even while the log is hidden.
        UpdateChatCrossReference(state)

        if state.show_quest_log ~= true then return end

        if ImGui.Begin("Quest Log") then
            ImGui.SetWindowFontScale(state.font_scale)

            local count = QuestLog.GetCount()
            local header_color = (count >= 8) and state.log_full_warning_color or state.quest_name_color
            local header_color_u32 = ImGui.GetColorU32(header_color[1], header_color[2], header_color[3], header_color[4])
            local header_text = "Quests (" .. count .. "/8)" .. (count >= 8 and "  -- LOG FULL" or "")

            ImGui.PushStyleColor(ImGuiCol.Text, header_color[1], header_color[2], header_color[3], header_color[4])
            ImGui.TextUnformatted(header_text)
            ImGui.PopStyleColor()
            ImGui.Separator()

            if count == 0 then
                ImGui.TextUnformatted("(no active quests)")
            end

            for i = 0, count - 1 do
                local ok, quest = pcall(QuestLog.GetQuestByIndex, i)
                if ok and quest ~= nil then
                    local ok_name, name = pcall(function() return quest:GetName() end)
                    name = (ok_name and name ~= nil and name ~= "") and name or "(unnamed quest)"

                    ImGui.PushStyleColor(ImGuiCol.Text, state.quest_name_color[1], state.quest_name_color[2], state.quest_name_color[3], state.quest_name_color[4])
                    if state.bold_text then
                        local cursor_x, cursor_y = ImGui.GetCursorPos()
                        ImGui.SetCursorPos(cursor_x + state.font_scale, cursor_y)
                        ImGui.TextUnformatted(name)
                        ImGui.SetCursorPos(cursor_x, cursor_y)
                    end
                    ImGui.TextUnformatted(name)
                    ImGui.PopStyleColor()

                    if state.show_recent_activity_badge then
                        local seconds_ago = GetRecentActivitySecondsAgo(state, name)
                        if seconds_ago ~= nil then
                            ImGui.SameLine()
                            local badge_color = state.recent_activity_color
                            ImGui.PushStyleColor(ImGuiCol.Text, badge_color[1], badge_color[2], badge_color[3], badge_color[4])
                            ImGui.TextUnformatted(string.format("[mentioned %ds ago]", math.floor(seconds_ago)))
                            ImGui.PopStyleColor()
                        end
                    end

                    if state.show_notes then
                        local existing_note = quest_notes[name] or ""
                        local new_note, changed = ImGui.InputText("##note_" .. i, existing_note)
                        if changed then
                            quest_notes[name] = new_note
                            SaveQuestNotesIfChanged()
                        end
                    end

                    if i < count - 1 then
                        ImGui.Separator()
                    end
                end
            end
        end
        ImGui.End()
    end


    -- Creating a local variable to interact with the global table so that the name is shorter/easier to use

    local function Update()
        if modern_quest_log_state.initialized == false then Initialize() end
        if modern_quest_log_state.initialized then Render() end
    end

    ModPack = ModPack or {}
    ModPack.QuestLog = {
        display_name = "Quest Log",
        Update = Update,
        Settings = Settings,
        OnDisable = OnDisable,
    }
end
-- ============================================================================
-- MOD: Effects (Buffs/Debuffs)
-- ============================================================================
do
    local UI = require("frontiers_forge.ui")                -- Access UI elements
    local Util = require("frontiers_forge.util")            -- Access Utility functions
    local Icon = require("frontiers_forge.icon")             -- Decode game icons into ImGui textures
    local Effects = require("frontiers_forge.effects")       -- Access active effects (buffs/debuffs) -- new in v1.0

    --[[
    Modern Effects (Buffs/Debuffs)

    Built on the new effects.lua module (v1.0), which finally exposes the player's active effects
    (the icon row next to the health/power/experience bars) -- name and icon per effect, up to 8.

    HONEST LIMITATION: there is no buff-vs-debuff distinction anywhere in the exposed data, just a
    name and an icon per active effect (matching what the module itself documents -- "couldn't find
    any other client side info for them"). This script shows every active effect together in one
    row rather than attempting to split them, since there's no reliable way to categorize them (a
    name-based guess would be unreliable and is not attempted here).
    ]]
    modern_effects_state = modern_effects_state or {
        initialized                 = false,
        native_toggle_confirmed      = false, -- v0.1.1: tracks whether the native display disable/enable write has actually landed yet

        settings_file_loaded        = false,
        _settings_snapshot          = "",

        show_effects_panel            = true,
        disable_in_start_menu         = false,

        window_transparent             = true,
        icon_size                     = 40,
        icon_spacing                  = 4,
        background_color               = {0.12, 0.12, 0.12, 0.9},
        show_border                   = true,
        border_color                  = {0, 0, 0, 1},
        border_thickness              = 1.5,
        corner_rounding                 = 6,

        show_names_below               = false, -- names can be long -- off by default, shown as a tooltip on hover instead
        name_text_color                = {1, 1, 1, 0.85},
        font_scale                    = 1.0,

        show_debug_info                = false,

        disable_default_effects_display  = true,
    }

    local function Trim(str)
        if str == nil then return "" end
        return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function ParseBool(value)
        value = Trim(value):lower()
        return (value == "true" or value == "1" or value == "yes" or value == "on")
    end

    local PERSISTED_SETTINGS = {
        { key = "show_effects_panel",              type = "bool" },
        { key = "disable_in_start_menu",            type = "bool" },

        { key = "window_transparent",               type = "bool" },
        { key = "icon_size",                       type = "number" },
        { key = "icon_spacing",                    type = "number" },
        { key = "background_color",                type = "color" },
        { key = "show_border",                     type = "bool" },
        { key = "border_color",                    type = "color" },
        { key = "border_thickness",                type = "number" },
        { key = "corner_rounding",                   type = "number" },

        { key = "show_names_below",                 type = "bool" },
        { key = "name_text_color",                  type = "color" },
        { key = "font_scale",                      type = "number" },

        { key = "show_debug_info",                  type = "bool" },
        { key = "disable_default_effects_display",    type = "bool" },
    }

    local function GetEffectsSettingsFilePath()
        return UiForge.resources_path .. "\\effects_settings.cfg"
    end

    local function SerializeSettingsValue(value, value_type)
        if value_type == "color" then
            return table.concat({ tostring(value[1]), tostring(value[2]), tostring(value[3]), tostring(value[4]) }, ",")
        elseif value_type == "bool" then
            return value and "true" or "false"
        else
            return tostring(value)
        end
    end

    local function ParseSettingsValue(raw_value, value_type)
        if value_type == "color" then
            local components = {}
            for field in tostring(raw_value):gmatch("[^,]+") do
                components[#components + 1] = tonumber(field)
            end
            if #components == 4 and components[1] and components[2] and components[3] and components[4] then
                return components
            end
            return nil
        elseif value_type == "bool" then
            return ParseBool(raw_value)
        else
            return tonumber(raw_value)
        end
    end

    local function BuildSettingsSnapshot()
        local lines = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            lines[#lines + 1] = def.key .. "=" .. SerializeSettingsValue(modern_effects_state[def.key], def.type)
        end
        return table.concat(lines, "\n")
    end

    local function WriteSettingsSnapshotToFile(snapshot)
        local file = io.open(GetEffectsSettingsFilePath(), "w")
        if file == nil then return false end
        file:write("# effects_settings.cfg -- auto-generated. Delete this file to reset to defaults.\n")
        file:write(snapshot)
        file:write("\n")
        file:close()
        return true
    end

    local function SaveEffectsSettingsIfChanged()
        local snapshot = BuildSettingsSnapshot()
        if snapshot ~= modern_effects_state._settings_snapshot then
            if WriteSettingsSnapshotToFile(snapshot) then
                modern_effects_state._settings_snapshot = snapshot
            end
        end
    end

    local function LoadEffectsSettingsFromFile()
        local file = io.open(GetEffectsSettingsFilePath(), "r")
        if file == nil then return false end

        local defs_by_key = {}
        for _, def in ipairs(PERSISTED_SETTINGS) do
            defs_by_key[def.key] = def.type
        end

        for line in file:lines() do
            local trimmed = Trim(line)
            if trimmed ~= "" and not trimmed:match("^#") then
                local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
                if key ~= nil and defs_by_key[key] ~= nil then
                    local parsed = ParseSettingsValue(raw_value, defs_by_key[key])
                    if parsed ~= nil then
                        modern_effects_state[key] = parsed
                    end
                end
            end
        end

        file:close()
        modern_effects_state._settings_snapshot = BuildSettingsSnapshot()
        return true
    end

    local function TryLoadEffectsSettingsOnce()
        if modern_effects_state.settings_file_loaded == true then return end
        LoadEffectsSettingsFromFile()
        modern_effects_state.settings_file_loaded = true
    end

    local function ToggleDefaultEffectsDisplay()
        if modern_effects_state.disable_default_effects_display == true then
            return UI.DisableActiveEffectsDisplay()
        end
        return UI.EnableActiveEffectsDisplay()
    end

    local function OnDisable()
        modern_effects_state.show_effects_panel = false
        UI.EnableActiveEffectsDisplay()
    end

    local function Initialize()
        TryLoadEffectsSettingsOnce()
        modern_effects_state.initialized = true
    end

    local function Settings()
        local state = modern_effects_state

        state.show_effects_panel = ImGui.Checkbox("Show Effects Panel", state.show_effects_panel)
        state.disable_in_start_menu = ImGui.Checkbox("Hide While Start Menu Is Open", state.disable_in_start_menu)

        ImGui.Separator()
        ImGui.TextUnformatted("No buff/debuff distinction is exposed anywhere in the API -- just")
        ImGui.TextUnformatted("a name and icon per active effect. All shown together below.")

        ImGui.Separator()
        ImGui.Text("Appearance")
        state.window_transparent = ImGui.Checkbox("Window Transparent (only icons have background)", state.window_transparent)
        state.icon_size = ImGui.SliderInt("Icon Size", state.icon_size, 20, 100, tostring(state.icon_size))
        state.icon_spacing = ImGui.SliderInt("Icon Spacing", state.icon_spacing, 0, 20, tostring(state.icon_spacing))
        state.background_color = ImGui.ColorEdit4("Background Color", state.background_color)
        state.show_border = ImGui.Checkbox("Show Border", state.show_border)
        state.border_color = ImGui.ColorEdit4("Border Color", state.border_color)
        state.border_thickness = ImGui.SliderFloat("Border Thickness", state.border_thickness, 0.5, 5.0, tostring(state.border_thickness))
        state.corner_rounding = ImGui.SliderFloat("Corner Rounding", state.corner_rounding, 0, 20, tostring(state.corner_rounding))

        ImGui.Separator()
        ImGui.Text("Names")
        state.show_names_below = ImGui.Checkbox("Show Names Below Icons", state.show_names_below)
        ImGui.TextUnformatted("(Names always show as a tooltip on hover regardless of this.)")
        state.name_text_color = ImGui.ColorEdit4("Name Text Color", state.name_text_color)
        state.font_scale = ImGui.SliderFloat("Font Scale", state.font_scale, 0.5, 3.0, tostring(state.font_scale))

        ImGui.Separator()
        state.show_debug_info = ImGui.Checkbox("Show Debug Info (troubleshooting)", state.show_debug_info)

        local new_val, pressed = ImGui.Checkbox("Disable Default Effects Display", state.disable_default_effects_display)
        if pressed then
            state.disable_default_effects_display = new_val
            state.native_toggle_confirmed = ToggleDefaultEffectsDisplay()
        end

        SaveEffectsSettingsIfChanged()
    end

    local function DrawEffect(state, effect)
        local draw_list = ImGui.GetWindowDrawList()
        local origin_x, origin_y = ImGui.GetCursorScreenPos()
        local p0 = ImVec2.new(origin_x, origin_y)
        local p1 = ImVec2.new(origin_x + state.icon_size, origin_y + state.icon_size)

        local bg_color_u32 = ImGui.GetColorU32(state.background_color[1], state.background_color[2], state.background_color[3], state.background_color[4])
        draw_list:AddRectFilled(p0, p1, bg_color_u32, state.corner_rounding)

        local drew_icon = false
        local debug_text = nil
        local ok_tex, texture = pcall(Icon.GetTexture, effect.icon_ref, { trim_transparent = true, trim_color = true })
        if ok_tex and texture ~= nil then
            local ok_draw = pcall(ImGui.Image, texture, state.icon_size, state.icon_size)
            drew_icon = ok_draw
            if not ok_draw then
                debug_text = "ImGui.Image failed on this effect's texture"
            end
        else
            debug_text = "Icon.GetTexture failed: " .. tostring(texture)
        end
        if not drew_icon then
            ImGui.Dummy(state.icon_size, state.icon_size)
        end

        if state.show_border then
            local border_color_u32 = ImGui.GetColorU32(state.border_color[1], state.border_color[2], state.border_color[3], state.border_color[4])
            draw_list:AddRect(p0, p1, border_color_u32, state.corner_rounding, 0, state.border_thickness)
        end

        if ImGui.IsItemHovered() then
            if state.show_debug_info and debug_text ~= nil then
                ImGui.SetTooltip((effect.name or "Unknown Effect") .. "\n" .. debug_text)
            else
                ImGui.SetTooltip(effect.name or "Unknown Effect")
            end
        end

        if state.show_names_below then
            local name = effect.name or "?"
            local name_width = ImGui.CalcTextSize(name)
            local name_color_u32 = ImGui.GetColorU32(state.name_text_color[1], state.name_text_color[2], state.name_text_color[3], state.name_text_color[4])
            draw_list:AddText(ImVec2.new(origin_x + (state.icon_size - name_width) / 2, origin_y + state.icon_size + 2), name_color_u32, name)
            ImGui.Dummy(state.icon_size, 14)
        end
    end

    local function Render()
        local state = modern_effects_state

        if Util.IsInGame() == 0 then return end
        if state.disable_in_start_menu and Util.IsStartMenuOpen() == 1 then return end
        if state.show_effects_panel ~= true then return end

        local count = Effects.GetCount()
        if count == 0 then return end -- auto-hide entirely when nothing is active

        local window_flags = ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoTitleBar
        if state.window_transparent then window_flags = window_flags + ImGuiWindowFlags.NoBackground end

        if ImGui.Begin("Effects", true, window_flags) then
            ImGui.SetWindowFontScale(state.font_scale)

            for index, effect in Effects.All() do
                if index > 0 then
                    ImGui.SameLine(0, state.icon_spacing)
                end
                DrawEffect(state, effect)
            end
        end
        ImGui.End()
    end

    local function Update()
        if modern_effects_state.initialized == false then Initialize() end

        if modern_effects_state.native_toggle_confirmed ~= true then
            modern_effects_state.native_toggle_confirmed = ToggleDefaultEffectsDisplay()
        end

        if modern_effects_state.initialized then Render() end
    end

    ModPack = ModPack or {}
    ModPack.Effects = {
        display_name = "Effects (Buffs/Debuffs)",
        Update = Update,
        Settings = Settings,
        OnDisable = OnDisable,
    }
end
-- ============================================================================
-- MOD: Target Level
-- ============================================================================
do
    local Util      = require("frontiers_forge.util")
    local Player    = require("frontiers_forge.player")
    local EntityList = require("frontiers_forge.entity_list")

    local function DisplayTargetLevel()
        -- Util.IsInGame() returns a number (0 or 1), not a real Lua boolean -- "not Util.IsInGame()"
        -- would never be true even when not in-game, since 0 is truthy in Lua.
        if Util.IsInGame() == 0 then return end

        -- AlwaysAutoResize (used elsewhere in this pack) forces the window back to fit its
        -- content every frame, which overrides any manual resize -- deliberately NOT used here
        -- so you can drag-resize this box. SetNextWindowSize only sets the STARTING size
        -- (FirstUseEver), so resizing it yourself sticks after that.
        ImGui.SetNextWindowSize(220, 80, ImGuiCond.FirstUseEver)
        local window_flags = ImGuiWindowFlags.NoTitleBar
        if ImGui.Begin("Target Level", true, window_flags) then
            local entity = EntityList.GetEntityById(Player.GetTargetEntityId())
            if entity == nil then
                ImGui.Text("Target: (none)")
                ImGui.Text("Level: --")
            else
                ImGui.Text("Target: " .. entity.name)
                ImGui.Separator()
                ImGui.Text("Level: " .. tostring(entity.level))
            end
        end
        ImGui.End()
    end

    ModPack = ModPack or {}
    ModPack.TargetLevel = {
        display_name = "Target Level",
        Update = DisplayTargetLevel,
        Settings = nil,   -- no settings panel for this simple mod
        OnDisable = nil,  -- no native UI to restore
    }
end
-- ============================================================================
-- MASTER DISPATCHER (ties every mod above together)
-- ============================================================================

local function GetModPackSettingsFilePath()
    return UiForge.resources_path .. "\\modern_ui_mods_settings.cfg"
end

local function BuildModEnabledSnapshot()
    local lines = {}
    for _, key in ipairs(MOD_ORDER) do
        lines[#lines + 1] = key .. "=" .. (modern_ui_mods_state.mod_enabled[key] and "true" or "false")
    end
    return table.concat(lines, "\n")
end

local function SaveModEnabledIfChanged()
    local snapshot = BuildModEnabledSnapshot()
    if snapshot ~= modern_ui_mods_state._settings_snapshot then
        local file = io.open(GetModPackSettingsFilePath(), "w")
        if file ~= nil then
            file:write("# modern_ui_mods_settings.cfg -- which mods are enabled. Delete to reset all to on.\n")
            file:write(snapshot)
            file:write("\n")
            file:close()
            modern_ui_mods_state._settings_snapshot = snapshot
        end
    end
end

local function LoadModEnabledFromFile()
    local file = io.open(GetModPackSettingsFilePath(), "r")
    if file == nil then return end

    for line in file:lines() do
        local trimmed = (tostring(line):gsub("^%s+", ""):gsub("%s+$", ""))
        if trimmed ~= "" and not trimmed:match("^#") then
            local key, raw_value = trimmed:match("^([%w_]+)=(.*)$")
            if key ~= nil and modern_ui_mods_state.mod_enabled[key] ~= nil then
                modern_ui_mods_state.mod_enabled[key] = (raw_value == "true")
            end
        end
    end

    file:close()
    modern_ui_mods_state._settings_snapshot = BuildModEnabledSnapshot()
end

local function Initialize()
    if modern_ui_mods_state.settings_file_loaded == false then
        LoadModEnabledFromFile()
        modern_ui_mods_state.settings_file_loaded = true
    end
    modern_ui_mods_state.initialized = true
end

-- Master Settings: one collapsible section per mod, with its own Enable checkbox followed by
-- its full settings panel (unchanged from when it was a standalone script).
local function Settings()
    local state = modern_ui_mods_state

    ImGui.TextUnformatted("Modern UI Mods -- expand a section below to enable/configure it.")
    ImGui.Separator()

    for _, key in ipairs(MOD_ORDER) do
        local mod = ModPack[key]
        if mod ~= nil then
            if ImGui.CollapsingHeader(mod.display_name) then
                ImGui.Indent()

                local new_val, pressed = ImGui.Checkbox("Enable " .. mod.display_name, state.mod_enabled[key])
                if pressed then
                    state.mod_enabled[key] = new_val
                    -- Restore whatever native UI this mod was hiding immediately on disable,
                    -- the same way UiForge used to do automatically when this was its own
                    -- separate script and you unchecked it in the script list.
                    if new_val == false and mod.OnDisable ~= nil then
                        mod.OnDisable()
                    end
                end

                if mod.Settings ~= nil then
                    ImGui.Separator()
                    mod.Settings()
                else
                    ImGui.TextUnformatted("(no additional settings for this mod)")
                end

                ImGui.Unindent()
            end
        end
    end

    SaveModEnabledIfChanged()
end

-- Master DisableScript: fires when the WHOLE combined file gets unchecked in UiForge's script
-- list. Restores every mod's native UI regardless of each mod's own individual enabled state,
-- so nothing is left hidden.
local function OnDisable()
    for _, key in ipairs(MOD_ORDER) do
        local mod = ModPack[key]
        if mod ~= nil and mod.OnDisable ~= nil then
            local ok, err = pcall(mod.OnDisable)
            if not ok then
                -- Never let one mod's cleanup failure stop the others from cleaning up too.
                print("Modern UI Mods: OnDisable failed for " .. tostring(key) .. ": " .. tostring(err))
            end
        end
    end
end

-- Master Save/Load: combines every mod that has its own Save/Load (HealthBar, ManaBar, ExpBars,
-- ChatLog) into one profile entry, keyed by mod name.
local function Save()
    local saved = {}
    for _, key in ipairs(MOD_ORDER) do
        local mod = ModPack[key]
        if mod ~= nil and mod.Save ~= nil then
            local ok, result = pcall(mod.Save)
            if ok then
                saved[key] = result
            end
        end
    end
    return saved
end

local function Load(saved)
    if type(saved) ~= "table" then return end
    for _, key in ipairs(MOD_ORDER) do
        local mod = ModPack[key]
        if mod ~= nil and mod.Load ~= nil and saved[key] ~= nil then
            pcall(mod.Load, saved[key])
        end
    end
end

-- Master Render: calls each enabled mod's own Update() (which itself already handles that mod's
-- lazy Initialize(), any per-frame native-UI maintenance, and its Render()) -- unchanged from
-- what each mod already did as a standalone script, just gated by our own enabled flag now.
local function Render()
    for _, key in ipairs(MOD_ORDER) do
        local mod = ModPack[key]
        if mod ~= nil and modern_ui_mods_state.mod_enabled[key] == true then
            local ok, err = pcall(mod.Update)
            if not ok then
                print("Modern UI Mods: Update failed for " .. tostring(key) .. ": " .. tostring(err))
            end
        end
    end
end

local function RegisterCallbacks()
    UiForge.RegisterCallback(UiForge.CallbackType.Settings, Settings)
    UiForge.RegisterCallback(UiForge.CallbackType.DisableScript, OnDisable)
    UiForge.RegisterCallback(UiForge.CallbackType.Save, Save)
    UiForge.RegisterCallback(UiForge.CallbackType.Load, Load)
    modern_ui_mods_state.callbacks_registered = true
end

if modern_ui_mods_state.initialized == false then Initialize() end

if modern_ui_mods_state.callbacks_registered == false then RegisterCallbacks() end

Render()
