-- ItemRack Forever: data broker and minimap button. The minimap button keeps the stock
-- gold ring look (31x31, icon 20x20, tracking border, zoom highlight).
-- Registered as "ItemRack", the name ItemRack used: its saved position carries over.
local _, ns = ...
local L = ns.L

local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

local function stockLook()
  local button = LDBIcon:GetMinimapButton("ItemRack")
  if not button then return end
  button:SetSize(31, 31)
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  if button.border then
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border:SetSize(53, 53)
    button.border:ClearAllPoints()
    button.border:SetPoint("TOPLEFT", 0, 0)
  end
  if button.icon then
    button.icon:SetSize(20, 20)
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", 7, -5)
  end
end

function ItemRack.InitBroker()
  ItemRack.Broker = LDB:NewDataObject("ItemRack", {
    type = "launcher",
    text = "ItemRack",
    icon = ItemRack.ICON,
    OnClick = ItemRack.MinimapOnClick,
    OnTooltipShow = ItemRack.MinimapOnEnter,
  })
  ItemRackSettings.minimap = ItemRackSettings.minimap or { hide = false }
  LDBIcon:Register("ItemRack", ItemRack.Broker, ItemRackSettings.minimap)
  stockLook()
  ItemRack.ShowMinimap()
  ItemRack.UpdateCurrentSet()
end

function ItemRack.ShowMinimap()
  if ItemRackSettings.ShowMinimap == "ON" then
    ItemRackSettings.minimap.hide = false
    LDBIcon:Show("ItemRack")
  else
    ItemRackSettings.minimap.hide = true
    LDBIcon:Hide("ItemRack")
  end
end

-- left: sets menu, right: options, Shift: unequip the current set,
-- Alt+right: events on/off (Alt+left: the menu with hidden sets)
function ItemRack.MinimapOnClick(self, button)
  if IsShiftKeyDown() then
    if ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet] then
      ItemRack.UnequipSet(ItemRackUser.CurrentSet)
    end
  elseif IsAltKeyDown() and (button == "RightButton" or ItemRackSettings.AllowHidden == "OFF") then
    ItemRack.ToggleEvents()
  elseif button == "LeftButton" then
    if ItemRackMenuFrame:IsVisible() and ItemRack.menuOpen == 20 then
      ItemRackMenuFrame:Hide()
    else
      local _, y = GetCursorPosition()
      if y / (UIParent:GetEffectiveScale() or 1) > UIParent:GetHeight() / 2 then
        ItemRack.DockWindows("TOPRIGHT", self, "BOTTOMRIGHT", "VERTICAL")
      else
        ItemRack.DockWindows("BOTTOMRIGHT", self, "TOPRIGHT", "VERTICAL")
      end
      ItemRack.BuildMenu(20)
    end
  else
    ItemRack.ToggleOptions()
  end
end

function ItemRack.MinimapOnEnter(tooltip)
  if ItemRackSettings.MinimapTooltip ~= "ON" then return end
  tooltip:AddLine("ItemRack", 0.95, 0.77, 0.36)
  local current = ItemRackUser.CurrentSet
  if current and ItemRackUser.Sets[current] and ItemRack.IsSetEquipped(current) then
    tooltip:AddDoubleLine(L["Current set:"], current, .8, .8, .8, 1, 1, 1)
  end
  tooltip:AddDoubleLine(L["Events:"], ItemRackUser.EnableEvents == "ON" and L["On"] or L["Off"], .8, .8, .8, 1, 1, 1)
  tooltip:AddLine(" ")
  tooltip:AddLine(L["Left click: Select a set"], .8, .8, .8, 1)
  tooltip:AddLine(L["Right click: Open options"], .8, .8, .8, 1)
  tooltip:AddLine(L["Alt left click: Show hidden sets"], .8, .8, .8, 1)
  tooltip:AddLine(L["Alt right click: Toggle events"], .8, .8, .8, 1)
  tooltip:AddLine(L["Shift click: Unequip this set"], .8, .8, .8, 1)
end
