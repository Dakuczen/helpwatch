-------------------------------------------------------------------
-- helpwatch - alerts on help / PvP / robbery calls in chat.
-- Captures chat IN-GAME via the CHAT_MESSAGE event (no log tailing,
-- so no foreign handle on the game's own files). Matched lines are
-- appended to alerts.log; helpwatch.ps1 relays them to Discord.
-------------------------------------------------------------------
if API_TYPE == nil then
    ADDON:ImportAPI(8)
    X2Chat:DispatchChatMessage(CMF_SYSTEM,
        "helpwatch: 'globals' folder not found - install it from the ArcheRage-addons repo")
    return
end

ADDON:ImportObject(OBJECT_TYPE.TEXT_STYLE)
ADDON:ImportObject(OBJECT_TYPE.WINDOW)
ADDON:ImportAPI(API_TYPE.CHAT.id)

-- ===== config =====
local OUT_PATH     = "../Documents/Addon/helpwatch/alerts.log"
local DEBUG_PATH   = "../Documents/Addon/helpwatch/debug.log"
local COOLDOWN     = 900     -- seconds; suppress an identical alert (matches watch.py)
local SHOW_IN_GAME = true    -- also print a local system-chat line on each match
local DEBUG        = true    -- log EVERY chat event to debug.log (channel id, isUserChat, msg)

local function dbg(s)
    local f = io.open(DEBUG_PATH, "a")
    if f then f:write(tostring(s) .. "\n"); f:close() end
end

-- channels we watch: in-game channel id -> label. Built defensively so a
-- missing constant can't crash the addon on load.
local WATCH = {}
local function watch(const, label) if const ~= nil then WATCH[const] = label end end
watch(CHAT_FACTION,    "Nation")
watch(CHAT_EXPEDITION, "Guild")   -- "guild" chat is the Expedition channel in ArcheAge
watch(CHAT_FAMILY,     "Family")
watch(CHAT_SAY,        "Local")

-- ===== tiny matching helpers (Lua patterns, not PCRE) =====
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

-- ===== classifier (ported from watch.py) =====
local LOCATIONS = { "marcala", "garden", "heedmar", "halcyona", "halcy", "hc", "hr", "cr",
    "crimson", "reedwind", "golden", "diamond", "ynystere", "sungold", "freedich", "cinder",
    "sunbite", "hellswamp", "hasla", "karkasse", "rookborne", "nuimari", "solzreed",
    "east", "west", "castle" }

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
    if string.find(c, "^%s*sos%f[%W]") then return true end
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
    local action = hasAny(c, { "come", "join", "push", "forming", "wanna", "who wants", "lets", "let's", "going" })
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
    local c = string.lower(message):gsub("%b[]", " ")  -- strip [link]/[item] tokens
    if tradeSpam(c) then return nil end
    if rawLink and pvpctx(c) then return "PvP-Raid" end
    if defense(c) then return "Defense" end
    if helpReq(c) or robbery(c) then return "Help" end
    if has(c, "pvp") and pvpActionable(c) then return "PvP" end
    return nil
end

-- ===== output: append to alerts.log (+ optional in-game line) =====
local lastSent = {}

local function emit(tier, label, name, message)
    local line = "[" .. tier .. "] [" .. label .. "] " .. tostring(name) .. ": " .. message
    local f = io.open(OUT_PATH, "a")
    if f then
        f:write(line .. "\n")
        f:close()
    end
    if SHOW_IN_GAME then
        X2Chat:DispatchChatMessage(CMF_SYSTEM, ">> " .. line)
    end
end

local function onChat(channel, relation, name, message, info)
    if DEBUG then
        local isUser = (info and info.isUserChat)
        dbg("chan=" .. tostring(channel) .. " isUser=" .. tostring(isUser)
            .. " mapped=" .. tostring(WATCH[channel])
            .. " name=" .. tostring(name) .. " msg=" .. tostring(message))
    end
    if not (info and info.isUserChat) then return end
    local label = WATCH[channel]
    if not label then return end
    if not message or message == "" then return end
    local tier = classify(message)
    if not tier then return end
    local key = tier .. "|" .. label .. "|" .. tostring(name) .. ":" .. message
    local now = os.time()
    if lastSent[key] and (now - lastSent[key]) < COOLDOWN then return end
    lastSent[key] = now
    emit(tier, label, name, message)
end

-- ===== chat event plumbing (same pattern as the translate addon) =====
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

dbg("=== helpwatch loaded at " .. tostring(os.time())
    .. " | mapped channels: Nation=" .. tostring(CHAT_FACTION)
    .. " Guild=" .. tostring(CHAT_EXPEDITION)
    .. " Family=" .. tostring(CHAT_FAMILY)
    .. " Local=" .. tostring(CHAT_SAY) .. " ===")
X2Chat:DispatchChatMessage(CMF_SYSTEM, "helpwatch loaded - watching Nation/Guild/Family/Local")
