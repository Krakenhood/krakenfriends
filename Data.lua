local _, KF = ...

KF.Theme = {
    bg      = { 0.047, 0.055, 0.071, 0.96 },
    panel   = { 1, 1, 1, 0.035 },
    hover   = { 1, 1, 1, 0.07 },
    line    = { 1, 1, 1, 0.08 },
    accent  = { 0.31, 0.82, 0.77 }, -- kraken teal
    accent2 = { 0.55, 0.42, 0.95 }, -- deep-sea violet
    text    = { 0.93, 0.94, 0.96 },
    dim     = { 0.56, 0.60, 0.66 },
    good    = { 0.36, 0.86, 0.47 },
}

--------------------------------------------------------------------------------
-- Icons. Each entry lists candidates; the first one the client actually has
-- wins (checked with GetFileIDFromPath), so a renamed file never shows as a
-- green square. Atlases are tried first when given.
--------------------------------------------------------------------------------

local I = "Interface\\Icons\\"
local function icon(...) return { files = { ... } } end

KF.Icons = {
    app       = icon(I .. "Achievement_Reputation_01", I .. "INV_Misc_GroupNeedMore"),
    kills     = icon(I .. "Ability_Rogue_Eviscerate", I .. "INV_Sword_04"),
    rare      = { atlas = "nameplates-icon-elite-silver", files = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" }, nocrop = true },
    elite     = { atlas = "nameplates-icon-elite-gold", files = { I .. "Ability_DualWield" } },
    boss      = { files = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" }, nocrop = true },
    dungeon   = icon(I .. "Achievement_Dungeon_ClassicDungeonMaster", I .. "INV_Misc_Key_03"),
    gold      = icon(I .. "INV_Misc_Coin_01"),
    epic      = icon(I .. "INV_Enchant_VoidCrystal", I .. "INV_Misc_Gem_Amethyst_02"),
    loot      = icon(I .. "INV_Misc_Bag_08", I .. "INV_Misc_Bag_10"),
    quest     = icon(I .. "INV_Misc_Note_01"),
    time      = icon(I .. "INV_Misc_PocketWatch_01"),
    death     = icon(I .. "INV_Misc_Bone_HumanSkull_01"),
    zone      = icon(I .. "INV_Misc_Map_01"),
    level     = icon(I .. "Achievement_Level_10", I .. "Spell_Holy_SurgeOfLight"),
    milestone = icon(I .. "Achievement_General", I .. "Ability_Warrior_BattleShout"),
    unknown   = icon(I .. "INV_Misc_QuestionMark"),
}
KF.Icons.start = KF.Icons.app

--------------------------------------------------------------------------------
-- Creature types, keyed by the id UnitCreatureType returns as its second value
-- (language-independent). Labels are replaced with the client's localized
-- names at login.
--------------------------------------------------------------------------------

KF.CreatureTypes = {
    [1]  = "beast",
    [2]  = "dragonkin",
    [3]  = "demon",
    [4]  = "elemental",
    [5]  = "giant",
    [6]  = "undead",
    [7]  = "humanoid",
    [8]  = "critter",
    [9]  = "mechanical",
    [10] = "unspecified",
    [11] = "totem",
    [12] = "critter",   -- non-combat pet
    [13] = "unspecified", -- gas cloud
    [14] = "critter",   -- wild pet
    [15] = "aberration",
}

KF.TypeInfo = {
    humanoid    = { id = 7,  label = "Humanoid",      icon = icon(I .. "INV_Misc_Head_Human_01", I .. "Achievement_Character_Human_Male") },
    beast       = { id = 1,  label = "Beast",         icon = icon(I .. "Ability_Hunter_Pet_Wolf") },
    undead      = { id = 6,  label = "Undead",        icon = icon(I .. "Spell_Shadow_RaiseDead") },
    demon       = { id = 3,  label = "Demon",         icon = icon(I .. "Spell_Shadow_SummonFelHunter") },
    elemental   = { id = 4,  label = "Elemental",     icon = icon(I .. "Spell_Frost_SummonWaterElemental", I .. "Spell_Fire_Fire") },
    dragonkin   = { id = 2,  label = "Dragonkin",     icon = icon(I .. "INV_Misc_Head_Dragon_01") },
    giant       = { id = 5,  label = "Giant",         icon = icon(I .. "Ability_WarStomp") },
    mechanical  = { id = 9,  label = "Mechanical",    icon = icon(I .. "INV_Misc_Gear_01") },
    aberration  = { id = 15, label = "Aberration",    icon = icon(I .. "Spell_Shadow_ShadowWordPain") },
    totem       = { id = 11, label = "Totem",         icon = icon(I .. "Spell_Nature_StoneSkinTotem") },
    critter     = { id = 8,  label = "Critter",       icon = icon(I .. "Spell_Nature_Polymorph") },
    player      = {          label = "Players",       icon = icon(I .. "Ability_DualWield") },
    unspecified = { id = 10, label = "Not specified", icon = icon(I .. "INV_Misc_QuestionMark") },
    unknown     = {          label = "Unidentified",  icon = icon(I .. "INV_Misc_QuestionMark") },
}

function KF:LocalizeTypes()
    if not (C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo) then return end
    for _, info in pairs(self.TypeInfo) do
        if info.id then
            local data = self.call(C_CreatureInfo.GetCreatureTypeInfo, info.id)
            local name = type(data) == "table" and self.clean(data.name)
            if type(name) == "string" and name ~= "" then info.label = name end
        end
    end
end

--------------------------------------------------------------------------------
-- Item quality
--------------------------------------------------------------------------------

KF.QualityFallback = {
    [0] = { "Poor",      0.62, 0.62, 0.62 },
    [1] = { "Common",    1.00, 1.00, 1.00 },
    [2] = { "Uncommon",  0.12, 1.00, 0.00 },
    [3] = { "Rare",      0.00, 0.44, 0.87 },
    [4] = { "Epic",      0.64, 0.21, 0.93 },
    [5] = { "Legendary", 1.00, 0.50, 0.00 },
}

function KF.QualityInfo(q)
    local fb = KF.QualityFallback[q] or KF.QualityFallback[1]
    local label = _G["ITEM_QUALITY" .. q .. "_DESC"] or fb[1]
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.r then return label, c.r, c.g, c.b end
    return label, fb[2], fb[3], fb[4]
end

--------------------------------------------------------------------------------
-- Milestones: logged in the journal and shown as a pop-up once reached.
--------------------------------------------------------------------------------

local function epics(s)
    local me, pa = s.lootMe or {}, s.lootPartner or {}
    return (me[4] or 0) + (me[5] or 0) + (pa[4] or 0) + (pa[5] or 0)
end
KF.CountEpics = epics

KF.Milestones = {
    { id = "kills", icon = "kills", steps = { 1, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000 },
      label = function(n) return n == 1 and "Your first kill together!" or KF.FormatNumber(n) .. " kills together" end },
    { id = "rare", icon = "rare", steps = { 1, 5, 10, 25, 50, 100 },
      label = function(n) return n == 1 and "Your first rare together!" or n .. " rares slain" end },
    { id = "boss", icon = "boss", steps = { 1, 10, 25, 50, 100, 250 },
      label = function(n) return n == 1 and "Your first boss together!" or n .. " bosses defeated" end },
    { id = "runs", icon = "dungeon", steps = { 1, 5, 10, 25, 50, 100 },
      label = function(n) return n == 1 and "Your first dungeon run!" or n .. " dungeon runs" end },
    { id = "epics", icon = "epic", steps = { 1, 10, 25, 50 }, value = epics,
      label = function(n) return n == 1 and "Your first epic!" or n .. " epics found" end },
    { id = "goldDuo", icon = "gold", steps = { 10000, 100000, 1000000, 5000000, 10000000, 50000000 },
      label = function(n) return KF.FormatMoney(n, true) .. " looted together" end },
    { id = "quests", icon = "quest", steps = { 10, 50, 100, 250, 500, 1000 },
      label = function(n) return n .. " quests completed together" end },
    { id = "time", icon = "time", steps = { 3600, 36000, 86400, 360000, 864000 },
      label = function(n) local h = math.floor(n / 3600); return h .. (h == 1 and " hour" or " hours") .. " spent together" end },
}
