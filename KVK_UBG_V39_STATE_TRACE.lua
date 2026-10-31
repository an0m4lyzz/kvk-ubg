-- [K]vk UBG V3.9 - DASH DIAGNOSTIC ADD-ON (read-only)
-- Launch V3.7 first, then this add-on. It does not dispatch any attacks or dashes.
-- Observations are local. They do not prove that a perfect dodge was awarded.

local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local localPlayer = Players.LocalPlayer
if not localPlayer then error('[K]vk Diagnostics: LocalPlayer unavailable') end

local env = _G
if type(getgenv) == 'function' then
    local ok, result = pcall(getgenv)
    if ok and type(result) == 'table' then env = result end
end
if env.KVK_UBG_V38_DIAG and type(env.KVK_UBG_V38_DIAG.Destroy) == 'function' then
    pcall(function() env.KVK_UBG_V38_DIAG:Destroy() end)
end
if env.KVK_UBG_V39_DIAG and type(env.KVK_UBG_V39_DIAG.Destroy) == 'function' then
    pcall(function() env.KVK_UBG_V39_DIAG:Destroy() end)
end

local diag = {
    running = true, connections = {}, stateConnections = {}, characterConnections = {},
    eventConnection = nil, dashEvent = nil, occupied = nil, character = nil,
    lines = {}, active = {}, sequence = 0, events = 0, pulses = 0,
    lastFlag = nil, lastSignalAt = nil, lastSignalValue = nil,
    currentSignalAt = nil, seenMovement = 0, missingFlag = 0,
    recent = 'Waiting for local dash events',
}
env.KVK_UBG_V39_DIAG = diag

local function timeNow() return os.clock() end
local function cleanConnections(connections)
    for i = #connections, 1, -1 do
        pcall(function() connections[i]:Disconnect() end)
        connections[i] = nil
    end
