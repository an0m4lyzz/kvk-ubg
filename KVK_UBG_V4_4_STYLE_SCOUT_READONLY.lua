-- [K]vk UBG V4.4 STYLE SCOUT -- read-only companion to V4.3
-- Purpose: inspect client-visible opponent style/mode fields + observed animation IDs.
-- Never dispatches attacks/dashes, modifies combat flags, or infers server success.
-- Run V4.3 first. Only the locked target from that engine is observed.
local Players=game:GetService("Players")
local localPlayer=Players.LocalPlayer
if not localPlayer then warn("[K]vk SCOUT: LocalPlayer missing");return end
local playerGui=localPlayer:WaitForChild("PlayerGui",6)
if not playerGui then warn("[K]vk SCOUT: PlayerGui missing");return end
local env=_G
if type(getgenv)=="function" then
    local ok,t=pcall(getgenv)
    if ok and type(t)=="table" then env=t end
end
if type(env.KVK_STYLE_SCOUT)=="table" and type(env.KVK_STYLE_SCOUT.Destroy)=="function" then
    pcall(function() env.KVK_STYLE_SCOUT:Destroy() end)
end
local old=playerGui:FindFirstChild("KVK_STYLE_SCOUT_UI")
if old then old:Destroy() end
local scout={running=true,events={},animations={},firstSeen={},observations=0,
    target=nil, style="Unexposed",mode="Unexposed",captures={},lastStatus="Awaiting locked opponent",conns={}}
