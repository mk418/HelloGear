local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.1.0"

-- Sentinel stored in a set's equip table to mean "this slot must be empty",
-- as opposed to nil which means "leave whatever is in this slot alone".
-- Numeric 0 matches ItemRack's convention, so imported sets carry over as-is.
ns.EMPTY = 0

local PREFIX = "|cff80ff80HelloGear|r "

function ns:Print(fmt, ...)
    if select("#", ...) > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. fmt:format(...))
    else
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(fmt))
    end
end

-- 1.15.9 moved Classic Era onto the modern shared UI codebase. Several
-- globals this addon would otherwise reach for are gone there (ShowHelm and
-- ShowCloak most notably - calling them unguarded is what broke ItemRack's
-- EquipSet). Everything version-sensitive is resolved once, here.
ns.API = {}
ns.API.GetItemInfo         = (C_Item and C_Item.GetItemInfo) or GetItemInfo
ns.API.GetItemInfoInstant  = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
ns.API.GetItemCooldown     = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
ns.API.GetItemCount        = (C_Item and C_Item.GetItemCount) or GetItemCount
ns.API.SetCVar             = (C_CVar and C_CVar.SetCVar) or SetCVar

-- ShowHelm()/ShowCloak() no longer exist; the CVars behind them still do.
function ns.API.SetShowHelm(show)
    pcall(ns.API.SetCVar, "showHelm", show and "1" or "0")
end

function ns.API.SetShowCloak(show)
    pcall(ns.API.SetCVar, "showCloak", show and "1" or "0")
end

ns.eventFrame = CreateFrame("Frame")
ns.eventHandlers = {}

ns.eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handlers = ns.eventHandlers[event]
    if not handlers then return end
    for i = 1, #handlers do
        handlers[i](...)
    end
end)

function ns:On(event, fn)
    if not ns.eventHandlers[event] then
        ns.eventHandlers[event] = {}
        ns.eventFrame:RegisterEvent(event)
    end
    table.insert(ns.eventHandlers[event], fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    ns.Config:Init()
end)

ns:On("PLAYER_LOGIN", function()
    ns.Sets:Init()
    ns.Equip:Init()
    ns.Menu:Init()
    ns.Minimap:Init()
    ns.Paperdoll:Init()
    ns.Panel:Init()
    ns.Config:CreatePanel()
    -- ItemRack's saved variables only exist once ItemRack itself has loaded,
    -- which is after us (addons load alphabetically). PLAYER_LOGIN is the
    -- first point where we can reliably see them.
    ns.Import:OnLogin()
end)

--------------------------------------------------------------------------
-- Macro API
--
-- ItemRack defined bare globals for macro use. Existing macros say things
-- like /script EquipSet("Tank"), so we adopt those names - but only if
-- nothing else has claimed them, so a still-installed ItemRack keeps its own.
--------------------------------------------------------------------------

HelloGear = {}
function HelloGear.EquipSet(name)     return ns.Equip:EquipSet(name) end
function HelloGear.UnequipSet(name)   return ns.Equip:UnequipSet(name) end
function HelloGear.ToggleSet(name)    return ns.Equip:ToggleSet(name) end
function HelloGear.IsSetEquipped(name, exact) return ns.Sets:IsEquipped(name, exact) end
function HelloGear.GetSetNames()      return ns.Sets:Names() end

ns:On("PLAYER_LOGIN", function()
    if not ns.Config:Get("legacyGlobals") then return end
    if _G.EquipSet == nil then _G.EquipSet = HelloGear.EquipSet end
    if _G.UnequipSet == nil then _G.UnequipSet = HelloGear.UnequipSet end
    if _G.ToggleSet == nil then _G.ToggleSet = HelloGear.ToggleSet end
    if _G.IsSetEquipped == nil then _G.IsSetEquipped = HelloGear.IsSetEquipped end
end)

