-- Minimal WoW API mock for headless testing of Krakenfriends (runs on fengari / Lua 5.3)
unpack = table.unpack
ERRORS = {}
CHAT = {}
CAPTURE = nil -- when a table, SetText calls append here

local function noop() end

-- clock ------------------------------------------------------------------
NOW = 1790000000
GT = 1000.0
function time(t) if t then return os.time(t) end return NOW end
function GetTime() return GT end
function GetServerTime() return NOW end
function date(fmt, t) return os.date(fmt, t or NOW) end

-- timers -------------------------------------------------------------------
TIMERS, TICKERS = {}, {}
C_Timer = {
    After = function(sec, fn) TIMERS[#TIMERS + 1] = { at = GT + sec, fn = fn } end,
    NewTicker = function(sec, fn)
        local t = { sec = sec, fn = fn, cancelled = false }
        function t:Cancel() self.cancelled = true end
        TICKERS[#TICKERS + 1] = t
        return t
    end,
}
function Advance(sec, realSec)
    -- moves both clocks; fires due timers; tickers fire once per call
    NOW = NOW + (realSec or sec)
    GT = GT + sec
    local due = {}
    for i = #TIMERS, 1, -1 do
        if TIMERS[i].at <= GT then due[#due + 1] = TIMERS[i]; table.remove(TIMERS, i) end
    end
    for i = #due, 1, -1 do due[i].fn() end
end
function TickAll()
    for _, t in ipairs(TICKERS) do if not t.cancelled then t.fn() end end
end

-- secrets -------------------------------------------------------------------
SECRET = setmetatable({}, { __tostring = function() error("touched a secret") end,
    __eq = function() error("compared a secret") end, __concat = function() error("concat secret") end })
function issecretvalue(v) return rawequal(v, SECRET) end
function canaccessvalue(v) return not rawequal(v, SECRET) end

-- frames ---------------------------------------------------------------------
local frames = {}
local eventFrames = {}
local Object = {}
Object.__index = function(t, k)
    local m = Object[k]
    if m then return m end
    if type(k) == "string" and k:match("^%u") then return noop end
    return nil
end
local function new(kind, parent)
    local o = setmetatable({ _kind = kind, _parent = parent, _shown = kind ~= "Frame" and true or true, _w = 0, _h = 0, _scripts = {}, _events = {} }, Object)
    frames[#frames + 1] = o
    return o
end
function Object:SetSize(w, h) rawset(self, "_w", w); rawset(self, "_h", h) end
function Object:SetWidth(w) rawset(self, "_w", w) end
function Object:SetHeight(h) rawset(self, "_h", h) end
function Object:GetWidth() return self._w end
function Object:GetHeight() return self._h end
function Object:Show() rawset(self, "_shown", true); local s = self._scripts.OnShow; if s then s(self) end end
function Object:Hide() local was = self._shown; rawset(self, "_shown", false); local s = self._scripts.OnHide; if s and was then s(self) end end
function Object:SetShown(v) if v then self:Show() else self:Hide() end end
function Object:IsShown() return self._shown end
function Object:IsVisible() return self._shown end
function Object:SetScript(name, fn) self._scripts[name] = fn end
function Object:GetScript(name) return self._scripts[name] end
function Object:HookScript(name, fn) self._scripts[name] = fn end
function Object:RegisterEvent(e)
    if e:match("^COMBAT_LOG") then return end -- forbidden, silently
    if not KNOWN_EVENTS[e] then error("unknown event " .. e) end
    self._events[e] = true
    eventFrames[self] = true
end
function Object:UnregisterEvent(e) self._events[e] = nil end
function Object:CreateTexture() return new("Texture", self) end
function Object:CreateMaskTexture() return new("MaskTexture", self) end
function Object:CreateFontString() local fs = new("FontString", self); rawset(fs, "_text", ""); return fs end
function Object:GetParent() return self._parent end
function Object:SetText(t) rawset(self, "_text", t); if CAPTURE and t and t ~= "" then CAPTURE[#CAPTURE + 1] = t end end
function Object:GetText() return self._text end
function Object:GetStringHeight() return 14 end
function Object:GetStringWidth() return 50 end
function Object:GetVerticalScroll() return self._scroll or 0 end
function Object:SetVerticalScroll(v) rawset(self, "_scroll", v) end
function Object:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Object:GetCenter() return 100, 100 end
function Object:GetEffectiveScale() return 1 end
function Object:GetFrameLevel() return 1 end
function Object:IsMouseOver() return false end
function Object:SetFont() return true end

function CreateFrame(kind, name, parent, template)
    local f = new(kind or "Frame", parent)
    if name then _G[name] = f end
    return f
end
function FireEvent(e, ...)
    for f in pairs(eventFrames) do
        if f._events[e] and f._scripts.OnEvent then f._scripts.OnEvent(f, e, ...) end
    end
end
function Click(btn, which)
    local s = btn._scripts.OnClick
    if s then s(btn, which or "LeftButton") end
end

UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap"); Minimap:SetSize(140, 140)
GameTooltip = CreateFrame("Frame", "GameTooltip")
DEFAULT_CHAT_FRAME = CreateFrame("Frame")
function DEFAULT_CHAT_FRAME:AddMessage(msg)
    msg = tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    CHAT[#CHAT + 1] = msg
    print("  [chat] " .. msg)
end
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
POPUPS = {}
function StaticPopup_Show(which, a1, a2, data) POPUPS[#POPUPS + 1] = { which = which, a1 = a1, data = data }; return true end
function geterrorhandler() return function(err) ERRORS[#ERRORS + 1] = err; print("  !! ERROR: " .. tostring(err)) end end
function PlaySound() end
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 1, IG_CHARACTER_INFO_CLOSE = 2, IG_CHARACTER_INFO_TAB = 3 }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function GetFileIDFromPath(p)
    if p:find("Achievement_Dungeon_ClassicDungeonMaster") then return nil end -- simulate a missing icon
    return 100000 + #p
end
function GetCursorPosition() return 0, 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s)
    local out, pattern = {}, "([^" .. sep:gsub("%p", "%%%0") .. "]*)"
    for part in (s .. sep):gmatch(pattern .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
    return table.unpack(out)
end
function BreakUpLargeNumbers(n)
    local s, k = tostring(math.floor(n)), nil
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PRIEST = { r = 1, g = 1, b = 1 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", PRIEST = "Priest", WARRIOR = "Warrior" }
ITEM_QUALITY_COLORS = {
    [0] = { r = .62, g = .62, b = .62, hex = "|cff9d9d9d" }, [1] = { r = 1, g = 1, b = 1, hex = "|cffffffff" },
    [2] = { r = .12, g = 1, b = 0, hex = "|cff1eff00" }, [3] = { r = 0, g = .44, b = .87, hex = "|cff0070dd" },
    [4] = { r = .64, g = .21, b = .93, hex = "|cffa335ee" }, [5] = { r = 1, g = .5, b = 0, hex = "|cffff8000" },
}
ITEM_QUALITY2_DESC, ITEM_QUALITY3_DESC, ITEM_QUALITY4_DESC = "Uncommon", "Rare", "Epic"
UNKNOWNOBJECT, YES, NO = "Unknown", "Yes", "No"
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_MONEY_SPLIT = "Your share of the loot is %s."
LOOT_MONEY_SPLIT_GUILD = "Your share of the loot is %s. (%s deposited to guild bank)"
YOU_LOOT_MONEY = "You loot %s"
YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)"
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
INSTANCE_RESET_SUCCESS = "%s has been reset."

-- world state --------------------------------------------------------------
UNITS = {}
GROUP = { n = 1, raid = false }
INSTANCE = { name = "Elwynn Forest", type = "none", id = 0 }
ZONE = "Elwynn Forest"
local function U(unit)
    if not unit then return nil end
    local u = UNITS[unit]
    if u then return u end
    -- "<unit>target" resolves through the unit's .target token
    local base = unit:match("^(.-)target$")
    local b = base and base ~= "" and UNITS[base]
    return b and b.target and UNITS[b.target] or nil
end

function UnitExists(u) return U(u) ~= nil end
function UnitGUID(u) local x = U(u); return x and x.guid end
function UnitName(u) local x = U(u); if x then return x.name, x.realm end end
function UnitFullName(u) local x = U(u); if x then return x.name, x.realm end end
function UnitClass(u) local x = U(u); if x and x.class then return LOCALIZED_CLASS_NAMES_MALE[x.class], x.class, 1 end end
function UnitLevel(u) local x = U(u); return x and x.level or 0 end
function UnitIsPlayer(u) local x = U(u); return x and x.player or false end
function UnitCanAttack(a, u) local x = U(u); return x and x.hostile or false end
function UnitCreatureType(u) local x = U(u); if x and x.ctype then return "type", x.ctype end end
function UnitClassification(u) local x = U(u); return x and x.cls or "normal" end
function UnitIsBossMob(u) local x = U(u); return x and x.boss or false end
function UnitIsTapDenied(u) local x = U(u); return x and x.tapDenied or false end
function UnitThreatSituation(u, mob) local m = U(mob); return m and m.threat and m.threat[u] or nil end
function UnitIsUnit(a, b)
    if a == b then return true end
    local x, y = U(a), U(b)
    if a:match("target$") and not x then
        local base = U(a:gsub("target$", ""))
        x = base and base.target and U(base.target)
    end
    return x ~= nil and y ~= nil and x.guid == y.guid
end
function UnitIsConnected(u) return U(u) ~= nil end
function UnitIsVisible(u) local x = U(u); return x and x.visible ~= false or false end
function UnitIsDeadOrGhost(u) local x = U(u); return x and x.dead or false end
function UnitTokenFromGUID(guid) for k, v in pairs(UNITS) do if v.guid == guid then return k end end end
function UnitNameFromGUID(guid) return NAMES_BY_GUID and NAMES_BY_GUID[guid] end
function IsInGroup() return GROUP.n > 1 end
function IsInRaid() return GROUP.raid end
function GetNumGroupMembers() return GROUP.n > 1 and GROUP.n or 0 end
function GetNumSubgroupMembers() return GROUP.n > 1 and GROUP.n - 1 or 0 end
function GetNormalizedRealmName() return "Forever" end
function BNGetInfo() return 1, "Kraken#1111" end
C_BattleNet = { GetAccountInfoByGUID = function(guid) return BNET and BNET[guid] end }
C_Map = { GetBestMapForUnit = function(u) return 1429 end }
C_CreatureInfo = { GetCreatureTypeInfo = function(id) return { id = id, name = nil } end }
C_Item = {
    GetItemQualityByID = function(id) return nil end,
    GetItemIconByID = function(id) return 12345 end,
}
C_Texture = { GetAtlasInfo = function(a) if a:find("^classicon") then return nil end return { width = 1 } end }
SENT = {}
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, GeneralError = 9 } }
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) PREFIXES = PREFIXES or {}; PREFIXES[p] = true; return 0 end,
    SendAddonMessage = function(prefix, text, chan) SENT[#SENT + 1] = { prefix = prefix, text = text, chan = chan }; return 0 end,
    AreOutgoingAddonChatMessagesRestricted = function() return true end,
}
C_Spell = {
    GetSpellName = function(id) return ({ [133] = "Fireball", [585] = "Smite", [2136] = "Fire Blast" })[id] end,
    GetSpellDescription = function(id) return ({ [133] = "Hurls a fiery ball that deals 50 Fire damage.", [585] = "Smites an enemy for 40 Holy damage.", [2136] = "Blasts the enemy for 30 Fire damage." })[id] end,
}
SPELL_SCHOOL0_NAME, SPELL_SCHOOL1_NAME, SPELL_SCHOOL2_NAME, SPELL_SCHOOL3_NAME = "Physical", "Holy", "Fire", "Nature"
SPELL_SCHOOL4_NAME, SPELL_SCHOOL5_NAME, SPELL_SCHOOL6_NAME = "Frost", "Shadow", "Arcane"
C_AddOns = { GetAddOnMetadata = function() return "1.0.0-test" end }
function GetInstanceInfo() return INSTANCE.name, INSTANCE.type, 0, "", 5, 0, false, INSTANCE.id, 0, nil, false end
function GetRealZoneText() return ZONE end
function SetPortraitTexture() end

KNOWN_EVENTS = {}
for e in ([[ADDON_LOADED PLAYER_LOGIN PLAYER_LOGOUT PLAYER_ENTERING_WORLD GROUP_ROSTER_UPDATE UNIT_CONNECTION
BN_FRIEND_INFO_CHANGED PARTY_KILL UNIT_DIED PLAYER_TARGET_DIED PLAYER_TARGET_CHANGED UPDATE_MOUSEOVER_UNIT
NAME_PLATE_UNIT_ADDED UNIT_THREAT_LIST_UPDATE UNIT_TARGET PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED CHAT_MSG_LOOT
CHAT_MSG_MONEY CHAT_MSG_SYSTEM ENCOUNTER_START ENCOUNTER_END BOSS_KILL PLAYER_DEAD UNIT_HEALTH PLAYER_LEVEL_UP
UNIT_LEVEL QUEST_TURNED_IN ZONE_CHANGED_NEW_AREA UNIT_SPELLCAST_SUCCEEDED UNIT_COMBAT CHAT_MSG_ADDON]]):gmatch("%S+") do KNOWN_EVENTS[e] = true end
