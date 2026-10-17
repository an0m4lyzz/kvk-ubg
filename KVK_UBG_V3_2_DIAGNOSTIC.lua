-- [K]vk V3.2 startup diagnostics: created BEFORE the full hub initializes.
local bootstrapGui, bootstrapStatus, bootstrapPlayerGui
local currentStage = "startup"
local function stage(value)
    currentStage = value
    if bootstrapStatus and bootstrapStatus.Parent then
        bootstrapStatus.Text = "[K]vk V3.2 | " .. value
    end
end

do
    local ok, errorText = pcall(function()
        local pl = game:GetService("Players").LocalPlayer
        bootstrapPlayerGui = pl and pl:WaitForChild("PlayerGui", 8)
        if not bootstrapPlayerGui then error("PlayerGui unavailable") end
        local prior = bootstrapPlayerGui:FindFirstChild("KVK_V32_STARTUP")
        if prior then prior:Destroy() end
        bootstrapGui = Instance.new("ScreenGui")
        bootstrapGui.Name = "KVK_V32_STARTUP"
        bootstrapGui.ResetOnSpawn = false
        bootstrapGui.DisplayOrder = 999
        bootstrapGui.Parent = bootstrapPlayerGui
        bootstrapStatus = Instance.new("TextLabel")
        bootstrapStatus.Name = "StartupStatus"
        bootstrapStatus.Size = UDim2.fromOffset(320, 64)
        bootstrapStatus.Position = UDim2.fromOffset(12, 64)
        bootstrapStatus.BackgroundColor3 = Color3.fromRGB(31, 45, 67)
        bootstrapStatus.TextColor3 = Color3.fromRGB(255, 255, 255)
        bootstrapStatus.Font = Enum.Font.GothamBold
        bootstrapStatus.TextSize = 14
        bootstrapStatus.TextWrapped = true
        bootstrapStatus.Text = "[K]vk V3.2 | Starting..."
        bootstrapStatus.Parent = bootstrapGui
        local detail = Instance.new("UICorner")
        detail.CornerRadius = UDim.new(0, 10)
        detail.Parent = bootstrapStatus
    end)
    if not ok then warn("[K]vk bootstrap: " .. tostring(errorText)) end
end

