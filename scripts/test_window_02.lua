-- Ball structure
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

-- Globals
test_02_state = test_02_state or {
    settings_registered = false,
    balls = {},
    ball_count = 10,
    window_size = {x = 500, y = 500},
    last_frame_time = 0
}

-- Helper functions
local function RandomFloat(min, max)
    return min + math.random() * (max - min)
end

local function PopulateBalls(count, window_size)
    test_02_state.balls = {}
    for i = 1, count do
        local radius = RandomFloat(10, 20)
        local position = {
            x = RandomFloat(radius, window_size.x - radius),
            y = RandomFloat(radius, window_size.y - radius),
        }
        local velocity = {
            x = math.random(2) == 1 and RandomFloat(-15, -8) or RandomFloat(8, 15),
            y = math.random(2) == 1 and RandomFloat(-15, -8) or RandomFloat(8, 15),
        }
        local color = RandomFloat(0xFF000000, 0xFFFFFFFF)
        table.insert(test_02_state.balls, Ball:new(position, velocity, radius, color))
    end
end

local function UpdateBalls(delta_time, window_size)
    for i = 1, #test_02_state.balls do
        local ball = test_02_state.balls[i]

        -- Update position
        ball.position.x = ball.position.x + ball.velocity.x * delta_time
        ball.position.y = ball.position.y + ball.velocity.y * delta_time

        -- Bounce off edges
        if ball.position.x - ball.radius < 0 or ball.position.x + ball.radius > window_size.x then
            ball.velocity.x = -ball.velocity.x
        end
        if ball.position.y - ball.radius < 0 or ball.position.y + ball.radius > window_size.y then
            ball.velocity.y = -ball.velocity.y
        end

        -- Handle ball-to-ball collisions
        for j = i + 1, #test_02_state.balls do
            local other = test_02_state.balls[j]
            local dx = ball.position.x - other.position.x
            local dy = ball.position.y - other.position.y
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance < ball.radius + other.radius then
                -- Swap velocities
                ball.velocity, other.velocity = other.velocity, ball.velocity
            end
        end
    end
end

local function RenderBalls(window_pos)
    local draw_list = ImGui.GetWindowDrawList()
    for _, ball in ipairs(test_02_state.balls) do
        draw_list:AddCircleFilled(ImVec2.new(window_pos.x + ball.position.x, window_pos.y + ball.position.y), ball.radius, ball.color)
    end
end

-- Register settings function
local function Settings()
    -- Slider to adjust the number of balls
    local value, clicked = ImGui.SliderInt("Number of Balls", test_02_state.ball_count, 1, 100)
    if value ~= test_02_state.ball_count and clicked then
        test_02_state.ball_count = value
        PopulateBalls(test_02_state.ball_count, test_02_state.window_size)
    end
end

-- Save callback. Returns a plain-data table describing the current simulation.
-- The core captures it into the profile being saved (File > Save Profile).
-- We snapshot every ball's position, velocity, radius and color so the exact
-- frozen frame can be restored later.
local function Save()
    local saved_balls = {}
    for i, ball in ipairs(test_02_state.balls) do
        saved_balls[i] = {
            position = { x = ball.position.x, y = ball.position.y },
            velocity = { x = ball.velocity.x, y = ball.velocity.y },
            radius   = ball.radius,
            color    = ball.color,
        }
    end

    return {
        ball_count = test_02_state.ball_count,
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
        test_02_state.ball_count = saved_state.ball_count
    end

    if type(saved_state.balls) == "table" then
        test_02_state.balls = {}
        for i, saved_ball in ipairs(saved_state.balls) do
            test_02_state.balls[i] = Ball:new(
                { x = saved_ball.position.x, y = saved_ball.position.y },
                { x = saved_ball.velocity.x, y = saved_ball.velocity.y },
                saved_ball.radius,
                saved_ball.color
            )
        end
    end
end

if test_02_state.settings_registered == false then
    UiForge.RegisterCallback(UiForge.CallbackType.Settings, Settings)
    UiForge.RegisterCallback(UiForge.CallbackType.Save, Save)
    UiForge.RegisterCallback(UiForge.CallbackType.Load, Load)
    test_02_state.settings_registered = true
end


if ImGui.Begin("Bouncing Balls Simulation") then
    -- for key, value in pairs(test_02_state.balls) do
    --     ImGui.Text(""..key..": ".. tostring(value))
    -- end

    -- Get delta time
    local current_time = ImGui.GetTime()
    local delta_time = current_time - test_02_state.last_frame_time
    test_02_state.last_frame_time = current_time

    -- Get window size and position
    test_02_state.window_size.x, test_02_state.window_size.y = ImGui.GetContentRegionAvail()
    local window_pos = {}
    window_pos.x, window_pos.y = ImGui.GetCursorScreenPos()

    -- Initialize balls if needed
    if #test_02_state.balls ~= test_02_state.ball_count then
        PopulateBalls(test_02_state.ball_count, test_02_state.window_size)
    end

    -- Update and render balls
    UpdateBalls(delta_time, test_02_state.window_size)

    RenderBalls(window_pos)

end
ImGui.End()
