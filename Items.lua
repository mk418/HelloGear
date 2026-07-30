local ADDON_NAME, ns = ...

ns.Items = {}
local Items = ns.Items

local API = ns.API
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerItemLink = C_Container.GetContainerItemLink
local GetContainerItemInfo = C_Container.GetContainerItemInfo

--------------------------------------------------------------------------
-- Slots
--
-- Inventory slot IDs are fixed by the client. Slot 0 is the ammo slot,
-- which still exists in Era; we resolve every slot through
-- GetInventorySlotInfo anyway so a slot the client no longer knows about
-- simply drops out of the table instead of erroring later.
--------------------------------------------------------------------------

local SLOT_DEFS = {
    { id = 0,  key = "AmmoSlot",          label = "Ammo" },
    { id = 1,  key = "HeadSlot",          label = "Head" },
    { id = 2,  key = "NeckSlot",          label = "Neck" },
    { id = 3,  key = "ShoulderSlot",      label = "Shoulder" },
    { id = 4,  key = "ShirtSlot",         label = "Shirt" },
    { id = 5,  key = "ChestSlot",         label = "Chest" },
    { id = 6,  key = "WaistSlot",         label = "Waist" },
    { id = 7,  key = "LegsSlot",          label = "Legs" },
    { id = 8,  key = "FeetSlot",          label = "Feet" },
    { id = 9,  key = "WristSlot",         label = "Wrist" },
    { id = 10, key = "HandsSlot",         label = "Hands" },
    { id = 11, key = "Finger0Slot",       label = "Finger 1" },
    { id = 12, key = "Finger1Slot",       label = "Finger 2" },
    { id = 13, key = "Trinket0Slot",      label = "Trinket 1" },
    { id = 14, key = "Trinket1Slot",      label = "Trinket 2" },
    { id = 15, key = "BackSlot",          label = "Back" },
    { id = 16, key = "MainHandSlot",      label = "Main hand" },
    { id = 17, key = "SecondaryHandSlot", label = "Off hand" },
    { id = 18, key = "RangedSlot",        label = "Ranged" },
    { id = 19, key = "TabardSlot",        label = "Tabard" },
}

ns.SLOTS = {}       -- ordered array of {id, key, label, emptyIcon}
ns.SLOT_BY_ID = {}  -- id -> entry

for _, def in ipairs(SLOT_DEFS) do
    local ok, id, emptyIcon = pcall(GetInventorySlotInfo, def.key)
    if ok and id then
        def.id = id
        def.emptyIcon = emptyIcon
        table.insert(ns.SLOTS, def)
        ns.SLOT_BY_ID[id] = def
    end
end

-- Which inventory slots an item's INVTYPE can go into. Used by the paperdoll
-- slot menus to decide what to offer, and by the swap engine to spot
-- two-handers.
ns.INVTYPE_SLOTS = {
    INVTYPE_AMMO             = { 0 },
    INVTYPE_HEAD             = { 1 },
    INVTYPE_NECK             = { 2 },
    INVTYPE_SHOULDER         = { 3 },
    INVTYPE_BODY             = { 4 },
    INVTYPE_CHEST            = { 5 },
    INVTYPE_ROBE             = { 5 },
    INVTYPE_WAIST            = { 6 },
    INVTYPE_LEGS             = { 7 },
    INVTYPE_FEET             = { 8 },
    INVTYPE_WRIST            = { 9 },
    INVTYPE_HAND             = { 10 },
    INVTYPE_FINGER           = { 11, 12 },
    INVTYPE_TRINKET          = { 13, 14 },
    INVTYPE_CLOAK            = { 15 },
    INVTYPE_WEAPON           = { 16, 17 },
    INVTYPE_2HWEAPON         = { 16 },
    INVTYPE_WEAPONMAINHAND   = { 16 },
    INVTYPE_WEAPONOFFHAND    = { 17 },
    INVTYPE_SHIELD           = { 17 },
    INVTYPE_HOLDABLE         = { 17 },
    INVTYPE_RANGED           = { 18 },
    INVTYPE_RANGEDRIGHT      = { 18 },
    INVTYPE_THROWN           = { 18 },
    INVTYPE_RELIC            = { 18 },
    INVTYPE_TABARD           = { 19 },
}

--------------------------------------------------------------------------
-- Gear IDs
--
-- A gear ID is "itemID:enchantID:suffixID:uniqueID". That is the subset of
-- the item string that actually identifies a specific piece of gear in Era:
-- there are no sockets, and the link's trailing level field changes every
-- time you ding (which is why ItemRack needed a routine to rewrite it).
--
-- suffixID distinguishes random-suffix drops - "Bracers of the Owl" and
-- "Bracers of the Eagle" share an itemID - so it is never ignored when
-- matching. uniqueID is a per-instance seed and is only used to break ties
-- between two otherwise identical items.
--------------------------------------------------------------------------