--------------------------------------------------------------------------
-- Key bindings
--
-- Equipping gear is not a protected action in Classic Era, so bindings can
-- call straight into Lua - no secure button indirection needed. Which set
-- each numbered binding equips is assigned with /hg bind.
--------------------------------------------------------------------------

_G.BINDING_HEADER_HELLOGEAR = "HelloGear"
for i = 1, 6 do
    _G["BINDING_NAME_HELLOGEAR_SET" .. i] = "Equip assigned set " .. i
end
_G.BINDING_NAME_HELLOGEAR_MENU = "Open set menu"

function HelloGear.ToggleMenu()
    ns.Menu:Toggle(ns.Minimap:GetButton())
end

function HelloGear.EquipBoundSet(index)
    local name = ns.Config:GetCharTable("bindings")[index]
    if not name then
        ns:Print("no set assigned to binding %d - use /hg bind %d <set>", index, index)
        return
    end
    ns.Equip:EquipSet(name)
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local usage = {
    "commands:",
    "  /hg                     - open the set menu",
    "  /hg equip <set>         - equip a set",
    "  /hg toggle <set>        - equip a set, or put back what it replaced",
    "  /hg unequip <set>       - put back what the set replaced",
    "  /hg save <set>          - save currently worn gear as <set>",
    "  /hg delete <set>        - delete a set",
    "  /hg list                - list sets",
    "  /hg manage              - open the gear set panel on the character sheet",
    "  /hg import [force]      - import sets from ItemRack",
    "  /hg bind <1-6> <set>    - assign a set to a key binding",
    "  /hg config              - open the options panel",
    "  /hg reset               - wipe all HelloGear data and reload",
}

SLASH_HELLOGEAR1 = "/hg"
SLASH_HELLOGEAR2 = "/hellogear"
SlashCmdList["HELLOGEAR"] = function(msg)
    msg = trim(msg or "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    rest = trim(rest or "")

    if cmd == "" then
        ns.Menu:Toggle()
    elseif cmd == "equip" then
        ns.Equip:EquipSet(rest)
    elseif cmd == "toggle" then
        ns.Equip:ToggleSet(rest)
    elseif cmd == "unequip" then
        ns.Equip:UnequipSet(rest)
    elseif cmd == "save" then
        if rest == "" then
            ns:Print("usage: /hg save <set>")
        else
            ns.Sets:SaveFromWorn(rest)
            ns:Print('saved worn gear as "%s"', rest)
            ns.Panel:Refresh()
        end
    elseif cmd == "delete" then
        if ns.Sets:Delete(rest) then
            ns:Print('deleted "%s"', rest)
            ns.Panel:Refresh()
        else
            ns:Print('no set named "%s"', rest)
        end
    elseif cmd == "list" then
        local names = ns.Sets:Names()
        if #names == 0 then
            ns:Print("no sets yet - /hg save <name> or /hg import")
        else
            ns:Print("%d set(s):", #names)
            for _, name in ipairs(names) do
                local mark = ns.Sets:IsEquipped(name) and "|cff80ff80*|r " or "  "
                DEFAULT_CHAT_FRAME:AddMessage(mark .. name)
            end
        end
    elseif cmd == "manage" then
        ns.Panel:Toggle()
    elseif cmd == "import" then
        ns.Import:Run(rest:lower() == "force")
    elseif cmd == "bind" then
        local index, name = rest:match("^(%d)%s+(.+)$")
        index = tonumber(index)
        if not index or index < 1 or index > 6 then
            ns:Print("usage: /hg bind <1-6> <set>")
        elseif not ns.Sets:Get(name) then
            ns:Print('no set named "%s"', name)
        else
            ns.Config:GetCharTable("bindings")[index] = name
            ns:Print('binding %d equips "%s" (assign a key in Esc -> Key Bindings -> HelloGear)', index, name)
        end
    elseif cmd == "config" then
        ns.Config:OpenPanel()
    elseif cmd == "reset" then
        HelloGearDB = nil
        HelloGearCharDB = nil
        ReloadUI()
    else
        for _, line in ipairs(usage) do ns:Print(line) end
    end
end
