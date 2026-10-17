local _, KR = ...
local call = KR.call
local T = KR.Theme

--------------------------------------------------------------------------------
-- Drawing helpers shared by the bar and the coach window, all in the game's
-- own look: gold borders, dark stone, the fantasy font for titles.
--------------------------------------------------------------------------------

local Wg = {}
KR.Widgets = Wg

Wg.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

function Wg.rgb(c) return c[1], c[2], c[3] end

-- the first file the client actually has (a missing file shows as a green square)
local fileCache = {}
function Wg.FirstFile(list)
    for _, path in ipairs(list) do
        local id = fileCache[path]
        if id == nil then
            id = (not GetFileIDFromPath) and true or (call(GetFileIDFromPath, path) or false)
            fileCache[path] = id
        end
        if id then return path end
    end
    return list[#list]
end

function Wg.Solid(parent, layer, color, alpha, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
    return t
end

function Wg.Text(parent, size, color, justify, outline)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(Wg.FONT, size or 12, outline or "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetTextColor(Wg.rgb(color or T.text))
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A title in the game's fantasy font and gold, with a fallback if the font is missing.
function Wg.Title(parent, size)
    local fs = Wg.Text(parent, size, T.gold)
    if not pcall(fs.SetFont, fs, KR.Files.titleFont, size, "") then fs:SetFont(Wg.FONT, size - 2, "") end
    return fs
end

-- The big look: dark stone inside the gold dialog border, drawn around `f`.
function Wg.DialogFrame(f)
    local frame = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetPoint("TOPLEFT", -7, 7)
    frame:SetPoint("BOTTOMRIGHT", 7, -7)
    frame:SetFrameLevel(math.max(0, f:GetFrameLevel()))
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = Wg.FirstFile(KR.Files.back), tile = true, tileSize = 256,
            edgeFile = Wg.FirstFile(KR.Files.edge), edgeSize = 32,
            insets = { left = 9, right = 9, top = 9, bottom = 9 },
        })
        frame:SetBackdropColor(0.55, 0.55, 0.55, 1)
    end
    return frame
end

-- The small look, for the bar and icons: dark stone with a thin gold edge.
function Wg.ThinFrame(f, pad)
    pad = pad or 3
    local frame = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetPoint("TOPLEFT", -pad, pad)
    frame:SetPoint("BOTTOMRIGHT", pad, -pad)
    frame:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = Wg.FirstFile(KR.Files.thinEdge), edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        frame:SetBackdropColor(T.stone[1], T.stone[2], T.stone[3], T.stone[4])
        frame:SetBackdropBorderColor(T.gold[1], T.gold[2], T.gold[3], 0.85)
    end
    return frame
end

function Wg.Icon(parent, size, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetSize(size, size)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return tex
end

function Wg.SetIcon(tex, file)
    if type(file) == "string" and not file:find("\\") then file = "Interface\\Icons\\" .. file end
    tex:SetTexture(file or "Interface\\Icons\\INV_Misc_QuestionMark")
end

-- An icon in a small square gold frame.
function Wg.FramedIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.icon = Wg.Icon(f, size - 2)
    f.icon:SetPoint("CENTER")
    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(T.gold[1], T.gold[2], T.gold[3], 0.9)
    f.edge = edge
    return f
end

-- A flat text button in the gold style (tabs, links).
function Wg.TextButton(parent, label, size)
    local b = CreateFrame("Button", nil, parent)
    b.text = Wg.Text(b, size or 12, T.dim, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetSize(math.max(40, (b.text:GetStringWidth() or 40) + 16), (size or 12) + 10)
    b.hl = Wg.Solid(b, "BACKGROUND", T.hover)
    b.hl:SetAllPoints()
    b.hl:Hide()
    b:SetScript("OnEnter", function() b.hl:Show() end)
    b:SetScript("OnLeave", function() b.hl:Hide() end)
    function b:SetActive(on)
        self.active = on
        self.text:SetTextColor(Wg.rgb(on and T.gold or T.dim))
    end
    return b
end

-- A tick box with a label. `get` and `set` read and write the setting.
function Wg.Check(parent, label, get, set, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb.label = Wg.Text(cb, 12, T.text)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label)
    cb:SetScript("OnShow", function(self) self:SetChecked(get() and true or false) end)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        KR:Fire("SETTINGS")
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    cb:SetChecked(get() and true or false)
    return cb
end

-- A thin horizontal meter (0..1) in a colour.
function Wg.Meter(parent, w, h)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(w, h)
    m.bg = Wg.Solid(m, "BACKGROUND", { 0, 0, 0 }, 0.5)
    m.bg:SetAllPoints()
    m.fill = Wg.Solid(m, "ARTWORK", T.gold)
    m.fill:SetPoint("TOPLEFT")
    m.fill:SetPoint("BOTTOMLEFT")
    m.fill:SetWidth(1)
    function m:Set(v, color)
        v = math.max(0, math.min(1, v or 0))
        self.fill:SetWidth(math.max(1, w * v))
        self.fill:SetShown(v > 0)
        if color then self.fill:SetColorTexture(color[1], color[2], color[3], 1) end
    end
    return m
end
