local ADDON_NAME, ns = ...

ns.Bank = {}
local Bank = ns.Bank
local Items = ns.Items
local Sets = ns.Sets

local PickupContainerItem = C_Container.PickupContainerItem

-- Same shape as the swap engine: moves complete asynchronously, so the work
-- runs in passes that re-read the world each time rather than assuming a
-- single sweep lands everything.
local MAX_PASSES = 20
local TIMEOUT = 10

local isOpen = false
Bank.job = nil

function Bank:IsOpen()
    return isOpen
end

--------------------------------------------------------------------------
-- Moves
--------------------------------------------------------------------------

local function CursorIsBusy()
    return CursorHasItem() or SpellIsTargeting() or (GetCursorInfo() ~= nil)
end

local function MoveContainerItem(fromBag, fromSlot, toBag, toSlot)
    if Items.IsBagSlotLocked(fromBag, fromSlot) or Items.IsBagSlotLocked(toBag, toSlot) then
        return false
    end
    PickupContainerItem(fromBag, fromSlot)
    if not CursorHasItem() then return false end
    PickupContainerItem(toBag, toSlot)
    if CursorHasItem() then
        ClearCursor()
        return false
    end
    return true
end

--------------------------------------------------------------------------
-- What needs moving
--
-- Recomputed every pass from the set and the world, so a move that silently
-- fails is simply retried and nothing has to be tracked between passes.
--------------------------------------------------------------------------

local function IndexBy(entries)
    local out = {}
    for _, entry in ipairs(entries) do
        out[entry.gearID] = out[entry.gearID] or {}
        table.insert(out[entry.gearID], entry)
    end
    return out
end

-- Best match for `wanted` among entries, preferring an exact one, skipping
-- anything already claimed this pass.
local function TakeBest(index, wanted, claimed)
    local best, bestScore
    for gearID, entries in pairs(index) do
        local score = Items.MatchScore(wanted, gearID)
        if score and (not bestScore or score > bestScore) then
            for _, entry in ipairs(entries) do
                local key = entry.bag .. ":" .. entry.slot
                if not claimed[key] then
                    best, bestScore = entry, score
                    break
                end
            end
        end
    end
    return best
end