env.KVK_STYLE_SCOUT=scout
local function connect(signal,fn)
    local c=signal:Connect(fn);scout.conns[#scout.conns+1]=c;return c
end
local function log(msg)
    local line=string.format("%.1fs %s",os.clock(),tostring(msg))
    scout.events[#scout.events+1]=line
    if #scout.events>32 then table.remove(scout.events,1) end
end
local function normalize(v)
    if type(v)=="string" then
        if #v>70 then return v:sub(1,70).."..." end
        return v
    end
    if type(v)=="boolean" or type(v)=="number" then return tostring(v) end
    return nil
end
local STYLE={"style","boxingstyle","fightingstyle","currentstyle","equippedstyle"}
local MODE={"mode","currentmode","stance","currentstance","form","transformation",
    "focus","monstrosity","whirlwind","flicker","drive","surgeonmode"}
local function keyClass(key)
    local k=key:lower():gsub("[_%-%s]","")
    for _,name in ipairs(STYLE) do if k==name then return "Style" end end
    for _,name in ipairs(MODE) do if k==name then return "Mode" end end
    return nil
end
local function capture(name,value,cls)
    local str=normalize(value)
    if not str or str=="" then return end
    local key=name.." = "..str
    if not scout.captures[key] then
        scout.captures[key]=true
        local count=0;for _ in pairs(scout.captures) do count=count+1 end
        if count<=45 then log("FIELD "..cls.." "..key) end
    end
    if cls=="Style" and scout.style=="Unexposed" then scout.style=str end
    if cls=="Mode" and scout.mode=="Unexposed" then scout.mode=str end
end
local function scan(source,path)
    if not source then return end
    local ok,attrs=pcall(function() return source:GetAttributes() end)
    if ok and type(attrs)=="table" then
        for key,val in pairs(attrs) do
            local cls=keyClass(key)
            if cls then capture(path.."[@"..key.."]",val,cls) end
        end
    end
    for _,child in ipairs(source:GetChildren()) do
        local cls=keyClass(child.Name)
        if cls and (child:IsA("StringValue") or child:IsA("BoolValue")
            or child:IsA("NumberValue") or child:IsA("IntValue")) then
            capture(path.."."..child.Name,child.Value,cls)
        end
    end
end
local function scanTarget(target)
    local player=Players:GetPlayerFromCharacter(target)
    scan(target,"Character")
    local occ=target:FindFirstChild("Occupied")
    scan(occ,"Character.Occupied")
    if player then
        scan(player,"Player")
        for _,folderName in ipairs({"Data","Stats","leaderstats","Profile","Values","PlayerData"}) do
            local folder=player:FindFirstChild(folderName)
            scan(folder,"Player."..folderName)
        end
    end
end
local function animationId(track)
    local ok,id=pcall(function() return track.Animation and track.Animation.AnimationId end)
    if not ok or type(id)~="string" then return nil end
    return id:match("%d+") or nil
end
local animConnection=nil
local function setTarget(target)
    if animConnection then animConnection:Disconnect();animConnection=nil end
    scout.target=target;scout.style="Unexposed";scout.mode="Unexposed"
    scout.captures={};scout.animations={}
    if not target then scout.lastStatus="No locked opponent";log("TARGET none");return end
    scout.lastStatus="Target locked"
    log("TARGET locked; scanning client-visible fields")
    local humanoid=target:FindFirstChildOfClass("Humanoid")
    local animator=humanoid and humanoid:FindFirstChildOfClass("Animator")
    if animator then
        animConnection=animator.AnimationPlayed:Connect(function(track)
            local id=animationId(track)
            if not id or not scout.running then return end
            local n=(scout.animations[id] or 0)+1
            scout.animations[id]=n
            if n==1 then log("ANIM "..id) end
        end)
    else log("Animator unavailable; animation IDs not captured") end
end
local gui=Instance.new("ScreenGui")
gui.Name="KVK_STYLE_SCOUT_UI";gui.ResetOnSpawn=false;gui.DisplayOrder=1050
gui.Parent=playerGui;scout.gui=gui
local panel=Instance.new("Frame")
panel.Size=UDim2.fromOffset(300,150)
panel.Position=UDim2.new(1,-310,0,100)
panel.BackgroundColor3=Color3.fromRGB(24,32,45)
panel.BorderSizePixel=0;panel.Parent=gui
local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,10);corner.Parent=panel
local label=Instance.new("TextLabel")
label.Size=UDim2.new(1,-16,0,100);label.Position=UDim2.fromOffset(8,8)
label.TextXAlignment=Enum.TextXAlignment.Left
label.TextYAlignment=Enum.TextYAlignment.Top
label.BackgroundTransparency=1;label.TextWrapped=true
label.TextColor3=Color3.fromRGB(242,247,255)
label.Font=Enum.Font.Gotham;label.TextSize=13
label.Text="[K]vk V4.4 STYLE SCOUT\nSearching..."
label.Parent=panel
local copy=Instance.new("TextButton")
copy.Size=UDim2.fromOffset(140,30);copy.Position=UDim2.fromOffset(8,113)
copy.Text="COPY REPORT";copy.Font=Enum.Font.GothamBold
copy.TextSize=12;copy.TextColor3=Color3.new(1,1,1)
copy.BackgroundColor3=Color3.fromRGB(23,115,145);copy.Parent=panel
local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(136,30);close.Position=UDim2.fromOffset(156,113)
close.Text="CLOSE";close.Font=Enum.Font.GothamBold
close.TextSize=12;close.TextColor3=Color3.new(1,1,1)
close.BackgroundColor3=Color3.fromRGB(88,95,108);close.Parent=panel
function scout:Report()
    local lines={
        "[K]vk UBG V4.4 STYLE SCOUT REPORT (read-only)",
        "PlaceId="..tostring(game.PlaceId),
        "Engine="..(type(env.KVK_UBG)=="table" and "detected" or "not detected"),
        "Target="..self.lastStatus,
        "Style candidate="..self.style,
        "Mode candidate="..self.mode,
        "Scans="..self.observations,
        "NOTE: Field names/values are client observations, not confirmed styles.",
        "NOTE: Animation IDs alone do not identify attacks or dodge windows.",
        "=== FIELD AND ANIMATION EVENTS ==="
    }
    for _,line in ipairs(self.events) do lines[#lines+1]=line end
    lines[#lines+1]="=== ANIMATIONS (count) ==="
    local sorted={}
    for id,count in pairs(self.animations) do sorted[#sorted+1]={id=id,n=count} end
    table.sort(sorted,function(a,b) return a.n>b.n end)
    for i=1,math.min(20,#sorted) do
        lines[#lines+1]=sorted[i].id.." x"..sorted[i].n
    end
    return table.concat(lines,"\n")
end
function scout:Destroy()
    if not self.running then return end
    self.running=false
    if animConnection then animConnection:Disconnect();animConnection=nil end
    for _,c in ipairs(self.conns) do pcall(function()c:Disconnect()end) end
    if self.gui then self.gui:Destroy() end
    if env.KVK_STYLE_SCOUT==self then env.KVK_STYLE_SCOUT=nil end
end
connect(copy.MouseButton1Click,function()
    local clip=env.setclipboard or _G.setclipboard
    if type(clip)~="function" then
        copy.Text="CLIPBOARD UNAVAILABLE"
        return
    end
    local ok=pcall(clip,scout:Report())
    copy.Text=ok and "COPIED" or "COPY FAILED"
    task.delay(2,function()if copy and copy.Parent then copy.Text="COPY REPORT" end end)
end)
connect(close.MouseButton1Click,function()scout:Destroy()end)
log("START read-only scout; no combat changes")
task.spawn(function()
    while scout.running do
        local engine=env.KVK_UBG
        local target=(type(engine)=="table" and engine.running) and engine.target or nil
        if target~=scout.target then setTarget(target) end
        if target and target.Parent then
            scout.observations=scout.observations+1
            scanTarget(target)
        end
        local n=0;for _ in pairs(scout.animations) do n=n+1 end
        if label and label.Parent then
            label.Text="[K]vk V4.4 STYLE SCOUT (read-only)\n"
                .."Style: "..scout.style.."\nMode: "..scout.mode
                .."\nScans: "..scout.observations.." | Anim IDs: "..n
                .."\nPlay normally, then COPY REPORT"
        end
        task.wait(1)
    end
end)
