-- ItemRack Forever: the popout menu (items for a slot, or the sets), its docking, the
-- small control menu (lock, queue, options, remove), tooltips, character sheet menus.
local _, ns = ...
local L = ns.L
local S = ns.Skin
local C = S.C
local API = ns.API
local GetItemInfo, GetContainerNumSlots, GetContainerItemLink, GetContainerItemCooldown, GetItemCooldown, PickupContainerItem =
  API.GetItemInfo, API.GetContainerNumSlots, API.GetContainerItemLink, API.GetContainerItemCooldown, API.GetItemCooldown, API.PickupContainerItem

local SIZE, STEP = 36, 40 -- menu buttons and their spacing

-- The menu frame: a tooltip backdrop; borderless and click-through when locked ----------
local menu = CreateFrame("Frame", "ItemRackMenuFrame", UIParent)
menu:SetSize(64, 64)
menu:SetFrameStrata("HIGH")
menu:SetMovable(true)
menu:SetClampedToScreen(true)
menu:SetToplevel(true)
menu:Hide()
S.Backdrop(menu, "menu", 0.3)
menu:SetScript("OnHide", function() ItemRack.MenuOnHide() end)

function ItemRack.HideMenu()
  menu:Hide()
end

-- The control menu: lock, queue, options, remove ---------------------------------------
local controls = CreateFrame("Frame", "ItemRackButtonMenu", menu)
controls:SetSize(SIZE, SIZE)
controls:Hide()
do
  -- tip: a function giving the tooltip (looked up on hover: the language is set later)
  local function control(name, glyph, point, x, y, tip)
    local b = S.GlyphButton(controls, glyph, 16, function(self) ItemRack.ButtonMenuOnClick(self) end)
    b:SetPoint(point, x, y)
    _G[name] = b
    S.Tooltip(b, tip)
    return b
  end
  control("ItemRackButtonMenuLock", "Lock", "TOPLEFT", 1, -1, function() return L["Lock Buttons"],
    L["Toggle locked state to prevent buttons/menus from moving and to hide borders and control buttons.\n\nHold ALT while you open a menu to access these control buttons while locked."] end)
  control("ItemRackButtonMenuQueue", "Cog", "TOPRIGHT", -1, -1, function() return L["Auto Queue"],
    L["Set up the auto queue for this slot.\n\nAlt+click the slot this menu opened from to toggle its auto queue on/off."] end)
  control("ItemRackButtonMenuOptions", "Sliders", "BOTTOMLEFT", 1, 1, function() return L["Options"],
    L["Open Options window to change settings, configure sets or auto queues."] end)
  control("ItemRackButtonMenuClose", "Cross", "BOTTOMRIGHT", -1, 1, function() return L["Remove"],
    L["Remove the slot this menu opened from."] end)
end

function ItemRack.ButtonMenuOnClick(self)
  local open = ItemRack.menuOpen
  if self == ItemRackButtonMenuClose then
    ItemRack.RemoveButton(open)
  elseif self == ItemRackButtonMenuOptions then
    ItemRack.ToggleOptions()
  elseif self == ItemRackButtonMenuLock then
    ItemRackUser.Locked = ItemRackUser.Locked == "ON" and "OFF" or "ON"
    ItemRack.ReflectLock()
    ItemRack.OptOnSettingsChanged()
  elseif self == ItemRackButtonMenuQueue then
    if open and open < 20 then
      ItemRack.ToggleOptions(nil, 4, open)
    else
      ItemRack.ToggleOptions(nil, 3)
    end
  end
end

function ItemRack.InitMenu()
  menu:SetScript("OnMouseDown", ItemRack.MenuFrameOnMouseDown)
  menu:SetScript("OnMouseUp", ItemRack.MenuFrameOnMouseUp)
  ItemRack.ReflectMenuScale()
end

