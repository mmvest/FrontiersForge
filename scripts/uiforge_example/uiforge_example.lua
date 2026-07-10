-- uiforge_example.lua
-- A single tour of UiForge's features. Widgets, drawing, window flags,
-- packaged modules and resources, fonts, audio, and an animated bouncing
-- balls demo wired into the Settings/Save/Load callbacks.

local bit = require("bit")

-- click_tally lives in this package's own modules folder
-- (scripts\uiforge_example\modules\click_tally.lua). No entry in the shared
-- scripts\modules directory is needed. Because modules are cached by
-- require, the tally persists across frames even though this script file
-- re-runs every frame.
local ClickTally = require("click_tally")

-- ===============================
-- Bouncing balls demo
-- ===============================

local Ball = {}
Ball.__index = Ball

function Ball:new(position, velocity, radius, color)
    return setmetatable({
        position = position,
        velocity = velocity,
        radius = radius,
        color = color,
    }, self)
end

state = state or {
    callbacks_registered = false,

    -- Basic widgets
    button_clicked      = false,
    checkbox_checked    = false,
    radio_buttons       = 0,
    input_demo_text     = "Type here...",
    input_demo_label    = "Label will update on Enter",
    slider_float        = 0.5,
    slider_int          = 5,
    combo_items         = {"Item 01", "Item 02", "Item 03"},
    combo_index         = 0,
    color4              = { 1, .5, .25, 1},
    progress_percent    = 0,

    -- Drawing
    line_thickness      = 1,
    sides               = 5,
    line_color          = {0, 0, 0, 1},

    -- Window flags
    demo_window_flags   = ImGuiWindowFlags.None,
    demo_cur_health     = 100,
    demo_max_health     = 100,
    demo_damage         = 10,

    -- Images
    image_texture       = nil,
    global_image_texture = nil,
    image_width         = 64,
    image_height        = 64,
    image_tint          = {1, 1, 1, 1},
    image_border_col    = {0, 0, 0, 0},

    -- Audio
    sound_volume        = 1.0,
    sound_loop          = false,

    -- Bouncing balls
    balls               = {},
    ball_count          = 10,
    ball_area           = {x = 400, y = 250},
    last_frame_time     = 0,
}

local function RandomFloat(min, max)
    return min + math.random() * (max - min)
end

local function PopulateBalls(count, area)
    state.balls = {}
    for i = 1, count do
        local radius = RandomFloat(10, 20)
        local position = {
            x = RandomFloat(radius, area.x - radius),
            y = RandomFloat(radius, area.y - radius),
        }
        local velocity = {
            x = math.random(2) == 1 and RandomFloat(-15, -8) or RandomFloat(8, 15),
            y = math.random(2) == 1 and RandomFloat(-15, -8) or RandomFloat(8, 15),
        }
        local color = RandomFloat(0xFF000000, 0xFFFFFFFF)
        table.insert(state.balls, Ball:new(position, velocity, radius, color))
    end
end

local function UpdateBalls(delta_time, area)
    for i = 1, #state.balls do
        local ball = state.balls[i]

        ball.position.x = ball.position.x + ball.velocity.x * delta_time
        ball.position.y = ball.position.y + ball.velocity.y * delta_time

        -- Bounce off edges
        if ball.position.x - ball.radius < 0 or ball.position.x + ball.radius > area.x then
            ball.velocity.x = -ball.velocity.x
        end
        if ball.position.y - ball.radius < 0 or ball.position.y + ball.radius > area.y then
            ball.velocity.y = -ball.velocity.y
        end

        -- Ball-to-ball collisions, resolved by swapping velocities
        for j = i + 1, #state.balls do
            local other = state.balls[j]
            local dx = ball.position.x - other.position.x
            local dy = ball.position.y - other.position.y
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance < ball.radius + other.radius then
                ball.velocity, other.velocity = other.velocity, ball.velocity
            end
        end
    end
end

local function RenderBalls(origin)
    local draw_list = ImGui.GetWindowDrawList()
    for _, ball in ipairs(state.balls) do
        draw_list:AddCircleFilled(ImVec2.new(origin.x + ball.position.x, origin.y + ball.position.y), ball.radius, ball.color)
    end
end

-- ===============================
-- Callbacks (Settings / Save / Load)
-- ===============================

