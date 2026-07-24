-- Offline harness for HelloGear's swap engine. Simulates a character's worn
-- gear, bags and item cursor, then runs the real Equip.lua against it.

-- Usage, from the addon root:  lua Tests/test_equip.lua
local ADDON = (arg[0]:match("^(.*)/Tests/[^/]+$")) or "."

--------------------------------------------------------------------------
-- Simulated world
--------------------------------------------------------------------------

local world = {}

local ITEM_DB = {}  -- itemID -> {equipLoc, name}
local function DefItem(id, equipLoc, name) ITEM_DB[id] = { equipLoc = equipLoc, name = name or ("Item" .. id) } end

DefItem(100, "INVTYPE_HEAD",           "Helm")
DefItem(101, "INVTYPE_CHEST",          "Chest")
DefItem(102, "INVTYPE_FINGER",         "Ring A")
DefItem(103, "INVTYPE_FINGER",         "Ring B")
DefItem(104, "INVTYPE_2HWEAPON",       "Big Axe")
DefItem(105, "INVTYPE_WEAPON",         "Sword")
DefItem(106, "INVTYPE_SHIELD",         "Shield")
DefItem(107, "INVTYPE_TRINKET",        "Trinket A")
DefItem(108, "INVTYPE_TRINKET",        "Trinket B")
DefItem(109, "INVTYPE_WRIST",          "Bracers")   -- random suffix carrier
DefItem(110, "INVTYPE_WEAPONOFFHAND",  "Offhand")
DefItem(111, "INVTYPE_HEAD",           "Helm B")

local function reset()
    world.worn = {}
    world.bags = {}
    for bag = 0, 4 do
        world.bags[bag] = { size = (bag == 0 and 16 or 16), items = {} }
    end
    world.cursor = nil
    world.time = 1000
end
reset()

local function bagFree(bag, slot) return world.bags[bag].items[slot] == nil end

--------------------------------------------------------------------------
-- WoW API stubs
--------------------------------------------------------------------------

local SLOT_IDS = {
    AmmoSlot = 0, HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4,
    ChestSlot = 5, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8, WristSlot = 9,
    HandsSlot = 10, Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13,
    Trinket1Slot = 14, BackSlot = 15, MainHandSlot = 16, SecondaryHandSlot = 17,
    RangedSlot = 18, TabardSlot = 19,
}
function GetInventorySlotInfo(key) return SLOT_IDS[key], "empty-icon" end

NUM_BAG_SLOTS = 4

local function gearItemID(gearID)
    return tonumber(gearID:match("^(%d+)"))
end

-- The client hands back a full item string, not a gear ID, so the sim has to
-- expand its compact internal form the same way.
local function linkFor(gearID)
    local id, enchant, suffix, unique = gearID:match("^(%d+):(%d+):(%-?%d+):(%d+)$")
    return ("|cffffffff|Hitem:%s:%s:0:0:0:0:%s:%s:60|h[%s]|h|r")
        :format(id, enchant, suffix, unique, ITEM_DB[tonumber(id)].name)
end

C_Container = {
    GetContainerNumSlots = function(bag) return world.bags[bag] and world.bags[bag].size or 0 end,
    GetContainerItemLink = function(bag, slot)
        local g = world.bags[bag] and world.bags[bag].items[slot]
        return g and linkFor(g) or nil
    end,
    GetContainerItemInfo = function(bag, slot)
        local g = world.bags[bag] and world.bags[bag].items[slot]
        if not g then return nil end
        return { hyperlink = linkFor(g), isLocked = false, itemID = gearItemID(g) }
    end,
    GetContainerNumFreeSlots = function(bag)
        local free = 0
        for slot = 1, world.bags[bag].size do
            if bagFree(bag, slot) then free = free + 1 end
        end
        return free, 0
    end,
    PickupContainerItem = function(bag, slot)
        local held = world.cursor
        local there = world.bags[bag].items[slot]
        if held == nil then
            if there == nil then return end
            world.cursor = there
            world.bags[bag].items[slot] = nil
        else
            world.bags[bag].items[slot] = held
            world.cursor = there
        end
    end,
}

