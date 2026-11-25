local ADDON_NAME, ns = ...
local L = ns.L

local panel, category
local widgets = {}

local function MakeCheck(parent, name, label, key, onChange)
    local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 2, 1)
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        if onChange then onChange() end
    end)
    check.Load = function() check:SetChecked(ns.db[key]) end
    widgets[#widgets + 1] = check
    return check
end

local function MakeSlider(parent, name, label, key, minVal, maxVal, step, format, onChange)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetWidth(230)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    _G[name .. "Low"]:SetText(tostring(minVal))
    _G[name .. "High"]:SetText(tostring(maxVal))
    local title = _G[name .. "Text"]
    local function Label(value)
        title:SetText(label .. ":  |cffffd24d" .. format:format(value) .. "|r")
    end
    slider:SetScript("OnValueChanged", function(_, value)
        value = tonumber(format:format(value)) or value
        ns.db[key] = value
        Label(value)
        if onChange then onChange() end
    end)
    slider.Load = function() slider:SetValue(ns.db[key]); Label(ns.db[key]) end
    widgets[#widgets + 1] = slider
    return slider
end

local function MakeColor(parent, label, key)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(150, 22)
    button:SetText(label)
    local swatch = button:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(14, 14)
    swatch:SetPoint("LEFT", button, "RIGHT", 8, 0)
    button.Load = function()
        local c = ns.db[key]
        swatch:SetColorTexture(c[1], c[2], c[3], 1)
    end
    button:SetScript("OnClick", function()
        local c = ns.db[key]
        local function Apply()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ns.db[key] = { r, g, b }
            swatch:SetColorTexture(r, g, b, 1)
            ns.Layout(); ns.Update()
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3], swatchFunc = Apply,
            cancelFunc = function()
                ns.db[key] = { c[1], c[2], c[3] }
                swatch:SetColorTexture(c[1], c[2], c[3], 1); ns.Layout()
            end,
        })
    end)
    widgets[#widgets + 1] = button
    return button
end

local function MakeSealColor(parent, seal)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(118, 20)
    button:SetText(seal)
    local swatch = button:CreateTexture(nil, "OVERLAY")
    swatch:SetSize(13, 13)
    swatch:SetPoint("LEFT", button, "RIGHT", 6, 0)

    local function Current()
        local c = ns.db.sealColors and ns.db.sealColors[seal]
        if type(c) == "table" and c[1] then return c end
        return ns.SEAL_DEFAULT[seal]
    end
    button.Load = function()
        local c = Current()
        swatch:SetColorTexture(c[1], c[2], c[3], 1)
    end
    button:SetScript("OnClick", function()
        local old = Current()
        local function Apply()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            ns.db.sealColors = ns.db.sealColors or {}
            ns.db.sealColors[seal] = { r, g, b }
            swatch:SetColorTexture(r, g, b, 1)
            if ns.ForceRebuild then ns.ForceRebuild() end
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = old[1], g = old[2], b = old[3], swatchFunc = Apply,
            cancelFunc = function()
                ns.db.sealColors = ns.db.sealColors or {}
                ns.db.sealColors[seal] = { old[1], old[2], old[3] }
                swatch:SetColorTexture(old[1], old[2], old[3], 1)
                if ns.ForceRebuild then ns.ForceRebuild() end
            end,
        })
    end)
    widgets[#widgets + 1] = button
    return button
end

local function MakeHeader(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetText(text)
    fs:SetTextColor(0.96, 0.82, 0.36)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetColorTexture(0.96, 0.82, 0.36, 0.2)
    fs.line = line
    return fs
end

local function Relayout() ns.Layout(); ns.Update() end

local function MakeRadio(parent, name, label, mode, onChange)
    local c = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    local text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", c, "RIGHT", 2, 1)
    text:SetText(label)
    c:SetScript("OnClick", function()
        ns.db.showMode = mode
        if onChange then onChange() end
    end)
    c.Load = function() c:SetChecked(ns.db.showMode == mode) end
    widgets[#widgets + 1] = c
    return c
end

local function ModeChanged() if ns.Rebuild then ns.Rebuild() end; Relayout() end

function ns.BuildOptions()
    panel = CreateFrame("Frame")
    panel.name = "SealEcho"

    local iconTex = panel:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(38, 38)
    iconTex:SetPoint("TOPLEFT", 16, -16)
    iconTex:SetTexture("Interface\\Icons\\spell_holy_blessedresillience")
    local okm, m = pcall(panel.CreateMaskTexture, panel)
    if okm and m then
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        m:SetAllPoints(iconTex); pcall(iconTex.AddMaskTexture, iconTex, m)
    end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("BOTTOMLEFT", iconTex, "RIGHT", 10, 6)
    title:SetText("SealEcho")
    local ver = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ver:SetPoint("LEFT", title, "RIGHT", 6, -1)
    ver:SetText("v1.0  by SkyTezz")
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", iconTex, "RIGHT", 10, -6)
    sub:SetText(L["Unsealed Wrath echo-stack bar - readable even in combat."])

    local LX, RX, TOP = 22, 322, -74

    local hPos = MakeHeader(panel, L["POSITION"])
    hPos:SetPoint("TOPLEFT", LX, TOP)
    hPos.line:SetPoint("LEFT", hPos, "RIGHT", 8, 0)
    hPos.line:SetPoint("RIGHT", panel, "LEFT", RX - 26, TOP - 7)

    local lock = MakeCheck(panel, "SealEchoLockCheck", L["Lock position"], "locked", Relayout)
    lock:SetPoint("TOPLEFT", hPos, "BOTTOMLEFT", -2, -6)
    local lockHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    lockHint:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 4, 0)
    lockHint:SetText(L["Unlocked: drag the bar, or right-click the minimap icon."])

    local hVis = MakeHeader(panel, L["VISIBILITY"])
    hVis:SetPoint("TOPLEFT", lockHint, "BOTTOMLEFT", -4, -14)
    hVis.line:SetPoint("LEFT", hVis, "RIGHT", 8, 0)
    hVis.line:SetPoint("RIGHT", panel, "LEFT", RX - 26, 0)

    local rAlways = MakeRadio(panel, "SealEchoModeAlways", L["Always"], "always", ModeChanged)
    rAlways:SetPoint("TOPLEFT", hVis, "BOTTOMLEFT", -1, -6)
    local rCombat = MakeRadio(panel, "SealEchoModeCombat", L["In combat only"], "combat", ModeChanged)
    rCombat:SetPoint("TOPLEFT", rAlways, "BOTTOMLEFT", 0, -2)
    local rEcho = MakeRadio(panel, "SealEchoModeEcho", L["Only with an active echo"], "echo", ModeChanged)
    rEcho:SetPoint("TOPLEFT", rCombat, "BOTTOMLEFT", 0, -2)
    local rNever = MakeRadio(panel, "SealEchoModeNever", L["Never (hide completely)"], "never", ModeChanged)
    rNever:SetPoint("TOPLEFT", rEcho, "BOTTOMLEFT", 0, -2)

    local hShow = MakeHeader(panel, L["DISPLAY"])
    hShow:SetPoint("TOPLEFT", rNever, "BOTTOMLEFT", -1, -14)
    hShow.line:SetPoint("LEFT", hShow, "RIGHT", 8, 0)
    hShow.line:SetPoint("RIGHT", panel, "LEFT", RX - 26, 0)

    local showSeal = MakeCheck(panel, "SealEchoSealCheck", L["Seal icon"], "showSeal", Relayout)
    showSeal:SetPoint("TOPLEFT", hShow, "BOTTOMLEFT", -2, -6)
    local showText = MakeCheck(panel, "SealEchoTextCheck", L["Countdown seconds"], "showText", Relayout)
    showText:SetPoint("TOPLEFT", showSeal, "BOTTOMLEFT", 0, -2)
    local flash = MakeCheck(panel, "SealEchoFlashCheck", L["Pulse at full stacks"], "flash", Relayout)
    flash:SetPoint("TOPLEFT", showText, "BOTTOMLEFT", 0, -2)
    local mmap = MakeCheck(panel, "SealEchoMinimapCheck", L["Minimap icon"], "minimap", Relayout)
    mmap:SetPoint("TOPLEFT", flash, "BOTTOMLEFT", 0, -2)

    local hSize = MakeHeader(panel, L["SIZE"])
    hSize:SetPoint("TOPLEFT", RX, TOP)
    hSize.line:SetPoint("LEFT", hSize, "RIGHT", 8, 0)
    hSize.line:SetPoint("RIGHT", panel, "LEFT", RX + 236, TOP - 7)

    local width = MakeSlider(panel, "SealEchoWidthSlider", L["Width"], "width", 120, 500, 2, "%d", Relayout)
    width:SetPoint("TOPLEFT", hSize, "BOTTOMLEFT", 6, -22)
    local height = MakeSlider(panel, "SealEchoHeightSlider", L["Slot height"], "height", 6, 40, 1, "%d", Relayout)
    height:SetPoint("TOPLEFT", width, "BOTTOMLEFT", 0, -34)
    local gap = MakeSlider(panel, "SealEchoGapSlider", L["Gap"], "gap", 2, 28, 1, "%d", Relayout)
    gap:SetPoint("TOPLEFT", height, "BOTTOMLEFT", 0, -34)
    local scale = MakeSlider(panel, "SealEchoScaleSlider", L["Scale"], "scale", 0.5, 2.5, 0.05, "%.2f", Relayout)
    scale:SetPoint("TOPLEFT", gap, "BOTTOMLEFT", 0, -34)

    local hColor = MakeHeader(panel, L["COLOR"])
    hColor:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", -6, -24)
    hColor.line:SetPoint("LEFT", hColor, "RIGHT", 8, 0)
    hColor.line:SetPoint("RIGHT", panel, "LEFT", RX + 236, 0)

    local fill = MakeColor(panel, L["Stack color"], "fill")
    fill:SetPoint("TOPLEFT", hColor, "BOTTOMLEFT", 6, -10)
    local colorHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    colorHint:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, -6)
    colorHint:SetText(L["Slot fill. The pulse colour comes from the seal below."])

    local hSeal = MakeHeader(panel, L["SEAL COLOURS"])
    hSeal:SetPoint("TOPLEFT", colorHint, "BOTTOMLEFT", 0, -16)
    hSeal.line:SetPoint("LEFT", hSeal, "RIGHT", 8, 0)
    hSeal.line:SetPoint("RIGHT", panel, "LEFT", RX + 236, 0)

    local lastSealRow
    for idx, seal in ipairs(ns.SEAL_ORDER or {}) do
        local b = MakeSealColor(panel, seal)
        b:SetSize(96, 20)
        local col, row = (idx - 1) % 2, math.floor((idx - 1) / 2)
        b:SetPoint("TOPLEFT", hSeal, "BOTTOMLEFT", 6 + col * 120, -8 - row * 23)
        if col == 0 then lastSealRow = b end
    end

    local preview = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    preview:SetPoint("TOPLEFT", lastSealRow or colorHint, "BOTTOMLEFT", lastSealRow and -6 or 0, -18)
    preview:SetSize(130, 22)
    preview:SetText(L["Preview (5s)"])
    preview:SetScript("OnClick", function()
        ns.Preview(true); C_Timer.After(5, function() ns.Preview(false) end)
    end)
    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetPoint("LEFT", preview, "RIGHT", 8, 0)
    reset:SetSize(130, 22)
    reset:SetText(L["Reset to defaults"])
    reset:SetScript("OnClick", function()
        for key, value in pairs(ns.DEFAULTS) do
            ns.db[key] = (type(value) == "table") and CopyTable(value) or value
        end
        Relayout(); ns.Rebuild()
    end)

    panel:SetScript("OnShow", function() ns.Rebuild() end)
    category = Settings.RegisterCanvasLayoutCategory(panel, "SealEcho")
    Settings.RegisterAddOnCategory(category)
end

function ns.Rebuild()
    for _, widget in ipairs(widgets) do
        if widget.Load then widget.Load() end
    end
end

function ns.OpenOptions()
    if category and not InCombatLockdown() then
        Settings.OpenToCategory(category:GetID())
    end
end
