-- =====================================================================
-- XENO REMOTE CONTROLLED SCRIPT
-- Todas las funciones se controlan desde el panel web
-- =====================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local Workspace        = game:GetService("Workspace")
local Debris           = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer

-- =====================================================================
-- CONFIGURACIÓN DE RED
-- =====================================================================
local BASE_URL = "http://127.0.0.1:5000"
local AUTH     = "Basic YWRtaW46aGFja3MxMjM="  -- admin:hacks123
local POLL     = 0.2

-- =====================================================================
-- HTTP HELPERS
-- =====================================================================
local function http_req(method, path, body)
    local opts = {
        Url = BASE_URL .. path,
        Method = method,
        Headers = {
            ["Authorization"] = AUTH,
            ["Content-Type"]  = "application/json"
        }
    }
    if body then opts.Body = HttpService:JSONEncode(body) end

    local req_fn = request or http_request or (syn and syn.request)
    if not req_fn then
        warn("[XENO] No se encontró función HTTP. Abortando.")
        return nil
    end
    local ok, res = pcall(req_fn, opts)
    if ok and res and res.Body then return res.Body end
    return nil
end

local function get_state()
    local body = http_req("GET", "/state")
    if not body then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok then return data end
    return nil
end

local function post_players(list)
    http_req("POST", "/players", { players = list })
end

-- =====================================================================
-- CONFIG (espejo del estado del servidor)
-- =====================================================================
local Config = {
    esp         = { enabled=false, lines=false, boxes=false, names=false, distance=false, team_check=false },
    fly         = { enabled=false, speed=50, vehicle=false },
    noclip      = { enabled=false, vehicle=false },
    speed_hack  = { enabled=false, speed=100 },
    knockback   = { force=100 },
    selected_player = "",
    action      = nil,
}

local last_action_id  = 0
local last_report     = 0

-- Estado interno
local FlyConn, FlyBV, FlyBG
local NoClipConn, NoClipParts = nil, {}
local OriginalWalkSpeed = 16
local ESPObjects = {}

-- =====================================================================
-- HELPERS
-- =====================================================================
local function GetSubject()
    local ch = LocalPlayer.Character
    if not ch then return nil end
    if Config.fly.vehicle then
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart then
            local v = hum.SeatPart:FindFirstAncestorOfClass("Model")
            if v then return v end
        end
    end
    return ch
end

-- =====================================================================
-- FLY
-- =====================================================================
local function ToggleFly(enabled)
    if FlyConn then FlyConn:Disconnect() FlyConn = nil end
    if FlyBV then FlyBV:Destroy() FlyBV = nil end
    if FlyBG then FlyBG:Destroy() FlyBG = nil end
    if not enabled then return end

    local subj = GetSubject()
    if not subj then return end
    local hrp = subj:FindFirstChild("HumanoidRootPart")
        or subj:FindFirstChild("PrimaryPart")
        or subj:FindFirstChildWhichIsA("BasePart")
    if not hrp then return end

    FlyBV = Instance.new("BodyVelocity")
    FlyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    FlyBV.Velocity = Vector3.zero
    FlyBV.P = 1250
    FlyBV.Parent = hrp

    FlyBG = Instance.new("BodyGyro")
    FlyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    FlyBG.P = 10000
    FlyBG.D = 100
    FlyBG.CFrame = hrp.CFrame
    FlyBG.Parent = hrp

    FlyConn = RunService.RenderStepped:Connect(function()
        if not Config.fly.enabled then return end
        local s = GetSubject()
        if not s then ToggleFly(false) return end
        local h = s:FindFirstChild("HumanoidRootPart")
            or s:FindFirstChild("PrimaryPart")
            or s:FindFirstChildWhichIsA("BasePart")
        if not h then return end

        if FlyBV and FlyBV.Parent ~= h then
            FlyBV:Destroy()
            FlyBV = Instance.new("BodyVelocity")
            FlyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            FlyBV.Velocity = Vector3.zero
            FlyBV.P = 1250
            FlyBV.Parent = h
        end
        if FlyBG and FlyBG.Parent ~= h then
            FlyBG:Destroy()
            FlyBG = Instance.new("BodyGyro")
            FlyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            FlyBG.P = 10000
            FlyBG.D = 100
            FlyBG.CFrame = h.CFrame
            FlyBG.Parent = h
        end

        local cam = Workspace.CurrentCamera
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end

        if dir.Magnitude > 0 then dir = dir.Unit * Config.fly.speed end
        if FlyBV then FlyBV.Velocity = dir end
        if FlyBG then FlyBG.CFrame = cam.CFrame end
    end)
end

