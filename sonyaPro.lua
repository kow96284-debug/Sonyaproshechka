--[[
    Sonya Pro | Blade Ball (Optimized for Xeno / 2026)
    Universal | Pink Theme | Anti-Detect Hardened
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Config = {
    AutoParry = true,
    AutoSpam = true,
    ParryRange = 58,
    BaseThreshold = 0.12,
    VelocityScaleFast = 0.0065,
    VelocityScaleSlow = 0.008,
    UseRemote = true,

    NormalCPS = 200,
    MacroCPS = 580,
    CloseDistance = 25,
    ExtraHits = 4,

    CurveMode = "Camera",
    CurveStrength = 1.4,
    ShowESP = true,
    JitterMS = 10 -- Humanization: 5-15ms random offset
}

-- UI Initialization (Rayfield with fallback)
task.spawn(function()
    local success, Rayfield = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/main.lua"))()
    end)
    
    if not success or not Rayfield then
        warn("[Sonya Pro] UI load failed. Running headless.")
        return
    end

    local Window = Rayfield:CreateWindow({
        Name = "Sonya Pro",
        LoadingTitle = "Sonya Pro",
        LoadingSubtitle = "Universal 2026",
        ConfigurationSaving = { Enabled = false },
        KeySystem = false,
    })

    local Tab = Window:CreateTab("Main", 4483362458)

    Tab:CreateToggle({ Name = "Auto Parry", CurrentValue = true, Callback = function(v) Config.AutoParry = v end })
    Tab:CreateToggle({ Name = "Auto Spam", CurrentValue = true, Callback = function(v) Config.AutoSpam = v end })
    Tab:CreateSlider({ Name = "Normal CPS", Range = {80, 350}, Increment = 10, CurrentValue = 200, Callback = function(v) Config.NormalCPS = v end })
    Tab:CreateSlider({ Name = "Macro CPS (Ctrl)", Range = {250, 700}, Increment = 20, CurrentValue = 580, Callback = function(v) Config.MacroCPS = v end })
    Tab:CreateDropdown({ Name = "Curve Mode", Options = {"Camera", "Random", "Backwards", "High", "Accelerated"}, CurrentOption = "Camera", Callback = function(v) Config.CurveMode = v end })
    Tab:CreateToggle({ Name = "Ball ESP", CurrentValue = true, Callback = function(v) Config.ShowESP = v end })
end)

-- Core State
local ParryRemote = nil
pcall(function()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        ParryRemote = remotes:FindFirstChild("ParryButtonPress") or remotes:FindFirstChild("Parry")
    end
end)

local lastParry = 0
local spamActive = false
local ctrlHeld = false
local ballHighlight = nil
local cachedBall = nil

local function getPing()
    local ok, ping = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    end)
    return ok and ping or 0.04
end

local function getBall()
    -- Optimized: check common locations first, avoid full GetDescendants unless necessary
    if cachedBall and cachedBall.Parent then return cachedBall end
    
    local folder = workspace:FindFirstChild("Balls") or workspace:FindFirstChild("Ball")
    if folder then
        for _, v in ipairs(folder:GetChildren()) do
            if v:IsA("BasePart") then 
                cachedBall = v
                return v 
            end
        end
    end
    
    -- Fallback: shallow search in workspace
    for _, v in ipairs(workspace:GetChildren()) do
        if v:IsA("BasePart") and string.find(string.lower(v.Name), "ball") then
            cachedBall = v
            return v
        end
    end
    
    cachedBall = nil
    return nil
end

local function isTargetingMe(ball, hrp)
    if not ball or not hrp then return false end
    local vel = ball.AssemblyLinearVelocity or ball.Velocity
    if not vel or vel.Magnitude < 1.5 then return false end
    local dir = (hrp.Position - ball.Position).Unit
    return vel.Unit:Dot(dir) > 0.60
end

