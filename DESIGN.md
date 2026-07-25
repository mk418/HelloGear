# HelloGear — Design Document

A gear set manager for World of Warcraft Classic Era. Written to replace ItemRack, which broke on the 1.15.9 client.

---

## Why this exists

ItemRack 4.23 calls `ShowHelm()` and `ShowCloak()` unguarded in `ItemRackEquip.lua`. Client 1.15.9 moved Classic Era onto the modern shared UI codebase, where both globals were removed in favour of the `showHelm` / `showCloak` CVars. Any set carrying a helm or cloak visibility flag now throws on equip.

That single break isn't worth a fork. The interesting part is that the surrounding code is 4000 lines of accumulated retail-era baggage — Titan's Grip, artifact weapons, Wrath jewelcrafting gem rules, a per-item cooldown queue system — for an addon whose job on Era is "put these items in these slots."

---

## Design philosophy

1. **Import first, ask questions later.** The addon is worthless if it can't read a decade of saved sets. The ItemRack import is the feature the rest is built around.
2. **Match the right item, not just the right item ID.** Random suffixes and enchants are what make Classic gear sets fiddly. Getting this wrong silently equips the wrong bracers.
3. **Converge, don't sequence.** Swaps are asynchronous. Rather than script a move order and hope, each pass re-reads the world and does whatever is currently possible. Self-healing beats clever.
4. **Same conventions as the other Hello addons.** Namespace threaded through `...`, one event dispatcher, version-sensitive API resolved once in `Core.lua`.

---

## Current scope

- **Sets** — create from worn gear, rename, delete, per-slot editing, per-character storage.
- **Equipping** — one-click equip, toggle (equip / put back what it displaced), single-item swaps.
- **ItemRack import** — sets, icons, hidden flags, helm/cloak toggles, deliberate-empty slots.
- **Set menu** — minimap button opens a list; click equips, shift-click toggles, right-click restores.
- **Character-sheet panel** — a button on the character frame opens a docked gear-set panel, and the paperdoll itself becomes the set editor.
- **Paperdoll slot menus** — every character-sheet slot gets a menu of the alternatives in your bags, with cooldown swirls.
- **Macro API** — `HelloGear.EquipSet("name")`, and the bare `EquipSet()` global ItemRack-era macros expect.

## Out of scope

- **Auto-swap events.** Equipping gear on stance change, zone entry or buff gain. ItemRack shipped this; it's a rules engine, and a rules engine that fires during a pull is a liability.
- **Cooldown queues.** Rotating trinkets by cooldown.
- **Bank access.** The client only exposes bank contents while a bank window is open, so a set referencing banked gear can't be resolved when you actually want it.
- **Anything outside Classic Era.**

---

## File structure

```
HelloGear/
├── HelloGear.toc
├── Core.lua            -- namespace, event dispatcher, API compat shims,
│                          slash commands, macro API
├── Config.lua          -- saved-variables schema, defaults, options panel
├── Items.lua           -- slot table, gear IDs, matching, inventory scanning
├── Sets.lua            -- set CRUD, save-from-worn, equipped tests
├── Equip.lua           -- the swap engine
├── Import.lua          -- ItemRack import and snapshotting
├── Menu.lua            -- the quick set menu (and shared popup chrome)
├── Minimap.lua         -- minimap button
├── Paperdoll.lua       -- everything attached to character-sheet slots:
│                          swap flyouts and the set-editing overlays
├── CharacterPanel.lua  -- the docked gear-set panel and its toggle button
└── Tests/              -- headless harnesses; not listed in the TOC
```

---

## Gear IDs

A gear ID is `itemID:enchantID:suffixID:uniqueID` — the subset of the item string that identifies a specific piece of Classic gear.

Everything else in the link is dropped deliberately:

- **Gem sockets** don't exist in Era.
- **The link level field** changes every time you level, which is why ItemRack carried a routine to rewrite stored IDs on the fly. Not storing it removes the problem.

