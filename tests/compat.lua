-- Real-save compatibility check (run with: node compat.js <path to a Krakenfriends.lua save file>)
--
-- The saved data goes in first, exactly as the game would load it, then the current
-- addon code loads over it. Every value that was in the save must still be there,
-- unchanged. New fields may be added; nothing may be lost, renamed or altered.

assert(load(SV_TEXT, "@savedvariables"))()
local function deepcopy(v) if type(v) ~= "table" then return v end local c = {} for k, x in pairs(v) do c[k] = deepcopy(x) end return c end
local before = deepcopy(KrakenfriendsDB or KrakenfriendsCharDB)
assert(before, "that file doesn't define KrakenfriendsDB or KrakenfriendsCharDB")

local NS = {}
for _, name in ipairs(TOC) do assert(load(FILES[name], "@" .. name))("Krakenfriends", NS) end
UNITS.player = { guid = "Player-1-0000AAAA", name = "Tester", realm = "Forever", class = "MAGE", level = 14, player = true }
FireEvent("ADDON_LOADED", "Krakenfriends")
FireEvent("PLAYER_LOGIN")

local lost, changed, added = 0, 0, 0
local function cmp(a, b, path)
    for k, v in pairs(a) do
        local w = b[k]
        local p = path .. "." .. tostring(k)
        if w == nil then lost = lost + 1; print("  LOST: " .. p)
        elseif type(v) == "table" then
            if type(w) ~= "table" then changed = changed + 1; print("  CHANGED: " .. p) else cmp(v, w, p) end
        elseif v ~= w and not (path == "" and (k == "version" or k == "savedAt")) then
            changed = changed + 1
            print("  CHANGED: " .. p .. " " .. tostring(v) .. " -> " .. tostring(w))
        end
    end
    for k in pairs(b) do if a[k] == nil then added = added + 1 end end
end
cmp(before, KrakenfriendsDB, "")

local journeys, pairCount, kills = 0, 0, 0
for _, j in pairs(KrakenfriendsDB.journeys) do
    journeys = journeys + 1
    kills = kills + ((j.total and j.total.kills) or 0)
    for _, p in pairs(j.pairs or {}) do
        pairCount = pairCount + 1
        assert(p.records and p.records.me and p.records.partner and p.records.duo, "a chapter is missing its records")
    end
end
print(("journeys: %d, character pairs: %d, kills (all journeys): %d"):format(journeys, pairCount, kills))
print(("old values lost: %d, changed: %d, new fields added: %d"):format(lost, changed, added))
assert(lost == 0 and changed == 0, "existing data was altered")
print("COMPAT OK: every old value is intact")
