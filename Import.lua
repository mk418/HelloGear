local ADDON_NAME, ns = ...

ns.Import = {}
local Import = ns.Import
local Items = ns.Items
local Sets = ns.Sets

--------------------------------------------------------------------------
-- ItemRack import
--
-- ItemRack keeps its sets in ItemRackUser, a per-character saved variable.
-- That global only exists while ItemRack itself is installed and enabled, and
-- the whole point of this addon is that you're about to turn ItemRack off. So
-- the first time we ever see it, we take our own copy - after that the import
-- keeps working with ItemRack deleted from disk.
--
-- We only ever read ItemRackUser. Writing to another addon's saved variables
-- is how you lose someone's data.
--------------------------------------------------------------------------

local function CopySets(source)
    if type(source) ~= "table" or type(source.Sets) ~= "table" then return nil end

    local copy = { Sets = {}, Hidden = {}, CurrentSet = source.CurrentSet }
    for name, set in pairs(source.Sets) do
        if type(set) == "table" and type(set.equip) == "table" then
            local equip = {}
            for slot, value in pairs(set.equip) do
                if type(slot) == "number" then equip[slot] = value end
            end
            copy.Sets[name] = {
                equip = equip,
                icon = set.icon,
                ShowHelm = set.ShowHelm,
                ShowCloak = set.ShowCloak,
            }
        end
    end
    if type(source.Hidden) == "table" then
        for _, name in ipairs(source.Hidden) do copy.Hidden[name] = true end
    end
    return copy
end

-- The live ItemRack data if it's loaded, otherwise our snapshot of it.
function Import:Source()
    if type(_G.ItemRackUser) == "table" and type(_G.ItemRackUser.Sets) == "table" then
        return _G.ItemRackUser, true
    end
    local backup = HelloGearCharDB and HelloGearCharDB.itemRackBackup
    if type(backup) == "table" and type(backup.Sets) == "table" then
        return backup, false
    end
    return nil
end

function Import:Available()
    local source = self:Source()
    if not source then return 0 end
    local n = 0
    for name in pairs(source.Sets) do
        -- ItemRack prefixes its internal scratch sets with a tilde.
        if not name:match("^~") then n = n + 1 end
    end
    return n
end

local function ConvertSet(name, irSet, hidden)
    local equip, slots = {}, 0
    for slot, value in pairs(irSet.equip) do
        if type(slot) == "number" and ns.SLOT_BY_ID[slot] then
            if value == 0 then
                equip[slot] = ns.EMPTY
                slots = slots + 1
            elseif type(value) == "string" and value ~= "" then
                local gearID = Items.FromLink(value)
                if gearID then
                    equip[slot] = gearID
                    slots = slots + 1
                end
            end
        end
    end
    if slots == 0 then return nil end

    local set = {
        name = name,
        equip = equip,
        icon = irSet.icon,
        hidden = hidden or nil,
    }
    -- ItemRack stores the cosmetic toggles as 1/0, and nil for "leave alone".
    if irSet.ShowHelm ~= nil then set.helm = irSet.ShowHelm == 1 end
    if irSet.ShowCloak ~= nil then set.cloak = irSet.ShowCloak == 1 end
    if not set.icon then set.icon = Sets:SuggestIcon(set) end
    return set
end

-- Hidden is an array of names in ItemRack's own table, but our snapshot
-- normalises it to a lookup. Handle both.
local function IsHidden(source, name)
    local hidden = source.Hidden
    if type(hidden) ~= "table" then return nil end
    if hidden[name] then return true end
    for _, hiddenName in ipairs(hidden) do
        if hiddenName == name then return true end
    end
    return nil
end

function Import:Run(overwrite)
    local source, live = self:Source()
    if not source then
        ns:Print("no ItemRack data found for this character")
        ns:Print("if ItemRack is still installed, enable it, log in once, then run /hg import")
        return 0, 0
    end

    local names = {}
    for name in pairs(source.Sets) do
        if not name:match("^~") then names[#names + 1] = name end
    end
    table.sort(names)

    local imported, skipped, empty = 0, 0, 0
    for _, name in ipairs(names) do
        local existing = Sets:Get(name)
        if existing and not overwrite then
            skipped = skipped + 1
        else
            local set = ConvertSet(name, source.Sets[name], IsHidden(source, name))
            if not set then
                empty = empty + 1
            else
                if existing then
                    -- Keep the slot the player assigned it in the menu order.
                    set.hidden = existing.hidden
                end
                Sets:Create(name, set)
                imported = imported + 1
            end
        end
    end

    if source.CurrentSet and Sets:Get(source.CurrentSet) and not HelloGearCharDB.currentSet then
        HelloGearCharDB.currentSet = source.CurrentSet
    end

    if imported > 0 then
        ns:Print("imported |cff80ff80%d|r set(s) from ItemRack%s", imported, live and "" or " (from saved snapshot)")
    end
    if skipped > 0 then
        ns:Print("skipped %d set(s) that already exist - use |cffffff00/hg import force|r to overwrite", skipped)
    end
    if empty > 0 then
        ns:Print("skipped %d empty set(s)", empty)
    end
    if imported == 0 and skipped == 0 and empty == 0 then
        ns:Print("nothing to import")
    end

    Sets:Init()
    ns.Menu:Refresh()
    ns.Panel:Refresh()
    return imported, skipped
end

StaticPopupDialogs["HELLOGEAR_IMPORT"] = {
    text = "HelloGear found %d ItemRack set(s) on this character.\n\nImport them?",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        ns.Import:Run()
        ns.Panel:Toggle()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Import:OnLogin()
    -- Refresh the snapshot whenever ItemRack is actually loaded, so it tracks
    -- any set edits made before the switchover.
    if type(_G.ItemRackUser) == "table" then
        local copy = CopySets(_G.ItemRackUser)
        if copy then HelloGearCharDB.itemRackBackup = copy end
    end

    if HelloGearCharDB.importOffered then return end
    if Sets:Count() > 0 then return end

    local available = self:Available()
    if available == 0 then return end

    HelloGearCharDB.importOffered = true
    StaticPopup_Show("HELLOGEAR_IMPORT", available)
end
