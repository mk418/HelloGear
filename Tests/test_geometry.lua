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

--------------------------------------------------------------------------
-- Vertical fit: how far above CharacterFrame's bottom the artwork ends.
-- Measured from the tab row, which sits across the artwork's bottom edge.
--------------------------------------------------------------------------

local ComputeArtBottom = ns.Panel.ComputeArtBottom

-- Measured off screenshot pixels: the tab row's top sits 78 above the frame's
-- bottom, and the tabs overlap upward INTO the artwork, whose bottom edge is
-- therefore 11 below that - 67 above the frame's bottom, not above the tabs.
check(ComputeArtBottom(0, 78), 67, "measured tab row")

-- Position-independent, like the horizontal fit.
check(ComputeArtBottom(400, 478), 67, "frame moved up the screen")

-- No tab row to measure gives the stock answer rather than an error.
check(ComputeArtBottom(0, nil), 67, "missing tab row falls back")

-- Nonsense in, fallback out: tabs above the frame, or absurdly far up it.
check(ComputeArtBottom(0, -50), 67, "tab below the frame bottom")
check(ComputeArtBottom(0, 500), 67, "tab most of the way up the frame")

-- A genuinely different tab position is followed, not snapped to the default.
check(ComputeArtBottom(0, 110), 99, "taller tab offset is respected")

--------------------------------------------------------------------------
-- Slicing the character frame's artwork. The quadrants are laid out
-- 384x512: top-left at (0,0) 256x256, top-right at (256,0) 128x256.
--------------------------------------------------------------------------

local TexCoords = ns.Panel.TexCoords
local topLeft  = { x = 0,   y = 0, width = 256, height = 256 }
local topRight = { x = 256, y = 0, width = 128, height = 256 }
local bottomRight = { x = 256, y = -256, width = 128, height = 256 }

local function coords(...)
    return string.format("%.4f %.4f %.4f %.4f", ...)
end

-- An 11px strip along the top border. It starts below the artwork's 5 rows of
-- transparent padding: sampling from row zero caught the padding instead of
-- the border, and drew nothing at all.
check(coords(TexCoords(topLeft, 120, 240, 5, 16)),
    coords(120/256, 240/256, 5/256, 16/256), "top border strip")

-- The right border, 11px wide, ending at the artwork's visible edge of 348,
-- sampled at a depth where it actually carries its bevel.
check(coords(TexCoords(topRight, 337, 348, 250, 252)),
    coords((337-256)/128, (348-256)/128, 250/256, 252/256), "right border strip")

-- Every coordinate has to land inside the texture, or the slice samples
-- neighbouring artwork - which is how the paperdoll's slot recesses got in.
local l, r, t, b = TexCoords(topRight, 337, 348, 5, 16)
check(l >= 0 and l <= 1 and r >= 0 and r <= 1, true, "right strip u in range")
check(t >= 0 and t <= 1 and b >= 0 and b <= 1, true, "right strip v in range")

-- A bottom quadrant is offset 256 down, so depth has to be measured from the
-- artwork's top, not the quadrant's.
check(coords(TexCoords(bottomRight, 348, 359, 300, 311)),
    coords((348-256)/128, (359-256)/128, (300-256)/256, (311-256)/256),
    "bottom quadrant depth is relative to the artwork")

print("")
if failures == 0 then
    print(("ALL %d CHECKS PASSED"):format(tests))
else
    print(("%d of %d CHECKS FAILED"):format(failures, tests))
    os.exit(1)
end
