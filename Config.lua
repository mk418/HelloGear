local ADDON_NAME, ns = ...

ns.Config = {}
local Config = ns.Config

local accountDefaults = {
    minimap = { hide = false, angle = 195 },
    -- Paperdoll slot menus
    slotMenus = true,
    slotMenuModifier = "ALT",  -- ALT | CTRL | SHIFT | NONE
    slotMenuChevrons = true,
    -- Chat feedback
    announceSwaps = true,
    -- Claim the bare EquipSet/ToggleSet globals for macro compatibility
    legacyGlobals = true,
}

local charDefaults = {
    sets = {},
    order = {},
    bindings = {},
    currentSet = nil,
    itemRackBackup = nil,
}

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                applyDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            applyDefaults(target[k], v)
        end
    end
end

function Config:Init()
    HelloGearDB = HelloGearDB or {}
    HelloGearCharDB = HelloGearCharDB or {}
    applyDefaults(HelloGearDB, accountDefaults)
    applyDefaults(HelloGearCharDB, charDefaults)
end

function Config:Get(key)
    return HelloGearDB and HelloGearDB[key]
end

function Config:Set(key, value)
    HelloGearDB = HelloGearDB or {}
    HelloGearDB[key] = value
end

function Config:GetTable(key)
    HelloGearDB = HelloGearDB or {}
    HelloGearDB[key] = HelloGearDB[key] or {}
    return HelloGearDB[key]
end

function Config:GetCharTable(key)
    HelloGearCharDB = HelloGearCharDB or {}
    HelloGearCharDB[key] = HelloGearCharDB[key] or {}
    return HelloGearCharDB[key]
end

function Config:CreatePanel()
    local panel = CreateFrame("Frame")
    panel.name = "HelloGear"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("HelloGear")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Gear sets for Classic Era.")

    local anchor = subtitle
    local function CheckBox(label, key, tooltip, onChange)
        local cb = CreateFrame("CheckButton", "HelloGearCheck" .. key, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
        local text = _G[cb:GetName() .. "Text"] or cb.Text
        if text then text:SetText(label) end
        if tooltip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(label, 1, 1, 1)
                GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", GameTooltip_Hide)
        end
        cb:SetScript("OnShow", function(self) self:SetChecked(Config:Get(key) and true or false) end)
        cb:SetScript("OnClick", function(self)
            Config:Set(key, self:GetChecked() and true or false)
            if onChange then onChange(self:GetChecked()) end
        end)
        anchor = cb
        return cb
    end

    CheckBox("Show minimap button", "minimapShown", nil, nil)
    -- The minimap flag is stored inverted (hide), so it gets its own handler.
    anchor:SetScript("OnShow", function(self)
        self:SetChecked(not Config:GetTable("minimap").hide)
    end)
    anchor:SetScript("OnClick", function(self)
        Config:GetTable("minimap").hide = not self:GetChecked()
        ns.Minimap:ApplyVisibility()
    end)

    CheckBox("Paperdoll slot menus", "slotMenus",
        "Adds a menu to each character-sheet slot listing every alternative in your bags.",
        function() ns.SlotMenus:ApplyVisibility() end)

    CheckBox("Show slot menu arrows on hover", "slotMenuChevrons",
        "Uncheck to open slot menus only with the modifier click.",
        function() ns.SlotMenus:ApplyVisibility() end)

    CheckBox("Announce swaps in chat", "announceSwaps")

    CheckBox("Define EquipSet()/ToggleSet() globals", "legacyGlobals",
        "Lets ItemRack-era macros such as /script EquipSet(\"Tank\") keep working. Takes effect on reload.")

    local modifiers = { "ALT", "CTRL", "SHIFT", "NONE" }
    local modLabels = { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift", NONE = "off" }

    local modButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    modButton:SetSize(240, 22)
    modButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -20)
    local function UpdateModButton()
        modButton:SetText("Slot menu modifier click: " .. (modLabels[Config:Get("slotMenuModifier")] or "Alt"))
    end
    modButton:SetScript("OnClick", function()
        local current = Config:Get("slotMenuModifier")
        local index = 1
        for i, mod in ipairs(modifiers) do
            if mod == current then index = i % #modifiers + 1 break end
        end
        Config:Set("slotMenuModifier", modifiers[index])
        UpdateModButton()
        ns.SlotMenus:ApplyVisibility()
    end)
    modButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Which modifier opens a slot menu when you click a character-sheet slot.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    modButton:SetScript("OnLeave", GameTooltip_Hide)
    panel:HookScript("OnShow", UpdateModButton)
    UpdateModButton()

    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", modButton, "BOTTOMLEFT", -4, -24)
    help:SetJustifyH("LEFT")
    help:SetText(
        "Slash commands:\n" ..
        "  /hg - open the set menu\n" ..
        "  /hg manage - open the set manager\n" ..
        "  /hg equip <set> / toggle <set> / save <set>\n" ..
        "  /hg import - import sets from ItemRack\n" ..
        "  /hg bind <1-6> <set> - assign a set to a key binding\n" ..
        "  /hg reset - wipe all HelloGear data and reload\n\n" ..
        "Key bindings: Esc -> Key Bindings -> HelloGear"
    )

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        self.category = category
    end

    self.panel = panel
end

function Config:OpenPanel()
    if Settings and Settings.OpenToCategory and self.category then
        Settings.OpenToCategory(self.category:GetID())
    end
end
