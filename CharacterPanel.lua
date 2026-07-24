local ADDON_NAME, ns = ...

ns.Panel = {}
local Panel = ns.Panel
local Items = ns.Items
local Sets = ns.Sets

local PANEL_WIDTH = 200
local PANEL_HEIGHT = 400
local ROW_HEIGHT = 36
local BUTTON_SIZE = 26

-- Distance from the right slot column's right edge out to where the panel
-- should start. That's the frame's own margin (~22px on the stock paperdoll)
-- less the few pixels of transparent padding baked into the panel's backdrop
-- border, so the drawn edges meet instead of leaving a seam. /hg dock nudges
-- it if it lands wrong.
local SLOT_TO_EDGE = 16

local panel, toggle, scroll, content, statusText, editButton, equipButton, saveButton
local rows = {}
local options          -- the per-set options popout
local selected

--------------------------------------------------------------------------
-- Popups
--------------------------------------------------------------------------

StaticPopupDialogs["HELLOGEAR_NEW_SET"] = {
    text = "Name for the new set:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 40,
    OnAccept = function(self)
        local box = self.editBox or self.EditBox
        local name = box and box:GetText()
        name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
        if not name or name == "" then return end
        if Sets:Get(name) then
            ns:Print('a set named "%s" already exists', name)
            return
        end
        Sets:SaveFromWorn(name)
        ns:Print('saved worn gear as "%s"', name)
        Panel:Select(name)
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["HELLOGEAR_NEW_SET"].OnAccept(parent)
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["HELLOGEAR_DELETE_SET"] = {
    text = 'Delete the set "%s"?',
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        if Sets:Delete(data) then
            ns:Print('deleted "%s"', data)
            Panel:Select(nil)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--------------------------------------------------------------------------
-- Per-set options popout
--
-- Rename, the cosmetic toggles and the menu-visibility flag are all things
-- you touch once when you make a set and then never again, so they live
-- behind the gear button rather than taking permanent space in a 200px
-- column.
--------------------------------------------------------------------------

local function CycleTriState(value)
    if value == nil then return true end
    if value == true then return false end
    return nil
end

local function TriStateText(label, value)
    if value == nil then return label .. ": |cff808080leave alone|r" end
    if value then return label .. ": |cff80ff80show|r" end
    return label .. ": |cffff8080hide|r"
end

local function BuildOptions()
    options = ns.CreatePanel("HelloGearSetOptions")
    options:SetSize(230, 156)
    options:SetClampedToScreen(true)

    options.title = options:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    options.title:SetPoint("TOPLEFT", 14, -12)
    options.title:SetText("Set options")

    options.nameBox = CreateFrame("EditBox", "HelloGearSetOptionsName", options, "InputBoxTemplate")
    options.nameBox:SetSize(190, 20)
    options.nameBox:SetPoint("TOPLEFT", 20, -32)
    options.nameBox:SetAutoFocus(false)
    options.nameBox:SetMaxLetters(40)
    options.nameBox:SetScript("OnEnterPressed", function(self)
        local newName = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        if options.setName and newName ~= "" and newName ~= options.setName then
            if Sets:Rename(options.setName, newName) then
                options.setName = newName
                Panel:Select(newName)
            else
                ns:Print('could not rename to "%s"', newName)
                self:SetText(options.setName)
            end
        end
        self:ClearFocus()
    end)
    options.nameBox:SetScript("OnEscapePressed", function(self)
        self:SetText(options.setName or "")
        self:ClearFocus()
    end)

    local hint = options:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", options.nameBox, "BOTTOMLEFT", 0, -2)
    hint:SetText("Enter to rename")

    options.helm = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    options.helm:SetSize(190, 22)
    options.helm:SetPoint("TOPLEFT", options.nameBox, "BOTTOMLEFT", -2, -18)
    options.helm:SetScript("OnClick", function()
        local set = options.setName and Sets:Get(options.setName)
        if not set then return end
        set.helm = CycleTriState(set.helm)
        Panel:RefreshOptions()
    end)

    options.cloak = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    options.cloak:SetSize(190, 22)
    options.cloak:SetPoint("TOPLEFT", options.helm, "BOTTOMLEFT", 0, -4)
    options.cloak:SetScript("OnClick", function()
        local set = options.setName and Sets:Get(options.setName)
        if not set then return end
        set.cloak = CycleTriState(set.cloak)
        Panel:RefreshOptions()
    end)

    options.hidden = CreateFrame("CheckButton", "HelloGearSetOptionsHidden", options, "UICheckButtonTemplate")
    options.hidden:SetPoint("TOPLEFT", options.cloak, "BOTTOMLEFT", -2, -4)
    local hiddenText = _G["HelloGearSetOptionsHiddenText"]
    if hiddenText then hiddenText:SetText("Keep out of the quick menu") end
    options.hidden:SetScript("OnClick", function(self)
        local set = options.setName and Sets:Get(options.setName)
        if not set then return end
        set.hidden = self:GetChecked() or nil
        ns.Menu:Refresh()
        Panel:Refresh()
    end)

    options.resetIcon = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    options.resetIcon:SetSize(190, 22)
    options.resetIcon:SetPoint("TOPLEFT", options.hidden, "BOTTOMLEFT", 2, -4)
    options.resetIcon:SetText("Reset icon to a set item")
    options.resetIcon:SetScript("OnClick", function()
        local set = options.setName and Sets:Get(options.setName)
        if not set then return end
        set.icon = Sets:SuggestIcon(set)
        Panel:Refresh()
    end)

    options:SetScript("OnShow", function()
        if not options.closer then
            options.closer = CreateFrame("Frame", nil, UIParent)
            options.closer:SetAllPoints()
            options.closer:SetFrameStrata("DIALOG")
            options.closer:SetFrameLevel(1)
            options.closer:EnableMouse(true)
            options.closer:SetScript("OnMouseDown", function() options:Hide() end)
        end
        options.closer:Show()
    end)
    options:SetScript("OnHide", function()
        if options.closer then options.closer:Hide() end
    end)
end

function Panel:RefreshOptions()
    if not options or not options:IsShown() then return end
    local set = options.setName and Sets:Get(options.setName)
    if not set then options:Hide() return end
    options.nameBox:SetText(options.setName)
    options.helm:SetText(TriStateText("Helm", set.helm))
    options.cloak:SetText(TriStateText("Cloak", set.cloak))
    options.hidden:SetChecked(set.hidden or false)
end

local function ShowOptions(anchor, setName)
    if not options then BuildOptions() end
    options.setName = setName
    options:ClearAllPoints()
    options:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 8)
    options:Show()
    Panel:RefreshOptions()
end

--------------------------------------------------------------------------
-- Set rows
--------------------------------------------------------------------------

local function RowTooltip(self)
    local set = Sets:Get(self.setName)
    if not set then return end

    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(self.setName, 1, 1, 1)
    if Sets:IsEquipped(self.setName) then
        GameTooltip:AddLine("Equipped", 0.5, 1, 0.5)
    end
    GameTooltip:AddLine(" ")

    for _, def in ipairs(ns.SLOTS) do
        local gearID = set.equip[def.id]
        if gearID then
            local right
            if gearID == ns.EMPTY then
                right = "|cff808080(empty)|r"
            else
                local itemName, _, _, quality = Items.GetInfo(gearID)
                local color = quality and ITEM_QUALITY_COLORS[quality]
                right = (color and color.hex or "|cffffffff") .. (itemName or "...") .. "|r"
            end
            GameTooltip:AddDoubleLine("|cffb0b0b0" .. def.label .. "|r", right)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to select, double-click to equip", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, content)
    row:SetSize(PANEL_WIDTH - 40, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.04)

    row.selectedBar = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.selectedBar:SetAllPoints()
    row.selectedBar:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")
    row.selectedBar:SetBlendMode("ADD")
    row.selectedBar:SetAlpha(0.5)
    row.selectedBar:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", 3, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", -40, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.1)

    -- Kept permanently visible at low alpha rather than shown on hover: a
    -- hover-only button that vanishes the moment you move toward it is a
    -- coin-flip to click.
    row.optionsButton = CreateFrame("Button", nil, row)
    row.optionsButton:SetSize(16, 16)
    row.optionsButton:SetPoint("RIGHT", -20, 0)
    row.optionsButton:SetNormalTexture("Interface\\WorldMap\\Gear_64Grey")
    row.optionsButton:GetNormalTexture():SetAlpha(0.5)
    row.optionsButton:SetScript("OnEnter", function(self)
        self:GetNormalTexture():SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Rename, icon, helm and cloak", 1, 1, 1)
        GameTooltip:Show()
    end)
    row.optionsButton:SetScript("OnLeave", function(self)
        self:GetNormalTexture():SetAlpha(0.5)
        GameTooltip_Hide()
    end)
    row.optionsButton:SetScript("OnClick", function(self)
        Panel:Select(self:GetParent().setName)
        ShowOptions(self:GetParent(), self:GetParent().setName)
    end)

    row.deleteButton = CreateFrame("Button", nil, row)
    row.deleteButton:SetSize(14, 14)
    row.deleteButton:SetPoint("RIGHT", -4, 0)
    row.deleteButton:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    row.deleteButton:GetNormalTexture():SetAlpha(0.5)
    row.deleteButton:SetScript("OnEnter", function(self)
        self:GetNormalTexture():SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(DELETE or "Delete", 1, 1, 1)
        GameTooltip:Show()
    end)
    row.deleteButton:SetScript("OnLeave", function(self)
        self:GetNormalTexture():SetAlpha(0.5)
        GameTooltip_Hide()
    end)
    row.deleteButton:SetScript("OnClick", function(self)
        local name = self:GetParent().setName
        local dialog = StaticPopup_Show("HELLOGEAR_DELETE_SET", name)
        if dialog then dialog.data = name end
    end)

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ns.Equip:ToggleSet(self.setName)
        else
            Panel:Select(self.setName)
        end
    end)
    row:SetScript("OnDoubleClick", function(self)
        ns.Equip:EquipSet(self.setName)
    end)

    rows[index] = row
    return row
