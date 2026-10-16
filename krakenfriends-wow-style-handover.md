# Handover: KrakenChat's WoW style for Krakenfriends

**Goal:** give Krakenfriends the "WoW style" look that KrakenChat has (gold border, dark stone, fantasy-font title) as the new default. The current teal look stays available as "classic" (`/kf style classic`, switching back with `/kf style wow`).

The reference is KrakenChat (repo `Krakenhood/krakenchat`, branch `claude/zealous-fermi-u3h5fc`). Everything you need is below, so you don't have to open that repo.

## 1. Colours: swap the Theme table at load

Krakenfriends draws almost everything from `KF.Theme` (Data.lua). The WoW style replaces those values before any frame is built:

```lua
KF.Palettes = {
    wow = {
        bg      = { 0, 0, 0, 0 },          -- the backdrop draws the background
        panel   = { 0, 0, 0, 0.30 },
        hover   = { 1, 0.82, 0, 0.10 },
        line    = { 1, 0.82, 0, 0.22 },
        accent  = { 1, 0.82, 0 },           -- the game's gold (instead of teal)
        accent2 = { 0.70, 0.08, 0.06 },     -- the red of its buttons (instead of violet)
        text    = { 1, 1, 1 },
        dim     = { 0.78, 0.72, 0.60 },
        -- keep Krakenfriends' own keys such as `good` as they are, or tune them
    },
}
```

At the end of `KF:LoadDB()` (it runs at ADDON_LOADED, before the UI is built):

```lua
local palette = KF.Palettes[KF.db.settings.style ~= "classic" and "wow" or ""]
if palette then
    for k, v in pairs(palette) do KF.Theme[k] = v end
end
KF.palette = KF.db.settings.style  -- remember what was applied, to know when a reload is needed
```

Add `style = "wow"` to the settings DEFAULTS.

## 2. The frame: gold border on dark stone

In `UI:Create()`, where the backdrop is drawn now (the `bg`, `glow`, `Border` and teal-to-violet `rim`, around UI.lua line 1160), branch on the style. The WoW branch:

```lua
local WOW_EDGES = { "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", "Interface\\DialogFrame\\UI-DialogBox-Border" }
local WOW_BACKS = { "Interface\\FrameGeneral\\UI-Background-Rock", "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" }

-- the first file the client actually has (a missing file shows as a green square)
local function firstFile(list)
    for _, path in ipairs(list) do
        if not GetFileIDFromPath or call(GetFileIDFromPath, path) then return path end
    end
    return list[#list]
end

local function CreateWoWFrame(f, headerHeight)
    local frame = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetPoint("TOPLEFT", -7, 7)
    frame:SetPoint("BOTTOMRIGHT", 7, -7)
    frame:SetFrameLevel(math.max(0, f:GetFrameLevel()))
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = firstFile(WOW_BACKS), tile = true, tileSize = 256,
            edgeFile = firstFile(WOW_EDGES), edgeSize = 32,
            insets = { left = 9, right = 9, top = 9, bottom = 9 },
        })
        frame:SetBackdropColor(0.55, 0.55, 0.55, 1)
    end
    -- a dark band behind the header
    local band = f:CreateTexture(nil, "BACKGROUND")
    band:SetColorTexture(0, 0, 0, 0.45)
    band:SetPoint("TOPLEFT", 2, -2)
    band:SetPoint("TOPRIGHT", -2, -2)
    band:SetHeight(headerHeight)
    return frame, band
end
```

The toast (Minimap.lua) and the journey menu can get the same frame, or just inherit the new colours.

**Title:** the game's fantasy font, gold, with a fallback:

```lua
if not pcall(title.SetFont, title, "Fonts\\MORPHEUS.TTF", 17, "") then title:SetFont(FONT, 15, "") end
```

## 3. Switching

- `/kf style classic` and `/kf style wow`: the command needs the name, so nobody switches by accident. Set `settings.style`, then offer a reload, because the colours are baked into the frames when they're built:

```lua
StaticPopupDialogs.KRAKENFRIENDS_RELOAD = {
    text = "This look has a different frame and colours.\n\nReload the interface now to see it?",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
-- after changing settings.style:
if settings.style ~= KF.palette then StaticPopup_Show("KRAKENFRIENDS_RELOAD") end
```

## 4. Pitfalls we hit in KrakenChat

- **Colours are baked in at build time.** Swapping `Theme` later doesn't repaint anything, so switching always needs the reload.
- **Save switches as `false`, not `nil`,** when a default exists. `fill()` puts the default back into a `nil`, so the user's choice is lost after a reload.
- **Hard-coded teal:** about 18 `|cff4fd1c5` colour codes, mostly the chat-print prefix and slash help. Those can stay teal (they're the addon's name colour in chat), but check the ones that show inside the window.
- **Check by eye in the game:** portrait class rings, number tiles, tab underlines, record cards, quality bars and the milestone toast. Most follow `Theme`, but how teal-based highlights look in gold needs screenshots.
- **Saved data must stay untouched:** run `node compat.js <a real Krakenfriends.lua save>` in `tests/` before releasing.

## 5. Release

Krakenfriends is on CurseForge (1.2.0). Existing users get the new look on their next update, so put a line in the release notes, e.g. "New look in the game's own style; `/kf style classic` brings back the old one."
