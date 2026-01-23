local  bit = require("bit")

state = state or {
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
    line_thickness      = 1,
    sides               = 5,
    line_color          = {0, 0, 0, 1},
    demo_window_flags   = ImGuiWindowFlags.None,
    demo_cur_health     = 100,
    demo_max_health     = 100,
    demo_damage         = 10,
    image_texture       = nil,
    image_width         = 64,
    image_height        = 64,
    image_tint          = {1, 1, 1, 1},
    image_border_col    = {0, 0, 0, 0}

}

-- Make a window
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
        end   -- Make Buttons like this
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

    -- Seperator
    ImGui.Separator()

    -- use ImVec2 and ImVec4
    local vec2 = ImVec2.new(10.0, 21.0)
    local vec4 = ImVec4.new(1, 2, 3, 4)
    -- ImGui.Text("ImVec2: " .. vec2.x .. ", " .. vec2.y)
    -- ImGui.Text("ImVec4: " .. vec4.x .. ", " .. vec4.y .. ", " .. vec4.z .. ", " .. vec4.w)
    
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

    -- Window Flags

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

    if ImGui.TreeNode("Images") then
        if state.image_texture == nil then
            state.image_texture = UiForge.IGraphicsApi.CreateTextureFromFile(UiForge.resources_path .. "\\gear-icon.png")
        end
        
        if state.image_texture ~= nil then
            state.image_width = ImGui.SliderInt("Image Width", state.image_width, 32, 128)
            state.image_height = ImGui.SliderInt("Image Height", state.image_height, 32, 128)
            state.image_tint = ImGui.ColorEdit4("Image Tint", state.image_tint)
            state.image_border_col = ImGui.ColorEdit4("Image Border Color", state.image_border_col)
            
            -- local image_tint = ImGui.GetColorU32(state.image_tint[1], state.image_tint[2], state.image_tint[3] , state.image_tint[4])
            -- local image_border_col = ImGui.GetColorU32(state.image_border_col[1], state.image_border_col[2], state.image_border_col[3] , state.image_border_col[4])
            
            -- Simplified image call
            ImGui.Image(state.image_texture, state.image_width, state.image_height)
            ImGui.SameLine()
            
            -- Advanced image calls
            -- ImGui.GetWindowDrawList():AddImage( state.image_texture,
            --                                     ImVec2.new(0,0),
            --                                     ImVec2.new(state.image_width, state.image_height),
            --                                     ImVec2.new(0,0),
            --                                     ImVec2.new(1,1),
            --                                     ImGui.GetColorU32(state.image_tint[1], state.image_tint[2], state.image_tint[3] , state.image_tint[4])
            --                                   )
            ImGui.Dummy(state.image_width, state.image_height)
            ImGui.SameLine()

            ImGui.Image(state.image_texture,
                        ImVec2.new(state.image_width, state.image_height),
                        ImVec2.new(0,0),
                        ImVec2.new(1,1),
                        ImVec4.new(state.image_tint[1], state.image_tint[2], state.image_tint[3] , state.image_tint[4]),
                        ImVec4.new(state.image_border_col[1], state.image_border_col[2], state.image_border_col[3] , state.image_border_col[4])
                        )
        end
        ImGui.TreePop()
    end

end

--end the window
ImGui.End()