end
local function log(kind, message)
    if not diag.running then return end
    local line = string.format('[%s] %.3f  %s', kind, timeNow(), tostring(message))
    diag.lines[#diag.lines + 1] = line
    if #diag.lines > 240 then table.remove(diag.lines, 1) end
    diag.recent = line
    print('[K]vk V3.9 ' .. line)
end
local function getOccupied()
    local states = workspace:FindFirstChild('States')
    local state = states and states:FindFirstChild(localPlayer.Name)
    return state and state:FindFirstChild('Occupied') or nil
end
local function getFlag()
    local occupied = diag.occupied or getOccupied()
    if not occupied then return nil, 'missing Occupied' end
    local obj = occupied:FindFirstChild('Dashing')
    local attr = occupied:GetAttribute('Dashing')
    local objValue = obj and obj:IsA('BoolValue') and obj.Value or nil
    if attr == true or objValue == true then return true, 'true' end
    if type(attr) == 'boolean' or type(objValue) == 'boolean' then
        return false, 'false'
    end
    return nil, 'not exposed'
end
local function rootAndHumanoid()
    local character = localPlayer.Character
    if not character then return nil, nil end
    return character:FindFirstChild('HumanoidRootPart'), character:FindFirstChildOfClass('Humanoid')
end
local function currentHealth()
    local _, hum = rootAndHumanoid()
    return hum and hum.Health or nil
end
local function currentPosition()
    local root = rootAndHumanoid()
    return root and root.Position or nil
end

-- Read-only contextual state snapshots: compare accepted and missing dashes.
local WATCH_WORDS = {'dash','dodge','stun','block','guard','attack','punch',
    'cooldown','stamina','energy','action','busy','recover','hit','knock','ragdoll'}
local function relatedName(k)
    local low = string.lower(tostring(k))
    for _, v in ipairs(WATCH_WORDS) do
        if string.find(low, v, 1, true) then return true end
    end
    return false
end
local function stateText(v)
    if type(v) == 'number' or type(v) == 'boolean' then return tostring(v) end
    if type(v) == 'string' then return string.sub(v, 1, 30) end
end
local function summarizeState(o, label)
    if not o then return label .. '=missing' end
    local result = {}
    for k, v in pairs(o:GetAttributes()) do
        local value = stateText(v)
        if relatedName(k) and value then
            result[#result+1] = '@' .. tostring(k) .. ':' .. value
        end
    end
    for _, c in ipairs(o:GetChildren()) do
        if relatedName(c.Name) and (c:IsA('BoolValue') or c:IsA('NumberValue')
                or c:IsA('IntValue') or c:IsA('StringValue')) then
            local value = stateText(c.Value)
            if value then result[#result+1] = c.Name .. ':' .. value end
        end
    end
    table.sort(result)
    if #result > 30 then
        for i = #result, 31, -1 do table.remove(result, i) end
        result[#result+1] = '(truncated)'
    end
    return label .. '={' .. table.concat(result, ',') .. '}'
end
local function snapshot()
    local parts = {summarizeState(diag.occupied or getOccupied(), 'occupied'),
        summarizeState(localPlayer.Character, 'character')}
    local root, hum = rootAndHumanoid()
    if hum then
        parts[#parts+1] = string.format('humanoid={state:%s,hp:%.1f,move:%.2f}',
            hum:GetState().Name, hum.Health, hum.MoveDirection.Magnitude)
    end
    if root then
        local v = root.AssemblyLinearVelocity
        parts[#parts+1] = string.format('root={anchored:%s,speedXZ:%.1f}',
            tostring(root.Anchored), math.sqrt(v.X*v.X+v.Z*v.Z))
    end
    return table.concat(parts, ' ')
end

local function isActiveSignal(value)
    return value ~= nil and value ~= false and value ~= 0 and value ~= ''
end
local function onFlagChanged()
    local flag, source = getFlag()
    if flag ~= diag.lastFlag then
        if flag == true then
            diag.pulses = diag.pulses + 1
            log('FLAG-ON', 'Local Dashing flag became true (' .. source .. ')')
            local t = timeNow()
            for _, trial in ipairs(diag.active) do
                if not trial.flagAt and t - trial.at <= 0.6 then trial.flagAt = t end
            end
        elseif diag.lastFlag == true then
            log('FLAG-OFF', 'Local Dashing flag ended; value=' .. tostring(flag))
        end
        diag.lastFlag = flag
    end
end
local function attachOccupied()
    local occupied = getOccupied()
    if occupied == diag.occupied then return end
    cleanConnections(diag.stateConnections)
    diag.occupied = occupied
    diag.lastFlag = nil
    if not occupied then
        log('STATE', 'Occupied missing; watching for state creation')
        return
    end
    log('STATE', 'Occupied found; Dashing flag watched')
    diag.stateConnections[#diag.stateConnections + 1] = occupied:GetAttributeChangedSignal('Dashing'):Connect(onFlagChanged)
    local function bindValue(obj)
        if obj and obj:IsA('BoolValue') and obj.Name == 'Dashing' then
            diag.stateConnections[#diag.stateConnections + 1] = obj.Changed:Connect(onFlagChanged)
        end
    end
    bindValue(occupied:FindFirstChild('Dashing'))
    diag.stateConnections[#diag.stateConnections + 1] = occupied.ChildAdded:Connect(function(obj)
        bindValue(obj)
        onFlagChanged()
    end)
    diag.stateConnections[#diag.stateConnections + 1] = occupied.ChildRemoved:Connect(function(obj)
        if obj.Name == 'Dashing' then onFlagChanged() end
    end)
    onFlagChanged()
end
local function onSignalChanged()
    local char = diag.character
    if not char then return end
    local signal = char:GetAttribute('Perfect')
    if isActiveSignal(signal) and signal ~= diag.lastSignalValue then
        diag.currentSignalAt = timeNow()
        diag.lastSignalAt = timeNow()
        log('SIGNAL', 'Perfect=' .. tostring(signal)
            .. ' direction=' .. tostring(char:GetAttribute('NeededDirection')))
    elseif not isActiveSignal(signal) and diag.currentSignalAt then
        log('SIGNAL-END', string.format('Local Perfect attribute lifetime %.1f ms',
            (timeNow() - diag.currentSignalAt) * 1000))
        diag.currentSignalAt = nil
    end
    diag.lastSignalValue = signal
end
local function attachCharacter()
    local character = localPlayer.Character
    if character == diag.character then return end
    cleanConnections(diag.characterConnections)
    diag.character = character
    diag.currentSignalAt = nil
    diag.lastSignalValue = nil
    if character then
        diag.characterConnections[#diag.characterConnections + 1] = character:GetAttributeChangedSignal('Perfect'):Connect(onSignalChanged)
        diag.characterConnections[#diag.characterConnections + 1] = character:GetAttributeChangedSignal('NeededDirection'):Connect(function()
            if diag.currentSignalAt then
                log('DIR-CHANGE', 'NeededDirection=' .. tostring(character:GetAttribute('NeededDirection')))
            end
        end)
        onSignalChanged()
        log('CHAR', 'Character signal observer attached')
    end
end
local function startTrial(payload)
    local now = timeNow()
    diag.sequence = diag.sequence + 1
    diag.events = diag.events + 1
    local direction = type(payload) == 'table' and tostring(payload.Direction) or '(unknown payload)'
    local pos = currentPosition()
    local hp = currentHealth()
    local flag, source = getFlag()
    local signalAge = diag.lastSignalAt and (now - diag.lastSignalAt) * 1000 or nil
    local hadOverlap = #diag.active > 0
    for _, old in ipairs(diag.active) do old.overlap = true end
    local trial = {
        id = diag.sequence, at = now, direction = direction, overlap = hadOverlap,
        pos = pos, hp = hp, lowestHP = hp, flagAt = flag == true and now or nil,
        maxXZ = 0, maxPlanarSpeed = 0, samples = 0,
        startFlag = source, startSignalAge = signalAge, startState = snapshot(), midState = nil,
    }
    diag.active[#diag.active + 1] = trial
    log('EVENT', string.format('#%d ForceDash.Event dir=%s; signalAge=%s; flag=%s',
        trial.id, direction,
        signalAge and string.format('%.0f ms', signalAge) or 'unknown', source))
end
local function attachDashEvent()
    local events = ReplicatedStorage:FindFirstChild('Events')
    local dash = events and events:FindFirstChild('ForceDash')
    if dash == diag.dashEvent then return end
    if diag.eventConnection then pcall(function() diag.eventConnection:Disconnect() end) end
    diag.eventConnection = nil
    diag.dashEvent = nil
    if dash and dash:IsA('BindableEvent') then
        diag.dashEvent = dash
        diag.eventConnection = dash.Event:Connect(startTrial)
        log('HOOK', 'Read-only listener attached to Events.ForceDash.Event')
    else
        log('HOOK', 'ForceDash BindableEvent not found; no local event observation')
    end
end
local function sampleTrial(trial)
    if not trial.midState and timeNow() - trial.at >= 0.075 then
        trial.midState = snapshot()
    end
    local pos = currentPosition()
    if pos and trial.pos then
        local dx, dz = pos.X - trial.pos.X, pos.Z - trial.pos.Z
        trial.maxXZ = math.max(trial.maxXZ, math.sqrt(dx * dx + dz * dz))
    end
    local root = rootAndHumanoid()
    if root then
        local velocity = root.AssemblyLinearVelocity
        trial.maxPlanarSpeed = math.max(trial.maxPlanarSpeed,
            math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z))
    end
    local hp = currentHealth()
    if hp and (not trial.lowestHP or hp < trial.lowestHP) then trial.lowestHP = hp end
    local flag = getFlag()
    if flag == true and not trial.flagAt then trial.flagAt = timeNow() end
    trial.samples = trial.samples + 1
end
local function finishTrial(trial)
    local latency = trial.flagAt and string.format('%.0fms', (trial.flagAt - trial.at) * 1000) or 'NOT_SEEN'
    local hpLoss = trial.hp and trial.lowestHP and (trial.hp - trial.lowestHP) or nil
    if not trial.flagAt then diag.missingFlag = diag.missingFlag + 1 end
    if trial.maxXZ > 1 then diag.seenMovement = diag.seenMovement + 1 end
    log('RESULT', string.format('#%d dir=%s flagLatency=%s moveXZ=%.2f studs maxSpeed=%.1f hpLoss=%s samples=%d overlap=%s',
        trial.id, trial.direction, latency, trial.maxXZ, trial.maxPlanarSpeed,
        hpLoss and string.format('%.1f', hpLoss) or 'unknown', trial.samples, tostring(trial.overlap)))
    log(trial.flagAt and 'DASH-STATE' or 'NO-DASH-STATE',
        '#' .. tostring(trial.id) .. ' before: ' .. (trial.startState or 'n/a')
        .. ' | +75ms: ' .. (trial.midState or 'n/a') .. ' | +500ms: ' .. snapshot())
end

-- No server outcome is inferred from these diagnostic state snapshots.
-- Existing result logs remain unchanged for comparison with V3.8.
local gui = Instance.new('ScreenGui')
gui.Name = 'KVK_UBG_V39_DASH_DIAGNOSTIC'
gui.ResetOnSpawn = false
-- V3.7 uses DisplayOrder=900; explicitly render this diagnostic above it.
gui.DisplayOrder = 1100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = false
local playerGui = localPlayer:WaitForChild('PlayerGui', 10)
if not playerGui then error('[K]vk Diagnostics: PlayerGui unavailable') end
gui.Parent = playerGui
local frame = Instance.new('Frame')
frame.Name = 'Panel'
frame.Size = UDim2.fromOffset(310, 226)
frame.Position = UDim2.new(0, 10, 0.19, 0)
frame.BackgroundColor3 = Color3.fromRGB(22, 30, 45)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
local corner = Instance.new('UICorner')
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame
local layout = Instance.new('UIListLayout')
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = frame
local padding = Instance.new('UIPadding')
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = frame
local function makeText(content, height, order, fontSize)
    local label = Instance.new('TextLabel')
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 0, height)
    label.Text = content
    label.TextColor3 = Color3.fromRGB(232, 242, 252)
    label.TextSize = fontSize or 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Font = Enum.Font.Gotham
    label.LayoutOrder = order
    label.Parent = frame
    return label
end
local title = makeText('[K]vk V3.9  |  DASH + STATE TRACE', 24, 1, 13)
title.Font = Enum.Font.GothamBold
local summary = makeText('Waiting for ForceDash events...', 37, 2, 12)
local status = makeText('Read-only. Existing V3.7 combat settings unchanged.', 44, 3, 11)
local feedbackUntil = 0
local recent = makeText('No results yet', 49, 4, 11)
local controls = Instance.new('Frame')
controls.BackgroundTransparency = 1
controls.Size = UDim2.new(1, 0, 0, 35)
controls.LayoutOrder = 5
controls.Parent = frame
local function makeButton(text, x, width, onClick)
    local b = Instance.new('TextButton')
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextColor3 = Color3.fromRGB(245, 250, 255)
    b.BackgroundColor3 = Color3.fromRGB(43, 79, 111)
    b.BorderSizePixel = 0
    b.Size = UDim2.new(width, -3, 1, 0)
    b.Position = UDim2.new(x, 0, 0, 0)
    b.Parent = controls
    local bc = Instance.new('UICorner')
    bc.CornerRadius = UDim.new(0, 7)
    bc.Parent = b
    diag.connections[#diag.connections + 1] = b.Activated:Connect(onClick)
    return b
end
local function buildReport()
    local engine = env.KVK_UBG
    local cfg = engine and engine.cfg or {}
    local header = {
        '[K]vk UBG V3.9 DASH + STATE DIAGNOSTIC REPORT (read-only)',
        'PlaceId=' .. tostring(game.PlaceId),
        'Engine=' .. ((engine and engine.running) and 'V3.x running' or 'not detected'),
        string.format('Events=%d FlagPulses=%d TrialsWithoutFlag=%d EventsWithXZMovementOver1=%d',
            diag.events, diag.pulses, diag.missingFlag, diag.seenMovement),
        'Config confirmMs=' .. tostring(cfg.confirmMs)
            .. ' feintWindowMs=' .. tostring(cfg.feintWindowMs)
            .. ' antiFeint=' .. tostring(cfg.antiFeint)
            .. ' retry=' .. tostring(cfg.retry)
            .. ' directionFallback=' .. tostring(cfg.directionFallback),
        'WARNING: Movement can be ordinary walking/knockback; health loss does not necessarily equal a hit from the tested attack.',
        'WARNING: Event and flag observations do not confirm server acceptance or perfect dodge.',
        'WARNING: overlapping trials can share one dash/flag pulse; interpret overlap=true cautiously.',
        '=== ADD-ON EVENTS ===',
        table.concat(diag.lines, '\n'),
        '=== V3.x ENGINE EVENTS (last 90 max) ===',
        (engine and type(engine.logs) == 'table') and table.concat(engine.logs, '\n') or 'Unavailable',
    }
    return table.concat(header, '\n')
end
makeButton('COPY REPORT', 0, 0.48, function()
    local fn = env.setclipboard or env.toclipboard or _G.setclipboard or _G.toclipboard
    if type(fn) ~= 'function' then
        status.Text = 'Clipboard unavailable. Logs also print to executor console.'
        feedbackUntil = timeNow() + 4
        return
    end
    local ok, err = pcall(fn, buildReport())
    status.Text = ok and 'Report copied. Paste it into ChatGPT.' or ('Copy failed: ' .. tostring(err))
    feedbackUntil = timeNow() + 4
end)
makeButton('CLEAR', 0.5, 0.23, function()
    diag.lines = {}
    diag.missingFlag, diag.seenMovement, diag.events, diag.pulses = 0, 0, 0, 0
    diag.sequence = 0
    diag.active = {}
    log('RESET', 'Add-on report cleared')
end)
makeButton('CLOSE', 0.75, 0.25, function() diag:Destroy() end)

function diag:Destroy()
    if not self.running then return end
    self.running = false
    cleanConnections(self.connections)
    cleanConnections(self.stateConnections)
    cleanConnections(self.characterConnections)
    if self.eventConnection then pcall(function() self.eventConnection:Disconnect() end) end
    if gui then pcall(function() gui:Destroy() end) end
    if env.KVK_UBG_V39_DIAG == self then env.KVK_UBG_V39_DIAG = nil end
end

local lastRefresh = 0
local lastAttach = 0
diag.connections[#diag.connections + 1] = RunService.Heartbeat:Connect(function()
    if not diag.running then return end
    local now = timeNow()
    if now - lastAttach > 0.25 then
        lastAttach = now
        attachOccupied()
        attachCharacter()
        attachDashEvent()
    end
    onFlagChanged()
    for i = #diag.active, 1, -1 do
        local trial = diag.active[i]
        sampleTrial(trial)
        if now - trial.at > 0.5 then
            finishTrial(trial)
            table.remove(diag.active, i)
        end
    end
    if now - lastRefresh > 0.18 then
        lastRefresh = now
        local engine = env.KVK_UBG
        local flag, source = getFlag()
        summary.Text = string.format('Events: %d   Flag ON pulses: %d   No flag: %d\nMovement >1 stud: %d',
            diag.events, diag.pulses, diag.missingFlag, diag.seenMovement)
        if timeNow() >= feedbackUntil then
            status.Text = string.format('V3.x: %s | Dashing: %s | ForceDash: %s',
                (engine and engine.running) and 'RUNNING' or 'NOT FOUND',
                tostring(flag) .. ' (' .. source .. ')', diag.dashEvent and 'FOUND' or 'MISSING')
        end
        recent.Text = diag.recent:sub(1, 210)
    end
end)

log('START', 'V3.9 add-on running; no inputs injected; no combat settings changed')
attachOccupied()
attachCharacter()
attachDashEvent()