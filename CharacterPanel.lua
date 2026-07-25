local ADDON_NAME, ns = ...

ns.Panel = {}
local Panel = ns.Panel
local Items = ns.Items
local Sets = ns.Sets

local PANEL_WIDTH = 214
local PANEL_HEIGHT = 400   -- provisional; FitToFrame anchors top and bottom
local ROW_HEIGHT = 36
local CONTENT_LEFT = 16    -- clear of the border
local CONTENT_RIGHT = -34  -- border, plus room for the scrollbar inside it
local ROW_WIDTH = PANEL_WIDTH + CONTENT_RIGHT - CONTENT_LEFT
local BUTTON_SIZE = 26


local panel, toggle, scroll, content, scrollBar, statusText, editButton, equipButton, saveButton
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
    options:SetSize(252, 182)
    options:SetClampedToScreen(true)

    options.title = options:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    options.title:SetPoint("TOPLEFT", 18, -18)
    options.title:SetText("Set options")

    options.nameBox = CreateFrame("EditBox", "HelloGearSetOptionsName", options, "InputBoxTemplate")
    options.nameBox:SetSize(206, 20)
    options.nameBox:SetPoint("TOPLEFT", 24, -40)
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
    options.helm:SetSize(206, 22)
    options.helm:SetPoint("TOPLEFT", options.nameBox, "BOTTOMLEFT", -2, -18)
    options.helm:SetScript("OnClick", function()
        local set = options.setName and Sets:Get(options.setName)
        if not set then return end
        set.helm = CycleTriState(set.helm)
        Panel:RefreshOptions()
    end)

    options.cloak = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    options.cloak:SetSize(206, 22)
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
    options.resetIcon:SetSize(206, 22)
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
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
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

-- Used when the measurement doesn't make sense. Only a fallback; the whole
-- point is not to rely on it. Measured on 1.15.9: CharacterFrame spans 0..384,
-- the slot columns run 21..343, so the artwork ends around 364 and the frame
-- carries ~20px of dead space past it.
local DEFAULT_ART_INSET = -20

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

-- Same problem at the bottom: CharacterFrame runs well past the artwork, this
-- time to leave room for the tab row. The tabs are the measurable thing - they
-- sit across the artwork's bottom edge, overlapping it by a few pixels.
local DEFAULT_ART_BOTTOM = 67
local TAB_OVERLAP = -11   -- the tabs overlap upward into the artwork

-- How far above CharacterFrame's bottom the artwork ends.
function Panel.ComputeArtBottom(frameBottom, tabTop)
    if not tabTop then return DEFAULT_ART_BOTTOM end
    local offset = (tabTop + TAB_OVERLAP) - frameBottom
    if offset < 20 or offset > 200 then return DEFAULT_ART_BOTTOM end
    return offset
end

-- The close button's own edges sit this far inside the artwork's corner.
local CLOSE_TO_EDGE = -8

--------------------------------------------------------------------------
-- Borrowing the character frame's own chrome
--
-- Read off the client with /hg dock art: the character frame is four texture
-- quadrants laid out 384x512 on PaperDollFrame, the classic corner-piece
-- frame. There is no reusable template for it, which is why every look-alike
-- border tried here was visibly not it.
--
-- So the panel draws those same four textures again, shifted right so their
-- right border lands on the panel's right edge. Everything to the left of the
-- character frame's own edge is hidden behind it (the panel draws underneath),
-- and what's left on screen is the character frame's artwork simply carrying
-- on - same border, same corners, same interior, no seam to match because
-- there isn't one.
--------------------------------------------------------------------------

-- Coordinates within the artwork's own 384x512 layout.
-- All measured off screenshot pixels rather than estimated: the artwork's
-- visible edges sit inside its 384x512 layout, with transparent padding on
-- every side, and every one of these was originally guessed wrong.
local ART_VISIBLE_RIGHT = 348   -- where the frame's right border ends
local ART_TOP_PADDING = 5       -- transparent rows above the top border
local ART_BORDER = 11           -- how thick that border is

-- Stretches of border known to be free of decoration. Whole quadrants can't be
-- used directly: they carry the paperdoll's slot recesses, and the bottom
-- border carries the hardware the character tabs bolt onto, which ends up
-- orphaned in the middle of a panel that has no tabs. So each edge is built
-- from a clean strip instead, and the bottom reuses the top border flipped -
-- the top is the one horizontal edge with nothing attached to it.
local CLEAN_TOP_X1, CLEAN_TOP_X2 = 120, 240   -- plain run of the top border
-- Depth matters as much as the x range: at depth 60 the right border is flat
-- and dark, while from ~120 down it carries the bevel that ends in the bright
-- outer line. Sampling the former is why the panel had a dull dark band for an
-- edge. Verified the same at depths 125, 245 and 365.
local CLEAN_RIGHT_Y1, CLEAN_RIGHT_Y2 = 250, 252

