-- Offline harness for the character-frame fitting maths in CharacterPanel.lua.
--
-- CharacterFrame is a vanilla UIPanelFrame: 384x512 of frame holding 338x424
-- of artwork, so anything anchored to the frame's own right edge floats ~46px
-- clear of the frame you can see. The panel derives that inset from the
-- paperdoll's slot columns instead of hardcoding it; this checks the sums.
--
-- Usage, from the addon root:  lua Tests/test_geometry.lua

local ADDON = (arg[0]:match("^(.*)/Tests/[^/]+$")) or "."

--------------------------------------------------------------------------
-- Enough of a namespace to load CharacterPanel.lua's chunk. Only the pure
-- geometry function is exercised, so the frame-building half never runs.
--------------------------------------------------------------------------

local ns = { EMPTY = 0, SLOTS = {}, API = {} }
ns.Items = {}
ns.Sets = {}
ns.Config = { Get = function() return false end, Set = function() end }
ns.Menu = { Refresh = function() end }
ns.Paperdoll = { IsEditing = function() return false end }
function ns:Print() end
function ns:On() end

StaticPopupDialogs = {}
ACCEPT, CANCEL, YES, NO = "Accept", "Cancel", "Yes", "No"

local chunk, err = loadfile(ADDON .. "/CharacterPanel.lua")
if not chunk then error(err) end
chunk("HelloGear", ns)

local ComputeArtInset = ns.Panel.ComputeArtInset

--------------------------------------------------------------------------

local failures, tests = 0, 0
local function check(actual, expected, msg)
    tests = tests + 1
    if actual ~= expected then
        failures = failures + 1
        print(("  FAIL: %s (got %s, wanted %s)"):format(msg, tostring(actual), tostring(expected)))
    end
end

-- Real numbers, read off a 1.15.9 client with /hg dock: CharacterFrame spans
-- 0..384 and the slot columns run 21..343, so the artwork's right edge is at
-- 343 + 21 = 364 and the frame carries 20px of dead space past it.
local FALLBACK = -20
check(ComputeArtInset(0, 384, 21, 343), -20, "measured 1.15.9 character frame")

-- Same frame moved across the screen: the answer is a difference of edges, so
-- it must not depend on where the frame sits.
check(ComputeArtInset(500, 884, 521, 843), -20, "frame moved right")
check(ComputeArtInset(-300, 84, -279, 43), -20, "frame moved off the left")

-- A frame whose artwork fills it completely - a modern template, or another
-- addon having resized things - should dock flush, not 20px away.
check(ComputeArtInset(0, 364, 21, 343), 0, "artwork fills the frame")

-- Wider padding still measures correctly rather than snapping to a guess.
check(ComputeArtInset(0, 384, 20, 318), -46, "46px of padding")

-- Nonsense in, fallback out.
check(ComputeArtInset(0, 384, 21, 900), FALLBACK, "right column past the frame edge")
check(ComputeArtInset(0, 384, 21, 0), FALLBACK, "right column left of the frame")
check(ComputeArtInset(0, 384, -50, 343), FALLBACK, "left column outside the frame")

-- The fallback is the measured inset, so a total measurement failure still
-- lands the panel in the right place on an unmodified frame.
check(ComputeArtInset(0, 384, 0, 0), ComputeArtInset(0, 384, 21, 343),
    "fallback matches the measured frame")

print("")
if failures == 0 then
    print(("ALL %d CHECKS PASSED"):format(tests))
else
    print(("%d of %d CHECKS FAILED"):format(failures, tests))
    os.exit(1)
end