-- Rendered inside the UiForge Settings panel when this script is selected
local function Settings()
    local value, clicked = ImGui.SliderInt("Number of Balls", state.ball_count, 1, 100)
    if value ~= state.ball_count and clicked then
        state.ball_count = value
        PopulateBalls(state.ball_count, state.ball_area)
    end
end

-- Save callback. Returns a plain-data table describing the current simulation.
-- The core captures it into the profile being saved (File > Save Profile).
local function Save()
    local saved_balls = {}
    for i, ball in ipairs(state.balls) do
        saved_balls[i] = {
            position = { x = ball.position.x, y = ball.position.y },
            velocity = { x = ball.velocity.x, y = ball.velocity.y },
            radius   = ball.radius,
            color    = ball.color,
        }
    end

    return {
        ball_count = state.ball_count,
        balls      = saved_balls,
    }
end

-- Load callback. Receives the table produced by Save when a profile is applied
-- and rebuilds the simulation from it, so the balls jump back to their saved spots.
local function Load(saved_state)
    if type(saved_state) ~= "table" then
        return
    end

    if saved_state.ball_count then
        state.ball_count = saved_state.ball_count
    end

    if type(saved_state.balls) == "table" then
        state.balls = {}
        for i, saved_ball in ipairs(saved_state.balls) do
            state.balls[i] = Ball:new(
                { x = saved_ball.position.x, y = saved_ball.position.y },
                { x = saved_ball.velocity.x, y = saved_ball.velocity.y },
                saved_ball.radius,
                saved_ball.color
            )
        end
    end
end

if state.callbacks_registered == false then
    UiForge.RegisterCallback(UiForge.CallbackType.Settings, Settings)
    UiForge.RegisterCallback(UiForge.CallbackType.Save, Save)
    UiForge.RegisterCallback(UiForge.CallbackType.Load, Load)
    state.callbacks_registered = true
end

-- ===============================
-- Fonts and audio (loaded once, cached by UiForge)
-- ===============================

-- LoadFont always returns a usable font, falling back to the default font when
-- the file is missing or fails to load, so PushFont is always safe.
local times_font = UiForge.LoadFont("C:\\Windows\\Fonts\\times.ttf", 20.0)
local times_font_large = UiForge.LoadFont("C:\\Windows\\Fonts\\times.ttf", 36.0)
local missing_font = UiForge.LoadFont("C:\\Windows\\Fonts\\does_not_exist.ttf", 20.0)

-- LoadSound returns nil when the file cannot be opened, and every other sound
-- function safely accepts a nil handle. This clip ships with every Windows install.
local tada_sound = UiForge.LoadSound("C:\\Windows\\Media\\tada.wav")

-- ===============================
-- Main window
-- ===============================

