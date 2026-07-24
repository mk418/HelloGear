local ADDON_NAME, ns = ...

ns.Sets = {}
local Sets = ns.Sets
local Items = ns.Items

--------------------------------------------------------------------------
-- A set looks like:
--
--   {
--     name    = "Tank",
--     icon    = 133160,                     -- fileID or texture path
--     equip   = { [1] = "22418:2583:0:0",   -- gear ID: wear this
--                 [17] = ns.EMPTY,          -- leave this slot empty
--                 ... },                    -- absent slot: don't touch
--     restore = { [1] = "21329:2583:0:0" }, -- what the set displaced, for toggling back
--     restoreSet = "High Threat",           -- which set was current before
--     helm    = true/false/nil,             -- cosmetic toggles, nil = leave alone
--     cloak   = true/false/nil,
--     hidden  = true/nil,                   -- keep out of the quick menu
--   }
--
-- Slots absent from equip are deliberately untouched, which is what makes
-- partial sets ("just swap my gloves") work.
--------------------------------------------------------------------------

function Sets:Store()
    return ns.Config:GetCharTable("sets")
end

function Sets:Order()
    return ns.Config:GetCharTable("order")
end

function Sets:Init()
    -- Reconcile the display order with what's actually stored, in case a set
    -- was added or removed by something that didn't maintain the order list.
    local store, order = self:Store(), self:Order()
    local seen = {}
    for i = #order, 1, -1 do
        local name = order[i]
        if not store[name] or seen[name] then
            table.remove(order, i)
        else
            seen[name] = true
        end
    end
    local missing = {}
    for name in pairs(store) do
        if not seen[name] then missing[#missing + 1] = name end
    end
    table.sort(missing)
    for _, name in ipairs(missing) do order[#order + 1] = name end
end

function Sets:Get(name)
    if not name or name == "" then return nil end
    return self:Store()[name]
end

-- Case-insensitive lookup, so /hg equip tank finds "Tank".
function Sets:Resolve(name)
    if not name or name == "" then return nil end
    local store = self:Store()
    if store[name] then return name end
    local lower = name:lower()
    for stored in pairs(store) do
        if stored:lower() == lower then return stored end
    end
    return nil
end

function Sets:Names(includeHidden)
    local store, out = self:Store(), {}
    for _, name in ipairs(self:Order()) do
        local set = store[name]
        if set and (includeHidden or not set.hidden) then
            out[#out + 1] = name
        end
    end
    return out
end

function Sets:Count()
    local n = 0
    for _ in pairs(self:Store()) do n = n + 1 end
    return n
end

function Sets:Create(name, set)
    if not name or name == "" then return nil end
    local store = self:Store()
    local isNew = store[name] == nil
    set = set or {}
    set.name = name
    set.equip = set.equip or {}
    store[name] = set
    if isNew then
        table.insert(self:Order(), name)
    end
    return set
end

function Sets:Delete(name)
    name = self:Resolve(name)
    if not name then return false end
    self:Store()[name] = nil
    local order = self:Order()
    for i, stored in ipairs(order) do
        if stored == name then table.remove(order, i) break end
    end
    for index, bound in pairs(ns.Config:GetCharTable("bindings")) do
        if bound == name then ns.Config:GetCharTable("bindings")[index] = nil end
    end
    if HelloGearCharDB.currentSet == name then HelloGearCharDB.currentSet = nil end
    return true
end

function Sets:Rename(oldName, newName)
    oldName = self:Resolve(oldName)
    if not oldName or not newName or newName == "" then return false end
    if self:Store()[newName] then return false end
    local set = self:Store()[oldName]
    self:Store()[oldName] = nil
    set.name = newName
    self:Store()[newName] = set
    for i, stored in ipairs(self:Order()) do
        if stored == oldName then self:Order()[i] = newName break end
    end
    for index, bound in pairs(ns.Config:GetCharTable("bindings")) do
        if bound == oldName then ns.Config:GetCharTable("bindings")[index] = newName end
    end
    if HelloGearCharDB.currentSet == oldName then HelloGearCharDB.currentSet = newName end
    return true
end

-- Captures everything currently worn. Empty slots are left out rather than
-- recorded as ns.EMPTY: a set built from your gear shouldn't start stripping
-- your shirt off just because you weren't wearing one.
function Sets:SaveFromWorn(name, keepIcon)
    local existing = self:Get(self:Resolve(name) or "")
    local set = self:Create(self:Resolve(name) or name, existing)
    wipe(set.equip)
    for _, def in ipairs(ns.SLOTS) do
        local worn = Items.GetWorn(def.id)
        if worn then set.equip[def.id] = worn end
    end
    set.restore = nil
    set.restoreSet = nil
    if not keepIcon or not set.icon then
        set.icon = self:SuggestIcon(set)
    end
    return set
end

-- Picks a representative icon: main hand first, then chest, then whatever
-- the set has. Mirrors what ItemRack stored as set.icon.
function Sets:SuggestIcon(set)
    for _, slot in ipairs({ 16, 5, 1, 15, 18, 13 }) do
        local gearID = set.equip[slot]
        if gearID and gearID ~= ns.EMPTY then
            local _, texture = Items.GetInfo(gearID)
            if texture then return texture end
        end
    end
    for _, gearID in pairs(set.equip) do
        if gearID ~= ns.EMPTY then
            local _, texture = Items.GetInfo(gearID)
            if texture then return texture end
        end
    end
    return "Interface\\Icons\\INV_Misc_Bag_10"
end

function Sets:GetIcon(set)
    return (set and set.icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- exact: every slot must hold the identical item, enchant included.
-- Otherwise a same-item-different-enchant match counts as equipped, which is
-- what you want when a set was saved before you re-enchanted something.
function Sets:IsEquipped(name, exact)
    local set = self:Get(self:Resolve(name) or "")
    if not set then return false end
    local any = false
    for slot, wanted in pairs(set.equip) do
        any = true
        local worn = Items.GetWorn(slot)
        if wanted == ns.EMPTY then
            if worn then return false end
        else
            local score = Items.MatchScore(wanted, worn)
            if not score then return false end
            if exact and score < 3 then return false end
        end
    end
    return any
end

--------------------------------------------------------------------------
-- Slot states
--
-- What a set does with one slot, and the cycle the paperdoll editor walks
-- through. Kept here rather than in the UI so it can be tested without a
-- character sheet to click on.
--------------------------------------------------------------------------

-- "worn"    managed, and the exact item is on right now
-- "stored"  managed, but the item isn't currently worn
-- "empty"   the set clears this slot
-- "ignored" the set leaves this slot alone
function Sets:SlotState(set, slotID)
    local gearID = set.equip[slotID]
    if gearID == nil then return "ignored" end
    if gearID == ns.EMPTY then return "empty" end
    if Items.MatchScore(gearID, Items.GetWorn(slotID)) == 3 then return "worn" end
    return "stored"
end

-- Assign a specific item to a slot. gearID may be a gear ID, ns.EMPTY to have
-- the set clear the slot, or nil to drop the slot from the set entirely.
function Sets:SetSlot(set, slotID, gearID)
    set.equip[slotID] = gearID
    return self:SlotState(set, slotID)
end

-- In or out of the set. Bringing a slot in adopts whatever is worn; if the
-- slot is bare there's nothing to adopt, so it comes in as "clear this slot",
-- which is the only other thing it could usefully mean.
function Sets:ToggleSlot(set, slotID)
    if set.equip[slotID] == nil then
        set.equip[slotID] = Items.GetWorn(slotID) or ns.EMPTY
    else
        set.equip[slotID] = nil
    end
    return self:SlotState(set, slotID)
end

-- Slots the set would change if equipped right now.
function Sets:PendingSlots(name)
    local set = self:Get(self:Resolve(name) or "")
    if not set then return {} end
    local out = {}
    for slot, wanted in pairs(set.equip) do
        local worn = Items.GetWorn(slot)
        if wanted == ns.EMPTY then
            if worn then out[slot] = ns.EMPTY end
        elseif Items.MatchScore(wanted, worn) ~= 3 then
            out[slot] = wanted
        end
    end
    return out
end