-- Items the set wants that are sitting in the bank and nowhere else.
local function PlanWithdraw(set)
    local worn = Items.GetWornSet()
    local bags = IndexBy(Items.ScanBags())
    local bank = IndexBy(Items.ScanBank())
    local claimed, plan = {}, {}

    local function alreadyHave(wanted)
        for gearID in pairs(bags) do
            if Items.MatchScore(wanted, gearID) then return true end
        end
        for _, gearID in pairs(worn) do
            if Items.MatchScore(wanted, gearID) then return true end
        end
        return false
    end

    for _, wanted in pairs(set.equip) do
        if wanted ~= ns.EMPTY then
            if not alreadyHave(wanted) then
                local entry = TakeBest(bank, wanted, claimed)
                if entry then
                    claimed[entry.bag .. ":" .. entry.slot] = true
                    plan[#plan + 1] = entry
                end
            end
        end
    end
    return plan
end

-- The set's items that are in your bags, which is what "put it away" means.
-- Anything worn stays on; taking a set off is what unequipping is for.
local function PlanDeposit(set)
    local bags = IndexBy(Items.ScanBags())
    local claimed, plan = {}, {}

    for _, wanted in pairs(set.equip) do
        if wanted ~= ns.EMPTY then
            local entry = TakeBest(bags, wanted, claimed)
            if entry then
                claimed[entry.bag .. ":" .. entry.slot] = true
                plan[#plan + 1] = entry
            end
        end
    end
    return plan
end

--------------------------------------------------------------------------
-- Job lifecycle
--------------------------------------------------------------------------

local function FinishJob(job, stalled)
    Bank.job = nil
    Bank:SetWatching(false)

    if job.moved > 0 then
        ns:Print(job.label, job.moved)
    elseif not job.noRoom and not stalled then
        ns:Print(job.nothing)
    end
    if job.noRoom then
        ns:Print("|cffff8080ran out of room|r after moving %d", job.moved)
    end
    if stalled then
        ns:Print("|cffff8080gave up|r with %d still to move", stalled)
    end

    ns.Panel:Refresh()
end

local function Step()
    local job = Bank.job
    if not job then return end

    if not isOpen then
        FinishJob(job)
        return
    end
    if GetTime() - job.startedAt > TIMEOUT or job.passes >= MAX_PASSES then
        local remaining = #job.plan(job.set)
        FinishJob(job, remaining > 0 and remaining or nil)
        return
    end
    if Items.AnythingLocked() or CursorIsBusy() then return end

    job.passes = job.passes + 1

    local plan = job.plan(job.set)
    if #plan == 0 then
        FinishJob(job)
        return
    end

    local freeClaimed = {}
    for _, entry in ipairs(plan) do
        if CursorIsBusy() then break end
        local bag, slot
        if job.toBank then
            bag, slot = Items.FindFreeBankSlot(freeClaimed)
        else
            bag, slot = Items.FindFreeBagSlot(freeClaimed)
        end
        if not bag then
            job.noRoom = true
            break
        end
        if MoveContainerItem(entry.bag, entry.slot, bag, slot) then
            job.moved = job.moved + 1
        end
    end

    if job.noRoom then FinishJob(job) end
end

function Bank:SetWatching(on)
    if on == self.watching then return end
    self.watching = on
    if on then
        self.watcher:RegisterEvent("ITEM_LOCK_CHANGED")
        self.watcher:RegisterEvent("BAG_UPDATE_DELAYED")
        self.watcher:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
        self.ticker = C_Timer.NewTicker(0.2, Step)
    else
        self.watcher:UnregisterAllEvents()
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    end
end

local function Start(job)
    if not isOpen then
        ns:Print("open the bank first")
        return false
    end
    job.passes = 0
    job.moved = 0
    job.startedAt = GetTime()
    Bank.job = job
    Bank:SetWatching(true)
    Step()
    return true
end

--------------------------------------------------------------------------

function Bank:Withdraw(name)
    local resolved = Sets:Resolve(name)
    local set = resolved and Sets:Get(resolved)
    if not set then
        ns:Print('no set named "%s"', tostring(name))
        return false
    end
    return Start({
        set = set,
        plan = PlanWithdraw,
        toBank = false,
        label = ('took %%d item(s) out of the bank for "%s"'):format(resolved),
        nothing = ('nothing to fetch for "%s" - everything is on you or in your bags'):format(resolved),
    })
end

function Bank:Deposit(name)
    local resolved = Sets:Resolve(name)
    local set = resolved and Sets:Get(resolved)
    if not set then
        ns:Print('no set named "%s"', tostring(name))
        return false
    end
    return Start({
        set = set,
        plan = PlanDeposit,
        toBank = true,
        label = ('put %%d item(s) from "%s" into the bank'):format(resolved),
        nothing = ('nothing from "%s" is in your bags - worn gear stays on'):format(resolved),
    })
end

-- How many of these the bank is holding. Used to turn "couldn't find it" into
-- something more useful when the bank happens to be open.
function Bank:CountHolding(gearIDs)
    if not isOpen then return 0 end
    local bank = Items.ScanBank()
    local count = 0
    for _, wanted in ipairs(gearIDs) do
        for _, entry in ipairs(bank) do
            if Items.MatchScore(wanted, entry.gearID) then
                count = count + 1
                break
            end
        end
    end
    return count
end

function Bank:Init()
    self.watcher = CreateFrame("Frame")
    self.watcher:SetScript("OnEvent", function()
        if self.stepPending then return end
        self.stepPending = true
        C_Timer.After(0, function()
            self.stepPending = false
            Step()
        end)
    end)

    ns:On("BANKFRAME_OPENED", function()
        isOpen = true
        ns.Panel:Refresh()
    end)
    ns:On("BANKFRAME_CLOSED", function()
        isOpen = false
        -- Anything still queued can't be completed with the window shut.
        if Bank.job then Step() end
        ns.Panel:Refresh()
    end)
end