end

--------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Fitting to the character frame
--
-- CharacterFrame is a vanilla UIPanelFrame: 384x512, with the artwork only
-- filling the top-left 338x424 of it. So its right edge is some 46px outside
-- the frame you can actually see, and anything anchored there floats in space.
--
-- Rather than hardcode that number, both the button and the panel are placed
-- from the paperdoll's own slot columns. The columns are laid out symmetrically
-- inside the artwork, so the left column's margin is also the right column's -
-- which gives the visible edge, and a button sharing the right column's edge
-- inherits the frame's real margin for free.
--------------------------------------------------------------------------

local function ColumnEdgeSlots()
    local centerX = CharacterFrame:GetCenter()
    if not centerX then return nil end

    local left, right
    for _, def in ipairs(ns.SLOTS) do
        local button = _G["Character" .. def.key]
        local buttonLeft = button and button:GetLeft()
        if buttonLeft and button:GetTop() then
            if buttonLeft > centerX then
                if not right or button:GetTop() > right:GetTop() then right = button end
            else
                if not left or button:GetTop() > left:GetTop() then left = button end
            end
        end
    end
    return left, right
end

-- The stock 384-vs-338 difference, used when the measurement doesn't make
-- sense. Only a fallback: the whole point is not to rely on it.
local DEFAULT_ART_INSET = -46

