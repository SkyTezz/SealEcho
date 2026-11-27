local ADDON_NAME, ns = ...
local L = ns.L

ns.MAX_STACKS = 3

local SEAL_COLOR = {
    ["Command"]       = { 0.88, 0.23, 0.16 },
    ["Righteousness"] = { 1.00, 0.88, 0.30 },
    ["Fury"]          = { 1.00, 0.48, 0.10 },
    ["Justice"]       = { 0.85, 0.89, 0.94 },
    ["Light"]         = { 0.44, 0.83, 0.64 },
    ["Wisdom"]        = { 0.29, 0.62, 1.00 },
}
ns.SEAL_DEFAULT = SEAL_COLOR
ns.SEAL_ORDER = { "Command", "Righteousness", "Fury", "Justice", "Light", "Wisdom" }

local function SealColor(seal)
    local c = ns.db and ns.db.sealColors and ns.db.sealColors[seal]
    if type(c) == "table" and c[1] then return c end
    return SEAL_COLOR[seal]
end
ns.SealColor = SealColor

ns.DEFAULTS = {
    width      = 250,
    height     = 11,
    gap        = 10,
    timerH     = 3,
    sealColors = {},
    scale      = 1.0,
    locked     = false,
    showMode   = "always",
    minimap    = true,
    minimapAngle = 210,
    showSeal   = true,
    showText   = true,
    flash      = true,
    point      = { "CENTER", "UIParent", "CENTER", 0, -170 },
    fill       = { 1.00, 0.82, 0.25 },
    ready      = { 0.45, 0.78, 1.00 },
    learned    = {},
}

local root, chrome, container, builtSig, lastError, pendingRebuild

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd24dSealEcho|r: " .. tostring(msg))
end

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) and true or false end
local function Readable(v) if v == nil or IsSecret(v) then return nil end return v end
local function Field(tbl, key)
    if tbl == nil then return nil end
    local ok, v = pcall(function() return tbl[key] end)
    if not ok then return nil end
    return v
end

local function Safe()
    if InCombatLockdown() then return false end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and secret then return false end
    end
    return true
end

local containerOK
local function ContainerAPI()
    if containerOK ~= nil then return containerOK end
    containerOK = false
    if not (CustomAuraContainerAuraProcessingPolicy and AuraContainerSortMethod and AuraContainerSortDirection) then
        return false
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        if C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
        if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then return false end
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    containerOK = (ok and c ~= nil and type(c.AddAuraSlot) == "function" and type(c.SetUnit) == "function") or false
    if ok and c then c:Hide() end
    return containerOK
end

local tenths
local function Tenths()
    if tenths ~= nil then return tenths or nil end
    tenths = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    local ok, f = pcall(function()
        local created = C_StringUtil.CreateNumericRuleFormatter()
        created:SetBreakpoints({ { threshold = 0, format = "%.1f" } })
        return created
    end)
    if ok and f then tenths = f end
    return tenths or nil
end

local timeCurve
local function TimeColorCurve()
    if timeCurve ~= nil then return timeCurve or nil end
    timeCurve = false
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor
            and Enum and Enum.LuaCurveType and Enum.DurationTextBindingProperty) then return nil end
    local ok, c = pcall(function()
        local curve = C_CurveUtil.CreateColorCurve()
        curve:SetType(Enum.LuaCurveType.Linear)
        curve:AddPoint(0.0, CreateColor(1.00, 0.22, 0.15, 1))
        curve:AddPoint(3.0, CreateColor(1.00, 0.48, 0.10, 1))
        curve:AddPoint(8.0, CreateColor(1.00, 0.86, 0.36, 1))
        return curve
    end)
    if ok and c then timeCurve = c end
    return timeCurve or nil
end

