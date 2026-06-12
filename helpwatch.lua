-------------------------------------------------------------------
-- helpwatch - alerts on help / PvP / robbery calls in chat.
-- Matched lines are written to alerts.log; helpwatch.ps1 relays
-- them to Discord. Configure via the [HW] button on screen.
-------------------------------------------------------------------
if API_TYPE == nil then
    ADDON:ImportAPI(8)
    X2Chat:DispatchChatMessage(CMF_SYSTEM,
        "helpwatch: 'globals' folder not found - install it from the ArcheRage-addons repo")
    return
end

ADDON:ImportObject(OBJECT_TYPE.TEXT_STYLE)
ADDON:ImportObject(OBJECT_TYPE.BUTTON)
ADDON:ImportObject(OBJECT_TYPE.DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.NINE_PART_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.COLOR_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.WINDOW)
ADDON:ImportObject(OBJECT_TYPE.LABEL)
ADDON:ImportObject(OBJECT_TYPE.ICON_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.IMAGE_DRAWABLE)
ADDON:ImportObject(OBJECT_TYPE.EDITBOX_MULTILINE)
ADDON:ImportAPI(API_TYPE.CHAT.id)

-- ===== paths =====
local SETTINGS_PATH = "../Documents/Addon/helpwatch/helpwatch_settings.txt"
local OUT_PATH      = "../Documents/Addon/helpwatch/alerts.log"
local DEBUG_PATH    = "../Documents/Addon/helpwatch/debug.log"
local DEBUG         = false

-- ===== settings =====
local DEFAULT = {
    watch_nation  = true,
    watch_guild   = true,
    watch_family  = true,
    watch_local   = true,
    alert_help    = true,
    alert_defense = true,
    alert_pvp     = true,
    alert_pvpraid = true,
    cooldown      = 900,
    show_in_game  = true,
    webhook       = "",
}

local cfg = {}
for k, v in pairs(DEFAULT) do cfg[k] = v end

local function loadSettings()
    local f = io.open(SETTINGS_PATH, "r")
    if not f then return end
    for line in f:lines() do
        local key, val = line:match("^([%w_]+)=(.*)$")
        if key then
            key = key:lower()
            if DEFAULT[key] ~= nil then
                if type(DEFAULT[key]) == "boolean" then
                    cfg[key] = (val == "true")
                elseif type(DEFAULT[key]) == "number" then
                    cfg[key] = tonumber(val) or DEFAULT[key]
                else
                    cfg[key] = val
                end
            end
        end
    end
    f:close()
end

local function saveSettings()
    local f = io.open(SETTINGS_PATH, "w")
    if not f then
        X2Chat:DispatchChatMessage(CMF_SYSTEM, "helpwatch: could not write settings file.")
        return
    end
    f:write("WATCH_NATION="   .. tostring(cfg.watch_nation)  .. "\n")
    f:write("WATCH_GUILD="    .. tostring(cfg.watch_guild)   .. "\n")
    f:write("WATCH_FAMILY="   .. tostring(cfg.watch_family)  .. "\n")
    f:write("WATCH_LOCAL="    .. tostring(cfg.watch_local)   .. "\n")
    f:write("ALERT_HELP="     .. tostring(cfg.alert_help)    .. "\n")
    f:write("ALERT_DEFENSE="  .. tostring(cfg.alert_defense) .. "\n")
    f:write("ALERT_PVP="      .. tostring(cfg.alert_pvp)     .. "\n")
    f:write("ALERT_PVPRAID="  .. tostring(cfg.alert_pvpraid) .. "\n")
    f:write("COOLDOWN="       .. tostring(cfg.cooldown)      .. "\n")
    f:write("SHOW_IN_GAME="   .. tostring(cfg.show_in_game)  .. "\n")
    f:write("WEBHOOK="        .. tostring(cfg.webhook)       .. "\n")
    f:close()
end

loadSettings()