-- =====================================================================
-- NOCLIP
-- =====================================================================
local function ToggleNoClip(enabled)
    if NoClipConn then NoClipConn:Disconnect() NoClipConn = nil end
    for part, orig in pairs(NoClipParts) do
        if part and part.Parent then part.CanCollide = orig end
    end
    NoClipParts = {}
    if not enabled then return end

    NoClipConn = RunService.Stepped:Connect(function()
        if not Config.noclip.enabled then return end
        local subj = GetSubject()
        if not subj then return end

        if Config.noclip.vehicle then
            local ch = LocalPlayer.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hum and hum.SeatPart then
                local v = hum.SeatPart:FindFirstAncestorOfClass("Model")
                if v then subj = v end
            end
        end

        for _, part in ipairs(subj:GetDescendants()) do
            if part:IsA("BasePart") then
                if NoClipParts[part] == nil then
                    NoClipParts[part] = part.CanCollide
                end
                part.CanCollide = false
            end
        end
    end)
end

-- =====================================================================
-- SPEED HACK
-- =====================================================================
local function ApplySpeedHack()
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = Config.speed_hack.speed end
end

local function ToggleSpeedHack(enabled)
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if enabled then
        OriginalWalkSpeed = hum.WalkSpeed
        ApplySpeedHack()
    else
        hum.WalkSpeed = OriginalWalkSpeed
    end
end

-- =====================================================================
-- ESP
-- =====================================================================
local function CreateESP(player)
    if ESPObjects[player] then return end
    local o = {}
    pcall(function()
        o.Line = Drawing.new("Line")
        o.Line.Visible = false
        o.Line.Thickness = 1.5
        o.Line.Transparency = 1
        o.Line.Color = Color3.fromRGB(255, 0, 0)

        o.Box = Drawing.new("Square")
        o.Box.Visible = false
        o.Box.Thickness = 1.5
        o.Box.Filled = false
        o.Box.Transparency = 1
        o.Box.Color = Color3.fromRGB(0, 255, 0)

        o.Name = Drawing.new("Text")
        o.Name.Visible = false
        o.Name.Size = 14
        o.Name.Center = true
        o.Name.Outline = true
        o.Name.OutlineColor = Color3.new(0, 0, 0)
        o.Name.Color = Color3.new(1, 1, 1)

        o.Distance = Drawing.new("Text")
        o.Distance.Visible = false
        o.Distance.Size = 12
        o.Distance.Center = true
        o.Distance.Outline = true
        o.Distance.OutlineColor = Color3.new(0, 0, 0)
        o.Distance.Color = Color3.new(1, 1, 1)
    end)
    ESPObjects[player] = o
end

local function RemoveESP(player)
    local o = ESPObjects[player]
    if not o then return end
    pcall(function()
        for _, obj in pairs(o) do if obj and obj.Remove then obj:Remove() end end
    end)
    ESPObjects[player] = nil
end

local function UpdateESP()
    if not Config.esp.enabled then
        for _, o in pairs(ESPObjects) do
            pcall(function() for _, v in pairs(o) do if v then v.Visible = false end end end)
        end
        return
    end

    local localHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local cam = Workspace.CurrentCamera

    for player, o in pairs(ESPObjects) do
        pcall(function()
            local ch = player.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            local head = ch and ch:FindFirstChild("Head")
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")

            if hrp and head and hum and hum.Health > 0 then
                if Config.esp.team_check and player.Team == LocalPlayer.Team then
                    for _, v in pairs(o) do if v then v.Visible = false end end
                    return
                end

                local pos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                local headPos = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                local legPos = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))

                if onScreen and pos.Z > 0 then
                    local dist = localHrp and (hrp.Position - localHrp.Position).Magnitude or 0

                    if Config.esp.lines and o.Line then
                        o.Line.Visible = true
                        o.Line.From = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                        o.Line.To = Vector2.new(pos.X, pos.Y)
                    elseif o.Line then o.Line.Visible = false end

                    if Config.esp.boxes and o.Box then
                        local bh = math.abs(headPos.Y - legPos.Y)
                        local bw = bh * 0.6
                        o.Box.Visible = true
                        o.Box.Size = Vector2.new(bw, bh)
                        o.Box.Position = Vector2.new(pos.X - bw / 2, pos.Y - bh / 2)
                    elseif o.Box then o.Box.Visible = false end

                    if Config.esp.names and o.Name then
                        o.Name.Visible = true
                        o.Name.Position = Vector2.new(headPos.X, headPos.Y - 25)
                        o.Name.Text = player.Name
                    elseif o.Name then o.Name.Visible = false end

                    if Config.esp.distance and o.Distance then
                        o.Distance.Visible = true
                        o.Distance.Position = Vector2.new(pos.X, legPos.Y + 5)
                        o.Distance.Text = string.format("%.1fm", dist)
                    elseif o.Distance then o.Distance.Visible = false end
                else
                    for _, v in pairs(o) do if v then v.Visible = false end end
                end
            else
                for _, v in pairs(o) do if v then v.Visible = false end end
            end
        end)
    end
