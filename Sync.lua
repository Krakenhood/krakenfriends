local _, KF = ...
local clean = KF.clean

--------------------------------------------------------------------------------
-- Sync between you and your friend
--
-- Both copies of the addon count the same journey and sometimes disagree (one of
-- you logs off before handing in a quest, a kill happens out of range, ...). A few
-- times an hour the two copies swap their numbers and each keeps the LARGER one.
--
--  * The journey is matched by BattleTag, the chapter by the exact pair of
--    characters, seen from the other side: my "Krakenhood & Thalianne" is his
--    "Thalianne & Krakenhood". Chapters never mix; one your copy doesn't have yet
--    is added as it is.
--  * Counters only ever go up: a number is raised, never lowered, so applying the
--    same message twice changes nothing, and a stale message can't undo anything.
--  * The journey total gets the same increase as the chapter, so it stays the sum.
--  * Your friend's "me" is your "partner", so those numbers are swapped on arrival.
--  * Messages go over the party channel, a few at a time, and only when you ask
--    (/kf sync) or at calm moments: when you two meet, now and then while you play,
--    and after a dungeon run.
--
--  * The lists (creatures hunted, rares, bosses, dungeons, zones, items found) are
--    merged as a union: an entry either copy has is real, so it is added to the
--    other; counts take the larger value, first-seen dates the earlier one, last-seen
--    the later one, and the friend's "me" and "partner" item counts are swapped.
--    Entries are never deleted. The journal is not synced (both copies already log
--    the same events at slightly different moments), nor the per-player record
--    guesses.
--------------------------------------------------------------------------------

local S = {}
KF.Sync = S

