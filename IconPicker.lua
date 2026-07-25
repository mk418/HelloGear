local ADDON_NAME, ns = ...

ns.IconPicker = {}
local IconPicker = ns.IconPicker
local Items = ns.Items

local COLUMNS, ROWS = 8, 7
local ICON_SIZE = 30
local ICON_PAD = 4
local CELL = ICON_SIZE + ICON_PAD
local GRID_TOP = 66

local frame, slider, header, search
local buttons = {}
local entries = {}      -- everything: { texture = , name = } with name possibly nil
local shown = {}        -- what the grid is currently showing
local offset = 0
local onPick, currentIcon, searchable

--------------------------------------------------------------------------
-- The icon list
--
-- The set's own items come first: nine times out of ten the icon you want is
-- one of the things the set puts on, and hunting for it in a grid of two
-- thousand is nobody's idea of a good time. The client's macro icon list
-- follows.
--
-- Each entry carries a name to search on where one can be had. Icons arrive
-- either as texture paths, whose last segment is the name, or as bare file
-- IDs, which carry no name at all - so whether searching is possible depends
-- on what this client hands back. The set's own icons always get one: the
-- item's own name, which is more useful than the texture's anyway.
--------------------------------------------------------------------------

local function TextureName(texture)
    if type(texture) ~= "string" then return nil end
    local name = texture:match("([^\\/]+)$")
    return name and name:lower() or nil
end

local function AppendMacroIcons(list, seen)
    local function add(icon)
        if icon and not seen[icon] then
            seen[icon] = true
            list[#list + 1] = { texture = icon, name = TextureName(icon) }
        end
    end

    if type(_G.GetMacroIcons) == "function" then
        local fetched = {}
        -- Only treat this as the answer if it actually returned something; a
        -- call that succeeds and fills nothing shouldn't stop us trying the
        -- older API.
        if pcall(_G.GetMacroIcons, fetched) and #fetched > 0 then
            for _, icon in ipairs(fetched) do add(icon) end
            return
        end
    end

    if type(_G.GetNumMacroIcons) == "function" and type(_G.GetMacroIconInfo) == "function" then
        local ok, count = pcall(_G.GetNumMacroIcons)
        if not ok or not count then return end
        for index = 1, count do
            local fine, icon = pcall(_G.GetMacroIconInfo, index)
            if fine then add(icon) end
        end
    end
end

local function BuildEntries(set)
    local list, seen = {}, {}

    for _, def in ipairs(ns.SLOTS) do
        local gearID = set.equip[def.id]
        if gearID and gearID ~= ns.EMPTY then
            local itemName, texture = Items.GetInfo(gearID)
            if texture and not seen[texture] then
                seen[texture] = true
                list[#list + 1] = {
                    texture = texture,
                    name = itemName and itemName:lower() or TextureName(texture),
                }
            end
        end
    end
    AppendMacroIcons(list, seen)

    local named = 0
    for _, entry in ipairs(list) do
        if entry.name then named = named + 1 end
    end
    return list, named
end

--------------------------------------------------------------------------

local function MaxOffset()
    return math.max(0, math.ceil(#shown / COLUMNS) - ROWS)
end

local function Render()
    for index, button in ipairs(buttons) do
        local entry = shown[offset * COLUMNS + index]
        if entry then
            button.icon:SetTexture(entry.texture)
            button.entry = entry
            button.selected:SetShown(entry.texture == currentIcon)
            button:Show()
        else
            button:Hide()
        end
    end
    slider:SetMinMaxValues(0, MaxOffset())
    slider:SetShown(MaxOffset() > 0)
    slider:SetValue(offset)
end

local function SetOffset(value)
    offset = math.max(0, math.min(MaxOffset(), math.floor(value + 0.5)))
    Render()
end

local function Filter(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    shown = {}
    if text == "" then
        for _, entry in ipairs(entries) do shown[#shown + 1] = entry end
    else
        for _, entry in ipairs(entries) do
            if entry.name and entry.name:find(text, 1, true) then
                shown[#shown + 1] = entry
            end
        end
    end
    offset = 0
    Render()
    return #shown
end

--------------------------------------------------------------------------

local function CreateButton(index)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    local col = (index - 1) % COLUMNS
    local row = math.floor((index - 1) / COLUMNS)
    button:SetPoint("TOPLEFT", 16 + col * CELL, -(GRID_TOP + row * CELL))

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

    button:SetScript("OnEnter", function(self)
        if not (self.entry and self.entry.name) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.entry.name, 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", function(self)
        if not self.entry then return end
        if onPick then onPick(self.entry.texture) end
        IconPicker:Close()
    end)

    buttons[index] = button
    return button
end

local function Build()
    frame = ns.CreatePanel("HelloGearIconPicker")
    frame:SetSize(16 * 2 + COLUMNS * CELL + 20, GRID_TOP + ROWS * CELL + 40)
    frame:SetClampedToScreen(true)
    -- Above the options popout it opens beside, which sits at 30.
    frame:SetFrameLevel(40)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) SetOffset(offset - delta) end)

    header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 18, -16)

    search = CreateFrame("EditBox", "HelloGearIconSearch", frame, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", 22, -36)
    search:SetSize(COLUMNS * CELL - 30, 20)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function(self)
        local count = Filter(self:GetText())
        if self:GetText() ~= "" and count == 0 then
            header:SetText("|cffffd200Choose an icon|r  |cffff8080nothing matches|r")
        else
            IconPicker:UpdateHeader()
        end
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    for index = 1, COLUMNS * ROWS do CreateButton(index) end

    slider = CreateFrame("Slider", nil, frame)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(12)
    slider:SetPoint("TOPRIGHT", -14, -(GRID_TOP + 2))
    slider:SetPoint("BOTTOMRIGHT", -14, 46)
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    slider:GetThumbTexture():SetSize(12, 24)
    slider:SetValueStep(1)
    slider:SetScript("OnValueChanged", function(_, value)
        if math.floor(value + 0.5) ~= offset then SetOffset(value) end
    end)

    local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22)
    cancel:SetPoint("BOTTOMRIGHT", -16, 14)
    cancel:SetText(CANCEL or "Cancel")
    cancel:SetScript("OnClick", function() IconPicker:Close() end)

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

function IconPicker:UpdateHeader()
    header:SetText(("|cffffd200Choose an icon|r  |cff808080%d shown of %d|r")
        :format(#shown, #entries))
end

function IconPicker:Open(set, anchor, callback)
    if not frame then Build() end

    self.set = set
    onPick = callback
    currentIcon = set.icon

    local named
    entries, named = BuildEntries(set)
    searchable = named > 0

    search:SetText("")
    search:SetEnabled(searchable)
    if searchable then
        search:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Search icon names", 1, 1, 1)
            GameTooltip:AddLine(("%d of %d icons have a name to search"):format(named, #entries),
                0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
    else
        -- The client handed back bare file IDs, which carry no name. Nothing
        -- to search, so say so rather than leaving a box that does nothing.
        search:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("This client's icons have no names to search", 1, 0.5, 0.5, true)
            GameTooltip:Show()
        end)
    end
    search:SetScript("OnLeave", GameTooltip_Hide)

    Filter("")
    self:UpdateHeader()

    -- Open on the row holding the set's current icon, so the picker starts
    -- where the answer probably is rather than at the top of two thousand.
    for index, entry in ipairs(shown) do
        if entry.texture == currentIcon then
            SetOffset(math.floor((index - 1) / COLUMNS))
            break
        end
    end

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