-- ===== watch table (rebuilt when channel settings change) =====
local WATCH = {}
local function rebuildWatch()
    WATCH = {}
    if cfg.watch_nation  and CHAT_FACTION    ~= nil then WATCH[CHAT_FACTION]    = "Nation" end
    if cfg.watch_guild   and CHAT_EXPEDITION ~= nil then WATCH[CHAT_EXPEDITION] = "Guild"  end
    if cfg.watch_family  and CHAT_FAMILY     ~= nil then WATCH[CHAT_FAMILY]     = "Family" end
    if cfg.watch_local   and CHAT_SAY        ~= nil then WATCH[CHAT_SAY]        = "Local"  end
end
rebuildWatch()

-- ===== debug =====
local function dbg(s)
    if not DEBUG then return end
    local f = io.open(DEBUG_PATH, "a")
    if f then f:write(tostring(s) .. "\n"); f:close() end
end

-- ===== matching helpers =====
local function has(s, sub) return string.find(s, sub, 1, true) ~= nil end
local function hasAny(s, list)
    for _, k in ipairs(list) do if has(s, k) then return true end end
    return false
end
local function hasWord(s, w) return string.find(s, "%f[%w]" .. w .. "%f[%W]") ~= nil end
local function hasAnyWord(s, list)
    for _, w in ipairs(list) do if hasWord(s, w) then return true end end
    return false
end

-- ===== classifier =====
local LOCATIONS = {
    "marcala", "garden", "heedmar", "halcyona", "halcy", "hc", "hr", "cr",
    "crimson", "reedwind", "golden", "diamond", "ynystere", "sungold", "freedich",
    "cinder", "sunbite", "hellswamp", "hasla", "karkasse", "rookborne", "nuimari",
    "solzreed", "east", "west", "castle"
}

local function pvpctx(c)
    return has(c, "pvp") or hasWord(c, "reds") or hasWord(c, "red")
        or has(c, "zerg") or has(c, "gank") or has(c, "contest") or hasWord(c, "inc")
end

local function defense(c)
    return hasAnyWord(c, { "inc", "incoming", "zerg" })
        or has(c, "gank") or has(c, "contest")
        or hasWord(c, "reds") or string.find(c, "%d+%s*red")
        or has(c, "defend") or has(c, "heads up") or has(c, "save us")
end

local function helpReq(c)
    if string.find(c, "^%s*help%f[%W]") then return true end
    if string.find(c, "^%s*sos%f[%W]")  then return true end
    return hasAny(c, { "help me", "someone help", "anyone help", "plz help", "pls help",
        "need help", "help with", "help nory" })
        or hasWord(c, "sos")
        or has(c, "rez") or has(c, "ress") or has(c, "res me") or has(c, "revive")
end

local function robbery(c)
    if hasAny(c, { "getting robbed", "gettin robbed", "being robbed", "been robbed",
        "got robbed", "robbing me", "robbing us", "robbing my", "robbing our" }) then
        return true
    end
    local theft = has(c, "stole") or has(c, "stolen") or has(c, "stealing")
        or has(c, "robbed") or has(c, "robbing")
    local victim = hasAnyWord(c, { "my", "our", "me" })
        or hasAny(c, { "pack", "merch", "cargo", "tradepack", "gilda" })
    local gossip = hasAnyWord(c, { "heard", "probably", "hope", "ive", "people",
        "his", "her", "their", "your", "you" }) or has(c, "i've")
    return theft and victim and not gossip
end

local function pvpActionable(c)
    local banter = string.find(c, "%?")
        or hasAnyWord(c, { "was", "been", "still", "thought", "heard", "login", "died", "exist" })
        or has(c, "how") or has(c, "ty for") or has(c, "no pvp")
        or has(c, "any other") or has(c, "going on") or has(c, "in case") or has(c, "not for real")
    if banter then return false end
    local action = hasAny(c, { "come", "join", "push", "forming", "wanna", "who wants",
        "lets", "let's", "going" })
        or hasWord(c, "lf") or string.find(c, "%f[%a]x%s+pvp") or has(c, "go pvp")
    local location = hasAnyWord(c, LOCATIONS) or has(c, "growl")
    return action or location
