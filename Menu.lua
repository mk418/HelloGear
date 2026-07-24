local ADDON_NAME, ns = ...

ns.Menu = {}
local Menu = ns.Menu
local Items = ns.Items
local Sets = ns.Sets

local ROW_HEIGHT = 20
local WIDTH = 210
local INSET = 15         -- clear of the border
-- UIPanelScrollFrameTemplate hangs its scrollbar OUTSIDE the scroll frame's
-- right edge, so the rows have to give up that much or the bar lands on the
-- border - or past it, outside the panel entirely.
local SCROLLBAR_ROOM = 22
local ROW_WIDTH = WIDTH - INSET * 2 - SCROLLBAR_ROOM
local MAX_VISIBLE = 14

local frame, scroll, content, scrollBar, footer
local rows = {}
local showHidden = false

--------------------------------------------------------------------------
-- The shared popup chrome. Built by hand rather than borrowing a Blizzard
-- dropdown: the dropdown API changed shape when Era moved onto the modern
-- UI codebase, and this needs about twenty lines of frame anyway.
--------------------------------------------------------------------------

-- 1.15.9 put Classic Era on the modern UI, and the character frame with it:
-- it's the dark nine-slice chrome now, not the old tan parchment. So
-- UI-DialogBox-Border was never going to match it at any edge size - it's the
-- wrong frame entirely. Borrow the same border the rest of that UI uses, and
-- keep the backdrop only for a client that doesn't have it.
local BORDER_TEMPLATES = { "DialogBorderDarkTemplate", "DialogBorderTemplate" }

ns.BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local borderTemplate
for _, template in ipairs(BORDER_TEMPLATES) do
    local ok, probe = pcall(CreateFrame, "Frame", nil, UIParent, template)
    if ok and probe then
        probe:Hide()
        borderTemplate = template
        break
    end
end

-- How far a panel has to overlap what it docks against for the two drawn
-- edges to meet. The nine-slice border sits nearly on the frame's bounds; the
-- fallback backdrop's edge texture is drawn well inside them.
ns.CHROME_INSET = borderTemplate and 4 or 11

local function ApplyChrome(target)
    if not borderTemplate then
        target:SetBackdrop(ns.BACKDROP)
        return
    end
    local bg = target:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    bg:SetColorTexture(0.04, 0.04, 0.05, 0.9)
    target.bg = bg

    local border = CreateFrame("Frame", nil, target, borderTemplate)
    border:SetAllPoints(target)
    target.chrome = border
end
ns.ApplyChrome = ApplyChrome

local function CreatePanel(name, parent)
    local f = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    ApplyChrome(f)
    f:SetFrameStrata("DIALOG")
    -- Explicit level so the click-away catcher (level 1, same strata) is
    -- always underneath rather than depending on creation order.
    f:SetFrameLevel(30)
    f:EnableMouse(true)
    f:Hide()
    return f
end
ns.CreatePanel = CreatePanel

--------------------------------------------------------------------------

local function SetTooltip(self)
    local set = Sets:Get(self.setName)
    if not set then return end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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
    GameTooltip:AddLine("Click to equip", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Shift-click to toggle on/off", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Right-click to put back what it replaced", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, content)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", -4, 0)
    row.label:SetJustifyH("LEFT")

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.12)

    row:SetScript("OnEnter", SetTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ns.Equip:UnequipSet(self.setName)
        elseif IsShiftKeyDown() then
            ns.Equip:ToggleSet(self.setName)
        else
            ns.Equip:EquipSet(self.setName)
        end
        Menu:Hide()
    end)

    rows[index] = row
    return row
end