-- Pure geometry, separated out so it can be tested without a character frame
-- to measure. Returns the offset from the frame's right edge to the artwork's
-- right edge, which is always negative.
function Panel.ComputeArtInset(frameLeft, frameRight, leftSlotLeft, rightSlotRight)
    local margin = leftSlotLeft - frameLeft
    local inset = (rightSlotRight + margin) - frameRight
    -- If the paperdoll has been rearranged into something this doesn't
    -- understand, fall back rather than flinging the panel somewhere absurd.
    if margin < 0 or inset > 0 or inset < -120 then return DEFAULT_ART_INSET end
    return inset
end

-- nil if the frame hasn't been laid out yet.
local function ArtInset()
    local left, right = ColumnEdgeSlots()
    if not left or not right then return nil end
    return Panel.ComputeArtInset(
        CharacterFrame:GetLeft(), CharacterFrame:GetRight(),
        left:GetLeft(), right:GetRight())
end

local function FitToFrame()
    local _, rightSlot = ColumnEdgeSlots()
    if rightSlot then
        -- Directly above the top slot of the right-hand column, sharing its
        -- right edge, so the margin matches the rest of the frame.
        toggle:ClearAllPoints()
        toggle:SetPoint("BOTTOMRIGHT", rightSlot, "TOPRIGHT", 0, 8)
    end

    -- The right slot column's own right edge is the one measurement here
    -- that's known good - the button sits on it and lands correctly. So the
    -- panel docks from that edge too, rather than from CharacterFrame's,
    -- which is a good way outside the visible artwork.
    local nudge = ns.Config:Get("dockNudge") or 0
    if rightSlot then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", rightSlot, "TOPRIGHT", SLOT_TO_EDGE + nudge, 12)
    else
        local inset = ArtInset() or DEFAULT_ART_INSET
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", inset + 1 + nudge, -12)
    end