-- Read at runtime rather than hardcoding file IDs, so a client that ships
-- different artwork still gets its own.
local function FrameArtPieces()
    if not PaperDollFrame then return nil end
    local pieces = {}
    for _, region in ipairs({ PaperDollFrame:GetRegions() }) do
        if region.GetTexture and region:GetDrawLayer() == "BORDER" then
            local file = region:GetTexture()
            local point, _, relPoint, ox, oy = region:GetPoint(1)
            if file and point == "TOPLEFT" and relPoint == "TOPLEFT" then
                pieces[#pieces + 1] = {
                    file = file,
                    width = region:GetWidth(),
                    height = region:GetHeight(),
                    x = ox or 0,
                    y = oy or 0,
                }
            end
        end
    end
    return #pieces > 0 and pieces or nil
end

-- The four quadrants keyed by which corner they are, identified by their own
-- offsets rather than by order or file ID.
local function ArtQuadrants()
    local pieces = FrameArtPieces()
    if not pieces then return nil end
    local quads = {}
    for _, piece in ipairs(pieces) do
        local key = (piece.y == 0 and "top" or "bottom") .. (piece.x == 0 and "Left" or "Right")
        quads[key] = piece
    end
    return (quads.topLeft and quads.topRight) and quads or nil
end

-- Frame coordinates -> texture coordinates within one quadrant. `depth` is
-- measured downward from the artwork's top, the way the layout offsets are.
function Panel.TexCoords(quad, x1, x2, depth1, depth2)
    local quadTop = -quad.y
    return (x1 - quad.x) / quad.width, (x2 - quad.x) / quad.width,
           (depth1 - quadTop) / quad.height, (depth2 - quadTop) / quad.height
end
local TexCoords = Panel.TexCoords

local function Slice(parent, quad, x1, x2, depth1, depth2, flipVertically)
    local texture = parent:CreateTexture(nil, "BORDER")
    texture:SetTexture(quad.file)
    local left, right, top, bottom = TexCoords(quad, x1, x2, depth1, depth2)
    if flipVertically then top, bottom = bottom, top end
    texture:SetTexCoord(left, right, top, bottom)
    return texture
end

-- Builds the panel's chrome out of clean strips of the character frame's own
-- artwork. Every piece is anchored to the panel's own edges, so unlike the
-- whole-quadrant approach this doesn't depend on the panel and the artwork
-- agreeing about where the frame's corner is.
local function BuildChrome(target)
    local quads = ArtQuadrants()
    if not quads then
        ns.ApplyChrome(target)
        return false
    end

    -- Textures can't be destroyed, so a rebuild hides the old set and makes a
    -- new one. Only ever a handful, and only when /hg dock border is used.
    if target.chrome then
        for _, texture in ipairs(target.chrome) do texture:Hide() end
    end
    target.chrome = {}
    local function keep(texture)
        target.chrome[#target.chrome + 1] = texture
        return texture
    end

    local B = ns.Config:Get("artBorder") or ART_BORDER
    local R = ART_VISIBLE_RIGHT

    local top = keep(Slice(target, quads.topLeft, CLEAN_TOP_X1, CLEAN_TOP_X2, ART_TOP_PADDING, ART_TOP_PADDING + B))
    top:SetPoint("TOPLEFT")
    top:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", -B, -B)

    local bottom = keep(Slice(target, quads.topLeft, CLEAN_TOP_X1, CLEAN_TOP_X2, ART_TOP_PADDING, ART_TOP_PADDING + B, true))
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", -B, B)

    -- Both anchors are on the same edge, so they fix the height but say
    -- nothing about the width; without SetWidth the texture falls back to its
    -- natural 128px and smears a stretched border across the panel.
    local right = keep(Slice(target, quads.topRight, R - B, R, CLEAN_RIGHT_Y1, CLEAN_RIGHT_Y2))
    right:SetWidth(B)
    right:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, -B)
    right:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, B)

    local topCorner = keep(Slice(target, quads.topRight, R - B, R, ART_TOP_PADDING, ART_TOP_PADDING + B))
    topCorner:SetSize(B, B)
    topCorner:SetPoint("TOPRIGHT")

    -- The real bottom-right corner sits next to the tab hardware, so the top
    -- corner is mirrored down instead.
    local bottomCorner = keep(Slice(target, quads.topRight, R - B, R, ART_TOP_PADDING, ART_TOP_PADDING + B, true))
    bottomCorner:SetSize(B, B)
    bottomCorner:SetPoint("BOTTOMRIGHT")

    -- The character frame's header band - the strip carrying the level and
    -- class - measured off a screenshot at RGB 58,53,49.
    --
    -- The input is lower than that fraction: feeding 0.227 came back as 71 on
    -- screen, so these are scaled to land on the header's rendered value
    -- rather than its nominal one.
    local fill = keep(target:CreateTexture(nil, "BACKGROUND"))
    fill:SetPoint("TOPLEFT", 0, -B)
    fill:SetPoint("BOTTOMRIGHT", -B, B)
    fill:SetColorTexture(0.178, 0.163, 0.151, 1)

    return true