end

-- =====================================================================
-- ACCIONES
-- =====================================================================
local function DoTeleport(name)
    local target = Players:FindFirstChild(name)
    if not target or not target.Character then return end
    local localChar = LocalPlayer.Character
    if not localChar then return end
    local hrp = localChar:FindFirstChild("HumanoidRootPart")
    local thrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not hrp or not thrp then return end

    local wasFlying = Config.fly.enabled
    if wasFlying then ToggleFly(false) end
    hrp.CFrame = thrp.CFrame + Vector3.new(0, 5, 0)
    if wasFlying then task.wait(0.1) ToggleFly(true) end
end

local function DoKnockback(name)
    local target = Players:FindFirstChild(name)
    if not target or not target.Character then return end
    local localChar = LocalPlayer.Character
    if not localChar then return end
    local lhrp = localChar:FindFirstChild("HumanoidRootPart")
    local thrp = target.Character:FindFirstChild("HumanoidRootPart")
    if not lhrp or not thrp then return end

    local dir = (thrp.Position - lhrp.Position).Unit
    local f = Config.knockback.force
    local vel = dir * f + Vector3.new(0, f * 0.4, 0)

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bv.Velocity = vel
    bv.P = 1000
    bv.Parent = thrp
    Debris:AddItem(bv, 0.3)

    local hum = target.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.AutoRotate = false
        task.wait(0.3)
        hum.AutoRotate = true
    end
end

-- =====================================================================
-- POLLING PRINCIPAL
-- =====================================================================
task.spawn(function()
    local prev_fly, prev_noclip, prev_speed = false, false, false

    while true do
        local data = get_state()
        if data then
            -- Actualizar config
            if data.esp then
                for k, v in pairs(data.esp) do Config.esp[k] = v end
            end
            if data.fly then
                for k, v in pairs(data.fly) do Config.fly[k] = v end
            end
            if data.noclip then
                for k, v in pairs(data.noclip) do Config.noclip[k] = v end
            end
            if data.speed_hack then
                for k, v in pairs(data.speed_hack) do Config.speed_hack[k] = v end
            end
            if data.knockback then
                for k, v in pairs(data.knockback) do Config.knockback[k] = v end
            end
            Config.selected_player = data.selected_player or ""

            -- Aplicar cambios de toggles
            if Config.fly.enabled ~= prev_fly then
                ToggleFly(Config.fly.enabled)
                prev_fly = Config.fly.enabled
            end
            if Config.noclip.enabled ~= prev_noclip then
                ToggleNoClip(Config.noclip.enabled)
                prev_noclip = Config.noclip.enabled
            end
            if Config.speed_hack.enabled ~= prev_speed then
                ToggleSpeedHack(Config.speed_hack.enabled)
                prev_speed = Config.speed_hack.enabled
            end
            if Config.speed_hack.enabled then ApplySpeedHack() end

            -- Procesar acción puntual
            if data.action and data.action.id and data.action.id > last_action_id then
                last_action_id = data.action.id
                local t = data.action.type
                if t == "teleport"  then DoTeleport(Config.selected_player) end
                if t == "knockback" then DoKnockback(Config.selected_player) end
            end
        end

        -- Reportar jugadores cada 1s
        local now = tick()
        if now - last_report > 1 then
            last_report = now
            local list = {}
            local lhrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local ch = p.Character
                    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                    local dist = 0
                    if lhrp and hrp then dist = (hrp.Position - lhrp.Position).Magnitude end
                    table.insert(list, {
                        name       = p.Name,
                        display    = p.DisplayName,
                        health     = hum and math.floor(hum.Health) or 0,
                        max_health = hum and math.floor(hum.MaxHealth) or 100,
                        distance   = math.floor(dist),
                        team       = p.Team and p.Team.Name or "",
                    })
                end
            end
            post_players(list)
        end

        task.wait(POLL)
    end
end)

-- =====================================================================
-- EVENTOS
-- =====================================================================
Players.PlayerAdded:Connect(function(p)
    task.wait(1)
    if p ~= LocalPlayer then CreateESP(p) end
end)
Players.PlayerRemoving:Connect(RemoveESP)

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then CreateESP(p) end
end

RunService.RenderStepped:Connect(UpdateESP)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if Config.speed_hack.enabled then ApplySpeedHack() end
    if Config.fly.enabled        then ToggleFly(true)    end
    if Config.noclip.enabled     then ToggleNoClip(true) end
end)

print("[XENO] Script cargado. Todo se controla desde el panel web.")
print("[XENO] Abre http://127.0.0.1:5000 en tu navegador.")