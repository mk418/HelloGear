# HelloGear

A gear set manager for WoW Classic Era, built to replace [ItemRack](https://www.curseforge.com/wow/addons/itemrack) — which throws on client 1.15.9 whenever you equip a set with a helm or cloak visibility flag, because the `ShowHelm()` and `ShowCloak()` globals it calls no longer exist.

Your ItemRack sets import in one click.

> **Heads up** — this is a personal work in progress. I build and evolve it as I play using it, so features land when I need them and design choices reflect my play style.

## Getting started

1. Drop `HelloGear` into `Interface/AddOns`.
2. Log in **once with ItemRack still enabled** so HelloGear can snapshot your sets.
3. Accept the import prompt, or run `/hg import`.
4. Disable ItemRack.

Step 2 matters: ItemRack's sets live in *its* saved variables, which only load when ItemRack does. HelloGear keeps its own copy from then on, so the import still works after you've deleted ItemRack entirely.

## Using it

- **Minimap button** — click for the set menu, right-click for the set manager.
- **In the menu** — click a set to equip it, shift-click to toggle it, right-click to put back what it replaced. Right-click *Manage sets* to reveal sets marked hidden.
- **Character sheet** — every slot gets a small arrow opening a list of the alternatives in your bags. Alt-click a slot does the same thing.
- **Set manager** — the slot grid shows what each set manages. Click a slot to record what you're wearing, right-click to cycle it between *worn item*, *clear this slot*, and *leave alone*.

Sets are per character. A set only touches the slots it manages, so a one-slot set — swap in the disarm-resist gloves, put on the fire resist cloak — leaves the rest of your gear alone, and toggling it off restores exactly what it displaced.

## Commands

```
/hg                      open the set menu
/hg equip <set>          equip a set
/hg toggle <set>         equip a set, or put back what it replaced
/hg unequip <set>        put back what the set replaced
/hg save <set>           save currently worn gear as <set>
/hg delete <set>         delete a set
/hg list                 list sets
/hg manage               open the set manager
/hg import [force]       import sets from ItemRack
/hg bind <1-6> <set>     assign a set to a key binding
/hg config               open the options panel
/hg reset                wipe all HelloGear data and reload
```

Key bindings live under Esc → Key Bindings → HelloGear. Assign sets to the six numbered bindings with `/hg bind`.

## Macros

```lua
/script HelloGear.EquipSet("Tank")
/script HelloGear.ToggleSet("Fire resistance")
```

ItemRack's bare globals — `EquipSet`, `UnequipSet`, `ToggleSet`, `IsSetEquipped` — are also defined, so existing macros keep working. HelloGear only claims a name nothing else has taken, and you can turn this off in the options.

## What it doesn't do

ItemRack's automatic set switching (on stance, zone, buff or mount) and its cooldown-based trinket queues are deliberately absent. See [DESIGN.md](DESIGN.md).

Bank contents aren't reachable — the client only exposes them while a bank window is open — so sets can only use gear you're carrying or wearing.

## Caveats

- Only works on Classic Era, no support for other game versions.

## License

Released under the [MIT License](LICENSE).
