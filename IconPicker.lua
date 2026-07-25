local ADDON_NAME, ns = ...

ns.IconPicker = {}
local IconPicker = ns.IconPicker
local Items = ns.Items

local COLUMNS, ROWS = 8, 7
local ICON_SIZE = 30
local ICON_PAD = 4
local CELL = ICON_SIZE + ICON_PAD

local frame, slider, header
local buttons = {}
local icons = {}
local offset = 0
local onPick, currentIcon

--------------------------------------------------------------------------
-- The icon list
--
-- The set's own items come first: nine times out of ten the icon you want is
-- one of the things the set puts on, and hunting for it in a grid of two
-- thousand is nobody's idea of a good time. The client's macro icon list
-- follows.
--------------------------------------------------------------------------

-- Which call exists depends on the client: modern fills a table you pass in,
-- older ones hand back one icon at a time. Neither is guaranteed, and the
-- picker is still useful with just the set's own icons, so a miss isn't fatal.
local function AppendMacroIcons(list, seen)
    if type(_G.GetMacroIcons) == "function" then
        local fetched = {}
        -- Only treat this as the answer if it actually returned something;
        -- a call that succeeds and fills nothing shouldn't stop us trying the
        -- older API.
        if pcall(_G.GetMacroIcons, fetched) and #fetched > 0 then
            for _, icon in ipairs(fetched) do
                if icon and not seen[icon] then
                    seen[icon] = true
                    list[#list + 1] = icon
                end
            end
            return
        end
    end

    if type(_G.GetNumMacroIcons) == "function" and type(_G.GetMacroIconInfo) == "function" then
        local ok, count = pcall(_G.GetNumMacroIcons)
        if not ok or not count then return end
        for index = 1, count do
            local _, icon = pcall(_G.GetMacroIconInfo, index)
            if icon and not seen[icon] then
                seen[icon] = true
                list[#list + 1] = icon
            end
        end
    end
end

local function BuildIconList(set)
    local list, seen = {}, {}

    for _, def in ipairs(ns.SLOTS) do
        local gearID = set.equip[def.id]
        if gearID and gearID ~= ns.EMPTY then
            local _, texture = Items.GetInfo(gearID)
            if texture and not seen[texture] then
                seen[texture] = true
                list[#list + 1] = texture
            end
        end
    end
    local setIcons = #list

    AppendMacroIcons(list, seen)
    return list, setIcons
end

--------------------------------------------------------------------------

local function MaxOffset()
    local rows = math.ceil(#icons / COLUMNS)
    return math.max(0, rows - ROWS)
end

local function Render()
    for index, button in ipairs(buttons) do
        local iconIndex = offset * COLUMNS + index
        local texture = icons[iconIndex]
        if texture then
            button.icon:SetTexture(texture)
            button.texture = texture
            button.selected:SetShown(texture == currentIcon)
            button:Show()
        else
            button:Hide()
        end
    end
    if slider then slider:SetValue(offset) end
end

local function SetOffset(value)
    offset = math.max(0, math.min(MaxOffset(), math.floor(value + 0.5)))
    Render()
end

local function CreateButton(index)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    local col = (index - 1) % COLUMNS
    local row = math.floor((index - 1) / COLUMNS)
    button:SetPoint("TOPLEFT", 16 + col * CELL, -(36 + row * CELL))

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    button.selected = button:CreateTexture(nil, "OVERLAY")
    button.selected:SetPoint("TOPLEFT", -2, 2)
    button.selected:SetPoint("BOTTOMRIGHT", 2, -2)
    button.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    button.selected:SetBlendMode("ADD")
    button.selected:Hide()

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.25)

    button:SetScript("OnClick", function(self)
        if not self.texture then return end
        if onPick then onPick(self.texture) end
        IconPicker:Close()
    end)

    buttons[index] = button
    return button
end

local function Build()
    frame = ns.CreatePanel("HelloGearIconPicker")
    frame:SetSize(16 * 2 + COLUMNS * CELL + 20, 36 + ROWS * CELL + 40)
    frame:SetClampedToScreen(true)
    -- Above the options popout it opens from, which sits at 30.
    frame:SetFrameLevel(40)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        SetOffset(offset - delta)
    end)

    header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 18, -16)

    for index = 1, COLUMNS * ROWS do CreateButton(index) end

    slider = CreateFrame("Slider", nil, frame)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(12)
    slider:SetPoint("TOPRIGHT", -14, -38)
    slider:SetPoint("BOTTOMRIGHT", -14, 46)
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    slider:GetThumbTexture():SetSize(12, 24)
    slider:SetScript("OnValueChanged", function(_, value)
        if math.floor(value + 0.5) ~= offset then SetOffset(value) end
    end)

    local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22)
    cancel:SetPoint("BOTTOMRIGHT", -16, 14)
    cancel:SetText(CANCEL or "Cancel")
    cancel:SetScript("OnClick", function() IconPicker:Close() end)

    local suggest = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    suggest:SetSize(130, 22)
    suggest:SetPoint("BOTTOMLEFT", 16, 14)
    suggest:SetText("Use a set item")
    suggest:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Pick an icon from the set's own gear, as a new set does", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    suggest:SetScript("OnLeave", GameTooltip_Hide)
    suggest:SetScript("OnClick", function()
        if onPick and IconPicker.set then onPick(ns.Sets:SuggestIcon(IconPicker.set)) end
        IconPicker:Close()
    end)

    -- Same click-away dismissal the other popups use.
    frame:SetScript("OnShow", function()
        if not IconPicker.closer then
            IconPicker.closer = CreateFrame("Frame", nil, UIParent)
            IconPicker.closer:SetAllPoints()
            IconPicker.closer:SetFrameStrata("DIALOG")
            IconPicker.closer:SetFrameLevel(1)
            IconPicker.closer:EnableMouse(true)
            IconPicker.closer:SetScript("OnMouseDown", function() IconPicker:Close() end)
        end
        IconPicker.closer:Show()
    end)
    frame:SetScript("OnHide", function()
        if IconPicker.closer then IconPicker.closer:Hide() end
        onPick, IconPicker.set = nil, nil
    end)
end

function IconPicker:Open(set, anchor, callback)
    if not frame then Build() end

    self.set = set
    onPick = callback
    currentIcon = set.icon

    local setIcons
    icons, setIcons = BuildIconList(set)
    header:SetText(("|cffffd200Choose an icon|r  |cff808080%d from this set, %d in all|r")
        :format(setIcons, #icons))

    slider:SetMinMaxValues(0, MaxOffset())
    slider:SetValueStep(1)
    slider:SetShown(MaxOffset() > 0)

    -- Open on the row holding the set's current icon, so the picker starts
    -- where the answer probably is rather than at the top of two thousand.
    offset = 0
    for index, texture in ipairs(icons) do
        if texture == currentIcon then
            offset = math.min(MaxOffset(), math.floor((index - 1) / COLUMNS))
            break
        end
    end
    Render()

    frame:ClearAllPoints()
    if anchor then
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
end

function IconPicker:Close()
    if frame then frame:Hide() end
end

function IconPicker:IsShown()
    return frame and frame:IsShown()
end
