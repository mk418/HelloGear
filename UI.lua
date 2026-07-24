local ADDON_NAME, ns = ...

ns.UI = {}
local UI = ns.UI
local Items = ns.Items
local Sets = ns.Sets

local LIST_ROW_HEIGHT = 22
local LIST_VISIBLE = 15
local CELL = 40
local CELL_PAD = 6
local GRID_COLS = 5

local frame, listScroll, listContent, listRows = nil, nil, nil, {}
local nameBox, gridCells, helmButton, cloakButton, hiddenCheck, statusText
local selected

--------------------------------------------------------------------------
-- Slot cell states
--
-- Each slot in a set is one of three things, and the grid cycles between
-- them: wearing something specific, deliberately empty, or not managed by
-- this set at all. That last one is what makes a one-slot set possible.
--------------------------------------------------------------------------

local function CellState(set, slotID)
    local gearID = set.equip[slotID]
    if gearID == nil then return "ignored" end
    if gearID == ns.EMPTY then return "empty" end
    return "item"
end

local function CycleCell(set, slotID)
    local state = CellState(set, slotID)
    if state == "item" then
        set.equip[slotID] = ns.EMPTY
    elseif state == "empty" then
        set.equip[slotID] = nil
    else
        local worn = Items.GetWorn(slotID)
        set.equip[slotID] = worn or ns.EMPTY
    end
end

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
        local name = (self.editBox or self.EditBox):GetText()
        name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
        if not name or name == "" then return end
        if Sets:Get(name) then
            ns:Print('a set named "%s" already exists', name)
            return
        end
        Sets:SaveFromWorn(name)
        ns:Print('saved worn gear as "%s"', name)
        UI:Select(name)
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
            UI:Select(nil)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--------------------------------------------------------------------------
-- Set list
--------------------------------------------------------------------------

local function CreateListRow(index)
    local row = CreateFrame("Button", nil, listContent)
    row:SetSize(178, LIST_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * LIST_ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", -4, 0)
    row.label:SetJustifyH("LEFT")

    row.selectedTex = row:CreateTexture(nil, "BACKGROUND")
    row.selectedTex:SetAllPoints()
    row.selectedTex:SetColorTexture(0.3, 0.5, 0.3, 0.35)
    row.selectedTex:Hide()

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.1)

    row:SetScript("OnClick", function(self) UI:Select(self.setName) end)
    row:SetScript("OnDoubleClick", function(self) ns.Equip:EquipSet(self.setName) end)

    listRows[index] = row
    return row
end

--------------------------------------------------------------------------
-- Slot grid
--------------------------------------------------------------------------

local function UpdateCell(cell)
    local set = selected and Sets:Get(selected)
    if not set then
        cell.icon:SetTexture(cell.def.emptyIcon)
        cell.icon:SetDesaturated(true)
        cell.icon:SetAlpha(0.3)
        cell.marker:Hide()
        return
    end

    local state = CellState(set, cell.def.id)
    if state == "item" then
        local _, texture = Items.GetInfo(set.equip[cell.def.id])
        cell.icon:SetTexture(texture)
        cell.icon:SetDesaturated(false)
        cell.icon:SetAlpha(1)
        cell.marker:Hide()
    elseif state == "empty" then
        cell.icon:SetTexture(cell.def.emptyIcon)
        cell.icon:SetDesaturated(false)
        cell.icon:SetAlpha(0.8)
        cell.marker:SetText("|cffff8080x|r")
        cell.marker:Show()
    else
        cell.icon:SetTexture(cell.def.emptyIcon)
        cell.icon:SetDesaturated(true)
        cell.icon:SetAlpha(0.25)
        cell.marker:Hide()
    end
end

local function CellTooltip(self)
    local set = selected and Sets:Get(selected)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.def.label, 1, 1, 1)

    if set then
        local state = CellState(set, self.def.id)
        if state == "item" then
            local link = Items.GetLink(set.equip[self.def.id])
            local itemName = link or (Items.GetInfo(set.equip[self.def.id])) or "?"
            GameTooltip:AddLine(itemName)
        elseif state == "empty" then
            GameTooltip:AddLine("Set clears this slot", 1, 0.5, 0.5)
        else
            GameTooltip:AddLine("Set leaves this slot alone", 0.6, 0.6, 0.6)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to put what you're wearing here", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click to cycle: worn / clear slot / leave alone", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateCell(parent, def, index)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetSize(CELL, CELL)
    local col = (index - 1) % GRID_COLS
    local row = math.floor((index - 1) / GRID_COLS)
    cell:SetPoint("TOPLEFT", col * (CELL + CELL_PAD), -row * (CELL + CELL_PAD))
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.def = def

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints()
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    cell.border = cell:CreateTexture(nil, "OVERLAY")
    cell.border:SetPoint("TOPLEFT", -2, 2)
    cell.border:SetPoint("BOTTOMRIGHT", 2, -2)
    cell.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    cell.border:SetAlpha(0.6)

    cell.marker = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cell.marker:SetPoint("CENTER")

    cell.highlight = cell:CreateTexture(nil, "HIGHLIGHT")
    cell.highlight:SetAllPoints()
    cell.highlight:SetColorTexture(1, 1, 1, 0.15)

    cell:SetScript("OnEnter", CellTooltip)
    cell:SetScript("OnLeave", GameTooltip_Hide)
    cell:SetScript("OnClick", function(self, button)
        local set = selected and Sets:Get(selected)
        if not set then return end
        if button == "RightButton" then
            CycleCell(set, self.def.id)
        else
            set.equip[self.def.id] = Items.GetWorn(self.def.id) or ns.EMPTY
        end
        UI:Refresh()
        CellTooltip(self)
    end)

    return cell
