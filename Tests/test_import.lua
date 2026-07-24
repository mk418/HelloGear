-- Offline harness: runs HelloGear's real Items/Sets/Import code against a
-- real ItemRack SavedVariables file, with the WoW API stubbed out.

-- Usage, from the addon root:  lua Tests/test_import.lua [path/to/ItemRack.lua]
local ADDON = (arg[0]:match("^(.*)/Tests/[^/]+$")) or "."
local SV = arg[1]
if not SV then
    io.stderr:write("usage: lua Tests/test_import.lua <path to an ItemRack.lua SavedVariables file>\n")
    os.exit(2)
end

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

function GetInventorySlotInfo(key)
    local id = SLOT_IDS[key]
    if not id then error("unknown slot " .. tostring(key)) end
    return id, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. key
end

NUM_BAG_SLOTS = 4
C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemLink = function() return nil end,
    GetContainerItemInfo = function() return nil end,
    GetContainerNumFreeSlots = function() return 0, 0 end,
    PickupContainerItem = function() end,
}
C_Item = {
    GetItemInfo = function() return nil end,
    GetItemInfoInstant = function() return nil end,
    GetItemCooldown = function() return 0, 0 end,
    GetItemCount = function() return 0 end,
}
C_CVar = { SetCVar = function() end }
function UnitLevel() return 60 end
function GetInventoryItemLink() return nil end
function GetInventoryItemID() return nil end
function IsInventoryItemLocked() return false end
StaticPopupDialogs = {}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

--------------------------------------------------------------------------
-- Namespace stubs
--------------------------------------------------------------------------

local ns = {}
ns.EMPTY = 0
ns.API = {
    GetItemInfo = C_Item.GetItemInfo,
    GetItemInfoInstant = C_Item.GetItemInfoInstant,
}