local function fields(str)
    local out, i = {}, 1
    for field in (str .. ":"):gmatch("([^:]*):") do
        out[i] = tonumber(field) or 0
        i = i + 1
    end
    return out
end

function Items.Make(itemID, enchant, suffix, unique)
    return string.format("%d:%d:%d:%d", itemID or 0, enchant or 0, suffix or 0, unique or 0)
end

-- Accepts an item link, an "item:..." string, a bare item ID, or an
-- ItemRack-style string ("22418:2583:::::::60::::::::::").
function Items.FromLink(link)
    if not link then return nil end
    if type(link) == "number" then return Items.Make(link, 0, 0, 0) end

    local payload = link:match("|Hitem:([%-%d:]+)")
        or link:match("^item:([%-%d:]+)")
        or link:match("^([%-%d][%-%d:]*)$")
    if not payload then return nil end

    local f = fields(payload)
    if not f[1] or f[1] == 0 then return nil end
    -- Fields 3-6 are gem sockets, 9 is the link level: both irrelevant here.
    return Items.Make(f[1], f[2], f[7], f[8])
end

function Items.Parse(gearID)
    if type(gearID) ~= "string" then return nil end
    local f = fields(gearID)
    return f[1], f[2], f[3], f[4]
end

function Items.BaseID(gearID)
    if gearID == ns.EMPTY or gearID == nil then return nil end
    return (Items.Parse(gearID))
end

-- Rebuilds a link the client will accept for GetItemInfo / tooltips.
function Items.ToItemString(gearID)
    local itemID, enchant, suffix, unique = Items.Parse(gearID)
    if not itemID then return nil end
    return string.format("item:%d:%d:0:0:0:0:%d:%d:%d", itemID, enchant, suffix, unique, UnitLevel("player") or 0)
end

-- The native /equipslot command is the one path the client permits for
-- weapon changes in combat. It accepts an item string, and does not need the
-- volatile player-level field that tooltip lookups do. Keeping this compact
-- matters because a WoW macro has room for only 255 characters.
function Items.ToEquipString(gearID)
    local itemID, enchant, suffix, unique = Items.Parse(gearID)
    if not itemID then return nil end
    return string.format("item:%d:%d:0:0:0:0:%d:%d", itemID, enchant, suffix, unique)
end

-- nil = different items. 3 = the same physical item. 2 = same item with the
-- same enchant. 1 = same item, different enchant.
function Items.MatchScore(wanted, have)
    if wanted == nil or have == nil then return nil end
    if wanted == ns.EMPTY or have == ns.EMPTY then return nil end
    if wanted == have then return 3 end

    local wID, wEnch, wSuf, wUniq = Items.Parse(wanted)
    local hID, hEnch, hSuf, hUniq = Items.Parse(have)
    if not wID or not hID then return nil end
    if wID ~= hID or wSuf ~= hSuf then return nil end
    if wEnch ~= hEnch then return 1 end
    if wUniq == hUniq then return 3 end
    return 2
end

-- Two items are interchangeable for a set's purposes when they share an item
-- ID and a suffix - the same rule MatchScore applies, minus the enchant, which
-- only ever breaks ties. Reducing to a key makes "do I own one of these?" a
-- table lookup instead of a scan, which matters when it's asked for every slot
-- of every set on each refresh.
function Items.AvailabilityKey(gearID)
    if gearID == nil or gearID == ns.EMPTY then return nil end
    local itemID, _, suffix = Items.Parse(gearID)
    if not itemID then return nil end
    return itemID .. ":" .. (suffix or 0)
end

function Items.GetInfo(gearID)
    if gearID == nil or gearID == ns.EMPTY then
        return "(empty)", "Interface\\PaperDoll\\UI-Backpack-EmptySlot", nil, 0
    end
    local itemString = Items.ToItemString(gearID)
    if not itemString then
        return nil, "Interface\\Icons\\INV_Misc_QuestionMark", nil, 0
    end
    local name, _, quality, _, _, _, _, _, equipLoc, texture = API.GetItemInfo(itemString)
    if not name then
        -- Not cached yet. GetItemInfoInstant never returns a name but always
        -- has the icon, which is enough to draw something sensible now; the
        -- caller redraws on GET_ITEM_INFO_RECEIVED.
        local _, _, _, instantEquipLoc, instantIcon = API.GetItemInfoInstant(Items.BaseID(gearID))
        return nil, instantIcon or "Interface\\Icons\\INV_Misc_QuestionMark", instantEquipLoc, 1
    end
    return name, texture, equipLoc, quality
end

function Items.GetLink(gearID)
    local itemString = Items.ToItemString(gearID)
    if not itemString then return nil end
    return (select(2, API.GetItemInfo(itemString)))
end

function Items.IsTwoHander(gearID)
    local _, _, equipLoc = Items.GetInfo(gearID)
    if equipLoc then return equipLoc == "INVTYPE_2HWEAPON" end
    local _, _, _, instantLoc = API.GetItemInfoInstant(Items.BaseID(gearID) or 0)
    return instantLoc == "INVTYPE_2HWEAPON"