-- Docking the menu --------------------------------------------------------------------
-- menuDock: corner of the menu, mainDock: corner of relativeTo; movable: button id, when
-- the menu can be docked elsewhere by dragging it
function ItemRack.DockWindows(menuDock, relativeTo, mainDock, menuOrient, movable)
  local key = mainDock .. menuDock
  local info = ItemRack.DockInfo[key]
  if not info then
    mainDock, menuDock, key = "TOPLEFT", "BOTTOMLEFT", "TOPLEFTBOTTOMLEFT"
    info = ItemRack.DockInfo[key]
  end
  menu:ClearAllPoints()
  ItemRack.currentDock = key
  menu:SetPoint(menuDock, relativeTo, mainDock, info.xoff, info.yoff)
  menu:SetParent(relativeTo)
  menu:SetFrameStrata("HIGH")
  ItemRack.mainDock = mainDock
  ItemRack.menuDock = menuDock
  ItemRack.menuOrient = menuOrient
  ItemRack.menuMovable = movable
  local name = relativeTo:GetName()
  ItemRack.menuDockedTo = name
  if name then ItemRack.MenuMouseoverFrames[name] = 1 end
  ItemRack.ReflectLock(not movable)
  ItemRack.ReflectMenuScale()
end

function ItemRack.DockMenuToButton(button)
  if (button == 13 or button == 14) and ItemRackSettings.TrinketMenuMode == "ON" and ItemRackUser.Buttons[13] and ItemRackUser.Buttons[14] then
    button = 13 + (ItemRackSettings.AnchorOther == "ON" and 1 or 0)
  end
  local parent = ItemRackUser.Buttons[ItemRack.FindParent(button)] or {}
  ItemRack.DockWindows(parent.MenuDock or "BOTTOMLEFT", _G["ItemRackButton" .. button], parent.MainDock or "TOPLEFT", parent.MenuOrient or "VERTICAL", button)
end

-- drag the menu (unlocked) around its button to dock it on another side; right-click it to
-- switch between vertical and horizontal
function ItemRack.MenuFrameOnMouseDown(self, button)
  if button == "LeftButton" and ItemRack.menuMovable then
    ItemRack.MenuDockingTo = ItemRack.menuMovable
    for i in pairs(ItemRackUser.Buttons) do
      if i ~= ItemRack.MenuDockingTo then
        _G["ItemRackButton" .. i]:SetAlpha(ItemRackUser.Alpha / 3)
      end
    end
    menu:StartMoving()
    ItemRack.StartTimer("MenuDocking")
  end
end

function ItemRack.MenuFrameOnMouseUp(self, button)
  if button == "LeftButton" and ItemRack.MenuDockingTo then
    ItemRack.StopTimer("MenuDocking")
    for i in pairs(ItemRackUser.Buttons) do
      _G["ItemRackButton" .. i]:SetAlpha(ItemRackUser.Alpha)
    end
    menu:StopMovingOrSizing()
    local parent = ItemRackUser.Buttons[ItemRack.FindParent(ItemRack.MenuDockingTo)]
    if parent then
      parent.MenuDock = ItemRack.menuDock
      parent.MainDock = ItemRack.mainDock
    end
    ItemRack.DockMenuToButton(ItemRack.MenuDockingTo)
    ItemRack.BuildMenu()
    ItemRack.MenuDockingTo = nil
    ItemRack.HideBrackets()
  elseif button == "RightButton" and ItemRack.menuMovable then
    local parent = ItemRackUser.Buttons[ItemRack.FindParent(ItemRack.menuMovable)]
    if parent then
      parent.MenuOrient = (parent.MenuOrient or "VERTICAL") == "VERTICAL" and "HORIZONTAL" or "VERTICAL"
      ItemRack.DockMenuToButton(ItemRack.menuMovable)
      ItemRack.BuildMenu()
    end
  end
end