`suffixID` is never ignored. *Bracers of the Owl* and *Bracers of the Eagle* share an itemID and differ only here, so a base-ID match would happily equip the wrong one. `uniqueID` is a per-instance seed, used only to tell two otherwise identical items apart.

### Matching

`Items.MatchScore(wanted, have)` returns:

| Score | Meaning |
|-------|---------|
| `3` | The same physical item |
| `2` | Same item, same enchant, different instance |
| `1` | Same item, different enchant |
| `nil` | Different items (including any suffix mismatch) |

The engine only moves an item into a slot when it can find a *strictly better* score than what's already there. This is what stops a set saved before you re-enchanted a weapon from reporting the weapon missing every time you equip it — the enchanted copy on your character scores 1, nothing in your bags beats it, so the slot is left alone.

### The three slot states

Each slot in a set is one of:

| State | Stored as | Meaning |
|-------|-----------|---------|
| Item | a gear ID | Wear this |
| Empty | `ns.EMPTY` (`0`) | Deliberately clear this slot |
| Ignored | absent | Not managed by this set |

The third one is what makes partial sets work — a set that only swaps your gloves leaves everything else alone. ItemRack used the same convention, including `0` for empty, so imports carry across unchanged.

---

## The swap engine

Swaps are cursor moves (`PickupContainerItem` → `PickupInventoryItem`) rather than `EquipItemByName`. Name-based equipping can't distinguish two copies of the same item, which is exactly the case that matters when one is enchanted and one isn't.

A swap is not instantaneous: the client locks both endpoints and completes the move a moment later. So the engine runs in **passes**:

1. Read worn gear and bags fresh.
2. Work out which slots still need something, and how good a match they currently hold.
3. For each, find the best unclaimed candidate; move it if it beats what's there.
4. Wait for the locks to clear, then go again.

A pass makes no assumptions about what an earlier pass achieved, so a move that silently fails is simply retried. Passes are driven by `ITEM_LOCK_CHANGED` and friends, plus a 0.2s ticker — events alone don't work, because a pass that can't move anything generates no events and would never wake up again. The job gives up after 15 passes or 8 seconds and reports what it couldn't do.

### Ordering

Within a pass, slots being **emptied** go first, so the bag space and body slots they free are available to the slots being filled. The rest run in ascending slot order, which puts the main hand (16) before the off hand (17) — that's what lets a one-hander displace a two-hander before the off-hand item goes on.

Two-handers get one explicit special case: if the set specifies a two-handed main hand but says nothing about the off hand, the engine clears the off hand itself rather than relying on the client to stow it. Same outcome when there's bag room, a clear error message when there isn't.

### Claiming

Two slots can want the same item — two rings, two trinkets, a set with the same weapon in both hands. A pass tracks claimed bag slots and claimed inventory slots so one item is never assigned twice, and items that already correctly satisfy a slot are claimed up front so they can't be yanked out to fill another.

Rings and trinkets that are simply in each other's slots are handled by a direct inventory-to-inventory move, so they never detour through a bag.

### In combat

Era permits gear swaps in combat, so the engine doesn't gate on it — no combat queue, no deferred swaps. `PLAYER_REGEN_ENABLED` is registered anyway, so a job that stalls mid-fight resumes when combat drops.

---

## The character-sheet integration

Set management lives on the character sheet rather than in a window of its own. A button inside the frame opens a panel docked to its right, and the paperdoll itself becomes the set editor.

**Why docked outside rather than inside.** Retail has a wide character frame with a dedicated right-hand column, which is where its equipment manager lives. Classic's frame has no such column — a panel inside it would cover the model and the slot buttons. Since the whole point is to click those slots while editing, the panel goes outside. The right edge is free in practice: CharacterStatsClassic overlays *inside* the frame, and DragonflightUI's own equipment manager only exists when DragonflightUI is enabled.

**Anchoring.** `CharacterFrame` is wider and taller than the frame you can see — its own edges sit in dead space, so anything anchored to them floats clear of the artwork. Measured on 1.15.9 via `/hg dock`: the frame spans 0..384 while the slot columns run 21..343.

Three references were tried, in this order:

