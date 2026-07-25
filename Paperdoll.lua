local ADDON_NAME, ns = ...

ns.Paperdoll = {}
local Paperdoll = ns.Paperdoll
local Items = ns.Items
local API = ns.API

local ROW_HEIGHT = 22
local WIDTH = 224
local INSET = 15         -- clear of the border
local SCROLLBAR_ROOM = 22  -- the scrollbar hangs outside the scroll frame
local ROW_WIDTH = WIDTH - INSET * 2 - SCROLLBAR_ROOM
local MAX_VISIBLE = 12

local flyout, scroll, content, scrollBar
local rows = {}
local openSlot
local openMode          -- "equip" (wear it now) or "assign" (put it in the set)
local widgets = {}      -- slotID -> {button, chevron, overlay}
local editingSet        -- set being edited on the paperdoll, or nil

--------------------------------------------------------------------------
-- Candidates
--------------------------------------------------------------------------

local function CanUseInSlot(equipLoc, slotID)
    local valid = ns.INVTYPE_SLOTS[equipLoc]
    if not valid then return false end
    for _, id in ipairs(valid) do
        if id == slotID then
            -- A one-hander only reaches the off hand if the character can
            -- actually dual wield.
            if slotID == 17 and equipLoc == "INVTYPE_WEAPON" and not CanDualWield() then
                return false
            end
            return true
        end
    end
    return false
end

local function GatherCandidates(slotID)
    local out, seen = {}, {}
    for _, entry in ipairs(Items.ScanBags()) do
        if not seen[entry.gearID] then
            local baseID = Items.BaseID(entry.gearID)
            local _, _, _, equipLoc = API.GetItemInfoInstant(baseID or 0)
            if equipLoc and CanUseInSlot(equipLoc, slotID) and Items.CanEquip(entry.gearID) then
                seen[entry.gearID] = true
                local name, texture, _, quality = Items.GetInfo(entry.gearID)
                local itemLevel = select(4, API.GetItemInfo(Items.ToItemString(entry.gearID) or "")) or 0
                out[#out + 1] = {
                    gearID = entry.gearID,
                    baseID = baseID,
                    name = name or ("Item " .. tostring(baseID)),
                    texture = texture,
                    quality = quality or 1,
                    itemLevel = itemLevel,
                    -- Kept so the row can read a cooldown off the item's
                    -- actual location; see Items.GetCooldown.
                    bag = entry.bag,
                    slot = entry.slot,
                }
            end
        end
    end

    table.sort(out, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
        return a.name < b.name
    end)
    return out
end

--------------------------------------------------------------------------
-- Swap flyout
--------------------------------------------------------------------------

local function CreateRow(index)
    local row = CreateFrame("Button", "HelloGearSlotRow" .. index, content)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.cooldown = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cooldown:SetAllPoints(row.icon)
    row.cooldown:SetDrawEdge(false)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", -4, 0)
    row.label:SetJustifyH("LEFT")

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.12)

    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(16, 16)
    row.check:SetPoint("RIGHT", -2, 0)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check:Hide()

    row:SetScript("OnEnter", function(self)
        if not self.gearID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = Items.GetLink(self.gearID)
        if link then GameTooltip:SetHyperlink(link) else GameTooltip:AddLine(self.label:GetText()) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        if openMode == "assign" then
            if editingSet then
                -- self.gearID is ns.EMPTY for the "no item" row, which is
                -- exactly what the set stores for "clear this slot".
                ns.Sets:SetSlot(editingSet, openSlot, self.gearID)
                Paperdoll:Refresh()
                ns.Panel:Refresh()
            end
        elseif self.gearID == ns.EMPTY then
            ns.Equip:ClearSlot(openSlot)
        else
            ns.Equip:EquipItem(self.gearID, openSlot)
        end
        Paperdoll:Close()
    end)

    rows[index] = row
    return row
end