local printed = {}
function ns:Print(fmt, ...)
    local line = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    printed[#printed + 1] = line
    print("  | " .. (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
end

HelloGearCharDB = { sets = {}, order = {}, bindings = {} }
ns.Config = {
    GetCharTable = function(_, key)
        HelloGearCharDB[key] = HelloGearCharDB[key] or {}
        return HelloGearCharDB[key]
    end,
    Get = function() return false end,
}
ns.Menu = { Refresh = function() end }
ns.Panel = { Refresh = function() end }

local function load_addon_file(name)
    local chunk, err = loadfile(ADDON .. "/" .. name)
    if not chunk then error(err) end
    chunk("HelloGear", ns)
end

load_addon_file("Items.lua")
load_addon_file("Sets.lua")
load_addon_file("Import.lua")

--------------------------------------------------------------------------
-- Load the real ItemRack saved variables
--------------------------------------------------------------------------

local sv = loadfile(SV)
if not sv then error("could not load " .. SV) end
sv()
assert(ItemRackUser and ItemRackUser.Sets, "no ItemRackUser.Sets in " .. SV)

local irCount = 0
for name in pairs(ItemRackUser.Sets) do
    if not name:match("^~") then irCount = irCount + 1 end
end

print("ItemRack sets on disk: " .. irCount)
print("Import:Available()   : " .. ns.Import:Available())
print("")
print("Running import...")
ns.Import:Run()
print("")

--------------------------------------------------------------------------
-- Verify the conversion
--------------------------------------------------------------------------

local Items, Sets = ns.Items, ns.Sets
local failures = 0
local function check(cond, msg)
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

check(Sets:Count() == irCount, ("set count %d ~= %d"):format(Sets:Count(), irCount))

-- Every stored gear ID must round-trip to the same four fields ItemRack had.
local totalSlots, emptySlots, suffixed = 0, 0, 0
for _, name in ipairs(Sets:Names(true)) do
    local set = Sets:Get(name)
    local irSet = ItemRackUser.Sets[name]
    check(irSet ~= nil, "imported set not in source: " .. name)

    for slot, gearID in pairs(set.equip) do
        totalSlots = totalSlots + 1
        check(slot >= 0 and slot <= 19, ("%s: slot %s out of range"):format(name, tostring(slot)))

        local source = irSet.equip[slot]
        if gearID == ns.EMPTY then
            emptySlots = emptySlots + 1
            check(source == 0, ("%s slot %d: EMPTY but source was %s"):format(name, slot, tostring(source)))
        else
            local itemID, enchant, suffix, unique = Items.Parse(gearID)
            check(type(source) == "string", ("%s slot %d: item but source was %s"):format(name, slot, tostring(source)))

            -- Re-derive from the raw ItemRack string independently.
            local parts = {}
            for field in (source .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = field end
            local expectID = tonumber(parts[1]) or 0
            local expectEnch = tonumber(parts[2]) or 0
            local expectSuf = tonumber(parts[7]) or 0
            local expectUniq = tonumber(parts[8]) or 0

            check(itemID == expectID, ("%s slot %d: itemID %d ~= %d"):format(name, slot, itemID, expectID))
            check(enchant == expectEnch, ("%s slot %d: enchant %d ~= %d"):format(name, slot, enchant, expectEnch))
            check(suffix == expectSuf, ("%s slot %d: suffix %d ~= %d"):format(name, slot, suffix, expectSuf))
            check(unique == expectUniq, ("%s slot %d: unique %d ~= %d"):format(name, slot, unique, expectUniq))
            if suffix ~= 0 then suffixed = suffixed + 1 end
        end
    end

    -- Cosmetic toggles
    if irSet.ShowHelm ~= nil then
        check(set.helm == (irSet.ShowHelm == 1), name .. ": helm flag lost")
    else
        check(set.helm == nil, name .. ": helm flag invented")
    end
    if irSet.ShowCloak ~= nil then
        check(set.cloak == (irSet.ShowCloak == 1), name .. ": cloak flag lost")
    else
        check(set.cloak == nil, name .. ": cloak flag invented")
    end
    check(set.icon ~= nil, name .. ": no icon")
end

-- Hidden flags
local hiddenExpected = 0
for _, hiddenName in ipairs(ItemRackUser.Hidden or {}) do
    if Sets:Get(hiddenName) then
        hiddenExpected = hiddenExpected + 1
        check(Sets:Get(hiddenName).hidden == true, hiddenName .. ": hidden flag lost")
    end
end

-- Internal ~sets must not have come across.
for name in pairs(ItemRackUser.Sets) do
    if name:match("^~") then
        check(Sets:Get(name) == nil, "internal set imported: " .. name)
    end
end

-- Matching semantics
local a = Items.Make(22418, 2583, 0, 0)
local b = Items.Make(22418, 2583, 0, 0)
local c = Items.Make(22418, 1503, 0, 0)
local d = Items.Make(18529, 0, 1408, 147762688)
local e = Items.Make(18529, 0, 1408, 999)
local f = Items.Make(18529, 0, 1122, 147762688)
check(Items.MatchScore(a, b) == 3, "identical items should score 3")
check(Items.MatchScore(a, c) == 1, "different enchant should score 1")
check(Items.MatchScore(d, e) == 2, "same suffix, different seed should score 2")
check(Items.MatchScore(d, f) == nil, "different random suffix must not match")
check(Items.MatchScore(a, ns.EMPTY) == nil, "EMPTY never matches an item")
check(Items.MatchScore(a, nil) == nil, "nil never matches")

-- Re-import must be idempotent (skips everything the second time).
local before = Sets:Count()
printed = {}
ns.Import:Run()
check(Sets:Count() == before, "re-import changed the set count")

-- Order list must stay consistent with the store.
local order = ns.Config:GetCharTable("order")
check(#order == Sets:Count(), ("order list %d ~= store %d"):format(#order, Sets:Count()))
local seen = {}
for _, name in ipairs(order) do
    check(not seen[name], "duplicate in order list: " .. name)
    check(Sets:Get(name) ~= nil, "order list references missing set: " .. name)
    seen[name] = true
end

print("")
print(("sets: %d   managed slots: %d   deliberate-empty: %d   random-suffix items: %d   hidden: %d")
    :format(Sets:Count(), totalSlots, emptySlots, suffixed, hiddenExpected))

if failures == 0 then
    print("ALL CHECKS PASSED")
else
    print(failures .. " CHECK(S) FAILED")
    os.exit(1)
end