end

local function tradeSpam(c)
    return hasAny(c, { "wts", "wtb", "wtt", "/each", "mail me", "on ah", "gold" })
        or string.find(c, "%d%s*g%f[%A]")
end

local function classify(message)
    local rawLink = has(message, "Recruit Any:") or has(message, "PvP/PvE")
    local c = string.lower(message):gsub("%b[]", " ")
    if tradeSpam(c) then return nil end
    if rawLink and pvpctx(c) then return cfg.alert_pvpraid and "PvP-Raid" or nil end
    if defense(c)             then return cfg.alert_defense and "Defense"  or nil end
    if helpReq(c) or robbery(c) then return cfg.alert_help and "Help"    or nil end
    if has(c, "pvp") and pvpActionable(c) then return cfg.alert_pvp and "PvP" or nil end
    return nil
end

-- ===== emit =====
local lastSent = {}

local function emit(tier, label, name, message)
    local line = "[" .. tier .. "] [" .. label .. "] " .. tostring(name) .. ": " .. message
    local f = io.open(OUT_PATH, "a")
    if f then f:write(line .. "\n"); f:close() end
    if cfg.show_in_game then
        X2Chat:DispatchChatMessage(CMF_SYSTEM, ">> " .. line)
    end
end

local function onChat(channel, relation, name, message, info)
    if not (info and info.isUserChat) then return end
    local label = WATCH[channel]
    if not label then return end
    if not message or message == "" then return end
    local tier = classify(message)
    if not tier then return end
    local key = tier .. "|" .. label .. "|" .. tostring(name) .. ":" .. message
    local now = os.time()
    if lastSent[key] and (now - lastSent[key]) < cfg.cooldown then return end
    lastSent[key] = now
    emit(tier, label, name, message)
end

-- ===== settings window =====
-- Width must be one of the predefined sizes in windowcommon.lua
local WIN_W, WIN_H = 350, 400
local COL1_X, COL2_X = 16, 179   -- two-column button layout
local BTN_W, BTN_H = 155, 26
local COLOR_ON  = { 0.30, 0.90, 0.42, 1 }
local COLOR_OFF = { 0.80, 0.30, 0.30, 1 }
local COLOR_HDR = { 0.90, 0.75, 0.40, 1 }

local settingsWindow = CreateBasicWindow("helpwatchSettings", "helpwatch settings",
    WIN_W, WIN_H, "CENTER", 0, 0)
settingsWindow:Show(false)

local function makeHeader(text, yPos)
    local lbl = settingsWindow:CreateChildWidget("label", "hw_h_" .. yPos, 0, false)
    lbl:SetText(text)
    lbl:AddAnchor("TOPLEFT", settingsWindow, COL1_X, yPos)
    lbl.style:SetFontSize(13)
    lbl.style:SetColor(COLOR_HDR[1], COLOR_HDR[2], COLOR_HDR[3], COLOR_HDR[4])
    return lbl
end

local function applyToggleColor(btn, on)
    local c = on and COLOR_ON or COLOR_OFF
    SetButtonFontOneColor(btn, c)
end

local function makeToggle(label, key, xPos, yPos)
    local btn = CreateActionButton({
        parent      = settingsWindow,
        name        = "hw_t_" .. key,
        anchor      = "TOPLEFT",
        anchorTarget = settingsWindow,
        offsetX     = xPos,
        offsetY     = yPos,
        text        = label .. ": " .. (cfg[key] and "ON" or "OFF"),
        width       = BTN_W,
        height      = BTN_H,
        handlers    = {
            OnClick = function(self)
                cfg[key] = not cfg[key]
                self:SetText(label .. ": " .. (cfg[key] and "ON" or "OFF"))
                applyToggleColor(self, cfg[key])
                if key:sub(1, 6) == "watch_" then rebuildWatch() end
            end,
        },
    })
    btn:SetStyle("text_default")
    applyToggleColor(btn, cfg[key])
    return btn
end