if ImGui.Begin("Hello, UiForge!", true, ImGuiWindowFlags.MenuBar) then
    -- Menu Bars
    if ImGui.BeginMenuBar() then
        if ImGui.BeginMenu("Menu 01") then
            if ImGui.MenuItem("Item 01") then
                -- Do a thing
            end
            if ImGui.MenuItem("Item 02") then
                -- Do a thing
            end
            ImGui.EndMenu()
        end
        if ImGui.BeginMenu("Menu 02") then
            if ImGui.MenuItem("Item 01") then
                -- Do a thing
            end
            if ImGui.MenuItem("Item 02") then
                -- Do a thing
            end
            ImGui.EndMenu()
        end
        ImGui.EndMenuBar()
    end

    if ImGui.TreeNode("Basic Widgets") then
        -- Display text
        ImGui.Text("You can display text like this.")
        ImGui.BulletText("This is a bullet point!")
        -- Button
        if ImGui.Button("Click Me!", 200, 50) then
            state.button_clicked = not state.button_clicked
        end
        if state.button_clicked then
            ImGui.Text("Button Clicked!")
        end

        -- Checkbox
        state.checkbox_checked = ImGui.Checkbox("I am a checkbox", state.checkbox_checked)
        ImGui.SameLine()

        -- Tooltips
        ImGui.Text("(?)")
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("This is a tooltip!")
        end

        -- Radio buttons -- I use an override of the function that isn't in meta.lua
        if ImGui.RadioButton("Radio 01", state.radio_buttons == 1) then
            state.radio_buttons = 1
        end

        if ImGui.RadioButton("Radio 02", state.radio_buttons == 2) then
            state.radio_buttons = (state.radio_buttons == 2) and 0 or 2   -- Makes the button toggleable on and off by clicking it again
        end

        -- Combo Box
        state.combo_index = ImGui.Combo("Combo Box", state.combo_index, state.combo_items, #state.combo_items)

        -- Input Text (press Enter to "submit")
        ImGui.Separator()
        ImGui.Text("Input box demo")
        ImGui.TextDisabled("Hit Enter to change label")
        local enter_returns_true_flag = (ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue) or 0
        local new_text, enter_pressed = ImGui.InputText("Input Box", state.input_demo_text, enter_returns_true_flag)
        state.input_demo_text = new_text
        if enter_pressed then
            state.input_demo_label = (state.input_demo_text ~= "" and state.input_demo_text) or "(empty)"
        end
        ImGui.Text("Label: " .. state.input_demo_label)
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Sliders and Progress Bars") then
        -- Sliders
        state.slider_float = ImGui.SliderFloat("Float Slider", state.slider_float, 0, 1.0)
        state.slider_int = ImGui.SliderInt("Int Slider", state.slider_int, 0, 10, "Slider Text: " .. state.slider_int)

        -- Color Picker
        state.color4 = ImGui.ColorEdit4("Color Picker", state.color4)

        -- Progress Bar
        local progress_text = string.format("Loading... (%.1f%%)", state.progress_percent * 100)
        ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0, .302, 0, 1)    -- Change the color
        ImGui.ProgressBar(state.progress_percent, 200, 20, progress_text)
        ImGui.PopStyleColor()
        state.progress_percent = state.progress_percent + .001
        if state.progress_percent >= 1 then
            state.progress_percent = 0
        end

        ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0, 0, 1, 1)
        ImGui.ProgressBar(-0.4 * ImGui.GetTime(), 0, 0, "Searching...")
        ImGui.PopStyleColor()
        ImGui.TreePop()
    end

    -- Tabs
    if ImGui.TreeNode("Tabs") then
        if ImGui.BeginTabBar("Tabs") then
            if ImGui.BeginTabItem("Tab 01") then
                ImGui.Text("This is the content for tab 1")
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem("Tab 02") then
                ImGui.Button("This is the content for tab 2")
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem("Tab 03") then
                ImGui.Text("This is the content for tab 3")
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
        ImGui.TreePop()
    end

    ImGui.Separator()

    if ImGui.TreeNode("Drawing") then
        -- Draw Primitives
        local draw_list = ImGui.GetWindowDrawList()

        state.line_thickness = ImGui.SliderInt("Line Thickness", state.line_thickness, 0, 5)
        state.sides = ImGui.SliderInt("Ngon Sides", state.sides, 3, 32)
        state.line_color = ImGui.ColorEdit4("Line Color", state.line_color)
        local line_color = ImGui.GetColorU32(state.line_color[1], state.line_color[2], state.line_color[3] , state.line_color[4])

        -- Rectangle
        local rect_p0 = ImVec2.new(ImGui.GetCursorScreenPos())      -- Functions that return two floats can be directly used in ImVec2
        local rect_p1 = ImVec2.new(rect_p0.x + 50 , rect_p0.y + 50)
        draw_list:AddRectFilled(rect_p0, rect_p1, 0xFF0000FF)
        draw_list:AddRect(rect_p0, rect_p1, line_color, 0, 0, state.line_thickness)

        -- Circle
        local circle_center = ImVec2.new(rect_p1.x + (rect_p1.x - rect_p0.x)/2, rect_p0.y + (rect_p1.y - rect_p0.y)/2)
        local circle_radius = (rect_p1.x - rect_p0.x)/2
        draw_list:AddCircleFilled(circle_center, circle_radius, 0xFF00FF00)
        draw_list:AddCircle(circle_center, circle_radius, line_color, 0, state.line_thickness)

        -- Triangle
        local triangle_p0 = ImVec2.new(rect_p1.x + circle_radius * 2, rect_p1.y)
        local triangle_p1 = ImVec2.new(rect_p1.x + circle_radius * 2 + (rect_p1.x - rect_p0.x)/2, rect_p0.y)
        local triangle_p2 = ImVec2.new(rect_p1.x + circle_radius * 4, rect_p1.y)
        draw_list:AddTriangleFilled(triangle_p0, triangle_p1, triangle_p2, 0xFFFF0000)
        draw_list:AddTriangle(triangle_p0, triangle_p1, triangle_p2, line_color, state.line_thickness)

        -- N-Gon
        local ngon_center = ImVec2.new(circle_center.x + (rect_p1.x - rect_p0.x) * 2, circle_center.y)
        local ngon_radius = circle_radius
        draw_list:AddNgonFilled(ngon_center, ngon_radius, 0xFFFFFFFF, state.sides)
        draw_list:AddNgon(ngon_center, ngon_radius, line_color, state.sides, state.line_thickness)
        ImGui.Dummy(0, 60) -- Create a buffer space for the shapes since using ImDrawList doesn't move the cursor
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Window Flags") then
        local flags = {
            { name = "No Title Bar",                flag = ImGuiWindowFlags.NoTitleBar },
            { name = "No Resize",                   flag = ImGuiWindowFlags.NoResize },
            { name = "No Move",                     flag = ImGuiWindowFlags.NoMove },
            { name = "No Scrollbar",                flag = ImGuiWindowFlags.NoScrollbar },
            { name = "No Scroll With Mouse",        flag = ImGuiWindowFlags.NoScrollWithMouse },
            { name = "No Collapse",                 flag = ImGuiWindowFlags.NoCollapse },
            { name = "Always Auto Resize",          flag = ImGuiWindowFlags.AlwaysAutoResize },
            { name = "No Background",               flag = ImGuiWindowFlags.NoBackground },
            { name = "No Saved Settings",           flag = ImGuiWindowFlags.NoSavedSettings },
            { name = "No Mouse Inputs",             flag = ImGuiWindowFlags.NoMouseInputs },
            { name = "Menu Bar",                    flag = ImGuiWindowFlags.MenuBar },
            { name = "Horizontal Scrollbar",        flag = ImGuiWindowFlags.HorizontalScrollbar },
            { name = "No Focus On Appearing",       flag = ImGuiWindowFlags.NoFocusOnAppearing },
            { name = "No Bring To Front On Focus",  flag = ImGuiWindowFlags.NoBringToFrontOnFocus },
            { name = "Always Vertical Scrollbar",   flag = ImGuiWindowFlags.AlwaysVerticalScrollbar },
            { name = "Always Horizontal Scrollbar", flag = ImGuiWindowFlags.AlwaysHorizontalScrollbar },
            { name = "No Nav Inputs",               flag = ImGuiWindowFlags.NoNavInputs },
            { name = "No Nav Focus",                flag = ImGuiWindowFlags.NoNavFocus },
            { name = "No Nav",                      flag = ImGuiWindowFlags.NoNav },
            { name = "No Decoration",               flag = ImGuiWindowFlags.NoDecoration },
            { name = "No Inputs",                   flag = ImGuiWindowFlags.NoInputs }
        }

        for _, item in ipairs(flags) do
            local new_val, pressed = ImGui.Checkbox(item.name, bit.band(state.demo_window_flags, item.flag) ~= 0)
            if pressed then
                state.demo_window_flags = bit.bxor(state.demo_window_flags, item.flag)
            end
        end

        ImGui.Begin("Demo Window", true, state.demo_window_flags)

        ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0, .33, 0, 1)
        ImGui.ProgressBar(state.demo_cur_health / state.demo_max_health, state.demo_max_health, 30, state.demo_cur_health .. "/" .. state.demo_max_health)
        ImGui.PopStyleColor()
        ImGui.SameLine()
        if ImGui.Button("Hit", 30, 30) then
            if state.demo_cur_health <= 0 then
                state.demo_cur_health = state.demo_max_health
            else
                state.demo_cur_health = state.demo_cur_health - state.demo_damage
            end
        end

        ImGui.End()

        ImGui.TreePop()
    end

    if ImGui.TreeNode("Local Module Demo (click_tally)") then
        ImGui.Text("This section uses a module bundled inside this script's package,")
        ImGui.Text("loaded with require(\"click_tally\").")

        if ImGui.Button("Tally Button A") then
            ClickTally.Record("Tally Button A")
        end
        ImGui.SameLine()
        if ImGui.Button("Tally Button B") then
            ClickTally.Record("Tally Button B")
        end
        ImGui.SameLine()
        if ImGui.Button("Reset Tally") then
            ClickTally.Reset()
        end

        ImGui.Text("ClickTally.GetTotal(): " .. ClickTally.GetTotal())
        ImGui.Text("ClickTally.GetSummary(): " .. ClickTally.GetSummary())
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Images") then
        if state.image_texture == nil then
            -- PER PACKAGE RESOURCE
            -- Relative paths resolve against this package's own resources folder
            -- first (scripts\uiforge_example\resources), then fall back to the
            -- shared scripts\resources directory.
            state.image_texture = UiForge.LoadTexture("gear-icon.png")
        end

        if state.global_image_texture == nil then
            -- GLOBAL RESOURCE
            -- To load from the shared scripts\resources directory explicitly,
            -- build an absolute path with UiForge.resources_path. Absolute paths
            -- skip the per package lookup entirely.
            state.global_image_texture = UiForge.LoadTexture(UiForge.resources_path .. "\\gear-icon.png")
        end

        if state.image_texture ~= nil then
            state.image_width = ImGui.SliderInt("Image Width", state.image_width, 32, 128)
            state.image_height = ImGui.SliderInt("Image Height", state.image_height, 32, 128)
            state.image_tint = ImGui.ColorEdit4("Image Tint", state.image_tint)
            state.image_border_col = ImGui.ColorEdit4("Image Border Color", state.image_border_col)

            -- Simplified image call, drawing the PER PACKAGE copy of the icon
            ImGui.Image(state.image_texture, state.image_width, state.image_height)
            ImGui.SameLine()
            ImGui.Dummy(state.image_width, state.image_height)
            ImGui.SameLine()

            -- Advanced image call, drawing the GLOBAL copy of the icon loaded
            -- from the shared resources directory
            if state.global_image_texture ~= nil then
                ImGui.Image(state.global_image_texture,
                            ImVec2.new(state.image_width, state.image_height),
                            ImVec2.new(0,0),
                            ImVec2.new(1,1),
                            ImVec4.new(state.image_tint[1], state.image_tint[2], state.image_tint[3] , state.image_tint[4]),
                            ImVec4.new(state.image_border_col[1], state.image_border_col[2], state.image_border_col[3] , state.image_border_col[4])
                            )
            end

            ImGui.Text("Left icon: package resource via UiForge.LoadTexture(\"gear-icon.png\")")
            ImGui.Text("Right icon: global resource via UiForge.LoadTexture(UiForge.resources_path .. \"\\\\gear-icon.png\")")
        end
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Fonts") then
        ImGui.Text("This line uses the default font.")

        ImGui.PushFont(times_font)
        ImGui.Text("This line uses Times New Roman at 20px.")
        ImGui.PopFont()

        ImGui.PushFont(times_font_large)
        ImGui.Text("This line uses Times New Roman at 36px.")
        ImGui.PopFont()

        ImGui.PushFont(missing_font)
        ImGui.Text("This line asked for a missing font and fell back to the default.")
        ImGui.PopFont()
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Audio") then
        if tada_sound == nil then
            ImGui.Text("Could not load C:\\Windows\\Media\\tada.wav")
        else
            ImGui.Text("Sound handle: " .. tada_sound)
            ImGui.Text("IsSoundPlaying: " .. tostring(UiForge.IsSoundPlaying(tada_sound)))

            if ImGui.Button("Play") then
                UiForge.PlaySound(tada_sound, {
                    volume = state.sound_volume,
                    loop = state.sound_loop,
                })
            end
            ImGui.SameLine()
            if ImGui.Button("Stop") then
                UiForge.StopSound(tada_sound)
            end

            local volume, changed = ImGui.SliderFloat("Volume", state.sound_volume, 0.0, 1.0)
            if changed then
                state.sound_volume = volume
                -- Takes effect immediately, even while the sound is playing.
                UiForge.SetSoundVolume(tada_sound, volume)
            end

            state.sound_loop = ImGui.Checkbox("Loop", state.sound_loop)
        end
        ImGui.TreePop()
    end

    if ImGui.TreeNode("Bouncing Balls") then
        ImGui.Text("The ball count lives in this script's Settings callback,")
        ImGui.Text("and the simulation is captured by the Save/Load callbacks (profiles).")

        local current_time = ImGui.GetTime()
        local delta_time = current_time - state.last_frame_time
        state.last_frame_time = current_time

        if ImGui.BeginChild("BallArea", state.ball_area.x, state.ball_area.y, ImGuiChildFlags.Border) then
            local origin = {}
            origin.x, origin.y = ImGui.GetCursorScreenPos()

            if #state.balls ~= state.ball_count then
                PopulateBalls(state.ball_count, state.ball_area)
            end

            UpdateBalls(delta_time, state.ball_area)
            RenderBalls(origin)
        end
        ImGui.EndChild()
        ImGui.TreePop()
    end
end

--end the window
ImGui.End()
