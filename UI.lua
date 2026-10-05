local _, KF = ...
local call = KF.call
local Theme = KF.Theme
local FN = KF.FormatNumber

local UI = {}
KF.UI = UI

local WIDTH, HEIGHT = 440, 560
local PAD = 16
local ROW_W = WIDTH - PAD * 2
local CONTENT_TOP = 136
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local AMBER = { 0.95, 0.72, 0.30 }

local TABS = {
    { id = "Overview", label = "Overview" },
    { id = "Bestiary", label = "Bestiary" },
    { id = "Loot", label = "Loot" },
    { id = "Dungeons", label = "Dungeons" },
    { id = "Journal", label = "Journal" },
}

local LOG_ICONS = {
    start = "start", zone = "zone", boss = "boss", rare = "rare", loot = "epic", record = "kills",
    milestone = "milestone", level = "level", dungeon = "dungeon",
}

--------------------------------------------------------------------------------
-- Drawing helpers
--------------------------------------------------------------------------------

local function rgb(c) return c[1], c[2], c[3] end

local function Solid(parent, layer, color, alpha)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
    return t
end

local function Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.75)
    fs:SetTextColor(rgb(color or Theme.text))
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Border(frame, color, alpha)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = Solid(frame, "BORDER", color, alpha)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
            t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side)
            t:SetPoint("BOTTOM" .. side)
            t:SetWidth(1)
        end
    end
end