end

--------------------------------------------------------------------------
-- Tri-state cosmetic toggles
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

--------------------------------------------------------------------------

function UI:Init()
    frame = CreateFrame("Frame", "HelloGearManager", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(620, 470)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    frame.TitleText:SetText("HelloGear")
    tinsert(UISpecialFrames, "HelloGearManager")

    -- Set list ------------------------------------------------------------
    local listLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", 16, -34)
    listLabel:SetText("Sets")

    listScroll = CreateFrame("ScrollFrame", "HelloGearManagerList", frame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 16, -50)
    listScroll:SetSize(178, LIST_VISIBLE * LIST_ROW_HEIGHT)

    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(178, 1)
    listScroll:SetScrollChild(listContent)

    local newButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    newButton:SetSize(88, 22)
    newButton:SetPoint("TOPLEFT", listScroll, "BOTTOMLEFT", 0, -8)
    newButton:SetText("New")
    newButton:SetScript("OnClick", function() StaticPopup_Show("HELLOGEAR_NEW_SET") end)
    newButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Save everything you're wearing as a new set", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    newButton:SetScript("OnLeave", GameTooltip_Hide)

    local deleteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deleteButton:SetSize(88, 22)
    deleteButton:SetPoint("LEFT", newButton, "RIGHT", 2, 0)
    deleteButton:SetText("Delete")
    deleteButton:SetScript("OnClick", function()
        if not selected then return end
        local dialog = StaticPopup_Show("HELLOGEAR_DELETE_SET", selected)
        if dialog then dialog.data = selected end
    end)

    local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importButton:SetSize(178, 22)
    importButton:SetPoint("TOPLEFT", newButton, "BOTTOMLEFT", 0, -4)
    importButton:SetText("Import from ItemRack")
    importButton:SetScript("OnClick", function() ns.Import:Run() end)
    importButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Import ItemRack sets", 1, 1, 1)
        local available = ns.Import:Available()
        if available > 0 then
            GameTooltip:AddLine(("%d set(s) available"):format(available), 0.5, 1, 0.5)
        else
            GameTooltip:AddLine("No ItemRack data found for this character", 1, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    importButton:SetScript("OnLeave", GameTooltip_Hide)
    self.importButton = importButton

    -- Detail pane ---------------------------------------------------------
    local detailX = 210

    nameBox = CreateFrame("EditBox", "HelloGearManagerName", frame, "InputBoxTemplate")
    nameBox:SetSize(240, 20)
    nameBox:SetPoint("TOPLEFT", detailX + 6, -52)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(40)
    nameBox:SetScript("OnEnterPressed", function(self)
        local newName = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        if selected and newName ~= "" and newName ~= selected then
            if Sets:Rename(selected, newName) then
                UI:Select(newName)
            else
                ns:Print('could not rename to "%s"', newName)
                self:SetText(selected)
            end
        end
        self:ClearFocus()
    end)
    nameBox:SetScript("OnEscapePressed", function(self)
        self:SetText(selected or "")
        self:ClearFocus()
    end)

    local nameHint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    nameHint:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    nameHint:SetText("Enter to rename")

    local equipButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    equipButton:SetSize(110, 22)
    equipButton:SetPoint("TOPLEFT", detailX, -80)
    equipButton:SetText("Equip")
    equipButton:SetScript("OnClick", function()
        if selected then ns.Equip:EquipSet(selected) end
    end)

    local saveButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveButton:SetSize(140, 22)
    saveButton:SetPoint("LEFT", equipButton, "RIGHT", 4, 0)
    saveButton:SetText("Save worn into set")
    saveButton:SetScript("OnClick", function()
        if not selected then return end
        Sets:SaveFromWorn(selected, true)
        ns:Print('"%s" now matches what you\'re wearing', selected)
        UI:Refresh()
    end)

    local iconButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    iconButton:SetSize(110, 22)
    iconButton:SetPoint("LEFT", saveButton, "RIGHT", 4, 0)
    iconButton:SetText("Reset icon")
    iconButton:SetScript("OnClick", function()
        local set = selected and Sets:Get(selected)
        if not set then return end
        set.icon = Sets:SuggestIcon(set)
        UI:Refresh()
    end)

    -- Slot grid -----------------------------------------------------------
    local gridLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    gridLabel:SetPoint("TOPLEFT", detailX, -114)
    gridLabel:SetText("Slots")

    local grid = CreateFrame("Frame", nil, frame)
    grid:SetPoint("TOPLEFT", detailX, -132)
    grid:SetSize(GRID_COLS * (CELL + CELL_PAD), 4 * (CELL + CELL_PAD))

    gridCells = {}
    for i, def in ipairs(ns.SLOTS) do
        gridCells[i] = CreateCell(grid, def, i)
    end

    -- Options -------------------------------------------------------------
    local optionsY = -132 - (math.ceil(#ns.SLOTS / GRID_COLS) * (CELL + CELL_PAD)) - 12

    helmButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    helmButton:SetSize(180, 22)
    helmButton:SetPoint("TOPLEFT", detailX, optionsY)
    helmButton:SetScript("OnClick", function()
        local set = selected and Sets:Get(selected)
        if not set then return end
        set.helm = CycleTriState(set.helm)
        UI:Refresh()
    end)

    cloakButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cloakButton:SetSize(180, 22)
    cloakButton:SetPoint("LEFT", helmButton, "RIGHT", 6, 0)
    cloakButton:SetScript("OnClick", function()
        local set = selected and Sets:Get(selected)
        if not set then return end
        set.cloak = CycleTriState(set.cloak)
        UI:Refresh()
    end)

    hiddenCheck = CreateFrame("CheckButton", "HelloGearHiddenCheck", frame, "UICheckButtonTemplate")
    hiddenCheck:SetPoint("TOPLEFT", helmButton, "BOTTOMLEFT", 0, -6)
    local hiddenText = _G["HelloGearHiddenCheckText"] or hiddenCheck.Text
    if hiddenText then hiddenText:SetText("Keep out of the quick menu") end
    hiddenCheck:SetScript("OnClick", function(self)
        local set = selected and Sets:Get(selected)
        if not set then return end
        set.hidden = self:GetChecked() or nil
        ns.Menu:Refresh()
    end)

    statusText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", 210, 14)
    statusText:SetPoint("BOTTOMRIGHT", -16, 14)
    statusText:SetJustifyH("LEFT")

    ns:On("GET_ITEM_INFO_RECEIVED", function()
        -- Item data trickles in from the server after login; redraw so the
        -- grid stops showing question marks.
        if frame:IsShown() then UI:Refresh() end
    end)
    ns:On("UNIT_INVENTORY_CHANGED", function(unit)
        if unit == "player" and frame:IsShown() then UI:Refresh() end
    end)

    self.frame = frame
end

function UI:Select(name)
    selected = name and Sets:Resolve(name) or nil
    self:Refresh()
end

function UI:Refresh()
    if not frame then return end

    if selected and not Sets:Get(selected) then selected = nil end
    if not selected then
        local names = Sets:Names(true)
        selected = names[1]
    end

    if self.importButton then
        if ns.Import:Available() > 0 then
            self.importButton:Enable()
        else
            self.importButton:Disable()
        end
    end

    if not frame:IsShown() then
        ns.Menu:Refresh()
        return
    end

    -- List
    local names = Sets:Names(true)
    for i, name in ipairs(names) do
        local row = listRows[i] or CreateListRow(i)
        local set = Sets:Get(name)
        row.setName = name
        row.icon:SetTexture(Sets:GetIcon(set))
        local color = Sets:IsEquipped(name) and "|cff80ff80" or (set.hidden and "|cff909090" or "|cffffffff")
        row.label:SetText(color .. name .. "|r")
        row.selectedTex:SetShown(name == selected)
        row:Show()
    end
    for i = #names + 1, #listRows do listRows[i]:Hide() end
    listContent:SetHeight(math.max(#names * LIST_ROW_HEIGHT, 1))

    -- Detail
    local set = selected and Sets:Get(selected)
    nameBox:SetText(selected or "")
    if set then nameBox:Enable() else nameBox:Disable() end
    hiddenCheck:SetChecked(set and set.hidden or false)
    helmButton:SetText(TriStateText("Helm", set and set.helm))
    cloakButton:SetText(TriStateText("Cloak", set and set.cloak))

    for _, cell in ipairs(gridCells) do UpdateCell(cell) end

    if set then
        local managed, missing = 0, 0
        for slot, gearID in pairs(set.equip) do
            managed = managed + 1
            if gearID ~= ns.EMPTY then
                local worn = Items.GetWorn(slot)
                if Items.MatchScore(gearID, worn) ~= 3 then missing = missing + 1 end
            end
        end
        if missing == 0 then
            statusText:SetText(("%d slot(s) managed - |cff80ff80fully equipped|r"):format(managed))
        else
            statusText:SetText(("%d slot(s) managed, %d not currently worn"):format(managed, missing))
        end
    else
        statusText:SetText("No set selected. Use New to save what you're wearing.")
    end

    ns.Menu:Refresh()
end

function UI:Toggle()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        if not selected then
            selected = HelloGearCharDB and HelloGearCharDB.currentSet
        end
        frame:Show()
        self:Refresh()
    end
end

function UI:Show()
    if frame and not frame:IsShown() then self:Toggle() end
end
