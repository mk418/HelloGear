local ADDON_NAME, ns = ...

ns.Equip = {}
local Equip = ns.Equip
local Items = ns.Items
local Sets = ns.Sets

local PickupContainerItem = C_Container.PickupContainerItem

local INVSLOT_AMMO_ID   = 0
local INVSLOT_RANGED_ID = 18
local INVSLOT_MAINHAND  = 16
local INVSLOT_OFFHAND   = 17

-- A swap is not instantaneous: the client locks both endpoints and completes
-- the move a moment later. So we run in passes - do everything we can, wait
-- for the locks to clear, recompute, go again - rather than assuming a single
-- sweep lands everything. These bound how long we keep trying.
local MAX_PASSES = 15
local TIMEOUT = 8

Equip.job = nil

--------------------------------------------------------------------------
-- Cursor-level moves
--
-- Cursor moves are used instead of EquipItemByName because they can target
-- one specific copy of an item. With two Ironfoe in your bags - one enchanted,
-- one not - name-based equipping picks whichever the client feels like.
--------------------------------------------------------------------------

local function CursorIsBusy()
    return CursorHasItem() or SpellIsTargeting() or (GetCursorInfo() ~= nil)
end

-- Every move ends with the cursor empty. If it doesn't, the second pickup was
-- rejected (wrong slot type, item can't be equipped) and the item is still
-- floating - drop it before it lands somewhere unintended.
local function FinishMove()
    if CursorHasItem() then
        ClearCursor()
        return false
    end
    return true
end

local function MoveBagToSlot(bag, bagSlot, invSlot)
    PickupContainerItem(bag, bagSlot)
    if not CursorHasItem() then return false end
    -- The ammo slot has never accepted a direct pickup in Classic; dropping
    -- ammo onto the ranged slot is how the client wants it done.
    PickupInventoryItem(invSlot == INVSLOT_AMMO_ID and INVSLOT_RANGED_ID or invSlot)
    return FinishMove()
end

local function MoveSlotToSlot(fromSlot, toSlot)
    PickupInventoryItem(fromSlot)
    if not CursorHasItem() then return false end
    PickupInventoryItem(toSlot)
    return FinishMove()
end

local function MoveSlotToBag(invSlot, bag, bagSlot)
    PickupInventoryItem(invSlot)
    if not CursorHasItem() then return false end
    PickupContainerItem(bag, bagSlot)
    return FinishMove()
end

--------------------------------------------------------------------------
-- Planning
--------------------------------------------------------------------------

-- Slots still needing work, given what is worn right now.
local function BuildPlan(equipTable)
    local plan, count = {}, 0
    for slot, wanted in pairs(equipTable) do
        local worn = Items.GetWorn(slot)
        if wanted == ns.EMPTY then
            if worn then plan[slot] = ns.EMPTY; count = count + 1 end
        elseif Items.MatchScore(wanted, worn) ~= 3 then
            plan[slot] = wanted
            count = count + 1
        end
    end
    return plan, count
end

-- Locate the best available copy of `wanted`, skipping anything already
-- spoken for. Returns a location table, or nil if the player doesn't have it.
local function FindBest(wanted, targetSlot, bags, worn, claimedBag, claimedInv)
    local best, bestScore

    for _, entry in ipairs(bags) do
        local key = entry.bag .. ":" .. entry.slot
        if not claimedBag[key] then
            local score = Items.MatchScore(wanted, entry.gearID)
            if score and (not bestScore or score > bestScore) then
                best = { bag = entry.bag, slot = entry.slot, key = key }
                bestScore = score
            end
        end
    end

    -- Only consider pulling gear off another slot if the bags can't do it, or
    -- if the worn copy is a strictly better match. Undressing one slot to
    -- dress another is a last resort.
    for slot, gearID in pairs(worn) do
        if slot ~= targetSlot and not claimedInv[slot] then
            local score = Items.MatchScore(wanted, gearID)
            if score and (not bestScore or score > bestScore) then
                best = { inv = slot }
                bestScore = score
            end
        end
    end

    return best, bestScore
end

--------------------------------------------------------------------------
-- One pass
--------------------------------------------------------------------------

-- Returns how many slots still need work. Gear the player doesn't own is
-- recorded on the job and dropped from the plan so we stop chasing it.
local function RunPass(job)
    local worn = Items.GetWornSet()
    local bags = Items.ScanBags()
    local claimedBag, claimedInv, freeClaimed = {}, {}, {}

    -- wornScore is how good a match the slot already holds. A set saved before
    -- you re-enchanted a weapon stores the old enchant, and the only copy you
    -- own is the one you're wearing - so "not an exact match" is not on its own
    -- a reason to go looking. Only a strictly better candidate is.
    local plan, wornScore, remaining = {}, {}, 0
    for slot, wanted in pairs(job.equip) do
        if wanted == ns.EMPTY then
            if worn[slot] then
                plan[slot] = ns.EMPTY
                remaining = remaining + 1
            end
        else
            local score = Items.MatchScore(wanted, worn[slot])
            if score ~= 3 then
                plan[slot] = wanted
                wornScore[slot] = score or 0
                remaining = remaining + 1
            end
        end
    end
    if remaining == 0 then return 0 end

    -- Anything the set already has right claims its spot, so a second slot
    -- wanting the same item can't yank it back out.
    for slot, wanted in pairs(job.equip) do
        if not plan[slot] and wanted ~= ns.EMPTY and worn[slot] then
            claimedInv[slot] = true
        end
    end

    -- A two-hander needs the off hand free. If the set doesn't already say
    -- what goes there, clearing it is on us.
    local mainWanted = plan[INVSLOT_MAINHAND]
    if mainWanted and mainWanted ~= ns.EMPTY and worn[INVSLOT_OFFHAND]
        and job.equip[INVSLOT_OFFHAND] == nil and Items.IsTwoHander(mainWanted) then
        plan[INVSLOT_OFFHAND] = ns.EMPTY
        remaining = remaining + 1
    end

    -- Slots being emptied go first so the room they free is available to the
    -- slots being filled; among the rest, ascending order puts the main hand
    -- before the off hand, which is what lets a one-hander displace a
    -- two-hander before the off hand is filled.
    local slots = {}
    for slot in pairs(plan) do slots[#slots + 1] = slot end
    table.sort(slots, function(a, b)
        local aEmpty, bEmpty = plan[a] == ns.EMPTY, plan[b] == ns.EMPTY
        if aEmpty ~= bEmpty then return aEmpty end
        return a < b
    end)

    for _, slot in ipairs(slots) do
        if CursorIsBusy() then break end

        local wanted = plan[slot]
        if IsInventoryItemLocked(slot) then
            -- Mid-move from an earlier step this pass. Skip it; the next pass
            -- recomputes and picks it up once the client has settled.
            wanted = nil
        end

        if wanted == ns.EMPTY then
            local bag, bagSlot = Items.FindFreeBagSlot(freeClaimed)
            if not bag then
                job.noRoom = true
                job.equip[slot] = nil  -- nowhere to put it; stop retrying
                remaining = remaining - 1
            else
                if MoveSlotToBag(slot, bag, bagSlot) then
                    remaining = remaining - 1
                end
            end
        elseif wanted then
            local found, score = FindBest(wanted, slot, bags, worn, claimedBag, claimedInv)
            if not found or score <= wornScore[slot] then
                -- Either we don't own it, or nothing we own beats what's
                -- already in the slot. Either way this slot is done.
                if not found and wornScore[slot] == 0 then
                    job.missing = job.missing or {}
                    job.missing[#job.missing + 1] = wanted
                end
                job.equip[slot] = nil
                remaining = remaining - 1
            elseif found.bag then
                if not Items.IsBagSlotLocked(found.bag, found.slot) then
                    claimedBag[found.key] = true
                    if MoveBagToSlot(found.bag, found.slot, slot) then
                        remaining = remaining - 1
                    end
                end
            elseif not IsInventoryItemLocked(found.inv) then
                claimedInv[found.inv] = true
                if MoveSlotToSlot(found.inv, slot) then
                    remaining = remaining - 1
                end
            end
        end
    end

    return remaining
end

--------------------------------------------------------------------------
-- Job lifecycle
--------------------------------------------------------------------------

local function Announce(fmt, ...)
    if ns.Config:Get("announceSwaps") then ns:Print(fmt, ...) end
end

local function FinishJob(job, stalled)
    Equip.job = nil
    Equip:SetWatching(false)

    local clean = not job.missing and not job.noRoom and not stalled

    if job.name and clean then
        HelloGearCharDB.currentSet = job.name
    end
    if job.clearRestoreOn then
        job.clearRestoreOn.restore = nil
        job.clearRestoreOn.restoreSet = nil
    end

    if job.noRoom then
        ns:Print("|cffff8080no free bag space|r - couldn't empty a slot")
    end
    if job.missing then
        local names = {}
        for _, gearID in ipairs(job.missing) do
            names[#names + 1] = Items.GetLink(gearID)
                or (Items.GetInfo(gearID))
                or ("item " .. tostring(Items.BaseID(gearID)))
        end
        ns:Print("|cffff8080couldn't find:|r %s", table.concat(names, ", "))
    end
    if stalled then
        ns:Print("|cffff8080gave up on %d slot(s)|r - something kept them locked", stalled)
    end
    if clean and job.label then
        Announce(job.label)
    end

    ns.Menu:Refresh()
    ns.UI:Refresh()
    ns.SlotMenus:Refresh()
end

local function Step()
    local job = Equip.job
    if not job then return end

    if GetTime() - job.startedAt > TIMEOUT or job.passes >= MAX_PASSES then
        local _, count = BuildPlan(job.equip)
        FinishJob(job, count > 0 and count or nil)
        return
    end

    -- Waiting on the client to finish a move, or on the player to drop
    -- whatever they picked up.
    if Items.AnythingLocked() or CursorIsBusy() then return end

    job.passes = job.passes + 1
    if RunPass(job) <= 0 then
        FinishJob(job)
    end
end

function Equip:SetWatching(on)
    if on == self.watching then return end
    self.watching = on
    if on then
        self.watcher:RegisterEvent("ITEM_LOCK_CHANGED")
        self.watcher:RegisterEvent("BAG_UPDATE_DELAYED")
        self.watcher:RegisterEvent("UNIT_INVENTORY_CHANGED")
        self.watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        self.watcher:RegisterEvent("PLAYER_UNGHOST")
        self.watcher:RegisterEvent("PLAYER_ALIVE")
        -- Events alone aren't enough to drive the job to completion: a pass
        -- that can't move anything (locks held, cursor busy, mid-cast)
        -- generates no events, so nothing would wake us up again. The ticker
        -- guarantees both progress and that the timeout is eventually seen.
        self.ticker = C_Timer.NewTicker(0.2, Step)
    else
        self.watcher:UnregisterAllEvents()
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    end
end

function Equip:Init()
    self.watcher = CreateFrame("Frame")
    self.watcher:SetScript("OnEvent", function()
        -- Coalesce: a single swap fires a burst of lock and bag events, and
        -- there is no point recomputing the plan for each one.
        if self.stepPending then return end
        self.stepPending = true
        C_Timer.After(0, function()
            self.stepPending = false
            Step()
        end)
    end)
end

-- job.equip is consumed and mutated (found items get removed as they land),
-- so callers pass a private copy.
function Equip:Start(job)
    if UnitIsDeadOrGhost("player") then
        ns:Print("can't swap gear while dead")
        return false
    end
    if self.job then
        -- Latest request wins. Queueing set swaps just means watching your
        -- character cycle through gear you didn't ask for.
        self.job = nil
    end

    job.passes = 0
    job.startedAt = GetTime()
    self.job = job

    if job.helm ~= nil then ns.API.SetShowHelm(job.helm) end
    if job.cloak ~= nil then ns.API.SetShowCloak(job.cloak) end

    self:SetWatching(true)
    Step()
    return true
end

--------------------------------------------------------------------------
-- Public entry points
--------------------------------------------------------------------------

function Equip:EquipSet(name)
    local resolved = Sets:Resolve(name)
    local set = resolved and Sets:Get(resolved)
    if not set then
        ns:Print('no set named "%s"', tostring(name))
        return false
    end

    local plan, count = BuildPlan(set.equip)
    if count == 0 then
        HelloGearCharDB.currentSet = resolved
        Announce('"%s" already equipped', resolved)
        ns.Menu:Refresh()
        ns.UI:Refresh()
        return true
    end

    -- Snapshot only the slots this set actually changes, so toggling a
    -- one-slot set back doesn't undo everything else you've swapped since.
    set.restore = {}
    for slot in pairs(plan) do
        set.restore[slot] = Items.GetWorn(slot) or ns.EMPTY
    end
    set.restoreSet = HelloGearCharDB.currentSet

    local equip = {}
    for slot, gearID in pairs(set.equip) do equip[slot] = gearID end

    return self:Start({
        equip = equip,
        name = resolved,
        label = ('equipped "%s"'):format(resolved),
        helm = set.helm,
        cloak = set.cloak,
    })
end

function Equip:UnequipSet(name)
    local resolved = Sets:Resolve(name)
    local set = resolved and Sets:Get(resolved)
    if not set then
        ns:Print('no set named "%s"', tostring(name))
        return false
    end
    if not set.restore or not next(set.restore) then
        ns:Print('nothing to put back for "%s"', resolved)
        return false
    end

    local equip = {}
    for slot, gearID in pairs(set.restore) do equip[slot] = gearID end

    return self:Start({
        equip = equip,
        name = set.restoreSet,
        label = ('put back what "%s" replaced'):format(resolved),
        clearRestoreOn = set,
    })
end

function Equip:ToggleSet(name)
    local resolved = Sets:Resolve(name)
    if not resolved then
        ns:Print('no set named "%s"', tostring(name))
        return false
    end
    if Sets:IsEquipped(resolved) then
        return self:UnequipSet(resolved)
    end
    return self:EquipSet(resolved)
end

-- Single-item swap, used by the paperdoll slot menus.
function Equip:EquipItem(gearID, slot)
    return self:Start({
        equip = { [slot] = gearID },
        label = nil,
    })
end

function Equip:ClearSlot(slot)
    return self:Start({
        equip = { [slot] = ns.EMPTY },
        label = nil,
    })
end

function Equip:IsBusy()
    return self.job ~= nil
end
