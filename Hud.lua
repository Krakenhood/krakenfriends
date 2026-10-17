local _, KR = ...
local call = KR.call
local T = KR.Theme
local Wg = KR.Widgets
local S = KR.Spells

--------------------------------------------------------------------------------
-- The rage bar
--
-- Your rage, with a tick at the cost of each ability you use: the icon above
-- a tick lights up when you can afford it, are in the right stance and it's
-- ready. Under it a thin swing timer, and big alerts when Overpower, Revenge or
-- Execute are worth pressing.
--------------------------------------------------------------------------------

local H = {}
KR.Hud = H

local BAR_W, BAR_H = 240, 18
local TICK_ICON = 15
local SWING_H = 4
local PROC_SIZE = 34
local UPDATE = 0.05

local frame, bar, rageText, swapText, keepMark, swing, stanceIcon
local ticks = {}  -- built from the abilities you know: { ability, known, line, icons = { frame } }
local procs = {}  -- kind -> alert frame
local elapsed = 0

--------------------------------------------------------------------------------
-- Which abilities get a tick
--------------------------------------------------------------------------------

function H:TickEnabled(key)
    local o = KR.char.ticks[key]
    if o ~= nil then return o end
    return KR.AbilityByKey[key].tick and true or false
end

function H:SetTickEnabled(key, on)
    local a = KR.AbilityByKey[key]
    if (a.tick and true or false) == on then KR.char.ticks[key] = nil else KR.char.ticks[key] = on end
    self:BuildTicks()
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function savePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    local hud = KR.db.settings.hud
    hud.point, hud.relPoint, hud.x, hud.y = point, relPoint, x, y
end

local function place()
    local hud = KR.db.settings.hud
    frame:ClearAllPoints()
    if hud.point then
        frame:SetPoint(hud.point, UIParent, hud.relPoint or hud.point, hud.x or 0, hud.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    end
    frame:SetScale(hud.scale or 1)
end

local function newProc(kind, iconFile, label)
    local p = Wg.FramedIcon(frame, PROC_SIZE)
    p.kind = kind
    Wg.SetIcon(p.icon, iconFile)
    p.time = Wg.Text(p, 14, T.text, "CENTER", "OUTLINE")
    p.time:SetPoint("BOTTOM", 0, 2)
    p.label = Wg.Text(p, 10, T.gold, "CENTER", "OUTLINE")
    p.label:SetPoint("TOP", p, "BOTTOM", 0, -2)
    p.label:SetText(label)
    p.glow = p:CreateTexture(nil, "OVERLAY")
    p.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    p.glow:SetBlendMode("ADD")
    p.glow:SetPoint("CENTER")
    p.glow:SetSize(PROC_SIZE * 1.9, PROC_SIZE * 1.9)
    p:Hide()
    procs[kind] = p
    return p
end

function H:Create()
    if frame then return end
    frame = CreateFrame("Frame", "KrakenrageHud", UIParent)
    self.frame = frame
    frame:SetSize(BAR_W, BAR_H)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) if not KR.db.settings.hud.locked then f:StartMoving() end end)
    frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); savePosition() end)
    Wg.ThinFrame(frame, 4)

    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetAllPoints()
    bar:SetStatusBarTexture(Wg.FirstFile(KR.Files.bar))
    bar:SetStatusBarColor(Wg.rgb(T.rage))
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    self.bar = bar
    local shine = bar:CreateTexture(nil, "OVERLAY")
    shine:SetPoint("TOPLEFT")
    shine:SetPoint("TOPRIGHT")
    shine:SetHeight(BAR_H / 2)
    shine:SetColorTexture(1, 1, 1, 0.06)

    rageText = Wg.Text(bar, 12, T.text, "CENTER", "OUTLINE")
    rageText:SetPoint("CENTER")
    self.rageText = rageText

    -- the rage you'd lose on a stance switch, right of the bar
    swapText = Wg.Text(frame, 11, T.bad, "LEFT", "OUTLINE")
    swapText:SetPoint("LEFT", frame, "RIGHT", 8, 0)
    self.swapText = swapText
    -- and a faint line at what you keep
    keepMark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    keepMark:SetSize(1, BAR_H)
    keepMark:SetColorTexture(1, 1, 1, 0.35)
    keepMark:Hide()

    stanceIcon = Wg.FramedIcon(frame, BAR_H + 8)
    stanceIcon:SetPoint("RIGHT", frame, "LEFT", -8, 0)
    self.stanceIcon = stanceIcon

    -- swing timer
    swing = CreateFrame("StatusBar", nil, frame)
    swing:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -5)
    swing:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -5)
    swing:SetHeight(SWING_H)
    swing:SetStatusBarTexture(Wg.FirstFile(KR.Files.bar))
    swing:SetStatusBarColor(Wg.rgb(T.gold))
    swing:SetMinMaxValues(0, 1)
    swing.bg = Wg.Solid(swing, "BACKGROUND", { 0, 0, 0 }, 0.6)
    swing.bg:SetAllPoints()
    swing:Hide()
    self.swing = swing

    -- proc alerts, centred under the bar
    newProc("ex", "INV_Sword_48", "Execute")
    newProc("op", "Ability_MeleeDamage", "Overpower")
    newProc("rv", "Ability_Warrior_Revenge", "Revenge")

    -- the unlocked hint
    frame.hint = Wg.Text(frame, 11, T.gold, "CENTER")
    frame.hint:SetPoint("BOTTOM", frame, "TOP", 0, 26)
    frame.hint:SetText("Krakenrage: drag me, then /kr lock")

    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < UPDATE then return end
        elapsed = 0
        KR.dispatch(H.Update, H)
    end)

    place()
    self:BuildTicks()
    self:ApplySettings()
    self:Update()