function PickupInventoryItem(slot)
    local held = world.cursor
    if held == nil then
        local there = world.worn[slot]
        if there == nil then return end
        world.cursor = there
        world.worn[slot] = nil
        return
    end

    -- Mirror the client: ammo dropped on the ranged slot lands in the ammo slot.
    local equipLoc = ITEM_DB[gearItemID(held)].equipLoc
    if slot == 18 and equipLoc == "INVTYPE_AMMO" then slot = 0 end

    -- The client refuses gear that doesn't belong in the slot; the item stays
    -- on the cursor, which is exactly the case FinishMove has to survive.
    local valid = false
    for _, id in ipairs(({
        INVTYPE_AMMO = {0}, INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3},
        INVTYPE_BODY = {4}, INVTYPE_CHEST = {5}, INVTYPE_WAIST = {6}, INVTYPE_LEGS = {7},
        INVTYPE_FEET = {8}, INVTYPE_WRIST = {9}, INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12},
        INVTYPE_TRINKET = {13, 14}, INVTYPE_CLOAK = {15}, INVTYPE_WEAPON = {16, 17},
        INVTYPE_2HWEAPON = {16}, INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_WEAPONOFFHAND = {17},
        INVTYPE_SHIELD = {17}, INVTYPE_RANGED = {18}, INVTYPE_THROWN = {18}, INVTYPE_TABARD = {19},
    })[equipLoc] or {}) do
        if id == slot then valid = true break end
    end
    if not valid then return end

    -- A two-hander going on pushes the off hand out; the client puts it in a
    -- bag if it can, and refuses the equip if it can't.
    if slot == 16 and equipLoc == "INVTYPE_2HWEAPON" and world.worn[17] then
        local placed = false
        for bag = 0, 4 do
            for s = 1, world.bags[bag].size do
                if bagFree(bag, s) then
                    world.bags[bag].items[s] = world.worn[17]
                    world.worn[17] = nil
                    placed = true
                    break
                end
            end
            if placed then break end
        end
        if not placed then return end
    end

    -- Likewise an off-hand item can't go on over a two-hander.
    if slot == 17 and world.worn[16] and ITEM_DB[gearItemID(world.worn[16])].equipLoc == "INVTYPE_2HWEAPON" then
        return
    end

    local there = world.worn[slot]
    world.worn[slot] = held
    world.cursor = there
end

function GetInventoryItemLink(_, slot)
    local g = world.worn[slot]
    return g and linkFor(g) or nil
end
function GetInventoryItemID(_, slot)
    local g = world.worn[slot]
    return g and gearItemID(g) or nil
end
function IsInventoryItemLocked() return false end
function CursorHasItem() return world.cursor ~= nil end
function ClearCursor()
    if not world.cursor then return end
    for bag = 0, 4 do
        for s = 1, world.bags[bag].size do
            if bagFree(bag, s) then
                world.bags[bag].items[s] = world.cursor
                world.cursor = nil
                return
            end
        end
    end
    error("cursor stuck: no bag space to drop it")
end
function GetCursorInfo() return world.cursor and "item" or nil end
function SpellIsTargeting() return false end
function UnitLevel() return 60 end
function UnitIsDeadOrGhost() return false end
function CanDualWield() return true end
function GetTime() return world.time end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

C_CVar = { SetCVar = function() end }
C_Item = {
    GetItemInfo = function(itemString)
        local id = tonumber(itemString:match("item:(%d+)"))
        local entry = id and ITEM_DB[id]
        if not entry then return nil end
        -- name, link, quality, itemLevel, minLevel, ..., equipLoc, texture
        return entry.name, itemString, 3, 60, 60, nil, nil, nil, entry.equipLoc, "icon"
    end,
    GetItemInfoInstant = function(id)
        local entry = ITEM_DB[id]
        if not entry then return nil end
        return id, nil, nil, entry.equipLoc, "icon"
    end,
    GetItemCooldown = function() return 0, 0 end,
    GetItemCount = function() return 1 end,
}