local function Gradient(tex, orientation, c1, a1, c2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient(orientation, CreateColor(c1[1], c1[2], c1[3], a1), CreateColor(c2[1], c2[2], c2[3], a2))
    else
        tex:SetColorTexture(c2[1], c2[2], c2[3], a2)
    end
end

local fileCache = {}
local function resolveFile(path)
    if type(path) == "number" or not GetFileIDFromPath then return path end
    local id = fileCache[path]
    if id == nil then
        id = call(GetFileIDFromPath, path) or false
        fileCache[path] = id
    end
    return id
end

local function Circle(tex)
    if not resolveFile(MASK) then return end
    local mask = tex:GetParent():CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
end
KF.Circle = Circle

-- Two rotated strokes: an "x" or a chevron without relying on font glyphs.
local function Strokes(parent, size, color, angles, spread)
    local strokes = {}
    for i, angle in ipairs(angles) do
        local s = parent:CreateTexture(nil, "ARTWORK")
        s:SetSize(size, 1.5)
        s:SetPoint("CENTER", spread and (i == 1 and -spread or spread) or 0, 0)
        s:SetColorTexture(rgb(color))
        s:SetRotation(math.rad(angle))
        strokes[i] = s
    end
    return strokes
end

function KF.SetIcon(tex, spec)
    if type(spec) == "string" then spec = KF.Icons[spec] end
    spec = spec or KF.Icons.unknown
    if spec.atlas and C_Texture and call(C_Texture.GetAtlasInfo, spec.atlas) then
        tex:SetAtlas(spec.atlas)
        return
    end
    for _, path in ipairs(spec.files) do
        local file = resolveFile(path)
        if file then
            tex:SetTexture(file)
            if spec.nocrop then tex:SetTexCoord(0, 1, 0, 1) else tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            return
        end
    end
    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local function SetClassIcon(tex, class)
    local atlas = class and ("classicon-" .. class:lower())
    if atlas and C_Texture and call(C_Texture.GetAtlasInfo, atlas) then
        tex:SetAtlas(atlas)
        return
    end
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        return
    end
    KF.SetIcon(tex, "unknown")
end

local function SetPortrait(tex, unit, class)
    if unit and SetPortraitTexture and call(UnitExists, unit) and call(UnitIsVisible, unit) then
        tex:SetTexCoord(0, 1, 0, 1)
        if pcall(SetPortraitTexture, tex, unit) then return end
    end
    SetClassIcon(tex, class)
end

local function ClassName(class)
    if not class then return "" end
    local names = LOCALIZED_CLASS_NAMES_MALE
    return names and names[class] or (class:sub(1, 1) .. class:sub(2):lower())
end

local function ShortName(key)
    return key and key:match("^[^%-]+") or "?"
end

local function Tooltip(owner, fn)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if type(fn) == "function" then fn(GameTooltip) else GameTooltip:AddLine(fn, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function HookTooltip(w)
    w:EnableMouse(true)
    w:SetScript("OnEnter", function(self)
        if self.hl and self.tooltip then self.hl:Show() end
        if self.tooltip then Tooltip(self, self.tooltip) end
    end)
    w:SetScript("OnLeave", function(self)
        if self.hl then self.hl:Hide() end
        GameTooltip:Hide()
    end)
end

local function sum(t)
    local n = 0
    for _, v in pairs(t or {}) do n = n + v end
    return n
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
-- Widget pools. Every refresh hands all widgets back and lays the tab out
-- again from the top, which keeps the builders simple.
--------------------------------------------------------------------------------

local factories = {}

function factories.section(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(ROW_W, 26)
    w.label = Text(w, 10, Theme.accent)
    w.label:SetPoint("BOTTOMLEFT", 0, 6)
    local line = Solid(w, "ARTWORK", Theme.line)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", w.label, "BOTTOMRIGHT", 8, 4)
    line:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 0, 10)
    return w
end

function factories.tile(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(120, 58)
    local bg = Solid(w, "BACKGROUND", Theme.panel)
    bg:SetAllPoints()
    w.hl = Solid(w, "BORDER", Theme.hover)
    w.hl:SetAllPoints()
    w.hl:Hide()
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetSize(22, 22)
    w.icon:SetPoint("TOPLEFT", 8, -8)
    w.value = Text(w, 16)
    w.value:SetPoint("LEFT", w.icon, "RIGHT", 8, 0)
    w.value:SetPoint("RIGHT", w, "RIGHT", -6, 0)
    w.label = Text(w, 10, Theme.dim)
    w.label:SetPoint("BOTTOMLEFT", 8, 8)
    w.label:SetPoint("BOTTOMRIGHT", -6, 8)
    HookTooltip(w)
    return w
end

function factories.row(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(ROW_W, 26)
    w.hl = Solid(w, "BACKGROUND", Theme.hover)
    w.hl:SetAllPoints()
    w.hl:Hide()
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetPoint("LEFT", 0, 1)
    w.value = Text(w, 12, Theme.text, "RIGHT")
    w.value:SetPoint("RIGHT", -2, 1)
    w.detail = Text(w, 11, Theme.dim, "RIGHT")
    w.detail:SetPoint("RIGHT", w.value, "LEFT", -10, 0)
    w.label = Text(w, 12)
    w.label:SetPoint("LEFT", 26, 1)
    w.label:SetPoint("RIGHT", w.detail, "LEFT", -8, 0)
    w.barBg = Solid(w, "BACKGROUND", Theme.line, 0.05)
    w.barBg:SetPoint("BOTTOMLEFT", 26, 1)
    w.barBg:SetPoint("BOTTOMRIGHT", 0, 1)
    w.barBg:SetHeight(2)
    w.bar = w:CreateTexture(nil, "ARTWORK")
    w.bar:SetPoint("BOTTOMLEFT", 26, 1)
    w.bar:SetHeight(2)
    HookTooltip(w)
    return w
end

function factories.line(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(ROW_W, 22)
    w.right = Text(w, 12, Theme.text, "RIGHT")
    w.right:SetPoint("RIGHT", -2, 0)
    w.left = Text(w, 12, Theme.dim)
    w.left:SetPoint("LEFT")
    w.left:SetPoint("RIGHT", w.right, "LEFT", -10, 0)
    return w
end

function factories.split(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(ROW_W, 44)
    w.title = Text(w, 10, Theme.dim, "CENTER")
    w.title:SetPoint("TOP", 0, -2)
    w.left = Text(w, 12)
    w.left:SetPoint("TOPLEFT", 0, -15)
    w.right = Text(w, 12, nil, "RIGHT")
    w.right:SetPoint("TOPRIGHT", 0, -15)
    w.a = w:CreateTexture(nil, "ARTWORK")
    w.a:SetPoint("BOTTOMLEFT", 0, 6)
    w.a:SetHeight(4)
    w.b = w:CreateTexture(nil, "ARTWORK")
    w.b:SetPoint("BOTTOMRIGHT", 0, 6)
    w.b:SetHeight(4)
    return w
end

-- A record for both players side by side: name, big number, spell and target.
function factories.record(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(ROW_W, 70)
    local half = ROW_W / 2 - 12
    w.title = Text(w, 10, Theme.dim, "CENTER")
    w.title:SetPoint("TOP", 0, -2)
    for _, side in ipairs({ "left", "right" }) do
        local anchor, justify = side == "left" and "TOPLEFT" or "TOPRIGHT", side == "left" and "LEFT" or "RIGHT"
        w[side] = {
            name = Text(w, 11, Theme.text, justify),
            amount = Text(w, 17, Theme.text, justify),
            sub = Text(w, 10, Theme.dim, justify),
        }
        w[side].name:SetPoint(anchor, 0, -17)
        w[side].amount:SetPoint(anchor, 0, -32)
        w[side].sub:SetPoint(anchor, 0, -52)
        for _, fs in pairs(w[side]) do fs:SetWidth(half) end
    end
    return w
end

function factories.note(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(ROW_W, 20)
    w.text = Text(w, 12, Theme.dim)
    w.text:SetPoint("TOPLEFT", 0, -4)
    w.text:SetWidth(ROW_W)
    w.text:SetWordWrap(true)
    w.text:SetJustifyV("TOP")
    return w
end

function factories.log(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(ROW_W, 24)
    w.time = Text(w, 10, Theme.dim)
    w.time:SetPoint("TOPLEFT", 0, -7)
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetSize(16, 16)
    w.icon:SetPoint("TOPLEFT", 40, -4)
    w.text = Text(w, 12)
    w.text:SetPoint("TOPLEFT", 64, -6)
    w.text:SetWidth(ROW_W - 64)
    w.text:SetWordWrap(true)
    w.sub = Text(w, 10, Theme.dim)
    w.sub:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -2)
    return w
end

-- One chapter of the journey: both characters' class icons, names, level
-- range and a few numbers. Clicking filters the whole window to it.
function factories.pair(parent)
    local w = CreateFrame("Button", nil, parent)
    w:SetSize(ROW_W, 42)
    w.hl = Solid(w, "BACKGROUND", Theme.hover)
    w.hl:SetAllPoints()
    w.hl:Hide()
    w.sel = Solid(w, "ARTWORK", Theme.accent)
    w.sel:SetPoint("TOPLEFT")
    w.sel:SetPoint("BOTTOMLEFT")
    w.sel:SetWidth(2)
    w.a = w:CreateTexture(nil, "ARTWORK", nil, 1)
    w.a:SetSize(24, 24)
    w.a:SetPoint("LEFT", 8, 0)
    Circle(w.a)
    local gap = Solid(w, "ARTWORK", Theme.bg)
    gap:SetDrawLayer("ARTWORK", 2)
    gap:SetSize(28, 28)
    gap:SetPoint("LEFT", 22, 0)
    Circle(gap)
    w.b = w:CreateTexture(nil, "ARTWORK", nil, 3)
    w.b:SetSize(24, 24)
    w.b:SetPoint("LEFT", 24, 0)
    Circle(w.b)
    w.value = Text(w, 12, Theme.text, "RIGHT")
    w.value:SetPoint("TOPRIGHT", -4, -7)
    w.since = Text(w, 10, Theme.dim, "RIGHT")
    w.since:SetPoint("TOPRIGHT", w.value, "BOTTOMRIGHT", 0, -4)
    w.name = Text(w, 12)
    w.name:SetPoint("TOPLEFT", 60, -7)
    w.name:SetPoint("RIGHT", w, "RIGHT", -96, 0)
    w.sub = Text(w, 10, Theme.dim)
    w.sub:SetPoint("TOPLEFT", w.name, "BOTTOMLEFT", 0, -4)
    w.sub:SetPoint("RIGHT", w, "RIGHT", -96, 0)
    HookTooltip(w)
    return w
end

function factories.qbar(parent)
    local w = CreateFrame("Frame", nil, parent)
    w:SetSize(ROW_W, 16)
    w.segs = {}
    for q = 0, 5 do
        w.segs[q] = w:CreateTexture(nil, "ARTWORK")
        w.segs[q]:SetHeight(6)
    end
    return w
end

function factories.chip(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(86, 20)
    b.bg = Solid(b, "BACKGROUND", Theme.panel)
    b.bg:SetAllPoints()
    b.edge = Solid(b, "ARTWORK", Theme.accent)
    b.edge:SetPoint("BOTTOMLEFT")
    b.edge:SetPoint("BOTTOMRIGHT")
    b.edge:SetHeight(1)
    b.text = Text(b, 11, Theme.dim, "CENTER")
    b.text:SetPoint("CENTER", 0, 1)
    return b
end

local pools = {}

function UI:Acquire(kind)
    local pool = pools[kind]
    if not pool then
        pool = { free = {}, used = {} }
        pools[kind] = pool
    end
    local w = table.remove(pool.free) or factories[kind](self.child)
    pool.used[#pool.used + 1] = w
    w.tooltip = nil
    if w.hl then w.hl:Hide() end
    w:Show()
    return w
end

function UI:ReleaseAll()
    for _, pool in pairs(pools) do
        for i = #pool.used, 1, -1 do
            local w = pool.used[i]
            w:Hide()
            w:ClearAllPoints()
            pool.free[#pool.free + 1] = w
            pool.used[i] = nil
        end
    end
end

function UI:Place(w, y, gap)
    y = y + (gap or 0)
    w:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
    return y + w:GetHeight()
end

--------------------------------------------------------------------------------
-- Layout building blocks
--------------------------------------------------------------------------------

function UI:Section(y, title)
    local w = self:Acquire("section")
    w.label:SetText(title:upper())
    return self:Place(w, y, y > 0 and 10 or 0)
end

function UI:Tiles(y, tiles)
    local gap = 8
    local width = (ROW_W - gap * 2) / 3
    for i, t in ipairs(tiles) do
        local tile = self:Acquire("tile")
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        tile:SetSize(width, 58)
        tile:SetPoint("TOPLEFT", self.child, "TOPLEFT", col * (width + gap), -(y + row * (58 + gap)))
        KF.SetIcon(tile.icon, t.icon)
        tile.value:SetText(t.value)
        tile.label:SetText(t.label)
        tile.tooltip = t.tooltip
    end
    local rows = math.ceil(#tiles / 3)
    return y + rows * 58 + (rows - 1) * gap
end

function UI:Row(y, o)
    local r = self:Acquire("row")
    if o.swatch then
        r.icon:SetSize(10, 10)
        r.icon:SetTexCoord(0, 1, 0, 1)
        r.icon:SetColorTexture(o.swatch[1], o.swatch[2], o.swatch[3], 1)
        r.icon:SetPoint("LEFT", 4, 1)
    else
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 0, 1)
        KF.SetIcon(r.icon, o.icon)
    end
    r.label:SetText(o.label or "")
    r.detail:SetText(o.detail or "")
    r.value:SetText(o.value or "")
    if o.fraction then
        local c = o.color or Theme.accent
        r.bar:SetColorTexture(c[1], c[2], c[3], 0.85)
        r.bar:SetWidth(math.max(1, (ROW_W - 26) * math.min(1, o.fraction)))
        r.bar:Show()
        r.barBg:Show()
    else
        r.bar:Hide()
        r.barBg:Hide()
    end
    r.tooltip = o.tooltip
    return self:Place(r, y)
end

function UI:Line(y, left, right)
    local w = self:Acquire("line")
    w.left:SetText(left)
    w.right:SetText(right)
    return self:Place(w, y)
end

function UI:Note(y, text)
    local w = self:Acquire("note")
    w.text:SetText(text)
    w:SetHeight(w.text:GetStringHeight() + 10)
    return self:Place(w, y)
end

function UI:Split(y, title, a, b, nameA, classA, nameB, classB)
    local w = self:Acquire("split")
    a, b = a or 0, b or 0
    w.title:SetText(title)
    w.left:SetText(KF.ClassText(nameA, classA) .. "   " .. FN(a))
    w.right:SetText(FN(b) .. "   " .. KF.ClassText(nameB, classB))
    local total = a + b
    local share = total > 0 and a / total or 0.5
    local usable = ROW_W - 2
    w.a:SetWidth(math.max(0.1, usable * share))
    w.b:SetWidth(math.max(0.1, usable * (1 - share)))
    local r, g, bl = KF.ClassColor(classA)
    w.a:SetColorTexture(r, g, bl, 0.9)
    r, g, bl = KF.ClassColor(classB)
    w.b:SetColorTexture(r, g, bl, 0.9)
    return self:Place(w, y, 2)
end

local CRIT_COLOR = { 1, 0.74, 0.2 }

function UI:Record(y, title, a, b, nameA, classA, nameB, classB, multi, color)
    local w = self:Acquire("record")
    w.title:SetText(title)
    local function fill(side, rec, name, class)
        local label = KF.ClassText(name, class)
        if rec and multi and rec.ch then label = label .. KF.Colorize("  " .. rec.ch, rgb(Theme.dim)) end
        side.name:SetText(label)
        if rec then
            side.amount:SetText(KF.Colorize(FN(rec.n), rgb(color or Theme.text)))
            side.sub:SetText((rec.s or "Melee") .. (rec.d and (" on " .. rec.d) or "") .. "  ·  " .. date("%d %b", rec.t))
        else
            side.amount:SetText(KF.Colorize("-", rgb(Theme.dim)))
            side.sub:SetText("no record yet")
        end
    end
    fill(w.left, a, nameA, classA)
    fill(w.right, b, nameB, classB)
    return self:Place(w, y, 2)
end

function UI:QualityBar(y, s)
    local w = self:Acquire("qbar")
    local total = sum(s.lootMe) + sum(s.lootPartner)
    local x = 0
    for q = 0, 5 do
        local seg = w.segs[q]
        local n = (s.lootMe[q] or 0) + (s.lootPartner[q] or 0)
        seg:ClearAllPoints()
        if total > 0 and n > 0 then
            local width = math.max(2, (ROW_W - 6) * n / total)
            local _, r, g, b = KF.QualityInfo(q)
            seg:SetColorTexture(r, g, b, 0.9)
            seg:SetPoint("TOPLEFT", x, -4)
            seg:SetWidth(width)
            seg:Show()
            x = x + width + 1
        else
            seg:Hide()
        end
    end
    return self:Place(w, y)
end

--------------------------------------------------------------------------------
-- Which journey and which characters are on screen
--------------------------------------------------------------------------------

function UI:ViewedJourney()
    return (self.viewId and KF.db.journeys[self.viewId]) or KF.journey
end

function UI:ViewStats(j)
    local pair = self.scope and j.pairs[self.scope]
    return pair and pair.stats or j.total
end

function UI:PartnerDisplay(j)
    local p = KF.partner
    if p and p.journey == j then
        return p.name, p.class, call(UnitLevel, p.unit) or p.level, p.unit
    end
    local key = j.lastPartnerChar
    if not (key and j.chars.partner[key]) then key = next(j.chars.partner) end
    local info = key and j.chars.partner[key] or {}
    return key and ShortName(key) or j.partnerName or "?", info.class, info.level
end

-- Names for the two sides: character names when one chapter is selected,
-- "You" and your friend's name for the whole journey.
function UI:Names(j)
    local pair = self.scope and j.pairs[self.scope]
    if pair then return ShortName(pair.me), pair.meClass, ShortName(pair.partner), pair.partnerClass end
    local pName, pClass = self:PartnerDisplay(j)
    return "You", KF.me.class, j.partnerName or pName, pClass
end

local function PairLabel(pair, plain)
    if plain then return ShortName(pair.me) .. " & " .. ShortName(pair.partner) end
    return KF.ClassText(ShortName(pair.me), pair.meClass) .. " & " .. KF.ClassText(ShortName(pair.partner), pair.partnerClass)
end

-- Tooltip lines saying which chapters an entry comes from.
local function AddBreakdown(tt, j, by, fmt)
    if not by then return end
    tt:AddLine(" ")
    for key, n in pairs(by) do
        local pair = j.pairs[key]
        if pair then tt:AddDoubleLine(PairLabel(pair), fmt and fmt(n) or FN(n), 1, 1, 1, 1, 1, 1) end
    end
end

-- The lists for what's on screen: one chapter, or all chapters merged.
-- Merged entries remember which chapters they came from (`by`).
function UI:Lists(j)
    local set = j.pairs
    if self.scope and j.pairs[self.scope] then set = { [self.scope] = j.pairs[self.scope] } end
    local L = { mobs = {}, rares = {}, bosses = {}, dungeons = {}, runs = {}, zones = {}, items = {}, log = {} }
    L.multi = not self.scope and count(j.pairs) > 1
    L.records = { me = {}, partner = {} }

    for key, p in pairs(set) do
        for id, e in pairs(p.mobs) do
            local m = L.mobs[id]
            if not m then m = { n = e.n, c = 0, ty = e.ty }; L.mobs[id] = m end
            m.c, m.n = m.c + (e.c or 0), m.n or e.n
            if (e.lv or 0) > (m.lv or 0) then m.lv = e.lv end
        end
        for id, e in pairs(p.rares) do
            local r = L.rares[id]
            if not r then r = { n = e.n, c = 0, t = e.t, lv = e.lv, by = {} }; L.rares[id] = r end
            r.c, r.t = r.c + (e.c or 0), math.min(r.t or e.t or 0, e.t or r.t or 0)
            r.by[key] = e.c
        end
        for name, e in pairs(p.bosses) do
            local b = L.bosses[name]
            if not b then b = { c = 0, t = e.t, by = {} }; L.bosses[name] = b end
            b.c, b.t = b.c + (e.c or 0), math.min(b.t or e.t or 0, e.t or b.t or 0)
            b.by[key] = e.c
        end
        for id, e in pairs(p.dungeons) do
            local d = L.dungeons[id]
            if not d then d = { n = e.n, runs = 0, time = 0, bosses = 0, last = 0, by = {} }; L.dungeons[id] = d end
            d.runs, d.time, d.bosses = d.runs + (e.runs or 0), d.time + (e.time or 0), d.bosses + (e.bosses or 0)
            d.last, d.n = math.max(d.last, e.last or 0), d.n or e.n
            d.by[key] = e.runs
        end
        for _, r in ipairs(p.runs) do L.runs[#L.runs + 1] = { r = r, pair = key } end
        for zone, t in pairs(p.zones) do
            if not L.zones[zone] or t < L.zones[zone] then L.zones[zone] = t end
        end
        for id, e in pairs(p.items) do
            local it = L.items[id]
            if not it then it = { n = e.n, q = e.q, c = 0, me = 0, pa = 0, t = e.t, l = 0, by = {} }; L.items[id] = it end
            it.c, it.me, it.pa = it.c + (e.c or 0), it.me + (e.me or 0), it.pa + (e.pa or 0)
            it.t, it.l = math.min(it.t or e.t or 0, e.t or it.t or 0), math.max(it.l, e.l or e.t or 0)
            it.by[key] = e.c
        end
        for i, e in ipairs(p.log) do L.log[#L.log + 1] = { e = e, pair = key, i = i } end
        for _, who in ipairs({ "me", "partner" }) do
            for _, kind in ipairs({ "hit", "crit" }) do
                local r = p.records and p.records[who] and p.records[who][kind]
                local best = L.records[who][kind]
                if r and (not best or r.n > best.n) then L.records[who][kind] = r end
            end
        end
        local tough = p.toughest
        if tough and tough.n and (tough.lv or 0) > ((L.toughest and L.toughest.lv) or 0) then L.toughest = tough end
    end

    table.sort(L.runs, function(a, b) return (a.r.start or 0) > (b.r.start or 0) end)
    table.sort(L.log, function(a, b)
        if a.e.t ~= b.e.t then return a.e.t < b.e.t end
        if a.pair ~= b.pair then return a.pair < b.pair end
        return a.i < b.i
    end)
    return L
end

local function status(j)
    if j.id:find("^demo:") then return "Demo journey", Theme.accent2 end
    local p = KF.partner
    if p and p.journey == j then
        if KF.together then return "Together", Theme.good end
        return "Apart, paused", AMBER
    end
    return "Not grouped", Theme.dim
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------

function UI:BuildWelcome(y)
    y = self:Section(y, "Welcome")
    y = self:Note(y, "|cffffffffYour journey starts with a friend.|r\n\n" ..
        "1.  Group up with your friend.\n" ..
        "2.  Accept the Krakenfriends prompt, or target them and type |cff4fd1c5/kf partner|r.\n" ..
        "3.  Play! Kills, loot, gold, dungeons and more are counted whenever you two are together.\n\n" ..
        "Both of you can install Krakenfriends. Each keeps their own journal, and your alts are " ..
        "linked automatically through Battle.net.\n\n" ..
        "Curious what it looks like? Type |cff4fd1c5/kf demo|r.")
    return y
end

-- The chapters of this journey, newest first. Clicking one filters the window.
function UI:BuildCharacters(y, j)
    local list = {}
    for key, pair in pairs(j.pairs) do list[#list + 1] = { key = key, pair = pair } end
    if #list == 0 then return y end
    table.sort(list, function(a, b) return (a.pair.last or 0) > (b.pair.last or 0) end)
    local p = KF.partner
    local live = p and p.journey == j and (KF.me.key .. " & " .. p.key)

    y = self:Section(y, "Characters")
    for _, e in ipairs(list) do
        local w = self:Acquire("pair")
        local pair, s, key = e.pair, e.pair.stats, e.key
        SetClassIcon(w.a, pair.meClass)
        SetClassIcon(w.b, pair.partnerClass)
        w.name:SetText(PairLabel(pair))
        local bits = {}
        if pair.lvMin then
            bits[#bits + 1] = pair.lvMin == pair.lvMax and ("level %d"):format(pair.lvMax) or ("level %d-%d"):format(pair.lvMin, pair.lvMax)
        end
        bits[#bits + 1] = FN(s.kills) .. " kills"
        bits[#bits + 1] = FN(s.runs) .. (s.runs == 1 and " run" or " runs")
        w.sub:SetText(table.concat(bits, "  ·  "))
        w.value:SetText(KF.FormatDuration(s.time))
        if key == live and KF.together then
            w.since:SetText(KF.Colorize("playing now", rgb(Theme.good)))
        else
            w.since:SetText("since " .. date("%d %b", pair.started or j.started))
        end
        local selected = self.scope == key
        w.sel:SetShown(selected)
        w.tooltip = selected and "Click to show all characters again." or "Click to show only this pair of characters."
        w:SetScript("OnClick", function()
            UI.scope = (UI.scope ~= key) and key or nil
            UI:Refresh()
        end)
        y = self:Place(w, y)
    end
    return y
end

function UI:BuildOverview(y, j, s, L)
    local nameA, classA, nameB, classB = self:Names(j)
    y = self:Tiles(y, {
        { icon = "kills", value = FN(s.kills), label = "Kills",
          tooltip = function(tt)
              tt:AddLine("Kills together")
              tt:AddDoubleLine("Elites", FN(s.elite), 0.7, 0.7, 0.7, 1, 1, 1)
              tt:AddDoubleLine("Players", FN(s.types.player or 0), 0.7, 0.7, 0.7, 1, 1, 1)
          end },
        { icon = "rare", value = FN(s.rare), label = "Rares" },
        { icon = "boss", value = FN(s.boss), label = "Bosses" },
        { icon = "dungeon", value = FN(s.runs), label = "Dungeon runs" },
        { icon = "gold", value = KF.FormatMoney(s.goldDuo, true), label = "Gold looted",
          tooltip = function(tt)
              tt:AddLine("Gold looted together")
              tt:AddLine(KF.FormatMoney(s.goldDuo), 1, 1, 1)
              tt:AddDoubleLine("Your share", KF.FormatMoney(s.goldMe), 0.7, 0.7, 0.7, 1, 1, 1)
              tt:AddLine("Shared loot is split evenly, so the duo total counts both shares.", 0.6, 0.6, 0.6, true)
          end },
        { icon = "epic", value = FN(KF.CountEpics(s)), label = "Epics found" },
    })

    y = self:BuildCharacters(y, j)

    y = self:Section(y, "Rivalry")
    y = self:Split(y, "Killing blows", s.kbMe, s.kbPartner, nameA, classA, nameB, classB)
    y = self:Split(y, "Items looted", sum(s.lootMe), sum(s.lootPartner), nameA, classA, nameB, classB)
    y = self:Split(y, "Deaths", s.deathsMe, s.deathsPartner, nameA, classA, nameB, classB)

    local rm, rp = L.records.me, L.records.partner
    if rm.hit or rm.crit or rp.hit or rp.crit then
        y = self:Section(y, "Records")
        y = self:Record(y, "Biggest crit", rm.crit, rp.crit, nameA, classA, nameB, classB, L.multi, CRIT_COLOR)
        y = self:Record(y, "Biggest hit", rm.hit, rp.hit, nameA, classA, nameB, classB, L.multi)
    end

    y = self:Section(y, "Trivia")
    y = self:Line(y, "Time together", KF.FormatDuration(s.time))
    y = self:Line(y, "Quests completed", FN(s.quests))
    y = self:Line(y, "Levels gained together", ("%s +%d  ·  %s +%d"):format(nameA, s.levelsMe, nameB, s.levelsPartner))
    y = self:Line(y, "Zones explored", FN(count(L.zones)))

    local top
    for _, m in pairs(L.mobs) do
        if m.n and (not top or m.c > top.c) then top = m end
    end
    if top then y = self:Line(y, "Most hunted", ("%s  (%s)"):format(top.n, FN(top.c))) end
    if L.toughest then
        y = self:Line(y, "Toughest foe", ("%s  (level %d)"):format(L.toughest.n, L.toughest.lv))
    end
    local fav
    for _, d in pairs(L.dungeons) do
        if not fav or d.runs > fav.runs then fav = d end
    end
    if fav then y = self:Line(y, "Favorite dungeon", ("%s  (%d %s)"):format(fav.n or "?", fav.runs, fav.runs == 1 and "run" or "runs")) end
    if (s.types.critter or 0) > 0 then y = self:Line(y, "Critters harmed", FN(s.types.critter)) end
    local pair = self.scope and j.pairs[self.scope]
    y = self:Line(y, pair and "Pair started" or "Journey began", date("%d %B %Y", pair and pair.started or j.started))
    return y
end

function UI:BuildBestiary(y, j, s, L)
    y = self:Section(y, "Creature types")
    local types = {}
    for key, n in pairs(s.types) do
        if n > 0 then types[#types + 1] = { key = key, n = n } end
    end
    table.sort(types, function(a, b) return a.n > b.n end)
    if #types == 0 then y = self:Note(y, "No kills yet. Go get 'em!") end
    local max = types[1] and types[1].n or 1
    for _, e in ipairs(types) do
        local info = KF.TypeInfo[e.key] or KF.TypeInfo.unknown
        y = self:Row(y, { icon = info.icon, label = info.label, value = FN(e.n), fraction = e.n / max,
            detail = s.kills > 0 and ("%d%%"):format(math.floor(e.n / s.kills * 100 + 0.5)) or nil })
    end

    y = self:Section(y, "By rank")
    local kills = math.max(1, s.kills)
    y = self:Row(y, { icon = "elite", label = "Elites", value = FN(s.elite), fraction = s.elite / kills, color = { 1, 0.82, 0 } })
    y = self:Row(y, { icon = "rare", label = "Rares", value = FN(s.rare), fraction = s.rare / kills, color = { 0.75, 0.78, 0.85 } })
    y = self:Row(y, { icon = "boss", label = "Bosses", value = FN(s.boss), fraction = s.boss / kills, color = { 0.95, 0.35, 0.35 } })

    local mobs = {}
    for _, m in pairs(L.mobs) do
        if m.n then mobs[#mobs + 1] = m end
    end
    if #mobs > 0 then
        table.sort(mobs, function(a, b) return a.c > b.c end)
        y = self:Section(y, "Most hunted")
        for i = 1, math.min(10, #mobs) do
            local m = mobs[i]
            local info = KF.TypeInfo[m.ty] or KF.TypeInfo.unknown
            y = self:Row(y, { icon = info.icon, label = m.n, value = FN(m.c), fraction = m.c / mobs[1].c,
                detail = m.lv and m.lv > 0 and ("level %d"):format(m.lv) or nil, color = Theme.accent2 })
        end
    end

    local rares = {}
    for _, r in pairs(L.rares) do rares[#rares + 1] = r end
    if #rares > 0 then
        table.sort(rares, function(a, b) return (a.t or 0) > (b.t or 0) end)
        y = self:Section(y, "Rares slain")
        for _, r in ipairs(rares) do
            y = self:Row(y, { icon = "rare", label = r.n or "?", value = date("%d %b", r.t),
                detail = r.c > 1 and ("%d×"):format(r.c) or (r.lv and r.lv > 0 and ("level %d"):format(r.lv)) or nil,
                tooltip = L.multi and function(tt)
                    tt:AddLine(r.n or "Rare")
                    AddBreakdown(tt, j, r.by, function(n) return n .. "×" end)
                end or nil })
        end
    end
    return y
end

function UI:BuildLoot(y, j, s, L)
    local nameA, _, nameB = self:Names(j)
    y = self:Tiles(y, {
        { icon = "gold", value = KF.FormatMoney(s.goldDuo, true), label = "Gold together",
          tooltip = function(tt) tt:AddLine(KF.FormatMoney(s.goldDuo), 1, 1, 1) end },
        { icon = "gold", value = KF.FormatMoney(s.goldMe, true), label = "Your share",
          tooltip = function(tt) tt:AddLine(KF.FormatMoney(s.goldMe), 1, 1, 1) end },
        { icon = "loot", value = FN(sum(s.lootMe) + sum(s.lootPartner)), label = "Items looted" },
    })

    y = self:Section(y, "By quality")
    y = self:QualityBar(y, s)
    for q = 5, 0, -1 do
        local a, b = s.lootMe[q] or 0, s.lootPartner[q] or 0
        if a + b > 0 or (q >= 2 and q <= 4) then
            local label, r, g, bl = KF.QualityInfo(q)
            y = self:Row(y, { swatch = { r, g, bl }, label = KF.Colorize(label, r, g, bl), value = FN(a + b),
                detail = ("%s %s  ·  %s %s"):format(nameA, FN(a), nameB, FN(b)) })
        end
    end

    -- notable finds, filterable by quality
    self.lootFilter = self.lootFilter or { [2] = false, [3] = true, [4] = true }
    y = self:Section(y, "Notable finds")
    local chips = { { 2, "Uncommon" }, { 3, "Rare" }, { 4, "Epic+" } }
    for i, c in ipairs(chips) do
        local chip = self:Acquire("chip")
        local q, on = c[1], self.lootFilter[c[1]]
        local _, r, g, bl = KF.QualityInfo(q)
        chip.text:SetText(c[2])
        chip.text:SetTextColor(on and r or 0.5, on and g or 0.5, on and bl or 0.5)
        chip.edge:SetColorTexture(r, g, bl, on and 0.9 or 0)
        chip:SetPoint("TOPLEFT", self.child, "TOPLEFT", (i - 1) * 92, -(y + 4))
        chip:SetScript("OnClick", function()
            UI.lootFilter[q] = not UI.lootFilter[q]
            UI:Refresh()
        end)
    end
    y = y + 30

    local items = {}
    for id, it in pairs(L.items) do
        if self.lootFilter[math.min(it.q or 2, 4)] then items[#items + 1] = { id = id, it = it } end
    end
    table.sort(items, function(a, b) return (a.it.l or 0) > (b.it.l or 0) end)
    if #items == 0 then y = self:Note(y, "Nothing here yet. Adventure awaits!") end
    for i = 1, math.min(60, #items) do
        local id, it = items[i].id, items[i].it
        local _, r, g, bl = KF.QualityInfo(it.q or 2)
        local who = {}
        if it.me > 0 then who[#who + 1] = nameA .. (it.me > 1 and (" ×" .. it.me) or "") end
        if it.pa > 0 then who[#who + 1] = nameB .. (it.pa > 1 and (" ×" .. it.pa) or "") end
        local iconID = C_Item and call(C_Item.GetItemIconByID, id)
        y = self:Row(y, {
            icon = iconID and { files = { iconID } } or "unknown",
            label = KF.Colorize(it.n or ("item " .. id), r, g, bl),
            detail = table.concat(who, "  ·  "),
            value = date("%d %b", it.l ~= 0 and it.l or it.t),
            tooltip = function(tt)
                if tt.SetItemByID then tt:SetItemByID(id) else tt:AddLine(it.n or "?") end
                if L.multi then AddBreakdown(tt, j, it.by, function(n) return n .. "×" end) end
            end,
        })
    end
    return y
end

function UI:BuildDungeons(y, j, s, L)
    local run = j.currentRun
    if run and self.scope and run.pair ~= self.scope then run = nil end
    local inside = 0
    for _, d in pairs(L.dungeons) do inside = inside + d.time end
    if run then inside = inside + math.max(0, (run.last or run.start) - run.start) end

    y = self:Tiles(y, {
        { icon = "dungeon", value = FN(s.runs), label = "Runs" },
        { icon = "boss", value = FN(s.boss), label = "Bosses" },
        { icon = "time", value = KF.FormatDuration(inside), label = "Time inside" },
    })

    if run then
        y = self:Section(y, "Current run")
        y = self:Row(y, { icon = "dungeon", label = run.n or "?", value = KF.FormatDuration(time() - run.start),
            detail = ("%d kills  ·  %d bosses"):format(run.kills or 0, run.bosses or 0) })
    end

    local dungeons = {}
    for _, d in pairs(L.dungeons) do dungeons[#dungeons + 1] = d end
    table.sort(dungeons, function(a, b) return a.runs > b.runs end)
    y = self:Section(y, "Dungeons")
    if #dungeons == 0 then y = self:Note(y, "No dungeons yet. The Deadmines won't clear themselves.") end
    for _, d in ipairs(dungeons) do
        y = self:Row(y, { icon = "dungeon", label = d.n or "?", value = ("%d %s"):format(d.runs, d.runs == 1 and "run" or "runs"),
            detail = ("%d bosses  ·  %s"):format(d.bosses, KF.FormatDuration(d.time)),
            fraction = d.runs / math.max(1, dungeons[1].runs), color = Theme.accent2,
            tooltip = L.multi and function(tt)
                tt:AddLine(d.n or "Dungeon")
                AddBreakdown(tt, j, d.by, function(n) return n .. (n == 1 and " run" or " runs") end)
            end or nil })
    end

    if #L.runs > 0 then
        y = self:Section(y, "Recent runs")
        for i = 1, math.min(12, #L.runs) do
            local r, pair = L.runs[i].r, j.pairs[L.runs[i].pair]
            y = self:Row(y, { icon = "dungeon", label = r.n or "?", value = date("%d %b", r.start),
                detail = ("%s  ·  %d kills  ·  %d bosses"):format(KF.FormatDuration(r.dur), r.kills or 0, r.bosses or 0),
                tooltip = function(tt)
                    tt:AddLine(r.n or "Dungeon run")
                    if pair then tt:AddLine(PairLabel(pair)) end
                    tt:AddDoubleLine("Started", date("%d %b %H:%M", r.start), 0.7, 0.7, 0.7, 1, 1, 1)
                    tt:AddDoubleLine("Deaths", FN(r.deaths or 0), 0.7, 0.7, 0.7, 1, 1, 1)
                end })
        end
    end

    local bosses = {}
    for name, b in pairs(L.bosses) do bosses[#bosses + 1] = { name = name, b = b } end
    if #bosses > 0 then
        table.sort(bosses, function(a, b) return (a.b.t or 0) > (b.b.t or 0) end)
        y = self:Section(y, "Bosses defeated")
        for _, e in ipairs(bosses) do
            y = self:Row(y, { icon = "boss", label = e.name, value = ("%d×"):format(e.b.c), detail = "first " .. date("%d %b", e.b.t),
                tooltip = L.multi and function(tt)
                    tt:AddLine(e.name)
                    AddBreakdown(tt, j, e.b.by, function(n) return n .. "×" end)
                end or nil })
        end
    end
    return y
end

function UI:BuildJournal(y, j, _, L)
    local log = L.log
    if #log == 0 then return self:Note(y, "Your story will be written here: first kills, rares, bosses, epic loot, new zones and milestones.") end
    local today, lastDay = date("%Y%m%d"), nil
    local yesterday = date("%Y%m%d", time() - 86400)
    for i = #log, math.max(1, #log - 200), -1 do
        local e, pair = log[i].e, j.pairs[log[i].pair]
        local day = date("%Y%m%d", e.t)
        if day ~= lastDay then
            lastDay = day
            y = self:Section(y, day == today and "Today" or day == yesterday and "Yesterday" or date("%A, %d %B", e.t))
        end
        local w = self:Acquire("log")
        w.time:SetText(date("%H:%M", e.t))
        KF.SetIcon(w.icon, LOG_ICONS[e.k] or "milestone")
        w.text:SetText(e.x)
        local height = w.text:GetStringHeight() + 12
        -- with several character pairs, say which one each entry belongs to
        if L.multi and pair then
            w.sub:SetText(PairLabel(pair, true))
            w.sub:Show()
            height = height + 12
        else
            w.sub:Hide()
        end
        w:SetHeight(math.max(24, height))
        y = self:Place(w, y)
    end
    return y
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local function CreateCard(parent, side)
    local card = {}
    card.ring = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    card.ring:SetSize(44, 44)
    card.ring:SetPoint(side, 0, 0)
    card.ring:SetColorTexture(1, 1, 1, 1)
    Circle(card.ring)
    card.portrait = parent:CreateTexture(nil, "ARTWORK", nil, 2)
    card.portrait:SetSize(38, 38)
    card.portrait:SetPoint("CENTER", card.ring)
    Circle(card.portrait)
    card.name = Text(parent, 14, nil, side)
    card.name:SetWidth(135)
    card.sub = Text(parent, 11, Theme.dim, side)
    card.sub:SetWidth(135)
    if side == "LEFT" then
        card.name:SetPoint("TOPLEFT", card.ring, "TOPRIGHT", 10, -6)
        card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
    else
        card.name:SetPoint("TOPRIGHT", card.ring, "TOPLEFT", -10, -6)
        card.sub:SetPoint("TOPRIGHT", card.name, "BOTTOMRIGHT", 0, -4)
    end
    return card
end

local function FillCard(card, name, class, level, unit, withPortrait)
    local r, g, b = KF.ClassColor(class)
    card.ring:SetColorTexture(r, g, b, 0.9)
    card.name:SetText(name or "?")
    card.name:SetTextColor(r, g, b)
    local sub = ClassName(class)
    if level and level > 0 then sub = ("Level %d %s"):format(level, sub) end
    card.sub:SetText(sub)
    if withPortrait then SetPortrait(card.portrait, unit, class) end
end

function UI:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "KrakenfriendsFrame", UIParent)
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
        KF.db.settings.window = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    f:SetScript("OnShow", function()
        UI:Refresh()
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
    end)
    f:SetScript("OnHide", function()
        if UI.menu then UI.menu:Hide() end
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
    end)
    f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "KrakenfriendsFrame") end

    local pos = KF.db.settings.window
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER")
    end

    -- backdrop: deep panel, faint teal glow at the top, teal-to-violet rim
    local bg = Solid(f, "BACKGROUND", Theme.bg)
    bg:SetAllPoints()
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("TOPRIGHT", -1, -1)
    glow:SetHeight(130)
    Gradient(glow, "VERTICAL", Theme.accent, 0, Theme.accent, 0.09)
    Border(f, Theme.line, 0.10)
    local rim = f:CreateTexture(nil, "ARTWORK")
    rim:SetPoint("TOPLEFT", 1, -1)
    rim:SetPoint("TOPRIGHT", -1, -1)
    rim:SetHeight(2)
    Gradient(rim, "HORIZONTAL", Theme.accent, 1, Theme.accent2, 1)

    -- close
    local close = CreateFrame("Button", nil, f)
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", -5, -6)
    local x = Strokes(close, 11, Theme.dim, { 45, -45 })
    close:SetScript("OnEnter", function() for _, s in ipairs(x) do s:SetColorTexture(1, 1, 1, 1) end end)
    close:SetScript("OnLeave", function() for _, s in ipairs(x) do s:SetColorTexture(Theme.dim[1], Theme.dim[2], Theme.dim[3], 1) end end)
    close:SetScript("OnClick", function() f:Hide() end)

    -- header: you & your partner
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", PAD, -22)
    header:SetPoint("TOPRIGHT", -PAD, -22)
    header:SetHeight(46)
    self.meCard = CreateCard(header, "LEFT")
    self.partnerCard = CreateCard(header, "RIGHT")
    local amp = Text(header, 20, Theme.accent, "CENTER")
    amp:SetPoint("CENTER", 0, 2)
    amp:SetText("&")

    -- status line + journey/character selector
    self.dot = f:CreateTexture(nil, "ARTWORK")
    self.dot:SetSize(7, 7)
    self.dot:SetPoint("TOPLEFT", PAD + 1, -82)
    self.dot:SetColorTexture(1, 1, 1, 1)
    Circle(self.dot)
    self.status = Text(f, 11, Theme.dim)
    self.status:SetPoint("LEFT", self.dot, "RIGHT", 6, 0)
    self.status:SetWidth(240)

    local scope = CreateFrame("Button", nil, f)
    scope:SetSize(160, 18)
    scope:SetPoint("TOPRIGHT", -PAD, -76)
    scope.text = Text(scope, 11, Theme.dim, "RIGHT")
    scope.text:SetPoint("RIGHT", -14, 0)
    scope.text:SetWidth(146)
    scope.chevron = Strokes(scope, 5, Theme.dim, { -45, 45 }, 1.7)
    for _, s in ipairs(scope.chevron) do s:ClearAllPoints() end
    scope.chevron[1]:SetPoint("RIGHT", scope, "RIGHT", -4.2, 0)
    scope.chevron[2]:SetPoint("RIGHT", scope, "RIGHT", -0.8, 0)
    scope:SetScript("OnClick", function(btn) UI:ToggleMenu(btn) end)
    scope:SetScript("OnEnter", function() scope.text:SetTextColor(rgb(Theme.text)) end)
    scope:SetScript("OnLeave", function() scope.text:SetTextColor(rgb(Theme.dim)) end)
    self.scopeButton = scope

    -- tabs
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", PAD, -100)
    tabBar:SetPoint("TOPRIGHT", -PAD, -100)
    tabBar:SetHeight(26)
    local base = Solid(tabBar, "BORDER", Theme.line)
    base:SetPoint("BOTTOMLEFT")
    base:SetPoint("BOTTOMRIGHT")
    base:SetHeight(1)
    self.tabs = {}
    local tabW = ROW_W / #TABS
    for i, def in ipairs(TABS) do
        local b = CreateFrame("Button", nil, tabBar)
        b:SetSize(tabW, 26)
        b:SetPoint("LEFT", (i - 1) * tabW, 0)
        b.text = Text(b, 12, Theme.dim, "CENTER")
        b.text:SetPoint("CENTER", 0, 1)
        b.text:SetText(def.label)
        b.underline = Solid(b, "ARTWORK", Theme.accent)
        b.underline:SetPoint("BOTTOMLEFT", 12, 0)
        b.underline:SetPoint("BOTTOMRIGHT", -12, 0)
        b.underline:SetHeight(2)
        b:SetScript("OnClick", function() UI:SelectTab(def.id) end)
        b:SetScript("OnEnter", function() if UI.tab ~= def.id then b.text:SetTextColor(rgb(Theme.text)) end end)
        b:SetScript("OnLeave", function() if UI.tab ~= def.id then b.text:SetTextColor(rgb(Theme.dim)) end end)
        self.tabs[def.id] = b
    end

    -- content
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", PAD, -CONTENT_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(ROW_W, 1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) UI:Scroll(-delta * 52) end)
    self.scroll, self.child = scroll, child

    self.track = Solid(f, "ARTWORK", Theme.line, 0.06)
    self.track:SetWidth(2)
    self.track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 7, 0)
    self.track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 7, 0)
    self.thumb = Solid(f, "OVERLAY", Theme.accent, 0.55)
    self.thumb:SetWidth(2)

    self:SelectTab(KF.db.settings.tab or "Overview", true)
end

function UI:Scroll(delta)
    local sf, child = self.scroll, self.child
    local height = sf:GetHeight()
    local max = math.max(0, child:GetHeight() - height)
    local v = math.min(max, math.max(0, sf:GetVerticalScroll() + delta))
    sf:SetVerticalScroll(v)
    if max <= 0 then
        self.thumb:Hide()
        self.track:Hide()
        return
    end
    self.thumb:Show()
    self.track:Show()
    local th = math.max(24, height * height / child:GetHeight())
    self.thumb:SetHeight(th)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 7, -(height - th) * (v / max))
end

function UI:SelectTab(id, silent)
    if not self.tabs[id] then id = "Overview" end
    self.tab = id
    KF.db.settings.tab = id
    for tid, b in pairs(self.tabs) do
        local on = tid == id
        b.underline:SetShown(on)
        b.text:SetTextColor(rgb(on and Theme.text or Theme.dim))
    end
    self.scroll:SetVerticalScroll(0)
    if not silent then
        if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        self:Refresh()
    end
end

function UI:RefreshHeader(j, withPortraits)
    local pair = j and self.scope and j.pairs[self.scope]
    if pair then
        -- a chapter is selected: show those two characters
        local p = KF.partner
        local meUnit = pair.me == KF.me.key and "player" or nil
        local pUnit = p and p.journey == j and p.key == pair.partner and p.unit or nil
        local mine, theirs = j.chars.me[pair.me] or {}, j.chars.partner[pair.partner] or {}
        FillCard(self.meCard, ShortName(pair.me), pair.meClass, meUnit and call(UnitLevel, "player") or mine.level, meUnit, withPortraits)
        FillCard(self.partnerCard, ShortName(pair.partner), pair.partnerClass, pUnit and call(UnitLevel, pUnit) or theirs.level, pUnit, withPortraits)
    else
        FillCard(self.meCard, KF.me.name, KF.me.class, call(UnitLevel, "player"), "player", withPortraits)
    end

    if not j then
        FillCard(self.partnerCard, "?", nil, nil, nil, withPortraits)
        self.partnerCard.sub:SetText("No partner yet")
        self.dot:SetColorTexture(Theme.dim[1], Theme.dim[2], Theme.dim[3], 1)
        self.status:SetText("Group up with a friend to begin")
        self.scopeButton:Hide()
        return
    end

    if not pair then
        local pName, pClass, pLevel, pUnit = self:PartnerDisplay(j)
        FillCard(self.partnerCard, pName, pClass, pLevel, pUnit, withPortraits)
    end

    local label, color = status(j)
    local s = self:ViewStats(j)
    local day = math.floor((time() - (j.started or time())) / 86400) + 1
    self.dot:SetColorTexture(color[1], color[2], color[3], 1)
    self.status:SetText(KF.Colorize(label, rgb(color)) .. ("   ·   Day %d   ·   %s"):format(day, KF.FormatDuration(s.time)))

    local scopeText = "All characters"
    if pair then
        scopeText = PairLabel(pair)
    elseif count(KF.db.journeys) > 1 then
        scopeText = (j.partnerName or "Journey") .. ": all characters"
    end
    self.scopeButton.text:SetText(scopeText)
    self.scopeButton:Show()
end

function UI:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    self.pending = false
    local j = self:ViewedJourney()
    if self.scope and not (j and j.pairs[self.scope]) then self.scope = nil end
    self:RefreshHeader(j, true)
    self:ReleaseAll()
    local y
    if not j then
        y = self:BuildWelcome(0)
    else
        y = self["Build" .. self.tab](self, 0, j, self:ViewStats(j), self:Lists(j))
    end
    self.child:SetHeight(math.max(1, y + 8))
    self:Scroll(0)
end

function UI:RequestRefresh()
    if self.pending or not (self.frame and self.frame:IsShown()) then return end
    self.pending = true
    C_Timer.After(0.25, function() UI:Refresh() end)
end

function UI:Show()
    self:Create()
    if self.frame:IsShown() then self:Refresh() else self.frame:Show() end
end

function UI:Toggle()
    self:Create()
    self.frame:SetShown(not self.frame:IsShown())
end

--------------------------------------------------------------------------------
-- Journey / character menu
--------------------------------------------------------------------------------

function UI:MenuEntries()
    local entries = {}
    local viewed = self:ViewedJourney()
    local journeys = {}
    for _, j in pairs(KF.db.journeys) do journeys[#journeys + 1] = j end
    table.sort(journeys, function(a, b) return (a.lastActive or 0) > (b.lastActive or 0) end)
    if #journeys > 1 then
        entries[#entries + 1] = { header = "Journeys" }
        for _, j in ipairs(journeys) do
            entries[#entries + 1] = { text = j.partnerName or j.id, checked = j == viewed,
                func = function() UI.viewId, UI.scope = j.id, nil end }
        end
    end
    if viewed then
        entries[#entries + 1] = { header = "Characters" }
        entries[#entries + 1] = { text = "All characters", checked = self.scope == nil, func = function() UI.scope = nil end }
        local keys = {}
        for key in pairs(viewed.pairs) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local pair = viewed.pairs[key]
            entries[#entries + 1] = {
                text = PairLabel(pair),
                checked = self.scope == key, func = function() UI.scope = key end,
            }
        end
    end
    return entries
end

function UI:ToggleMenu(anchor)
    if self.menu and self.menu:IsShown() then
        self.menu:Hide()
        return
    end
    if not self.menu then
        local m = CreateFrame("Frame", nil, self.frame)
        m:SetFrameStrata("DIALOG")
        m:SetClampedToScreen(true)
        m:EnableMouse(true)
        Solid(m, "BACKGROUND", { 0.035, 0.04, 0.055, 0.98 }):SetAllPoints()
        Border(m, Theme.line, 0.14)
        m.buttons = {}
        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("DIALOG")
        catcher:SetFrameLevel(1)
        catcher:SetScript("OnClick", function() m:Hide() end)
        catcher:Hide()
        m:SetScript("OnShow", function() catcher:Show() end)
        m:SetScript("OnHide", function() catcher:Hide() end)
        m:SetFrameLevel(catcher:GetFrameLevel() + 5)
        m:Hide()
        self.menu = m
    end

    local m = self.menu
    local entries = self:MenuEntries()
    for _, b in ipairs(m.buttons) do b:Hide() end
    local y = 6
    for i, e in ipairs(entries) do
        local b = m.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, m)
            b:SetHeight(20)
            b.hl = Solid(b, "BACKGROUND", Theme.hover)
            b.hl:SetAllPoints()
            b.hl:Hide()
            b.check = Solid(b, "ARTWORK", Theme.accent)
            b.check:SetSize(3, 12)
            b.check:SetPoint("LEFT", 6, 0)
            b.text = Text(b, 12)
            b.text:SetPoint("LEFT", 16, 0)
            b.text:SetPoint("RIGHT", -8, 0)
            b:SetScript("OnEnter", function(btn) if btn.func then btn.hl:Show() end end)
            b:SetScript("OnLeave", function(btn) btn.hl:Hide() end)
            b:SetScript("OnClick", function(btn)
                if not btn.func then return end
                btn.func()
                m:Hide()
                UI:Refresh()
            end)
            m.buttons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 1, -y)
        b:SetPoint("TOPRIGHT", -1, -y)
        b.func = e.func
        if e.header then
            b.text:SetFont(FONT, 10, "")
            b.text:SetTextColor(rgb(Theme.accent))
            b.text:SetText(e.header:upper())
            b.check:Hide()
        else
            b.text:SetFont(FONT, 12, "")
            b.text:SetTextColor(rgb(Theme.text))
            b.text:SetText(e.text)
            b.check:SetShown(e.checked)
        end
        b:Show()
        y = y + 20
    end
    m:SetSize(230, y + 6)
    m:ClearAllPoints()
    m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    m:Show()
end

--------------------------------------------------------------------------------

KF:Listen("UPDATE", function() UI:RequestRefresh() end)
KF:Listen("PARTNER", function() UI:RequestRefresh() end)
KF:Listen("TOGETHER", function() UI:RequestRefresh() end)
KF:Listen("TICK", function()
    if UI.frame and UI.frame:IsShown() then UI:RefreshHeader(UI:ViewedJourney(), false) end
end)