end

-- One tick line per distinct cost, icons above it; icons that would overlap
-- move up a row.
function H:BuildTicks()
    if not frame then return end
    for _, t in ipairs(ticks) do
        t.line:Hide()
        for _, ic in ipairs(t.icons) do ic:Hide() end
    end
    wipe(ticks)
    local _, max = S:Rage()
    local groups, byCost = {}, {}
    for _, a in ipairs(KR.Abilities) do
        local k = S:Known(a.key)
        if k and k.cost > 0 and self:TickEnabled(a.key) then
            local g = byCost[k.cost]
            if not g then
                g = { cost = k.cost, items = {} }
                byCost[k.cost] = g
                groups[#groups + 1] = g
            end
            g.items[#g.items + 1] = { ability = a, known = k }
        end
    end
    table.sort(groups, function(a, b) return a.cost < b.cost end)

    local rows = {} -- the right edge of the last icon in each row
    for _, g in ipairs(groups) do
        local x = BAR_W * math.min(1, g.cost / max)
        local line = self:Line()
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", bar, "TOPLEFT", x - 1, 0)
        line:Show()
        local w = #g.items * (TICK_ICON + 1) - 1
        local left = math.max(-TICK_ICON / 2, math.min(BAR_W - w + TICK_ICON / 2, x - w / 2))
        local row = 1
        while rows[row] and rows[row] > left - 1 do row = row + 1 end
        rows[row] = left + w
        local entry = { cost = g.cost, line = line, icons = {} }
        for i, item in ipairs(g.items) do
            local ic = self:TickIcon()
            ic.ability, ic.known = item.ability, item.known
            Wg.SetIcon(ic.icon, item.known.icon)
            ic:ClearAllPoints()
            ic:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", left + (i - 1) * (TICK_ICON + 1), 5 + (row - 1) * (TICK_ICON + 2))
            ic:Show()
            entry.icons[i] = ic
        end
        ticks[#ticks + 1] = entry
    end
    self.ticks = ticks
end

local linePool, iconPool = {}, {}
function H:Line()
    for _, l in ipairs(linePool) do if not l:IsShown() then return l end end
    local l = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    l:SetSize(2, BAR_H)
    l:SetColorTexture(0, 0, 0, 0.7)
    linePool[#linePool + 1] = l
    return l
end

function H:TickIcon()
    for _, ic in ipairs(iconPool) do if not ic:IsShown() then return ic end end
    local ic = Wg.FramedIcon(frame, TICK_ICON)
    ic.queued = ic:CreateTexture(nil, "OVERLAY")
    ic.queued:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    ic.queued:SetBlendMode("ADD")
    ic.queued:SetPoint("CENTER")
    ic.queued:SetSize(TICK_ICON * 1.9, TICK_ICON * 1.9)
    ic.queued:Hide()
    iconPool[#iconPool + 1] = ic
    return ic
end

function H:ApplySettings()
    if not frame then return end
    local hud = KR.db.settings.hud
    place()
    frame:EnableMouse(not hud.locked)
    frame.hint:SetShown(not hud.locked)
    stanceIcon:SetShown(hud.stance and true or false)
    if not hud.swing then swing:Hide() end
    if not hud.procs then for _, p in pairs(procs) do p:Hide() end end
end

--------------------------------------------------------------------------------
-- Updating
--------------------------------------------------------------------------------

-- Is the ability one you could press right now? (for the icon above its tick)
function H:Ready(a, k, rage, stanceKey)
    if a.key == "overpower" then return KR.Coach.windows.op ~= nil and S:StanceFits(a, stanceKey) and (rage == nil or rage >= k.cost) end
    if a.key == "revenge" then return KR.Coach.windows.rv ~= nil and S:StanceFits(a, stanceKey) and (rage == nil or rage >= k.cost) end
    if a.key == "execute" then return KR.Coach.execute and S:StanceFits(a, stanceKey) and (rage == nil or rage >= k.cost) end
    if not S:StanceFits(a, stanceKey) then return false end
    if rage ~= nil and rage < k.cost then return false end
    local cd = S:CooldownLeft(a.key)
    if cd and cd > 0.1 then return false end
    if rage == nil then
        -- rage hidden from us: let the game decide
        local usable = S:Usable(a.key)
        return usable and true or false
    end
    return true
end

function H:Update()
    if not frame then return end
    local hud = KR.db.settings.hud
    local rage, max, raw = S:Rage()
    local inCombat = KR.Coach.fight ~= nil
    bar:SetMinMaxValues(0, max)
    if rage then
        bar:SetValue(rage)
        rageText:SetText(rage > 0 and tostring(rage) or "")
    else
        pcall(bar.SetValue, bar, raw or 0) -- a status bar may take a secret value
        rageText:SetText("")
    end

    local stance = S:Stance()
    local stanceKey = stance and stance.key
    if hud.stance and stance then
        Wg.SetIcon(stanceIcon.icon, stance.texture or stance.icon)
        stanceIcon:SetAlpha(1)
    elseif hud.stance then
        stanceIcon:SetAlpha(0.3)
    end

    -- rage you'd lose switching stance now
    local keep = S:Keep()
    if hud.stance and rage and rage > keep then
        swapText:SetText(("-%d on switch"):format(rage - keep))
        swapText:SetTextColor(Wg.rgb((rage - keep) >= 20 and T.bad or T.dim))
        swapText:Show()
    else
        swapText:Hide()
    end
    if hud.stance and keep > 0 then
        keepMark:ClearAllPoints()
        keepMark:SetPoint("TOPLEFT", bar, "TOPLEFT", BAR_W * math.min(1, keep / max), 0)
        keepMark:Show()
    else
        keepMark:Hide()
    end

    -- ticks
    for _, t in ipairs(ticks) do
        local afford = rage and rage >= t.cost
        t.line:SetColorTexture(afford and T.gold[1] or 0, afford and T.gold[2] or 0, afford and T.gold[3] or 0, afford and 0.9 or 0.7)
        for _, ic in ipairs(t.icons) do
            local ready = self:Ready(ic.ability, ic.known, rage, stanceKey)
            ic.icon:SetDesaturated(not ready)
            ic:SetAlpha(ready and 1 or 0.45)
            ic.queued:SetShown(ic.ability.swing and S:Queued(ic.ability.key) or false)
        end
    end

    -- swing timer
    if hud.swing then
        local done = KR.Swing:Progress()
        if done then
            swing:SetValue(done)
            local color = T.gold
            for _, key in ipairs({ "hs", "cleave" }) do
                local k = S:Known(key)
                if k and S:Queued(key) then
                    color = T.warn
                    -- the queued swing would leave too little for your big ability
                    if rage and self:MainShort(rage - k.cost) then color = T.bad end
                end
            end
            swing:SetStatusBarColor(Wg.rgb(color))
            swing:Show()
        else
            swing:Hide()
        end
    end

    -- proc alerts
    if hud.procs then
        local shown = {}
        if KR.Coach.execute and S:Known("execute") then shown[#shown + 1] = { procs.ex } end
        for _, kind in ipairs({ "op", "rv" }) do
            local left = KR.Coach:Window(kind)
            if left and S:Known(kind == "op" and "overpower" or "revenge") then shown[#shown + 1] = { procs[kind], left } end
        end
        for _, p in pairs(procs) do p:Hide() end
        local total = #shown * (PROC_SIZE + 10) - 10
        for i, s in ipairs(shown) do
            local p, left = s[1], s[2]
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", frame, "BOTTOM", -total / 2 + (i - 1) * (PROC_SIZE + 10), -(SWING_H + 12))
            p.time:SetText(left and ("%.1f"):format(left) or "")
            local a = KR.AbilityByKey[p.kind == "ex" and "execute" or p.kind == "op" and "overpower" or "revenge"]
            local fits = S:StanceFits(a, stanceKey)
            p.icon:SetDesaturated(not fits)
            p.label:SetText(fits and a and S:Known(a.key).name or (KR.Stances[p.kind == "rv" and 2 or 1].label or ""))
            p.glow:SetAlpha(0.5 + 0.5 * math.abs(math.sin(GetTime() * 4)))
            p:Show()
        end
    end

    -- dim out of combat with nothing to show
    if hud.locked and hud.fade and not inCombat and (rage == nil or rage == 0) then
        frame:SetAlpha(0.35)
    else
        frame:SetAlpha(1)
    end
end

-- True when `rage` wouldn't pay for the big ability you have and it's (nearly) ready.
function H:MainShort(rage)
    for _, key in ipairs({ "ms", "bt", "ss" }) do
        local k = S:Known(key)
        if k then
            local cd = S:CooldownLeft(key)
            return (cd == nil or cd <= 1.5) and rage < k.cost
        end
    end
    return false
end

KR:Listen("SETUP", function() H:Create() end)
KR:Listen("SPELLS", function() H:BuildTicks() end)
KR:Listen("SETTINGS", function() H:ApplySettings() end)
KR:Listen("PROC", function() H:Update() end)
KR:OnReady("UNIT_MAXPOWER", function() H:BuildTicks() end)