end

-- Prints what the addon can actually see of the character frame. Guessing at
-- this from the outside has not worked; /hg dock reports the real numbers.
function Panel:ReportGeometry()
    if not (PaperDollFrame and PaperDollFrame:IsShown()) then
        ns:Print("open the character sheet first, then run /hg dock")
        return
    end
    local left, right = ColumnEdgeSlots()
    ns:Print("character frame: left %.1f  right %.1f  width %.1f",
        CharacterFrame:GetLeft() or -1, CharacterFrame:GetRight() or -1, CharacterFrame:GetWidth() or -1)
    if left and right then
        ns:Print("slot columns: left edge %.1f  right edge %.1f", left:GetLeft(), right:GetRight())
        ns:Print("derived artwork inset: %.1f (fallback %d)", ArtInset() or 0, DEFAULT_ART_INSET)
    else
        ns:Print("could not measure the slot columns")
    end
    ns:Print("panel left edge: %.1f   nudge: %d",
        panel:GetLeft() or -1, ns.Config:Get("dockNudge") or 0)
    ns:Print("use |cffffff00/hg dock <pixels>|r to shift it; negative moves it left")
end

function Panel:SetDockNudge(pixels)
    ns.Config:Set("dockNudge", pixels ~= 0 and pixels or nil)
    FitToFrame()
    ns:Print("dock nudge set to %d", pixels)
end