local SEAL_ALIAS = {
    ["Command"] = "Command", ["Righteousness"] = "Righteousness", ["Fury"] = "Fury",
    ["Justice"] = "Justice", ["Light"] = "Light", ["Wisdom"] = "Wisdom",
    ["Befehls"] = "Command", ["Rechtschaffenheit"] = "Righteousness", ["Zorns"] = "Fury",
    ["Gerechtigkeit"] = "Justice", ["Lichts"] = "Light", ["Weisheit"] = "Wisdom",
    ["autorité"] = "Command", ["piété"] = "Righteousness", ["fureur"] = "Fury",
    ["justice"] = "Justice", ["lumière"] = "Light", ["sagesse"] = "Wisdom",
    ["orden"] = "Command", ["rectitud"] = "Righteousness", ["furia"] = "Fury",
    ["justicia"] = "Justice", ["luz"] = "Light", ["sabiduría"] = "Wisdom",
}

local function MatchSealName(auraName)
    local raw = auraName:match("^Echo of (.+)$")
        or auraName:match("^Echo de[sr] (.+)$")
        or auraName:match("^Écho d[e'] ?(.+)$")
        or auraName:match("^Eco de (.+)$")
    if not raw then return nil end
    if SEAL_COLOR[raw] then return raw end
    return SEAL_ALIAS[raw] or SEAL_ALIAS[raw:lower()]
end

local function LearnFromAuras()
    if not Safe() then return false end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
    local changed = false
    for i = 1, 60 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or type(aura) ~= "table" then break end
        local name    = Readable(Field(aura, "name"))
        local spellID = Readable(Field(aura, "spellId"))
        if name and spellID then
            local seal = MatchSealName(name)
            if seal and SEAL_COLOR[seal] and ns.db.learned[spellID] ~= seal then
                ns.db.learned[spellID] = seal
                changed = true
                ns.Print((L["learned Echo of %s (spell %d)"]):format(seal, spellID))
            end
        end
    end
    return changed
end

local function LearnedSig()
    local ids = {}
    for id in pairs(ns.db.learned) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
        .. "|" .. tostring(ns.db.flash)
        .. "|" .. tostring(ns.db.showSeal)
        .. "|" .. tostring(ns.db.showText)
        .. "|" .. tostring(ns.db.height)
        .. "|" .. tostring(ns.db.timerH)
end

local function LearnedIDSet()
    local set = {}
    for id in pairs(ns.db.learned) do set[id] = true end
    return set
end

local function IDsBySeal()
    local bySeal = {}
    for id, seal in pairs(ns.db.learned) do
        if type(seal) == "string" and SEAL_COLOR[seal] then
            bySeal[seal] = bySeal[seal] or {}
            bySeal[seal][id] = true
        end
    end
    return bySeal
end

local TEXCELL = "Interface\\AddOns\\SealEcho\\Textures\\cell"
local TEXOUT  = "Interface\\AddOns\\SealEcho\\Textures\\cellout"
local TEXGLOW = "Interface\\AddOns\\SealEcho\\Textures\\glow"
local TEXPILL = "Interface\\AddOns\\SealEcho\\Textures\\pill"
local TEXICON = "Interface\\AddOns\\SealEcho\\Textures\\iconmask"

local function MakeCell(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell.outline = cell:CreateTexture(nil, "BORDER")
    cell.outline:SetTexture(TEXOUT)
    cell.outline:SetAllPoints(cell)
    cell.outline:SetVertexColor(0.86, 0.80, 0.62, 0.38)
    cell.preview = cell:CreateTexture(nil, "OVERLAY")
    cell.preview:SetTexture(TEXCELL)
    cell.preview:SetAllPoints(cell)
    cell.preview:Hide()
    return cell
end

local function BuildRoot()
    root = CreateFrame("Frame", "SealEchoBar", UIParent)
    root:SetMovable(true)
    root:SetClampedToScreen(true)
    root:EnableMouse(true)
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving() end end)
    root:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.db.point = { p, "UIParent", rp, x, y }
    end)

    chrome = { cells = {} }
    chrome.icon = CreateFrame("Frame", nil, root)
    for i = 1, ns.MAX_STACKS do chrome.cells[i] = MakeCell(root) end

    root:Hide()
end

