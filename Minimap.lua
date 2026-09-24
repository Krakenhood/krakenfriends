local _, KF = ...
local Theme = KF.Theme
local FN = KF.FormatNumber
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

local button

local function updatePosition()
    local angle = math.rad(KF.db.settings.minimap.angle or 205)
    local radius = Minimap:GetWidth() / 2 + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function updateState()
    if not button then return end
    button:SetShown(not KF.db.settings.minimap.hide)
    local c = KF.together and Theme.good or (KF.partner and { 0.95, 0.72, 0.30 }) or nil
    if c then
        button.pip:SetColorTexture(c[1], c[2], c[3], 1)
        button.pip:Show()
    else
        button.pip:Hide()
    end
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff4fd1c5Kraken|rfriends")
    local j = KF.journey
    if j then
        local state = KF.together and "|cff5cdb78Together|r" or (KF.partner and "|cfff2b84dApart, paused|r") or "|cff8a8f98Not grouped|r"
        GameTooltip:AddDoubleLine("Journey with " .. (j.partnerName or "?"), state, 1, 1, 1)
        local s = j.total
        GameTooltip:AddDoubleLine("Kills", FN(s.kills), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Dungeon runs", FN(s.runs), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Gold looted", KF.FormatMoney(s.goldDuo), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Time together", KF.FormatDuration(s.time), 0.7, 0.7, 0.7, 1, 1, 1)
    else
        GameTooltip:AddLine("Group up with a friend to start your journey.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: journal   Right-click: status   Drag: move", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function createButton()
    button = CreateFrame("Button", "KrakenfriendsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    KF.SetIcon(icon, "app")
    KF.Circle(icon)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- green while you two are together, amber while grouped but apart
    button.pip = button:CreateTexture(nil, "OVERLAY", nil, 2)
    button.pip:SetSize(7, 7)
    button.pip:SetPoint("BOTTOMRIGHT", -6, 6)
    button.pip:SetColorTexture(1, 1, 1, 1)
    KF.Circle(button.pip)

    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then KF:PrintStatus() else KF.UI:Toggle() end
    end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            KF.db.settings.minimap.angle = math.deg(atan2(py / scale - my, px / scale - mx))
            updatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
    updateState()
end

-- Retail's addon compartment (the button under the minimap) calls this
-- global, named in the .toc.
function Krakenfriends_OnAddonCompartmentClick()
    KF.UI:Toggle()
end

--------------------------------------------------------------------------------
-- Milestone toasts
--------------------------------------------------------------------------------

local toast, queue = nil, {}
local showNext

local function createToast()
    toast = CreateFrame("Frame", nil, UIParent)
    toast:SetSize(310, 58)
    toast:SetPoint("TOP", 0, -150)
    toast:SetFrameStrata("HIGH")
    toast:EnableMouse(true)
    toast:Hide()

    local bg = toast:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(Theme.bg[1], Theme.bg[2], Theme.bg[3], 0.95)
    local stripe = toast:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(3)
    stripe:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    local edge = toast:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(1, 1, 1, 0.08)

    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(34, 34)
    toast.icon:SetPoint("LEFT", 14, 0)

    toast.title = toast:CreateFontString(nil, "OVERLAY")
    toast.title:SetFont(FONT, 10, "")
    toast.title:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3])
    toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 12, -1)

    toast.text = toast:CreateFontString(nil, "OVERLAY")
    toast.text:SetFont(FONT, 13, "")
    toast.text:SetTextColor(1, 1, 1)
    toast.text:SetShadowOffset(1, -1)
    toast.text:SetShadowColor(0, 0, 0, 0.8)
    toast.text:SetJustifyH("LEFT")
    toast.text:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4)
    toast.text:SetWidth(240)
    toast.text:SetWordWrap(true)

    toast:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        local t = self.t
        if t < 0.25 then
            self:SetAlpha(t / 0.25)
        elseif t < 4.5 then
            self:SetAlpha(1)
        elseif t < 5 then
            self:SetAlpha(1 - (t - 4.5) / 0.5)
        else
            self:Hide()
            showNext()
        end
    end)
    toast:SetScript("OnMouseUp", function(self)
        self:Hide()
        wipe(queue)
        KF.UI:Show()
        KF.UI:SelectTab("Journal")
    end)
end

function showNext()
    local item = table.remove(queue, 1)
    if not item then return end
    if not toast then createToast() end
    toast.title:SetText(item.title:upper())
    toast.text:SetText(item.text)
    KF.SetIcon(toast.icon, item.icon or "milestone")
    toast.t = 0
    toast:SetAlpha(0)
    toast:Show()
    local sound = SOUNDKIT and (SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.IG_QUEST_LIST_COMPLETE)
    if sound then PlaySound(sound) end
end

function KF.ShowToast(title, text, icon)
    if #queue >= 5 then return end
    queue[#queue + 1] = { title = title, text = text, icon = icon }
    if not (toast and toast:IsShown()) then showNext() end
end

--------------------------------------------------------------------------------

KF:Listen("LOGIN", createButton)
KF:Listen("SETTINGS", updateState)
KF:Listen("TOGETHER", updateState)
KF:Listen("PARTNER", updateState)