local function BuildFlyout()
    flyout = ns.CreatePanel("HelloGearSlotFlyout")
    flyout:SetWidth(WIDTH)
    flyout:SetClampedToScreen(true)

    flyout.title = flyout:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    flyout.title:SetPoint("TOPLEFT", INSET + 2, -INSET)

    scroll = CreateFrame("ScrollFrame", "HelloGearSlotFlyoutScroll", flyout, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", INSET, -(INSET + 18))
    scroll:SetWidth(ROW_WIDTH)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_WIDTH, 1)
    scroll:SetScrollChild(content)
    scrollBar = _G[scroll:GetName() .. "ScrollBar"]

    flyout:SetScript("OnShow", function()
        if not Paperdoll.closer then
            Paperdoll.closer = CreateFrame("Frame", nil, UIParent)
            Paperdoll.closer:SetAllPoints()
            Paperdoll.closer:SetFrameStrata("DIALOG")
            Paperdoll.closer:SetFrameLevel(1)
            Paperdoll.closer:EnableMouse(true)
            Paperdoll.closer:SetScript("OnMouseDown", function() Paperdoll:Close() end)
        end
        Paperdoll.closer:Show()
    end)
    flyout:SetScript("OnHide", function()
        if Paperdoll.closer then Paperdoll.closer:Hide() end
        openSlot = nil
    end)
end

local function QualityColor(quality)
    local color = quality and ITEM_QUALITY_COLORS[quality]
    return color and color.hex or "|cffffffff"
end

local function Populate(slotID, mode)
    local def = ns.SLOT_BY_ID[slotID]
    local label = def and def.label or "Slot"
    local candidates = GatherCandidates(slotID)
    local worn = Items.GetWorn(slotID)
    local assigned = mode == "assign" and editingSet and editingSet.equip[slotID] or nil

    local index, seen = 0, {}
    local function AddRow(gearID, texture, text, source)
        if gearID ~= ns.EMPTY and seen[gearID] then return end
        seen[gearID] = true

        index = index + 1
        local row = rows[index] or CreateRow(index)
        row.gearID = gearID
        row.icon:SetTexture(texture)
        row.label:SetText(text)

        local start, duration = Items.GetCooldown(source)
        if start and duration and duration > 0 then
            row.cooldown:SetCooldown(start, duration)
        else
            row.cooldown:Clear()
        end

        row.check:SetShown(mode == "assign" and gearID == assigned)
        row:Show()
    end

    if mode == "assign" then
        flyout.title:SetText(("|cffffd200%s|r  |cff808080%s|r")
            :format(label, editingSet and editingSet.name or ""))
        -- Always offered: a set can deliberately strip a slot, and that's not
        -- the same as leaving the slot alone (which is the right-click).
        AddRow(ns.EMPTY, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "|cffff8080No item|r")
    else
        flyout.title:SetText("|cffffd200" .. label .. "|r")
        if worn then
            AddRow(ns.EMPTY, "Interface\\Buttons\\UI-GroupLoot-Pass-Up", "|cffff8080Take off|r")
        end
    end

    -- What you're wearing is a legitimate choice for a set; for an equip it
    -- would be a no-op, so it's only offered in assign mode.
    if mode == "assign" and worn then
        local name, texture, _, quality = Items.GetInfo(worn)
        AddRow(worn, texture,
            QualityColor(quality) .. (name or "...") .. "|r |cff808080(worn)|r",
            { invSlot = slotID })
    end

    for _, candidate in ipairs(candidates) do
        AddRow(candidate.gearID, candidate.texture,
            QualityColor(candidate.quality) .. candidate.name .. "|r",
            candidate)
    end

    -- The set can point at gear that's in the bank, or gone. Show it anyway,
    -- so it can be seen for what it is and replaced.
    if assigned and assigned ~= ns.EMPTY and not seen[assigned] then
        local name, texture, _, quality = Items.GetInfo(assigned)
        AddRow(assigned, texture,
            QualityColor(quality) .. (name or "...") .. "|r |cff808080(not carried)|r")
    end

    for i = index + 1, #rows do rows[i]:Hide() end

    if index == 0 then
        flyout.title:SetText(("|cffffd200%s|r  |cff808080nothing to swap in|r"):format(label))
    end

    local visible = math.min(math.max(index, 1), MAX_VISIBLE)
    content:SetHeight(math.max(index * ROW_HEIGHT, 1))
    scroll:SetHeight(visible * ROW_HEIGHT)
    if scrollBar then scrollBar:SetShown(index > MAX_VISIBLE) end
    flyout:SetHeight(visible * ROW_HEIGHT + INSET * 2 + 20)
