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
- **Set manager** — window with the set list, a 20-slot grid, and the cosmetic toggles.
- **Paperdoll slot menus** — every character-sheet slot gets a menu of the alternatives in your bags, with cooldown swirls.
- **Key bindings** — six assignable set slots plus a menu toggle.
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
├── Bindings.xml        -- key bindings (auto-loaded by WoW)
├── Core.lua            -- namespace, event dispatcher, API compat shims,
│                          slash commands, macro API, BINDING_NAME globals
├── Config.lua          -- saved-variables schema, defaults, options panel
├── Items.lua           -- slot table, gear IDs, matching, inventory scanning
├── Sets.lua            -- set CRUD, save-from-worn, equipped tests
├── Equip.lua           -- the swap engine
├── Import.lua          -- ItemRack import and snapshotting
├── Menu.lua            -- the quick set menu (and shared popup chrome)
├── Minimap.lua         -- minimap button
├── SlotMenus.lua       -- character-sheet slot flyouts
├── UI.lua              -- set manager window
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
lua Tests/test_import.lua "<path to a WTF .../SavedVariables/ItemRack.lua>"
```

- **`test_import.lua`** loads a real ItemRack saved-variable file — it's valid Lua — and checks that every set round-trips to the same four fields, re-derived independently from the raw ItemRack strings. Also covers hidden flags, helm/cloak flags, `~`-prefixed internal sets being skipped, and import idempotency.
- **`test_equip.lua`** runs the real swap engine against a simulated character: worn slots, five bags, an item cursor, and client rules for two-handers, invalid slots and full bags. Covers ring cross-swaps, two-hander transitions in both directions, deliberate empties, enchant preference, random-suffix rejection, missing gear, toggle round-trips and full 15-slot swaps.

`Tests/` is not listed in the TOC, so the game never loads it.