local function CellGeometry(db)
    local iconSize = db.showSeal and (db.height + 4 + (db.timerH or 3)) or 0
    local iconGap  = db.showSeal and 6 or 0
    local span     = db.width - iconSize - iconGap
    local gap      = db.gap
    local cellW    = (span - gap * (ns.MAX_STACKS - 1)) / ns.MAX_STACKS
    return iconSize, iconGap, span, gap, cellW
end

function ns.Layout()
    if not root then return end
    local db = ns.db
    local iconSize, iconGap, span, gap, cellW = CellGeometry(db)

    local th = db.timerH or 3
    root:SetScale(db.scale)
    root:SetSize(db.width, db.height + 4 + th + 2)
    root:EnableMouse(not db.locked)
    root:ClearAllPoints()
    root:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])

    chrome.icon:SetShown(db.showSeal)
    chrome.icon:ClearAllPoints()
    chrome.icon:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    chrome.icon:SetSize(math.max(iconSize, 1), math.max(iconSize, 1))

    local previewColor = SealColor("Fury") or db.fill
    for i, cell in ipairs(chrome.cells) do
        local x = iconSize + iconGap + (i - 1) * (cellW + gap)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", root, "TOPLEFT", x, 0)
        cell:SetSize(cellW, db.height)
        cell.preview:SetVertexColor(previewColor[1], previewColor[2], previewColor[3], 1)
    end

    ns.geo = { iconSize = iconSize, cellW = cellW, height = db.height }
    if ns.UpdateMinimap then ns.UpdateMinimap() end
end

local function StyleSealCell(button, i, seal)
    local c = SealColor(seal)
    local ox = math.max(12, (ns.db.height or 11) * 1.25)

    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", chrome.cells[i], "TOPLEFT", -ox, ox)
    button:SetPoint("BOTTOMRIGHT", chrome.cells[i], "BOTTOMRIGHT", ox, -ox)
    pcall(button.SetClipsChildren, button, false)

    local gate = CreateFrame("StatusBar", nil, button)
    gate:SetAllPoints(button)
    gate:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    gate:SetStatusBarColor(0, 0, 0, 0)
    gate:SetMinMaxValues(0, ns.MAX_STACKS)
    pcall(gate.SetClipsChildren, gate, false)

    local glow = gate:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(TEXGLOW)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(c[1], c[2], c[3])
    glow:SetAllPoints(button)
    if ns.db.flash then
        local pulse = glow:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local a = pulse:CreateAnimation("Alpha")
        a:SetFromAlpha(0.30); a:SetToAlpha(0.85); a:SetDuration(1.20)
        a:SetStartDelay((i - 1) * 0.20)
        pulse:Play()
    else
        glow:SetAlpha(0.35)
    end

    local fill = gate:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(TEXCELL)
    fill:SetAllPoints(chrome.cells[i])
    local function cl(v) return math.max(0, math.min(1, v)) end
    if CreateColor and fill.SetGradient then
        local lo = CreateColor(cl(c[1] * 0.60), cl(c[2] * 0.42), cl(c[3] * 0.40), 1)
        local hi = CreateColor(cl(c[1] + 0.22), cl(c[2] + 0.34), cl(c[3] + 0.20), 1)
        if not pcall(fill.SetGradient, fill, "VERTICAL", lo, hi) then
            fill:SetVertexColor(c[1], c[2], c[3], 1)
        end
    else
        fill:SetVertexColor(c[1], c[2], c[3], 1)
    end

    local outline = gate:CreateTexture(nil, "OVERLAY")
    outline:SetTexture(TEXOUT)
    outline:SetAllPoints(chrome.cells[i])
    outline:SetVertexColor(1.00, 0.97, 0.92, 0.9)

    pcall(button.SetApplicationBar, button, gate, { minApplications = i, maxApplications = ns.MAX_STACKS })
end