end

-- Right and top of the frame you can actually see. Preferred reference is the
-- close button, which Blizzard pins to the artwork's top-right corner; the
-- slot-column derivation is the fallback for a frame without one.
local function VisibleCorner()
    -- Only the horizontal comes from the close button. The artwork *is* flush
    -- with CharacterFrame's top - measuring the close button for the top
    -- pushed the panel a dozen pixels above the character frame, and the
    -- resulting height stopped matching the 424 the artwork actually is.
    local close = _G.CharacterFrameCloseButton
    if close and close:GetRight() then
        return close:GetRight() + CLOSE_TO_EDGE, CharacterFrame:GetTop() - ART_TOP_PADDING
    end
    local left, right = ColumnEdgeSlots()
    local inset = (left and right)
        and Panel.ComputeArtInset(CharacterFrame:GetLeft(), CharacterFrame:GetRight(),
                left:GetLeft(), right:GetRight())
        or DEFAULT_ART_INSET
    return CharacterFrame:GetRight() + inset, CharacterFrame:GetTop() - ART_TOP_PADDING
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

    local nudge = ns.Config:Get("dockNudge") or 0

    -- Now that the character frame is modern chrome, its border is a nine-slice
    -- whose bounds ARE the frame you can see - which is the thing every
    -- derivation up to here was trying to reconstruct by measuring around it.
    -- Anchor to it directly and the panel matches on all three edges at once.
    -- The visible corner comes from the close button, which Blizzard pins to
    -- the artwork's top-right. Deriving it from the slot columns doesn't work:
    -- they aren't symmetric within the artwork (left margin 21, right nearer
    -- 9), so mirroring one onto the other overshoots by about ten pixels.
    local right, top = VisibleCorner()
    local x = (right - CharacterFrame:GetLeft()) + nudge

    local tab1 = _G.CharacterFrameTab1
    local bottom = Panel.ComputeArtBottom(CharacterFrame:GetBottom(), tab1 and tab1:GetTop())

    -- The panel's bounds are the artwork's bounds: left edge on the character
    -- frame's right edge, top flush with it, bottom on the artwork's bottom.
    -- The borrowed chrome brings its own transparent padding, exactly as the
    -- character frame's does, so nothing here is inflated to compensate.
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", x, top - CharacterFrame:GetTop())
    panel:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", x, bottom)

    -- Slide the borrowed artwork so its right border lands on the panel's
    -- right edge; the rest runs off to the left, behind the character frame.
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

    local visible = CharacterFrame.NineSlice
    if visible and visible:GetRight() then
        ns:Print("nine-slice (the frame you see): right %.1f  top %.1f  bottom %.1f |cff80ff80(in use)|r",
            visible:GetRight(), visible:GetTop(), visible:GetBottom())
    else
        local close = _G.CharacterFrameCloseButton
        ns:Print("|cffff8080no nine-slice|r - using the close button: right %.1f  top %.1f",
            close and close:GetRight() or -1, close and close:GetTop() or -1)
        local cornerX, cornerY = VisibleCorner()
        ns:Print("visible corner: right %.1f  top %.1f", cornerX, cornerY)
    end
    if left and right then
        ns:Print("slot columns: left edge %.1f  right edge %.1f", left:GetLeft(), right:GetRight())
        ns:Print("derived artwork inset: %.1f (fallback %d)", ArtInset() or 0, DEFAULT_ART_INSET)
    else
        ns:Print("could not measure the slot columns")
    end
    if PaperDollFrame then
        local cornerX = (VisibleCorner())
        ns:Print("paperdoll: left %.1f  top %.1f   artwork origin x %.1f",
            PaperDollFrame:GetLeft() or -1, PaperDollFrame:GetTop() or -1,
            PANEL_WIDTH - (cornerX - (PaperDollFrame:GetLeft() or 0)))
    end
    local tab1 = _G.CharacterFrameTab1
    ns:Print("frame bottom %.1f  tab top %.1f  derived artwork bottom offset %.1f",
        CharacterFrame:GetBottom() or -1, tab1 and tab1:GetTop() or -1,
        Panel.ComputeArtBottom(CharacterFrame:GetBottom(), tab1 and tab1:GetTop()))
    ns:Print("panel: left %.1f  height %.1f   nudge: %d",
        panel:GetLeft() or -1, panel:GetHeight() or -1, ns.Config:Get("dockNudge") or 0)
    ns:Print("use |cffffff00/hg dock <pixels>|r to shift it; negative moves it left")
