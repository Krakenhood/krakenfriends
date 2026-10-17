local _, KR = ...
local T = KR.Theme
local Wg = KR.Widgets
local S = KR.Spells
local C = KR.Coach

--------------------------------------------------------------------------------
-- The coach window: the last fight (or one picked from the history), the
-- history with trends, and the bar's settings.
--------------------------------------------------------------------------------

local UI = {}
KR.UI = UI

local WIDTH, HEIGHT = 440, 580
local PAD = 18
local INNER = WIDTH - PAD * 2
local TOP = 66 -- where the pages start, under the title and tabs

local TABS = {
    { id = "fight", label = "Last fight" },
    { id = "history", label = "History" },
    { id = "bar", label = "Rage bar" },
}

local CLASSIFICATION = { elite = "Elite", rareelite = "Rare elite", rare = "Rare", worldboss = "Boss" }
local TIP_MARK = { good = "+", warn = "!", bad = "!" }

-- "%d" wants a whole number
local function fmtValue(fmt, v)
    if fmt:find("%%d") then v = math.floor(v + 0.5) end
    return fmt:format(v)
end

local function colorOf(level) return level == "good" and T.good or level == "warn" and T.warn or T.bad end

--------------------------------------------------------------------------------
-- Pools: text lines and meters reused between renders
--------------------------------------------------------------------------------

local function Pool(make)
    local pool = { items = {}, used = 0 }
    function pool:Get()
        self.used = self.used + 1
        local it = self.items[self.used]
        if not it then it = make(); self.items[self.used] = it end
        it:Show()
        return it
    end
    function pool:Reset()
        for _, it in ipairs(self.items) do it:Hide() end
        self.used = 0
    end
    return pool
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

function UI:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "KrakenrageFrame", UIParent)
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        KR.db.settings.window = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    f:SetScript("OnShow", function()
        UI:Render()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
    end)
    f:SetScript("OnHide", function()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
    end)
    f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "KrakenrageFrame") end

    local pos = KR.db.settings.window
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER")
    end

    Wg.DialogFrame(f)
    local band = Wg.Solid(f, "BACKGROUND", { 0, 0, 0 }, 0.45, 1)
    band:SetPoint("TOPLEFT", 2, -2)
    band:SetPoint("TOPRIGHT", -2, -2)
    band:SetHeight(26)

    local title = Wg.Title(f, 18)
    title:SetPoint("TOPLEFT", PAD, -7)
    title:SetText("Krakenrage")
    local sub = Wg.Text(f, 11, T.dim)
    sub:SetPoint("LEFT", title, "RIGHT", 8, -1)
    sub:SetText("the warrior's coach")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- tabs
    self.tabs = {}
    local x = PAD - 8
    for _, tab in ipairs(TABS) do
        local b = Wg.TextButton(f, tab.label, 12)
        b:SetPoint("TOPLEFT", x, -34)
        b:SetScript("OnClick", function() UI:Show(tab.id) end)
        x = x + b:GetWidth() + 4
        self.tabs[tab.id] = b
    end
    local rule = Wg.Solid(f, "ARTWORK", T.line)
    rule:SetPoint("TOPLEFT", PAD, -TOP + 6)
    rule:SetPoint("TOPRIGHT", -PAD, -TOP + 6)
    rule:SetHeight(1)

    -- pages
    self.pages = {}
    for _, tab in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", PAD, -TOP)
        page:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        page:Hide()
        self.pages[tab.id] = page
    end
    local fight = self.pages.fight
    self.texts = Pool(function()
        local fs = Wg.Text(fight, 12, T.text)
        fs:SetWidth(INNER)
        return fs
    end)
    self.meters = Pool(function() return Wg.Meter(fight, 150, 6) end)
    self.grade = Wg.Title(fight, 40)
    self.grade:SetPoint("TOPRIGHT", 0, -2)
    self.gradeScore = Wg.Text(fight, 11, T.dim, "RIGHT")
    self.gradeScore:SetPoint("TOPRIGHT", self.grade, "BOTTOMRIGHT", 0, -2)

    self:CreateHistory()
    self:CreateBarPage()
    self.page = "fight"
end