local tickers = {}
C_Timer = {
    After = function(_, fn) fn() end,
    NewTicker = function(_, fn)
        local t = { fn = fn, cancelled = false }
        t.Cancel = function(self) self.cancelled = true end
        tickers[#tickers + 1] = t
        return t
    end,
}

local function CreateFrameStub()
    local f = {}
    function f:SetScript() end
    function f:RegisterEvent() end
    function f:UnregisterAllEvents() end
    return f
end
function CreateFrame() return CreateFrameStub() end

--------------------------------------------------------------------------
-- Namespace
--------------------------------------------------------------------------

local ns = {}
ns.EMPTY = 0
ns.API = {
    GetItemInfo = C_Item.GetItemInfo,
    GetItemInfoInstant = C_Item.GetItemInfoInstant,
    GetItemCooldown = C_Item.GetItemCooldown,
    GetItemCount = C_Item.GetItemCount,
    SetShowHelm = function() end,
    SetShowCloak = function() end,
}

local messages = {}
function ns:Print(fmt, ...)
    local line = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    messages[#messages + 1] = (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

HelloGearCharDB = { sets = {}, order = {}, bindings = {} }
ns.Config = {
    GetCharTable = function(_, key)
        HelloGearCharDB[key] = HelloGearCharDB[key] or {}
        return HelloGearCharDB[key]
    end,
    Get = function(_, key) return key ~= "announceSwaps" end,
}
ns.Menu = { Refresh = function() end }
ns.Panel = { Refresh = function() end }
ns.Paperdoll = { Refresh = function() end }

local function load_addon_file(name)
    local chunk, err = loadfile(ADDON .. "/" .. name)
    if not chunk then error(err) end
    chunk("HelloGear", ns)
end

load_addon_file("Items.lua")
load_addon_file("Sets.lua")
load_addon_file("Equip.lua")

local Items, Sets, Equip = ns.Items, ns.Sets, ns.Equip
Equip:Init()

--------------------------------------------------------------------------
-- Driving a swap to completion
--------------------------------------------------------------------------

local function drain()
    local guard = 0
    while Equip.job do
        guard = guard + 1
        if guard > 200 then error("swap never finished") end
        world.time = world.time + 0.05
        for _, t in ipairs(tickers) do
            if not t.cancelled and Equip.job then t.fn() end
        end
    end
end

local function G(id, enchant, suffix, unique) return Items.Make(id, enchant or 0, suffix or 0, unique or 0) end

local function putBag(gearID, bag, slot)
    bag = bag or 0
    if not slot then
        for s = 1, world.bags[bag].size do
            if bagFree(bag, s) then slot = s break end
        end
    end
    world.bags[bag].items[slot] = gearID
end

local function bagContains(gearID)
    for bag = 0, 4 do
        for s = 1, world.bags[bag].size do
            if world.bags[bag].items[s] == gearID then return true end
        end
    end
    return false
end

--------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------

local failures, tests = 0, 0
local function check(cond, msg)
    tests = tests + 1
    if not cond then
        failures = failures + 1
        print("  FAIL: " .. msg)
    end
end

local function scenario(name, fn)
    reset()
    HelloGearCharDB.sets, HelloGearCharDB.order = {}, {}
    HelloGearCharDB.currentSet = nil
    messages = {}
    print(name)
    fn()
end

------------------------------------------------------------------
scenario("full set out of bags", function()
    local helm, chest, ring = G(100), G(101), G(102)
    putBag(helm); putBag(chest); putBag(ring)
    Sets:Create("Tank", { equip = { [1] = helm, [5] = chest, [11] = ring } })

    Equip:EquipSet("Tank")
    drain()

    check(world.worn[1] == helm, "helm equipped")
    check(world.worn[5] == chest, "chest equipped")
    check(world.worn[11] == ring, "ring equipped")
    check(Sets:IsEquipped("Tank"), "set reports equipped")
    check(HelloGearCharDB.currentSet == "Tank", "current set recorded")
end)

------------------------------------------------------------------
scenario("rings already worn but in each other's slots", function()
    local ringA, ringB = G(102), G(103)
    world.worn[11] = ringB
    world.worn[12] = ringA
    Sets:Create("Swap", { equip = { [11] = ringA, [12] = ringB } })

    Equip:EquipSet("Swap")
    drain()

    check(world.worn[11] == ringA, "ring A moved to slot 11")
    check(world.worn[12] == ringB, "ring B moved to slot 12")
    check(not bagContains(ringA) and not bagContains(ringB), "neither ring detoured through a bag")
end)

------------------------------------------------------------------
scenario("two-hander displaces an occupied off hand", function()
    local axe, sword, shield = G(104), G(105), G(106)
    world.worn[16] = sword
    world.worn[17] = shield
    putBag(axe)
    Sets:Create("2H", { equip = { [16] = axe } })

    Equip:EquipSet("2H")
    drain()

    check(world.worn[16] == axe, "two-hander equipped")
    check(world.worn[17] == nil, "off hand emptied")
    check(bagContains(shield), "shield went to a bag")
end)

------------------------------------------------------------------
scenario("one-hander plus shield replaces a two-hander", function()
    local axe, sword, shield = G(104), G(105), G(106)
    world.worn[16] = axe
    putBag(sword); putBag(shield)
    Sets:Create("SnB", { equip = { [16] = sword, [17] = shield } })

    Equip:EquipSet("SnB")
    drain()

    check(world.worn[16] == sword, "one-hander equipped")
    check(world.worn[17] == shield, "shield equipped")
    check(bagContains(axe), "two-hander stowed")
end)

------------------------------------------------------------------
scenario("deliberately empty slot", function()
    local shield = G(106)
    world.worn[17] = shield
    Sets:Create("NoOffhand", { equip = { [17] = ns.EMPTY } })

    Equip:EquipSet("NoOffhand")
    drain()

    check(world.worn[17] == nil, "off hand cleared")
    check(bagContains(shield), "shield went to a bag")
    check(Sets:IsEquipped("NoOffhand"), "empty-slot set reports equipped")
end)

------------------------------------------------------------------
scenario("partial set leaves other slots alone", function()
    local helm, chest, ring = G(100), G(101), G(102)
    world.worn[1] = helm
    world.worn[5] = chest
    putBag(ring)
    Sets:Create("JustRing", { equip = { [11] = ring } })

    Equip:EquipSet("JustRing")
    drain()

    check(world.worn[1] == helm, "helm untouched")
    check(world.worn[5] == chest, "chest untouched")
    check(world.worn[11] == ring, "ring equipped")
end)

------------------------------------------------------------------
scenario("prefers the copy with the matching enchant", function()
    local plain, enchanted = G(105, 0), G(105, 2543)
    putBag(plain, 0, 1)
    putBag(enchanted, 0, 2)
    Sets:Create("Enchanted", { equip = { [16] = enchanted } })

    Equip:EquipSet("Enchanted")
    drain()

    check(world.worn[16] == enchanted, "picked the enchanted copy")
    check(bagContains(plain), "unenchanted copy left in the bag")
end)

------------------------------------------------------------------
scenario("will not equip the wrong random suffix", function()
    local owl  = G(109, 0, 1408, 111)
    local bear = G(109, 0, 1122, 222)
    putBag(bear)
    Sets:Create("Owl", { equip = { [9] = owl } })

    Equip:EquipSet("Owl")
    drain()

    check(world.worn[9] == nil, "wrong suffix not equipped")
    check(bagContains(bear), "wrong suffix left alone")
    local reported = false
    for _, m in ipairs(messages) do if m:match("couldn't find") then reported = true end end
    check(reported, "missing item reported")
end)

------------------------------------------------------------------
scenario("accepts a different instance of the same suffix", function()
    local wanted = G(109, 0, 1408, 111)
    local other  = G(109, 0, 1408, 999)
    putBag(other)
    Sets:Create("Owl", { equip = { [9] = wanted } })

    Equip:EquipSet("Owl")
    drain()

    check(world.worn[9] == other, "equipped the equivalent copy")
end)

------------------------------------------------------------------
scenario("missing gear does not block the rest of the set", function()
    local helm, chest = G(100), G(101)
    putBag(helm)
    Sets:Create("Partial", { equip = { [1] = helm, [5] = chest } })

    Equip:EquipSet("Partial")
    drain()

    check(world.worn[1] == helm, "available piece still equipped")
    check(world.worn[5] == nil, "missing piece skipped")
end)

------------------------------------------------------------------
scenario("a set saved before re-enchanting does not churn", function()
    -- The set stores the pre-enchant weapon; the only copy owned is the
    -- enchanted one already equipped. Nothing should move, nothing should be
    -- reported missing.
    local saved, worn = G(105, 0), G(105, 2543)
    world.worn[16] = worn
    Sets:Create("Old", { equip = { [16] = saved } })

    Equip:EquipSet("Old")
    drain()

    check(world.worn[16] == worn, "kept the enchanted copy on")
    check(not bagContains(worn), "did not stow it")
    for _, m in ipairs(messages) do
        check(not m:match("couldn't find"), "should not report the item missing: " .. m)
    end
end)

------------------------------------------------------------------
scenario("an exact copy in the bag still wins over a partial match", function()
    local saved, worn = G(105, 2543), G(105, 0)
    world.worn[16] = worn
    putBag(saved)
    Sets:Create("Exact", { equip = { [16] = saved } })

    Equip:EquipSet("Exact")
    drain()

    check(world.worn[16] == saved, "swapped to the exact copy")
    check(bagContains(worn), "old copy stowed")
end)

------------------------------------------------------------------
scenario("toggle puts back exactly what it replaced", function()
    local oldHelm, newHelm, chest = G(100), G(111), G(101)
    world.worn[1] = oldHelm
    world.worn[5] = chest
    putBag(newHelm)
    Sets:Create("Hat", { equip = { [1] = newHelm } })

    Equip:ToggleSet("Hat")
    drain()
    check(world.worn[1] == newHelm, "new helm on")

    Equip:ToggleSet("Hat")
    drain()
    check(world.worn[1] == oldHelm, "old helm restored")
    check(world.worn[5] == chest, "untouched slot stayed put")
    check(bagContains(newHelm), "new helm back in the bag")
end)

------------------------------------------------------------------
scenario("toggling a set that clears a slot restores it", function()
    local shield = G(106)
    world.worn[17] = shield
    Sets:Create("NoOffhand", { equip = { [17] = ns.EMPTY } })

    Equip:ToggleSet("NoOffhand")
    drain()
    check(world.worn[17] == nil, "off hand cleared")

    Equip:ToggleSet("NoOffhand")
    drain()
    check(world.worn[17] == shield, "shield put back")
end)

------------------------------------------------------------------
scenario("no free bag space when a slot must be emptied", function()
    local shield = G(106)
    world.worn[17] = shield
    for bag = 0, 4 do
        for s = 1, world.bags[bag].size do world.bags[bag].items[s] = G(107) end
    end
    Sets:Create("NoOffhand", { equip = { [17] = ns.EMPTY } })

    Equip:EquipSet("NoOffhand")
    drain()

    check(world.worn[17] == shield, "shield left equipped")
    local reported = false
    for _, m in ipairs(messages) do if m:match("no free bag space") then reported = true end end
    check(reported, "bag space problem reported")
end)

------------------------------------------------------------------
scenario("re-equipping an already worn set is a no-op", function()
    local helm = G(100)
    world.worn[1] = helm
    Sets:Create("Hat", { equip = { [1] = helm } })

    Equip:EquipSet("Hat")
    drain()

    check(world.worn[1] == helm, "still wearing it")
    check(Equip.job == nil, "no job left running")
    check(HelloGearCharDB.currentSet == "Hat", "current set recorded anyway")
end)

------------------------------------------------------------------
scenario("single-item swap from a slot menu", function()
    local sword, shield, offhand = G(105), G(106), G(110)
    world.worn[16] = sword
    world.worn[17] = shield
    putBag(offhand)

    Equip:EquipItem(offhand, 17)
    drain()

    check(world.worn[17] == offhand, "off-hand item equipped")
    check(bagContains(shield), "shield stowed")
    check(world.worn[16] == sword, "main hand untouched")
end)

------------------------------------------------------------------
scenario("full 15-slot set swap in one go", function()
    local wanted = {}
    local layout = {
        [1] = 100, [5] = 101, [9] = 109, [11] = 102, [12] = 103,
        [13] = 107, [14] = 108, [16] = 105, [17] = 106,
    }
    for slot, id in pairs(layout) do
        wanted[slot] = G(id, 1000 + slot)
        putBag(wanted[slot])
    end
    -- Start out wearing a different variant of each piece.
    for slot, id in pairs(layout) do
        world.worn[slot] = G(id, 2000 + slot)
    end
    Sets:Create("Everything", { equip = wanted })

    Equip:EquipSet("Everything")
    drain()

    for slot in pairs(layout) do
        check(world.worn[slot] == wanted[slot], ("slot %d holds the right item"):format(slot))
    end
    check(Sets:IsEquipped("Everything", true), "exact match after swap")
end)

------------------------------------------------------------------
scenario("right-click takes a slot in and out of the set", function()
    local helm = G(100)
    world.worn[1] = helm
    local set = Sets:Create("Edit", { equip = {} })

    check(Sets:SlotState(set, 1) == "ignored", "starts out unmanaged")

    check(Sets:ToggleSlot(set, 1) == "worn", "coming in adopts what's worn")
    check(set.equip[1] == helm, "stored the worn item")

    check(Sets:ToggleSlot(set, 1) == "ignored", "toggling again drops it")
    check(set.equip[1] == nil, "slot dropped from the set")
end)

------------------------------------------------------------------
scenario("a bare slot comes into the set as a clear", function()
    -- Nothing worn in the off hand, so there is nothing to adopt; the only
    -- other thing including it could mean is "this set strips the slot".
    local set = Sets:Create("Edit", { equip = {} })
    check(Sets:ToggleSlot(set, 17) == "empty", "bare slot comes in as a clear")
    check(Sets:ToggleSlot(set, 17) == "ignored", "and goes back out")
end)

------------------------------------------------------------------
scenario("left-click assigns a specific item to a slot", function()
    local worn, other = G(100), G(111)
    world.worn[1] = worn
    local set = Sets:Create("Edit", { equip = {} })

    check(Sets:SetSlot(set, 1, other) == "stored", "picked an item that isn't on")
    check(set.equip[1] == other, "stored the chosen item")

    check(Sets:SetSlot(set, 1, worn) == "worn", "picking the worn item reads as worn")

    -- The "No item" row: the set strips the slot, which is not the same as
    -- dropping the slot from the set.
    check(Sets:SetSlot(set, 1, ns.EMPTY) == "empty", "no-item means clear the slot")
    check(set.equip[1] == ns.EMPTY, "stored the empty sentinel, not nil")

    check(Sets:SetSlot(set, 1, nil) == "ignored", "nil drops the slot entirely")
end)

------------------------------------------------------------------
scenario("a managed slot reads as stored when its item is off", function()
    local worn, other = G(100), G(111)
    world.worn[1] = worn
    local set = Sets:Create("Edit", { equip = { [1] = other } })
    check(Sets:SlotState(set, 1) == "stored", "set item is not the one worn")

    world.worn[1] = other
    check(Sets:SlotState(set, 1) == "worn", "reads as worn once it's on")
end)

------------------------------------------------------------------
print("")
if failures == 0 then
    print(("ALL %d CHECKS PASSED"):format(tests))
else
    print(("%d of %d CHECKS FAILED"):format(failures, tests))
    os.exit(1)
end