local initialized, failure = xpcall(function()
stage("Loading services")
-- [K]vk | UBG PREMIUM HUB V3.2
-- Standalone Luau | Delta iOS-oriented | no loaders or external dependencies
-- Root PlaceId: 13621938427 | UniverseId: 4730278139
-- WARNING: ForceDash and combat attributes are unverified game internals.
-- A successful BindableEvent:Fire is NOT proof of a server-accepted dodge.

-- Always build the diagnostic UI, even if the script was launched in
-- another place. Combat actions remain disabled outside the UBG experience.
local ROOT_PLACE_ID = 13621938427
local UNIVERSE_ID = 4730278139
local IS_UBG = game.PlaceId == ROOT_PLACE_ID or game.GameId == UNIVERSE_ID
if not IS_UBG then
    warn('[K]vk UBG V3.2: Unexpected PlaceId=' .. tostring(game.PlaceId)
        .. ', UniverseId=' .. tostring(game.GameId)
        .. '. UI will start, but combat actions are disabled.')
end

stage('Services / game validation')
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')
local HttpService = game:GetService('HttpService')
local localPlayer = Players.LocalPlayer
if not localPlayer then error('[K]vk V3.2: LocalPlayer missing') end

stage('Previous instance cleanup')
local env = _G
if type(getgenv) == 'function' then
    local ok, result = pcall(getgenv)
    if ok and type(result) == 'table' then env = result end
end
if type(env.KVK_UBG) == 'table' and type(env.KVK_UBG.Destroy) == 'function' then
    pcall(function() env.KVK_UBG:Destroy() end)
end

local VALID_DIRECTIONS = {Left = true, Right = true, Forward = true, Backward = true}
local SAVE_FILE = 'KVK_UBG_V3_settings.json'
local LOG_LIMIT = 45
local defaults = {
    master = true, dodge = true, antiFeint = true, distance = 14,
    confirmMs = 30, cooldownMs = 320, retry = false,
    esp = true, smallHud = true, espColor = 'Coral', espOpacity = 75,
    theme = 'Cyan', scale = 100, opacity = 96,
    animations = true, autosave = false,
}
local config = {}
for key, value in pairs(defaults) do config[key] = value end

local COLORS = {
    bg = Color3.fromRGB(13, 18, 28),
    panel = Color3.fromRGB(19, 25, 38),
    surface = Color3.fromRGB(28, 36, 52),
    elevated = Color3.fromRGB(34, 43, 63),
    stroke = Color3.fromRGB(53, 64, 88),
    text = Color3.fromRGB(243, 247, 255),
    muted = Color3.fromRGB(151, 165, 187),
    off = Color3.fromRGB(78, 86, 103),
    green = Color3.fromRGB(97, 223, 166),
    red = Color3.fromRGB(250, 113, 122),
    cyan = Color3.fromRGB(75, 206, 239),
    purple = Color3.fromRGB(172, 135, 255),
    amber = Color3.fromRGB(255, 195, 99),
}
local function accent()
    return config.theme == 'Purple' and COLORS.purple or COLORS.cyan
end
local function validate(key, value)
    if defaults[key] == nil then return nil end
    if type(defaults[key]) == 'boolean' then
        if type(value) == 'boolean' then return value end
        return nil
    end
    if type(defaults[key]) == 'number' then
        if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return nil end
        local limits = {
            distance = {7, 22, 1}, confirmMs = {0, 90, 5}, cooldownMs = {150, 800, 25},
            espOpacity = {10, 95, 5}, scale = {85, 110, 5}, opacity = {75, 100, 5},
        }
        local rule = limits[key]
        if not rule then return nil end
        local rounded = math.floor(value / rule[3] + 0.5) * rule[3]
        return math.clamp(rounded, rule[1], rule[2])
    end
    if key == 'theme' and (value == 'Cyan' or value == 'Purple') then return value end
    if key == 'espColor' and (value == 'Coral' or value == 'Cyan' or value == 'Purple') then return value end
    return nil
end
local function safeGetFileApi(name)
    local f = env[name]
    if type(f) ~= 'function' then f = _G[name] end
    return type(f) == 'function' and f or nil
end
local function loadSettings()
    local read = safeGetFileApi('readfile')
    if not read then return false, 'readfile unavailable' end
    local exists = safeGetFileApi('isfile')
    if exists then
        local ok, present = pcall(exists, SAVE_FILE)
        if not ok or not present then return false, 'No saved settings' end
    end
    local ok, raw = pcall(read, SAVE_FILE)
    if not ok or type(raw) ~= 'string' then return false, 'Could not read saved settings' end
    local decodedOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
    if not decodedOk or type(decoded) ~= 'table' then return false, 'Invalid settings JSON' end
    for key, val in pairs(decoded) do
        local clean = validate(key, val)
        if clean ~= nil then config[key] = clean end
    end
    return true, 'Settings loaded'
end
local function saveSettings()
    local write = safeGetFileApi('writefile')
    if not write then return false, 'writefile unavailable' end
    local clean = {}
    for key in pairs(defaults) do clean[key] = config[key] end
    local ok, err = pcall(function() write(SAVE_FILE, HttpService:JSONEncode(clean)) end)
    return ok, ok and 'Settings saved' or tostring(err)
end
-- Loading is non-destructive and only accepts recognized settings keys.
loadSettings()
stage('Engine state initialized')

local app = {
    running = true, cfg = config, connections = {}, charConnections = {}, targetConnections = {},
    uiConnections = {}, uiTweens = {}, bindings = {}, signals = 0, attempts = 0,
    dispatches = 0, blocked = 0, feints = 0, errors = 0, retryCount = 0,
    lastAction = 'Awaiting combat signal', lastError = 'None', lastBlock = 'None',
    logs = {}, character = nil, target = nil, feintActive = false,
    feintGuardUntil = 0, pending = nil, pendingRetry = nil,
    serial = 0, lastDashAt = -math.huge, signalValue = nil,
    signalActive = false, highlight = nil, highlightTarget = nil,
    lastTargetRefresh = 0, repaint = nil, gui = nil, currentTab = 'Home',
    minimized = false, unloading = false, saveToken = 0,
}
env.KVK_UBG = app

local function now() return os.clock() end
local function connect(sig, fn, bucket)
    local c = sig:Connect(fn)
    local list = bucket or app.connections
    list[#list + 1] = c
    return c
end
local function clearConnections(bucket)
    for i = #bucket, 1, -1 do
        local c = bucket[i]
        bucket[i] = nil
        pcall(function() c:Disconnect() end)
    end
end
local function record(kind, msg)
    if not app.running then return end
    local entry = string.format('[%s] %.2f  %s', kind, now(), tostring(msg))
    app.logs[#app.logs + 1] = entry
    if #app.logs > LOG_LIMIT then table.remove(app.logs, 1) end
end
local function cancelPending(reason)
    if app.pending or app.pendingRetry then
        app.serial = app.serial + 1
        app.pending, app.pendingRetry = nil, nil
        if reason then
            app.lastAction = reason
            record('CANCEL', reason)
        end
    end
end
local function skip(reason)
    app.blocked = app.blocked + 1
    app.lastBlock = reason
    app.lastAction = reason
    record('SKIP', reason)
end
local function activeSignal(value)
    return value ~= nil and value ~= false
end
local function getOccupied()
    local states = workspace:FindFirstChild('States')
    local state = states and states:FindFirstChild(localPlayer.Name)
    return state and state:FindFirstChild('Occupied')
end
local function getTarget(occupied)
    local lock = occupied and occupied:FindFirstChild('LockedOn')
    if not lock or not lock:IsA('ObjectValue') then return nil end
    local model = lock.Value
    return model and model:IsA('Model') and model.Parent and model or nil
end
local function getRoot(model)
    local part = model and model:FindFirstChild('HumanoidRootPart')
    return part and part:IsA('BasePart') and part or nil
end
local function getDistance(character, target)
    local a, b = getRoot(character), getRoot(target)
    if not a or not b then return nil end
    return (a.Position - b.Position).Magnitude
end
local function getAlive(character)
    local hum = character and character:FindFirstChildOfClass('Humanoid')
    if hum and hum.Health <= 0 then return false end
    return character ~= nil and character.Parent ~= nil
end
local function isDashing(occupied)
    local flag = occupied and occupied:FindFirstChild('Dashing')
    return flag and flag:IsA('BoolValue') and flag.Value or false
end
local function getStamina(character, occupied)
    -- Check only fields that actually exist; no inferred game-specific offsets.
    for _, obj in ipairs({character, occupied}) do
        if obj then
            local attr = obj:GetAttribute('Stamina')
            if type(attr) == 'number' then return attr end
            local field = obj:FindFirstChild('Stamina')
            if field and (field:IsA('NumberValue') or field:IsA('IntValue')) then
                return field.Value
            end
        end
    end
    return nil
end
local function isFeinting(target)
    return target ~= nil and (target:GetAttribute('IsFeinting') == true
        or target:GetAttribute('LocalIsFeinting') == true) or false
end
local function getDashEvent()
    local events = ReplicatedStorage:FindFirstChild('Events')
    local dash = events and events:FindFirstChild('ForceDash')
    return dash and dash:IsA('BindableEvent') and dash or nil
end

local function clearTargetWatch()
    clearConnections(app.targetConnections)
    app.target = nil
    app.feintActive = false
    app.feintGuardUntil = 0
end
local function invalidateForFeint(text)
    app.feintGuardUntil = math.max(app.feintGuardUntil, now() + 0.06)
    if app.pending or app.pendingRetry then
        app.feints = app.feints + 1
        cancelPending(text or 'Feint interrupted a pending dodge')
    end
end
local function watchTarget(target)
    if app.target == target then return end
    cancelPending('Lock-on changed')
    clearTargetWatch()
    app.target = target
    if not target then return end
    app.feintActive = isFeinting(target)
    if app.feintActive then
        app.feintGuardUntil = now() + 0.06
    end
    local function changed()
        if not app.running or app.target ~= target then return end
        local active = isFeinting(target)
        if active then
            app.feintActive = true
            if config.antiFeint then invalidateForFeint('Feint attribute activated') end
        elseif app.feintActive then
            app.feintActive = false
            app.feintGuardUntil = math.max(app.feintGuardUntil, now() + 0.06)
            record('FEINT', 'Feint ended; short settling window')
        end
    end
    connect(target:GetAttributeChangedSignal('IsFeinting'), changed, app.targetConnections)
    connect(target:GetAttributeChangedSignal('LocalIsFeinting'), changed, app.targetConnections)
    connect(target.AncestryChanged, function(_, parent)
        if not parent and app.target == target then watchTarget(nil) end
    end, app.targetConnections)
end
local function refreshTarget()
    local target = getTarget(getOccupied())
    if target ~= app.target then watchTarget(target) end
    return target
end
local function clearCharacter()
    clearConnections(app.charConnections)
    cancelPending()
    clearTargetWatch()
    app.character = nil
    app.signalActive = false
    app.signalValue = nil
    app.serial = app.serial + 1
end

local function dispatch(direction, isRetry)
    local dash = getDashEvent()
    if not dash then skip('ForceDash missing / incompatible'); return false end
    app.attempts = app.attempts + 1
    local ok, err = pcall(function() dash:Fire({Direction = direction}) end)
    if not ok then
        app.errors = app.errors + 1
        app.lastError = tostring(err):sub(1, 180)
        app.lastAction = 'Local dispatch error'
        record('ERROR', app.lastError)
        return false
    end
    app.dispatches = app.dispatches + 1
    app.lastDashAt = now()
    if isRetry then app.retryCount = app.retryCount + 1 end
    app.lastAction = (isRetry and 'Retry' or 'Dispatch') .. ' sent: ' .. direction
    record('FIRE', app.lastAction .. ' (server result unknown)')
    return true
end
local function validContext(character, target, direction)
    if not app.running or not config.master or not config.dodge then return false, 'Combat paused or auto-dodge OFF' end
    if not IS_UBG then return false, 'Outside UBG experience' end
    if app.character ~= character or localPlayer.Character ~= character or not getAlive(character) then
        return false, 'Character changed or inactive'
    end
    local occupied = getOccupied()
    if not target or getTarget(occupied) ~= target or app.target ~= target then
        return false, 'Missing or changed opponent'
    end
    if not getAlive(target) then return false, 'Opponent inactive' end
    if not VALID_DIRECTIONS[direction] then return false, 'Unknown dodge direction' end
    if config.antiFeint and isFeinting(target) then return false, 'Attack flagged as feint' end
    if isDashing(occupied) then return false, 'Already dashing' end
    local distance = getDistance(character, target)
    if not distance then return false, 'Character root part unavailable' end
    if distance > config.distance then return false, 'Outside dodge range' end
    local stamina = getStamina(character, occupied)
    if stamina ~= nil and stamina <= 0 then return false, 'Stamina exhausted' end
    return true, nil
end
local function processPending()
    local p = app.pending
    if not p then return end
    if not config.master or not config.dodge then cancelPending('Auto-dodge disabled'); return end
    if app.character ~= p.character or localPlayer.Character ~= p.character then
        cancelPending('Character switched'); return
    end
    local current = p.character:GetAttribute('Perfect')
    if not activeSignal(current) or current ~= p.value then
        cancelPending('Perfect signal ended'); return
    end
    if now() - p.created > math.max(0.16, config.confirmMs / 1000 + 0.085) then
        cancelPending('Signal expired'); skip('Signal expired before confirmed attack'); return
    end
    if config.antiFeint and p.target and isFeinting(p.target) then
        app.feints = app.feints + 1
        cancelPending('Feint blocked pending action'); return
    end
    if now() - p.created < config.confirmMs / 1000 then return end
    if config.antiFeint and now() < app.feintGuardUntil then return end
    local direction = p.character:GetAttribute('NeededDirection')
    if not VALID_DIRECTIONS[direction] then return end
    app.pending = nil
    local ok, reason = validContext(p.character, p.target, direction)
    if not ok then skip(reason); return end
    if now() - app.lastDashAt < config.cooldownMs / 1000 then skip('Dodge cooldown'); return end
    -- No yield after final context validation; this is a client-local dispatch only.
    if dispatch(direction, false) and config.retry then
        app.pendingRetry = {
            character = p.character, target = p.target, value = p.value,
            direction = direction, due = now() + 0.065,
            untilTime = now() + 0.12, token = app.serial,
        }
    end
end
local function processRetry()
    local r = app.pendingRetry
    if not r then return end
    if now() < r.due then return end
    app.pendingRetry = nil
    if now() > r.untilTime or r.token ~= app.serial then return end
    if not config.retry or not config.master or not config.dodge then return end
    if r.character:GetAttribute('Perfect') ~= r.value then return end
    if config.antiFeint and now() < app.feintGuardUntil then return end
    local good, reason = validContext(r.character, r.target, r.direction)
    if not good then skip('Retry: ' .. reason); return end
    -- Explicitly an optional second local dispatch, NOT confirmed by the server.
    dispatch(r.direction, true)
end
local function observeCharacter(character)
    clearCharacter()
    if not character then return end
    app.character = character
    app.signalValue = character:GetAttribute('Perfect')
    app.signalActive = activeSignal(app.signalValue)
    watchTarget(getTarget(getOccupied()))
    connect(character:GetAttributeChangedSignal('Perfect'), function()
        if not app.running or app.character ~= character then return end
        local value = character:GetAttribute('Perfect')
        local active = activeSignal(value)
        if not active then
            app.signalValue = value
            app.signalActive = false
            cancelPending('Perfect signal cleared')
            return
        end
        if app.signalActive and app.signalValue == value then return end
        app.signalActive = true
        app.signalValue = value
        app.signals = app.signals + 1
        cancelPending('New attack signal')
        local target = refreshTarget()
        if not target then skip('No locked opponent at signal'); return end
        if config.antiFeint and isFeinting(target) then
            app.feints = app.feints + 1
            skip('Feint already active')
            return
        end
        app.pending = {character = character, target = target, value = value,
            created = now(), token = app.serial}
        processPending()
    end, app.charConnections)
    connect(character:GetAttributeChangedSignal('NeededDirection'), function()
        if app.character == character then processPending() end
    end, app.charConnections)
    connect(character.AncestryChanged, function(_, parent)
        if not parent and app.character == character then clearCharacter() end
    end, app.charConnections)
end

local function clearHighlight()
    if app.highlight then pcall(function() app.highlight:Destroy() end) end
    app.highlight = nil
    app.highlightTarget = nil
end
local function desiredFill()
    if config.espColor == 'Cyan' then return COLORS.cyan end
    if config.espColor == 'Purple' then return COLORS.purple end
    return COLORS.red
end
local function updateHighlight()
    local target = (config.esp and app.target and getAlive(app.target)) and app.target or nil
    if not target then clearHighlight(); return end
    if target ~= app.highlightTarget or not app.highlight or not app.highlight.Parent then
        clearHighlight()
        local ok, highlight = pcall(function()
            local h = Instance.new('Highlight')
            h.Name = 'KVK_UBG_Target'
            h.Adornee = target
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = target
            return h
        end)
        if not ok then record('ERROR', 'Highlight creation failed'); return end
        app.highlight, app.highlightTarget = highlight, target
    end
    app.highlight.FillColor = desiredFill()
    app.highlight.OutlineColor = Color3.fromRGB(244, 248, 255)
    app.highlight.FillTransparency = config.espOpacity / 100
    app.highlight.OutlineTransparency = 0.12
end

-- Full unload is idempotent, also compatible with the previous V2.x interface.
function app:Destroy()
    if self.unloading then return end
    self.unloading, self.running = true, false
    self.serial = self.serial + 1
    self.saveToken = self.saveToken + 1
    self.pending, self.pendingRetry = nil, nil
    clearConnections(self.charConnections)
    clearConnections(self.targetConnections)
    clearConnections(self.uiConnections)
    clearConnections(self.connections)
    for obj, tw in pairs(self.uiTweens) do
        pcall(function() tw:Cancel() end)
        self.uiTweens[obj] = nil
    end
    clearHighlight()
    if self.gui then pcall(function() self.gui:Destroy() end) end
    self.gui = nil
    if env.KVK_UBG == self then env.KVK_UBG = nil end
end

local function scheduleSave()
    app.saveToken = app.saveToken + 1
    local token = app.saveToken
    task.delay(0.65, function()
        if not app.running or not config.autosave or token ~= app.saveToken then return end
        local success, message = saveSettings()
        if not success then record('WARN', message) end
    end)
end
local function setSetting(key, value)
    local clean = validate(key, value)
    if clean == nil or config[key] == clean then return end
    config[key] = clean
    if key == 'master' or key == 'dodge' or key == 'antiFeint' or key == 'retry' then
        cancelPending('Combat setting changed')
    end
    if key == 'esp' and not clean then clearHighlight() end
    if key == 'autosave' then
        -- Persist both ON and OFF; otherwise the next launch may restore ON.
        local success, message = saveSettings()
        record(success and 'SAVE' or 'WARN', message)
    elseif config.autosave then
        scheduleSave()
    end
    if app.repaint then app.repaint() end
end
local function resetSettings()
    cancelPending('Settings reset')
    app.saveToken = app.saveToken + 1
    for key, val in pairs(defaults) do config[key] = val end
    clearHighlight()
    record('SET', 'Restored default settings')
    if app.repaint then app.repaint() end
end

stage('Finding PlayerGui')
local playerGui = localPlayer:WaitForChild('PlayerGui', 10)
if not playerGui then
    app:Destroy()
    error('[K]vk V3.2: PlayerGui unavailable')
end
for _, name in ipairs({'KVK_UBG_V3', 'KVK_UBG_V22', 'KVK_UBG_Menu'}) do
    local old = playerGui:FindFirstChild(name)
    if old then pcall(function() old:Destroy() end) end
end

local opacitySurfaces = {}
local function markSurface(object)
    opacitySurfaces[#opacitySurfaces + 1] = object
    return object
end
local function round(parent, radius)
    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0, radius or 11)
    corner.Parent = parent
    return corner
end
local function stroke(parent, color, thickness)
    local s = Instance.new('UIStroke')
    s.Color = color or COLORS.stroke
    s.Thickness = thickness or 1
    s.Transparency = 0.30
    s.Parent = parent
    return s
end
local function make(class, props, parent)
    local object = Instance.new(class)
    for k, v in pairs(props or {}) do object[k] = v end
    object.Parent = parent
    return object
end
local function textLabel(parent, value, size, color, bold)
    return make('TextLabel', {
        Text = tostring(value), BackgroundTransparency = 1,
        TextColor3 = color or COLORS.text, TextSize = size or 13,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end
local function tween(obj, data, duration)
    local old = app.uiTweens[obj]
    if old then pcall(function() old:Cancel() end) end
    if not config.animations then
        for k, v in pairs(data) do obj[k] = v end
        app.uiTweens[obj] = nil
        return
    end
    local t = TweenService:Create(obj,
        TweenInfo.new(duration or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), data)
    app.uiTweens[obj] = t
    t:Play()
end

stage('Creating ScreenGui')
local gui = make('ScreenGui', {
    Name = 'KVK_UBG_V3', ResetOnSpawn = false,
    DisplayOrder = 900, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = false,
}, playerGui)
app.gui = gui

local panel = make('Frame', {
    Name = 'Hub', BackgroundColor3 = COLORS.bg,
    BorderSizePixel = 0, ClipsDescendants = true,
    Size = UDim2.fromOffset(346, 462),
    Position = UDim2.fromOffset(14, 52),
}, gui)
round(panel, 16)
markSurface(panel)
stroke(panel, COLORS.stroke, 1.2)
local panelScale = make('UIScale', {Scale = 1}, panel)
local header = make('Frame', {
    Name = 'DragHandle', Active = true, BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 67), BackgroundColor3 = COLORS.panel,
}, panel)
markSurface(header)
local brandLine = make('Frame', {
    BorderSizePixel = 0, BackgroundColor3 = COLORS.cyan,
    Position = UDim2.fromOffset(14, 18), Size = UDim2.fromOffset(3, 32),
}, header)
round(brandLine, 3)
local headline = textLabel(header, '[K]vk  /  UBG', 18, COLORS.text, true)
headline.Position = UDim2.fromOffset(29, 9)
headline.Size = UDim2.new(1, -145, 0, 28)
local subtitle = textLabel(header, 'PREMIUM COMBAT HUB  ·  V3.2', 9, COLORS.muted, true)
subtitle.Position = UDim2.fromOffset(29, 35)
subtitle.Size = UDim2.new(1, -145, 0, 18)
local function iconButton(parent, symbol, xOffset)
    local b = make('TextButton', {
        Size = UDim2.fromOffset(52, 52), Position = UDim2.new(1, xOffset, 0, 8),
        BackgroundColor3 = COLORS.surface, Text = symbol, TextColor3 = COLORS.text,
        TextSize = 18, Font = Enum.Font.GothamBold, AutoButtonColor = false,
        BorderSizePixel = 0,
    }, parent)
    round(b, 12)
    return b
end
local minimize = iconButton(header, '−', -114)
local close = iconButton(header, '×', -57)
close.TextColor3 = COLORS.red

local tabs = make('Frame', {
    BackgroundTransparency = 1, Size = UDim2.new(1, -22, 0, 60),
    Position = UDim2.fromOffset(11, 73),
}, panel)
local tabLayout = make('UIListLayout', {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
}, tabs)
local pages = {}
local tabButtons = {}
local tabOrder = {'Home', 'Combat', 'Visuals', 'Settings'}
local icons = {Home = '⌂', Combat = '⚔', Visuals = '◉', Settings = '⚙'}
for _, name in ipairs(tabOrder) do
    local b = make('TextButton', {
        Name = name, Size = UDim2.new(0.25, -4, 1, -4),
        Text = icons[name] .. '  ' .. name,
        Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = COLORS.muted, BorderSizePixel = 0,
        BackgroundColor3 = COLORS.panel, AutoButtonColor = false,
    }, tabs)
    round(b, 10)
    markSurface(b)
    tabButtons[name] = b
end
local area = make('Frame', {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(11, 140),
    Size = UDim2.new(1, -22, 1, -178), ClipsDescendants = true,
}, panel)
local footer = textLabel(panel, '●  MONITOR READY', 10, COLORS.green, true)
footer.Position = UDim2.new(0, 16, 1, -34)
footer.Size = UDim2.new(1, -32, 0, 26)

for _, name in ipairs({'Home', 'Combat', 'Visuals', 'Settings', 'Debug'}) do
    local scroller = make('ScrollingFrame', {
        Name = name, Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = COLORS.stroke,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = name == 'Home',
    }, area)
    make('UIPadding', {
        PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 5),
    }, scroller)
    make('UIListLayout', {Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder}, scroller)
    pages[name] = scroller
end
local orderCount = {}
local function nextOrder(parent)
    orderCount[parent] = (orderCount[parent] or 0) + 1
    return orderCount[parent]
end
local function card(parent, height)
    local c = make('Frame', {
        LayoutOrder = nextOrder(parent), BackgroundColor3 = COLORS.surface,
        BorderSizePixel = 0, Size = UDim2.new(1, -4, 0, height),
    }, parent)
    round(c, 12)
    markSurface(c)
    stroke(c, COLORS.stroke, 0.75)
    return c
end
local function info(parent, caption, initial)
    local c = card(parent, 54)
    local t = textLabel(c, caption, 10, COLORS.muted, true)
    t.Position = UDim2.fromOffset(13, 5)
    t.Size = UDim2.new(1, -24, 0, 20)
    local v = textLabel(c, initial, 13, COLORS.text, true)
    v.Position = UDim2.fromOffset(13, 25)
    v.Size = UDim2.new(1, -24, 0, 22)
    return v
end
local function section(parent, caption, note)
    local c = card(parent, note and 66 or 45)
    c.BackgroundColor3 = COLORS.panel
    local t = textLabel(c, caption, 14, COLORS.text, true)
    t.Position = UDim2.fromOffset(14, 7)
    t.Size = UDim2.new(1, -28, 0, 25)
    if note then
        local n = textLabel(c, note, 10, COLORS.muted)
        n.Position = UDim2.fromOffset(14, 33)
        n.Size = UDim2.new(1, -28, 0, 22)
    end
    return c
end
local toggles = {}
local function switch(parent, title, detail, key)
    local c = card(parent, 67)
    local label = textLabel(c, title, 13, COLORS.text, true)
    label.Position = UDim2.fromOffset(14, 7)
    label.Size = UDim2.new(1, -96, 0, 27)
    local sub = textLabel(c, detail, 10, COLORS.muted)
    sub.Position = UDim2.fromOffset(14, 33)
    sub.Size = UDim2.new(1, -96, 0, 22)
    local hit = make('TextButton', {
        Size = UDim2.fromOffset(66, 56),
        Position = UDim2.new(1, -76, 0, 6),
        BackgroundTransparency = 1, Text = '', AutoButtonColor = false,
    }, c)
    local track = make('Frame', {
        BackgroundColor3 = COLORS.off, BorderSizePixel = 0,
        Size = UDim2.fromOffset(51, 29), Position = UDim2.fromOffset(8, 13),
    }, hit)
    round(track, 15)
    local dot = make('Frame', {
        BackgroundColor3 = COLORS.text, BorderSizePixel = 0,
        Size = UDim2.fromOffset(23, 23), Position = UDim2.fromOffset(3, 3),
    }, track)
    round(dot, 12)
    toggles[#toggles + 1] = {key = key, track = track, dot = dot}
    connect(hit.Activated, function() setSetting(key, not config[key]) end, app.uiConnections)
    return c
end
local sliders = {}
local function slider(parent, title, key, minValue, maxValue, step, suffix, description)
    local c = card(parent, description and 144 or 118)
    local label = textLabel(c, title, 13, COLORS.text, true)
    label.Position = UDim2.fromOffset(14, 7)
    label.Size = UDim2.new(1, -116, 0, 26)
    local valueLabel = textLabel(c, '', 12, accent(), true)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Position = UDim2.new(1, -116, 0, 7)
    valueLabel.Size = UDim2.fromOffset(101, 26)
    local minus = make('TextButton', {
        Text = '−', Font = Enum.Font.GothamBold, TextSize = 20,
        TextColor3 = COLORS.text, BackgroundColor3 = COLORS.elevated,
        Position = UDim2.fromOffset(12, 43), Size = UDim2.fromOffset(53, 53),
        BorderSizePixel = 0, AutoButtonColor = false,
    }, c)
    round(minus, 10)
    local plus = make('TextButton', {
        Text = '+', Font = Enum.Font.GothamBold, TextSize = 20,
        TextColor3 = COLORS.text, BackgroundColor3 = COLORS.elevated,
        Position = UDim2.new(1, -65, 0, 43), Size = UDim2.fromOffset(53, 53),
        BorderSizePixel = 0, AutoButtonColor = false,
    }, c)
    round(plus, 10)
    local hit = make('Frame', {
        BackgroundTransparency = 1, Active = true,
        Position = UDim2.fromOffset(68, 43),
        Size = UDim2.new(1, -136, 0, 53),
    }, c)
    local track = make('Frame', {
        Position = UDim2.new(0, 0, 0.5, -3), Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = COLORS.off, BorderSizePixel = 0,
    }, hit)
    round(track, 3)
    local fill = make('Frame', {
        Size = UDim2.new(0.5, 0, 1, 0),
        BackgroundColor3 = accent(), BorderSizePixel = 0,
    }, track)
    round(fill, 3)
    local knob = make('Frame', {
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.new(0.5, -9, 0.5, -9),
        BackgroundColor3 = COLORS.text, BorderSizePixel = 0,
    }, track)
    round(knob, 9)
    sliders[#sliders + 1] = {key = key, text = valueLabel, fill = fill,
        knob = knob, min = minValue, max = maxValue, suffix = suffix}
    local function fromInput(input)
        local span = math.max(1, hit.AbsoluteSize.X)
        local fraction = math.clamp((input.Position.X - hit.AbsolutePosition.X) / span, 0, 1)
        local raw = minValue + (maxValue - minValue) * fraction
        local stepped = minValue + math.floor((raw - minValue) / step + 0.5) * step
        setSetting(key, stepped)
    end
    local activeTouch = nil
    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or
            input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeTouch = input
            fromInput(input)
        end
    end, app.uiConnections)
    connect(UserInputService.InputChanged, function(input)
        if not activeTouch then return end
        if input == activeTouch or (activeTouch.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement) then
            fromInput(input)
        end
    end, app.uiConnections)
    connect(UserInputService.InputEnded, function(input)
        if activeTouch and (input == activeTouch or
            (activeTouch.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseButton1)) then
            activeTouch = nil
        end
    end, app.uiConnections)
    connect(minus.Activated, function() setSetting(key, config[key] - step) end, app.uiConnections)
    connect(plus.Activated, function() setSetting(key, config[key] + step) end, app.uiConnections)
    if description then
        local note = textLabel(c, description, 10, COLORS.muted)
        note.Position = UDim2.fromOffset(14, 104)
        note.Size = UDim2.new(1, -28, 0, 24)
    end
    return c
end
local function actionButton(parent, label, callback, caution)
    local b = make('TextButton', {
        LayoutOrder = nextOrder(parent), Text = label,
        Size = UDim2.new(1, -4, 0, 53), BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = caution and COLORS.red or COLORS.text,
        BackgroundColor3 = caution and Color3.fromRGB(56, 31, 43) or COLORS.elevated,
        AutoButtonColor = false,
    }, parent)
    round(b, 12)
    markSurface(b)
    stroke(b, COLORS.stroke, 0.7)
    connect(b.Activated, callback, app.uiConnections)
    return b
end

stage('Creating tabs, sliders and controls')
-- HOME
section(pages.Home, 'Dashboard', 'Live local signals · no fabricated success rate')
local homeStatus = info(pages.Home, 'ENGINE', 'Active')
local homeGame = info(pages.Home, 'GAME / PLACE ID', 'Checking...')
local homeTarget = info(pages.Home, 'LOCKED OPPONENT', 'None')
local homeFeint = info(pages.Home, 'FEINT MONITOR', 'Waiting')
local homeStats = info(pages.Home, 'DISPATCHES / ATTEMPTS', '0 / 0')
switch(pages.Home, 'Combat assistance', 'Master switch — pauses all dispatches', 'master')
switch(pages.Home, 'Quick auto-dodge', 'Mirror of the Combat tab toggle', 'dodge')
actionButton(pages.Home, 'EMERGENCY PAUSE', function()
    setSetting('master', false)
    cancelPending('Emergency pause')
    record('STOP', 'Combat dispatched disabled')
end, true)

-- COMBAT
section(pages.Combat, 'Combat engine', 'Conservative signal confirmation by default')
switch(pages.Combat, 'Enable combat engine', 'Global emergency pause and resume', 'master')
switch(pages.Combat, 'Auto perfect-dodge attempt', 'Dispatch only on exposed Perfect signal', 'dodge')
switch(pages.Combat, 'Anti-feint guard', 'Watch target feint transitions', 'antiFeint')
switch(pages.Combat, 'Optional retry (experimental)', 'One extra local dash dispatch; OFF by default', 'retry')
slider(pages.Combat, 'Opponent range', 'distance', 7, 22, 1, ' studs')
slider(pages.Combat, 'Confirmation wait', 'confirmMs', 0, 90, 5, ' ms', 'Longer wait can prevent feints but miss fast punches')
slider(pages.Combat, 'Dodge cooldown', 'cooldownMs', 150, 800, 25, ' ms')
local combatBlock = info(pages.Combat, 'LAST SUPPRESSION REASON', 'None')
actionButton(pages.Combat, 'PAUSE ALL COMBAT ACTIONS', function()
    setSetting('master', false)
    cancelPending('Combat paused')
end, true)

-- VISUALS
section(pages.Visuals, 'Visual controls', 'Highlight only the current locked opponent')
switch(pages.Visuals, 'Target highlight', 'Requires a replicated target Model', 'esp')
switch(pages.Visuals, 'Compact status HUD', 'Small overlay that remains when minimized', 'smallHud')
slider(pages.Visuals, 'Highlight transparency', 'espOpacity', 10, 95, 5, '%')
local colorLabel = info(pages.Visuals, 'TARGET COLOR', config.espColor)
actionButton(pages.Visuals, 'CYCLE TARGET COLOR  ↻', function()
    local nextColors = {Coral = 'Cyan', Cyan = 'Purple', Purple = 'Coral'}
    setSetting('espColor', nextColors[config.espColor] or 'Coral')
end)

-- SETTINGS
section(pages.Settings, 'Preferences', 'Changes take effect without re-executing')
slider(pages.Settings, 'Menu UI scale', 'scale', 85, 110, 5, '%')
slider(pages.Settings, 'Menu opacity', 'opacity', 75, 100, 5, '%')
switch(pages.Settings, 'Menu animations', 'Cancellable interface tweens', 'animations')
switch(pages.Settings, 'Auto-save settings', 'Requires executor writefile support', 'autosave')
local themeLabel = info(pages.Settings, 'ACCENT COLOR', config.theme)
actionButton(pages.Settings, 'CYCLE CYAN / PURPLE  ↻', function()
    setSetting('theme', config.theme == 'Cyan' and 'Purple' or 'Cyan')
end)
actionButton(pages.Settings, 'SAVE CONFIGURATION', function()
    local ok, message = saveSettings()
    app.lastAction = message
    record(ok and 'SAVE' or 'WARN', message)
end)
actionButton(pages.Settings, 'LOAD CONFIGURATION', function()
    local ok, message = loadSettings()
    cancelPending('Settings reloaded')
    if app.repaint then app.repaint() end
    app.lastAction = message
    record(ok and 'LOAD' or 'WARN', message)
end)
actionButton(pages.Settings, 'OPEN DEBUG CONSOLE  ›', function()
    if app.showTab then app.showTab('Debug') end
end)
actionButton(pages.Settings, 'RESET TO DEFAULTS', resetSettings)
actionButton(pages.Settings, 'FULL UNLOAD / CLOSE', function() app:Destroy() end, true)

-- DEBUG SECTION
section(pages.Debug, 'Diagnostics', 'Client-side telemetry · server result unavailable')
local diagSignal = info(pages.Debug, 'PERFECT / DIRECTION', 'nil / nil')
local diagTarget = info(pages.Debug, 'OPPONENT / DISTANCE', 'None')
local diagFeint = info(pages.Debug, 'FEINT FLAGS', 'nil / nil')
local diagDash = info(pages.Debug, 'FORCEDASH EVENT', 'Checking')
local diagStamina = info(pages.Debug, 'STAMINA FIELD', 'unknown / unchecked')
local diagStats = info(pages.Debug, 'SIGNALS / ATTEMPTS / FIRES / ERRORS', '0 / 0 / 0 / 0')
local diagLast = info(pages.Debug, 'LAST ACTION / BLOCK REASON', 'None')
local diagError = info(pages.Debug, 'LAST LOCAL ERROR', 'None')
local logCard = card(pages.Debug, 177)
local logTitle = textLabel(logCard, 'RECENT EVENTS (max 45)', 11, COLORS.muted, true)
logTitle.Size = UDim2.new(1, -20, 0, 26)
logTitle.Position = UDim2.fromOffset(12, 7)
local logScroll = make('ScrollingFrame', {
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
    Position = UDim2.fromOffset(10, 33), Size = UDim2.new(1, -20, 1, -43),
    CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, logCard)
local logText = textLabel(logScroll, 'No events yet', 10, COLORS.muted)
logText.TextWrapped = true
logText.TextTruncate = Enum.TextTruncate.None
logText.TextYAlignment = Enum.TextYAlignment.Top
logText.Size = UDim2.new(1, -8, 0, 30)
actionButton(pages.Debug, 'COPY DIAGNOSTIC LOG', function()
    local copy = safeGetFileApi('setclipboard') or safeGetFileApi('toclipboard')
    if not copy then record('WARN', 'Clipboard API unavailable'); return end
    local summary = table.concat(app.logs, '\n')
    local ok, err = pcall(copy, summary)
    record(ok and 'COPY' or 'ERROR', ok and 'Diagnostic log copied' or tostring(err))
end)
actionButton(pages.Debug, 'CLEAR LOG', function()
    app.logs = {}
    record('INFO', 'Diagnostic history cleared')
end)
actionButton(pages.Debug, '‹ BACK TO SETTINGS', function()
    if app.showTab then app.showTab('Settings') end
end)

local mini = make('TextButton', {
    Name = 'MiniHub', Visible = false, Text = '[K]vk',
    TextColor3 = COLORS.text, Font = Enum.Font.GothamBold,
    TextSize = 16, BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0, AutoButtonColor = false,
    Size = UDim2.fromOffset(75, 54), Position = panel.Position,
}, gui)
round(mini, 14)
markSurface(mini)
stroke(mini, COLORS.cyan, 1)

local hud = make('Frame', {
    Name = 'CompactHUD', BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0, Visible = true,
    Size = UDim2.fromOffset(208, 46), Position = UDim2.new(0, 12, 1, -55),
}, gui)
round(hud, 10)
markSurface(hud)
local hudText = textLabel(hud, '[K]vk · awaiting opponent', 11, COLORS.text, true)
hudText.Position = UDim2.fromOffset(11, 4)
hudText.Size = UDim2.new(1, -22, 1, -8)

stage('Wiring UI input and viewport')
local function viewport()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(750, 500)
end
local function applyGeometry()
    if not app.running then return end
    local v = viewport()
    local desired = config.scale / 100
    local scale = math.min(desired, math.max(0.85, (v.X - 18) / 346))
    -- Scroll internally instead of scaling the controls too small in landscape.
    local baseHeight = math.max(245, math.min(510, (v.Y - 20) / scale))
    panelScale.Scale = scale
    panel.Size = UDim2.fromOffset(346, baseHeight)
    local p = panel.Position
    local px = math.clamp(p.X.Offset, 0, math.max(0, v.X - 346 * scale))
    local py = math.clamp(p.Y.Offset, 0, math.max(0, v.Y - baseHeight * scale))
    panel.Position = UDim2.fromOffset(px, py)
    local fade = 1 - config.opacity / 100
    for _, surface in ipairs(opacitySurfaces) do
        if surface.Parent then surface.BackgroundTransparency = fade end
    end
    mini.BackgroundColor3 = COLORS.panel
end
local function moveFrame(frame, x, y)
    local v = viewport()
    local s = frame == panel and panelScale.Scale or 1
    local w = frame.Size.X.Offset * s
    local h = frame.Size.Y.Offset * s
    frame.Position = UDim2.fromOffset(
        math.clamp(x, 0, math.max(0, v.X - w)),
        math.clamp(y, 0, math.max(0, v.Y - h)))
end
local function enableDrag(handle, frame)
    handle.Active = true
    local inputStart, origin, frameOrigin
    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch or
            input.UserInputType == Enum.UserInputType.MouseButton1 then
            inputStart, origin = input, input.Position
            frameOrigin = frame.AbsolutePosition
        end
    end, app.uiConnections)
    connect(UserInputService.InputChanged, function(input)
        if not inputStart then return end
        if input == inputStart or
            (inputStart.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = input.Position - origin
            moveFrame(frame, frameOrigin.X + d.X, frameOrigin.Y + d.Y)
        end
    end, app.uiConnections)
    connect(UserInputService.InputEnded, function(input)
        if inputStart and (input == inputStart or
            (inputStart.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseButton1)) then
            inputStart = nil
        end
    end, app.uiConnections)
end
enableDrag(header, panel)
-- Mini widget: dedicated button remains accessible even after minimizing.
connect(minimize.Activated, function()
    app.minimized = true
    mini.Position = panel.Position
    panel.Visible = false
    mini.Visible = true
    record('UI', 'Minimized')
end, app.uiConnections)
connect(mini.Activated, function()
    app.minimized = false
    panel.Position = mini.Position
    mini.Visible = false
    panel.Visible = true
    applyGeometry()
    record('UI', 'Restored')
end, app.uiConnections)
connect(close.Activated, function() app:Destroy() end, app.uiConnections)

local function showTab(name)
    if not pages[name] then return end
    app.currentTab = name
    if app.lastPaintedTab == name and app.lastPaintedTheme == config.theme then return end
    app.lastPaintedTab, app.lastPaintedTheme = name, config.theme
    for tab, page in pairs(pages) do page.Visible = (tab == name) end
    for tab, button in pairs(tabButtons) do
        local selected = tab == name or (name == 'Debug' and tab == 'Settings')
        tween(button, {BackgroundColor3 = selected and COLORS.elevated or COLORS.panel,
            TextColor3 = selected and accent() or COLORS.muted}, 0.14)
    end
end
app.showTab = showTab
for _, name in ipairs(tabOrder) do
    connect(tabButtons[name].Activated, function() showTab(name) end, app.uiConnections)
end

local function drawSettings()
    for _, t in ipairs(toggles) do
        local enabled = config[t.key]
        if t.lastState ~= enabled or t.lastTheme ~= config.theme then
            tween(t.track, {BackgroundColor3 = enabled and accent() or COLORS.off}, 0.14)
            tween(t.dot, {Position = UDim2.fromOffset(enabled and 25 or 3, 3)}, 0.14)
            t.lastState, t.lastTheme = enabled, config.theme
        end
    end
    for _, s in ipairs(sliders) do
        local value = config[s.key]
        local fraction = math.clamp((value - s.min) / (s.max - s.min), 0, 1)
        s.text.Text = tostring(value) .. s.suffix
        s.text.TextColor3 = accent()
        s.fill.BackgroundColor3 = accent()
        s.fill.Size = UDim2.new(fraction, 0, 1, 0)
        s.knob.Position = UDim2.new(fraction, -9, 0.5, -9)
    end
    brandLine.BackgroundColor3 = accent()
    colorLabel.Text = config.espColor
    themeLabel.Text = config.theme
    hud.Visible = config.smallHud
    showTab(app.currentTab)
    applyGeometry()
end
app.repaint = drawSettings

local function refreshStatus()
    local target = refreshTarget()
    updateHighlight()
    local ch = app.character
    local distance = getDistance(ch, target)
    local distanceText = distance and string.format('%.1f studs', distance) or 'n/a'
    local blocked = (not config.master or not config.dodge)
    homeGame.Text = (IS_UBG and 'UBG' or 'NOT UBG') .. '  ·  ' .. tostring(game.PlaceId)
    homeGame.TextColor3 = IS_UBG and COLORS.green or COLORS.red
    homeStatus.Text = (not IS_UBG and 'INACTIVE · wrong Roblox experience')
        or (blocked and 'PAUSED · dispatch disabled' or 'ACTIVE · watching signal transitions')
    homeStatus.TextColor3 = (not IS_UBG and COLORS.red) or (blocked and COLORS.amber or COLORS.green)
    homeTarget.Text = target and (target.Name .. ' · ' .. distanceText) or 'None · waiting for lock-on'
    local feintText = target and (isFeinting(target) and 'ACTIVE'
        or (now() < app.feintGuardUntil and 'SETTLING' or 'CLEAR')) or 'No target'
    homeFeint.Text = config.antiFeint and feintText or 'Guard disabled'
    homeStats.Text = tostring(app.dispatches) .. ' / ' .. tostring(app.attempts)
    combatBlock.Text = app.lastBlock
    footer.Text = (not IS_UBG and '●  WRONG GAME  ·  UI DIAGNOSTICS ONLY')
        or (blocked and '●  COMBAT PAUSED  ·  LOCAL UI ACTIVE'
        or '●  ACTIVE  ·  SERVER RESULTS UNVERIFIED')
    footer.TextColor3 = (not IS_UBG and COLORS.red) or (blocked and COLORS.amber or COLORS.green)
    hudText.Text = '[K]vk · ' .. (blocked and 'PAUSED' or (target and target.Name or 'NO TARGET'))
    local perf = ch and ch:GetAttribute('Perfect')
    local direction = ch and ch:GetAttribute('NeededDirection')
    diagSignal.Text = tostring(perf) .. ' / ' .. tostring(direction)
    diagTarget.Text = target and (target.Name .. ' · ' .. distanceText) or 'None'
    diagFeint.Text = target and (tostring(target:GetAttribute('IsFeinting')) .. ' / '
        .. tostring(target:GetAttribute('LocalIsFeinting'))) or 'No target'
    diagDash.Text = getDashEvent() and 'BindableEvent found · acceptance unknown' or 'Unavailable / incompatible'
    local stamina = getStamina(ch, getOccupied())
    diagStamina.Text = stamina == nil and 'Unknown (not assumed)' or tostring(stamina)
    diagStats.Text = string.format('%d / %d / %d / %d',
        app.signals, app.attempts, app.dispatches, app.errors)
    diagLast.Text = app.lastAction .. ' · ' .. app.lastBlock
    diagError.Text = app.lastError
    local start = math.max(1, #app.logs - 10)
    local lines = {}
    for i = start, #app.logs do lines[#lines + 1] = app.logs[i] end
    logText.Text = #lines == 0 and 'No events yet' or table.concat(lines, '\n')
    logText.Size = UDim2.new(1, -8, 0, math.max(30, #lines * 26))
end

stage('Attaching game listeners')
connect(localPlayer.CharacterAdded, function(character)
    observeCharacter(character)
    clearHighlight()
    record('RESPAWN', 'Character watchers rebound')
end)
connect(localPlayer.CharacterRemoving, function(character)
    if app.character == character then clearCharacter() end
    clearHighlight()
end)
observeCharacter(localPlayer.Character)

local elapsed = 0
connect(RunService.Heartbeat, function(dt)
    if not app.running then return end
    if localPlayer.Character ~= app.character then observeCharacter(localPlayer.Character) end
    processPending()
    processRetry()
    elapsed = elapsed + (type(dt) == 'number' and dt or 0)
    if elapsed >= 0.16 then
        elapsed = 0
        refreshStatus()
        local v = viewport()
        if app.lastViewportX ~= v.X or app.lastViewportY ~= v.Y then
            app.lastViewportX, app.lastViewportY = v.X, v.Y
            applyGeometry()
            moveFrame(mini, mini.Position.X.Offset, mini.Position.Y.Offset)
        end
    end
end)

stage('First UI render')
record('READY', 'V3.2 loaded; anti-feint ' .. (config.antiFeint and 'ON' or 'OFF'))
drawSettings()
refreshStatus()
print('[K]vk UBG Premium Hub V3.2 UI ready. PlaceId=' .. tostring(game.PlaceId) .. '; isUBG=' .. tostring(IS_UBG) .. '. ForceDash acceptance unverified.')


stage("Hub initialized")
end, function(err)
    if debug and type(debug.traceback) == "function" then
        return debug.traceback(tostring(err), 2)
    end
    return tostring(err)
end)

if not initialized then
    local message = "V3.2 failed at " .. currentStage .. ": " .. tostring(failure)
    warn("[K]vk] " .. message)
    if bootstrapStatus then
        bootstrapStatus.BackgroundColor3 = Color3.fromRGB(120, 36, 48)
        bootstrapStatus.Size = UDim2.fromOffset(340, 144)
        bootstrapStatus.Text = "[K]vk ERROR | " .. currentStage .. "\n" .. tostring(failure):sub(1, 320)
        bootstrapStatus.TextWrapped = true
        bootstrapStatus.TextSize = 13
    end
    -- Remove any partial hub without hiding diagnostic error UI.
    local env = _G
    if type(getgenv) == "function" then
        local ok, result = pcall(getgenv)
        if ok and type(result) == "table" then env = result end
    end
    if type(env.KVK_UBG) == "table" and type(env.KVK_UBG.Destroy) == "function" then
        pcall(function() env.KVK_UBG:Destroy() end)
    end
else
    if bootstrapStatus then
        bootstrapStatus.Text = "[K]vk V3.2 | Menu created. Close Delta to view."
        task.delay(3, function()
            if bootstrapGui and bootstrapGui.Parent then bootstrapGui:Destroy() end
        end)
    end
end
