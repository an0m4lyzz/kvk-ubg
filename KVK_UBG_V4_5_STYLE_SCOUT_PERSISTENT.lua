-- [K]vk UBG V4.5 STYLE SCOUT (read-only)
-- Run V4.3 first. Observes the engine's locked target only.
-- No combat input, attribute changes, remote calls, or dodge guarantees.
local Players=game:GetService("Players")
local me=Players.LocalPlayer
if not me then warn("[K]vk scout: no LocalPlayer"); return end
local pg=me:WaitForChild("PlayerGui",6)
if not pg then warn("[K]vk scout: no PlayerGui"); return end
local env=_G
if type(getgenv)=="function" then
    local ok,v=pcall(getgenv)
    if ok and type(v)=="table" then env=v end
end
if type(env.KVK_STYLE_SCOUT)=="table" and type(env.KVK_STYLE_SCOUT.Destroy)=="function" then
    pcall(function() env.KVK_STYLE_SCOUT:Destroy() end)
end
local previousUI=pg:FindFirstChild("KVK_STYLE_SCOUT_UI")
if previousUI then previousUI:Destroy() end

local scout={running=true,target=nil,style="Unexposed",mode="Unexposed",
    observations=0,targetScans=0,targetCount=0,anim={},fields={},sessions={},
    events={},connections={},status="Waiting for locked target"}