-- Channels
makeHeader("Channels", 52)
makeToggle("Nation",  "watch_nation",  COL1_X, 74)
makeToggle("Guild",   "watch_guild",   COL2_X, 74)
makeToggle("Family",  "watch_family",  COL1_X, 106)
makeToggle("Local",   "watch_local",   COL2_X, 106)

-- Alert types
makeHeader("Alert types", 142)
makeToggle("Help / SOS", "alert_help",     COL1_X, 164)
makeToggle("Defense",    "alert_defense",  COL2_X, 164)
makeToggle("PvP",        "alert_pvp",      COL1_X, 196)
makeToggle("PvP Raid",   "alert_pvpraid",  COL2_X, 196)

-- Options
makeHeader("Options", 232)
makeToggle("In-game popup", "show_in_game", COL1_X, 254)

-- Webhook URL
makeHeader("Discord webhook URL", 292)

local webhookBg = settingsWindow:CreateColorDrawable(0.05, 0.05, 0.05, 0.85, "background")
webhookBg:AddAnchor("TOPLEFT", settingsWindow, COL1_X, 312)
webhookBg:SetExtent(WIN_W - COL1_X * 2, 28)

local webhookBox = settingsWindow:CreateChildWidget("editboxmultiline", "hw_webhook", 0, true)
webhookBox:AddAnchor("TOPLEFT", settingsWindow, COL1_X, 312)
webhookBox:SetWidth(WIN_W - COL1_X * 2)
webhookBox:SetHeight(28)
webhookBox:SetInset(5, 5, 5, 5)
webhookBox:SetMaxTextLength(256)
webhookBox:SetGuideText("https://discord.com/api/webhooks/...")

-- populate webhook field whenever window opens
settingsWindow.ShowProc = function()
    webhookBox:SetText(cfg.webhook or "")
end

-- Save button
local saveBtn = CreateActionButton({
    parent      = settingsWindow,
    name        = "hw_save",
    anchor      = "BOTTOM",
    anchorTarget = settingsWindow,
    offsetX     = 0,
    offsetY     = -14,
    text        = "Save",
    width       = 110,
    height      = 30,
    handlers    = {
        OnClick = function()
            cfg.webhook = webhookBox:GetText()
            saveSettings()
            rebuildWatch()
            X2Chat:DispatchChatMessage(CMF_SYSTEM, "helpwatch: settings saved.")
            settingsWindow:Show(false)
        end,
    },
})
saveBtn:SetStyle("text_default")
SetButtonFontOneColor(saveBtn, COLOR_ON)

-- ===== [HW] toggle button =====
local hwFrame = CreateEmptyWindow("helpwatchBtnFrame", "UIParent")
hwFrame:SetExtent(52, 24)
hwFrame:AddAnchor("TOPRIGHT", "UIParent", -6, 190)
hwFrame:Show(true)
hwFrame:EnableDrag(true)

local hwBtn = CreateActionButton({
    parent      = hwFrame,
    name        = "helpwatchBtn",
    anchor      = "CENTER",
    anchorTarget = hwFrame,
    offsetX     = 0,
    offsetY     = 0,
    text        = "[HW]",
    width       = 52,
    height      = 24,
    handlers    = {
        OnClick = function()
            settingsWindow:Show(not settingsWindow:IsVisible())
        end,
    },
})
hwBtn:SetStyle("text_default")
SetButtonFontOneColor(hwBtn, COLOR_HDR)

-- ===== chat event plumbing =====
local events = {
    CHAT_MESSAGE = function(channel, relation, name, message, info)
        onChat(channel, relation, name, message, info)
    end,
}

local listener = CreateEmptyWindow("helpwatchListener", "UIParent")
listener:Show(false)
listener:SetHandler("OnEvent", function(this, event, ...)
    events[event](...)
end)
listener:RegisterEvent("CHAT_MESSAGE")

dbg("=== helpwatch loaded at " .. tostring(os.time()) .. " ===")
X2Chat:DispatchChatMessage(CMF_SYSTEM, "helpwatch loaded  -  click [HW] to configure")