end

function Paperdoll:Open(slotID, anchor, mode)
    if not flyout then BuildFlyout() end
    openSlot = slotID
    openMode = mode or "equip"
    Populate(slotID, openMode)
    flyout:ClearAllPoints()
    flyout:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    flyout:Show()
end

function Paperdoll:Close()
    if flyout then flyout:Hide() end
end

function Paperdoll:Toggle(slotID, anchor, mode)
    if flyout and flyout:IsShown() and openSlot == slotID then
        self:Close()
    else
        self:Open(slotID, anchor, mode)
    end
end

--------------------------------------------------------------------------
-- Slot editing
--
-- While a set is being edited the overlays stop being a modifier-only
-- affordance and take every click on the paperdoll. That is deliberate: the
-- natural gesture on a slot is a left-click, and the default handler would
-- have picked the item up before any hook of ours saw the click. Owning the
-- mouse is the only way to make left-click mean "cycle this slot".
--------------------------------------------------------------------------

local STATE_COLOR = {
    worn   = { 0.25, 0.85, 0.25 },  -- managed, and it's on right now
    stored = { 1.00, 0.82, 0.20 },  -- managed, but not currently worn
    empty  = { 0.90, 0.30, 0.30 },  -- the set clears this slot
}

local function SlotState(set, slotID)
    return ns.Sets:SlotState(set, slotID)
end

local function UpdateEditOverlay(w)
    local overlay = w.overlay
    if not editingSet then
        overlay.icon:Hide()
        overlay.border:Hide()
        overlay.dim:Hide()
        overlay.cross:Hide()
        return
    end

    local state = SlotState(editingSet, w.slotID)

    if state == "ignored" then
        overlay.icon:Hide()
        overlay.border:Hide()
        overlay.cross:Hide()
        overlay.dim:Show()
    elseif state == "empty" then
        overlay.icon:Hide()
        overlay.dim:Hide()
        overlay.cross:Show()
        overlay.border:SetVertexColor(unpack(STATE_COLOR.empty))
        overlay.border:Show()
    else
        local _, texture = Items.GetInfo(editingSet.equip[w.slotID])
        overlay.icon:SetTexture(texture)
        overlay.icon:Show()
        overlay.dim:Hide()
        overlay.cross:Hide()
        overlay.border:SetVertexColor(unpack(STATE_COLOR[state]))
        overlay.border:Show()
    end
end

