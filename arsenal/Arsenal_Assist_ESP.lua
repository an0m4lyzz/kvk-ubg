-- Arsenal_Assist_ESP.lua
-- Revision: tablet3, cumulative camera tracking and on-device diagnostics.
-- Client source: LocalScript in your own place, or a client runtime exposing Roblox APIs.
-- No Studio-only restriction, remote manipulation, or external dependency.
-- See README.md in this directory for controls, local-resize limits, and verification scope.

local Config = {
    AimAssist = {
        Enabled = true,
        ActivationKey = Enum.UserInputType.MouseButton2,
        FOV = 180, -- Fast tablet preset; radius in viewport pixels.
        Smoothness = 0.35, -- Fraction corrected in 1/60 second; no instant snapping.
        TargetPart = "UpperTorso",
        TeamCheck = true,
        WallCheck = true,
        AliveCheck = true,
        TargetLock = true,
        Prediction = false,
        ShowFOV = false,
        PredictionSeconds = 0.08, -- Optional linear lead; not a ballistic solver.
    },
    ESP = {
        Enabled = true,
        Outlines = true,
        ThroughWalls = true,
        TeamCheck = true,
        ShowNames = false,
        ShowDistance = false,
        ShowHealth = false,
        MaxDistance = 300, -- Studs from the current camera to character root.
    },
    Hitbox = {
        Enabled = false, -- Opt in: LOCAL resize can confound server hit registration.
        Size = 6, -- Minimum root-part size on each axis, in studs; never shrink originals.
        ShowBox = true, -- Visualizes the local resize, not confirmed damage registration.
        TeamCheck = true,
        MaxDistance = 300,
    },
    Mobile = {
        Enabled = true, -- Show touch controls when TouchEnabled is true.
        ActivationMode = "Toggle", -- "Toggle" (tap on/off) or "Hold".
        ButtonScale = 1,
        DockX = 0.10, -- Left side by default to keep the right fire-control area clear.
        DockY = 0.35,
    },
    Performance = {
        OptimizeESP = true,
        AutoCleanup = true,
        DebugMode = false,
        ESPInterval = 0.10,
        AcquireInterval = 0.04,
        MaxHighlights = 64, -- Our budget only; other systems share the engine limit.
        IdleVisualLifetime = 2,
    },
}

-- 1. Environment and configuration ------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

if not RunService:IsClient() then
    warn("[ArsenalAssist] Run this source in a Roblox client context.")
    return
end

local localPlayer = Players.LocalPlayer
if not localPlayer then
    warn("[ArsenalAssist] LocalPlayer is unavailable in this context.")
    return
end
local playerGui = localPlayer:WaitForChild("PlayerGui", 15)
if not playerGui then
    warn("[ArsenalAssist] PlayerGui did not become available.")
    return
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local defaults = copy(Config) -- Reset returns to the initial table in this file.
local numberLimits = {
    AimAssist = {
        FOV = {5, 1000}, Smoothness = {0, 0.5}, PredictionSeconds = {0, 0.25},
    },
    ESP = {MaxDistance = {0, 10000}},
    Hitbox = {Size = {2, 12}, MaxDistance = {0, 10000}},
    Mobile = {ButtonScale = {0.75, 1.5}, DockX = {0, 1}, DockY = {0, 1}},
    Performance = {
        ESPInterval = {0.05, 1}, AcquireInterval = {0.025, 1},
        MaxHighlights = {1, 255}, IdleVisualLifetime = {0, 30},
    },
}

local function activationIsValid(value)
    if typeof(value) ~= "EnumItem" then return false end
    return (value.EnumType == Enum.KeyCode and value ~= Enum.KeyCode.Unknown)
        or value == Enum.UserInputType.MouseButton1
        or value == Enum.UserInputType.MouseButton2
        or value == Enum.UserInputType.MouseButton3
end