end

--------------------------------------------------------------------------
-- Reading what is worn and what is carried
--------------------------------------------------------------------------

function Items.GetWorn(slot)
    local link = GetInventoryItemLink("player", slot)
    if link then return Items.FromLink(link) end
    -- The ammo slot has never returned a usable link in Classic; fall back to
    -- the item ID, which is all ammo needs (it carries no enchant or suffix).
    if slot == 0 then
        local id = GetInventoryItemID("player", 0)
        if id then return Items.Make(id, 0, 0, 0) end
    end
    return nil
end

-- Snapshot of every worn slot, keyed by slot ID.
function Items.GetWornSet()
    local worn = {}
    for _, def in ipairs(ns.SLOTS) do
        worn[def.id] = Items.GetWorn(def.id)
    end
    return worn
end

-- Every item sitting in a carried bag: array of {bag, slot, gearID, locked}.
function Items.ScanBags()
    local out = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local gearID = Items.FromLink(link)
                if gearID then
                    local info = GetContainerItemInfo(bag, slot)
                    out[#out + 1] = {
                        bag = bag,
                        slot = slot,
                        gearID = gearID,
                        locked = info and info.isLocked or false,
                    }
                end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------
-- The bank
--
-- Readable only while the bank window is open - the client simply doesn't
-- report its contents otherwise - so everything here is guarded by that and
-- the features built on it say so rather than quietly finding nothing.
--------------------------------------------------------------------------

local BANK_MAIN = -1

function Items.BankContainers()
    local out = { BANK_MAIN }
    for index = 1, (NUM_BANKBAGSLOTS or 6) do
        out[#out + 1] = NUM_BAG_SLOTS + index
    end
    return out
end

function Items.ScanBank()
    local out = {}
    for _, bag in ipairs(Items.BankContainers()) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local gearID = Items.FromLink(link)
                if gearID then
                    out[#out + 1] = { bag = bag, slot = slot, gearID = gearID }
                end
            end
        end
    end
    return out
end

function Items.FindFreeBankSlot(claimed)
    for _, bag in ipairs(Items.BankContainers()) do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        -- The main bank window has no family; purchased bank bags may be
        -- profession-only and can't take gear.
        if bag == BANK_MAIN or not family or family == 0 then
            for slot = 1, (GetContainerNumSlots(bag) or 0) do
                local key = bag .. ":" .. slot
                if not GetContainerItemLink(bag, slot) and not (claimed and claimed[key]) then
                    if claimed then claimed[key] = true end
                    return bag, slot
                end
            end
        end
    end
end

-- First free, usable bag slot. Profession bags can't hold gear, so anything
-- with a non-zero family is skipped.
function Items.FindFreeBagSlot(claimed)
    for bag = NUM_BAG_SLOTS, 0, -1 do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        if bag == 0 or not family or family == 0 then
            for slot = 1, (GetContainerNumSlots(bag) or 0) do
                local key = bag .. ":" .. slot
                if not GetContainerItemLink(bag, slot) and not (claimed and claimed[key]) then
                    if claimed then claimed[key] = true end
                    return bag, slot
                end
            end
        end
    end
end

-- Cooldown for an item at a known location: {bag=, slot=} for a bag, or
-- {invSlot=} for something worn. Read from the location rather than from an
-- item ID because 1.15.9 has no working item-ID cooldown call - the bare
-- GetItemCooldown global was removed and C_Item has no replacement, so
-- anything built on one silently resolves to nil and errors on first use.
-- Returns nothing for an item that is neither carried nor worn.
function Items.GetCooldown(source)
    if not source then return end
    if source.bag then
        return C_Container.GetContainerItemCooldown(source.bag, source.slot)
    elseif source.invSlot then
        return GetInventoryItemCooldown("player", source.invSlot)
    end
end

function Items.IsBagSlotLocked(bag, slot)
    local info = GetContainerItemInfo(bag, slot)
    return info and info.isLocked or false
end

-- True while any equipment or bag slot is mid-move. Kicking off a second
-- swap under those conditions is how items end up in the wrong slot.
function Items.AnythingLocked()
    for _, def in ipairs(ns.SLOTS) do
        if IsInventoryItemLocked(def.id) then return true end
    end
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            if Items.IsBagSlotLocked(bag, slot) then return true end
        end
    end
    return false
end

-- Can the player actually put this item on? Level requirement only - class
-- and weapon-skill restrictions would need the tooltip scanned, and getting
-- them wrong hides gear the player owns, which is worse than listing one
-- item they can't wear.
function Items.CanEquip(gearID)
    local itemString = Items.ToItemString(gearID)
    if not itemString then return true end
    local _, _, _, _, minLevel = API.GetItemInfo(itemString)
    if not minLevel then return true end
    return minLevel <= (UnitLevel("player") or 0)
end