1. **`CharacterFrame.NineSlice`** — its bounds *are* the visible frame, so anchoring to it would settle all three edges at once. Preferred when present; on 1.15.9 it isn't, despite the frame having modern chrome.
2. **Mirroring the slot columns' margin** — the left column sits 21px inside the frame, so assume the right column does too. Wrong: the margins aren't symmetric (the right is nearer 9), and it overshot by about ten pixels.
3. **`CharacterFrameCloseButton`** — Blizzard pins it to the artwork's top-right corner, so its own right and top edges sit a few pixels inside the frame's. This is what's used, and it gives the top edge as well as the right.

The bottom still comes from the tab row, which is the only thing pinned near the artwork's bottom edge.

That 20 isn't hardcoded — it's only the fallback. Both the button and the panel are placed from the paperdoll's own slot columns, which are laid out symmetrically inside the artwork: the left column's margin is also the right column's, so `right column's right edge + that margin` gives the artwork's edge. The button sits directly above the top slot of the right-hand column, sharing its right edge, and so inherits the frame's real margin for free.

The panel's *horizontal* position comes from that edge, but its *vertical* position has to come from the top of the frame rather than from a slot button most of the way down it — so it anchors to `CharacterFrame`'s `TOPLEFT` with a measured x, not to a slot.

Vertically it's the same problem at the other end: the frame runs past the artwork again, this time to leave room for the tab row. The tabs are the measurable thing — they sit across the artwork's bottom edge — so the panel anchors top *and* bottom and comes out exactly as tall as the character frame, tracking it rather than carrying a fixed height that would over- or under-shoot.

Two subtleties worth writing down:

- **Docking flush means overlapping.** The border is drawn ~11px inside the frame's bounds, so the panel's frame has to sit that much *inside* the artwork for the two drawn edges to meet. This cost two rounds on its own: the position arithmetic was right while the panel still looked detached, because a correct frame position with the wrong overlap looks exactly like a wrong frame position. `ns.CHROME_INSET` is the one number for it, and `/hg dock` prints enough to tell the two apart — if the computed corner matches the frame's real edge but there's still a gap, it's the overlap, not the position.
- **The panel is its own window, standing beside the character sheet.** Making it read as a *continuation* of the character frame was tried at length and abandoned. Matching that frame's border meant reusing its artwork — four texture quadrants on `PaperDollFrame`, no reusable template — and every route in brought something worse: whole quadrants carried the paperdoll's slot recesses and the hardware its tabs bolt onto into the middle of the panel; sliced strips sampled the wrong half of the texture file, because those regions carry texcoords of their own that `SetTexCoord` discards; a hand-drawn edge lost the bevel. Tucking the panel under the character frame's border to share a seam made it read as one oversized frame rather than two.

  What's here instead is the shared `ns.ApplyChrome` — the same border the quick menu and the flyouts use — over the dark fill, separated from the character frame by `PANEL_GAP`. It stands beside the character sheet the way the guild information window does. Its top and bottom track the artwork's, so it matches the character sheet's height, but nothing about it pretends to be part of that frame.
- **The scrollbar hangs outside its scroll frame.** `UIPanelScrollFrameTemplate` anchors the bar past the scroll frame's right edge, so a scroll frame sized to the full content width puts its scrollbar on the border — or outside the panel altogether. Every list gives up `SCROLLBAR_ROOM` for it, and hides the bar entirely when the list fits.

Measuring rather than hardcoding also means the panel docks correctly against a frame some other addon has resized, and it's re-measured on every `PaperDollFrame` show rather than once at login. The arithmetic is `Panel.ComputeArtInset`, kept free of frame lookups so `Tests/test_geometry.lua` can exercise it against the real measured numbers. `/hg dock` reports what the addon sees and `/hg dock <pixels>` shifts it, saved per account, for the case where the symmetry assumption doesn't hold on someone's setup.

The button is styled as a small action button (icon plus the `UI-Quickslot2` ring at Blizzard's 1.83x ratio) rather than a spellbook-style sidebar tab. That tab artwork is drawn to key into the spellbook frame's specific edge and looks out of place anywhere else.

**Why the overlays own the mouse while editing.** Clicking a paperdoll slot normally picks the item up, and that handler runs before any hook of ours sees the click. There's no way to hook it and cancel. So each slot carries a transparent overlay button that takes the mouse only when it should: while a modifier is held (for the swap flyout) or while a set is being edited. In edit mode the overlay also draws the set's item over the real one — retexturing the slot button itself would be undone by `PaperDollItemSlotButton_Update` on the next inventory event.

Edit mode is explicitly entered and exited rather than being implied by having a set selected. While it's on the swap arrows hide, so a click on a slot has exactly one meaning:

- **Left-click** opens the same flyout used for swapping, in *assign* mode — it writes the choice into the set instead of onto the character, and leads with a *No item* row. Reusing the flyout means picking a set's item and picking an item to wear right now look and behave the same.
- **Right-click** takes the slot in or out of the set.

The two are separate because "the set clears this slot" and "the set ignores this slot" are genuinely different, and a single cycling click made you tour through states you didn't want to reach the one you did. Splitting them also means neither gesture can put the set into a state you can't see the name of.

**Where the panel follows.** Switching to the Reputation or Skills tab leaves `CharacterFrame` shown but hides `PaperDollFrame`, so the panel hooks `PaperDollFrame` rather than its own parent. That hide is deliberately not recorded as "the user closed the panel", so it comes back when you switch to the paperdoll again.

**What didn't fit.** A 200px column has room for the set list and Equip/Save. Renaming, the icon, the helm/cloak toggles and the menu-visibility flag are all things you set once and never touch again, so they moved behind a gear button on each row.

Slot state and the edit cycle live in `Sets.lua`, not in the UI file, so they can be tested without a character sheet to click on.

---

## The ItemRack import

`ItemRackUser` is a per-character saved variable, so it only exists in memory when ItemRack itself is installed and enabled — and the point of this addon is that ItemRack is about to be turned off.

So the first time HelloGear sees it, it takes its own copy into `HelloGearCharDB.itemRackBackup`. After that the import keeps working with ItemRack deleted from disk. The snapshot is refreshed on every login where ItemRack is loaded, so it tracks any last-minute edits.

The alternative — declaring `ItemRackUser` in our own TOC — was rejected. It works, but it makes two addons owners of the same global, and a stale copy loading in the wrong order would overwrite real data.

**HelloGear never writes to `ItemRackUser`.**

What comes across: sets, per-slot items, deliberate empties, icons, helm/cloak flags, and the hidden-set list. What doesn't: ItemRack's `~`-prefixed internal scratch sets, its `old`/`oldset` undo state (HelloGear captures its own on equip), and its event and queue configuration, neither of which HelloGear implements.

---

## Testing

The pure-logic layers run headless. `Items.lua`, `Sets.lua`, `Equip.lua` and `Import.lua` touch the WoW API only through functions that can be stubbed, so both can be exercised with a stock `lua` binary:

```sh
lua Tests/test_equip.lua
lua Tests/test_geometry.lua
lua Tests/test_import.lua "<path to a WTF .../SavedVariables/ItemRack.lua>"
```

- **`test_import.lua`** loads a real ItemRack saved-variable file — it's valid Lua — and checks that every set round-trips to the same four fields, re-derived independently from the raw ItemRack strings. Also covers hidden flags, helm/cloak flags, `~`-prefixed internal sets being skipped, and import idempotency.
- **`test_geometry.lua`** checks the character-frame fitting arithmetic — stock layout, a moved frame, artwork that fills its frame, and the nonsense-in-fallback-out cases.
- **`test_equip.lua`** runs the real swap engine against a simulated character: worn slots, five bags, an item cursor, and client rules for two-handers, invalid slots and full bags. Covers ring cross-swaps, two-hander transitions in both directions, deliberate empties, enchant preference, random-suffix rejection, missing gear, toggle round-trips and full 15-slot swaps.

`Tests/` is not listed in the TOC, so the game never loads it.
