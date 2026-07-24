local ADDON_NAME, ns = ...

ns.Minimap = {}
local Minimap_ = ns.Minimap

local DEFAULT_ANGLE = 195  -- lower-left of the minimap, well clear of clock/zoom

local button

local function Store()
    return ns.Config:GetTable("minimap")
end

local function UpdatePosition()
    local angle = math.rad(Store().angle or DEFAULT_ANGLE)
    -- Anchor just outside the minimap edge, computed from the live minimap
    -- width so it adapts if another addon resizes the minimap.
    local r = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function DraggingUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    Store().angle = math.deg(math.atan2(py - my, px - mx))
    UpdatePosition()
end

function Minimap_:Init()
    button = CreateFrame("Button", "HelloGearMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Chest_Plate06")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", DraggingUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(self, click)
        if click == "RightButton" then
            ns.UI:Toggle()
        else
            ns.Menu:Toggle(self)
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("HelloGear", 1, 1, 1)
        local current = HelloGearCharDB and HelloGearCharDB.currentSet
        if current and ns.Sets:Get(current) then
            GameTooltip:AddDoubleLine("Current set", current, 0.7, 0.7, 0.7, 0.5, 1, 0.5)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click for the set menu", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click to manage sets", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Drag to move", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    UpdatePosition()
    self:ApplyVisibility()
end

function Minimap_:ApplyVisibility()
    if button then button:SetShown(not Store().hide) end
end

function Minimap_:GetButton()
    return button
end