end

-- Dumps the character frame's own artwork so the panel can be built from the
-- same pieces instead of from a look-alike chosen by eye.
function Panel:ReportArtwork()
    for _, frame in ipairs({ CharacterFrame, PaperDollFrame }) do
        if frame then
            ns:Print("|cffffd200%s|r regions:", frame:GetName() or "?")
            local shown = 0
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.GetTexture and shown < 14 then
                    local atlas = region.GetAtlas and region:GetAtlas()
                    local texture = region:GetTexture()
                    if atlas or texture then
                        shown = shown + 1
                        local point, _, relPoint, ox, oy = region:GetPoint(1)
                        ns:Print("  %s  %.0fx%.0f  %s->%s %.0f,%.0f",
                            tostring(atlas or texture),
                            region:GetWidth() or 0, region:GetHeight() or 0,
                            tostring(point), tostring(relPoint), ox or 0, oy or 0)
                    end
                end
            end
            if shown == 0 then ns:Print("  (none)") end
        end
    end
end

-- Whether the sliced border actually made it onto the screen, and where. The
-- pieces have been silently absent more than once, and "no border visible" and
-- "border drawn somewhere unhelpful" look identical from a screenshot.
function Panel:ReportChrome()
    if not panel.chrome then
        ns:Print("|cffff8080no sliced chrome|r - the generic fallback is in use")
        return
    end
    ns:Print("panel: left %.1f right %.1f top %.1f bottom %.1f",
        panel:GetLeft() or -1, panel:GetRight() or -1,
        panel:GetTop() or -1, panel:GetBottom() or -1)
    for index, texture in ipairs(panel.chrome) do
        local l, r, t, b = texture:GetLeft(), texture:GetRight(), texture:GetTop(), texture:GetBottom()
        ns:Print("  %d: %s  %s  l%.0f r%.0f t%.0f b%.0f",
            index, texture:IsShown() and "shown" or "|cffff8080hidden|r",
            tostring(texture:GetTexture()), l or -1, r or -1, t or -1, b or -1)
    end
end

function Panel:SetBorderWidth(pixels)
    ns.Config:Set("artBorder", pixels ~= ART_BORDER and pixels or nil)
    BuildChrome(panel)
    ns:Print("border width set to %d (default %d)", pixels, ART_BORDER)
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
    -- Behind the character frame, not in front. The panel's left edge is tucked
    -- under the character frame's right border, and letting that border draw
    -- over it makes the seam between the two the character frame's own artwork
    -- - which matches by definition, instead of a second border in a slightly
    -- different style butted up against the first.
    panel:SetFrameLevel(math.max(0, CharacterFrame:GetFrameLevel() - 1))
    panel:EnableMouse(true)
    panel:Hide()

    BuildChrome(panel)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", CONTENT_LEFT + 2, -18)
    title:SetText("Gear Sets")

    equipButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    equipButton:SetSize(83, 22)
    equipButton:SetPoint("TOPLEFT", CONTENT_LEFT, -40)
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
    saveButton:SetSize(83, 22)
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
    scroll:SetPoint("TOPLEFT", CONTENT_LEFT, -68)
    scroll:SetPoint("BOTTOMRIGHT", CONTENT_RIGHT, 90)

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_WIDTH, 1)
    scroll:SetScrollChild(content)
    scrollBar = _G[scroll:GetName() .. "ScrollBar"]

    editButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    editButton:SetSize(ROW_WIDTH, 22)
    editButton:SetPoint("BOTTOMLEFT", CONTENT_LEFT, 62)
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
    newButton:SetSize(ROW_WIDTH, 22)
    newButton:SetPoint("BOTTOMLEFT", CONTENT_LEFT, 38)
    newButton:SetText("New set from worn gear")
    newButton:SetScript("OnClick", function() StaticPopup_Show("HELLOGEAR_NEW_SET") end)

    statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    statusText:SetPoint("BOTTOMLEFT", CONTENT_LEFT + 2, 20)
    statusText:SetPoint("BOTTOMRIGHT", CONTENT_RIGHT + 12, 20)
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

    local contentHeight = #names * ROW_HEIGHT
    content:SetHeight(math.max(contentHeight, 1))
    if scrollBar then
        scrollBar:SetShown(contentHeight > scroll:GetHeight() + 1)
    end

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