local function BuildPanel()
    toggle = CreateFrame("CheckButton", "HelloGearCharacterButton", CharacterFrame)
    toggle:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    toggle:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -54, -48)
    toggle:SetFrameLevel(CharacterFrame:GetFrameLevel() + 2)

    toggle.icon = toggle:CreateTexture(nil, "BACKGROUND")
    toggle.icon:SetPoint("TOPLEFT", 2, -2)
    toggle.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    toggle.icon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
    toggle.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Standard action-button furniture: the gold ring is drawn at ~1.83x the
    -- button, the same ratio Blizzard's 36px action buttons use for their
    -- 66px border.
    toggle.border = toggle:CreateTexture(nil, "OVERLAY")
    toggle.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    toggle.border:SetSize(BUTTON_SIZE * 1.83, BUTTON_SIZE * 1.83)
    toggle.border:SetPoint("CENTER", 0, -1)

    toggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    toggle:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    toggle:GetCheckedTexture():SetBlendMode("ADD")

    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Gear Sets", 1, 1, 1)
        GameTooltip:AddLine(("%d set(s)"):format(Sets:Count()), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", GameTooltip_Hide)
    toggle:SetScript("OnClick", function(self)
        Panel:SetShown(self:GetChecked())
    end)

    panel = CreateFrame("Frame", "HelloGearCharacterPanel", CharacterFrame, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    -- Provisional; FitToFrame docks it flush against the artwork once the
    -- character frame has been laid out.
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -45, -12)
    panel:SetFrameLevel(CharacterFrame:GetFrameLevel() + 1)
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Gear Sets")

    equipButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    equipButton:SetSize(84, 22)
    equipButton:SetPoint("TOPLEFT", 12, -32)
    equipButton:SetText(EQUIPSET_EQUIP or "Equip")
    equipButton:SetScript("OnClick", function()
        if selected then ns.Equip:EquipSet(selected) end
    end)
    equipButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Equip the selected set", 1, 1, 1)
        GameTooltip:Show()
    end)
    equipButton:SetScript("OnLeave", GameTooltip_Hide)

    saveButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    saveButton:SetSize(84, 22)
    saveButton:SetPoint("LEFT", equipButton, "RIGHT", 4, 0)
    saveButton:SetText(SAVE or "Save")
    saveButton:SetScript("OnClick", function()
        if not selected then return end
        Sets:SaveFromWorn(selected, true)
        ns:Print('"%s" now matches what you\'re wearing', selected)
        Panel:Refresh()
    end)
    saveButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Overwrite the selected set with what you're wearing", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    saveButton:SetScript("OnLeave", GameTooltip_Hide)

    scroll = CreateFrame("ScrollFrame", "HelloGearCharacterPanelScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -60)
    scroll:SetPoint("BOTTOMRIGHT", -28, 84)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PANEL_WIDTH - 40, 1)
    scroll:SetScrollChild(content)

    editButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    editButton:SetSize(PANEL_WIDTH - 24, 22)
    editButton:SetPoint("BOTTOMLEFT", 12, 56)
    editButton:SetScript("OnClick", function()
        Panel:SetEditing(not ns.Paperdoll:IsEditing())
    end)
    editButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Edit slots on the character sheet", 1, 1, 1)
        GameTooltip:AddLine("Each slot shows what the set does with it. " ..
            "Left-click a slot to pick its item from what you're carrying, " ..
            "right-click to take the slot in or out of the set.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    editButton:SetScript("OnLeave", GameTooltip_Hide)

    local newButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    newButton:SetSize(PANEL_WIDTH - 24, 22)
    newButton:SetPoint("BOTTOMLEFT", 12, 32)
    newButton:SetText("New set from worn gear")
    newButton:SetScript("OnClick", function() StaticPopup_Show("HELLOGEAR_NEW_SET") end)

    statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", 14, 14)
    statusText:SetPoint("BOTTOMRIGHT", -14, 14)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(false)

    -- Switching to Reputation or Skills leaves CharacterFrame shown but hides
    -- the paperdoll, so the panel follows PaperDollFrame rather than its own
    -- parent.
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            -- Re-measured on every show rather than once at login: the frame
            -- has a real rect by now, and this also re-fits if another addon
            -- rearranges the paperdoll later.
            FitToFrame()
            toggle:Show()
            if ns.Config:Get("panelShown") then
                panel:Show()
                Panel:Refresh()
            end
        end)
        PaperDollFrame:HookScript("OnHide", function()
            -- Hide directly rather than through SetShown: switching to the
            -- Reputation tab shouldn't be remembered as "the panel is closed".
            panel:Hide()
            toggle:Hide()
            Panel:SetEditing(false)
        end)
    end
    CharacterFrame:HookScript("OnHide", function()
        Panel:SetEditing(false)
        if options then options:Hide() end
    end)
end

--------------------------------------------------------------------------