function ItemRack.MenuDocking()
  local main = _G["ItemRackButton" .. (ItemRack.MenuDockingTo or 0)]
  if not ItemRack.MenuDockingTo or not main then return end
  local ms, ns_ = main:GetEffectiveScale(), menu:GetEffectiveScale()
  local near = ItemRack.Near
  local mL, mR, mT, mB = main:GetLeft() * ms, main:GetRight() * ms, main:GetTop() * ms, main:GetBottom() * ms
  local nL, nR, nT, nB = menu:GetLeft() * ns_, menu:GetRight() * ns_, menu:GetTop() * ns_, menu:GetBottom() * ns_
  if near(mR, nL) then
    if near(mT, nT) then ItemRack.mainDock, ItemRack.menuDock = "TOPRIGHT", "TOPLEFT"
    elseif near(mB, nB) then ItemRack.mainDock, ItemRack.menuDock = "BOTTOMRIGHT", "BOTTOMLEFT" end
  elseif near(mL, nR) then
    if near(mT, nT) then ItemRack.mainDock, ItemRack.menuDock = "TOPLEFT", "TOPRIGHT"
    elseif near(mB, nB) then ItemRack.mainDock, ItemRack.menuDock = "BOTTOMLEFT", "BOTTOMRIGHT" end
  elseif near(mR, nR) then
    if near(mT, nB) then ItemRack.mainDock, ItemRack.menuDock = "TOPRIGHT", "BOTTOMRIGHT"
    elseif near(mB, nT) then ItemRack.mainDock, ItemRack.menuDock = "BOTTOMRIGHT", "TOPRIGHT" end
  elseif near(mL, nL) then
    if near(mT, nB) then ItemRack.mainDock, ItemRack.menuDock = "TOPLEFT", "BOTTOMLEFT"
    elseif near(mB, nT) then ItemRack.mainDock, ItemRack.menuDock = "BOTTOMLEFT", "TOPLEFT" end
  end
  ItemRack.MoveBracket("Main", ItemRack.mainDock, main, ItemRack.mainDock)
  ItemRack.MoveBracket("Menu", ItemRack.menuDock, menu, ItemRack.menuDock)
end

-- Building the menu ----------------------------------------------------------------------
function ItemRack.AlreadyInMenu(id)
  for i = 1, #ItemRack.Menu do
    if ItemRack.Menu[i] == id then return 1 end
  end
end

function ItemRack.AddToMenu(itemID)
  if ItemRackSettings.AllowHidden == "OFF" or IsAltKeyDown() or not ItemRack.IsHidden(itemID) then
    table.insert(ItemRack.Menu, itemID)
  end
end

local function addBag(id, bag)
  for j = 1, GetContainerNumSlots(bag) do
    local itemID = ItemRack.GetID(bag, j)
    if itemID ~= 0 then
      local _, _, equipSlot = ItemRack.GetInfoByID(itemID)
      if equipSlot and ItemRack.SlotInfo[id][equipSlot] and ItemRack.PlayerCanWear(id, bag, j)
        and (ItemRackSettings.HideTradables == "OFF" or ItemRack.IsSoulbound(bag, j))
        and (id ~= 0 or not ItemRack.AlreadyInMenu(itemID)) then
        ItemRack.AddToMenu(itemID)
      end
    end
  end
end

