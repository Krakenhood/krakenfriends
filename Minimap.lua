local _, KR = ...
local C = KR.Coach
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

local button

local function updatePosition()
    local angle = math.rad(KR.db.settings.minimap.angle or 220)
    local radius = Minimap:GetWidth() / 2 + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function updateState()
    if button then button:SetShown(not KR.db.settings.minimap.hide) end
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff4fd1c5Kraken|rrage")
    local fights = KR.char.fights
    local last = fights[#fights]
    if last then
        GameTooltip:AddDoubleLine("Last fight", ("%s  %s"):format(last.target or "?", KR.Colorize(C.Grade(last.score), C.GradeColor(last.score))), 0.7, 0.7, 0.7, 1, 1, 1)
        for _, tr in ipairs(C:Trends()) do
            if tr.label == "Grade" then GameTooltip:AddDoubleLine("Average grade", ("%d"):format(math.floor(tr.now + 0.5)), 0.7, 0.7, 0.7, 1, 1, 1) end
        end
    else
        GameTooltip:AddLine("No fights graded yet.", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: coach   Right-click: lock or unlock the bar   Drag: move", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

local function createButton()
    if button then return end
    button = CreateFrame("Button", "KrakenrageMinimapButton", Minimap)
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
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture("Interface\\AddOns\\Krakenrage\\Media\\minimap")
    local mask = button.CreateMaskTexture and button:CreateMaskTexture()
    if mask then
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, which)
        if which == "RightButton" then SlashCmdList.KRAKENRAGE("lock") else KR.UI:Toggle() end
    end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            KR.db.settings.minimap.angle = math.deg(atan2(py / scale - my, px / scale - mx))
            updatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
    updateState()
end

KR:Listen("SETUP", createButton)
KR:Listen("SETTINGS", updateState)
