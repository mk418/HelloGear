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
local onPick, currentIcon, searchable, namedCount

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

-- Two ways to ask, and which one this client answers decides whether searching
-- is possible at all: the indexed call yields texture paths, whose last
-- segment is a name, while the table-filling one yields bare file IDs, which
-- carry nothing to match against. So the indexed call is tried first, and only
-- kept if it really does hand back strings.
-- Whatever this client will hand over, in whatever form it hands it over.
local function MacroIconList()
    if type(_G.GetNumMacroIcons) == "function" and type(_G.GetMacroIconInfo) == "function" then
        local ok, count = pcall(_G.GetNumMacroIcons)
        if ok and count and count > 0 then
            local fine, first = pcall(_G.GetMacroIconInfo, 1)
            if fine and type(first) == "string" then
                local out = {}
                for index = 1, count do
                    local got, icon = pcall(_G.GetMacroIconInfo, index)
                    if got and icon then out[#out + 1] = icon end
                end
                return out
            end
        end
    end

    if type(_G.GetMacroIcons) == "function" then
        local fetched = {}
        if pcall(_G.GetMacroIcons, fetched) and #fetched > 0 then return fetched end
    end
    return {}
end

local function AppendMacroIcons(list, seen)
    for _, icon in ipairs(MacroIconList()) do
        if not seen[icon] then
            seen[icon] = true
            -- ns.IconNames is the generated file-ID lookup, shipped only if
            -- this client needs it; without it a bare ID has no name.
            local name = TextureName(icon) or (ns.IconNames and ns.IconNames[icon])
            list[#list + 1] = { texture = icon, name = name }
        end
    end
end

-- Anything whose icon we can put a name to, we do. On a client that hands back
-- bare file IDs the macro list carries no names at all, so this is the whole
-- of what searching can cover: the set's own gear, everything else you're
-- carrying, and every spell you know. An icon shared with one of those becomes
-- searchable by that thing's name, which is what you'd type anyway.
local function AppendNamedIcons(list, seen, gearIDs)
    local function add(texture, name)
        if texture and not seen[texture] then
            seen[texture] = true
            list[#list + 1] = {
                texture = texture,
                name = (name and name ~= "" and name:lower()) or TextureName(texture),
            }
        end
    end

    for _, gearID in ipairs(gearIDs) do
        local itemName, texture = Items.GetInfo(gearID)
        add(texture, itemName)
    end

    -- Spellbook APIs differ across clients and neither is guaranteed; a miss
    -- here just means fewer names, so it fails quietly.
    local index = 1
    while index < 600 do
        local name, texture
        if _G.C_SpellBook and _G.C_SpellBook.GetSpellBookItemName then
            local bank = _G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player
            local ok, spellName = pcall(_G.C_SpellBook.GetSpellBookItemName, index, bank)
            if not ok then break end
            name = spellName
            local fine, spellTexture = pcall(_G.C_SpellBook.GetSpellBookItemTexture, index, bank)
            texture = fine and spellTexture or nil
        elseif type(_G.GetSpellBookItemName) == "function" then
            local ok, spellName = pcall(_G.GetSpellBookItemName, index, "spell")
            if not ok then break end
            name = spellName
            local fine, spellTexture = pcall(_G.GetSpellBookItemTexture, index, "spell")
            texture = fine and spellTexture or nil
        else
            break
        end
        if not name then break end
        add(texture, name)
        index = index + 1
    end
end

local function BuildEntries(set)
    local list, seen = {}, {}

    -- The set's own gear leads: nine times out of ten the icon you want is
    -- something the set puts on.
    local setGear = {}
    for _, def in ipairs(ns.SLOTS) do
        local gearID = set.equip[def.id]
        if gearID and gearID ~= ns.EMPTY then setGear[#setGear + 1] = gearID end
    end
    AppendNamedIcons(list, seen, setGear)

    local carried = {}
    for _, gearID in pairs(Items.GetWornSet()) do carried[#carried + 1] = gearID end
    for _, entry in ipairs(Items.ScanBags()) do carried[#carried + 1] = entry.gearID end
    if ns.Bank and ns.Bank:IsOpen() then
        for _, entry in ipairs(Items.ScanBank()) do carried[#carried + 1] = entry.gearID end
    end
    AppendNamedIcons(list, seen, carried)

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
    if search:GetText() ~= "" then
        header:SetText(("|cffffd200Choose an icon|r  |cff808080%d shown of %d|r")
            :format(#shown, #entries))
    elseif not searchable then
        header:SetText(("|cffffd200Choose an icon|r  |cffff8080%d, none searchable|r")
            :format(#entries))
    elseif namedCount < #entries then
        -- Being explicit beats a search box that quietly only covers part of
        -- the grid and reads as broken.
        header:SetText(("|cffffd200Choose an icon|r  |cff808080%d, %d searchable|r")
            :format(#entries, namedCount))
    else
        header:SetText(("|cffffd200Choose an icon|r  |cff808080%d icons|r"):format(#entries))
    end
end

function IconPicker:Open(set, anchor, callback)
    if not frame then Build() end

    self.set = set
    onPick = callback
    currentIcon = set.icon

    entries, namedCount = BuildEntries(set)
    searchable = namedCount > 0

    search:SetText("")
    if searchable then search:Enable() else search:Disable() end
    if searchable then
        search:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Search icon names", 1, 1, 1)
            GameTooltip:AddLine(("%d of %d icons have a name to search"):format(namedCount, #entries),
                0.7, 0.7, 0.7)
            if namedCount < #entries then
                GameTooltip:AddLine("This client reports its icons as bare file IDs, which carry " ..
                    "no name. Searchable ones are those shared with your gear or your spells.",
                    0.6, 0.6, 0.6, true)
            end
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
        -- Both frames' borders are drawn inside their bounds, so the gap you
        -- see is this offset plus both insets. Negative to bring them close.
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -(ns.CHROME_INSET * 2) + 4, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
end

-- Writes the raw icon list to saved variables so it can be turned into a name
-- table offline. Only needed once, and again if a patch adds icons.
function IconPicker:Dump()
    local list = MacroIconList()
    if #list == 0 then
        ns:Print("this client returned no icon list to dump")
        return
    end

    HelloGearDB.iconDump = list
    local sample = type(list[1]) == "string" and "paths" or "file IDs"
    ns:Print("dumped |cff80ff80%d|r icon %s", #list, sample)
    ns:Print("now |cffffff00/reload|r so it's written to disk")
end

function IconPicker:Close()
    if frame then frame:Hide() end
end

function IconPicker:IsShown()
    return frame and frame:IsShown()
end
