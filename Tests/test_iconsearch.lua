-- Exercises the picker's search key against the shipped name table: the point
-- is that separators don't matter, since names arrive underscored, spaced and
-- capitalised depending on where they came from.
local ns = {}
-- Usage, from the addon root:  lua Tests/test_iconsearch.lua
local ADDON = (arg[0]:match("^(.*)/Tests/[^/]+$")) or "."
loadfile(ADDON .. "/IconNames.lua")("HelloGear", ns)

local function SearchKey(name)
    if not name then return nil end
    return (name:lower():gsub("[^%a%d]", ""))
end

local failures = 0
local function check(cond, msg)
    if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

local function matches(query)
    local key = SearchKey(query)
    local n = 0
    for _, name in pairs(ns.IconNames) do
        if SearchKey(name):find(key, 1, true) then n = n + 1 end
    end
    return n
end

check(matches("ambush") > 0, "plain word finds an icon")
check(matches("shadow bolt") > 0, "spaced query finds an underscored name")
check(matches("shadow_bolt") > 0, "underscored query works too")
check(matches("SHADOW BOLT") > 0, "case doesn't matter")
check(matches("frost") > 20, "a common word finds many")
check(matches("zzzznotathing") == 0, "nonsense finds nothing")
check(SearchKey("Chromatic Boots") == "chromaticboots", "item names normalise")
check(SearchKey("spell_shadow_shadowbolt") == "spellshadowshadowbolt", "paths normalise")

print(("ambush=%d  'shadow bolt'=%d  frost=%d"):format(
    matches("ambush"), matches("shadow bolt"), matches("frost")))
print(failures == 0 and "ALL CHECKS PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
