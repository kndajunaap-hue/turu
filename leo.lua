--[[
    LEOXD RECORDER v2
]]

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

local VERSION = "2"
local DATA_FOLDER = "LeoXDRecords"
local MIN_FRAMES = 5
local WALK_VEL_THRESHOLD = 0.2

local MAX_VELOCITY_CLAMP = 50
local SMOOTHING_FACTOR = 0.85
local MAX_ROUTE_START_DISTANCE = 220
local ROUTE_REACH_DISTANCE = 4
local ROUTE_APPROACH_TIMEOUT = 12

local SKIP_IDLE = true
local IDLE_VEL_THRESHOLD = 0.3
local ADMIN_USERNAME = "AnamBitss"
local BAN_FILE = DATA_FOLDER .. "/banned_users.json"
local WEBHOOK_USAGE_URL = "https://discordapp.com/api/webhooks/1498782486660907108/71UX2_Lh_E8GjToMS2GvR5u6A8H5RDyMT2QbT2WSX1lFK6P33ZnhC5xNk63KrwC6W1xJ"
local WEBHOOK_MERGE_URL = "https://discordapp.com/api/webhooks/1498783117526171791/hbGQJDo70nsqDGwfwM7lt9qR2jlZ9XXkP5iJB_yoSBdiEv98PejeeSTtpr_fn7tduURQ"

if not isfolder(DATA_FOLDER) then makefolder(DATA_FOLDER) end

-- ==================== STATE ====================
local isRecording = false
local recordedFrames = {}
local recordStartTime = 0
local recordHB = nil
local pendingFrames = nil
local isSaving = false

local isPlaying = false
local isPaused = false
local isLooping = false
local currentData = nil
local currentFrames = nil
local playbackStartTime = 0
local playbackTime = 0
local walkHB = nil
local originalWalkSpeed = 16
local originalJumpPower = 50

local savedRecords = {}
local checkpointRecords = {}
local mergedRecords = {}
local selectedRecord = nil
local notifLabel = nil

local updatePlaybackUI = function() end
local renderList = function() end

local savedPosition = nil
local recordingIndicator = nil
local guiFrame = nil
local isCollapsed = false
local originalHeight = 470
local bannedUsers = {}
local isAdmin = false

-- ==================== FUNGSI DASAR ====================
local function getGroundLevel(pos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LP.Character}
    local origin = Vector3.new(pos.X, pos.Y + 5, pos.Z)
    local direction = Vector3.new(0, -15, 0)
    local result = Workspace:Raycast(origin, direction, params)
    if result then return result.Position.Y end
    return pos.Y - 3
end

local function getYaw(cf)
    local success, yaw = pcall(function() return cf:Yaw() end)
    if success then return yaw end
    return math.atan2(cf.LookVector.X, cf.LookVector.Z)
end

local function getHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = LP.Character
    return c and c:FindFirstChild("Humanoid")
end

local function getRequestFunction()
    return (syn and syn.request) or http_request or request or (http and http.request)
end

local function postWebhook(url, payload)
    if type(url) ~= "string" or url == "" then return false end
    local req = getRequestFunction()
    local body = HttpService:JSONEncode(payload)
    local ok, _ = pcall(function()
        if req then
            req({
                Url = url,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = body
            })
        else
            HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
        end
    end)
    return ok
end

local function loadBans()
    if not isfile(BAN_FILE) then
        bannedUsers = {}
        return
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(BAN_FILE))
    end)
    if ok and type(data) == "table" then
        bannedUsers = data
    else
        bannedUsers = {}
    end
end

local function saveBans()
    pcall(function()
        writefile(BAN_FILE, HttpService:JSONEncode(bannedUsers))
    end)
end

local function isPlayerBanned(userName)
    local key = string.lower(tostring(userName or ""))
    return bannedUsers[key] ~= nil
end

local function sendUsageWebhook()
    local playerName = LP.Name
    local displayName = LP.DisplayName
    local userId = LP.UserId
    local placeId = game.PlaceId
    local gameId = game.GameId
    local jobId = game.JobId
    local mapName = "Unknown"
    pcall(function()
        local info = game:GetService("MarketplaceService"):GetProductInfo(placeId)
        if info and info.Name then
            mapName = info.Name
        end
    end)
    local payload = {
        username = "LeoXD Usage Logger",
        embeds = {{
            title = "Player memakai script LeoXD",
            color = 5793266,
            fields = {
                {name = "Username", value = tostring(playerName), inline = true},
                {name = "Display", value = tostring(displayName), inline = true},
                {name = "UserId", value = tostring(userId), inline = true},
                {name = "Map / Game", value = tostring(mapName), inline = false},
                {name = "PlaceId", value = tostring(placeId), inline = true},
                {name = "JobId", value = tostring(jobId), inline = true},
                {name = "GameId", value = tostring(gameId), inline = false},
                {name = "Version", value = "v" .. VERSION, inline = true},
            },
            timestamp = DateTime.now():ToIsoDate(),
        }}
    }
    task.spawn(function()
        postWebhook(WEBHOOK_USAGE_URL, payload)
    end)
end

local function sendMergeWebhook(mergeRecordName, totalFrames, durationSec)
    local payload = {
        username = "LeoXD Merge Logger",
        embeds = {{
            title = "Merge baru dibuat",
            color = 10857471,
            fields = {
                {name = "Merge Name", value = tostring(mergeRecordName), inline = false},
                {name = "By", value = tostring(LP.Name) .. " (" .. tostring(LP.DisplayName) .. ")", inline = false},
                {name = "Frames", value = tostring(totalFrames), inline = true},
                {name = "Duration", value = string.format("%.2fs", durationSec or 0), inline = true},
                {name = "PlaceId", value = tostring(game.PlaceId), inline = true},
            },
            timestamp = DateTime.now():ToIsoDate(),
        }}
    }
    task.spawn(function()
        postWebhook(WEBHOOK_MERGE_URL, payload)
    end)
end

-- ==================== NOTIF ====================
local function notif(msg, color, duration)
    if not notifLabel then return end
    notifLabel.Text = msg
    notifLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
    notifLabel.TextTransparency = 0
    notifLabel.BackgroundTransparency = 0
    notifLabel.Visible = true
    task.delay(duration or 3.5, function()
        if not notifLabel then return end
        for i = 1, 10 do
            notifLabel.TextTransparency = i / 10
            notifLabel.BackgroundTransparency = i / 10
            task.wait(0.05)
        end
        notifLabel.Visible = false
        notifLabel.BackgroundTransparency = 0
        notifLabel.TextTransparency = 0
    end)
end

