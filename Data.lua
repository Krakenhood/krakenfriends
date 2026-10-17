local _, KR = ...

--------------------------------------------------------------------------------
-- The look: the game's own style, like KrakenChat. Gold on dark stone, the
-- game's red for rage.
--------------------------------------------------------------------------------

KR.Theme = {
    panel  = { 0, 0, 0, 0.30 },
    hover  = { 1, 0.82, 0, 0.10 },
    line   = { 1, 0.82, 0, 0.22 },
    gold   = { 1, 0.82, 0 },
    red    = { 0.70, 0.08, 0.06 },
    rage   = { 0.78, 0.12, 0.10 },      -- the bar itself
    rageHi = { 1.00, 0.30, 0.18 },      -- the bright top of the bar
    text   = { 1, 1, 1 },
    dim    = { 0.78, 0.72, 0.60 },
    faint  = { 0.50, 0.46, 0.38 },
    good   = { 0.36, 0.86, 0.47 },
    warn   = { 0.95, 0.72, 0.30 },
    bad    = { 1.00, 0.36, 0.30 },
    stone  = { 0.10, 0.09, 0.08, 0.92 }, -- behind the bar
}

-- Gold-border and stone files, the first one the client has wins.
KR.Files = {
    edge = { "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", "Interface\\DialogFrame\\UI-DialogBox-Border" },
    back = { "Interface\\FrameGeneral\\UI-Background-Rock", "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
    thinEdge = { "Interface\\Tooltip\\UI-Tooltip-Border" },
    bar = { "Interface\\TargetingFrame\\UI-StatusBar" },
    titleFont = "Fonts\\MORPHEUS.TTF",
}

--------------------------------------------------------------------------------
-- Stances, in the order the stance bar lists them for a warrior.
--------------------------------------------------------------------------------

KR.Stances = {
    { key = "battle",    id = 2457, name = "Battle Stance",    icon = "Ability_Warrior_OffensiveStance" },
    { key = "defensive", id = 71,   name = "Defensive Stance", icon = "Ability_Warrior_DefensiveStance" },
    { key = "berserker", id = 2458, name = "Berserker Stance", icon = "Ability_Racial_Avatar" },
}

--------------------------------------------------------------------------------
-- Abilities. `id` is rank 1; the rank you actually know is looked up by name
-- (`name` is the English one, used only when the client can't name the spell).
-- `cost` is the base rage cost, used only when the game can't tell us the real
-- one (talents lower Heroic Strike, Sunder Armor and Execute).
-- `stances` lists where it can be used (nil = anywhere).
-- `tick`: shown on the bar by default. `main`: a big ability whose rage you
-- shouldn't spend on Heroic Strike. `swing`: replaces the next swing.
-- `gives`: gives rage instead of costing it.
--------------------------------------------------------------------------------

local B, D, Z = "battle", "defensive", "berserker"

KR.Abilities = {
    { key = "hs",        id = 78, name = "Heroic Strike",    cost = 15, short = "HS",  icon = "Ability_Rogue_Ambush", tick = true, swing = true },
    { key = "cleave",    id = 845, name = "Cleave",   cost = 20, short = "Cl",  icon = "Ability_Warrior_Cleave", swing = true },
    { key = "execute",   id = 5308, name = "Execute",  cost = 15, short = "Ex",  icon = "INV_Sword_48", tick = true, stances = { B, Z } },
    { key = "ms",        id = 12294, name = "Mortal Strike", cost = 30, short = "MS",  icon = "Ability_Warrior_SavageBlow", tick = true, main = true },
    { key = "bt",        id = 23881, name = "Bloodthirst", cost = 30, short = "BT",  icon = "Spell_Nature_BloodLust", tick = true, main = true },
    { key = "ss",        id = 23922, name = "Shield Slam", cost = 20, short = "SS",  icon = "INV_Shield_05", tick = true, main = true },
    { key = "ww",        id = 1680, name = "Whirlwind",  cost = 25, short = "WW",  icon = "Ability_Whirlwind", tick = true, stances = { Z } },
    { key = "sunder",    id = 7386, name = "Sunder Armor",  cost = 15, short = "SA",  icon = "Ability_Warrior_Sunder", tick = true },
    { key = "revenge",   id = 6572, name = "Revenge",  cost = 5,  short = "Rv",  icon = "Ability_Warrior_Revenge", tick = true, stances = { D } },
    { key = "overpower", id = 7384, name = "Overpower",  cost = 5,  short = "OP",  icon = "Ability_MeleeDamage", tick = true, stances = { B } },
    { key = "slam",      id = 1464, name = "Slam",  cost = 15, short = "Sl",  icon = "Ability_Warrior_DecisiveStrike" },
    { key = "tclap",     id = 6343, name = "Thunder Clap",  cost = 20, short = "TC",  icon = "Spell_Nature_ThunderClap", stances = { B } },
    { key = "rend",      id = 772, name = "Rend",   cost = 10, short = "Re",  icon = "Ability_Gouge", stances = { B, D } },
    { key = "hamstring", id = 1715, name = "Hamstring",  cost = 10, short = "Ha",  icon = "Ability_ShockWave", stances = { B, Z } },
    { key = "pummel",    id = 6552, name = "Pummel",  cost = 10, short = "Pu",  icon = "INV_Gauntlets_04", stances = { Z } },
    { key = "bash",      id = 72, name = "Shield Bash",    cost = 10, short = "SB",  icon = "Ability_Warrior_ShieldBash", stances = { B, D } },
    { key = "block",     id = 2565, name = "Shield Block",  cost = 10, short = "Bl",  icon = "Ability_Defend", stances = { D } },
    { key = "shout",     id = 6673, name = "Battle Shout",  cost = 10, short = "BS",  icon = "Ability_Warrior_BattleShout" },
    { key = "demo",      id = 1160, name = "Demoralizing Shout",  cost = 10, short = "DS",  icon = "Ability_Warrior_WarCry" },
    { key = "intercept", id = 20252, name = "Intercept", cost = 10, short = "In",  icon = "Ability_Rogue_Sprint", stances = { Z } },
    { key = "sweeping",  id = 12292, name = "Sweeping Strikes", cost = 30, short = "SwS", icon = "Ability_Rogue_SliceDice", stances = { B } },
    { key = "concussion", id = 12809, name = "Concussion Blow", cost = 15, short = "CB", icon = "Ability_ThunderBolt" },
    { key = "bloodrage", id = 2687, name = "Bloodrage",  cost = 0,  short = "BR",  icon = "Ability_Racial_BloodRage", gives = true },
    { key = "charge",    id = 100, name = "Charge",   cost = 0,  short = "Ch",  icon = "Ability_Warrior_Charge", gives = true, stances = { B } },
}

KR.AbilityByKey = {}
for _, a in ipairs(KR.Abilities) do KR.AbilityByKey[a.key] = a end

-- Tactical Mastery: the talent that keeps some rage on a stance switch.
KR.TACTICAL_MASTERY = 12295

-- How long the game keeps a reactive ability usable after the dodge or block.
KR.PROC_WINDOW = 5