env.KVK_STYLE_SCOUT=scout
local animConn=nil
local function on(signal,fn)
    local c=signal:Connect(fn)
    scout.connections[#scout.connections+1]=c
end
local function log(msg)
    scout.events[#scout.events+1]=string.format("%.1fs %s",os.clock(),msg)
    if #scout.events>65 then table.remove(scout.events,1) end
end
local function keyType(name)
    local k=name:lower():gsub("[_%-%s]","")
    if k:find("style",1,true) then return "STYLE" end
    -- SlowMoDebounce and similar timestamps are not stance/mode indicators.
    local modeKeys = {
        mode=true, currentmode=true, equippedmode=true, stancemode=true,
        stance=true, currentstance=true, currentform=true, form=true,
        transformation=true, focus=true, focusmode=true,
        monstrosity=true, flicker=true, whirlwind=true,
        surgeonmode=true, drivemode=true
    }
    if modeKeys[k] then return "MODE" end
    return nil
end
local function accept(path,key,value)
    local kind=keyType(key)
    if not kind then return end
    local vt=type(value)
    if vt~="string" and vt~="number" and vt~="boolean" then return end
    -- Reject clock-like mode values even if the field name seems plausible.
    if kind=="MODE" and type(value)=="number" and value>100000000 then return end
    local text=tostring(value)
    if #text>55 then text=text:sub(1,55).."..." end
    local entry=kind.." "..path.."."..key.." = "..text
    if not scout.fields[entry] then
        scout.fields[entry]=true
        log("FIELD "..entry)
    end
    local lower=text:lower()
    if lower=="" or lower=="unknown" or lower=="none" or lower=="false" or lower=="0" then
        return
    end
    if kind=="STYLE" and scout.style=="Unexposed" then scout.style=text end
    if kind=="MODE" and scout.mode=="Unexposed" then scout.mode=key.."="..text end
end
local function scanObject(obj,path,allowFolders)
    if not obj then return end
    local ok,attrs=pcall(function() return obj:GetAttributes() end)
    if ok and type(attrs)=="table" then
        for key,value in pairs(attrs) do accept(path.."@",key,value) end
    end
    for i,child in ipairs(obj:GetChildren()) do
        if i>150 then break end
        if child:IsA("StringValue") or child:IsA("NumberValue")
            or child:IsA("IntValue") or child:IsA("BoolValue") then
            accept(path,child.Name,child.Value)
        elseif allowFolders and child:IsA("Folder") then
            local f=child.Name:lower()
            if f:find("style",1,true) or f:find("stat",1,true)
                or f:find("mode",1,true) or f:find("profile",1,true)
                or f:find("data",1,true) or f:find("combat",1,true) then
                scanObject(child,path.."."..child.Name,false)
            end
        end
    end
end
local function scanTarget(target)
    scanObject(target,"Character",false)
    scanObject(target:FindFirstChild("Occupied"),"Character.Occupied",true)
    local player=Players:GetPlayerFromCharacter(target)
    if player then scanObject(player,"Player",true) end
end
local function sortedAnim(tbl)
    local out={}
    for id,n in pairs(tbl) do out[#out+1]={id=id,n=n} end
    table.sort(out,function(a,b) return a.n>b.n end)
    return out
end
local function sortedFields(tbl)
    local out={}
    for x in pairs(tbl) do out[#out+1]=x end
    table.sort(out)
    return out
end
local function snapshot()
    return {index=scout.targetCount,style=scout.style,mode=scout.mode,
        scans=scout.targetScans,anims=sortedAnim(scout.anim),
        fields=sortedFields(scout.fields)}
end
local function archive()
    if not scout.target then return end
    local saved=snapshot()
    scout.sessions[#scout.sessions+1]=saved
    if #scout.sessions>4 then table.remove(scout.sessions,1) end
    log("ARCHIVED target #"..saved.index.."; uniqueAnimIDs="..#saved.anims
        .."; style="..saved.style.."; mode="..saved.mode)
end
local function animationId(track)
    local ok,id=pcall(function() return track.Animation and track.Animation.AnimationId end)
    if not ok or type(id)~="string" then return nil end
    return id:match("%d+")
end
local function setTarget(target)
    if animConn then animConn:Disconnect();animConn=nil end
    archive()
    scout.target=target
    scout.targetScans=0;scout.style="Unexposed";scout.mode="Unexposed"
    scout.fields={};scout.anim={}
    if not target then
        scout.status="No locked opponent; earlier target archived"
        log("TARGET cleared (possibly reset). Previous data retained.")
        return
    end
    scout.targetCount=scout.targetCount+1
    scout.status="Target #"..scout.targetCount.." locked"
    log("TARGET #"..scout.targetCount.." locked")
    local humanoid=target:FindFirstChildOfClass("Humanoid")
    local animator=humanoid and humanoid:FindFirstChildOfClass("Animator")
    if animator then
        animConn=animator.AnimationPlayed:Connect(function(track)
            if not scout.running then return end
            local id=animationId(track)
            if not id then return end
            local n=(scout.anim[id] or 0)+1
            scout.anim[id]=n
            if n==1 then log("ANIM "..id) end
        end)
    else log("No animator found on locked target") end
end

local gui=Instance.new("ScreenGui")
gui.Name="KVK_STYLE_SCOUT_UI";gui.ResetOnSpawn=false;gui.DisplayOrder=1050
gui.Parent=pg;scout.gui=gui
local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(310,160)
frame.Position=UDim2.new(1,-320,0,100)
frame.BackgroundColor3=Color3.fromRGB(24,32,45)
frame.BorderSizePixel=0;frame.Parent=gui
local corner=Instance.new("UICorner")
corner.CornerRadius=UDim.new(0,10);corner.Parent=frame
local label=Instance.new("TextLabel")
label.Size=UDim2.fromOffset(290,105)
label.Position=UDim2.fromOffset(10,6)
label.BackgroundTransparency=1
label.TextXAlignment=Enum.TextXAlignment.Left
label.TextYAlignment=Enum.TextYAlignment.Top
label.TextColor3=Color3.fromRGB(242,247,255)
label.TextWrapped=true;label.Font=Enum.Font.Gotham;label.TextSize=13
label.Text="V4.5 scout starting";label.Parent=frame
local copy=Instance.new("TextButton")
copy.Size=UDim2.fromOffset(140,32)
copy.Position=UDim2.fromOffset(10,120)
copy.BackgroundColor3=Color3.fromRGB(23,115,145)
copy.TextColor3=Color3.new(1,1,1)
copy.Font=Enum.Font.GothamBold;copy.TextSize=12
copy.Text="COPY REPORT";copy.Parent=frame
local close=Instance.new("TextButton")
close.Size=UDim2.fromOffset(140,32)
close.Position=UDim2.fromOffset(160,120)
close.BackgroundColor3=Color3.fromRGB(88,95,108)
close.TextColor3=Color3.new(1,1,1)
close.Font=Enum.Font.GothamBold;close.TextSize=12
close.Text="CLOSE";close.Parent=frame

function scout:Report()
    local lines={"[K]vk UBG V4.5 PERSISTENT STYLE SCOUT (read-only)",
        "PlaceId="..game.PlaceId,
        "Engine="..(type(env.KVK_UBG)=="table" and "detected" or "missing"),
        "Status="..self.status,
        "Scans="..self.observations.." Encounters="..self.targetCount,
        "NOTE: Reset does not delete archived target data.",
        "NOTE: Style/mode fields are unverified client observations.",
        "NOTE: Animation IDs alone do not prove specific attacks or perfect dodges."}
    local function append(data,kind)
        lines[#lines+1]="=== "..kind.." #"..data.index
            .." (scans="..data.scans..") ==="
        lines[#lines+1]="Style candidate="..data.style
        lines[#lines+1]="Mode candidate="..data.mode
        lines[#lines+1]="Fields:"
        if #data.fields==0 then lines[#lines+1]="(no matching fields)" end
        for i=1,math.min(25,#data.fields) do lines[#lines+1]=data.fields[i] end
        lines[#lines+1]="Animations:"
        if #data.anims==0 then lines[#lines+1]="(none)" end
        for i=1,math.min(30,#data.anims) do
            local a=data.anims[i]
            lines[#lines+1]=a.id.." x"..a.n
        end
    end
    for _,session in ipairs(self.sessions) do append(session,"ARCHIVED") end
    if self.target then append(snapshot(),"CURRENT") end
    lines[#lines+1]="=== RECENT EVENTS ==="
    for _,event in ipairs(self.events) do lines[#lines+1]=event end
    return table.concat(lines,"\n")
end
function scout:Destroy()
    if not self.running then return end
    self.running=false
    if animConn then animConn:Disconnect();animConn=nil end
    for _,c in ipairs(self.connections) do pcall(function() c:Disconnect() end) end
    if self.gui then self.gui:Destroy() end
    if env.KVK_STYLE_SCOUT==self then env.KVK_STYLE_SCOUT=nil end
end
on(copy.MouseButton1Click,function()
    local clipboard=env.setclipboard or _G.setclipboard
    if type(clipboard)~="function" then
        copy.Text="NO CLIPBOARD";return
    end
    local ok=pcall(clipboard,scout:Report())
    copy.Text=ok and "COPIED" or "COPY FAILED"
    task.delay(2,function()
        if copy and copy.Parent then copy.Text="COPY REPORT" end
    end)
end)
on(close.MouseButton1Click,function() scout:Destroy() end)
log("START read-only; preserving data across target resets")
task.spawn(function()
    while scout.running do
        local engine=env.KVK_UBG
        local target=(type(engine)=="table" and engine.running) and engine.target or nil
        if target~=scout.target then setTarget(target) end
        if target and target.Parent then
            scout.observations=scout.observations+1
            scout.targetScans=scout.targetScans+1
            scanTarget(target)
        end
        local total=0
        for _ in pairs(scout.anim) do total=total+1 end
        local last=scout.sessions[#scout.sessions]
        local shownStyle=scout.target and scout.style or (last and last.style or "Unexposed")
        local shownMode=scout.target and scout.mode or (last and last.mode or "Unexposed")
        if label and label.Parent then
            label.Text="[K]vk V4.5 STYLE SCOUT (read-only)\n"
                ..scout.status.."\nStyle: "..shownStyle.."\nMode: "..shownMode
                .."\nScans: "..scout.observations.." | AnimIDs: "..total
                .." | Saved: "..#scout.sessions
        end
        task.wait(1)
    end
end)