local function OverlayTooltip(self)
    if not editingSet then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetInventoryItem("player", self.slotID)
        GameTooltip:Show()
        return
    end

    local def = ns.SLOT_BY_ID[self.slotID]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(def and def.label or "Slot", 1, 1, 1)

    local state = SlotState(editingSet, self.slotID)
    if state == "ignored" then
        GameTooltip:AddLine("Left alone by this set", 0.6, 0.6, 0.6)
    elseif state == "empty" then
        GameTooltip:AddLine("Cleared by this set", 0.9, 0.4, 0.4)
    else
        local gearID = editingSet.equip[self.slotID]
        GameTooltip:AddLine(Items.GetLink(gearID) or (Items.GetInfo(gearID)) or "?")
        if state == "stored" then
            GameTooltip:AddLine("Not currently worn", 1, 0.82, 0.2)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click to pick the item for this slot", 0.6, 0.6, 0.6)
    GameTooltip:AddLine(state == "ignored"
        and "Right-click to add this slot to the set"
        or "Right-click to drop this slot from the set", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function Paperdoll:SetEditMode(set)
    editingSet = set
    if set then self:Close() end
    self:ApplyVisibility()
end

function Paperdoll:IsEditing()
    return editingSet ~= nil
end

function Paperdoll:GetEditingSet()
    return editingSet
end

--------------------------------------------------------------------------
-- Attachments
--------------------------------------------------------------------------

local function ModifierHeld()
    local mod = ns.Config:Get("slotMenuModifier")
    if mod == "ALT" then return IsAltKeyDown() end
    if mod == "CTRL" then return IsControlKeyDown() end
    if mod == "SHIFT" then return IsShiftKeyDown() end
    return false
end

local function AttachTo(def)
    local button = _G["Character" .. def.key]
    if not button then return end

    local chevron = CreateFrame("Button", nil, button)
    chevron:SetSize(12, 12)
    chevron:SetPoint("BOTTOMRIGHT", 2, -2)
    chevron:SetFrameLevel(button:GetFrameLevel() + 3)
    chevron:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    chevron:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    chevron:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    chevron:GetNormalTexture():SetAlpha(0.55)
    chevron:SetScript("OnEnter", function(self)
        self:GetNormalTexture():SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Swap " .. def.label:lower(), 1, 1, 1)
        GameTooltip:Show()
    end)
    chevron:SetScript("OnLeave", function(self)
        self:GetNormalTexture():SetAlpha(0.55)
        GameTooltip_Hide()
    end)
    chevron:SetScript("OnClick", function()
        Paperdoll:Toggle(def.id, button)
    end)

    local overlay = CreateFrame("Button", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button:GetFrameLevel() + 2)
    overlay:EnableMouse(false)
    overlay:Hide()
    overlay.slotID = def.id

    -- The set's item is drawn over the real one rather than by retexturing the
    -- slot button itself: PaperDollItemSlotButton_Update would stomp any change
    -- we made there on the next inventory event.
    overlay.icon = overlay:CreateTexture(nil, "ARTWORK")
    overlay.icon:SetAllPoints()
    overlay.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    overlay.icon:Hide()

    overlay.dim = overlay:CreateTexture(nil, "OVERLAY")
    overlay.dim:SetAllPoints()
    overlay.dim:SetColorTexture(0, 0, 0, 0.6)
    overlay.dim:Hide()

    overlay.cross = overlay:CreateTexture(nil, "OVERLAY")
    overlay.cross:SetSize(22, 22)
    overlay.cross:SetPoint("CENTER")
    overlay.cross:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    overlay.cross:Hide()

    overlay.border = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    overlay.border:SetPoint("TOPLEFT", -2, 2)
    overlay.border:SetPoint("BOTTOMRIGHT", 2, -2)
    overlay.border:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    overlay.border:Hide()

    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:SetScript("OnEnter", OverlayTooltip)
    overlay:SetScript("OnLeave", GameTooltip_Hide)
    overlay:SetScript("OnClick", function(self, click)
        if not editingSet then
            Paperdoll:Toggle(self.slotID, button)
        elseif click == "RightButton" then
            ns.Sets:ToggleSlot(editingSet, self.slotID)
            Paperdoll:Close()
            UpdateEditOverlay(widgets[self.slotID])
            ns.Panel:Refresh()
            OverlayTooltip(self)
        else
            Paperdoll:Toggle(self.slotID, button, "assign")
        end
    end)

    widgets[def.id] = { button = button, chevron = chevron, overlay = overlay, slotID = def.id }
end

function Paperdoll:ApplyVisibility()
    local enabled = ns.Config:Get("slotMenus")
    local editing = editingSet ~= nil
    -- While editing, the arrows would offer a second, conflicting meaning for
    -- clicking a slot, so they go away.
    local chevrons = enabled and not editing and ns.Config:Get("slotMenuChevrons")
    local overlayOn = editing or (enabled and ModifierHeld())

    for _, w in pairs(widgets) do
        w.chevron:SetShown(chevrons and true or false)
        w.overlay:EnableMouse(overlayOn and true or false)
        w.overlay:SetShown(overlayOn and true or false)
        UpdateEditOverlay(w)
    end

    if not enabled and not editing then self:Close() end
end

function Paperdoll:Refresh()
    if flyout and flyout:IsShown() and openSlot then
        Populate(openSlot, openMode)
    end
    if editingSet then
        for _, w in pairs(widgets) do UpdateEditOverlay(w) end
    end
end

function Paperdoll:Init()
    for _, def in ipairs(ns.SLOTS) do
        AttachTo(def)
    end
    -- MODIFIER_STATE_CHANGED is a firehose. There is nothing to update unless
    -- the character sheet is actually on screen.
    ns:On("MODIFIER_STATE_CHANGED", function()
        if CharacterFrame and CharacterFrame:IsShown() then
            Paperdoll:ApplyVisibility()
        end
    end)
    ns:On("PLAYER_REGEN_DISABLED", function() Paperdoll:Close() end)
    self:ApplyVisibility()
end
