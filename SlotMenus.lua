local ADDON_NAME, ns = ...

ns.SlotMenus = {}
local SlotMenus = ns.SlotMenus
local Items = ns.Items
local API = ns.API

local ROW_HEIGHT = 22
local WIDTH = 210
local MAX_VISIBLE = 12

local flyout, scroll, content
local rows = {}
local openSlot
local widgets = {}   -- slotID -> {button, chevron, overlay}

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
-- Flyout
--------------------------------------------------------------------------

local function CreateRow(index)
    local row = CreateFrame("Button", "HelloGearSlotRow" .. index, content)
    row:SetSize(WIDTH - 24, ROW_HEIGHT)
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

    row:SetScript("OnEnter", function(self)
        if not self.gearID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local link = Items.GetLink(self.gearID)
        if link then GameTooltip:SetHyperlink(link) else GameTooltip:AddLine(self.label:GetText()) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        if self.gearID == ns.EMPTY then
            ns.Equip:ClearSlot(openSlot)
        else
            ns.Equip:EquipItem(self.gearID, openSlot)
        end
        SlotMenus:Close()
    end)

    rows[index] = row
    return row
end

local function BuildFlyout()
    flyout = ns.CreatePanel("HelloGearSlotFlyout")
    flyout:SetWidth(WIDTH)
    flyout:SetClampedToScreen(true)

    flyout.title = flyout:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    flyout.title:SetPoint("TOPLEFT", 12, -10)

    scroll = CreateFrame("ScrollFrame", "HelloGearSlotFlyoutScroll", flyout, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -26)
    scroll:SetWidth(WIDTH - 24)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 24, 1)
    scroll:SetScrollChild(content)

    flyout:SetScript("OnShow", function()
        if not SlotMenus.closer then
            SlotMenus.closer = CreateFrame("Frame", nil, UIParent)
            SlotMenus.closer:SetAllPoints()
            SlotMenus.closer:SetFrameStrata("DIALOG")
            SlotMenus.closer:SetFrameLevel(1)
            SlotMenus.closer:EnableMouse(true)
            SlotMenus.closer:SetScript("OnMouseDown", function() SlotMenus:Close() end)
        end
        SlotMenus.closer:Show()
    end)
    flyout:SetScript("OnHide", function()
        if SlotMenus.closer then SlotMenus.closer:Hide() end
        openSlot = nil
    end)
end

local function Populate(slotID)
    local def = ns.SLOT_BY_ID[slotID]
    local candidates = GatherCandidates(slotID)
    local worn = Items.GetWorn(slotID)

    flyout.title:SetText("|cffffd200" .. (def and def.label or "Slot") .. "|r")

    local index = 0

    if worn then
        index = index + 1
        local row = rows[index] or CreateRow(index)
        row.gearID = ns.EMPTY
        row.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        row.cooldown:Clear()
        row.label:SetText("|cffff8080Take off|r")
        row:Show()
    end

    for _, candidate in ipairs(candidates) do
        index = index + 1
        local row = rows[index] or CreateRow(index)
        row.gearID = candidate.gearID
        row.icon:SetTexture(candidate.texture)
        local color = ITEM_QUALITY_COLORS[candidate.quality]
        row.label:SetText((color and color.hex or "|cffffffff") .. candidate.name .. "|r")

        local start, duration = API.GetItemCooldown(candidate.baseID)
        if start and duration and duration > 0 then
            row.cooldown:SetCooldown(start, duration)
        else
            row.cooldown:Clear()
        end
        row:Show()
    end

    for i = index + 1, #rows do rows[i]:Hide() end

    if index == 0 then
        flyout.title:SetText("|cffffd200" .. (def and def.label or "Slot") .. "|r  |cff808080nothing to swap in|r")
    end

    local visible = math.min(math.max(index, 1), MAX_VISIBLE)
    content:SetHeight(math.max(index * ROW_HEIGHT, 1))
    scroll:SetHeight(visible * ROW_HEIGHT)
    flyout:SetHeight(visible * ROW_HEIGHT + 42)
end

function SlotMenus:Open(slotID, anchor)
    if not flyout then BuildFlyout() end
    openSlot = slotID
    Populate(slotID)
    flyout:ClearAllPoints()
    flyout:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    flyout:Show()
end

function SlotMenus:Close()
    if flyout then flyout:Hide() end
end

function SlotMenus:Toggle(slotID, anchor)
    if flyout and flyout:IsShown() and openSlot == slotID then
        self:Close()
    else
        self:Open(slotID, anchor)
    end
end

function SlotMenus:Refresh()
    if flyout and flyout:IsShown() and openSlot then
        Populate(openSlot)
    end
end

--------------------------------------------------------------------------
-- Paperdoll attachments
--
-- Two ways in, because neither alone is good enough: a small arrow in the
-- corner of each slot so the feature is discoverable, and a modifier-click
-- for when you already know it's there.
--
-- The modifier click is done with an overlay that only takes the mouse while
-- the modifier is held. Hooking the slot button's own OnClick doesn't work -
-- the default handler runs first and has already picked the item up by the
-- time the hook sees the click.
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
    chevron:SetFrameLevel(button:GetFrameLevel() + 2)
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
        SlotMenus:Toggle(def.id, button)
    end)

    local overlay = CreateFrame("Button", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button:GetFrameLevel() + 1)
    overlay:EnableMouse(false)
    overlay:Hide()
    overlay:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetInventoryItem("player", def.id)
        GameTooltip:Show()
    end)
    overlay:SetScript("OnLeave", GameTooltip_Hide)
    overlay:SetScript("OnClick", function()
        SlotMenus:Toggle(def.id, button)
    end)

    widgets[def.id] = { button = button, chevron = chevron, overlay = overlay }
end

function SlotMenus:ApplyVisibility()
    local enabled = ns.Config:Get("slotMenus")
    local chevrons = enabled and ns.Config:Get("slotMenuChevrons")
    local overlayOn = enabled and ModifierHeld()
    for _, w in pairs(widgets) do
        w.chevron:SetShown(chevrons and true or false)
        w.overlay:EnableMouse(overlayOn and true or false)
        w.overlay:SetShown(overlayOn and true or false)
    end
    if not enabled then self:Close() end
end

function SlotMenus:Init()
    for _, def in ipairs(ns.SLOTS) do
        AttachTo(def)
    end
    -- MODIFIER_STATE_CHANGED is a firehose. There is nothing to update unless
    -- the character sheet is actually on screen.
    ns:On("MODIFIER_STATE_CHANGED", function()
        if CharacterFrame and CharacterFrame:IsShown() then
            SlotMenus:ApplyVisibility()
        end
    end)
    ns:On("PLAYER_REGEN_DISABLED", function() SlotMenus:Close() end)
    self:ApplyVisibility()
end