local function StyleMain(button)
    local db = ns.db
    local geo = ns.geo or { iconSize = 18, cellW = 70, height = db.height }
    button:EnableMouse(false)
    button:ClearAllPoints()
    button:SetAllPoints(root)

    local iconEdge = button:CreateTexture(nil, "BACKGROUND")
    iconEdge:SetTexture(TEXICON)
    iconEdge:SetVertexColor(1.00, 0.86, 0.45, 0.85)
    iconEdge:SetPoint("TOPLEFT", chrome.icon, "TOPLEFT", -2, 2)
    iconEdge:SetPoint("BOTTOMRIGHT", chrome.icon, "BOTTOMRIGHT", 2, -2)
    iconEdge:SetShown(db.showSeal)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetAllPoints(chrome.icon)
    icon:SetShown(db.showSeal)
    local okMask, mask = pcall(button.CreateMaskTexture, button)
    if okMask and mask then
        mask:SetTexture(TEXICON, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        pcall(icon.AddMaskTexture, icon, mask)
    end

    local th = db.timerH or 3

    local tEdge = button:CreateTexture(nil, "BACKGROUND")
    tEdge:SetTexture(TEXPILL)
    tEdge:SetVertexColor(0.60, 0.60, 0.65, 0.85)
    tEdge:SetPoint("TOPLEFT", chrome.cells[1], "BOTTOMLEFT", 0, -4)
    tEdge:SetPoint("TOPRIGHT", chrome.cells[ns.MAX_STACKS], "BOTTOMRIGHT", 0, -4)
    tEdge:SetHeight(th + 2)

    local tInner = button:CreateTexture(nil, "BORDER")
    tInner:SetTexture(TEXPILL)
    tInner:SetVertexColor(0, 0, 0, 0.92)
    tInner:SetPoint("TOPLEFT", tEdge, "TOPLEFT", 1, -1)
    tInner:SetPoint("BOTTOMRIGHT", tEdge, "BOTTOMRIGHT", -1, 1)

    local tb = CreateFrame("StatusBar", nil, button)
    tb:SetAllPoints(tInner)
    tb:SetStatusBarTexture(TEXPILL)
    tb:SetStatusBarColor(1, 1, 1, 1)
    tb:SetFrameLevel(button:GetFrameLevel() + 2)
    local ttex = tb:GetStatusBarTexture()
    if ttex and CreateColor and ttex.SetGradient then
        pcall(ttex.SetGradient, ttex, "HORIZONTAL",
            CreateColor(0.95, 0.16, 0.10, 1),
            CreateColor(1.00, 0.58, 0.10, 1))
    else
        tb:SetStatusBarColor(1.00, 0.45, 0.12, 1)
    end

    local secs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    secs:SetPoint("LEFT", chrome.cells[ns.MAX_STACKS], "RIGHT", 7, 0)
    secs:SetShown(db.showText)

    pcall(button.SetIcon, button, icon)
    local dir = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
    pcall(button.SetDurationBar, button, tb, { direction = dir })
    if db.showText then
        local fmt, curve = Tenths(), TimeColorCurve()
        local opts = { textFormatter = fmt }
        if curve and Enum.DurationTextBindingProperty then
            opts.textColor = { curve = curve, property = Enum.DurationTextBindingProperty.RemainingDuration }
        end
        if not (fmt and pcall(button.SetDurationText, button, secs, opts)) then
            opts.textColor = nil
            if not (fmt and pcall(button.SetDurationText, button, secs, { textFormatter = fmt })) then
                pcall(button.SetDurationText, button, secs, {})
            end
        end
    end
    button._se = { icon = icon, tb = tb, secs = secs }
    ns.mainButton = button
end

local function TearDown()
    if container then
        pcall(container.SetEnabled, container, false)
        container:Hide(); container:SetParent(nil); container = nil
    end
    ns.mainButton = nil
    builtSig = nil
end

local function BuildContainer()
    if not Safe() then return false end
    if not ContainerAPI() then return false end
    local ids = LearnedIDSet()
    if not next(ids) then TearDown(); return false end
    local sig = LearnedSig()
    if container and builtSig == sig then return true end
    TearDown()

    local ok, err = pcall(function()
        container = CreateFrame("AuraContainer", nil, root, "CustomAuraContainerTemplate")
        container:SetEnabled(false)
        container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
        container:SetPoint("TOPLEFT", root, "TOPLEFT")
        container:SetUnit("player")
        pcall(container.EnableMouse, container, false)
        pcall(container.SetMouseClickEnabled, container, false)
        pcall(container.SetMouseMotionEnabled, container, false)
        pcall(container.SetClipsChildren, container, false)

        container:AddAuraSlot("Main", "HELPFUL", {
            candidateFilters = { includeSpellIDs = ids },
            sortMethod = AuraContainerSortMethod.Default,
            sortDirection = AuraContainerSortDirection.Normal,
            initializeFrame = function(button) StyleMain(button) end,
        })
        for seal, sealIDs in pairs(IDsBySeal()) do
            for i = 1, ns.MAX_STACKS do
                container:AddAuraSlot("Cell_" .. seal .. "_" .. i, "HELPFUL", {
                    candidateFilters = { includeSpellIDs = sealIDs },
                    initializeFrame = function(button) StyleSealCell(button, i, seal) end,
                })
            end
        end

        if container.SetAuraSlotEnabled then
            container:SetAuraSlotEnabled("Main", true)
            for seal in pairs(IDsBySeal()) do
                for i = 1, ns.MAX_STACKS do
                    container:SetAuraSlotEnabled("Cell_" .. seal .. "_" .. i, true)
                end
            end
        end
    end)

    if not ok then
        lastError = tostring(err)
        TearDown()
        ns.Print("|cffff4040could not build aura container|r: " .. tostring(err))
        return false
    end
    container:SetEnabled(true)
    builtSig = sig
    return true
end

local function UpdateVisibility(forceCombat)
    local db = ns.db
    local mode = db.showMode or "always"
    local inCombat
    if forceCombat ~= nil then
        inCombat = forceCombat
    else
        inCombat = InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    end
    if mode == "never" then
        root:Hide()
        return
    end
    if mode == "combat" and not inCombat then
        root:Hide()
        return
    end
    local showChrome = (mode == "always") or (mode == "combat" and inCombat)
    root:SetShown(showChrome or container ~= nil)
    for _, cell in ipairs(chrome.cells) do cell:SetShown(showChrome) end
    root:SetAlpha(showChrome and 0.85 or 1)
end

function ns.Update(forceCombat)
    if not root then return end
    if Safe() then
        if LearnFromAuras() then builtSig = nil end
        if pendingRebuild then
            pendingRebuild = nil
            TearDown()
        end
        BuildContainer()
    end
    UpdateVisibility(forceCombat)
end

function ns.ForceRebuild()
    if not Safe() then
        pendingRebuild = true
        return false
    end
    pendingRebuild = nil
    TearDown()
    ns.Update()
    return true
end

function ns.Preview(show)
    if not root then return end
    for i, cell in ipairs(chrome.cells) do
        if show then cell:Show() end
        cell.preview:SetShown(show and i <= 2)
    end
    if show then root:Show(); root:SetAlpha(1) else ns.Update() end
end

local minimap
local function UpdateMinimapPos()
    if not minimap then return end
    local a = math.rad(ns.db.minimapAngle or 210)
    local r = (Minimap:GetWidth() or 140) / 2 + 4
    minimap:ClearAllPoints()
    minimap:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function ns.UpdateMinimap()
    if not minimap then return end
    minimap:SetShown(ns.db.minimap ~= false)
    UpdateMinimapPos()
end

local function BuildMinimap()
    if minimap then return end
    minimap = CreateFrame("Button", "SealEchoMinimapButton", Minimap)
    minimap:SetSize(31, 31)
    minimap:SetFrameStrata("MEDIUM")
    minimap:SetFrameLevel(8)
    minimap:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimap:RegisterForDrag("LeftButton")

    local icon = minimap:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\spell_holy_blessedresillience")
    local okm, m = pcall(minimap.CreateMaskTexture, minimap)
    if okm and m then
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        m:SetAllPoints(icon)
        pcall(icon.AddMaskTexture, icon, m)
    end
    local border = minimap:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    minimap:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local s = Minimap:GetEffectiveScale()
            local px, py = GetCursorPosition()
            if mx and px then
                ns.db.minimapAngle = math.deg(math.atan2(py / s - my, px / s - mx))
                UpdateMinimapPos()
            end
        end)
    end)
    minimap:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    minimap:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            ns.db.locked = not ns.db.locked
            ns.Layout()
            ns.Print(ns.db.locked and L["position locked"] or L["position unlocked - drag to move"])
        elseif ns.OpenOptions then
            ns.OpenOptions()
        end
    end)
    minimap:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("SealEcho")
        GameTooltip:AddLine(L["Left-click: options"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Right-click: lock / unlock bar"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Drag: move around the minimap"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    minimap:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.UpdateMinimap()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterUnitEvent("UNIT_AURA", "player")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        SealEchoDB = SealEchoDB or {}
        ns.db = SealEchoDB
        local fresh = (next(ns.db) == nil)
        local prevUi = ns.db.uiVersion
        if ns.db.showMode == nil then
            if ns.db.alwaysShow == false then ns.db.showMode = "echo"
            elseif ns.db.hideOOC == true then ns.db.showMode = "combat"
            else ns.db.showMode = "always" end
        end
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = (type(v) == "table") and CopyTable(v) or v end
        end
        for id, val in pairs(ns.db.learned) do
            if type(val) ~= "string" then ns.db.learned[id] = nil end
        end
        if not fresh and (prevUi or 0) < 2 then
            ns.db.height = math.max(6, math.floor(ns.db.height * 0.7 + 0.5))
        end
        if not fresh and (prevUi or 0) < 3 then
            ns.db.timerH = math.max(2, math.floor((ns.db.timerH or 6) * 0.5 + 0.5))
        end
        ns.db.uiVersion = 3
        BuildRoot()
        BuildMinimap()
        ns.Layout()
        if ns.BuildOptions then ns.BuildOptions() end
        ns.Update()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        ns.Update(false)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.Update()
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateVisibility(true)
    elseif event == "UNIT_AURA" then
        if Safe() then ns.Update() end
    end
end)

SLASH_SEALECHO1 = "/sealecho"
SLASH_SEALECHO2 = "/se"
SlashCmdList.SEALECHO = function(input)
    local cmd = (input or ""):lower():match("^%s*(%S*)")
    if cmd == "lock" then
        ns.db.locked = true; ns.Layout(); ns.Print(L["position locked"])
    elseif cmd == "unlock" then
        ns.db.locked = false; ns.Layout(); ns.Print(L["position unlocked - drag to move"])
    elseif cmd == "learn" then
        if not Safe() then ns.Print(L["out of combat please (names are secret in combat)"]); return end
        if LearnFromAuras() then builtSig = nil; ns.Update() end
        local n = 0; for _ in pairs(ns.db.learned) do n = n + 1 end
        ns.Print((L["known echo IDs: %d; use a seal, hit a mob, then after combat run /se learn"]):format(n))
    elseif cmd == "status" then
        local n = 0
        for id, seal in pairs(ns.db.learned) do n = n + 1; ns.Print(("  %d = Echo of %s"):format(id, tostring(seal))) end
        ns.Print((L["learned echoes: %d"]):format(n))
        ns.Print("Blizzard_AuraContainer API: " .. (ContainerAPI() and "|cff40ff40YES|r" or "|cffff4040NO|r"))
        ns.Print("container built: " .. (container and "|cff40ff40YES|r" or "no"))
        ns.Print("enums (ProcessingPolicy): " .. (CustomAuraContainerAuraProcessingPolicy and "OK" or "|cffff4040missing|r"))
        local inSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret and select(2, pcall(C_Secrets.ShouldAurasBeSecret))
        ns.Print("in combat: " .. (InCombatLockdown() and "yes" or "no") .. " | secret mode: " .. (inSecret and "yes" or "no"))
        ns.Print("last error: " .. tostring(lastError))
    elseif cmd == "rebuild" then
        if not Safe() then ns.Print(L["out of combat please"]); return end
        TearDown(); ns.Update(); ns.Print(L["container rebuilt"])
    else
        if ns.OpenOptions then ns.OpenOptions() end
    end
end