function UI:Toggle()
    self:Create()
    self.frame:SetShown(not self.frame:IsShown())
end

function UI:Show(page, fightIndex)
    self:Create()
    self.page = page or self.page
    if page == "fight" then self.viewing = fightIndex end
    if self.frame:IsShown() then self:Render() else self.frame:Show() end
end

function UI:Render()
    if not (self.frame and self.frame:IsShown()) then return end
    for id, page in pairs(self.pages) do page:SetShown(id == self.page) end
    for id, b in pairs(self.tabs) do b:SetActive(id == self.page) end
    if self.page == "fight" then self:RenderFight()
    elseif self.page == "history" then self:RenderHistory()
    else self:RenderBar() end
end

--------------------------------------------------------------------------------
-- Last fight
--------------------------------------------------------------------------------

local function spentLine(r)
    local list = {}
    for key, n in pairs(r.spent or {}) do
        local k, a = S:Known(key), KR.AbilityByKey[key]
        list[#list + 1] = { name = (k and k.name) or (a and a.short) or key, n = n }
    end
    table.sort(list, function(a, b) return a.n > b.n end)
    local parts = {}
    for i = 1, math.min(5, #list) do parts[i] = ("%s %d"):format(list[i].name, list[i].n) end
    return table.concat(parts, "  ·  ")
end

local function stanceLine(r)
    local parts, total = {}, 0
    for _, st in ipairs(KR.Stances) do total = total + ((r.stance or {})[st.key] or 0) end
    for _, st in ipairs(KR.Stances) do
        local s = (r.stance or {})[st.key]
        if s and total > 0 and s / total >= 0.01 then
            parts[#parts + 1] = ("%s %d%%"):format((st.label or st.name):gsub(" Stance$", ""), KR.Percent(s, total))
        end
    end
    local line = table.concat(parts, "  ·  ")
    if (r.swaps or 0) > 0 then
        line = line .. ("   %d %s"):format(r.swaps, r.swaps == 1 and "switch" or "switches")
        if (r.stanceLoss or 0) > 0 then line = line .. (", %d rage lost"):format(r.stanceLoss) end
    end
    return line
end

UI.SpentLine, UI.StanceLine = spentLine, stanceLine

function UI:RenderFight()
    local page = self.pages.fight
    self.texts:Reset()
    self.meters:Reset()
    local fights = KR.char.fights
    local index = self.viewing or #fights
    local r = fights[index]
    local y = 0
    local function line(text, size, color, gap, wrap)
        local fs = self.texts:Get()
        fs:SetFont(Wg.FONT, size or 12, "")
        fs:SetTextColor(Wg.rgb(color or T.text))
        fs:SetWordWrap(wrap and true or false)
        fs:SetWidth(INNER)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        fs:SetText(text)
        y = y + (wrap and math.max(14, fs:GetStringHeight()) or (size or 12) + 3) + (gap or 4)
        return fs
    end

    if not r then
        self.grade:SetText("")
        self.gradeScore:SetText("")
        line("No fights yet.", 14, T.gold, 8)
        line("Fight something for at least six seconds and the coach grades it here: Overpower and Revenge chances, the Execute phase, rage that went to waste, stance switches, Battle Shout and Sunder Armor.", 12, T.dim, 10, true)
        line("/kr demo fills the coach with sample fights.", 12, T.dim, 0, true)
        return
    end

    -- header: who, how long, when; the grade on the right
    local name = r.target or "Unknown foe"
    if CLASSIFICATION[r.cls or ""] then name = name .. "  " .. KR.Colorize(CLASSIFICATION[r.cls], T.warn) end
    if r.practice then name = name .. "  " .. KR.Colorize("practice", T.faint) end
    local title = line(name, 16, T.gold, 2)
    title:SetWidth(INNER - 70)
    local meta = KR.FormatClock(r.dur) .. "  ·  " .. KR.FormatAgo(r.t)
    if (r.adds or 0) > 0 then meta = meta .. ("  ·  %d more %s"):format(r.adds, r.adds == 1 and "foe" or "foes") end
    if index ~= #fights then meta = meta .. ("  ·  fight %d of %d"):format(index, #fights) end
    line(meta, 11, T.dim, 14)
    self.grade:SetText(C.Grade(r.score))
    self.grade:SetTextColor(Wg.rgb(C.GradeColor(r.score)))
    self.gradeScore:SetText(r.score and (r.score .. " / 100") or "nothing to grade")

    -- the parts of the grade
    local parts = C:Parts(r)
    if #parts > 0 then
        line("How it went", 13, T.gold, 6)
        for _, p in ipairs(parts) do
            local fs = line(p.label, 12, T.text, 3)
            fs:SetWidth(150)
            local m = self.meters:Get()
            m:ClearAllPoints()
            m:SetPoint("LEFT", fs, "LEFT", 160, 0)
            local pct = math.floor(p.value * 100 + 0.5)
            m:Set(p.value, C.GradeColor(pct))
            local v = self.texts:Get()
            v:SetFont(Wg.FONT, 11, "")
            v:SetWordWrap(false)
            v:SetWidth(60)
            v:SetTextColor(Wg.rgb(T.dim))
            v:ClearAllPoints()
            v:SetPoint("LEFT", m, "RIGHT", 8, 0)
            v:SetText(pct .. "%")
        end
        y = y + 8
    end

    -- the tips
    local tips = C:Tips(r)
    if #tips > 0 then
        line("The coach says", 13, T.gold, 6)
        for i = 1, math.min(6, #tips) do
            local tip = tips[i]
            local c = colorOf(tip.level)
            line(KR.Colorize(TIP_MARK[tip.level] .. "  ", c) .. tip.text, 12, T.text, 6, true)
        end
        y = y + 6
    end

    local spent = spentLine(r)
    if spent ~= "" then
        line("Rage went into", 13, T.gold, 4)
        line(spent, 11, T.dim, 10, true)
    end
    local stances = stanceLine(r)
    if stances ~= "" then
        line("Stances", 13, T.gold, 4)
        line(stances, 11, T.dim, 0, true)
    end
end

--------------------------------------------------------------------------------
-- History
--------------------------------------------------------------------------------

local HISTORY_ROWS = 12
local ROW_H = 20

function UI:CreateHistory()
    local page = self.pages.history
    self.trendTitle = Wg.Text(page, 13, T.gold)
    self.trendTitle:SetPoint("TOPLEFT", 0, 0)
    self.trendLines = {}
    for i = 1, #C.TrendDefs do
        local row = {}
        row.label = Wg.Text(page, 12, T.text)
        row.label:SetPoint("TOPLEFT", 0, -20 - (i - 1) * 17)
        row.label:SetWidth(190)
        row.value = Wg.Text(page, 12, T.text, "RIGHT")
        row.value:SetPoint("TOPLEFT", 190, -20 - (i - 1) * 17)
        row.value:SetWidth(70)
        row.change = Wg.Text(page, 11, T.dim)
        row.change:SetPoint("TOPLEFT", 270, -20 - (i - 1) * 17)
        row.change:SetWidth(INNER - 270)
        self.trendLines[i] = row
    end
    local listTop = 20 + #C.TrendDefs * 17 + 14
    self.listTitle = Wg.Text(page, 13, T.gold)
    self.listTitle:SetPoint("TOPLEFT", 0, -listTop)
    self.rows = {}
    for i = 1, HISTORY_ROWS do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(INNER, ROW_H)
        b:SetPoint("TOPLEFT", 0, -(listTop + 20) - (i - 1) * ROW_H)
        b.hl = Wg.Solid(b, "BACKGROUND", T.hover)
        b.hl:SetAllPoints()
        b.hl:Hide()
        b.grade = Wg.Title(b, 14)
        b.grade:SetPoint("LEFT", 4, 0)
        b.grade:SetWidth(20)
        b.name = Wg.Text(b, 12, T.text)
        b.name:SetPoint("LEFT", 30, 0)
        b.name:SetWidth(220)
        b.dur = Wg.Text(b, 11, T.dim, "RIGHT")
        b.dur:SetPoint("LEFT", 250, 0)
        b.dur:SetWidth(46)
        b.ago = Wg.Text(b, 11, T.dim, "RIGHT")
        b.ago:SetPoint("RIGHT", -4, 0)
        b.ago:SetWidth(100)
        b:SetScript("OnEnter", function() b.hl:Show() end)
        b:SetScript("OnLeave", function() b.hl:Hide() end)
        b:SetScript("OnClick", function() UI:Show("fight", b.index) end)
        self.rows[i] = b
    end
    self.empty = Wg.Text(page, 12, T.dim)
    self.empty:SetPoint("TOPLEFT", self.listTitle, "BOTTOMLEFT", 0, -8)
end

function UI:RenderHistory()
    local fights = KR.char.fights
    local trends = C:Trends()
    self.trendTitle:SetText(#fights > 10 and "Your last 10 fights, against the 10 before" or "Your fights so far")
    for i, row in ipairs(self.trendLines) do
        local tr = trends[i]
        row.label:SetShown(tr ~= nil)
        row.value:SetShown(tr ~= nil)
        row.change:SetShown(tr ~= nil)
        if tr then
            row.label:SetText(tr.label)
            row.value:SetText(fmtValue(tr.fmt, tr.now))
            if tr.before then
                local word = tr.better == true and KR.Colorize("better", T.good) or tr.better == false and KR.Colorize("worse", T.bad) or "same"
                row.change:SetText(("%s (was %s)"):format(word, fmtValue(tr.fmt, tr.before)))
            else
                row.change:SetText("")
            end
        end
    end

    self.listTitle:SetText(#fights > 0 and ("Recent fights (%d kept)"):format(#fights) or "Recent fights")
    self.empty:SetShown(#fights == 0)
    self.empty:SetText("Nothing here yet.")
    for i, b in ipairs(self.rows) do
        local index = #fights - i + 1
        local r = fights[index]
        b:SetShown(r ~= nil)
        if r then
            b.index = index
            b.grade:SetText(C.Grade(r.score))
            b.grade:SetTextColor(Wg.rgb(C.GradeColor(r.score)))
            local name = r.target or "Unknown foe"
            if CLASSIFICATION[r.cls or ""] then name = name .. " " .. KR.Colorize("(" .. CLASSIFICATION[r.cls] .. ")", T.warn) end
            if r.practice then name = name .. " " .. KR.Colorize("practice", T.faint) end
            b.name:SetText(name)
            b.dur:SetText(KR.FormatClock(r.dur))
            b.ago:SetText(KR.FormatAgo(r.t))
        end
    end
end

--------------------------------------------------------------------------------
-- The bar's settings
--------------------------------------------------------------------------------

function UI:CreateBarPage()
    local page = self.pages.bar
    local hud = function() return KR.db.settings.hud end
    local h = Wg.Text(page, 13, T.gold)
    h:SetPoint("TOPLEFT", 0, 0)
    h:SetText("The bar")
    local opts = {
        { "Lock the bar", function() return hud().locked end, function(v) hud().locked = v end, "Unlocked, the bar can be dragged." },
        { "Swing timer (experimental)", function() return hud().swing end, function(v) hud().swing = v end, "A thin bar under the rage showing your next main-hand swing. It turns amber with Heroic Strike queued, red when that would leave too little rage for your big ability." },
        { "Overpower, Revenge and Execute alerts", function() return hud().procs end, function(v) hud().procs = v end },
        { "Stance and what a switch costs", function() return hud().stance end, function(v) hud().stance = v end, "Your stance left of the bar, and right of it the rage a stance switch would cost you now." },
        { "Dim out of combat", function() return hud().fade end, function(v) hud().fade = v end },
        { "A note after each fight", function() return KR.db.settings.toasts end, function(v) KR.db.settings.toasts = v end },
        { "Minimap button", function() return not KR.db.settings.minimap.hide end, function(v) KR.db.settings.minimap.hide = not v end },
    }
    self.checks = {}
    for i, o in ipairs(opts) do
        local cb = Wg.Check(page, o[1], o[2], o[3], o[4])
        cb:SetPoint("TOPLEFT", -4, -20 - (i - 1) * 22)
        self.checks[#self.checks + 1] = cb
    end
    local tickTop = 20 + #opts * 22 + 14
    local th = Wg.Text(page, 13, T.gold)
    th:SetPoint("TOPLEFT", 0, -tickTop)
    th:SetText("Ticks on the bar")
    local note = Wg.Text(page, 11, T.dim)
    note:SetPoint("TOPLEFT", 0, -tickTop - 18)
    note:SetText("Abilities you know, at their real rage cost.")
    self.tickTop = tickTop + 38
    self.tickChecks = {}
end

function UI:RenderBar()
    local page = self.pages.bar
    for _, cb in ipairs(self.checks) do cb:Hide(); cb:Show() end -- re-read the settings
    for _, cb in ipairs(self.tickChecks) do cb:Hide() end
    local i = 0
    for _, a in ipairs(KR.Abilities) do
        local k = S:Known(a.key)
        if k and k.cost > 0 then
            i = i + 1
            local cb = self.tickChecks[i]
            if not cb then
                cb = Wg.Check(page, "", function() return cb and cb.key and KR.Hud:TickEnabled(cb.key) end, function(v) KR.Hud:SetTickEnabled(cb.key, v) end)
                cb.icon = Wg.Icon(cb, 16)
                cb.icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
                cb.label:ClearAllPoints()
                cb.label:SetPoint("LEFT", cb.icon, "RIGHT", 5, 0)
                self.tickChecks[i] = cb
            end
            cb.key = a.key
            Wg.SetIcon(cb.icon, k.icon)
            cb.label:SetText(("%s  |cffb8ad99%d|r"):format(k.name, k.cost))
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", page, "TOPLEFT", (i % 2 == 1) and -4 or INNER / 2, -self.tickTop - math.floor((i - 1) / 2) * 22)
            cb:Hide()
            cb:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- The note after a fight
--------------------------------------------------------------------------------

local toast

local function createToast()
    toast = CreateFrame("Button", "KrakenrageToast", UIParent)
    toast:SetSize(300, 48)
    toast:SetFrameStrata("HIGH")
    Wg.ThinFrame(toast, 0)
    toast.grade = Wg.Title(toast, 26)
    toast.grade:SetPoint("LEFT", 12, 0)
    toast.title = Wg.Text(toast, 12, T.gold)
    toast.title:SetPoint("TOPLEFT", 48, -9)
    toast.title:SetWidth(240)
    toast.text = Wg.Text(toast, 11, T.dim)
    toast.text:SetPoint("TOPLEFT", 48, -26)
    toast.text:SetWidth(240)
    toast:SetScript("OnClick", function()
        toast:Hide()
        UI:Show("fight", #KR.char.fights)
    end)
    toast:Hide()
end

function UI:Toast(r)
    if not KR.db.settings.toasts then return end
    if not toast then createToast() end
    toast:ClearAllPoints()
    local hud = KR.Hud.frame
    if hud then toast:SetPoint("BOTTOM", hud, "TOP", 0, 60) else toast:SetPoint("TOP", 0, -160) end
    toast.grade:SetText(C.Grade(r.score))
    toast.grade:SetTextColor(Wg.rgb(C.GradeColor(r.score)))
    toast.title:SetText(("%s, %s"):format(r.target or "Fight", KR.FormatClock(r.dur)))
    local tips = C:Tips(r)
    local first = tips[1]
    local n = 0
    for i, t in ipairs(tips) do if t.level ~= "good" and i <= 6 then n = n + 1 end end -- the window shows six
    toast.text:SetText(first and (n > 0 and ("%d %s from the coach. Click to read."):format(n, n == 1 and "tip" or "tips") or "Clean fight. Click for details.") or "Click for details.")
    toast:SetAlpha(1)
    toast:Show()
    local shownAt = GetTime()
    toast.shownAt = shownAt
    C_Timer.After(8, function()
        if toast.shownAt == shownAt and not toast:IsMouseOver() then toast:Hide() end
    end)
end

KR:Listen("FIGHT_DONE", function(r) UI:Toast(r) end)
KR:Listen("FIGHTS", function()
    if UI.viewing and not KR.char.fights[UI.viewing] then UI.viewing = nil end
    UI:Render()
end)
KR:Listen("SPELLS", function() UI:Render() end)