function Menu:Init()
    frame = CreatePanel("HelloGearMenu")
    frame:SetWidth(WIDTH)
    frame:SetClampedToScreen(true)

    scroll = CreateFrame("ScrollFrame", "HelloGearMenuScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", INSET, -INSET)
    scroll:SetWidth(ROW_WIDTH)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_WIDTH, 1)
    scroll:SetScrollChild(content)
    scrollBar = _G[scroll:GetName() .. "ScrollBar"]

    footer = CreateFrame("Button", nil, frame)
    footer:SetSize(ROW_WIDTH, ROW_HEIGHT)
    footer:SetPoint("BOTTOMLEFT", INSET, INSET)
    footer.label = footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    footer.label:SetPoint("LEFT", 2, 0)
    footer.label:SetText("Manage sets...")
    footer.highlight = footer:CreateTexture(nil, "HIGHLIGHT")
    footer.highlight:SetAllPoints()
    footer.highlight:SetColorTexture(1, 1, 1, 0.12)
    footer:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    footer:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            Menu:SetShowHidden(not showHidden)
        else
            Menu:Hide()
            ns.Panel:Toggle()
        end
    end)
    footer:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Click to open the set manager", 1, 1, 1)
        GameTooltip:AddLine("Right-click to show or hide sets marked hidden", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    footer:SetScript("OnLeave", GameTooltip_Hide)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 3)
    divider:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 3)

    -- Clicking anywhere else dismisses the menu, the way a dropdown would.
    frame:SetScript("OnShow", function()
        if not Menu.closer then
            Menu.closer = CreateFrame("Frame", nil, UIParent)
            Menu.closer:SetAllPoints()
            Menu.closer:SetFrameStrata("DIALOG")
            Menu.closer:SetFrameLevel(1)
            Menu.closer:EnableMouse(true)
            Menu.closer:SetScript("OnMouseDown", function() Menu:Hide() end)
        end
        Menu.closer:Show()
    end)
    frame:SetScript("OnHide", function()
        if Menu.closer then Menu.closer:Hide() end
    end)

    ns:On("PLAYER_REGEN_DISABLED", function() Menu:Hide() end)
end

function Menu:Refresh()
    if not frame or not frame:IsShown() then return end
    self:Populate()
end

function Menu:Populate()
    local names = Sets:Names(showHidden)
    local hiddenCount = #Sets:Names(true) - #Sets:Names(false)

    for i, name in ipairs(names) do
        local row = rows[i] or CreateRow(i)
        row.setName = name
        row.icon:SetTexture(Sets:GetIcon(Sets:Get(name)))

        local equipped = Sets:IsEquipped(name)
        row.label:SetText((equipped and "|cff80ff80" or "|cffffffff") .. name .. "|r")
        row.icon:SetDesaturated(Sets:Get(name).hidden and not equipped or false)
        row:Show()
    end
    for i = #names + 1, #rows do
        rows[i]:Hide()
    end

    if #names == 0 then
        footer.label:SetText("No sets yet - manage...")
    elseif hiddenCount > 0 then
        footer.label:SetText(showHidden and "Manage sets..." or ("Manage sets... (+%d hidden)"):format(hiddenCount))
    else
        footer.label:SetText("Manage sets...")
    end

    local visible = math.min(math.max(#names, 1), MAX_VISIBLE)
    content:SetHeight(math.max(#names * ROW_HEIGHT, 1))
    scroll:SetHeight(visible * ROW_HEIGHT)
    if scrollBar then scrollBar:SetShown(#names > MAX_VISIBLE) end
    frame:SetHeight(visible * ROW_HEIGHT + ROW_HEIGHT + INSET * 2 + 8)
end

function Menu:Show(anchorFrame)
    self:Populate()
    frame:ClearAllPoints()
    if anchorFrame then
        local _, y = anchorFrame:GetCenter()
        local below = y and y > (UIParent:GetHeight() / 2)
        if below then
            frame:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -4)
        else
            frame:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 4)
        end
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
end

function Menu:Hide()
    if frame then frame:Hide() end
end

function Menu:Toggle(anchorFrame)
    if frame and frame:IsShown() then
        self:Hide()
    else
        self:Show(anchorFrame)
    end
end

function Menu:SetShowHidden(value)
    showHidden = value
    self:Refresh()
end

function Menu:IsShown()
    return frame and frame:IsShown()
end
