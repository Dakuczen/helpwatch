-------------------------------------------------------------------
-- helpwatch  |  alert on help / pvp / robbery calls in chat
-- Click [HW] to open settings, or type !hw help in Local chat.
-------------------------------------------------------------------
if API_TYPE == nil then
    ADDON:ImportAPI(8)
    X2Chat:DispatchChatMessage(CMF_SYSTEM,
        "helpwatch: 'globals' folder not found")
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

-- ===== defaults =====
local DEFAULT = {
    watch_nation     = true,
    watch_guild      = true,
    watch_family     = true,
    watch_local      = true,
    watch_whisper    = true,
    alert_help       = true,
    alert_defense    = true,
    alert_pvp        = true,
    alert_pvpraid    = true,
    cooldown         = 900,
    show_in_game     = true,
    webhook_default  = "",
    webhook_help     = "",
    webhook_defense  = "",
    webhook_pvp      = "",
    webhook_pvpraid  = "",
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
                if     type(DEFAULT[key]) == "boolean" then cfg[key] = (val == "true")
                elseif type(DEFAULT[key]) == "number"  then cfg[key] = tonumber(val) or DEFAULT[key]
                else                                        cfg[key] = val
                end
            end
        end
    end
    f:close()
end

local function saveSettings()
    local f = io.open(SETTINGS_PATH, "w")
    if not f then
        X2Chat:DispatchChatMessage(CMF_SYSTEM, "helpwatch: could not write settings.")
        return
    end
    local function w(k) f:write(k:upper() .. "=" .. tostring(cfg[k]) .. "\n") end
    w("watch_nation"); w("watch_guild"); w("watch_family"); w("watch_local"); w("watch_whisper")
    w("alert_help"); w("alert_defense"); w("alert_pvp"); w("alert_pvpraid")
    w("cooldown"); w("show_in_game")
    w("webhook_default"); w("webhook_help"); w("webhook_defense")
    w("webhook_pvp"); w("webhook_pvpraid")
    f:close()
end

loadSettings()

-- ===== watch table =====
local WATCH = {}
local function rebuildWatch()
    WATCH = {}
    if cfg.watch_nation  and CHAT_FACTION    ~= nil then WATCH[CHAT_FACTION]    = "Nation" end
    if cfg.watch_guild   and CHAT_EXPEDITION ~= nil then WATCH[CHAT_EXPEDITION] = "Guild"  end
    if cfg.watch_family  and CHAT_FAMILY     ~= nil then WATCH[CHAT_FAMILY]     = "Family" end
    if cfg.watch_local   and CHAT_SAY        ~= nil then WATCH[CHAT_SAY]        = "Local"   end
    if cfg.watch_whisper and CHAT_WHISPER    ~= nil then WATCH[CHAT_WHISPER]    = "Whisper" end
end
rebuildWatch()

-- ===== matching helpers =====
local function has(s, sub) return string.find(s, sub, 1, true) ~= nil end
local function hasAny(s, list)
    for _, k in ipairs(list) do if has(s, k) then return true end end
end
local function hasWord(s, w) return string.find(s, "%f[%w]" .. w .. "%f[%W]") ~= nil end
local function hasAnyWord(s, list)
    for _, w in ipairs(list) do if hasWord(s, w) then return true end end
end

-- ===== classifier =====
local LOCATIONS = {
    "marcala","garden","heedmar","halcyona","halcy","hc","hr","cr",
    "crimson","reedwind","golden","diamond","ynystere","sungold","freedich",
    "cinder","sunbite","hellswamp","hasla","karkasse","rookborne","nuimari",
    "solzreed","east","west","castle"
}

local function pvpctx(c)
    return has(c,"pvp") or hasWord(c,"reds") or hasWord(c,"red")
        or has(c,"zerg") or has(c,"gank") or has(c,"contest") or hasWord(c,"inc")
end
local function defense(c)
    return hasAnyWord(c,{"inc","incoming","zerg"})
        or has(c,"gank") or has(c,"contest")
        or hasWord(c,"reds") or string.find(c,"%d+%s*red")
        or has(c,"defend") or has(c,"heads up") or has(c,"save us")
end
local function helpReq(c)
    if string.find(c,"^%s*help%f[%W]") then return true end
    if string.find(c,"^%s*sos%f[%W]")  then return true end
    return hasAny(c,{"help me","someone help","anyone help","plz help","pls help",
        "need help","help with","help nory"})
        or hasWord(c,"sos")
        or has(c,"rez") or has(c,"ress") or has(c,"res me") or has(c,"revive")
end
local function robbery(c)
    if hasAny(c,{"getting robbed","gettin robbed","being robbed","been robbed",
        "got robbed","robbing me","robbing us","robbing my","robbing our"}) then return true end
    local theft  = has(c,"stole") or has(c,"stolen") or has(c,"stealing") or has(c,"robbed") or has(c,"robbing")
    local victim = hasAnyWord(c,{"my","our","me"}) or hasAny(c,{"pack","merch","cargo","tradepack","gilda"})
    local gossip = hasAnyWord(c,{"heard","probably","hope","ive","people","his","her","their","your","you"}) or has(c,"i've")
    return theft and victim and not gossip
end
local function pvpActionable(c)
    local banter = string.find(c,"%?")
        or hasAnyWord(c,{"was","been","still","thought","heard","login","died","exist"})
        or has(c,"how") or has(c,"ty for") or has(c,"no pvp")
        or has(c,"any other") or has(c,"going on") or has(c,"in case") or has(c,"not for real")
    if banter then return false end
    return hasAny(c,{"come","join","push","forming","wanna","who wants","lets","let's","going"})
        or hasWord(c,"lf") or string.find(c,"%f[%a]x%s+pvp") or has(c,"go pvp")
        or hasAnyWord(c,LOCATIONS) or has(c,"growl")
end
local function tradeSpam(c)
    return hasAny(c,{"wts","wtb","wtt","/each","mail me","on ah","gold"})
        or string.find(c,"%d%s*g%f[%A]")
end

local function classify(message)
    local rawLink = has(message,"Recruit Any:") or has(message,"PvP/PvE")
    local c = string.lower(message):gsub("%b[]"," ")
    if tradeSpam(c) then return nil end
    if rawLink and pvpctx(c)            then return cfg.alert_pvpraid and "PvP-Raid" or nil end
    if defense(c)                       then return cfg.alert_defense and "Defense"  or nil end
    if helpReq(c) or robbery(c)         then return cfg.alert_help    and "Help"     or nil end
    if has(c,"pvp") and pvpActionable(c) then return cfg.alert_pvp    and "PvP"      or nil end
end

-- ===== alert popup =====
local POPUP_DURATION = 6
local popupTimer     = 0

local alertPopup = CreateEmptyWindow("helpwatchPopup", "UIParent")
alertPopup:SetExtent(440, 50)
alertPopup:AddAnchor("TOP", "UIParent", 0, 120)
alertPopup:Show(false)
alertPopup:EnableDrag(true)
alertPopup:SetHandler("OnDragStart", function(self) self:StartMoving() end)
alertPopup:SetHandler("OnDragStop",  function(self) self:StopMovingOrSizing() end)

local popupBg = alertPopup:CreateColorDrawable(0.10, 0.04, 0.04, 0.92, "background")
popupBg:AddAnchor("TOPLEFT",     alertPopup, 0, 0)
popupBg:AddAnchor("BOTTOMRIGHT", alertPopup, 0, 0)

local popupLabel = alertPopup:CreateChildWidget("label", "hw_popup_lbl", 0, false)
popupLabel:AddAnchor("CENTER", alertPopup, 0, 0)
popupLabel.style:SetFontSize(14)
popupLabel.style:SetColor(1, 0.88, 0.25, 1)
popupLabel.style:SetAlign(ALIGN_CENTER)

alertPopup:SetHandler("OnUpdate", function(self, dt)
    if popupTimer > 0 then
        popupTimer = popupTimer - dt
        if popupTimer <= 0 then self:Show(false) end
    end
end)

-- ===== emit =====
local lastSent = {}

local function emit(tier, label, name, message)
    local line = "[" .. tier .. "] [" .. label .. "] " .. tostring(name) .. ": " .. message
    local f = io.open(OUT_PATH, "a")
    if f then f:write(line .. "\n"); f:close() end
    if cfg.show_in_game then
        popupLabel:SetText(line)
        popupTimer = POPUP_DURATION
        alertPopup:Show(true)
        X2Chat:DispatchChatMessage(CMF_SYSTEM, ">> " .. line)
    end
end

-- ===== settings window =====
local WIN_W  = 380
local WIN_H  = 460
local PAD    = 14
local BTN_W  = 160
local BTN_H  = 26

local C_BG     = { 0.94, 0.88, 0.74, 1.00 }
local C_BORDER = { 0.55, 0.40, 0.18, 1.00 }
local C_ON     = { 0.10, 0.45, 0.10, 1 }
local C_OFF    = { 0.60, 0.12, 0.08, 1 }
local C_HDR    = { 0.38, 0.18, 0.04, 1 }
local C_TAB_A  = { 0.38, 0.18, 0.04, 1 }   -- active tab
local C_TAB_I  = { 0.65, 0.50, 0.30, 1 }   -- inactive tab

local sw = CreateEmptyWindow("helpwatchSettings", "UIParent")
sw:SetExtent(WIN_W, WIN_H)
sw:AddAnchor("CENTER", "UIParent", 0, 0)
sw:Show(false)
sw:EnableDrag(true)
sw:SetCloseOnEscape(true)
sw:SetHandler("OnDragStart", function(self) self:StartMoving() end)
sw:SetHandler("OnDragStop",  function(self) self:StopMovingOrSizing() end)

local swBorder = sw:CreateColorDrawable(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1, "background")
swBorder:AddAnchor("TOPLEFT",     sw, 0, 0)
swBorder:AddAnchor("BOTTOMRIGHT", sw, 0, 0)

local swBg = sw:CreateColorDrawable(C_BG[1], C_BG[2], C_BG[3], 1, "background")
swBg:AddAnchor("TOPLEFT",     sw,  2,  2)
swBg:AddAnchor("BOTTOMRIGHT", sw, -2, -2)

local swTitle = sw:CreateChildWidget("label", "hw_title", 0, false)
swTitle:SetText("helpwatch settings")
swTitle:AddAnchor("TOP", sw, 0, 10)
swTitle.style:SetFontSize(16)
swTitle.style:SetColor(C_HDR[1], C_HDR[2], C_HDR[3], 1)
swTitle.style:SetAlign(ALIGN_CENTER)

local swClose = CreateActionButton({
    parent=sw, name="hw_close", anchor="TOPRIGHT", anchorTarget=sw,
    offsetX=-PAD, offsetY=8, text="X", width=22, height=22,
    handlers={OnClick=function() sw:Show(false) end},
})
swClose:SetStyle("text_default")
SetButtonFontOneColor(swClose, C_HDR)

-- ===== tab system =====
local TABS      = { "Channels & Alerts", "Webhooks", "Options" }
local TAB_BTN_W = 118
local TAB_Y     = 36
local CONTENT_Y = 68

local activeTab   = 1
local tabBtns     = {}
local tabWidgets  = { {}, {}, {} }   -- per-tab widget lists

local function showTab(n)
    activeTab = n
    for t = 1, #TABS do
        for _, w in ipairs(tabWidgets[t]) do w:Show(t == n) end
        if tabBtns[t] then
            SetButtonFontOneColor(tabBtns[t], t == n and C_TAB_A or C_TAB_I)
        end
    end
end

for i, name in ipairs(TABS) do
    local xOff = PAD + (i - 1) * (TAB_BTN_W + 4)
    local btn  = CreateActionButton({
        parent=sw, name="hw_tab"..i, anchor="TOPLEFT", anchorTarget=sw,
        offsetX=xOff, offsetY=TAB_Y, text=name,
        width=TAB_BTN_W, height=24,
        handlers={OnClick=function() showTab(i) end},
    })
    btn:SetStyle("text_default")
    tabBtns[i] = btn
end

-- tab divider line
local tabLine = sw:CreateColorDrawable(C_BORDER[1], C_BORDER[2], C_BORDER[3], 0.8, "background")
tabLine:AddAnchor("TOPLEFT",  sw, 2, CONTENT_Y - 2)
tabLine:SetExtent(WIN_W - 4, 1)

-- helper: register a widget to a tab so it gets shown/hidden
local function reg(t, w) tabWidgets[t][#tabWidgets[t]+1] = w; w:Show(false) end

-- helper: section header label
local function hdr(t, text, y)
    local lbl = sw:CreateChildWidget("label", "hw_h"..t.."_"..y, 0, false)
    lbl:SetText(text)
    lbl:AddAnchor("TOPLEFT", sw, PAD, y)
    lbl.style:SetFontSize(13)
    lbl.style:SetColor(C_HDR[1], C_HDR[2], C_HDR[3], 1)
    reg(t, lbl)
    return lbl
end

-- helper: ON/OFF toggle button
local function toggle(t, label, key, x, y)
    local btn = CreateActionButton({
        parent=sw, name="hw_t_"..key, anchor="TOPLEFT", anchorTarget=sw,
        offsetX=x, offsetY=y,
        text=label..": "..(cfg[key] and "ON" or "OFF"),
        width=BTN_W, height=BTN_H,
        handlers={
            OnClick=function(self)
                cfg[key] = not cfg[key]
                self:SetText(label..": "..(cfg[key] and "ON" or "OFF"))
                self:SetExtent(BTN_W, BTN_H)
                SetButtonFontOneColor(self, cfg[key] and C_ON or C_OFF)
                if key:sub(1,6) == "watch_" then rebuildWatch() end
            end,
        },
    })
    btn:SetStyle("text_default")
    SetButtonFontOneColor(btn, cfg[key] and C_ON or C_OFF)
    reg(t, btn)
    return btn
end

-- ===== TAB 1: Channels & Alerts =====
local C2X = PAD + BTN_W + 8   -- second column x

hdr(1, "Channels", CONTENT_Y + 4)
toggle(1, "Nation",  "watch_nation",  PAD, CONTENT_Y + 22)
toggle(1, "Guild",   "watch_guild",   C2X, CONTENT_Y + 22)
toggle(1, "Family",  "watch_family",   PAD, CONTENT_Y + 54)
toggle(1, "Local",   "watch_local",   C2X, CONTENT_Y + 54)
toggle(1, "Whisper", "watch_whisper", PAD, CONTENT_Y + 86)

hdr(1, "Alert types", CONTENT_Y + 122)
toggle(1, "Help / SOS", "alert_help",     PAD, CONTENT_Y + 140)
toggle(1, "Defense",    "alert_defense",  C2X, CONTENT_Y + 140)
toggle(1, "PvP",        "alert_pvp",      PAD, CONTENT_Y + 172)
toggle(1, "PvP Raid",   "alert_pvpraid",  C2X, CONTENT_Y + 172)

-- ===== TAB 2: Webhooks =====
-- single shared editbox; type-selector buttons switch which webhook is being edited
local WH_TYPES  = { "default", "help", "defense", "pvp", "pvpraid" }
local WH_LABELS = { "Default", "Help", "Defense", "PvP", "PvP-Raid" }
local whSelIdx  = 1   -- currently selected type index
local whTypeBtns = {}

local function whKey(i) return "webhook_" .. WH_TYPES[i] end

-- type selector buttons
local WH_BTN_W = 62
local function updateWhTypeBtns()
    for i, b in ipairs(whTypeBtns) do
        SetButtonFontOneColor(b, i == whSelIdx and C_TAB_A or C_TAB_I)
    end
end

local WHY = CONTENT_Y + 4
hdr(2, "Select type:", WHY)

for i, lbl in ipairs(WH_LABELS) do
    local xOff = PAD + (i-1)*(WH_BTN_W + 3)
    local btn  = CreateActionButton({
        parent=sw, name="hw_wh_sel"..i, anchor="TOPLEFT", anchorTarget=sw,
        offsetX=xOff, offsetY=WHY + 18,
        text=lbl, width=WH_BTN_W, height=22,
        handlers={
            OnClick=function()
                whSelIdx = i
                updateWhTypeBtns()
                -- populate editbox with current value for this type
                if whEditBox then
                    whEditBox:SetText(cfg[whKey(i)] or "")
                end
            end,
        },
    })
    btn:SetStyle("text_default")
    whTypeBtns[i] = btn
    reg(2, btn)
end

local whHdr2 = hdr(2, "Webhook URL:", WHY + 48)

local whBg = sw:CreateColorDrawable(0.80, 0.72, 0.55, 1.0, "background")
whBg:AddAnchor("TOPLEFT", sw, PAD, WHY + 64)
whBg:SetExtent(WIN_W - PAD*2, 28)
reg(2, whBg)

local whEditBox = sw:CreateChildWidget("editboxmultiline", "hw_wh_edit", 0, true)
whEditBox:AddAnchor("TOPLEFT", sw, PAD, WHY + 64)
whEditBox:SetWidth(WIN_W - PAD*2)
whEditBox:SetHeight(26)
whEditBox:SetInset(4, 4, 4, 4)
whEditBox:SetMaxTextLength(256)
reg(2, whEditBox)

local whApply = CreateActionButton({
    parent=sw, name="hw_wh_apply", anchor="TOPLEFT", anchorTarget=sw,
    offsetX=PAD, offsetY=WHY + 100,
    text="Apply", width=90, height=26,
    handlers={
        OnClick=function()
            cfg[whKey(whSelIdx)] = whEditBox:GetText()
            saveSettings()
            X2Chat:DispatchChatMessage(CMF_SYSTEM,
                "helpwatch: " .. WH_LABELS[whSelIdx] .. " webhook saved.")
        end,
    },
})
whApply:SetStyle("text_default")
SetButtonFontOneColor(whApply, C_ON)
reg(2, whApply)

local whHint = sw:CreateChildWidget("label", "hw_wh_hint", 0, false)
whHint:SetText("!hw set webhook <type> <url>  |  types: default help defense pvp pvpraid")
whHint:AddAnchor("TOPLEFT", sw, PAD, WHY + 134)
whHint.style:SetFontSize(11)
whHint.style:SetColor(C_HDR[1], C_HDR[2], C_HDR[3], 0.75)
reg(2, whHint)

local whHint2 = sw:CreateChildWidget("label", "hw_wh_hint2", 0, false)
whHint2:SetText("Leave empty to use Default. Type in Local chat.")
whHint2:AddAnchor("TOPLEFT", sw, PAD, WHY + 150)
whHint2.style:SetFontSize(11)
whHint2.style:SetColor(C_HDR[1], C_HDR[2], C_HDR[3], 0.75)
reg(2, whHint2)

-- ===== TAB 3: Options =====
local OY = CONTENT_Y + 4
hdr(3, "Display", OY)
toggle(3, "In-game popup", "show_in_game", PAD, OY + 18)

hdr(3, "Cooldown (seconds)", OY + 60)

local cdBg = sw:CreateColorDrawable(0.80, 0.72, 0.55, 1.0, "background")
cdBg:AddAnchor("TOPLEFT", sw, PAD, OY + 78)
cdBg:SetExtent(80, 26)
reg(3, cdBg)

local cdBox = sw:CreateChildWidget("editboxmultiline", "hw_cd_edit", 0, true)
cdBox:AddAnchor("TOPLEFT", sw, PAD, OY + 78)
cdBox:SetWidth(80)
cdBox:SetHeight(26)
cdBox:SetInset(4, 4, 4, 4)
cdBox:SetMaxTextLength(6)
reg(3, cdBox)

local cdApply = CreateActionButton({
    parent=sw, name="hw_cd_apply", anchor="TOPLEFT", anchorTarget=sw,
    offsetX=PAD+88, offsetY=OY + 78,
    text="Set", width=60, height=26,
    handlers={
        OnClick=function()
            local v = tonumber(cdBox:GetText())
            if v and v > 0 then
                cfg.cooldown = v
                saveSettings()
                X2Chat:DispatchChatMessage(CMF_SYSTEM,
                    "helpwatch: cooldown set to " .. v .. "s.")
            end
        end,
    },
})
cdApply:SetStyle("text_default")
SetButtonFontOneColor(cdApply, C_ON)
reg(3, cdApply)

local cdHint = sw:CreateChildWidget("label", "hw_cd_hint", 0, false)
cdHint:SetText("Or: !hw set cooldown <seconds>")
cdHint:AddAnchor("TOPLEFT", sw, PAD, OY + 112)
cdHint.style:SetFontSize(11)
cdHint.style:SetColor(C_HDR[1], C_HDR[2], C_HDR[3], 0.75)
reg(3, cdHint)

-- ===== Save all + tab-state save button (bottom) =====
local saveBtn = CreateActionButton({
    parent=sw, name="hw_save", anchor="BOTTOM", anchorTarget=sw,
    offsetX=0, offsetY=-14,
    text="Save all settings", width=150, height=28,
    handlers={
        OnClick=function()
            if whEditBox then cfg[whKey(whSelIdx)] = whEditBox:GetText() end
            local v = tonumber(cdBox:GetText())
            if v and v > 0 then cfg.cooldown = v end
            saveSettings()
            rebuildWatch()
            X2Chat:DispatchChatMessage(CMF_SYSTEM, "helpwatch: all settings saved.")
            sw:Show(false)
        end,
    },
})
saveBtn:SetStyle("text_default")
SetButtonFontOneColor(saveBtn, C_ON)

-- populate live values when window opens
sw:SetHandler("OnShow", function()
    whEditBox:SetText(cfg[whKey(whSelIdx)] or "")
    cdBox:SetText(tostring(cfg.cooldown))
    updateWhTypeBtns()
    showTab(activeTab)
end)

-- initialize tab 1 visible
showTab(1)

-- ===== [HW] toggle button =====
local hwFrame = CreateEmptyWindow("helpwatchBtnFrame", "UIParent")
hwFrame:SetExtent(52, 24)
hwFrame:AddAnchor("TOPLEFT", "UIParent", 6, 190)
hwFrame:Show(true)
hwFrame:EnableDrag(true)
hwFrame:Clickable(true)
hwFrame:SetHandler("OnDragStart", function(self) self:StartMoving() end)
hwFrame:SetHandler("OnDragStop",  function(self) self:StopMovingOrSizing() end)
hwFrame:SetHandler("OnClick",     function() sw:Show(not sw:IsVisible()) end)

local hwBg = hwFrame:CreateColorDrawable(0.08, 0.08, 0.08, 0.90, "background")
hwBg:AddAnchor("TOPLEFT",     hwFrame, 0, 0)
hwBg:AddAnchor("BOTTOMRIGHT", hwFrame, 0, 0)

local hwLabel = hwFrame:CreateChildWidget("label", "hw_lbl", 0, false)
hwLabel:SetText("[HW]")
hwLabel:AddAnchor("CENTER", hwFrame, 0, 0)
hwLabel.style:SetFontSize(12)
hwLabel.style:SetColor(0.90, 0.75, 0.40, 1)
hwLabel.style:SetAlign(ALIGN_CENTER)

-- ===== !hw bang commands (Local chat, any sender) =====
local HW_HELP = {
    "!hw help                          - show this list",
    "!hw set webhook <type> <url>       - set webhook (types: default help defense pvp pvpraid)",
    "!hw set cooldown <seconds>         - set alert cooldown",
    "!hw toggle <key>                   - toggle a setting",
    "  keys: nation guild family local  help defense pvp pvpraid popup",
}

local TOGGLE_KEYS = {
    nation="watch_nation", guild="watch_guild", family="watch_family", local_="watch_local",
    whisper="watch_whisper",
    help="alert_help", defense="alert_defense", pvp="alert_pvp", pvpraid="alert_pvpraid",
    popup="show_in_game",
}

local WH_NAME_TO_KEY = {
    default="webhook_default", help="webhook_help", defense="webhook_defense",
    pvp="webhook_pvp", pvpraid="webhook_pvpraid",
}

local function handleBangCmd(msg)
    local cmd = msg:match("^!hw%s*(.*)")
    if not cmd then return end
    cmd = cmd:lower():match("^%s*(.-)%s*$")   -- trim

    if cmd == "" or cmd == "help" then
        for _, line in ipairs(HW_HELP) do
            X2Chat:DispatchChatMessage(CMF_SYSTEM, line)
        end
        return
    end

    -- !hw set webhook <type> <url>
    local whType, url = cmd:match("^set%s+webhook%s+(%S+)%s+(%S+)")
    if whType and url then
        local key = WH_NAME_TO_KEY[whType]
        if key then
            cfg[key] = url
            saveSettings()
            X2Chat:DispatchChatMessage(CMF_SYSTEM,
                "helpwatch: " .. whType .. " webhook set.")
        else
            X2Chat:DispatchChatMessage(CMF_SYSTEM,
                "helpwatch: unknown type '" .. whType .. "'. Use: default help defense pvp pvpraid")
        end
        return
    end

    -- !hw set cooldown <n>
    local cd = cmd:match("^set%s+cooldown%s+(%d+)")
    if cd then
        cfg.cooldown = tonumber(cd) or cfg.cooldown
        saveSettings()
        X2Chat:DispatchChatMessage(CMF_SYSTEM,
            "helpwatch: cooldown set to " .. cfg.cooldown .. "s.")
        return
    end

    -- !hw toggle <key>
    local tkey = cmd:match("^toggle%s+(%S+)")
    if tkey then
        -- "local" is a Lua keyword so stored as "local_" but accepted as "local"
        local cfgKey = TOGGLE_KEYS[tkey] or TOGGLE_KEYS[tkey .. "_"]
        if cfgKey then
            cfg[cfgKey] = not cfg[cfgKey]
            rebuildWatch()
            saveSettings()
            X2Chat:DispatchChatMessage(CMF_SYSTEM,
                "helpwatch: " .. tkey .. " -> " .. (cfg[cfgKey] and "ON" or "OFF"))
        else
            X2Chat:DispatchChatMessage(CMF_SYSTEM,
                "helpwatch: unknown key '" .. tkey .. "'. Type !hw help.")
        end
        return
    end

    X2Chat:DispatchChatMessage(CMF_SYSTEM, "helpwatch: unknown command. Type !hw help.")
end

-- ===== chat event plumbing =====
local function onChat(channel, relation, name, message, info)
    if not (info and info.isUserChat) then return end
    if not message or message == "" then return end

    -- bang command: accept from Local/Say or Whisper (whisper = only you know your own webhook)
    local isCmd = message:sub(1, 3):lower() == "!hw"
    if isCmd and (channel == CHAT_SAY or channel == CHAT_WHISPER) then
        handleBangCmd(message)
        return
    end

    local label = WATCH[channel]
    if not label then return end
    local tier = classify(message)
    if not tier then return end
    local key = tier .. "|" .. label .. "|" .. tostring(name) .. ":" .. message
    local now = os.time()
    if lastSent[key] and (now - lastSent[key]) < cfg.cooldown then return end
    lastSent[key] = now
    emit(tier, label, name, message)
end

local listener = CreateEmptyWindow("helpwatchListener", "UIParent")
listener:Show(false)
listener:SetHandler("OnEvent", function(this, event, ...)
    if event == "CHAT_MESSAGE" then onChat(...) end
end)
listener:RegisterEvent("CHAT_MESSAGE")

X2Chat:DispatchChatMessage(CMF_SYSTEM,
    "helpwatch loaded  |  [HW] to configure  |  !hw help in Local chat")