local function validatedPatch(patch)
    if type(patch) ~= "table" then return nil, "Expected a configuration table." end
    local nextConfig = copy(Config)
    for section, settings in pairs(patch) do
        if defaults[section] == nil or type(settings) ~= "table" then
            return nil, "Unknown section or invalid settings: " .. tostring(section)
        end
        for key, value in pairs(settings) do
            local template = defaults[section][key]
            if template == nil then return nil, "Unknown setting: " .. tostring(key) end
            if key == "ActivationKey" then
                if not activationIsValid(value) then
                    return nil, "ActivationKey must be a mouse button or KeyCode."
                end
            elseif type(value) ~= type(template) then
                return nil, "Wrong type for " .. section .. "." .. key
            elseif type(value) == "number" then
                if value ~= value or value == math.huge or value == -math.huge then
                    return nil, "Non-finite number for " .. key
                end
                local limits = numberLimits[section] and numberLimits[section][key]
                if limits then value = math.clamp(value, limits[1], limits[2]) end
                if key == "MaxHighlights" then value = math.floor(value) end
            elseif key == "TargetPart" and (value == "" or #value > 100) then
                return nil, "TargetPart must be a nonempty part name (at most 100 characters)."
            elseif section == "Mobile" and key == "ActivationMode"
                and value ~= "Toggle" and value ~= "Hold" then
                return nil, "Mobile.ActivationMode must be Toggle or Hold."
            end
            nextConfig[section][key] = value
        end
    end
    return nextConfig
end

-- This helper deliberately uses no frame cap: normal-frame convergence is exact
-- for a stationary goal. The render callback skips long stalls separately.
local function smoothingAlpha(strength, dt)
    return 1 - (1 - strength) ^ (60 * dt)
end

-- 2. Runtime ownership and cleanup -------------------------------------------------
local RUNTIME_NAME = "ArsenalAssistESP_Runtime"
local oldRuntime = playerGui:FindFirstChild(RUNTIME_NAME)
if oldRuntime then
    local oldUnload = oldRuntime:FindFirstChild("Unload")
    if oldUnload and oldUnload:IsA("BindableFunction") then
        -- Synchronous handoff; a unique render binding also isolates instances.
        local ok, err = pcall(function() oldUnload:Invoke() end)
        if not ok then warn("[ArsenalAssist] Previous unload: " .. tostring(err)) end
    end
    oldRuntime:Destroy()
end

local runtime = Instance.new("Folder")
runtime.Name = RUNTIME_NAME
runtime.Parent = playerGui
local visuals = Instance.new("Folder")
visuals.Name = "ArsenalAssistESP_Visuals_" .. tostring(localPlayer.UserId)
visuals.Parent = Workspace
local unloadFunction = Instance.new("BindableFunction")
unloadFunction.Name = "Unload"
unloadFunction.Parent = runtime
local configureFunction = Instance.new("BindableFunction")
configureFunction.Name = "Configure"
configureFunction.Parent = runtime

local running = true
local connections = {}
local records = {}
local camera = Workspace.CurrentCamera
local target = nil
local held = false
local activationSource = nil
local touchInput = nil
local dragInput, dragOrigin, dragStartCenter
local windowFocused = true
local menuOpen = false
local renderBound = false
local renderName = "ArsenalAssistESP_" .. HttpService:GenerateGUID(false)
local renderBindings = {}
local cameraOffset, previousBaseFrame, lastWrittenFrame, lastWriteCamera
local wroteThisFrame = false
local diagnostics = {
    State = "IDLE", Detail = "manual fire", Frames = 0, ActiveFrames = 0,
    Scans = 0, Candidates = 0, InFOV = 0, Blocked = 0, Outside = 0,
    CameraOverwrites = 0, CameraRebases = 0, PixelError = nil,
}
local highlightCount = 0
local espElapsed = 0
local scanElapsed = math.huge
local clock = 0
local gui, panel, statusLabel, fovCircle, uiScale
local touchDock, touchAimButton, touchESPButton, touchHitboxButton, touchScale, touchDockCenter
local refreshUI
local refreshRayFilter
local refreshTouchState
local layoutTouchDock
local restoreHitbox
local rayFilterDirty = false

local function resetCameraMemory()
    cameraOffset, previousBaseFrame, lastWrittenFrame, lastWriteCamera = nil, nil, nil, nil
    wroteThisFrame = false
end

local function setAimStatus(state, detail)
    local changed = diagnostics.State ~= state or diagnostics.Detail ~= detail
    diagnostics.State, diagnostics.Detail = state, detail
    if changed and refreshTouchState then refreshTouchState() end
end

local function connect(signal, callback, bucket)
    local connection = signal:Connect(callback)
    table.insert(bucket or connections, connection)
    return connection
end

local function disconnectAll(bucket)
    for _, connection in ipairs(bucket) do connection:Disconnect() end
    table.clear(bucket)
end

local function releaseAim()
    held = false
    activationSource = nil
    touchInput = nil
    target = nil
    scanElapsed = math.huge
    resetCameraMemory()
    diagnostics.ActiveFrames = 0
    diagnostics.PixelError = nil
    setAimStatus("IDLE", "manual fire")
    if refreshTouchState then refreshTouchState() end
end

local function destroyVisuals(record)
    if record.highlight then
        record.highlight:Destroy()
        record.highlight = nil
        highlightCount = highlightCount - 1
    end
    if record.billboard then record.billboard:Destroy() end
    record.billboard, record.label = nil, nil
    record.inactiveSince = nil
    record.lastText = nil
end

local function cleanup()
    if not running then return end
    running = false
    dragInput = nil
    releaseAim()
    for _, name in ipairs(renderBindings) do RunService:UnbindFromRenderStep(name) end
    table.clear(renderBindings)
    renderBound = false
    disconnectAll(connections)
    for _, record in pairs(records) do
        disconnectAll(record.playerConnections)
        disconnectAll(record.characterConnections)
        if restoreHitbox then restoreHitbox(record) end
        destroyVisuals(record)
    end
    table.clear(records)
    if gui then gui:Destroy() end
    visuals:Destroy()
    runtime:Destroy()
end
unloadFunction.OnInvoke = function() cleanup(); return true end

-- 3. Player/character registry -----------------------------------------------------
local function partNamed(character, name)
    local part = character:FindFirstChild(name)
    return part and part:IsA("BasePart") and part or nil
end

local function refreshParts(record)
    local character = record.character
    if not character then return end
    record.humanoid = character:FindFirstChildOfClass("Humanoid")
    -- The default never falls back to Head. R6 uses Torso.
    record.aimPart = partNamed(character, Config.AimAssist.TargetPart)
        or partNamed(character, "UpperTorso") or partNamed(character, "Torso")
        or partNamed(character, "HumanoidRootPart")
    record.root = partNamed(character, "HumanoidRootPart") or record.aimPart
    record.labelPart = partNamed(character, "Head") or record.aimPart or record.root
    espElapsed = math.huge
end

local function clearCharacter(record)
    if target == record then target = nil; scanElapsed = math.huge end
    disconnectAll(record.characterConnections)
    if restoreHitbox then restoreHitbox(record) end
    destroyVisuals(record)
    record.character, record.humanoid = nil, nil
    record.root, record.aimPart, record.labelPart = nil, nil, nil
end

local function setCharacter(record, character)
    if record.character == character then return end
    clearCharacter(record)
    record.character = character
    if not character then return end
    refreshParts(record)
    -- Direct children cover standard R6/R15 body parts and streaming replacements.
    connect(character.ChildAdded, function(child)
        if child:IsA("BasePart") or child:IsA("Humanoid") then refreshParts(record) end
    end, record.characterConnections)
    connect(character.ChildRemoved, function(child)
        local changedAim = child == record.aimPart or child == record.humanoid
        local changedVisual = child == record.root or child == record.labelPart or child == record.humanoid
        local changedHitbox = child == record.hitboxPart
        if not changedAim and not changedVisual and not changedHitbox then return end
        if changedHitbox and restoreHitbox then restoreHitbox(record) end
        refreshParts(record)
        if changedAim and target == record then target = nil; scanElapsed = math.huge end
        -- A cached adornee may have just streamed out.
        if changedVisual then destroyVisuals(record) end
    end, record.characterConnections)
    connect(character.AncestryChanged, function()
        if not character:IsDescendantOf(Workspace) then
            if target == record then target = nil end
            if restoreHitbox then restoreHitbox(record) end
            destroyVisuals(record)
        end
        espElapsed = math.huge
    end, record.characterConnections)
end

local function invalidateTeams()
    target = nil
    scanElapsed = math.huge
    espElapsed = math.huge
end

local function addPlayer(player)
    if player == localPlayer or records[player] then return end
    local record = {
        player = player, character = nil,
        playerConnections = {}, characterConnections = {},
    }
    records[player] = record
    connect(player.CharacterAdded, function(character) setCharacter(record, character) end, record.playerConnections)
    connect(player.CharacterRemoving, function(character)
        if record.character == character then clearCharacter(record) end
    end, record.playerConnections)
    connect(player:GetPropertyChangedSignal("Team"), invalidateTeams, record.playerConnections)
    connect(player:GetPropertyChangedSignal("Neutral"), invalidateTeams, record.playerConnections)
    setCharacter(record, player.Character)
end

local function removePlayer(player)
    local record = records[player]
    if not record then return end
    clearCharacter(record)
    disconnectAll(record.playerConnections)
    records[player] = nil
end

local function isEnemy(player, teamCheck)
    if player == localPlayer then return false end
    if not teamCheck then return true end
    -- Neutral/nil teams are FFA, rather than one shared friendly team.
    return localPlayer.Neutral or player.Neutral or localPlayer.Team == nil
        or player.Team == nil or localPlayer.Team ~= player.Team
end

local function recordIsPresent(record)
    return records[record.player] == record and record.player.Parent == Players
        and record.character ~= nil and record.character == record.player.Character
        and record.character:IsDescendantOf(Workspace)
end

local function partIsPresent(part, character)
    return part ~= nil and part:IsDescendantOf(character)
end

local function isAlive(record)
    local humanoid = record.humanoid
    return humanoid ~= nil and humanoid.Parent == record.character and humanoid.Health > 0
end

-- 4. Target validation and selection ----------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false -- Obstruction follows CanQuery, not collision.
refreshRayFilter = function()
    local exclude = {visuals}
    if localPlayer.Character then table.insert(exclude, localPlayer.Character) end
    if camera then table.insert(exclude, camera) end -- Ignore camera-parented viewmodels.
    -- Artificially enlarged roots must not make a torso behind a wall seem visible.
    -- These exclusions apply only to this assist's visibility queries.
    for _, record in pairs(records) do
        if record.hitboxPart then table.insert(exclude, record.hitboxPart) end
    end
    rayParams.FilterDescendantsInstances = exclude
    rayFilterDirty = false
end

local function visible(character, position)
    local origin = camera.CFrame.Position
    local direction = position - origin
    if direction.Magnitude < 0.001 then return true end
    local result = Workspace:Raycast(origin, direction, rayParams)
    return result == nil or result.Instance:IsDescendantOf(character)
end

local function eligibleTarget(record, radiusSquared)
    if not recordIsPresent(record) then return nil, nil, "INVALID" end
    if not isEnemy(record.player, Config.AimAssist.TeamCheck) then return nil, nil, "TEAM" end
    if Config.AimAssist.AliveCheck and not isAlive(record) then return nil, nil, "DEAD" end
    if not partIsPresent(record.aimPart, record.character) then return nil, nil, "PART" end

    local position = record.aimPart.Position
    if Config.AimAssist.Prediction then
        position = position + record.aimPart.AssemblyLinearVelocity * Config.AimAssist.PredictionSeconds
    end
    local point, onScreen = camera:WorldToViewportPoint(position)
    if not onScreen or point.Z <= 0 then return nil, nil, "OFFSCREEN" end
    local dx = point.X - camera.ViewportSize.X * 0.5
    local dy = point.Y - camera.ViewportSize.Y * 0.5
    local distanceSquared = dx * dx + dy * dy
    if distanceSquared > radiusSquared then return nil, nil, "FOV" end
    return position, distanceSquared
end

local function targetIsVisible(record, position)
    if not Config.AimAssist.WallCheck then return true end
    -- Check the real torso as well as an optional predicted aim point.
    if not visible(record.character, record.aimPart.Position) then return false end
    return not Config.AimAssist.Prediction or visible(record.character, position)
end

local function acquireTarget(radiusSquared)
    local best, bestPosition, bestDistance = nil, nil, math.huge
    diagnostics.Scans = diagnostics.Scans + 1
    diagnostics.Candidates, diagnostics.InFOV, diagnostics.Blocked, diagnostics.Outside = 0, 0, 0, 0
    for _, record in pairs(records) do
        diagnostics.Candidates = diagnostics.Candidates + 1
        local position, distanceSquared, reason = eligibleTarget(record, radiusSquared)
        if position then diagnostics.InFOV = diagnostics.InFOV + 1
        elseif reason == "FOV" or reason == "OFFSCREEN" then diagnostics.Outside = diagnostics.Outside + 1 end
        local winsTie = best ~= nil and distanceSquared == bestDistance
            and record.player.UserId < best.player.UserId
        if position and (distanceSquared < bestDistance or winsTie) then
            if targetIsVisible(record, position) then
                best, bestPosition, bestDistance = record, position, distanceSquared
            else diagnostics.Blocked = diagnostics.Blocked + 1 end
        end
    end
    if not best then
        if diagnostics.Candidates == 0 then setAimStatus("NO_PLAYERS", "no other players")
        elseif diagnostics.InFOV > 0 and diagnostics.Blocked > 0 then setAimStatus("BLOCKED", "obstruction")
        elseif diagnostics.Outside > 0 then setAimStatus("OUTSIDE_FOV", "move camera closer")
        else setAimStatus("NO_ELIGIBLE", "team, health or parts") end
    end
    return best, bestPosition
end

-- 5. Local root resize and ESP ----------------------------------------------------
restoreHitbox = function(record)
    local part, original = record.hitboxPart, record.hitboxOriginal
    record.hitboxPart, record.hitboxOriginal = nil, nil
    record.hitboxWantedSize, record.hitboxSizeSetting = nil, nil
    if record.hitboxMarker then record.hitboxMarker:Destroy(); record.hitboxMarker = nil end
    if part and original then
        local ok, err = pcall(function()
            part.Size = original.Size
            part.CanCollide = original.CanCollide
            part.CanQuery = original.CanQuery
        end)
        if not ok then warn("[ArsenalAssist] Local size restore failed: " .. tostring(err)) end
        rayFilterDirty = true
    end
end

local function updateRecordHitbox(record)
    local settings = Config.Hitbox
    local root = record.root
    if not settings.Enabled or not camera or not recordIsPresent(record) or not isAlive(record)
        or not isEnemy(record.player, settings.TeamCheck) or not partIsPresent(root, record.character)
        or root.Name ~= "HumanoidRootPart"
        or (root.Position - camera.CFrame.Position).Magnitude > settings.MaxDistance then
        restoreHitbox(record)
        return
    end
    if record.hitboxPart ~= root then
        restoreHitbox(record)
        record.hitboxOriginal = {Size = root.Size, CanCollide = root.CanCollide, CanQuery = root.CanQuery}
        record.hitboxPart = root
        rayFilterDirty = true
    end
    if record.hitboxSizeSetting ~= settings.Size then
        local size = record.hitboxOriginal.Size
        record.hitboxWantedSize = Vector3.new(math.max(size.X, settings.Size),
            math.max(size.Y, settings.Size), math.max(size.Z, settings.Size))
        record.hitboxSizeSetting = settings.Size
    end
    -- Only local geometry/query flags change. No damage remotes or touch events.
    if root.Size ~= record.hitboxWantedSize then root.Size = record.hitboxWantedSize end
    if root.CanCollide then root.CanCollide = false end
    if not root.CanQuery then root.CanQuery = true end
    if settings.ShowBox then
        if not record.hitboxMarker then
            local marker = Instance.new("BoxHandleAdornment")
            marker.Name = "Hitbox_" .. tostring(record.player.UserId)
            marker.Adornee = root
            marker.Color3 = Color3.fromRGB(255, 183, 96)
            marker.Transparency = 0.85
            marker.ZIndex = 1
            marker.Parent = visuals
            record.hitboxMarker = marker
        end
        record.hitboxMarker.Size = record.hitboxWantedSize
        record.hitboxMarker.AlwaysOnTop = Config.ESP.ThroughWalls
    elseif record.hitboxMarker then
        record.hitboxMarker:Destroy()
        record.hitboxMarker = nil
    end
end

local function updateAllHitboxes()
    for _, record in pairs(records) do updateRecordHitbox(record) end
    if rayFilterDirty then refreshRayFilter() end
end

local OUTLINE_COLOR = Color3.fromRGB(255, 114, 104)
local function suspendVisuals(record)
    if record.highlight then record.highlight.Enabled = false end
    if record.billboard then record.billboard.Enabled = false end
    if record.inactiveSince == nil then record.inactiveSince = clock end
    if Config.Performance.AutoCleanup
        and clock - record.inactiveSince >= Config.Performance.IdleVisualLifetime then
        destroyVisuals(record)
    end
end

local function espDistance(record)
    local esp = Config.ESP
    if not camera or not esp.Enabled or not recordIsPresent(record)
        or not isEnemy(record.player, esp.TeamCheck) or not isAlive(record)
        or not partIsPresent(record.root, record.character) then
        return nil
    end
    local distance = (record.root.Position - camera.CFrame.Position).Magnitude
    return distance <= esp.MaxDistance and distance or nil
end

local function updateRecordESP(record)
    local esp = Config.ESP
    local distance = espDistance(record)
    if distance == nil then suspendVisuals(record); return end
    record.inactiveSince = nil

    if not esp.Outlines and record.highlight then
        record.highlight:Destroy()
        record.highlight = nil
        highlightCount = highlightCount - 1
    end
    if esp.Outlines and not record.highlight and highlightCount < Config.Performance.MaxHighlights then
        local highlight = Instance.new("Highlight")
        highlight.Name = "Enemy_" .. tostring(record.player.UserId)
        highlight.Adornee = record.character
        highlight.FillTransparency = 1
        highlight.OutlineTransparency = 0.15
        highlight.OutlineColor = OUTLINE_COLOR
        highlight.Parent = visuals
        record.highlight = highlight
        highlightCount = highlightCount + 1
    end
    if record.highlight then
        record.highlight.Adornee = record.character
        record.highlight.DepthMode = esp.ThroughWalls
            and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        record.highlight.Enabled = true
    end

    local needsLabel = esp.ShowNames or esp.ShowHealth or esp.ShowDistance
    if not needsLabel or not partIsPresent(record.labelPart, record.character) then
        if record.billboard then record.billboard:Destroy() end
        record.billboard, record.label, record.lastText = nil, nil, nil
        return
    end
    if not record.billboard then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "Label_" .. tostring(record.player.UserId)
        billboard.Size = UDim2.fromOffset(220, 56)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
        billboard.MaxDistance = esp.MaxDistance
        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 13
        label.TextColor3 = Color3.fromRGB(255, 235, 230)
        label.TextStrokeTransparency = 0.3
        label.TextWrapped = true
        label.RichText = false
        label.Parent = billboard
        billboard.Parent = visuals
        record.billboard, record.label = billboard, label
    end
    record.billboard.Adornee = record.labelPart
    record.billboard.AlwaysOnTop = esp.ThroughWalls
    record.billboard.MaxDistance = esp.MaxDistance
    record.billboard.Enabled = true
    local text = ""
    if esp.ShowNames then text = record.player.DisplayName .. " (@" .. record.player.Name .. ")" end
    if esp.ShowHealth then
        if text ~= "" then text = text .. "\n" end
        text = text .. tostring(math.floor(record.humanoid.Health + 0.5)) .. "/"
            .. tostring(math.floor(record.humanoid.MaxHealth + 0.5)) .. " HP"
    end
    if esp.ShowDistance then
        if text ~= "" then text = text .. "  |  " end
        text = text .. tostring(math.floor(distance + 0.5)) .. " studs"
    end
    if text ~= record.lastText then record.label.Text = text; record.lastText = text end
end

local function updateAllESP()
    -- Disabled Highlights still consume engine slots. At our budget limit,
    -- reclaim ineligible owners first so iteration order cannot starve newcomers.
    -- This bounded extra pass runs only when the owned budget is full.
    if highlightCount >= Config.Performance.MaxHighlights then
        for _, record in pairs(records) do
            if record.highlight and (not Config.ESP.Outlines or espDistance(record) == nil) then
                record.highlight:Destroy()
                record.highlight = nil
                highlightCount = highlightCount - 1
            end
        end
    end
    for _, record in pairs(records) do updateRecordESP(record) end
end

-- 6. Configuration application and lightweight UI ---------------------------------
local function applyConfig(patch)
    local nextConfig, err = validatedPatch(patch)
    if not nextConfig then return false, err end
    Config = nextConfig
    dragInput = nil
    releaseAim() -- Changing behavior requires a fresh press, never a stale hold.
    for _, record in pairs(records) do refreshParts(record) end
    -- Budget reductions free old slots immediately, then rebuild up to the new cap.
    if highlightCount > Config.Performance.MaxHighlights then
        for _, record in pairs(records) do destroyVisuals(record) end
    end
    espElapsed = math.huge
    updateAllHitboxes()
    updateAllESP()
    refreshUI()
    return true, copy(Config)
end

local function getStats()
    local players, labels, characterConnections = 0, 0, 0
    local playerConnections = 0
    for _, record in pairs(records) do
        players = players + 1
        if record.billboard then labels = labels + 1 end
        characterConnections = characterConnections + #record.characterConnections
        playerConnections = playerConnections + #record.playerConnections
    end
    return {
        Running = running, Players = players, Highlights = highlightCount, Labels = labels,
        Connections = #connections + playerConnections + characterConnections,
        TargetUserId = target and target.player.UserId or nil,
        ActivationHeld = held, RenderBound = renderBound,
        ActivationSource = activationSource,
        Revision = "tablet3",
        RenderPhases = #renderBindings,
        Diagnostics = copy(diagnostics),
    }
end

local function diagnosticReport()
    local errorText = diagnostics.PixelError and string.format("%.1f", diagnostics.PixelError) or "none"
    return string.format("KVK Arsenal tablet3 | manual fire\nstate=%s (%s)\ntarget=%s camera=%s armed=%s\nFOV=%d strength=%.3f errorPx=%s\nscans=%d candidates=%d inFOV=%d blocked=%d overrides=%d rebases=%d\nlocalHitbox=%s",
        diagnostics.State, diagnostics.Detail, target and target.player.Name or "none",
        camera and camera.CameraType.Name or "none", tostring(held), Config.AimAssist.FOV,
        Config.AimAssist.Smoothness, errorText, diagnostics.Scans, diagnostics.Candidates,
        diagnostics.InFOV, diagnostics.Blocked, diagnostics.CameraOverwrites,
        diagnostics.CameraRebases, tostring(Config.Hitbox.Enabled))
end

configureFunction.OnInvoke = function(action, payload)
    if action == "Get" then return copy(Config) end
    if action == "Patch" then return applyConfig(payload) end
    if action == "Reset" then return applyConfig(copy(defaults)) end
    if action == "Stats" then return getStats() end
    if action == "Report" then return diagnosticReport() end
    return false, "Use Get, Patch, Reset, Stats, or Report."
end

local function create(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props) do object[key] = value end
    object.Parent = parent
    return object
end

local function buildUI()
    gui = create("ScreenGui", {
        Name = "ArsenalAssistESP_UI", ResetOnSpawn = false, DisplayOrder = 50,
        IgnoreGuiInset = true, ScreenInsets = Enum.ScreenInsets.None,
        ClipToDeviceSafeArea = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, playerGui)
    fovCircle = create("Frame", {
        Name = "FOV", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
        BorderSizePixel = 0, Visible = false,
    }, gui)
    create("UICorner", {CornerRadius = UDim.new(0.5, 0)}, fovCircle)
    create("UIStroke", {Color = Color3.fromRGB(185, 211, 255), Thickness = 1, Transparency = 0.3}, fovCircle)
    panel = create("Frame", {
        Name = "Panel", Position = UDim2.fromOffset(16, 64), Size = UDim2.fromOffset(340, 480),
        BackgroundColor3 = Color3.fromRGB(24, 29, 39), BorderSizePixel = 0, Active = true,
        Visible = not UserInputService.TouchEnabled,
    }, gui)
    create("UICorner", {CornerRadius = UDim.new(0, 10)}, panel)
    uiScale = create("UIScale", {Scale = 1}, panel)
    create("TextLabel", {
        Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(312, 24),
        BackgroundTransparency = 1, Text = "AIM ASSIST + ESP", Font = Enum.Font.GothamBold,
        TextSize = 17, TextColor3 = Color3.fromRGB(235, 240, 250), TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)
    statusLabel = create("TextLabel", {
        Name = "LockStatus",
        Position = UDim2.fromOffset(14, 36), Size = UDim2.fromOffset(312, 34),
        BackgroundTransparency = 1, Text = "RMB: hold to track | F1: hide panel", Font = Enum.Font.Gotham,
        TextSize = 12, TextColor3 = Color3.fromRGB(170, 183, 205), TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)
    local list = create("ScrollingFrame", {
        Position = UDim2.fromOffset(12, 78), Size = UDim2.fromOffset(316, 344),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
        CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
    }, panel)
    create("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, list)
    local refreshers = {}
    local order = 0
    local rowHeight = UserInputService.TouchEnabled and 44 or 30
    local function button(parent, text, size, position)
        return create("TextButton", {
            Text = text, Size = size, Position = position or UDim2.fromOffset(0, 0),
            BackgroundColor3 = Color3.fromRGB(40, 49, 66), BorderSizePixel = 0,
            Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(230, 238, 250),
            AutoButtonColor = true,
            Active = true,
        }, parent)
    end
    local function toggle(label, section, key)
        order = order + 1
        local control = button(list, "", UDim2.new(1, -8, 0, rowHeight))
        control.LayoutOrder = order
        table.insert(refreshers, function()
            control.Text = label .. ": " .. (Config[section][key] and "ON" or "OFF")
        end)
        connect(control.Activated, function()
            applyConfig({[section] = {[key] = not Config[section][key]}})
        end)
    end
    local function numeric(label, section, key, step, format)
        order = order + 1
        local row = create("Frame", {
            Size = UDim2.new(1, -8, 0, rowHeight), BackgroundTransparency = 1, LayoutOrder = order,
        }, list)
        local caption = create("TextLabel", {
            Size = UDim2.new(1, -84, 1, 0), BackgroundTransparency = 1,
            TextColor3 = Color3.fromRGB(230, 238, 250), Font = Enum.Font.Gotham,
            TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
        }, row)
        local minus = button(row, "-", UDim2.fromOffset(36, rowHeight), UDim2.new(1, -80, 0, 0))
        local plus = button(row, "+", UDim2.fromOffset(36, rowHeight), UDim2.new(1, -40, 0, 0))
        table.insert(refreshers, function()
            caption.Text = label .. ": " .. string.format(format, Config[section][key])
        end)
        connect(minus.Activated, function() applyConfig({[section] = {[key] = Config[section][key] - step}}) end)
        connect(plus.Activated, function() applyConfig({[section] = {[key] = Config[section][key] + step}}) end)
    end
    local aimPresets = {
        {Name = "Subtle", Strength = 0.055, FOV = 75},
        {Name = "Tablet", Strength = 0.22, FOV = 140},
        {Name = "Fast", Strength = 0.35, FOV = 180},
    }
    local function presetIndex()
        for i, preset in ipairs(aimPresets) do
            if Config.AimAssist.Smoothness == preset.Strength and Config.AimAssist.FOV == preset.FOV then return i end
        end
        return 0
    end
    order = order + 1
    local presetButton = button(list, "", UDim2.new(1, -8, 0, rowHeight))
    presetButton.Name = "AimPreset"
    presetButton.LayoutOrder = order
    table.insert(refreshers, function()
        local index = presetIndex()
        presetButton.Text = "Aim preset: " .. (index > 0 and aimPresets[index].Name or "Custom")
    end)
    connect(presetButton.Activated, function()
        local preset = aimPresets[presetIndex() % #aimPresets + 1]
        applyConfig({AimAssist = {Smoothness = preset.Strength, FOV = preset.FOV}})
    end)
    order = order + 1
    local copyDiagnostics = button(list, "Copy diagnostics", UDim2.new(1, -8, 0, rowHeight))
    copyDiagnostics.Name = "CopyDiagnostics"
    copyDiagnostics.LayoutOrder = order
    connect(copyDiagnostics.Activated, function()
        local report = diagnosticReport()
        local copied = type(setclipboard) == "function" and pcall(setclipboard, report)
        if not copied then print(report) end
        copyDiagnostics.Text = copied and "Diagnostics copied" or "Diagnostics printed to output"
    end)
    toggle("Aim assist [F2]", "AimAssist", "Enabled")
    toggle("ESP [F3]", "ESP", "Enabled")
    numeric("Tracking strength", "AimAssist", "Smoothness", 0.025, "%.3f")
    numeric("FOV radius (pixels)", "AimAssist", "FOV", 5, "%.0f")
    numeric("ESP range (studs)", "ESP", "MaxDistance", 25, "%.0f")
    toggle("Show FOV [F4]", "AimAssist", "ShowFOV")
    toggle("Retain target", "AimAssist", "TargetLock")
    toggle("Aim visibility check", "AimAssist", "WallCheck")
    toggle("Aim team filter", "AimAssist", "TeamCheck")
    toggle("ESP team filter", "ESP", "TeamCheck")
    toggle("Enemy outlines", "ESP", "Outlines")
    toggle("ESP through walls", "ESP", "ThroughWalls")
    toggle("Names", "ESP", "ShowNames")
    toggle("Health", "ESP", "ShowHealth")
    toggle("Distance", "ESP", "ShowDistance")
    toggle("Local hitbox resize", "Hitbox", "Enabled")
    numeric("Local size (studs)", "Hitbox", "Size", 1, "%.0f")
    toggle("Show local size box", "Hitbox", "ShowBox")
    toggle("Hitbox team filter", "Hitbox", "TeamCheck")
    order = order + 1
    local touchMode = button(list, "", UDim2.new(1, -8, 0, rowHeight))
    touchMode.Name = "TouchMode"
    touchMode.LayoutOrder = order
    table.insert(refreshers, function() touchMode.Text = "Touch aim mode: " .. Config.Mobile.ActivationMode end)
    connect(touchMode.Activated, function()
        applyConfig({Mobile = {ActivationMode = Config.Mobile.ActivationMode == "Toggle" and "Hold" or "Toggle"}})
    end)
    local reset = button(panel, "Reset defaults [F6]", UDim2.fromOffset(180, 32), UDim2.fromOffset(12, 434))
    local unload = button(panel, "Unload [End]", UDim2.fromOffset(126, 32), UDim2.fromOffset(202, 434))
    connect(reset.Activated, function() applyConfig(copy(defaults)) end)
    connect(unload.Activated, cleanup)

    -- This dock is a sibling of Panel, so hiding settings never removes touch controls.
    touchDock = create("Frame", {
        Name = "TouchControls", AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(144, 306), BackgroundColor3 = Color3.fromRGB(24, 29, 39),
        BackgroundTransparency = 0.10, BorderSizePixel = 0, Visible = false, Active = false,
    }, gui)
    create("UICorner", {CornerRadius = UDim.new(0, 10)}, touchDock)
    touchScale = create("UIScale", {Scale = 1}, touchDock)
    local handle = button(touchDock, "MOVE CONTROLS", UDim2.fromOffset(128, 26), UDim2.fromOffset(8, 0))
    handle.Name = "DragHandle"
    touchAimButton = button(touchDock, "AIM: OFF", UDim2.fromOffset(128, 48), UDim2.fromOffset(8, 34))
    touchAimButton.Name = "AimButton"
    touchAimButton.TextSize = 15
    touchESPButton = button(touchDock, "ESP: ON", UDim2.fromOffset(128, 48), UDim2.fromOffset(8, 88))
    touchESPButton.Name = "ESPButton"
    touchHitboxButton = button(touchDock, "HITBOX: ON", UDim2.fromOffset(128, 48), UDim2.fromOffset(8, 142))
    touchHitboxButton.Name = "HitboxButton"
    local settings = button(touchDock, "SETTINGS", UDim2.fromOffset(128, 48), UDim2.fromOffset(8, 196))
    settings.Name = "SettingsButton"
    local touchUnload = button(touchDock, "UNLOAD", UDim2.fromOffset(128, 48), UDim2.fromOffset(8, 250))
    touchUnload.Name = "UnloadButton"

    refreshTouchState = function()
        local text = Config.Mobile.ActivationMode == "Hold" and (held and "HOLD AIM: ON" or "HOLD AIM")
            or (held and "AIM: ON" or "AIM: OFF")
        if held then text = text .. "\n" .. diagnostics.State end
        if touchAimButton.Text ~= text then touchAimButton.Text = text end
        local espText = Config.ESP.Enabled and "ESP: ON" or "ESP: OFF"
        if touchESPButton.Text ~= espText then touchESPButton.Text = espText end
        local hitboxText = Config.Hitbox.Enabled and "HITBOX: ON" or "HITBOX: OFF"
        if touchHitboxButton.Text ~= hitboxText then touchHitboxButton.Text = hitboxText end
    end
    layoutTouchDock = function()
        local viewport = camera and camera.ViewportSize
        touchDock.Visible = Config.Mobile.Enabled and UserInputService.TouchEnabled
            and viewport ~= nil and viewport.X >= 48 and viewport.Y >= 48
        if not touchDock.Visible then return end
        local scale = math.min(Config.Mobile.ButtonScale, (viewport.X - 24) / 144, (viewport.Y - 24) / 306)
        local insetX, insetY = 12 + 72 * scale, 12 + 153 * scale
        local x = math.clamp(Config.Mobile.DockX * viewport.X, insetX, viewport.X - insetX)
        local y = math.clamp(Config.Mobile.DockY * viewport.Y, insetY, viewport.Y - insetY)
        touchDockCenter = Vector2.new(x, y)
        touchDock.Position = UDim2.fromOffset(x, y)
        touchScale.Scale = scale
    end
    local function canUseTouch()
        return running and Config.Mobile.Enabled and UserInputService.TouchEnabled
            and windowFocused and not menuOpen and not UserInputService:GetFocusedTextBox()
    end
    local function beginTouch(input, holdMode)
        if not canUseTouch() or (holdMode and touchInput ~= nil) then return end
        if not Config.AimAssist.Enabled then applyConfig({AimAssist = {Enabled = true}}) end
        releaseAim()
        held = true
        activationSource = holdMode and "TouchHold" or "TouchToggle"
        touchInput = holdMode and input or nil
        scanElapsed = math.huge
        setAimStatus("SEARCHING", "manual fire")
        refreshTouchState()
    end
    connect(touchAimButton.Activated, function(input)
        if Config.Mobile.ActivationMode ~= "Toggle" or not canUseTouch() then return end
        if held and activationSource == "TouchToggle" then releaseAim()
        else beginTouch(input, false) end
    end)
    connect(touchAimButton.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch and Config.Mobile.ActivationMode == "Hold" then
            beginTouch(input, true)
        end
    end)
    connect(touchESPButton.Activated, function() applyConfig({ESP = {Enabled = not Config.ESP.Enabled}}) end)
    connect(touchHitboxButton.Activated, function() applyConfig({Hitbox = {Enabled = not Config.Hitbox.Enabled}}) end)
    connect(settings.Activated, function() panel.Visible = not panel.Visible end)
    connect(touchUnload.Activated, cleanup)
    connect(handle.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch or not canUseTouch() or dragInput then return end
        dragInput = input
        dragOrigin = Vector2.new(input.Position.X, input.Position.Y)
        dragStartCenter = touchDockCenter
    end)
    connect(UserInputService.InputChanged, function(input)
        if input ~= dragInput or not dragOrigin or not dragStartCenter or not camera then return end
        if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
            dragInput = nil
            return
        end
        local viewport = camera.ViewportSize
        if viewport.X <= 0 or viewport.Y <= 0 then return end
        Config.Mobile.DockX = math.clamp((dragStartCenter.X + input.Position.X - dragOrigin.X) / viewport.X, 0, 1)
        Config.Mobile.DockY = math.clamp((dragStartCenter.Y + input.Position.Y - dragOrigin.Y) / viewport.Y, 0, 1)
        layoutTouchDock()
    end)
    connect(UserInputService:GetPropertyChangedSignal("TouchEnabled"), function()
        dragInput = nil
        releaseAim()
        layoutTouchDock()
    end)
    refreshUI = function()
        for _, refresh in ipairs(refreshers) do refresh() end
        refreshTouchState()
        layoutTouchDock()
    end
    refreshUI()
end

-- 7. Input and camera -------------------------------------------------------------
local function activationMatches(input)
    local key = Config.AimAssist.ActivationKey
    return input.UserInputType == key or input.KeyCode == key
end

local function activationStillDown()
    if activationSource == "TouchToggle" then
        return Config.Mobile.Enabled and UserInputService.TouchEnabled
    elseif activationSource == "TouchHold" then
        if not Config.Mobile.Enabled or not UserInputService.TouchEnabled or not touchInput then return false end
        return touchInput.UserInputState == Enum.UserInputState.Begin
            or touchInput.UserInputState == Enum.UserInputState.Change
    end
    local key = Config.AimAssist.ActivationKey
    if key.EnumType == Enum.KeyCode then return UserInputService:IsKeyDown(key) end
    return UserInputService:IsMouseButtonPressed(key)
end

local function localCharacterIsAlive()
    local character = localPlayer.Character
    if not character or not character:IsDescendantOf(Workspace) then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

local lastViewport = Vector2.new(-1, -1)
local lastFOV = -1

local function prepareCamera(dt)
    wroteThisFrame = false
    if not running or not held or not Config.AimAssist.Enabled or not camera or not camera.Parent then return end
    if dt <= 0 or dt > 0.25 or camera.CameraType ~= Enum.CameraType.Custom then resetCameraMemory(); return end
    -- Translation can change independently, so compare rotations and preserve the
    -- current position. An unknown external rotation must not receive stale carry.
    if previousBaseFrame and lastWrittenFrame and lastWriteCamera == camera then
        local rotation = camera.CFrame.Rotation
        if rotation:FuzzyEq(lastWrittenFrame.Rotation, 0.00001) then
            camera.CFrame = CFrame.new(camera.CFrame.Position) * previousBaseFrame.Rotation
        elseif not rotation:FuzzyEq(previousBaseFrame.Rotation, 0.00001) then
            -- Native camera already owns a changed view (for example recoil).
            -- Commit it as the new base instead of adding our old correction twice.
            diagnostics.CameraRebases = diagnostics.CameraRebases + 1
            resetCameraMemory()
        end
    end
end

local function onRender(dt)
    if not running then return end
    diagnostics.Frames = diagnostics.Frames + 1
    if rayFilterDirty then refreshRayFilter() end
    if not camera or not camera.Parent then
        target = nil
        resetCameraMemory()
        setAimStatus("WAIT_CAMERA", "CurrentCamera unavailable")
        if fovCircle then fovCircle.Visible = false end
        if touchDock then touchDock.Visible = false end
        return
    end
    local viewport = camera.ViewportSize
    if viewport ~= lastViewport then
        dragInput = nil
        lastViewport = viewport
        fovCircle.Position = UDim2.fromOffset(viewport.X * 0.5, viewport.Y * 0.5)
        uiScale.Scale = math.clamp(math.min(viewport.X / 380, viewport.Y / 570), 0.2, 1)
        layoutTouchDock()
    end
    if lastFOV ~= Config.AimAssist.FOV then
        lastFOV = Config.AimAssist.FOV
        fovCircle.Size = UDim2.fromOffset(lastFOV * 2, lastFOV * 2)
    end
    fovCircle.Visible = Config.AimAssist.Enabled and Config.AimAssist.ShowFOV
        and viewport.X > 0 and viewport.Y > 0

    if not held or not Config.AimAssist.Enabled or not windowFocused or menuOpen
        or UserInputService:GetFocusedTextBox() or not activationStillDown() then
        releaseAim()
        return
    end
    if dt <= 0 or dt > 0.25 or viewport.X <= 0 or viewport.Y <= 0
        or UserInputService.VREnabled or camera.CameraType ~= Enum.CameraType.Custom
        or not localCharacterIsAlive() then
        target = nil
        resetCameraMemory()
        if camera.CameraType ~= Enum.CameraType.Custom then setAimStatus("CAMERA_PAUSED", camera.CameraType.Name)
        elseif not localCharacterIsAlive() then setAimStatus("NO_CHARACTER", "waiting for alive character")
        elseif UserInputService.VREnabled then setAimStatus("CAMERA_PAUSED", "VR")
        else setAimStatus("PAUSED", "frame or viewport unavailable") end
        scanElapsed = math.huge
        return
    end

    diagnostics.ActiveFrames = diagnostics.ActiveFrames + 1
    local baseFrame = camera.CFrame
    -- Carry correction across frames even when the game writes an absolute base
    -- angle each frame. Project targets from the actual carried view, not the base.
    if cameraOffset then camera.CFrame = baseFrame * cameraOffset end

    local radiusSquared = Config.AimAssist.FOV * Config.AimAssist.FOV
    local position = nil
    if target then
        position = eligibleTarget(target, radiusSquared)
        if not position or not targetIsVisible(target, position) then
            target = nil
            position = nil
            scanElapsed = math.huge
        end
    end
    scanElapsed = scanElapsed + dt
    -- An empty search must not delay a newly eligible target on the next frame.
    -- Only optional reselection of an already valid target is rate limited.
    if not target or (not Config.AimAssist.TargetLock
        and scanElapsed >= Config.Performance.AcquireInterval) then
        target, position = acquireTarget(radiusSquared)
        scanElapsed = 0
    end
    if not target or not position then resetCameraMemory(); diagnostics.PixelError = nil; return end
    if Config.AimAssist.Smoothness == 0 then resetCameraMemory(); setAimStatus("PAUSED", "strength is zero"); return end
    local current = camera.CFrame
    if (position - current.Position).Magnitude < 0.001 then return end
    local goal = CFrame.lookAt(current.Position, position, current.UpVector)
    camera.CFrame = current:Lerp(goal, smoothingAlpha(Config.AimAssist.Smoothness, dt))
    previousBaseFrame = baseFrame
    lastWrittenFrame, lastWriteCamera = camera.CFrame, camera
    cameraOffset = baseFrame.Rotation:ToObjectSpace(lastWrittenFrame.Rotation)
    wroteThisFrame = true
    local point = camera:WorldToViewportPoint(position)
    local dx, dy = point.X - viewport.X * 0.5, point.Y - viewport.Y * 0.5
    diagnostics.PixelError = math.sqrt(dx * dx + dy * dy)
    setAimStatus(diagnostics.PixelError <= 4 and "LOCKED" or "TRACKING", "manual fire")
end

local function observeCamera()
    -- Best effort at this priority only; no universal final camera writer exists.
    if running and wroteThisFrame and camera == lastWriteCamera
        and not camera.CFrame.Rotation:FuzzyEq(lastWrittenFrame.Rotation, 0.00001) then
        diagnostics.CameraOverwrites = diagnostics.CameraOverwrites + 1
        diagnostics.CameraRebases = diagnostics.CameraRebases + 1
        diagnostics.PixelError = nil
        resetCameraMemory()
        setAimStatus("CAMERA_OVERRIDE", "another camera writer")
    end
end

-- 8. Initialization with fail-closed teardown -------------------------------------
local ok, initError = xpcall(function()
    buildUI()
    refreshRayFilter()
    connect(Players.PlayerAdded, addPlayer)
    connect(Players.PlayerRemoving, removePlayer)
    for _, player in ipairs(Players:GetPlayers()) do addPlayer(player) end
    connect(localPlayer:GetPropertyChangedSignal("Team"), invalidateTeams)
    connect(localPlayer:GetPropertyChangedSignal("Neutral"), invalidateTeams)
    connect(localPlayer.CharacterAdded, function() releaseAim(); refreshRayFilter() end)
    connect(localPlayer.CharacterRemoving, function() releaseAim(); refreshRayFilter() end)
    connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
        camera = Workspace.CurrentCamera
        dragInput = nil
        releaseAim()
        refreshRayFilter()
        lastViewport = Vector2.new(-1, -1)
        espElapsed = math.huge
    end)
    connect(UserInputService.InputBegan, function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() or menuOpen or not windowFocused then return end
        if activationMatches(input) then
            releaseAim()
            held = true
            activationSource = "Hardware"
            scanElapsed = math.huge
            setAimStatus("SEARCHING", "manual fire")
            refreshTouchState()
        end
        local key = input.KeyCode
        if key == Enum.KeyCode.F1 then panel.Visible = not panel.Visible
        elseif key == Enum.KeyCode.F2 then applyConfig({AimAssist = {Enabled = not Config.AimAssist.Enabled}})
        elseif key == Enum.KeyCode.F3 then applyConfig({ESP = {Enabled = not Config.ESP.Enabled}})
        elseif key == Enum.KeyCode.F4 then applyConfig({AimAssist = {ShowFOV = not Config.AimAssist.ShowFOV}})
        elseif key == Enum.KeyCode.F6 then applyConfig(copy(defaults))
        elseif key == Enum.KeyCode.End then cleanup() end
    end)
    connect(UserInputService.InputEnded, function(input)
        -- Release even if another UI has consumed the event.
        if input == dragInput then dragInput = nil end
        if input == touchInput then releaseAim()
        elseif activationSource == "Hardware" and activationMatches(input) then releaseAim() end
    end)
    connect(UserInputService.WindowFocusReleased, function() windowFocused = false; dragInput = nil; releaseAim() end)
    connect(UserInputService.WindowFocused, function() windowFocused = true end)
    connect(UserInputService.TextBoxFocused, function() dragInput = nil; releaseAim() end)
    connect(GuiService.MenuOpened, function() menuOpen = true; dragInput = nil; releaseAim() end)
    connect(GuiService.MenuClosed, function() menuOpen = false end)
    -- Client loaders may not supply a LocalScript instance or a script global.
    -- The explicit Unload control works independently of script ownership.
    -- Destroying is best effort: Deferred signals cannot clean up a deleted script.
    if typeof(script) == "Instance" and script:IsA("LocalScript") then
        connect(script.Destroying, cleanup)
    end
    connect(runtime.Destroying, cleanup)
    connect(gui.Destroying, cleanup)
    connect(RunService.Heartbeat, function(dt)
        if not running then return end
        clock = clock + dt
        espElapsed = espElapsed + dt
        local interval = Config.Performance.OptimizeESP and Config.Performance.ESPInterval or (1 / 30)
        if espElapsed < interval then return end
        espElapsed = 0
        local success, err = xpcall(function()
            updateAllHitboxes()
            updateAllESP()
            local name = target and target.player.Name or "none"
            statusLabel.Text = diagnostics.State .. " | " .. diagnostics.Detail .. "\nTarget: " .. name
        end, debug.traceback)
        if not success then warn("[ArsenalAssist] ESP stopped: " .. tostring(err)); cleanup() end
    end)
    local function bindPhase(name, priority, callback)
        RunService:BindToRenderStep(name, priority, function(dt)
            if not running then return end
            local success, err = xpcall(callback, debug.traceback, dt)
            if not success then warn("[ArsenalAssist] Camera stopped: " .. tostring(err)); cleanup() end
        end)
        table.insert(renderBindings, name)
    end
    bindPhase(renderName .. "_Prepare", Enum.RenderPriority.Camera.Value - 1, prepareCamera)
    bindPhase(renderName, Enum.RenderPriority.Last.Value + 1, onRender)
    bindPhase(renderName .. "_Observe", Enum.RenderPriority.Last.Value + 2, observeCamera)
    renderBound = true
    if Config.Performance.DebugMode then print("[ArsenalAssist] Initialized. F1 panel; End unload.") end
end, debug.traceback)
if not ok then
    warn("[ArsenalAssist] Initialization failed: " .. tostring(initError))
    cleanup()
end