local function getDynamicThreshold(speed)
    if speed > 65 then
        return math.max(0.055, Config.BaseThreshold - (speed * Config.VelocityScaleFast))
    else
        return math.min(0.21, Config.BaseThreshold + (speed * Config.VelocityScaleSlow))
    end
end

local function applyCurve()
    if Config.CurveMode == "Random" then
        Camera.CFrame = Camera.CFrame * CFrame.Angles(math.rad(math.random(-18, 18)), math.rad(math.random(-22, 22)), 0)
    elseif Config.CurveMode == "Backwards" then
        Camera.CFrame = Camera.CFrame * CFrame.Angles(0, math.rad(180), 0)
    elseif Config.CurveMode == "High" then
        Camera.CFrame = Camera.CFrame * CFrame.Angles(math.rad(-28 * Config.CurveStrength), 0, 0)
    elseif Config.CurveMode == "Accelerated" then
        Camera.CFrame = Camera.CFrame + Camera.CFrame.LookVector * (9 * Config.CurveStrength)
    end
end

local function fireParry()
    if Config.UseRemote and ParryRemote then
        pcall(function() ParryRemote:FireServer() end)
    else
        -- Fallback: VIM is flagged, use sparingly. Added micro-delay for realism.
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
            task.wait(0.012 + (math.random(5, 15) / 1000))
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        end)
    end
end

local function doParry(extra)
    local now = os.clock()
    local cooldown = 0.04 + (math.random(5, Config.JitterMS) / 1000) -- Humanized jitter
    if now - lastParry < cooldown then return end
    lastParry = now
    
    applyCurve()
    fireParry()
    
    if extra then
        for i = 1, Config.ExtraHits do
            task.wait(0.015 + (math.random(5, 10) / 1000))
            fireParry()
        end
    end
end

-- Heartbeat driven spam loop (avoids while/task.wait detection)
local lastSpam = 0
RunService.Heartbeat:Connect(function()
    if not spamActive then return end
    
    local now = os.clock()
    local cps = ctrlHeld and Config.MacroCPS or Config.NormalCPS
    local delay = 1 / math.clamp(cps, 60, 750)
    
    if now - lastSpam >= delay then
        lastSpam = now
        fireParry()
    end
end)

-- Main Logic Loop
RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local ball = getBall()
    if not ball then
        if ballHighlight then 
            pcall(function() ballHighlight:Destroy() end) 
            ballHighlight = nil 
        end
        if not ctrlHeld then spamActive = false end
        return
    end

    -- ESP Management
    if Config.ShowESP then
        if not ballHighlight or ballHighlight.Parent ~= ball then
            if ballHighlight then pcall(function() ballHighlight:Destroy() end) end
            local ok, hl = pcall(function()
                local h = Instance.new("Highlight")
                h.FillColor = Color3.fromRGB(255, 105, 180)
                h.OutlineColor = Color3.fromRGB(255, 182, 193)
                h.FillTransparency = 0.35
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = ball
                return h
            end)
            if ok then ballHighlight = hl end
        end
    end

    local vel = ball.AssemblyLinearVelocity or ball.Velocity or Vector3.zero
    local speed = vel.Magnitude
    local dist = (ball.Position - hrp.Position).Magnitude
    local relative = math.max(0.1, vel:Dot((hrp.Position - ball.Position).Unit))
    local tti = dist / relative
    local targeting = isTargetingMe(ball, hrp)

    -- Auto Parry Logic
    if Config.AutoParry and targeting and dist < Config.ParryRange then
        local threshold = getDynamicThreshold(speed) + (getPing() * 0.48)
        if tti < threshold or dist < 12 then
            doParry(true)
        end
    end

    -- Auto Spam Logic
    if Config.AutoSpam and targeting and dist < Config.CloseDistance then
        spamActive = true
    else
        if not ctrlHeld then spamActive = false end
    end
end)

-- Input Handling
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        ctrlHeld = true
        spamActive = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        ctrlHeld = false
        spamActive = false
    end
end)

print("[Sonya Pro] Loaded | Optimized for Xeno 2026")