local function createAdminPanel(parentGui)
    if not isAdmin then return end

    local panel = Instance.new("Frame")
    panel.Name = "LeoXDAdminPanel"
    panel.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
    panel.BorderSizePixel = 0
    panel.Position = UDim2.new(0.5, 178, 0.5, -280)
    panel.Size = UDim2.new(0, 240, 0, 220)
    panel.Active = true
    panel.Draggable = true
    panel.Parent = parentGui
    local panelCorner = Instance.new("UICorner", panel)
    panelCorner.CornerRadius = UDim.new(0, 10)
    local panelStroke = Instance.new("UIStroke", panel)
    panelStroke.Color = Color3.fromRGB(180, 120, 255)
    panelStroke.Transparency = 0.25

    local title = Instance.new("TextLabel", panel)
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 10, 0, 8)
    title.Size = UDim2.new(1, -20, 0, 22)
    title.Font = Enum.Font.GothamBold
    title.Text = "Admin Panel (AnamBitss)"
    title.TextColor3 = Color3.fromRGB(230, 235, 255)
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left

    local targetBox = Instance.new("TextBox", panel)
    targetBox.BackgroundColor3 = Color3.fromRGB(28, 34, 52)
    targetBox.BorderSizePixel = 0
    targetBox.Position = UDim2.new(0, 10, 0, 36)
    targetBox.Size = UDim2.new(1, -20, 0, 30)
    targetBox.Font = Enum.Font.Gotham
    targetBox.Text = ""
    targetBox.PlaceholderText = "Target username"
    targetBox.PlaceholderColor3 = Color3.fromRGB(135, 145, 170)
    targetBox.TextColor3 = Color3.fromRGB(240, 245, 255)
    targetBox.TextSize = 11
    targetBox.ClearTextOnFocus = false
    local boxCorner = Instance.new("UICorner", targetBox)
    boxCorner.CornerRadius = UDim.new(0, 8)

    local function mkAdminBtn(x, y, w, text, color)
        local b = Instance.new("TextButton", panel)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.Position = UDim2.new(0, x, 0, y)
        b.Size = UDim2.new(0, w, 0, 30)
        b.Font = Enum.Font.GothamBold
        b.Text = text
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.TextSize = 11
        local c = Instance.new("UICorner", b)
        c.CornerRadius = UDim.new(0, 8)
        return b
    end

    local onlineBtn = mkAdminBtn(10, 76, 106, "👥 ONLINE", Color3.fromRGB(54, 98, 162))
    local bansBtn = mkAdminBtn(124, 76, 106, "📄 BAN LIST", Color3.fromRGB(74, 88, 138))
    local banBtn = mkAdminBtn(10, 114, 106, "🚫 BAN", Color3.fromRGB(160, 58, 82))
    local unbanBtn = mkAdminBtn(124, 114, 106, "✅ UNBAN", Color3.fromRGB(56, 138, 95))
    local kickBtn = mkAdminBtn(10, 152, 220, "⛔ KICK TARGET", Color3.fromRGB(136, 66, 52))

    onlineBtn.MouseButton1Click:Connect(function()
        local names = {}
        for _, p in ipairs(Players:GetPlayers()) do
            table.insert(names, p.Name)
        end
        notif("👥 Online: " .. table.concat(names, ", "), Color3.fromRGB(140,200,255), 5)
    end)

    bansBtn.MouseButton1Click:Connect(function()
        local list = {}
        for uname, _ in pairs(bannedUsers) do
            table.insert(list, uname)
        end
        table.sort(list)
        if #list == 0 then
            notif("✅ Ban list kosong", Color3.fromRGB(120,255,150))
        else
            notif("🚫 Ban list: " .. table.concat(list, ", "), Color3.fromRGB(255,160,120), 6)
        end
    end)

    banBtn.MouseButton1Click:Connect(function()
        local target = tostring(targetBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if target == "" then
            notif("❌ Isi target username dulu", Color3.fromRGB(255,100,100))
            return
        end
        bannedUsers[string.lower(target)] = { by = LP.Name, at = os.time() }
        saveBans()
        notif("🚫 Dibanned: " .. target, Color3.fromRGB(255,120,120))
        if string.lower(target) == string.lower(LP.Name) then
            task.wait(0.2)
            LP:Kick("Kamu diban dari LeoXD script")
        end
    end)

    unbanBtn.MouseButton1Click:Connect(function()
        local target = tostring(targetBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if target == "" then
            notif("❌ Isi target username dulu", Color3.fromRGB(255,100,100))
            return
        end
        bannedUsers[string.lower(target)] = nil
        saveBans()
        notif("✅ Unban: " .. target, Color3.fromRGB(120,255,150))
    end)

    kickBtn.MouseButton1Click:Connect(function()
        local target = tostring(targetBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if target == "" then
            notif("❌ Isi target username dulu", Color3.fromRGB(255,100,100))
            return
        end
        if string.lower(target) == string.lower(LP.Name) then
            LP:Kick("Kicked by LeoXD admin panel")
        else
            notif("⚠️ Client script tidak bisa kick player lain tanpa server-side.", Color3.fromRGB(255,200,90), 4)
        end
    end)
end

-- ==================== RECORDING (sama persis) ====================
local function stopRecording()
    if not isRecording then
        notif("❌ Tidak sedang merekam", Color3.fromRGB(255,100,100))
        return
    end
    isRecording = false
    if recordHB then recordHB:Disconnect(); recordHB = nil end
    local hum = getHum()
    if hum then hum.AutoRotate = true end

    if recordingIndicator then
        recordingIndicator:Destroy()
        recordingIndicator = nil
    end

    if #recordedFrames < MIN_FRAMES then
        notif(string.format("❌ Rekaman terlalu pendek (%d frame)", #recordedFrames), Color3.fromRGB(255,100,100))
        recordedFrames = {}
        pendingFrames = nil
        return
    end

    local startIdx = 1
    for i = 1, #recordedFrames do
        local f = recordedFrames[i]
        local speed = math.sqrt(f.velocity.x^2 + f.velocity.z^2)
        if speed >= WALK_VEL_THRESHOLD then
            startIdx = i
            break
        end
    end

    local trimmed = {}
    if startIdx > 1 and startIdx <= #recordedFrames then
        local timeOffset = recordedFrames[startIdx].time
        for i = startIdx, #recordedFrames do
            local f = recordedFrames[i]
            local newFrame = {}
            for k,v in pairs(f) do newFrame[k] = v end
            newFrame.time = f.time - timeOffset
            table.insert(trimmed, newFrame)
        end
    else
        trimmed = recordedFrames
    end

    if #trimmed < MIN_FRAMES then
        notif("❌ Rekaman terlalu pendek setelah trim", Color3.fromRGB(255,100,100))
        recordedFrames = {}
        pendingFrames = nil
        return
    end

    pendingFrames = trimmed
    recordedFrames = {}
    notif(string.format("⏹ %d frame (%.1fs) — siap save", #pendingFrames, pendingFrames[#pendingFrames].time),
          Color3.fromRGB(255,200,50))
end

local function createRecordingIndicator()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RecorderIndicator"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = LP:WaitForChild("PlayerGui")
    
    local blackBg = Instance.new("Frame")
    blackBg.Size = UDim2.new(0, 64, 0, 64)
    blackBg.Position = UDim2.new(0, 12, 0.6, -32)
    blackBg.AnchorPoint = Vector2.new(0, 0.5)
    blackBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    blackBg.BackgroundTransparency = 0
    blackBg.BorderSizePixel = 0
    blackBg.Visible = true
    blackBg.ZIndex = 10
    blackBg.Active = true
    blackBg.Selectable = true
    local blackCorner = Instance.new("UICorner")
    blackCorner.CornerRadius = UDim.new(1, 0)
    blackCorner.Parent = blackBg
    blackBg.Parent = screenGui
    
    local redDot = Instance.new("Frame")
    redDot.Size = UDim2.new(0, 36, 0, 36)
    redDot.Position = UDim2.new(0.5, -18, 0.5, -18)
    redDot.AnchorPoint = Vector2.new(0, 0)
    redDot.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
    redDot.BackgroundTransparency = 0
    redDot.BorderSizePixel = 0
    redDot.ZIndex = 12
    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = redDot
    redDot.Parent = blackBg
    
    task.spawn(function()
        while redDot and redDot.Parent do
            redDot.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
            redDot.BackgroundTransparency = 0
            task.wait(0.5)
            redDot.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
            redDot.BackgroundTransparency = 0.2
            task.wait(0.5)
        end
    end)
    
    blackBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if isRecording then stopRecording() end
            if guiFrame then guiFrame.Visible = true end
        end
    end)
    
    return blackBg
end

local function showRecordingIndicator(show)
    if show then
        if not recordingIndicator or not recordingIndicator.Parent then
            recordingIndicator = createRecordingIndicator()
        else
            recordingIndicator.Visible = true
        end
    else
        if recordingIndicator then
            recordingIndicator:Destroy()
            recordingIndicator = nil
        end
    end
end

local function getNextCheckpointNum()
    local max = 0
    if isfolder(DATA_FOLDER) then
        for _, file in ipairs(listfiles(DATA_FOLDER)) do
            local n = file:match("Checkpoint_(%d+)%.json$")
            if n then
                local num = tonumber(n)
                if num and num > max then max = num end
            end
        end
    end
    return max + 1
end

local function sanitizeName(raw)
    local text = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("[^%w_%-%s]", "")
    text = text:gsub("%s+", "_")
    if #text > 28 then
        text = text:sub(1, 28)
    end
    return text
end

local function buildUniqueRecordName(baseName)
    local name = baseName
    local idx = 1
    while isfile(DATA_FOLDER .. "/" .. name .. ".json") do
        idx = idx + 1
        name = string.format("%s_%d", baseName, idx)
    end
    return name
end

local function isMergedRecordName(name)
    return name:match("^Merged_") ~= nil or name:match("^MergedNoJeda_") ~= nil
end

-- ==================== DELTA ENCODING ====================
local DELTA_PRECISION = 1000 -- 3 desimal

local function roundN(v, n)
    return math.floor(v * n + 0.5) / n
end

local function encodeDelta(frames)
    if not frames or #frames == 0 then return frames end
    local encoded = {}
    local prev = nil
    for i, f in ipairs(frames) do
        if i == 1 then
            local full = {}
            for k,v in pairs(f) do full[k] = v end
            full._delta = false
            table.insert(encoded, full)
            prev = f
        else
            local d = { _delta = true }
            local dpx = roundN(f.position.x - prev.position.x, DELTA_PRECISION)
            local dpy = roundN(f.position.y - prev.position.y, DELTA_PRECISION)
            local dpz = roundN(f.position.z - prev.position.z, DELTA_PRECISION)
            if dpx ~= 0 or dpy ~= 0 or dpz ~= 0 then
                d.dp = { x = dpx, y = dpy, z = dpz }
            end
            local dvx = roundN(f.velocity.x - prev.velocity.x, DELTA_PRECISION)
            local dvy = roundN(f.velocity.y - prev.velocity.y, DELTA_PRECISION)
            local dvz = roundN(f.velocity.z - prev.velocity.z, DELTA_PRECISION)
            if dvx ~= 0 or dvy ~= 0 or dvz ~= 0 then
                d.dv = { x = dvx, y = dvy, z = dvz }
            end
            local dr = roundN(f.rotation - prev.rotation, DELTA_PRECISION)
            if dr ~= 0 then d.dr = dr end
            d.dt = roundN(f.time - prev.time, DELTA_PRECISION)
            local mdx = roundN(f.moveDirection.x - prev.moveDirection.x, DELTA_PRECISION)
            local mdz = roundN(f.moveDirection.z - prev.moveDirection.z, DELTA_PRECISION)
            if mdx ~= 0 or mdz ~= 0 then
                d.dmd = { x = mdx, z = mdz }
            end
            local crx = roundN(f.cf_right.x - prev.cf_right.x, DELTA_PRECISION)
            local cry = roundN(f.cf_right.y - prev.cf_right.y, DELTA_PRECISION)
            local crz = roundN(f.cf_right.z - prev.cf_right.z, DELTA_PRECISION)
            if crx ~= 0 or cry ~= 0 or crz ~= 0 then
                d.dcr = { x = crx, y = cry, z = crz }
            end
            local cux = roundN(f.cf_up.x - prev.cf_up.x, DELTA_PRECISION)
            local cuy = roundN(f.cf_up.y - prev.cf_up.y, DELTA_PRECISION)
            local cuz = roundN(f.cf_up.z - prev.cf_up.z, DELTA_PRECISION)
            if cux ~= 0 or cuy ~= 0 or cuz ~= 0 then
                d.dcu = { x = cux, y = cuy, z = cuz }
            end
            local dgl = roundN(f.groundLevel - prev.groundLevel, DELTA_PRECISION)
            if dgl ~= 0 then d.dgl = dgl end
            if f.walkSpeed ~= prev.walkSpeed then d.ws = f.walkSpeed end
            if f.hipHeight ~= prev.hipHeight then d.hh = f.hipHeight end
            if f.state ~= prev.state then d.st = f.state end
            if f.jumping ~= prev.jumping then d.jmp = f.jumping end
            table.insert(encoded, d)
            prev = f
        end
    end
    return encoded
end

local function decodeDelta(encoded)
    if not encoded or #encoded == 0 then return encoded end
    if encoded[1]._delta == nil then return encoded end
    local decoded = {}
    local prev = nil
    for _, d in ipairs(encoded) do
        if not d._delta then
            local f = {}
            for k,v in pairs(d) do f[k] = v end
            f._delta = nil
            table.insert(decoded, f)
            prev = f
        else
            local f = {}
            local dp = d.dp or { x=0, y=0, z=0 }
            f.position = {
                x = prev.position.x + (dp.x or 0),
                y = prev.position.y + (dp.y or 0),
                z = prev.position.z + (dp.z or 0),
            }
            local dv = d.dv or { x=0, y=0, z=0 }
            f.velocity = {
                x = prev.velocity.x + (dv.x or 0),
                y = prev.velocity.y + (dv.y or 0),
                z = prev.velocity.z + (dv.z or 0),
            }
            f.rotation = prev.rotation + (d.dr or 0)
            f.time = prev.time + (d.dt or 0)
            local dmd = d.dmd or { x=0, z=0 }
            f.moveDirection = {
                x = prev.moveDirection.x + (dmd.x or 0),
                y = 0,
                z = prev.moveDirection.z + (dmd.z or 0),
            }
            local dcr = d.dcr or { x=0, y=0, z=0 }
            f.cf_right = {
                x = prev.cf_right.x + (dcr.x or 0),
                y = prev.cf_right.y + (dcr.y or 0),
                z = prev.cf_right.z + (dcr.z or 0),
            }
            local dcu = d.dcu or { x=0, y=0, z=0 }
            f.cf_up = {
                x = prev.cf_up.x + (dcu.x or 0),
                y = prev.cf_up.y + (dcu.y or 0),
                z = prev.cf_up.z + (dcu.z or 0),
            }
            f.groundLevel = prev.groundLevel + (d.dgl or 0)
            f.walkSpeed = d.ws ~= nil and d.ws or prev.walkSpeed
            f.hipHeight = d.hh ~= nil and d.hh or prev.hipHeight
            f.state = d.st ~= nil and d.st or prev.state
            f.jumping = d.jmp ~= nil and d.jmp or prev.jumping
            table.insert(decoded, f)
            prev = f
        end
    end
    return decoded
end

local function startRecording()
    if isPlaying then
        notif("❌ Hentikan playback dulu", Color3.fromRGB(255,100,100))
        return
    end
    if isRecording then
        if recordHB then recordHB:Disconnect(); recordHB = nil end
        isRecording = false
    end
    pendingFrames = nil
    recordedFrames = {}
    recordStartTime = tick()
    isRecording = true

    if guiFrame then guiFrame.Visible = false end
    showRecordingIndicator(true)

    local lastRecTick = tick()
    notif("🔴 Merekam...", Color3.fromRGB(255,80,80))

    if recordHB then recordHB:Disconnect() end
    recordHB = RunService.Heartbeat:Connect(function()
        if not isRecording then
            recordHB:Disconnect()
            recordHB = nil
            return
        end
        local now = tick()
        if now - lastRecTick < 1/60 then return end
        lastRecTick = now

        local hrp = getHRP()
        local hum = getHum()
        if not hrp then return end

        local pos = hrp.Position
        local cf = hrp.CFrame
        local vel = hrp.AssemblyLinearVelocity
        local groundY = getGroundLevel(pos)

        local rotY = getYaw(cf)
        local moveDir = Vector3.new(vel.X, 0, vel.Z).Unit
        if moveDir.Magnitude < 0.01 then moveDir = Vector3.new(0,0,0) end

        local state = hum and hum:GetState() or Enum.HumanoidStateType.Running
        local stateStr = tostring(state):gsub("Enum.HumanoidStateType.", "")
        local isJumping = (state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall)

        table.insert(recordedFrames, {
            position = { x = pos.X, y = pos.Y, z = pos.Z },
            velocity = { x = vel.X, y = vel.Y, z = vel.Z },
            rotation = rotY,
            moveDirection = { x = moveDir.X, y = 0, z = moveDir.Z },
            state = stateStr,
            walkSpeed = hum and hum.WalkSpeed or 16,
            hipHeight = hum and hum.HipHeight or 0,
            jumping = isJumping,
            time = now - recordStartTime,
            groundLevel = groundY,
            cf_right = { x = cf.RightVector.X, y = cf.RightVector.Y, z = cf.RightVector.Z },
            cf_up = { x = cf.UpVector.X, y = cf.UpVector.Y, z = cf.UpVector.Z },
        })
    end)
end

local function saveRecording(customName)
    if isSaving then
        notif("⚠️ Sedang menyimpan...", Color3.fromRGB(255,200,50))
        return nil
    end
    if not pendingFrames or #pendingFrames == 0 then
        notif("❌ Tidak ada rekaman", Color3.fromRGB(255,100,100))
        return nil
    end
    isSaving = true
    local cleaned = sanitizeName(customName)
    local name
    if cleaned ~= "" then
        name = buildUniqueRecordName("Checkpoint_" .. cleaned)
    else
        local num = getNextCheckpointNum()
        name = buildUniqueRecordName("Checkpoint_" .. num)
    end
    local fileName = DATA_FOLDER .. "/" .. name .. ".json"
    local encodedFrames = encodeDelta(pendingFrames)
    local data = {
        name = name,
        date = os.time(),
        version = VERSION,
        frames = encodedFrames,
        totalFrames = #pendingFrames,
        duration = pendingFrames[#pendingFrames].time,
        deltaEncoded = true,
    }
    local ok, err = pcall(function()
        writefile(fileName, HttpService:JSONEncode(data))
    end)
    if ok then
        notif(string.format("💾 %s (%d frame)", name, #pendingFrames), Color3.fromRGB(100,255,150))
        pendingFrames = nil
        isSaving = false
        return name
    else
        notif("❌ Gagal: "..tostring(err), Color3.fromRGB(255,100,100))
        isSaving = false
        return nil
    end
end

-- ==================== LOAD RECORD ====================
local function getRecordFilePath(name)
    local mainFile = DATA_FOLDER .. "/" .. name .. ".json"
    if isfile(mainFile) then return mainFile end
    return nil
end

local function loadRecord(name)
    local filePath = getRecordFilePath(name)
    if not filePath then return false end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(filePath)) end)
    if not ok then return false end
    currentData = data
    -- Decode delta jika file menggunakan delta encoding
    if data.deltaEncoded then
        currentFrames = decodeDelta(data.frames)
    else
        currentFrames = data.frames
    end
    selectedRecord = name
    notif(string.format("📂 %s (%d frame)", name, data.totalFrames or 0), Color3.fromRGB(100,180,255))
    return true
end

local function deleteRecord(name)
    local filePath = getRecordFilePath(name)
    if not filePath then return false end
    delfile(filePath)
    if currentData and currentData.name == name then currentData = nil end
    if selectedRecord == name then selectedRecord = nil end
    notif("🗑️ Dihapus: "..name, Color3.fromRGB(255,160,60))
    return true
end

local function sortRecords(list)
    table.sort(list, function(a,b)
        local na = tonumber(a:match("Checkpoint_(%d+)$"))
        local nb = tonumber(b:match("Checkpoint_(%d+)$"))
        if na and nb then return na < nb end
        if na then return true end
        if nb then return false end
        return a < b
    end)
end

local function refreshRecords()
    savedRecords = {}
    checkpointRecords = {}
    mergedRecords = {}
    if isfolder(DATA_FOLDER) then
        for _, file in ipairs(listfiles(DATA_FOLDER)) do
            if file:find("%.json$") then
                local name = file:match("([^/\\]+)%.json$")
                if name then
                    table.insert(savedRecords, name)
                    if isMergedRecordName(name) then
                        table.insert(mergedRecords, name)
                    else
                        table.insert(checkpointRecords, name)
                    end
                end
            end
        end
    end
    sortRecords(savedRecords)
    sortRecords(checkpointRecords)
    sortRecords(mergedRecords)
end

-- ==================== KOMPRESI ====================
local function getCompressedFrames(originalFrames)
    if not SKIP_IDLE then return originalFrames end
    
    local movingFrames = {}
    for _, frame in ipairs(originalFrames) do
        local speed = math.sqrt(frame.velocity.x^2 + frame.velocity.z^2)
        local isIdle = speed < IDLE_VEL_THRESHOLD
        if not isIdle or frame.jumping then
            table.insert(movingFrames, frame)
        end
    end
    
    if #movingFrames < 2 then return originalFrames end
    
    local reconstructed = {}
    local currentTime = 0
    for i, frame in ipairs(movingFrames) do
        local newFrame = {}
        for k,v in pairs(frame) do newFrame[k] = v end
        newFrame.time = currentTime
        table.insert(reconstructed, newFrame)
        
        if i < #movingFrames then
            local nextFrame = movingFrames[i+1]
            local dx = nextFrame.position.x - frame.position.x
            local dz = nextFrame.position.z - frame.position.z
            local dist = math.sqrt(dx*dx + dz*dz)
            local v1 = math.sqrt(frame.velocity.x^2 + frame.velocity.z^2)
            local v2 = math.sqrt(nextFrame.velocity.x^2 + nextFrame.velocity.z^2)
            local avgSpeed = (v1 + v2) / 2
            local delta = 0.016
            if avgSpeed > 0.1 then
                delta = dist / avgSpeed
                delta = math.max(delta, 0.016)
                delta = math.min(delta, 0.1)
            end
            currentTime = currentTime + delta
        end
    end
    return reconstructed
end

-- ==================== PLAYBACK ENGINE ====================
local function binarySearch(frames, time)
    local lo, hi = 1, #frames
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if frames[mid].time <= time then lo = mid else hi = mid - 1 end
    end
    return lo
end

local function lerp(a, b, t) return a + (b - a) * t end

local function lerpVector(v1, v2, t)
    return Vector3.new(lerp(v1.x, v2.x, t), lerp(v1.y, v2.y, t), lerp(v1.z, v2.z, t))
end

local function lerpAngle(a, b, t)
    local diff = b - a
    diff = math.atan2(math.sin(diff), math.cos(diff))
    return a + diff * t
end

local function findNearestFrameIndex(frames, currentPos)
    local nearestIdx = 1
    local nearestDist = math.huge
    for i, frame in ipairs(frames) do
        local framePos = Vector3.new(frame.position.x, frame.position.y, frame.position.z)
        local dist = (framePos - currentPos).Magnitude
        if dist < nearestDist then
            nearestDist = dist
            nearestIdx = i
        end
    end
    return nearestIdx, nearestDist
end

local function walkToRouteStart(hum, targetPos)
    local hrp = getHRP()
    if not hum or not hrp then return false, "Character tidak siap" end

    local startTick = tick()
    local lastMoveTick = 0
    while tick() - startTick <= ROUTE_APPROACH_TIMEOUT do
        hrp = getHRP()
        if not hrp then return false, "Character hilang" end

        local dist = (targetPos - hrp.Position).Magnitude
        if dist <= ROUTE_REACH_DISTANCE then
            return true
        end

        if tick() - lastMoveTick >= 0.2 then
            hum:MoveTo(targetPos)
            lastMoveTick = tick()
        end
        task.wait(0.05)
    end

    return false, "Timeout ke rute"
end

local function stopPlayback()
    isPlaying = false
    isPaused = false
    if walkHB then walkHB:Disconnect(); walkHB = nil end
    
    local hrp = getHRP()
    local hum = getHum()
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    if hum then
        hum.AutoRotate = true
        hum.WalkSpeed = originalWalkSpeed
        hum.JumpPower = originalJumpPower
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
    notif("⏹️ Playback berhenti", Color3.fromRGB(200,200,200))
    if updatePlaybackUI then updatePlaybackUI(false) end
end

local function pausePlayback()
    if not isPlaying then return end
    isPaused = not isPaused
    if not isPaused then
        playbackStartTime = tick() - playbackTime
    end
    notif(isPaused and "⏸️ Pause" or "▶️ Resume", Color3.fromRGB(255,180,60))
end

local function startPlaybackFromTime(startTime)
    if not currentData or not currentFrames then
        notif("❌ Pilih rekaman dulu", Color3.fromRGB(255,100,100))
        return false
    end
    
    local hrp = getHRP()
    local hum = getHum()
    if not hrp or not hum then
        notif("❌ Character tidak siap", Color3.fromRGB(255,100,100))
        return false
    end
    
    if isPlaying then stopPlayback() end
    
    originalWalkSpeed = hum.WalkSpeed
    originalJumpPower = hum.JumpPower
    
    local frames = getCompressedFrames(currentFrames)
    if #frames < 2 then
        notif("❌ Rekaman terlalu pendek setelah kompresi", Color3.fromRGB(255,100,100))
        return false
    end
    
    playbackTime = math.clamp(startTime, 0, frames[#frames].time)
    local startFrame = frames[binarySearch(frames, playbackTime)]

    local routeStartPos = Vector3.new(startFrame.position.x, startFrame.position.y, startFrame.position.z)
    local distanceToRoute = (routeStartPos - hrp.Position).Magnitude
    if distanceToRoute > MAX_ROUTE_START_DISTANCE then
        notif(string.format("❌ Terlalu jauh dari rute (%.1f studs)", distanceToRoute), Color3.fromRGB(255,100,100))
        return false
    end

    -- Jalankan approach + playback di task.spawn agar tidak block
    task.spawn(function()
        local currentHrp = getHRP()
        local currentHum = getHum()
        if not currentHrp or not currentHum then return end

        if distanceToRoute > ROUTE_REACH_DISTANCE then
            notif("🚶 Menuju titik rute dulu...", Color3.fromRGB(255,200,50), 1.8)
            local okWalk, walkErr = walkToRouteStart(currentHum, routeStartPos)
            if not okWalk then
                notif("❌ Gagal menuju rute: "..tostring(walkErr), Color3.fromRGB(255,100,100))
                return
            end
        end

        currentHrp = getHRP()
        currentHum = getHum()
        if not currentHrp or not currentHum then return end

        currentHrp.CFrame = CFrame.new(routeStartPos)
        currentHrp.AssemblyLinearVelocity = Vector3.zero
        currentHrp.AssemblyAngularVelocity = Vector3.zero
        
        currentHum.AutoRotate = false
        currentHum.WalkSpeed = originalWalkSpeed
        currentHum.JumpPower = originalJumpPower
        currentHum:ChangeState(Enum.HumanoidStateType.Running)
        
        isPlaying = true
        isPaused = false
        playbackStartTime = tick() - playbackTime
        
        if walkHB then walkHB:Disconnect() end
        
        local lastVelocity = Vector3.zero
        
        walkHB = RunService.Heartbeat:Connect(function()
            if not isPlaying then
                if walkHB then walkHB:Disconnect(); walkHB = nil end
                return
            end
            if isPaused then
                playbackStartTime = tick() - playbackTime
                return
            end
            
            local loopHrp = getHRP()
            local loopHum = getHum()
            if not loopHrp or not loopHum then
                stopPlayback()
                return
            end
            
            local now = tick()
            local newPlaybackTime = now - playbackStartTime
            local totalDur = frames[#frames].time
            
            if newPlaybackTime >= totalDur then
                if isLooping then
                    newPlaybackTime = 0
                    playbackStartTime = now
                    playbackTime = 0
                    notif("🔄 Loop", Color3.fromRGB(150,220,255), 1)
                else
                    stopPlayback()
                    playbackTime = 0
                    notif("✅ Selesai", Color3.fromRGB(100,255,150))
                    return
                end
            end
            
            playbackTime = newPlaybackTime
            
            local frameIdx = binarySearch(frames, playbackTime)
            local nextIdx = math.min(frameIdx + 1, #frames)
            local f1 = frames[frameIdx]
            local f2 = frames[nextIdx]
            
            local deltaTime = f2.time - f1.time
            local t = (playbackTime - f1.time) / (deltaTime > 0 and deltaTime or 0.001)
            t = math.clamp(t, 0, 1)
            
            local pos1 = Vector3.new(f1.position.x, f1.position.y, f1.position.z)
            local pos2 = Vector3.new(f2.position.x, f2.position.y, f2.position.z)
            local newPos = lerpVector(pos1, pos2, t)
            
            local right1 = Vector3.new(f1.cf_right.x, f1.cf_right.y, f1.cf_right.z)
            local right2 = Vector3.new(f2.cf_right.x, f2.cf_right.y, f2.cf_right.z)
            local up1 = Vector3.new(f1.cf_up.x, f1.cf_up.y, f1.cf_up.z)
            local up2 = Vector3.new(f2.cf_up.x, f2.cf_up.y, f2.cf_up.z)
            local right = lerpVector(right1, right2, t)
            local up = lerpVector(up1, up2, t)
            local newCF = CFrame.fromMatrix(newPos, right, up)
            
            local vel1 = Vector3.new(f1.velocity.x, f1.velocity.y, f1.velocity.z)
            local vel2 = Vector3.new(f2.velocity.x, f2.velocity.y, f2.velocity.z)
            local targetVel = lerpVector(vel1, vel2, t)
            
            local newVel = lastVelocity * SMOOTHING_FACTOR + targetVel * (1 - SMOOTHING_FACTOR)
            if newVel.Magnitude > MAX_VELOCITY_CLAMP then
                newVel = newVel.Unit * MAX_VELOCITY_CLAMP
            end
            
            loopHrp.CFrame = newCF
            loopHrp.AssemblyLinearVelocity = newVel
            loopHrp.AssemblyAngularVelocity = Vector3.zero
            
            local isJumpingNow = f1.jumping or (f2.jumping and t > 0.5)
            if isJumpingNow and loopHum:GetState() ~= Enum.HumanoidStateType.Jumping and loopHum:GetState() ~= Enum.HumanoidStateType.Freefall then
                loopHum:ChangeState(Enum.HumanoidStateType.Jumping)
            elseif not isJumpingNow and (loopHum:GetState() == Enum.HumanoidStateType.Jumping or loopHum:GetState() == Enum.HumanoidStateType.Freefall) then
                if loopHum.FloorMaterial ~= Enum.Material.Air then
                    loopHum:ChangeState(Enum.HumanoidStateType.Running)
                end
            end
            
            lastVelocity = newVel
        end)
        
        notif(string.format("▶️ %s (dari %.1fs)", currentData.name, playbackTime), Color3.fromRGB(100,255,150))
        if updatePlaybackUI then updatePlaybackUI(true) end
    end)

    return true
end

local function startPlaybackFromStart()
    if not currentData or not currentFrames then
        notif("❌ Pilih rekaman dulu", Color3.fromRGB(255,100,100))
        return false
    end
    local hrp = getHRP()
    if not hrp then
        notif("❌ Character tidak siap", Color3.fromRGB(255,100,100))
        return false
    end
    
    -- Saat PLAY setelah STOP, selalu mulai dari titik rute terdekat posisi sekarang
    -- agar tidak ketarik ke posisi stop terakhir jika pemain sempat jalan manual.
    local nearestIdx, nearestDist = findNearestFrameIndex(currentFrames, hrp.Position)
    local nearestTime = currentFrames[nearestIdx].time
    notif(string.format("📍 Start dari rute terdekat: frame %d (jarak %.1f)", nearestIdx, nearestDist), Color3.fromRGB(100,255,150), 2)
    return startPlaybackFromTime(nearestTime)
end

local function startPlaybackFromNearest()
    if not currentData or not currentFrames then
        notif("❌ Pilih rekaman dulu", Color3.fromRGB(255,100,100))
        return false
    end
    local hrp = getHRP()
    if not hrp then
        notif("❌ Character tidak siap", Color3.fromRGB(255,100,100))
        return false
    end
    local currentPos = hrp.Position
    local nearestIdx, nearestDist = findNearestFrameIndex(currentFrames, currentPos)
    local startTime = currentFrames[nearestIdx].time
    notif(string.format("📍 Resume nearest: frame %d (jarak %.1f studs) | waktu: %.2fs", nearestIdx, nearestDist, startTime), Color3.fromRGB(100,255,150), 2.5)
    return startPlaybackFromTime(startTime)
end

-- ==================== SAVE/LOAD POSISI ====================
local function savePosition()
    local hrp = getHRP()
    if hrp then
        savedPosition = hrp.CFrame
        notif("💾 Posisi tersimpan", Color3.fromRGB(100,255,100))
    else
        notif("❌ Character tidak siap", Color3.fromRGB(255,100,100))
    end
end

local function loadPosition()
    if savedPosition then
        local hrp = getHRP()
        local hum = getHum()
        if hrp and hum then
            hrp.CFrame = savedPosition
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hum.AutoRotate = true
            hum:ChangeState(Enum.HumanoidStateType.Running)
            notif("📂 Posisi dimuat", Color3.fromRGB(100,200,255))
        else
            notif("❌ Character tidak siap", Color3.fromRGB(255,100,100))
        end
    else
        notif("❌ Belum ada posisi tersimpan", Color3.fromRGB(255,100,100))
    end
end

-- ==================== MERGE TANPA JEDA ====================
local function mergeAndCompressAll(mergeName)
    local toMerge = {}
    for _, name in ipairs(checkpointRecords) do
        if name:match("^Checkpoint_") then
            local filePath = DATA_FOLDER .. "/" .. name .. ".json"
            if isfile(filePath) then table.insert(toMerge, name) end
        end
    end
    if #toMerge < 2 then
        notif("❌ Minimal 2 Checkpoint", Color3.fromRGB(255,100,100))
        return
    end

    local cpDataList = {}
    for _, name in ipairs(toMerge) do
        local fileName = DATA_FOLDER .. "/" .. name .. ".json"
        if not isfile(fileName) then continue end
        local raw = readfile(fileName)
        if raw == "" then continue end
        local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if not ok or not data or not data.frames or #data.frames < 2 then continue end
        local frames = data.deltaEncoded and decodeDelta(data.frames) or data.frames
        table.insert(cpDataList, { name = name, frames = frames })
    end

    if #cpDataList < 2 then
        notif("❌ Minimal 2 CP valid", Color3.fromRGB(255,100,100))
        return
    end

    local allRawFrames = {}
    for _, cpData in ipairs(cpDataList) do
        local frames = cpData.frames
        local startIdx, endIdx = 1, #frames
        for i = 1, #frames do
            local speed = math.sqrt(frames[i].velocity.x^2 + frames[i].velocity.z^2)
            if speed >= WALK_VEL_THRESHOLD then startIdx = i; break end
        end
        for i = #frames, 1, -1 do
            local speed = math.sqrt(frames[i].velocity.x^2 + frames[i].velocity.z^2)
            if speed >= WALK_VEL_THRESHOLD then endIdx = i; break end
        end
        if startIdx > endIdx then startIdx, endIdx = 1, #frames end
        for i = startIdx, endIdx do
            table.insert(allRawFrames, frames[i])
        end
    end

    if #allRawFrames < 2 then
        notif("❌ Tidak cukup frame setelah trim", Color3.fromRGB(255,100,100))
        return
    end

    local mergedFrames = {}
    local currentTime = 0
    for i = 1, #allRawFrames do
        local frame = allRawFrames[i]
        local newFrame = {}
        for k,v in pairs(frame) do newFrame[k] = v end
        newFrame.time = currentTime
        table.insert(mergedFrames, newFrame)
        
        if i < #allRawFrames then
            local nextFrame = allRawFrames[i+1]
            local pos1 = Vector3.new(frame.position.x, frame.position.y, frame.position.z)
            local pos2 = Vector3.new(nextFrame.position.x, nextFrame.position.y, nextFrame.position.z)
            local dist = (pos2 - pos1).Magnitude
            local v1 = Vector3.new(frame.velocity.x, frame.velocity.y, frame.velocity.z)
            local v2 = Vector3.new(nextFrame.velocity.x, nextFrame.velocity.y, nextFrame.velocity.z)
            local avgSpeed = (v1.Magnitude + v2.Magnitude) / 2
            local delta = 0.016
            if avgSpeed > 0.1 and dist > 0.01 then
                delta = dist / avgSpeed
                delta = math.max(delta, 0.016)
                delta = math.min(delta, 0.1)
            end
            currentTime = currentTime + delta
        end
    end

    local cleanedMergeName = sanitizeName(mergeName)
    if cleanedMergeName == "" then
        notif("❌ Isi nama merge dulu", Color3.fromRGB(255,100,100))
        return
    end

    local outName = buildUniqueRecordName("Merged_" .. cleanedMergeName)
    local outFile = DATA_FOLDER .. "/" .. outName .. ".json"
    local encodedMergedFrames = encodeDelta(mergedFrames)
    local outData = {
        name = outName,
        date = os.time(),
        version = VERSION,
        frames = encodedMergedFrames,
        totalFrames = #mergedFrames,
        duration = mergedFrames[#mergedFrames].time,
        merged = true,
        noJeda = true,
        deltaEncoded = true,
    }
    local ok, err = pcall(function() writefile(outFile, HttpService:JSONEncode(outData)) end)
    if ok then
        notif(string.format("🔗 Merge '%s' jadi %d frame", cleanedMergeName, #mergedFrames), Color3.fromRGB(100,255,150))
        sendMergeWebhook(outName, #mergedFrames, mergedFrames[#mergedFrames].time)
        refreshRecords()
        if renderList then renderList() end
    else
        notif("❌ Gagal: "..tostring(err), Color3.fromRGB(255,100,100))
    end
end

-- ==================== CLEANUP TOTAL ====================
local function cleanupAll()
    if isRecording then
        isRecording = false
        if recordHB then recordHB:Disconnect(); recordHB = nil end
        showRecordingIndicator(false)
        local hum = getHum()
        if hum then hum.AutoRotate = true end
    end
    if isPlaying then
        isPlaying = false
        isPaused = false
        if walkHB then walkHB:Disconnect(); walkHB = nil end
        local hrp = getHRP()
        local hum = getHum()
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        if hum then
            hum.AutoRotate = true
            hum.WalkSpeed = originalWalkSpeed
            hum.JumpPower = originalJumpPower
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
    end
    if recordingIndicator then
        recordingIndicator:Destroy()
        recordingIndicator = nil
    end
    local gui = LP.PlayerGui:FindFirstChild("LeoXDRecorder")
    if gui then gui:Destroy() end
    guiFrame = nil
    notifLabel = nil
end

-- ==================== GUI DENGAN LAYOUT RAPAT ====================
local function createGUI()
    local old = LP.PlayerGui:FindFirstChild("LeoXDRecorder")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "LeoXDRecorder"
    gui.ResetOnSpawn = false
    gui.Parent = LP:WaitForChild("PlayerGui")
    createAdminPanel(gui)

    local W, H = 334, 530
    originalHeight = H
    
    local frame = Instance.new("Frame", gui)
    frame.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
    frame.BorderSizePixel = 0
    frame.Position = UDim2.new(0.5,-W/2,0.5,-H/2)
    frame.Size = UDim2.new(0,W,0,H)
    frame.Active = true
    frame.Draggable = true
    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0,12)
    frameCorner.Parent = frame
    guiFrame = frame

    local fs = Instance.new("UIStroke", frame)
    fs.Color = Color3.fromRGB(130, 180, 255)
    fs.Thickness = 1.8

    -- Title bar
    local titleBar = Instance.new("Frame", frame)
    titleBar.BackgroundColor3 = Color3.fromRGB(24, 30, 48)
    titleBar.BorderSizePixel = 0
    titleBar.Size = UDim2.new(1,0,0,36)
    local titleBarCorner = Instance.new("UICorner")
    titleBarCorner.CornerRadius = UDim.new(0,12)
    titleBarCorner.Parent = titleBar

    local titleLbl = Instance.new("TextLabel", titleBar)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Position = UDim2.new(0,12,0,0)
    titleLbl.Size = UDim2.new(1,-80,1,0)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.Text = "LeoXD Route Studio"
    titleLbl.TextColor3 = Color3.fromRGB(255,255,255)
    titleLbl.TextSize = 14
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left

    -- Tombol Minimize
    local minBtn = Instance.new("TextButton", titleBar)
    minBtn.BackgroundColor3 = Color3.fromRGB(80,80,100)
    minBtn.BorderSizePixel = 0
    minBtn.Position = UDim2.new(1,-62,0,6)
    minBtn.Size = UDim2.new(0,24,0,24)
    minBtn.Font = Enum.Font.GothamBold
    minBtn.Text = "—"
    minBtn.TextColor3 = Color3.fromRGB(255,255,255)
    minBtn.TextSize = 16
    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0,6)
    minCorner.Parent = minBtn

    -- Tombol Close
    local closeBtn = Instance.new("TextButton", titleBar)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200,50,50)
    closeBtn.BorderSizePixel = 0
    closeBtn.Position = UDim2.new(1,-32,0,6)
    closeBtn.Size = UDim2.new(0,24,0,24)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
    closeBtn.TextSize = 12
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0,6)
    closeCorner.Parent = closeBtn

    -- Container untuk semua konten
    local contentContainer = Instance.new("Frame", frame)
    contentContainer.BackgroundTransparency = 1
    contentContainer.Position = UDim2.new(0,0,0,36)
    contentContainer.Size = UDim2.new(1,0,1,-36)
    
    -- ========== KOMPONEN GUI (Y diatur rapat dari 0) ==========
    local function mkBtn(x,y,w,h,text,r,g,b)
        local btn = Instance.new("TextButton", contentContainer)
        btn.BackgroundColor3 = Color3.fromRGB(r,g,b)
        btn.BorderSizePixel = 0
        btn.Position = UDim2.new(0,x,0,y)
        btn.Size = UDim2.new(0,w,0,h)
        btn.Font = Enum.Font.GothamBold
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.TextSize = 12
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0,8)
        btnCorner.Parent = btn
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(255,255,255)
        stroke.Transparency = 0.88
        stroke.Thickness = 1
        stroke.Parent = btn
        return btn
    end

    local function mkDiv(y)
        local d = Instance.new("Frame", contentContainer)
        d.BackgroundColor3 = Color3.fromRGB(33,43,66)
        d.BorderSizePixel = 0
        d.Position = UDim2.new(0,12,0,y)
        d.Size = UDim2.new(1,-24,0,1.5)
    end

    local function mkLbl(y,text)
        local lbl = Instance.new("TextLabel", contentContainer)
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0,12,0,y)
        lbl.Size = UDim2.new(1,-24,0,16)
        lbl.Font = Enum.Font.GothamBold
        lbl.Text = text
        lbl.TextColor3 = Color3.fromRGB(144,200,255)
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
    end

    local function mkInput(x,y,w,h,placeholder)
        local box = Instance.new("TextBox", contentContainer)
        box.BackgroundColor3 = Color3.fromRGB(18, 22, 34)
        box.BorderSizePixel = 0
        box.Position = UDim2.new(0,x,0,y)
        box.Size = UDim2.new(0,w,0,h)
        box.Font = Enum.Font.Gotham
        box.Text = ""
        box.TextColor3 = Color3.fromRGB(235,240,255)
        box.PlaceholderText = placeholder
        box.PlaceholderColor3 = Color3.fromRGB(122,132,162)
        box.TextSize = 11
        box.ClearTextOnFocus = false
        box.TextXAlignment = Enum.TextXAlignment.Left
        local pad = Instance.new("UIPadding", box)
        pad.PaddingLeft = UDim.new(0,8)
        local boxCorner = Instance.new("UICorner")
        boxCorner.CornerRadius = UDim.new(0,8)
        boxCorner.Parent = box
        local boxStroke = Instance.new("UIStroke")
        boxStroke.Color = Color3.fromRGB(102,127,175)
        boxStroke.Transparency = 0.7
        boxStroke.Thickness = 1
        boxStroke.Parent = box
        return box
    end

    mkLbl(0, "RECORD")
    local checkpointNameBox = mkInput(12,18,310,26,"Nama checkpoint (opsional)")
    local recBtn = mkBtn(12,50,150,32,"🔴 REC",189,66,92)
    local stpBtn = mkBtn(172,50,150,32,"⏹ SAVE",62,128,187)

    local recStatus = Instance.new("TextLabel", contentContainer)
    recStatus.BackgroundTransparency = 1
    recStatus.Position = UDim2.new(0,12,0,88)
    recStatus.Size = UDim2.new(1,-24,0,14)
    recStatus.Font = Enum.Font.Gotham
    recStatus.Text = "Siap | F = Record"
    recStatus.TextColor3 = Color3.fromRGB(100,255,150)
    recStatus.TextSize = 11
    recStatus.TextXAlignment = Enum.TextXAlignment.Left

    mkDiv(108)

    mkLbl(116, "PLAYBACK")
    local playStartBtn = mkBtn(12,134,100,30,"▶ START",78,62,180)
    local playNearestBtn = mkBtn(120,134,100,30,"📍 NEAREST",48,118,172)
    local pauseBtn = mkBtn(228,134,94,30,"⏸ PAUSE",164,118,48)
    local stopBtn2 = mkBtn(12,170,100,30,"⏹ STOP",170,60,86)
    local loopBtn = mkBtn(120,170,100,30,"🔁 LOOP: OFF",55,60,98)
    local savePosBtn = mkBtn(228,170,94,30,"💾 Save",62,114,74)
    local loadPosBtn = mkBtn(228,206,94,30,"📂 Load",70,92,152)

    mkDiv(244)
    mkLbl(250, "RECORD LIST")
    local refreshBtn = mkBtn(250,248,72,24,"🔄",36,58,97)

    local listFrame = Instance.new("ScrollingFrame", contentContainer)
    listFrame.BackgroundColor3 = Color3.fromRGB(14,17,28)
    listFrame.BorderSizePixel = 0
    listFrame.Position = UDim2.new(0,12,0,272)
    listFrame.Size = UDim2.new(1,-24,0,150)
    listFrame.ScrollBarThickness = 4
    listFrame.ScrollBarImageColor3 = Color3.fromRGB(116,176,255)
    listFrame.CanvasSize = UDim2.new(0,0,0,0)
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    local listCorner = Instance.new("UICorner")
    listCorner.CornerRadius = UDim.new(0,6)
    listCorner.Parent = listFrame

    local ll = Instance.new("UIListLayout", listFrame)
    ll.Padding = UDim.new(0,4)
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    local lp2 = Instance.new("UIPadding", listFrame)
    lp2.PaddingTop = UDim.new(0,6)
    lp2.PaddingLeft = UDim.new(0,6)
    lp2.PaddingRight = UDim.new(0,6)

    -- listFrame berakhir di Y=422+36=458 (contentContainer offset 36)
    mkDiv(430)
    mkLbl(436, "MERGE")
    local mergeNameBox = mkInput(12,454,208,26,"Nama hasil merge (wajib)")
    local mergeBtn = mkBtn(228,454,94,26,"🔗 MERGE",94,48,170)

    notifLabel = Instance.new("TextLabel", contentContainer)
    notifLabel.BackgroundColor3 = Color3.fromRGB(34, 56, 99)
    notifLabel.BorderSizePixel = 0
    notifLabel.Position = UDim2.new(0,12,0,486)
    notifLabel.Size = UDim2.new(1,-24,0,22)
    notifLabel.Font = Enum.Font.Gotham
    notifLabel.Text = ""
    notifLabel.TextColor3 = Color3.fromRGB(255,255,255)
    notifLabel.TextSize = 11
    notifLabel.TextWrapped = true
    notifLabel.Visible = false
    local notifCorner = Instance.new("UICorner")
    notifCorner.CornerRadius = UDim.new(0,6)
    notifCorner.Parent = notifLabel

    -- ========== LIST RECORD ==========
    local rowCache = {}

    local function getLayoutOrder(recName)
        for i,n in ipairs(savedRecords) do if n == recName then return i end end
        return 9999
    end

    local function addEmptyLabel()
        local e = Instance.new("TextLabel", listFrame)
        e.Name = "__empty"
        e.BackgroundTransparency = 1
        e.Size = UDim2.new(1,-12,0,32)
        e.Font = Enum.Font.Gotham
        e.Text = "Belum ada data"
        e.TextColor3 = Color3.fromRGB(70,80,100)
        e.TextSize = 11
    end

    local function addSectionHeader(text, layoutOrder)
        local section = Instance.new("TextLabel", listFrame)
        section.BackgroundTransparency = 1
        section.Size = UDim2.new(1,-12,0,18)
        section.LayoutOrder = layoutOrder
        section.Font = Enum.Font.GothamBold
        section.Text = text
        section.TextColor3 = Color3.fromRGB(145,190,255)
        section.TextSize = 10
        section.TextXAlignment = Enum.TextXAlignment.Left
    end

    local function addRowToList(recName, layoutOrder)
        local isSel = (selectedRecord == recName)
        local row = Instance.new("Frame", listFrame)
        row.Name = "row_"..recName
        row.LayoutOrder = layoutOrder
        row.BackgroundColor3 = isSel and Color3.fromRGB(35,77,130) or Color3.fromRGB(24,28,40)
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1,-12,0,34)
        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0,6)
        rowCorner.Parent = row
        rowCache[recName] = row

        local nb = Instance.new("TextButton", row)
        nb.BackgroundTransparency = 1
        nb.Position = UDim2.new(0,8,0,0)
        nb.Size = UDim2.new(1,-44,1,0)
        nb.Font = isSel and Enum.Font.GothamBold or Enum.Font.Gotham
        nb.Text = (isSel and "▶ " or "  ")..recName
        nb.TextColor3 = isSel and Color3.fromRGB(0,210,255) or Color3.fromRGB(160,175,200)
        nb.TextSize = 11
        nb.TextXAlignment = Enum.TextXAlignment.Left
        nb.TextTruncate = Enum.TextTruncate.AtEnd
        nb.MouseButton1Click:Connect(function()
            if selectedRecord and rowCache[selectedRecord] then
                local oldRow = rowCache[selectedRecord]
                if oldRow and oldRow.Parent then
                    oldRow.BackgroundColor3 = Color3.fromRGB(20,20,30)
                    local oldNb = oldRow:FindFirstChildOfClass("TextButton")
                    if oldNb then
                        oldNb.Font = Enum.Font.Gotham
                        oldNb.Text = "  "..selectedRecord
                        oldNb.TextColor3 = Color3.fromRGB(160,175,200)
                    end
                end
            end
            selectedRecord = recName
            row.BackgroundColor3 = Color3.fromRGB(0,70,120)
            nb.Font = Enum.Font.GothamBold
            nb.Text = "▶ "..recName
            nb.TextColor3 = Color3.fromRGB(0,210,255)
            loadRecord(recName)
        end)

        local db = Instance.new("TextButton", row)
        db.BackgroundColor3 = Color3.fromRGB(122,38,56)
        db.BorderSizePixel = 0
        db.Position = UDim2.new(1,-28,0,4)
        db.Size = UDim2.new(0,22,0,24)
        db.Font = Enum.Font.GothamBold
        db.Text = "🗑"
        db.TextSize = 11
        db.TextColor3 = Color3.fromRGB(255,255,255)
        local dbCorner = Instance.new("UICorner")
        dbCorner.CornerRadius = UDim.new(0,4)
        dbCorner.Parent = db
        db.MouseButton1Click:Connect(function()
            row:Destroy()
            rowCache[recName] = nil
            if selectedRecord == recName then selectedRecord = nil end
            local hasRows = false
            for _,c in pairs(listFrame:GetChildren()) do
                if c:IsA("Frame") then hasRows = true; break end
            end
            if not hasRows then addEmptyLabel() end
            task.spawn(function()
                deleteRecord(recName)
                for i,n in ipairs(savedRecords) do if n == recName then table.remove(savedRecords,i); break end end
            end)
        end)
    end

    renderList = function()
        for _,c in pairs(listFrame:GetChildren()) do
            if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
        end
        rowCache = {}
        if #savedRecords == 0 then addEmptyLabel(); return end

        local order = 1
        addSectionHeader("CHECKPOINT", order)
        order = order + 1
        if #checkpointRecords == 0 then
            local emptyCp = Instance.new("TextLabel", listFrame)
            emptyCp.BackgroundTransparency = 1
            emptyCp.Size = UDim2.new(1,-12,0,20)
            emptyCp.LayoutOrder = order
            emptyCp.Font = Enum.Font.Gotham
            emptyCp.Text = "- belum ada checkpoint -"
            emptyCp.TextColor3 = Color3.fromRGB(92,102,125)
            emptyCp.TextSize = 10
            emptyCp.TextXAlignment = Enum.TextXAlignment.Left
            order = order + 1
        else
            for _,recName in ipairs(checkpointRecords) do
                addRowToList(recName, order)
                order = order + 1
            end
        end

        addSectionHeader("HASIL MERGE", order)
        order = order + 1
        if #mergedRecords == 0 then
            local emptyMerge = Instance.new("TextLabel", listFrame)
            emptyMerge.BackgroundTransparency = 1
            emptyMerge.Size = UDim2.new(1,-12,0,20)
            emptyMerge.LayoutOrder = order
            emptyMerge.Font = Enum.Font.Gotham
            emptyMerge.Text = "- belum ada hasil merge -"
            emptyMerge.TextColor3 = Color3.fromRGB(92,102,125)
            emptyMerge.TextSize = 10
            emptyMerge.TextXAlignment = Enum.TextXAlignment.Left
        else
            for _,recName in ipairs(mergedRecords) do
                addRowToList(recName, order)
                order = order + 1
            end
        end
    end

    updatePlaybackUI = function(playing) end

    -- Update status text periodik
    task.spawn(function()
        while gui and gui.Parent do
            if isRecording then
                recStatus.Text = string.format("🔴 %d frame  |  %.1fs", #recordedFrames, tick()-recordStartTime)
                recStatus.TextColor3 = Color3.fromRGB(255,90,90)
            elseif isPlaying and currentData then
                local pct = math.floor(playbackTime / (currentData.duration or 1) * 100)
                recStatus.Text = string.format("▶ %.1fs / %.1fs  (%d%%)", playbackTime, currentData.duration or 0, pct)
                recStatus.TextColor3 = Color3.fromRGB(80,220,130)
            else
                recStatus.Text = "✅ Siap | F = Record | ORDER DI BIO GUYS"
                recStatus.TextColor3 = Color3.fromRGB(100,255,150)
            end
            task.wait(0.2)
        end
    end)

    -- Event tombol
    recBtn.MouseButton1Click:Connect(startRecording)
    stpBtn.MouseButton1Click:Connect(function()
        if isRecording then stopRecording() end
        task.defer(function()
            local saved = saveRecording(checkpointNameBox.Text)
            if saved then
                checkpointNameBox.Text = ""
                refreshRecords()
                renderList()
            end
        end)
    end)
    playStartBtn.MouseButton1Click:Connect(startPlaybackFromStart)
    playNearestBtn.MouseButton1Click:Connect(startPlaybackFromNearest)
    pauseBtn.MouseButton1Click:Connect(pausePlayback)
    stopBtn2.MouseButton1Click:Connect(stopPlayback)
    savePosBtn.MouseButton1Click:Connect(savePosition)
    loadPosBtn.MouseButton1Click:Connect(loadPosition)
    loopBtn.MouseButton1Click:Connect(function()
        isLooping = not isLooping
        loopBtn.Text = isLooping and "🔁 LOOP: ON" or "🔁 LOOP: OFF"
        loopBtn.BackgroundColor3 = isLooping and Color3.fromRGB(0,120,65) or Color3.fromRGB(35,35,55)
    end)
    refreshBtn.MouseButton1Click:Connect(function()
        refreshRecords()
        renderList()
        notif("🔄 Direfresh", Color3.fromRGB(130,190,255),1.5)
    end)
    mergeBtn.MouseButton1Click:Connect(function()
        mergeAndCompressAll(mergeNameBox.Text)
        if mergeNameBox.Text ~= "" then
            mergeNameBox.Text = ""
        end
    end)

    -- Minimize (collapse) logic
    local function toggleCollapse()
        if isCollapsed then
            frame.Size = UDim2.new(0, W, 0, originalHeight)
            contentContainer.Visible = true
            minBtn.Text = "—"
            isCollapsed = false
        else
            frame.Size = UDim2.new(0, W, 0, 36)
            contentContainer.Visible = false
            minBtn.Text = "□"
            isCollapsed = true
        end
    end
    minBtn.MouseButton1Click:Connect(toggleCollapse)

    -- Close total
    closeBtn.MouseButton1Click:Connect(cleanupAll)

    refreshRecords()
    renderList()
end

-- ==================== CHARACTER ADDED ====================
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    local hum = getHum()
    if hum then
        hum.AutoRotate = true
        hum.JumpPower = 50
        hum.WalkSpeed = 16
    end
    if isPlaying then stopPlayback() end
    if isRecording then stopRecording() end
end)

-- ==================== KEYBIND F ====================
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F then
        if isRecording then
            stopRecording()
            if guiFrame then guiFrame.Visible = true end
        else
            startRecording()
            if guiFrame then guiFrame.Visible = false end
        end
    end
end)

-- ==================== START ====================
loadBans()
isAdmin = (string.lower(LP.Name) == string.lower(ADMIN_USERNAME))
if isPlayerBanned(LP.Name) then
    LP:Kick("Akses LeoXD script diblokir (banned).")
    return
end

sendUsageWebhook()

createGUI()
refreshRecords()
showRecordingIndicator(false)