-- id: 0-19 a slot, 20 the sets, nil = rebuild the last one. Call DockWindows first.
-- menuInclude: the worn item(s) are listed too (the options' paperdoll uses it)
function ItemRack.BuildMenu(id, menuInclude)
  if id then
    ItemRack.menuOpen = id
    ItemRack.menuInclude = menuInclude
  else
    id = ItemRack.menuOpen
    menuInclude = ItemRack.menuInclude
  end
  if not id or not ItemRack.currentDock then return end

  local showControls = ItemRack.menuMovable and (IsAltKeyDown() or ItemRackUser.Locked == "OFF")
  wipe(ItemRack.Menu)

  if id < 20 then
    if menuInclude then
      local worn = ItemRack.GetID(id)
      if worn ~= 0 then ItemRack.AddToMenu(worn) end
      local other = ItemRack.SlotInfo[id].other
      if other then
        worn = ItemRack.GetID(other)
        if worn ~= 0 then ItemRack.AddToMenu(worn) end
      end
    end
    for bag = 0, 4 do addBag(id, bag) end
    if ItemRack.BankOpen then
      for _, bag in pairs(ItemRack.BankSlots) do addBag(id, bag) end
    elseif ItemRack.GetID(id) ~= 0 and ItemRackSettings.AllowEmpty == "ON" then
      table.insert(ItemRack.Menu, 0)
    end
  else
    for name, set in pairs(ItemRackUser.Sets) do
      if not name:match("^~") then ItemRack.AddToMenu(name) end
    end
    table.sort(ItemRack.Menu)
  end
  if showControls then table.insert(ItemRack.Menu, "MENU") end

  local count = #ItemRack.Menu
  if count < 1 then
    menu:Hide()
    return
  end

  local dock = ItemRack.DockInfo[ItemRack.currentDock]
  local maxCols = 1
  if ItemRackUser.SetMenuWrap == "ON" then
    maxCols = math.max(1, math.floor(tonumber(ItemRackUser.SetMenuWrapValue) or 3))
  elseif count > 24 then maxCols = 5
  elseif count > 18 then maxCols = 4
  elseif count > 9 then maxCols = 3
  elseif count > 4 then maxCols = 2
  end

  local col, row, x, y = 0, 0, dock.xstart, dock.ystart
  for i = 1, count do
    local button = ItemRack.CreateMenuButton(i, ItemRack.Menu[i]) or controls
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", menu, ItemRack.menuDock, x, y)
    button:SetFrameLevel(menu:GetFrameLevel() + 2)
    if ItemRack.menuOrient == "VERTICAL" then
      x = x + dock.xdir * STEP
      col = col + 1
      if col == maxCols then
        x, col = dock.xstart, 0
        y = y + dock.ydir * STEP
        row = row + 1
      end
    else
      y = y + dock.ydir * STEP
      col = col + 1
      if col == maxCols then
        y, col = dock.ystart, 0
        x = x + dock.xdir * STEP
        row = row + 1
      end
    end
    button:Show()
    local icon = _G["ItemRackMenu" .. i .. "Icon"]
    if icon and button ~= controls then
      icon:SetDesaturated(IsAltKeyDown() and ItemRackSettings.AllowHidden == "ON" and ItemRack.IsHidden(ItemRack.Menu[i]) and true or false)
    end
  end
  if showControls then
    table.remove(ItemRack.Menu)
  else
    controls:Hide()
  end
  local i = #ItemRack.Menu + 1
  while _G["ItemRackMenu" .. i] do
    _G["ItemRackMenu" .. i]:Hide()
    i = i + 1
  end
  if col == 0 then row = row - 1 end

  local cols, rows = maxCols, row + 1
  if ItemRack.menuOrient == "VERTICAL" then
    menu:SetSize(12 + cols * STEP, 12 + rows * STEP)
  else
    menu:SetSize(12 + rows * STEP, 12 + cols * STEP)
  end

  ItemRack.StartTimer("MenuMouseover")
  menu:SetAlpha(ItemRackUser.Alpha or 1)
  menu:Show()
  ItemRack.UpdateMenuCooldowns()

  for i = 1, #ItemRack.Menu do
    local b, item = _G["ItemRackMenu" .. i], ItemRack.Menu[i]
    local state
    if id == 20 then
      _G["ItemRackMenu" .. i .. "Name"]:SetText(item)
      local missing = ItemRack.MissingItems(item)
      if missing == 0 then state = C.bad elseif missing == 1 then state = C.bank end
      b.isCurrent = ItemRackUser.CurrentSet == item and ItemRack.IsSetEquipped(item)
    else
      _G["ItemRackMenu" .. i .. "Name"]:SetText("")
      if item ~= 0 and ItemRack.GetCountByID(item) == 0 then state = C.bank end
      b.isCurrent = nil
    end
    b:SetStateBorder(state)
    b.current:SetShown(b.isCurrent and true or false)
    if id == 0 then
      local n = ItemRack.GetCountByID(item)
      _G["ItemRackMenu" .. i .. "Count"]:SetText(n > 0 and n or "")
    else
      _G["ItemRackMenu" .. i .. "Count"]:SetText("")
    end
  end
end

function ItemRack.CreateMenuButton(idx, itemID)
  if itemID == "MENU" then return end
  local name = "ItemRackMenu" .. idx
  local button = _G[name]
  if not button then
    button = CreateFrame("CheckButton", name, menu)
    button:SetSize(SIZE, SIZE)
    button:SetID(idx)
    button:SetFrameStrata("HIGH")
    ItemRack.CreateItemParts(button, name)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", ItemRack.MenuOnClick)
    button:HookScript("OnEnter", ItemRack.MenuTooltip)
    button:HookScript("OnLeave", ItemRack.ClearTooltip)
    -- the set worn now: lit like a checked action button
    local current = button:CreateTexture(nil, "OVERLAY")
    current:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    current:SetBlendMode("ADD")
    current:SetAllPoints()
    current:Hide()
    button.current = current
  end
  local icon = _G[name .. "Icon"]
  if itemID ~= 0 then
    local set = ItemRackUser.Sets[itemID]
    if set then
      icon:SetTexture(set.icon or ItemRack.ICON)
    else
      local _, texture = ItemRack.GetInfoByID(itemID)
      icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
  else
    icon:SetTexture(select(2, GetInventorySlotInfo(ItemRack.SlotInfo[ItemRack.menuOpen].name)))
  end
  return button
end

function ItemRack.UpdateMenuCooldowns()
  for i = 1, #ItemRack.Menu do
    local cd = _G["ItemRackMenu" .. i .. "Cooldown"]
    local baseID = tonumber(ItemRack.GetIRString(ItemRack.Menu[i], true))
    if baseID and baseID > 0 and ItemRack.menuOpen < 20 then
      ItemRack.SetCooldown(cd, GetItemCooldown(baseID))
    elseif cd then
      cd:Hide()
    end
    local time = _G["ItemRackMenu" .. i .. "Time"]
    if time and (ItemRackSettings.CooldownCount ~= "ON" or ItemRack.menuOpen == 20) then time:SetText("") end
  end
  ItemRack.WriteMenuCooldowns()
end

function ItemRack.WriteMenuCooldowns()
  if ItemRackSettings.CooldownCount == "ON" and menu:IsVisible() and ItemRack.menuOpen and ItemRack.menuOpen < 20 then
    for i = 1, #ItemRack.Menu do
      local baseID = tonumber(ItemRack.GetIRString(ItemRack.Menu[i], true))
      if baseID and baseID > 0 then
        ItemRack.WriteCooldown(_G["ItemRackMenu" .. i .. "Time"], GetItemCooldown(baseID))
      else
        _G["ItemRackMenu" .. i .. "Time"]:SetText("")
      end
    end
  end
end

-- the menu closes once the mouse leaves it and the frames it belongs to
function ItemRack.MenuMouseover()
  if ItemRack.MenuDockingTo then return end
  local focus = ItemRack.GetMouseFocus and ItemRack.GetMouseFocus()
  local focusName = focus and focus.GetName and focus:GetName()
  if ItemRack.MouseIsOver(menu) or IsShiftKeyDown()
    or (focusName and focus:IsVisible() and ItemRack.MenuMouseoverFrames[focusName]) then
    return
  end
  for name in pairs(ItemRack.MenuMouseoverFrames) do
    local frame = _G[name]
    if frame and frame.IsVisible and frame:IsVisible() and ItemRack.MouseIsOver(frame) then return end
  end
  ItemRack.StopTimer("MenuMouseover")
  ItemRack.HideMenu()
end

function ItemRack.MenuOnHide()
  ItemRack.menuDockedTo = nil
  ItemRack.StopTimer("MenuMouseover")
end

-- Clicking an entry ---------------------------------------------------------------------
function ItemRack.MenuOnClick(self, button)
  self:SetChecked(false)
  local item = ItemRack.Menu[self:GetID()]
  local open = ItemRack.menuOpen
  if item == nil then return end
  ItemRack.ClearLockList()
  if IsAltKeyDown() and ItemRackSettings.AllowHidden == "ON" then
    ItemRack.ToggleHidden(item)
    ItemRack.BuildMenu()
  elseif IsShiftKeyDown() and open < 20 and ItemRack.ChatOpen() then
    ItemRack.ChatLinkID(item)
  elseif ItemRack.menuInclude then
    -- picking an item for the set being edited
    if ItemRack.OptOnMenuPick then ItemRack.OptOnMenuPick(open, item) end
    menu:Hide()
  elseif open < 20 then
    if ItemRack.BankOpen then
      if ItemRack.GetCountByID(item) == 0 then
        local bankBag, bankSlot = ItemRack.FindInBank(item)
        if bankBag then
          local freeBag, freeSlot = ItemRack.FindSpace()
          if freeBag and not SpellIsTargeting() and not GetCursorInfo() then
            PickupContainerItem(bankBag, bankSlot)
            PickupContainerItem(freeBag, freeSlot)
          else
            ItemRack.Print(L["Not enough room in bags to pull this item from bank."])
          end
        end
      else
        local bankBag, bankSlot = ItemRack.FindBankSpace()
        if bankBag then
          local _, bag, slot = ItemRack.FindItem(item)
          if bag and not SpellIsTargeting() and not GetCursorInfo() then
            PickupContainerItem(bag, slot)
            PickupContainerItem(bankBag, bankSlot)
          end
        else
          ItemRack.Print(L["Not enough room in bank to put this item."])
        end
      end
    else
      if ItemRackSettings.EquipOnSetPick == "ON" and ItemRack.OptOnMenuPick then
        ItemRack.OptOnMenuPick(open, item, true)
      end
      local slot = open
      if open >= 13 and open <= 14 and ItemRackSettings.TrinketMenuMode == "ON" and ItemRackUser.Buttons[13] and ItemRackUser.Buttons[14] then
        slot = button == "RightButton" and 14 or 13
      end
      ItemRack.EquipItemByID(item, slot)
      ItemRack.HideMenu()
    end
  elseif open == 20 then
    if ItemRack.BankOpen then
      if ItemRack.MissingItems(item) == 1 then
        ItemRack.GetBankedSet(item)
      else
        ItemRack.PutBankedSet(item)
      end
    elseif ItemRackSettings.EquipToggle == "ON" or IsShiftKeyDown() then
      ItemRack.ToggleSet(item)
    else
      ItemRack.EquipSet(item)
    end
    if not ItemRack.BankOpen then
      ItemRack.StopTimer("MenuMouseover")
      ItemRack.HideMenu()
    end
  end
end

-- Lock: buttons and menu can't move, the menu loses its frame and the controls ---------
function ItemRack.ReflectLock(override)
  local locked = ItemRackUser.Locked == "ON" or override
  menu:EnableMouse(not locked)
  S.SetRoundedShown(menu, not locked)
end

-- Tooltips --------------------------------------------------------------------------------
function ItemRack.AnchorTooltip(owner)
  if string.match(ItemRack.menuDockedTo or "", "^Character") then
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  elseif ItemRackSettings.TooltipFollow == "ON" then
    if owner.GetLeft and owner:GetLeft() and owner:GetLeft() < 400 then
      GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    else
      GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    end
  else
    GameTooltip_SetDefaultAnchor(GameTooltip, owner)
  end
end

-- tooltip of a worn slot (refreshed every second while on cooldown)
function ItemRack.InventoryTooltip(self)
  if ItemRackSettings.ShowTooltips ~= "ON" then return end
  local id = self:GetID()
  if id == 20 then
    ItemRack.SetTooltip(self, ItemRackUser.CurrentSet)
  else
    ItemRack.TooltipOwner = self
    ItemRack.TooltipType = "INVENTORY"
    ItemRack.TooltipSlot = id
    ItemRack.TooltipBag = ItemRack.CombatQueue[id] and ItemRack.GetInfoByID(ItemRack.CombatQueue[id])
    ItemRack.StartTimer("TooltipUpdate", 0)
  end
end

function ItemRack.MenuTooltip(self)
  if ItemRackSettings.ShowTooltips ~= "ON" then return end
  local id = self:GetID()
  if ItemRack.menuOpen == 20 then
    ItemRack.SetTooltip(self, ItemRack.Menu[id])
  else
    ItemRack.TooltipOwner = self
    ItemRack.TooltipType = "BAG"
    local _
    _, ItemRack.TooltipBag, ItemRack.TooltipSlot = ItemRack.FindItem(ItemRack.Menu[id])
    if ItemRack.TooltipBag and ItemRack.TooltipSlot then
      ItemRack.StartTimer("TooltipUpdate", 0)
    else
      ItemRack.IDTooltip(self, ItemRack.Menu[id])
    end
  end
end

-- tooltip of an ItemRack ID: worn, carried, banked or only known
function ItemRack.IDTooltip(self, itemID)
  if not itemID or itemID == 0 then
    ItemRack.AnchorTooltip(self)
    GameTooltip:AddLine(L["(empty)"], .6, .6, .6)
    GameTooltip:Show()
    return
  end
  ItemRack.AnchorTooltip(self)
  local inv, bag, slot = ItemRack.FindItem(itemID)
  if inv then
    GameTooltip:SetInventoryItem("player", inv)
  elseif bag then
    GameTooltip:SetBagItem(bag, slot)
  else
    bag, slot = ItemRack.FindInBank(itemID)
    local link = bag and GetContainerItemLink(bag, slot) or ItemRack.IRStringToItemString(ItemRack.UpdateIRString(itemID))
    pcall(GameTooltip.SetHyperlink, GameTooltip, link)
  end
  ItemRack.ShrinkTooltip(self)
  GameTooltip:Show()
end

function ItemRack.ClearTooltip()
  GameTooltip:Hide()
  ItemRack.StopTimer("TooltipUpdate")
  ItemRack.TooltipType = nil
end

function ItemRack.TooltipUpdate()
  if not ItemRack.TooltipType then return end
  local owner = ItemRack.TooltipOwner
  if not owner or not owner:IsVisible() then
    ItemRack.ClearTooltip()
    return
  end
  local cooldown
  ItemRack.AnchorTooltip(owner)
  if ItemRack.TooltipType == "BAG" then
    GameTooltip:SetBagItem(ItemRack.TooltipBag, ItemRack.TooltipSlot)
    cooldown = ItemRack.ReadCooldown(GetContainerItemCooldown(ItemRack.TooltipBag, ItemRack.TooltipSlot))
  else
    GameTooltip:SetInventoryItem("player", ItemRack.TooltipSlot)
    cooldown = ItemRack.ReadCooldown(GetInventoryItemCooldown("player", ItemRack.TooltipSlot))
  end
  ItemRack.ShrinkTooltip(owner)
  if ItemRack.TooltipType == "INVENTORY" and ItemRack.TooltipBag then
    GameTooltip:AddLine(L["Queued:"] .. " " .. ItemRack.TooltipBag, S.Color(C.gold))
  end
  GameTooltip:Show()
  if cooldown == 0 then -- nothing to count down: no need to refresh
    ItemRack.StopTimer("TooltipUpdate")
    ItemRack.TooltipType = nil
  end
end

-- plain tooltip (line1 = title, line2 = text)
function ItemRack.OnTooltip(self, line1, line2)
  if ItemRackSettings.ShowTooltips ~= "ON" or not line1 then return end
  ItemRack.AnchorTooltip(self)
  GameTooltip:AddLine(line1, 1, .85, .45)
  if line2 then GameTooltip:AddLine(line2, .85, .82, .75, 1) end
  GameTooltip:Show()
end

-- tiny tooltips: name, charges, durability and cooldown only
function ItemRack.ShrinkTooltip(owner)
  if ItemRackSettings.TinyTooltips ~= "ON" then return end
  local r, g, b = GameTooltipTextLeft1:GetTextColor()
  local name = GameTooltipTextLeft1:GetText()
  local charge, durability, cooldown
  for i = 2, GameTooltip:NumLines() do
    local line = _G["GameTooltipTextLeft" .. i]
    if line and line:IsVisible() then
      local text = line:GetText() or ""
      if ItemRack.DURABILITY_PATTERN ~= "" and string.match(text, ItemRack.DURABILITY_PATTERN) then durability = text end
      if COOLDOWN_REMAINING and string.find(text, COOLDOWN_REMAINING, 1, true) then cooldown = text end
      for _, pattern in pairs(ItemRack.CHARGES_PATTERNS or {}) do
        if string.find(text, pattern) then charge = text end
      end
    end
  end
  ItemRack.AnchorTooltip(owner)
  GameTooltip:AddLine(name, r, g, b)
  if charge then GameTooltip:AddLine(charge, 1, 1, 1) end
  if durability then GameTooltip:AddLine(durability, 1, 1, 1) end
  if cooldown then GameTooltip:AddLine(cooldown, 1, 1, 1) end
end

-- a set: its items, red when missing, blue when in the bank
function ItemRack.SetTooltip(self, setname)
  local set = setname and ItemRackUser.Sets[setname]
  if not set or not set.equip then return end
  ItemRack.AnchorTooltip(self)
  GameTooltip:AddLine(setname, S.Color(C.title))
  if ItemRackSettings.TinyTooltips ~= "ON" then
    for i = 0, 19 do
      if set.equip[i] then
        local itemName = ItemRack.GetInfoByID(set.equip[i])
        if itemName then
          local col = "FFAAA393"
          if set.equip[i] ~= 0 and ItemRack.GetCountByID(set.equip[i]) == 0 then
            col = ItemRack.FindInBank(set.equip[i]) and "FF5C9BFF" or "FFFF5A4A"
          end
          GameTooltip:AddLine("|cFFEFE8D8" .. ItemRack.SlotInfo[i].real .. ":|r |c" .. col .. itemName)
        end
      end
    end
  end
  GameTooltip:Show()
end

-- Character sheet: hovering a slot opens its menu ---------------------------------------
function ItemRack.DockMenuToCharacterSheet(self)
  local name = self:GetName()
  local slot
  for i = 0, 19 do
    if name == "Character" .. ItemRack.SlotInfo[i].name then slot = i end
  end
  if not slot then return end
  if slot == 0 or (slot >= 16 and slot <= 18) then
    ItemRack.DockWindows("TOPLEFT", self, "BOTTOMLEFT", "VERTICAL")
  else
    if slot == 14 and ItemRackSettings.TrinketMenuMode == "ON" and CharacterTrinket0Slot then
      self = CharacterTrinket0Slot
    end
    ItemRack.DockWindows("TOPLEFT", self, "TOPRIGHT", "HORIZONTAL")
  end
  ItemRack.BuildMenu(slot)
end

function ItemRack.OnEnterCharacterSlot(self)
  if not self or not self.GetName then return end
  if ItemRack.menuDockedTo ~= self:GetName() and (ItemRackSettings.MenuOnShift == "OFF" or IsShiftKeyDown())
    and ItemRackSettings.CharacterSheetMenus == "ON" then
    ItemRack.DockMenuToCharacterSheet(self)
  end
end

-- when the client has no PaperDollItemSlotButton_OnEnter to hook: the slots themselves
function ItemRack.HookCharacterSheet()
  if type(PaperDollItemSlotButton_OnEnter) == "function" then
    hooksecurefunc("PaperDollItemSlotButton_OnEnter", ItemRack.OnEnterCharacterSlot)
    return
  end
  for i = 0, 19 do
    local slot = _G["Character" .. ItemRack.SlotInfo[i].name]
    if slot then slot:HookScript("OnEnter", ItemRack.OnEnterCharacterSlot) end
  end
end