function Panel:Init()
    BuildPanel()
    ns:On("GET_ITEM_INFO_RECEIVED", function()
        -- Item data trickles in from the server after login; redraw so rows
        -- and slot overlays stop showing question marks.
        if panel:IsShown() then Panel:Refresh() end
    end)
    ns:On("UNIT_INVENTORY_CHANGED", function(unit)
        if unit == "player" and panel:IsShown() then Panel:Refresh() end
    end)

    local paperdollUp = PaperDollFrame and PaperDollFrame:IsShown() or false
    if paperdollUp then FitToFrame() end
    toggle:SetShown(paperdollUp)
    toggle:SetChecked(ns.Config:Get("panelShown") and true or false)
    if paperdollUp and ns.Config:Get("panelShown") then
        panel:Show()
        self:Refresh()
    end
end

function Panel:Select(name)
    selected = name and Sets:Resolve(name) or nil
    if ns.Paperdoll:IsEditing() then
        -- Follow the selection rather than silently editing the old set.
        ns.Paperdoll:SetEditMode(selected and Sets:Get(selected) or nil)
    end
    self:Refresh()
end

function Panel:GetSelected()
    return selected
end

function Panel:SetEditing(on)
    if on and not selected then
        ns:Print("select a set first")
        return
    end
    ns.Paperdoll:SetEditMode(on and Sets:Get(selected) or nil)
    self:Refresh()
end

-- The button's visibility is tied to the paperdoll being up; this only
-- controls the panel itself, and is what gets remembered between sessions.
function Panel:SetShown(shown)
    shown = shown and true or false
    ns.Config:Set("panelShown", shown)
    toggle:SetChecked(shown)
    if shown then
        panel:Show()
        self:Refresh()
    else
        panel:Hide()
        self:SetEditing(false)
        if options then options:Hide() end
    end
end

function Panel:Toggle()
    if not panel then return end
    if panel:IsShown() then
        self:SetShown(false)
        return
    end
    if not (CharacterFrame and CharacterFrame:IsShown()) then
        ToggleCharacter("PaperDollFrame")
    elseif PaperDollFrame and not PaperDollFrame:IsShown() and CharacterFrameTab1 then
        -- Character sheet is up on Reputation or Skills; clicking the tab is
        -- the reliable way back to the paperdoll.
        CharacterFrameTab1:Click()
    end
    self:SetShown(true)
end

function Panel:Refresh()
    if not panel then return end

    if selected and not Sets:Get(selected) then selected = nil end
    if not selected then
        selected = HelloGearCharDB and HelloGearCharDB.currentSet
        if selected and not Sets:Get(selected) then selected = nil end
        if not selected then selected = Sets:Names(true)[1] end
    end

    ns.Menu:Refresh()
    if not panel:IsShown() then return end

    local names = Sets:Names(true)
    for i, name in ipairs(names) do
        local row = rows[i] or CreateRow(i)
        local set = Sets:Get(name)
        row.setName = name
        row.icon:SetTexture(Sets:GetIcon(set))
        local color = Sets:IsEquipped(name) and "|cff80ff80" or (set.hidden and "|cff909090" or "|cffffffff")
        row.label:SetText(color .. name .. "|r")
        row.selectedBar:SetShown(name == selected)
        row.stripe:SetShown(i % 2 == 0)
        row:Show()
    end
    for i = #names + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(#names * ROW_HEIGHT, 1))

    local editing = ns.Paperdoll:IsEditing()
    editButton:SetText(editing and "|cffffd200Done editing slots|r" or "Edit slots")
    if selected then
        equipButton:Enable()
        saveButton:Enable()
    else
        equipButton:Disable()
        saveButton:Disable()
    end

    local set = selected and Sets:Get(selected)
    if editing and set then
        statusText:SetText("L-click a slot: item   R-click: in/out")
    elseif set then
        local managed, missing = 0, 0
        for slot, gearID in pairs(set.equip) do
            managed = managed + 1
            if gearID ~= ns.EMPTY and Items.MatchScore(gearID, Items.GetWorn(slot)) ~= 3 then
                missing = missing + 1
            end
        end
        if missing == 0 then
            statusText:SetText(("%d slots - |cff80ff80all worn|r"):format(managed))
        else
            statusText:SetText(("%d slots, %d not worn"):format(managed, missing))
        end
    else
        statusText:SetText("No sets yet")
    end

    self:RefreshOptions()
end
