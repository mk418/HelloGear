-- luacheck configuration for HelloGear (World of Warcraft Classic Era addon).
-- WoW runs on Lua 5.1. From the addon root, run:  luacheck .

std = "lua51"

max_line_length = false
unused_args = false

-- Headless harnesses; they stub the WoW API, so every global is "undefined"
-- by this config's standards. Run them with `lua Tests/<file>` instead.
exclude_files = { "Tests/" }

ignore = {
    "211/ADDON_NAME",  -- `local ADDON_NAME, ns = ...` idiom; name unused in most files
    "432/self",        -- inner callbacks (OnClick/OnDragStart/...) take their own `self`
}

-- True globals this addon owns or mutates. Everything else lives on the `ns`
-- table threaded in via `local ADDON_NAME, ns = ...`.
globals = {
    "HelloGearDB",           -- SavedVariables
    "HelloGearCharDB",       -- SavedVariablesPerCharacter
    "HelloGear",             -- macro API table
    "SlashCmdList",
    "SLASH_HELLOGEAR1",
    "SLASH_HELLOGEAR2",
    "StaticPopupDialogs",
    "UISpecialFrames",
    -- Macro-compatibility globals adopted from ItemRack, only when unclaimed
    "EquipSet",
    "UnequipSet",
    "ToggleSet",
    "IsSetEquipped",
    -- Another addon's saved variable. Read only - see Import.lua.
    "ItemRackUser",
    -- Binding display names and the macro-API globals are installed through _G
    "_G",
}

-- WoW Classic Era API surface used by the addon.
read_globals = {
    -- Frames / UI
    "CreateFrame",
    "UIParent",
    "Minimap",
    "CharacterFrame",
    "CharacterFrameCloseButton",
    "CharacterFrameTab1",
    "PaperDollFrame",
    "ToggleCharacter",
    "GameTooltip",
    "GameTooltip_Hide",
    "DEFAULT_CHAT_FRAME",
    "Settings",
    "ReloadUI",
    "InCombatLockdown",
    "StaticPopup_Show",
    "ITEM_QUALITY_COLORS",
    "GetMacroIcons",
    "GetNumMacroIcons",
    "GetMacroIconInfo",
    "ACCEPT", "CANCEL", "YES", "NO", "DELETE", "SAVE", "EQUIPSET_EQUIP",
    "unpack",
    "C_Timer",
    "C_CVar",
    "SetCVar",
    -- Items and containers
    "C_Item",
    "C_Container",
    "GetItemInfo",
    "GetItemInfoInstant",
    "NUM_BAG_SLOTS",
    "NUM_BANKBAGSLOTS",
    -- Inventory
    "GetInventorySlotInfo",
    "GetInventoryItemLink",
    "GetInventoryItemID",
    "IsInventoryItemLocked",
    "GetInventoryItemCooldown",
    "PickupInventoryItem",
    -- Cursor
    "CursorHasItem",
    "ClearCursor",
    "GetCursorInfo",
    "GetCursorPosition",
    "SpellIsTargeting",
    -- Player state
    "UnitLevel",
    "UnitIsDeadOrGhost",
    "CanDualWield",
    "GetTime",
    "IsShiftKeyDown",
    "IsControlKeyDown",
    "IsAltKeyDown",
    "wipe",
    "tinsert",
}