local PROTO = 1
local BUDGET = 230     -- bytes per message (the game's limit is 255)
local MIN_GAP = 20     -- seconds between two automatic pushes
local REPLY_GAP = 60   -- answer a friend's hello only if we haven't sent for this long
local PERIOD = 300     -- while together, push at least this often
local SPACING = 0.3    -- seconds between two messages
local MAX_VALUE = 1e9
local MAX_MESSAGES = 200
local MAX_MOBS = 80      -- the most-hunted creatures that are sent
local MAX_ITEMS = 200    -- the most recent items that are sent

-- numbers that mean the same to both players: token, field
local SHARED = {
    { "k", "kills" }, { "e", "elite" }, { "r", "rare" }, { "b", "boss" },
    { "q", "quests" }, { "n", "runs" }, { "t", "time" }, { "g", "goldDuo" },
}
-- numbers seen from one side: token, sender's field, field on the receiving side
local SWAPPED = {
    { "a", "kbMe", "kbPartner" }, { "p", "kbPartner", "kbMe" },
    { "d", "deathsMe", "deathsPartner" }, { "f", "deathsPartner", "deathsMe" },
    { "l", "levelsMe", "levelsPartner" }, { "m", "levelsPartner", "levelsMe" },
}

local DECODE = {}
for _, e in ipairs(SHARED) do DECODE[e[1]] = e[2] end
for _, e in ipairs(SWAPPED) do DECODE[e[1]] = e[3] end

local NEW_LABEL = { mobs = "creatures", rares = "rares", bosses = "bosses", dungeons = "dungeons", zones = "zones", items = "items" }
local LABEL = { kills = "kills", quests = "quests", runs = "dungeon runs", boss = "bosses", rare = "rares", elite = "elites", time = "time together", goldDuo = "gold" }
local ORDER = { "kills", "quests", "runs", "boss", "rare", "elite", "time", "goldDuo" }

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

--------------------------------------------------------------------------------
-- Encoding: a chapter becomes a few short messages
--------------------------------------------------------------------------------

local function tokensFor(stats)
    local out = {}
    local function add(key, v)
        if type(v) == "number" and v > 0 then out[#out + 1] = key .. "=" .. math.floor(v) end
    end
    for _, e in ipairs(SHARED) do add(e[1], stats[e[2]]) end
    for _, e in ipairs(SWAPPED) do add(e[1], stats[e[2]]) end
    for q = 0, 5 do
        add("L" .. q, stats.lootMe and stats.lootMe[q])
        add("P" .. q, stats.lootPartner and stats.lootPartner[q])
    end
    for _, name in ipairs(sortedKeys(stats.types)) do add("y." .. name, stats.types[name]) end
    return out
end

local function chunks(tokens, budget)
    local list, cur = {}, ""
    for _, token in ipairs(tokens) do
        if cur ~= "" and #cur + #token + 1 > budget then
            list[#list + 1] = cur
            cur = ""
        end
        cur = (cur == "") and token or (cur .. ";" .. token)
    end
    if cur ~= "" then list[#list + 1] = cur end
    return list
end

local function plain(text)
    return (tostring(text or ""):gsub("[|;]", " "):sub(1, 40))
end

local function txt(s, n)
    return (tostring(s or ""):gsub("[|;,=]", " "):sub(1, n or 30))
end

local function int(v)
    return type(v) == "number" and math.floor(v) or 0
end

-- The lists of a chapter as groups of entries. An entry is a few comma-separated
-- fields, the name last (names never contain the separators).
local function listGroups(pair)
    local groups = {}
    local function add(kind, entries)
        if #entries > 0 then groups[#groups + 1] = { kind = kind, entries = entries, sig = table.concat(entries, ";") } end
    end

    local e = {}
    for _, id in ipairs(sortedKeys(pair.rares)) do
        local r = pair.rares[id]
        e[#e + 1] = ("%s,%d,%d,%d,%s"):format(txt(id, 12), int(r.c), int(r.t), int(r.lv), txt(r.n))
    end
    add("rares", e)

    e = {}
    for _, name in ipairs(sortedKeys(pair.bosses)) do
        local b = pair.bosses[name]
        e[#e + 1] = ("%d,%d,%s"):format(int(b.c), int(b.t), txt(name))
    end
    add("bosses", e)

    e = {}
    for _, id in ipairs(sortedKeys(pair.dungeons)) do
        local d = pair.dungeons[id]
        e[#e + 1] = ("%s,%d,%d,%d,%d,%s"):format(txt(id, 16), int(d.runs), int(d.time), int(d.bosses), int(d.last), txt(d.n))
    end
    add("dungeons", e)

    e = {}
    for _, name in ipairs(sortedKeys(pair.zones)) do
        e[#e + 1] = ("%d,%s"):format(int(pair.zones[name]), txt(name))
    end
    add("zones", e)

    if pair.toughest and pair.toughest.n then
        add("toughest", { ("%d,%s"):format(int(pair.toughest.lv), txt(pair.toughest.n)) })
    end

    local items = {}
    for id, it in pairs(pair.items) do items[#items + 1] = { id = id, it = it } end
    table.sort(items, function(a, b)
        if (a.it.l or 0) ~= (b.it.l or 0) then return (a.it.l or 0) > (b.it.l or 0) end
        return tostring(a.id) < tostring(b.id)
    end)
    e = {}
    for i = 1, math.min(MAX_ITEMS, #items) do
        local id, it = items[i].id, items[i].it
        e[#e + 1] = ("%s,%d,%d,%d,%d,%d,%d,%s"):format(txt(id, 12), int(it.q), int(it.c), int(it.me), int(it.pa), int(it.t), int(it.l), txt(it.n))
    end
    table.sort(e)
    add("items", e)

    local mobs = {}
    for id, m in pairs(pair.mobs) do mobs[#mobs + 1] = { id = id, m = m } end
    table.sort(mobs, function(a, b)
        if (a.m.c or 0) ~= (b.m.c or 0) then return (a.m.c or 0) > (b.m.c or 0) end
        return tostring(a.id) < tostring(b.id)
    end)
    e = {}
    for i = 1, math.min(MAX_MOBS, #mobs) do
        local id, m = mobs[i].id, mobs[i].m
        e[#e + 1] = ("%s,%d,%d,%s,%s"):format(txt(id, 12), int(m.c), int(m.lv), txt(m.ty, 12), txt(m.n))
    end
    table.sort(e)
    add("mobs", e)
    return groups
end

-- The messages for one chapter, exactly as this copy sees it. A list that hasn't
-- changed since it was last sent (`sent` remembers that per chapter) is left out.
function S.Messages(pair, sent, key)
    local head = ("C|%s|%s|%s|%s|"):format(plain(pair.me), plain(pair.partner), pair.meClass or "-", pair.partnerClass or "-")
    local msgs = {}
    for _, c in ipairs(chunks(tokensFor(pair.stats), BUDGET - #head)) do msgs[#msgs + 1] = head .. c end
    local duo = pair.records and pair.records.duo
    for _, kind in ipairs({ "hit", "crit" }) do
        local r = duo and duo[kind]
        if r and type(r.n) == "number" and r.n > 0 then
            msgs[#msgs + 1] = ("R|%s|%s|%s|%d|%d|%s|%s"):format(plain(pair.me), plain(pair.partner), kind,
                math.floor(r.n), math.floor(r.t or 0), plain(r.s), plain(r.d))
        end
    end
    for _, g in ipairs(listGroups(pair)) do
        local id = (key or "") .. "/" .. g.kind
        if not (sent and sent[id] == g.sig) then
            local lead = ("L|%s|%s|%s|"):format(g.kind, plain(pair.me), plain(pair.partner))
            for _, c in ipairs(chunks(g.entries, BUDGET - #lead)) do msgs[#msgs + 1] = lead .. c end
            if sent then sent[id] = g.sig end
        end
    end
    return msgs
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

local lastPush, queue, sending, retries = -1000, {}, false, 0
local sentSigs = {} -- chapter/list -> what the friend has been sent; cleared when they say hello

-- the game limits how fast addon messages may go; when it says "too fast", wait and try again
local function throttled(result)
    local e = Enum and Enum.SendAddonMessageResult
    return type(result) == "number" and e ~= nil and (result == e.AddonMessageThrottle or result == e.ChannelThrottle)
end

local function pump()
    local msg = table.remove(queue, 1)
    if not msg then
        sending = false
        return
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, KF.msgPrefix, msg, S.channel or "PARTY")
    result = clean(result)
    if ok and throttled(result) and retries < 5 then
        retries = retries + 1
        table.insert(queue, 1, msg)
        KF:Debug("sync: the game says too fast, waiting a moment (try %d)", retries)
        C_Timer.After(3, pump)
        return
    end
    if not ok or (type(result) == "number" and result ~= 0) then
        KF:Debug("sync: the game refused a message (result %s), stopping this push", tostring(result))
        wipe(queue)
        sending = false
        retries = 0
        return
    end
    retries = 0
    C_Timer.After(SPACING, pump)
end

function S:Push(force)
    if not KF.db.settings.sync then return false, "syncing is off (/kf sync on)" end
    local p = KF.partner
    local channel = KF.groupChannel and KF.groupChannel()
    if not (p and p.journey and channel and C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        return false, "you aren't grouped with your journey partner"
    end
    local now = GetTime()
    if not force and now - lastPush < MIN_GAP then return false, "just sent" end
    lastPush = now
    if force then wipe(sentSigs) end

    local list = { ("H|%d|%s|%s"):format(PROTO, plain(KF.version), plain(KF.me.tag or "-")) }
    local pairs_ = p.journey.pairs
    for _, key in ipairs(sortedKeys(pairs_)) do
        for _, m in ipairs(S.Messages(pairs_[key], sentSigs, key)) do list[#list + 1] = m end
    end
    while #list > MAX_MESSAGES do table.remove(list) end

    wipe(queue)
    for _, m in ipairs(list) do queue[#queue + 1] = m end
    S.channel = channel
    if not sending then
        sending = true
        pump()
    end
    KF:Debug("sync: sending %d messages to %s", #list, channel)
    return true, #list
end

function S:Schedule(delay)
    C_Timer.After(delay, function() S:Push() end)
end

function S:Command(arg)
    arg = (arg or ""):lower()
    local settings = KF.db.settings
    if arg == "off" or arg == "on" then
        settings.sync = arg == "on"
        KF:Print("Syncing with your friend is " .. (settings.sync and "on." or "off."))
        return
    end
    local ok, info = self:Push(true)
    if ok then
        KF:Printf("sent your journey to your friend (%d messages). If their copy answers, you'll see what changed.", info)
    else
        KF:Print("not sent: " .. info .. ".")
    end
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

local pending, flushScheduled = {}, false

local function chapterLabel(key)
    return (key:gsub("%-[^%s&]+", ""))
end

local function flush()
    flushScheduled = false
    local p = KF.partner
    local name = (p and p.journey and p.journey.partnerName) or (p and p.name) or "your friend"
    for key, c in pairs(pending) do
        local parts = {}
        for _, field in ipairs(ORDER) do
            local change = c.fields[LABEL[field]]
            if change then
                local fmt = (field == "time" and KF.FormatDuration) or (field == "goldDuo" and function(v) return KF.FormatMoney(v, true) end) or KF.FormatNumber
                parts[#parts + 1] = ("%s %s → %s"):format(LABEL[field], fmt(change[1]), fmt(change[2]))
            end
        end
        if c.other > 0 then parts[#parts + 1] = ("%d other counters"):format(c.other) end
        for _, kind in ipairs({ "items", "mobs", "rares", "bosses", "dungeons", "zones" }) do
            if c.new and c.new[kind] then parts[#parts + 1] = ("%d new %s"):format(c.new[kind], NEW_LABEL[kind]) end
        end
        if c.records then parts[#parts + 1] = "new shared record" end
        if c.created then table.insert(parts, 1, "new chapter") end
        if #parts > 0 then
            KF:Printf("synced with %s (%s): %s", name, chapterLabel(key), table.concat(parts, ", "))
        end
    end
    wipe(pending)
    S.lastSync = { t = KF.Now() }
    KF:CheckMilestones()
    KF:Fire("UPDATE")
end

local function note(key, label, old, new)
    local c = pending[key]
    if not c then
        c = { fields = {}, other = 0 }
        pending[key] = c
    end
    if label == "@created" then c.created = true
    elseif label == "@record" then c.records = (c.records or 0) + 1
    elseif label and label:sub(1, 5) == "@new:" then
        c.new = c.new or {}
        local kind = label:sub(6)
        c.new[kind] = (c.new[kind] or 0) + 1
    elseif label then c.fields[label] = { old, new }
    else c.other = c.other + 1 end
    if not flushScheduled then
        flushScheduled = true
        C_Timer.After(2, flush)
    end
end

-- Raises a counter to `value` if it is lower; the journey total grows by the same amount.
local function raise(j, pair, field, sub, value)
    local stats, total = pair.stats, j.total
    local old
    if sub == nil then
        old = stats[field] or 0
        if value <= old then return end
        stats[field] = value
        total[field] = (total[field] or 0) + (value - old)
    else
        stats[field] = stats[field] or {}
        total[field] = total[field] or {}
        old = stats[field][sub] or 0
        if value <= old then return end
        stats[field][sub] = value
        total[field][sub] = (total[field][sub] or 0) + (value - old)
    end
    return old, value
end

-- The chapter, as this copy knows it, for a pair named from the sender's side. Names
-- are compared without spaces, hyphens and capitals, so "Naendor Delorentis" and
-- "Naendor-Delorentis" are the same character.
local function chapterFor(j, senderMe, senderPartner, meClass, partnerClass)
    local mine, theirs = KF.NormName(senderPartner), KF.NormName(senderMe)
    for key, pair in pairs(j.pairs) do
        if KF.NormName(pair.me) == mine and KF.NormName(pair.partner) == theirs then return pair, key end
    end
    local key = senderPartner .. " & " .. senderMe
    local pair = KF.NewPair(senderPartner, partnerClass, senderMe, meClass)
    j.pairs[key] = pair
    note(key, "@created")
    return pair, key
end

local function validName(s)
    return type(s) == "string" and s ~= "" and #s <= 40
end

local function classOf(s)
    if type(s) == "string" and s:match("^%u+$") and #s <= 20 then return s end
end

local function partnerAndJourney(sender)
    local p = KF.partner
    if p and p.journey and KF.IsSender(sender, p) then return p, p.journey end
end

-- A backup is taken at the start of every batch of messages from the friend, but kept
-- only if the batch changed something (judged by a cheap fingerprint of the journey), so
-- /kf restore always goes back to just before the last sync that mattered.
local function fingerprint(j)
    local sum, n = 0, 0
    local function walk(t, depth)
        for _, v in pairs(t) do
            if type(v) == "number" then
                sum = sum + v
                n = n + 1
            elseif type(v) == "table" and depth < 6 then
                walk(v, depth + 1)
            end
        end
    end
    walk(j.total, 0)
    walk(j.pairs, 0)
    return sum .. ":" .. n
end

local candidate

local function startCandidate(j)
    if candidate then return end
    candidate = { id = j.id, t = KF.Now(), sig = fingerprint(j), data = KF.DeepCopy(j) }
    C_Timer.After(90, function()
        local c = candidate
        candidate = nil
        local now = c and KF.db.journeys[c.id]
        if now and fingerprint(now) ~= c.sig then
            KF.db.backup = { t = c.t, id = c.id, partner = now.partnerName, data = c.data }
        end
    end)
end

function S:OnHello(sender, text)
    local _, proto, version, tag = strsplit("|", text)
    local p, j = partnerAndJourney(sender)
    if not j then return end
    S.peer = nil
    if tonumber(proto) ~= PROTO then
        KF:Debug("sync: ignoring %s (protocol %s)", sender, tostring(proto))
        return
    end
    if j.partnerTag and tag and tag ~= "-" and j.partnerTag ~= tag then
        KF:Debug("sync: ignoring %s (a different BattleTag)", sender)
        return
    end
    S.peer = { name = p.name, version = version }
    startCandidate(j)
    wipe(sentSigs) -- they are (re)starting: send them everything again
    -- answer a friend who has just reached out, unless we have only just sent ourselves
    if GetTime() - lastPush >= REPLY_GAP then S:Schedule(1) end
end

function S:OnChapter(sender, text)
    local p, j = partnerAndJourney(sender)
    if not (j and S.peer and S.peer.name == p.name) then return end
    local _, me, partner, meClass, partnerClass, payload = strsplit("|", text)
    if not (validName(me) and validName(partner) and type(payload) == "string") then return end
    -- his "me" is my "partner"
    local pair, key = chapterFor(j, me, partner, classOf(meClass), classOf(partnerClass))
    for token in payload:gmatch("[^;]+") do
        local k, v = token:match("^([%w%.]+)=(%d+)$")
        v = tonumber(v)
        if k and v and v <= MAX_VALUE then
            local field, sub = DECODE[k], nil
            if not field then
                if k:match("^L[0-5]$") then field, sub = "lootPartner", tonumber(k:sub(2))
                elseif k:match("^P[0-5]$") then field, sub = "lootMe", tonumber(k:sub(2))
                elseif k:match("^y%.") and KF.TypeInfo[k:sub(3)] then field, sub = "types", k:sub(3)
                end
            end
            if field then
                local old, new = raise(j, pair, field, sub, v)
                if old then note(key, sub == nil and LABEL[field] or nil, old, new) end
            end
        end
    end
end

function S:OnRecord(sender, text)
    local p, j = partnerAndJourney(sender)
    if not (j and S.peer and S.peer.name == p.name) then return end
    local _, me, partner, kind, n, t, spell, target = strsplit("|", text)
    n, t = tonumber(n), tonumber(t)
    if not (t and t >= 0 and t <= 4e9) then t = nil end
    if not (validName(me) and validName(partner) and (kind == "hit" or kind == "crit") and n and n > 0 and n <= MAX_VALUE) then return end
    local pair, key = chapterFor(j, me, partner, nil, nil)
    local duo = pair.records.duo
    if not duo[kind] or n > duo[kind].n then
        duo[kind] = { n = n, s = (spell ~= "" and spell or nil), d = (target ~= "" and target or nil), t = t or KF.Now() }
        note(key, "@record")
    end
end

--------------------------------------------------------------------------------
-- The lists: a union, never a deletion
--------------------------------------------------------------------------------

local function num(v, max)
    v = tonumber(v)
    if v and v >= 0 and v <= (max or MAX_VALUE) then return math.floor(v) end
end

-- dates are seconds since 1970, far above the limit for counters
local function stamp(v)
    return num(v, 4e9)
end

local function name(s)
    if type(s) == "string" and s ~= "" then return s:sub(1, 40) end
end

local function key(s)
    if type(s) ~= "string" or s == "" or #s > 20 then return end
    return tonumber(s) or s
end

local function earlier(a, b)
    if (a or 0) == 0 then return b end
    if (b or 0) == 0 then return a end
    return math.min(a, b)
end

-- the first time anything happened is known now, so the journey's "first time" is used up
local function seen(j, kind, id, when)
    local k = kind .. ":" .. tostring(id)
    if not j.firsts[k] then j.firsts[k] = (when and when > 0) and when or KF.Now() end
end

local MERGE = {}

function MERGE.rares(j, pair, chapterKey, id, c, t, lv, nm)
    id, c, t, lv, nm = key(id), num(c), stamp(t), num(lv), name(nm)
    if not (id and c) then return end
    local e = pair.rares[id]
    if not e then
        pair.rares[id] = { n = nm, c = c, t = (t and t > 0) and t or KF.Now(), lv = lv }
        seen(j, "rare", id, t)
        return true
    end
    e.c, e.t, e.lv, e.n = math.max(e.c or 0, c), earlier(e.t, t), math.max(e.lv or 0, lv or 0), e.n or nm
end

function MERGE.bosses(j, pair, chapterKey, c, t, nm)
    c, t, nm = num(c), stamp(t), name(nm)
    if not (c and nm) then return end
    local e = pair.bosses[nm]
    if not e then
        pair.bosses[nm] = { c = c, t = (t and t > 0) and t or KF.Now() }
        seen(j, "boss", nm, t)
        return true
    end
    e.c, e.t = math.max(e.c or 0, c), earlier(e.t, t)
end

function MERGE.dungeons(j, pair, chapterKey, id, runs, spent, bosses, last, nm)
    id, runs, spent, bosses, last, nm = key(id), num(runs), num(spent), num(bosses), stamp(last), name(nm)
    if not (id and runs) then return end
    local e = pair.dungeons[id]
    if not e then
        pair.dungeons[id] = { n = nm, runs = runs, time = spent or 0, bosses = bosses or 0, last = last }
        seen(j, "dungeon", id, last)
        return true
    end
    e.runs, e.time, e.bosses = math.max(e.runs or 0, runs), math.max(e.time or 0, spent or 0), math.max(e.bosses or 0, bosses or 0)
    e.last, e.n = math.max(e.last or 0, last or 0), e.n or nm
end

function MERGE.zones(j, pair, chapterKey, t, nm)
    t, nm = stamp(t), name(nm)
    if not (t and nm) then return end
    local e = pair.zones[nm]
    if not e then
        pair.zones[nm] = (t > 0) and t or KF.Now()
        seen(j, "zone", nm, t)
        return true
    end
    pair.zones[nm] = earlier(e, t)
end

function MERGE.toughest(j, pair, chapterKey, lv, nm)
    lv, nm = num(lv, 1000), name(nm)
    if not (lv and nm) then return end
    if lv > ((pair.toughest and pair.toughest.lv) or 0) then pair.toughest = { n = nm, lv = lv } end
end

function MERGE.items(j, pair, chapterKey, id, q, c, theirMe, theirPartner, t, l, nm)
    id, q, c, theirMe, theirPartner, t, l, nm = key(id), num(q, 5), num(c), num(theirMe), num(theirPartner), stamp(t), stamp(l), name(nm)
    if not (id and q and c and theirMe and theirPartner) then return end
    local e = pair.items[id]
    -- his "me" is my "partner"
    if not e then
        pair.items[id] = { n = nm, q = q, c = c, me = theirPartner, pa = theirMe, t = (t and t > 0) and t or KF.Now(), l = (l and l > 0) and l or KF.Now() }
        return true
    end
    e.c, e.me, e.pa = math.max(e.c or 0, c), math.max(e.me or 0, theirPartner), math.max(e.pa or 0, theirMe)
    e.t, e.l, e.n = earlier(e.t, t), math.max(e.l or 0, l or 0), e.n or nm
end

function MERGE.mobs(j, pair, chapterKey, id, c, lv, ty, nm)
    id, c, lv, nm = key(id), num(c), num(lv), name(nm)
    if not (id and c) then return end
    local e = pair.mobs[id]
    if not e then
        pair.mobs[id] = { n = nm, c = c, lv = lv, ty = KF.TypeInfo[ty] and ty or "unspecified" }
        return true
    end
    e.c, e.lv, e.n = math.max(e.c or 0, c), math.max(e.lv or 0, lv or 0), e.n or nm
end

function S:OnList(sender, text)
    local p, j = partnerAndJourney(sender)
    if not (j and S.peer and S.peer.name == p.name) then return end
    local _, kind, me, partner, entries = strsplit("|", text)
    local merge = MERGE[kind]
    if not (merge and validName(me) and validName(partner) and type(entries) == "string") then return end
    local pair, chapterKey = chapterFor(j, me, partner, nil, nil)
    local count = 0
    for entry in entries:gmatch("[^;]+") do
        count = count + 1
        if count > 300 then break end
        local ok, added = pcall(merge, j, pair, chapterKey, strsplit(",", entry))
        if ok and added then note(chapterKey, "@new:" .. kind) end
    end
end

KF:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    prefix, text, sender = clean(prefix), clean(text), clean(sender)
    if prefix ~= KF.msgPrefix or type(text) ~= "string" or type(sender) ~= "string" or not KF.me then return end
    local kind = text:sub(1, 2)
    if kind ~= "H|" and kind ~= "C|" and kind ~= "R|" and kind ~= "L|" then return end -- ping and pong live in Core
    if KF.IsSender(sender, KF.me) then return end                      -- our own message echoed back
    if not KF.db.settings.sync then return end
    if KF.db.settings.debug then
        local p = KF.partner
        KF:Debug("sync: %s message from \"%s\" (your partner: \"%s\"): %s", kind:sub(1, 1), sender, p and p.key or "nobody", (p and KF.IsSender(sender, p)) and "accepted" or "ignored")
    end
    if kind == "H|" then S:OnHello(sender, text)
    elseif kind == "C|" then S:OnChapter(sender, text)
    elseif kind == "L|" then S:OnList(sender, text)
    else S:OnRecord(sender, text) end
end)

--------------------------------------------------------------------------------
-- When to sync
--------------------------------------------------------------------------------

KF:Listen("TOGETHER", function(together)
    if together then S:Schedule(3) end
end)

KF:Listen("RUN_FINISHED", function() S:Schedule(2) end)

KF:Listen("LOGIN", function()
    C_Timer.NewTicker(60, function()
        if KF.together and GetTime() - lastPush >= PERIOD then S:Push() end
    end)
end)
