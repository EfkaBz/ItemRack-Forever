-- ItemRack Forever: the dockable slot buttons (0-19) and the set button (20).
-- Alt+click a slot of the character sheet (Alt+click the model for the set button) to add
-- or remove one; drag to move, Shift+drag to move one out of a docked group; dropped next
-- to another, they dock. Same frame names as ItemRack (ItemRackButton0..20 and parts).
local _, ns = ...
local L = ns.L
local S = ns.Skin
local C = S.C
local MEDIA = S.MEDIA
local GetItemCount = ns.API.GetItemCount

ItemRack.Docking = {} -- docking under way
ItemRack.LockedButtons = {} -- buttons shown as locked (desaturated)
ItemRack.NewAnchor = nil -- the last added button: the next one docks to it

-- docking brackets: cx, cy, texcoords (4x4 grid of the Brackets texture)
ItemRack.BracketInfo = {
  TOP = { 36, 12, .25, .75, 0, .25 }, BOTTOM = { 36, 12, .25, .75, .75, 1 },
  LEFT = { 12, 36, 0, .25, .25, .75 }, RIGHT = { 12, 36, .75, 1, .25, .75 },
  TOPLEFT = { 12, 12, 0, .25, 0, .25 }, TOPRIGHT = { 12, 12, .75, 1, 0, .25 },
  BOTTOMLEFT = { 12, 12, 0, .25, .75, 1 }, BOTTOMRIGHT = { 12, 12, .75, 1, .75, 1 },
}

ItemRack.DockInfo = {
  LEFT = { xoff = 1, yoff = 0 }, RIGHT = { xoff = -1, yoff = 0 },
  TOP = { xoff = 0, yoff = -1 }, BOTTOM = { xoff = 0, yoff = 1 },
  -- menu docks: mainDock..menuDock
  TOPRIGHTTOPLEFT = { xoff = 0, yoff = 8, xdir = 1, ydir = -1, xstart = 8, ystart = -8 },
  BOTTOMRIGHTBOTTOMLEFT = { xoff = 0, yoff = -8, xdir = 1, ydir = 1, xstart = 8, ystart = 44 },
  TOPLEFTTOPRIGHT = { xoff = 0, yoff = 8, xdir = -1, ydir = -1, xstart = -44, ystart = -8 },
  BOTTOMLEFTBOTTOMRIGHT = { xoff = 0, yoff = -8, xdir = -1, ydir = 1, xstart = -44, ystart = 44 },
  TOPRIGHTBOTTOMRIGHT = { xoff = 8, yoff = 0, xdir = -1, ydir = 1, xstart = -44, ystart = 44 },
  BOTTOMRIGHTTOPRIGHT = { xoff = 8, yoff = 0, xdir = -1, ydir = -1, xstart = -44, ystart = -8 },
  TOPLEFTBOTTOMLEFT = { xoff = -8, yoff = 0, xdir = 1, ydir = 1, xstart = 8, ystart = 44 },
  BOTTOMLEFTTOPLEFT = { xoff = -8, yoff = 0, xdir = 1, ydir = -1, xstart = 8, ystart = -8 },
}
ItemRack.OppositeSide = { LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BOTTOM", BOTTOM = "TOP" }

-- frames besides the menu that keep it open while the mouse is over them
ItemRack.MenuMouseoverFrames = { PaperDollFrame = 1, CharacterTrinket1Slot = 1 }

local function spacing() return ItemRackUser.ButtonSpacing or 4 end

-- Parts shared by the slot buttons and the menu buttons ------------------------------
-- name..: Icon, Cooldown, Time, Count, HotKey, Name, Queue
function ItemRack.CreateItemParts(b, name)
  S.SkinItemButton(b, name)
  local cd = CreateFrame("Cooldown", name .. "Cooldown", b, "CooldownFrameTemplate")
  cd:SetPoint("TOPLEFT", 2, -2)
  cd:SetPoint("BOTTOMRIGHT", -2, 2)
  if cd.SetDrawEdge then cd:SetDrawEdge(false) end
  if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.7) end
  if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end

  local over = CreateFrame("Frame", nil, b) -- above the cooldown swirl
  over:SetAllPoints()
  over:SetFrameLevel(cd:GetFrameLevel() + 2)
  b.over = over

  local time = over:CreateFontString(name .. "Time", "OVERLAY", "NumberFontNormal")
  time:SetJustifyH("CENTER")
  time:SetPoint("BOTTOM", 0, 2)
  local count = over:CreateFontString(name .. "Count", "OVERLAY", "NumberFontNormal")
  count:SetPoint("BOTTOMRIGHT", -2, 2)
  count:SetJustifyH("RIGHT")
  local hotkey = over:CreateFontString(name .. "HotKey", "OVERLAY", "NumberFontNormalSmallGray")
  hotkey:SetPoint("TOPRIGHT", -2, -2)
  hotkey:SetJustifyH("RIGHT")
  local label = over:CreateFontString(name .. "Name", "OVERLAY", "GameFontHighlightSmallOutline")
  label:SetPoint("BOTTOMLEFT", 2, 2)
  label:SetPoint("BOTTOMRIGHT", -2, 2)
  label:SetJustifyH("CENTER")
  label:SetWordWrap(false)
  local queue = over:CreateTexture(name .. "Queue", "OVERLAY", nil, 2)
  queue:SetSize(20, 20)
  queue:SetPoint("TOPLEFT", -2, 2)
  queue:Hide()
  ItemRack.SetFont(name)
end

-- cooldown numbers: small along the bottom, or large and gold in the middle
function ItemRack.SetFont(name)
  local time, button = _G[name .. "Time"], _G[name]
  if not time then return end
  time:ClearAllPoints()
  if ItemRackSettings.LargeNumbers == "ON" then
    time:SetFontObject(NumberFontNormalLarge)
    time:SetTextColor(1, .82, 0)
    time:SetPoint("CENTER", button, "CENTER")
  else
    time:SetFontObject(NumberFontNormal)
    time:SetTextColor(1, 1, 1)
    time:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)
  end
end

function ItemRack.ReflectCooldownFont()
  for i = 0, 20 do ItemRack.SetFont("ItemRackButton" .. i) end
  local i = 1
  while _G["ItemRackMenu" .. i] do
    ItemRack.SetFont("ItemRackMenu" .. i)
    i = i + 1
  end
end

function ItemRack.SetCooldown(cd, start, duration, enable)
  if not cd then return end
  if CooldownFrame_Set then
    pcall(CooldownFrame_Set, cd, start, duration, enable)
  elseif start and duration then
    pcall(cd.SetCooldown, cd, start, duration)
  end
end

-- The buttons (created at load: secure frames can't be made in combat) ------------
for i = 0, 20 do
  local name = "ItemRackButton" .. i
  local b = CreateFrame("CheckButton", name, UIParent, "SecureActionButtonTemplate")
  b:SetID(i)
  b:SetSize(36, 36)
  b:SetMovable(true)
  b:SetClampedToScreen(true)
  b:Hide()
  ItemRack.CreateItemParts(b, name)
  b:SetScript("PostClick", function(self, button) ItemRack.ButtonPostClick(self, button) end)
  b:SetScript("OnDragStart", function(self) ItemRack.StartMovingButton(self) end)
  b:SetScript("OnDragStop", function(self) ItemRack.StopMovingButton(self) end)
  b:HookScript("OnEnter", function(self) ItemRack.OnEnterButton(self) end)
  b:HookScript("OnLeave", function(self) ItemRack.ClearTooltip(self) end)
end
ItemRackButton20Queue:SetTexture(ItemRack.GEAR)

-- docking brackets
for _, which in ipairs({ "Main", "Menu" }) do
  local f = CreateFrame("Frame", "ItemRack" .. which .. "Bracket", UIParent)
  f:Hide()
  local t = f:CreateTexture("ItemRack" .. which .. "BracketTexture", "OVERLAY", nil, 7)
  t:SetAllPoints()
  t:SetTexture(MEDIA .. "Brackets")
end

-- keybind targets for the slots (bound from the options): use the item in that slot
ItemRack.UseButtons = {}
for i = 0, 19 do
  local b = CreateFrame("Button", "ItemRackUseButton" .. i, UIParent, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyDown") -- a key sends a down and an up click: only one use
  b:SetAttribute("type", "item")
  b:SetAttribute("slot", i)
  b:SetSize(1, 1)
  b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -2000, 2000)
  b:SetAlpha(0)
  b:Show()
  b:HookScript("PostClick", function() ItemRack.ReflectItemUse(i) end)
  ItemRack.UseButtons[i] = b
end

-- Queue badges on the character sheet slots ---------------------------------------
local function characterSheetBadges()
  for i = 1, 19 do
    local slot = _G["Character" .. ItemRack.SlotInfo[i].name]
    if slot and not _G["Character" .. ItemRack.SlotInfo[i].name .. "Queue"] then
      local holder = CreateFrame("Frame", nil, slot)
      holder:SetSize(18, 18)
      holder:SetPoint("TOPLEFT", -3, 3)
      holder:SetFrameLevel(slot:GetFrameLevel() + 5)
      local q = holder:CreateTexture("Character" .. ItemRack.SlotInfo[i].name .. "Queue", "OVERLAY")
      q:SetAllPoints()
      q:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      q:Hide()
    end
  end
end

-- Start-up ------------------------------------------------------------------------------
function ItemRack.InitButtons()
  ItemRackUser.Buttons = ItemRackUser.Buttons or {}
  characterSheetBadges()

  -- Alt+click on the character sheet adds/removes buttons
  if type(PaperDollItemSlotButton_OnModifiedClick) == "function" then
    hooksecurefunc("PaperDollItemSlotButton_OnModifiedClick", ItemRack.newPaperDollItemSlotButton_OnModifiedClick)
  else
    for i = 1, 19 do
      local slot = _G["Character" .. ItemRack.SlotInfo[i].name]
      if slot then
        slot:HookScript("OnClick", function(self, button) ItemRack.newPaperDollItemSlotButton_OnModifiedClick(self, button) end)
      end
    end
  end
  if CharacterAmmoSlot then
    ItemRack.oldCharacterAmmoSlot_OnClick = CharacterAmmoSlot:GetScript("OnClick")
    CharacterAmmoSlot:SetScript("OnClick", ItemRack.newCharacterAmmoSlot_OnClick)
  end
  local model = CharacterModelFrame or CharacterModelScene
  if model then model:HookScript("OnMouseUp", ItemRack.newCharacterModelFrame_OnMouseUp) end
  ItemRack.HookCharacterSheet()

  for i = 0, 20 do
    local b = _G["ItemRackButton" .. i]
    if i < 20 then
      b:SetAttribute("type", "item")
      b:SetAttribute("slot", i)
      b:SetAttribute("shift-slot*", ATTRIBUTE_NOOP) -- Shift+click links the item, doesn't use it
    end
    b:RegisterForDrag("LeftButton", "RightButton")
    b:RegisterForClicks("AnyUp")
    ItemRack.MenuMouseoverFrames["ItemRackButton" .. i] = 1
  end

  ItemRack.CreateTimer("ButtonsDocking", ItemRack.ButtonsDocking, .2, 1)
  ItemRack.CreateTimer("MenuDocking", ItemRack.MenuDocking, .2, 1)
  ItemRack.CreateTimer("ReflectClickedUpdate", ItemRack.ReflectClickedUpdate, .2, 1)

  local events = ItemRackFrame
  for _, e in ipairs({ "UNIT_INVENTORY_CHANGED", "ACTIONBAR_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "ITEM_LOCK_CHANGED", "UPDATE_BINDINGS", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(events.RegisterEvent, events, e)
  end
  ItemRack.InitMenu()
  ItemRack.ReflectMainScale()
  ItemRack.ReflectMenuOnRight()
  ItemRack.ConstructLayout()
  ItemRack.ReflectAlpha()
  ItemRack.UpdateButtonCooldowns()
  ItemRack.ReflectHideOOC()
  ItemRack.ReflectCooldownFont()
  ItemRack.UpdateCombatQueue()
  ItemRack.KeyBindingsChanged()
  ItemRack.UpdateDisableAltClick()
  ItemRack.ReflectLock()
end

function ItemRack.UpdateDisableAltClick()
  if InCombatLockdown() then return end
  for i = 0, 19 do
    _G["ItemRackButton" .. i]:SetAttribute("alt-slot*", ItemRackSettings.DisableAltClick == "OFF" and ATTRIBUTE_NOOP or nil)
  end
end

function ItemRack.newPaperDollItemSlotButton_OnModifiedClick(self, button)
  if IsAltKeyDown() and self.GetID then
    ItemRack.ToggleButton(self:GetID())
  end
end

function ItemRack.newCharacterAmmoSlot_OnClick(self, button)
  if IsAltKeyDown() then
    ItemRack.ToggleButton(0)
  elseif button == "LeftButton" and ItemRack.oldCharacterAmmoSlot_OnClick then
    ItemRack.oldCharacterAmmoSlot_OnClick(self, button)
  end
end

function ItemRack.newCharacterModelFrame_OnMouseUp(self, button)
  if IsAltKeyDown() then ItemRack.ToggleButton(20) end
end

-- Adding and removing --------------------------------------------------------------
function ItemRack.AddButton(id)
  ItemRackUser.Buttons[id] = {}
  local button = _G["ItemRackButton" .. id]
  button:ClearAllPoints()
  if ItemRack.NewAnchor and ItemRackUser.Buttons[ItemRack.NewAnchor] then
    ItemRackUser.Buttons[id].Side = "LEFT"
    ItemRackUser.Buttons[id].DockTo = ItemRack.NewAnchor
    local dock = ItemRack.DockInfo.LEFT
    button:SetPoint("LEFT", "ItemRackButton" .. ItemRack.NewAnchor, "RIGHT", dock.xoff * spacing(), dock.yoff * spacing())
  else
    button:SetPoint("CENTER", UIParent, "CENTER")
  end
  ItemRack.NewAnchor = id
  _G["ItemRackButton" .. id .. "Icon"]:SetTexture(ItemRack.GetTextureBySlot(id))
  button:SetAlpha(ItemRackUser.Alpha)
  button:Show()
  ItemRack.UpdateButtonCooldowns()
  ItemRack.KeyBindingsChanged()
  ItemRack.UpdateCombatQueue()
  if id == 20 then
    ItemRack.UpdateCurrentSet()
    ItemRack.ReflectEventsRunning()
  end
  ItemRack.OptOnSettingsChanged()
end

function ItemRack.RemoveButton(id)
  if InCombatLockdown() then
    ItemRack.Print(L["Sorry, you can't add or remove buttons during combat."])
    return
  end
  if not ItemRackUser.Buttons[id] then return end
  for i, info in pairs(ItemRackUser.Buttons) do
    if info.DockTo == id then
      -- its children stay where they are, undocked
      info.DockTo, info.Side = nil, nil
      local child = _G["ItemRackButton" .. i]
      local x, y = child:GetLeft(), child:GetTop()
      child:ClearAllPoints()
      child:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
      info.Left, info.Top = x, y
    end
  end
  ItemRack.NewAnchor = nil
  ItemRackUser.Buttons[id] = nil
  local button = _G["ItemRackButton" .. id]
  if ItemRackMenuFrame:IsShown() and ItemRack.menuOpen == id then ItemRackMenuFrame:Hide() end
  button:Hide()
  ItemRack.OptOnSettingsChanged()
end

function ItemRack.ToggleButton(id)
  if InCombatLockdown() then
    ItemRack.Print(L["Sorry, you can't add or remove buttons during combat."])
  elseif ItemRackUser.Buttons[id] then
    ItemRack.RemoveButton(id)
  else
    ItemRack.AddButton(id)
  end
end

-- Moving and docking ----------------------------------------------------------------
function ItemRack.Near(v1, v2)
  if v1 and v2 and math.abs(v1 - v2) < 12 then return 1 end
end

-- shapes a bracket (Main or Menu) to a side and shows it on relativeTo's corner
function ItemRack.MoveBracket(which, side, relativeTo, corner)
  local bracket = _G["ItemRack" .. which .. "Bracket"]
  local info = side and ItemRack.BracketInfo[side]
  if not bracket or not info then return end
  bracket:SetSize(info[1], info[2])
  _G["ItemRack" .. which .. "BracketTexture"]:SetTexCoord(info[3], info[4], info[5], info[6])
  bracket:ClearAllPoints()
  bracket:SetParent(relativeTo)
  bracket:SetPoint(corner, relativeTo, corner)
  bracket:SetFrameLevel(relativeTo:GetFrameLevel() + 10)
  bracket:Show()
end

function ItemRack.HideBrackets()
  ItemRackMainBracket:Hide()
  ItemRackMenuBracket:Hide()
  ItemRack.Docking.Side, ItemRack.Docking.From, ItemRack.Docking.To = nil, nil, nil
end

-- true when candidate isn't already docked (directly or not) to button
function ItemRack.LegalDock(button, candidate)
  while ItemRackUser.Buttons[candidate] and ItemRackUser.Buttons[candidate].DockTo do
    if ItemRackUser.Buttons[candidate].DockTo == button then return nil end
    candidate = ItemRackUser.Buttons[candidate].DockTo
  end
  return 1
end

-- the first button of a docked group
function ItemRack.FindParent(button)
  while ItemRackUser.Buttons[button] and ItemRackUser.Buttons[button].DockTo do
    button = ItemRackUser.Buttons[button].DockTo
  end
  return button
end

-- while a button is dragged: show where it would dock
function ItemRack.ButtonsDocking()
  local button = ItemRack.ButtonMoving
  if not button then
    ItemRack.StopTimer("ButtonsDocking")
    return
  end
  local id, near = button:GetID(), ItemRack.Near
  local side
  for i in pairs(ItemRackUser.Buttons) do
    local dock = _G["ItemRackButton" .. i]
    if i ~= id and ItemRack.LegalDock(id, i) then
      local sameRow = near(button:GetTop(), dock:GetTop()) or near(button:GetBottom(), dock:GetBottom())
      local sameCol = near(button:GetLeft(), dock:GetLeft()) or near(button:GetRight(), dock:GetRight())
      if near(button:GetLeft(), dock:GetRight()) and sameRow then
        side = "LEFT"
        ItemRack.MoveBracket("Main", "LEFT", button, "TOPLEFT")
        ItemRack.MoveBracket("Menu", "RIGHT", dock, "TOPRIGHT")
      elseif near(button:GetRight(), dock:GetLeft()) and sameRow then
        side = "RIGHT"
        ItemRack.MoveBracket("Main", "LEFT", dock, "TOPLEFT")
        ItemRack.MoveBracket("Menu", "RIGHT", button, "TOPRIGHT")
      elseif near(button:GetTop(), dock:GetBottom()) and sameCol then
        side = "TOP"
        ItemRack.MoveBracket("Main", "TOP", button, "TOPLEFT")
        ItemRack.MoveBracket("Menu", "BOTTOM", dock, "BOTTOMLEFT")
      elseif near(button:GetBottom(), dock:GetTop()) and sameCol then
        side = "BOTTOM"
        ItemRack.MoveBracket("Main", "TOP", dock, "TOPLEFT")
        ItemRack.MoveBracket("Menu", "BOTTOM", button, "BOTTOMLEFT")
      end
      if side then
        ItemRack.Docking.Side, ItemRack.Docking.From, ItemRack.Docking.To = side, id, i
        return
      end
    end
  end
  ItemRack.HideBrackets()
end

function ItemRack.StartMovingButton(self)
  if ItemRackUser.Locked == "ON" or InCombatLockdown() then return end
  if IsShiftKeyDown() then
    ItemRack.ButtonMoving = self
  else
    ItemRack.ButtonMoving = _G["ItemRackButton" .. ItemRack.FindParent(self:GetID())]
  end
  for i, info in pairs(ItemRackUser.Buttons) do -- light up the group leaders
    if not info.DockTo then _G["ItemRackButton" .. i]:LockHighlight() end
  end
  ItemRackMenuFrame:Hide()
  ItemRack.ButtonMoving:StartMoving()
  ItemRack.StartTimer("ButtonsDocking")
end

function ItemRack.StopMovingButton(self)
  local moving = ItemRack.ButtonMoving
  if not moving then return end
  ItemRack.ButtonMoving = nil
  ItemRack.StopTimer("ButtonsDocking")
  moving:StopMovingOrSizing()
  ItemRack.NewAnchor = nil
  local id = moving:GetID()
  local info = ItemRackUser.Buttons[id]
  if info then
    if ItemRack.Docking.Side and ItemRack.Docking.From == id then
      local side = ItemRack.Docking.Side
      local dock = ItemRack.DockInfo[side]
      moving:ClearAllPoints()
      moving:SetPoint(side, "ItemRackButton" .. ItemRack.Docking.To, ItemRack.OppositeSide[side], dock.xoff * spacing(), dock.yoff * spacing())
      info.DockTo, info.Side = ItemRack.Docking.To, side
      info.Left, info.Top = nil, nil
    else
      info.DockTo, info.Side = nil, nil
      info.Left, info.Top = moving:GetLeft(), moving:GetTop()
    end
  end
  for i in pairs(ItemRackUser.Buttons) do _G["ItemRackButton" .. i]:UnlockHighlight() end
  ItemRack.HideBrackets()
end

-- places every button: free ones first, then the docked ones in docking order
function ItemRack.ConstructLayout()
  if InCombatLockdown() then
    if not tContains(ItemRack.RunAfterCombat, "ConstructLayout") then
      table.insert(ItemRack.RunAfterCombat, "ConstructLayout")
    end
    return
  end
  local buttons = ItemRackUser.Buttons
  for i, info in pairs(buttons) do
    info.needsDrawn = 1
    -- docked to a button that's gone: free it
    if info.DockTo and not buttons[info.DockTo] then info.DockTo, info.Side = nil, nil end
  end
  for i, info in pairs(buttons) do
    if not info.DockTo then
      local button = _G["ItemRackButton" .. i]
      info.needsDrawn = nil
      button:ClearAllPoints()
      if info.Left then
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", info.Left, info.Top)
      else
        button:SetPoint("CENTER", UIParent, "CENTER")
      end
      button:Show()
    end
  end
  local placed = true
  while placed do
    placed = false
    for i, info in pairs(buttons) do
      if info.needsDrawn and not buttons[info.DockTo].needsDrawn then
        local button = _G["ItemRackButton" .. i]
        info.needsDrawn = nil
        button:ClearAllPoints()
        local side = info.Side or "LEFT"
        local dock = ItemRack.DockInfo[side]
        button:SetPoint(side, "ItemRackButton" .. info.DockTo, ItemRack.OppositeSide[side], dock.xoff * spacing(), dock.yoff * spacing())
        button:Show()
        placed = true
      end
    end
  end
  -- a docking loop in damaged data: break it
  for i, info in pairs(buttons) do
    if info.needsDrawn then
      info.needsDrawn, info.DockTo, info.Side = nil, nil, nil
      local button = _G["ItemRackButton" .. i]
      button:ClearAllPoints()
      button:SetPoint("CENTER", UIParent, "CENTER")
      button:Show()
    end
  end
  for i = 0, 20 do
    if not buttons[i] then _G["ItemRackButton" .. i]:Hide() end
  end
  ItemRack.UpdateButtons()
end

-- icons of the worn items, ammo count
function ItemRack.UpdateButtons()
  for i in pairs(ItemRackUser.Buttons) do
    if i < 20 then
      _G["ItemRackButton" .. i .. "Icon"]:SetTexture(ItemRack.GetTextureBySlot(i))
    end
    if i == 0 then
      local baseID = ItemRack.GetIRString(ItemRack.GetID(0), true)
      ItemRackButton0Count:SetText(baseID ~= 0 and (GetItemCount(baseID) or "") or "")
    end
  end
  if not ItemRack.SetSwapping and not ItemRack.SwapPending then
    ItemRack.UpdateCurrentSet()
  end
  ItemRack.UpdateButtonCooldowns()
end

-- Using the buttons -----------------------------------------------------------------
function ItemRack.OnEnterButton(self)
  ItemRack.InventoryTooltip(self)
  if ItemRack.IsTimerActive("ButtonsDocking") or (not IsShiftKeyDown() and ItemRackSettings.MenuOnShift == "ON") or ItemRackSettings.MenuOnRight == "ON" then
    return
  end
  local id = self:GetID()
  ItemRack.DockMenuToButton(id)
  ItemRack.BuildMenu(id)
end

function ItemRack.ButtonPostClick(self, button)
  self:SetChecked(false)
  local id = self:GetID()
  if button == "RightButton" and ItemRackSettings.MenuOnRight == "ON" then
    if ItemRackMenuFrame:IsVisible() and ItemRack.menuOpen == id then
      ItemRackMenuFrame:Hide()
    else
      ItemRack.DockMenuToButton(id)
      ItemRack.BuildMenu(id)
    end
  elseif IsShiftKeyDown() then
    if id < 20 then
      ItemRack.InsertLink(GetInventoryItemLink("player", id))
    elseif ItemRackUser.CurrentSet then
      ItemRack.UnequipSet(ItemRackUser.CurrentSet)
    end
  elseif IsAltKeyDown() then
    if id < 20 and ItemRackSettings.DisableAltClick == "OFF" then
      -- Alt+click: this slot's auto queue on/off (set it up first if it has none)
      if not ItemRack.GetQueues()[id] then
        ItemRack.ToggleOptions(true, 4, id)
      end
      ItemRack.GetQueuesEnabled()[id] = not ItemRack.GetQueuesEnabled()[id] or nil
      ItemRack.UpdateCombatQueue()
    elseif id == 20 then
      ItemRack.ToggleEvents()
    end
  elseif id < 20 then
    ItemRack.ReflectItemUse(id)
  elseif id == 20 then
    if button == "LeftButton" and ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet] then
      if ItemRackSettings.EquipToggle == "ON" then
        ItemRack.ToggleSet(ItemRackUser.CurrentSet)
      else
        ItemRack.EquipSet(ItemRackUser.CurrentSet)
      end
    else
      ItemRack.ToggleOptions(nil, 2)
    end
  end
end

-- a used button stays lit a moment
function ItemRack.ReflectClickedUpdate()
  local reflect, found = ItemRack.ReflectClicked
  for i in pairs(reflect) do
    reflect[i] = reflect[i] - .2
    if reflect[i] < 0 then
      _G["ItemRackButton" .. i]:SetChecked(false)
      reflect[i] = nil
    end
    found = 1
  end
  if not found then ItemRack.StopTimer("ReflectClickedUpdate") end
end

function ItemRack.UpdateButtonCooldowns()
  for i in pairs(ItemRackUser.Buttons) do
    if i < 20 then
      ItemRack.SetCooldown(_G["ItemRackButton" .. i .. "Cooldown"], GetInventoryItemCooldown("player", i))
    end
  end
  ItemRack.WriteButtonCooldowns()
end

function ItemRack.WriteButtonCooldowns()
  if ItemRackSettings.CooldownCount == "ON" then
    for i in pairs(ItemRackUser.Buttons) do
      if i < 20 then
        ItemRack.WriteCooldown(_G["ItemRackButton" .. i .. "Time"], GetInventoryItemCooldown("player", i))
      end
    end
  end
end

function ItemRack.UpdateButtonLocks()
  for i in pairs(ItemRackUser.Buttons) do
    if i < 20 then
      local isLocked = IsInventoryItemLocked(i)
      if isLocked and not ItemRack.LockedButtons[i] then
        _G["ItemRackButton" .. i .. "Icon"]:SetDesaturated(true)
        ItemRack.LockedButtons[i] = 1
      elseif not isLocked and ItemRack.LockedButtons[i] then
        _G["ItemRackButton" .. i .. "Icon"]:SetDesaturated(false)
        ItemRack.LockedButtons[i] = nil
      end
    end
  end
end

-- "12 s", "3 m", "2 h"
function ItemRack.WriteCooldown(where, start, duration)
  if not where then return end
  start, duration = ItemRack.ReadCooldown(start, duration)
  local remain = duration - (GetTime() - start)
  if start == 0 or ItemRackSettings.CooldownCount == "OFF" or remain <= 0 then
    where:SetText("")
  elseif remain < 3 and (where:GetText() or "") == "" then
    -- the global cooldown: not worth showing
  else
    local limit = ItemRackSettings.Cooldown90 == "ON" and 90 or 60
    if remain < limit then
      where:SetText(math.floor(remain + .5) .. " s")
    elseif remain < 3600 then
      where:SetText(math.ceil(remain / 60) .. " m")
    else
      where:SetText(math.ceil(remain / 3600) .. " h")
    end
  end
end

-- Settings shown by the buttons ------------------------------------------------------
function ItemRack.ReflectMainScale(changing)
  if InCombatLockdown() then
    if not tContains(ItemRack.RunAfterCombat, "ReflectMainScale") then
      table.insert(ItemRack.RunAfterCombat, "ReflectMainScale")
    end
    return
  end
  local scale = ItemRackUser.MainScale or 1
  for i = 0, 20 do
    local info, frame = ItemRackUser.Buttons[i], _G["ItemRackButton" .. i]
    if not changing or not info or not info.Left then
      frame:SetScale(scale)
    else
      -- free buttons keep their place on screen while the scale changes
      local old = frame:GetScale() or 1
      local x, y = (frame:GetLeft() or 0) * old, (frame:GetTop() or 0) * old
      frame:SetScale(scale)
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
      info.Left, info.Top = x / scale, y / scale
    end
  end
end

function ItemRack.ReflectMenuOnRight()
  if InCombatLockdown() then
    if not tContains(ItemRack.RunAfterCombat, "ReflectMenuOnRight") then
      table.insert(ItemRack.RunAfterCombat, "ReflectMenuOnRight")
    end
    return
  end
  for i = 0, 20 do
    _G["ItemRackButton" .. i]:SetAttribute("slot2", ItemRackSettings.MenuOnRight == "ON" and ATTRIBUTE_NOOP or nil)
  end
end

function ItemRack.ReflectHideOOC()
  if InCombatLockdown() then return end -- (shown/hidden as combat starts and ends)
  for i in pairs(ItemRackUser.Buttons) do
    local b = _G["ItemRackButton" .. i]
    if ItemRackSettings.HideOOC == "ON" and not ItemRack.inCombat then
      b:Hide()
    else
      b:Show()
    end
  end
end

function ItemRack.ReflectAlpha()
  for i = 0, 20 do _G["ItemRackButton" .. i]:SetAlpha(ItemRackUser.Alpha) end
  if ItemRackMenuFrame then ItemRackMenuFrame:SetAlpha(ItemRackUser.Alpha) end
end

function ItemRack.ReflectMenuScale(scale)
  ItemRackMenuFrame:SetScale(scale or ItemRackUser.MenuScale)
end

-- key bindings on the buttons (the slot's use binding, or a click binding on the button)
function ItemRack.KeyBindingsChanged()
  for i in pairs(ItemRackUser.Buttons) do
    local hotkey = _G["ItemRackButton" .. i .. "HotKey"]
    if ItemRackSettings.ShowHotKeys == "ON" then
      local key
      if i < 20 then key = GetBindingKey("CLICK ItemRackUseButton" .. i .. ":LeftButton") end
      key = key or GetBindingKey("CLICK ItemRackButton" .. i .. ":LeftButton")
      hotkey:SetText(key and GetBindingText(key, nil, 1) or "")
    else
      hotkey:SetText("")
    end
  end
end

function ItemRack.ResetButtons()
  if InCombatLockdown() then
    ItemRack.Print(L["Sorry, you can't add or remove buttons during combat."])
    return
  end
  for i in pairs(ItemRackUser.Buttons) do ItemRack.RemoveButton(i) end
  ItemRackUser.Alpha = 1
  ItemRackUser.Locked = "OFF"
  ItemRackUser.MainScale = 1
  ItemRackUser.MenuScale = .85
  ItemRack.ReflectAlpha()
  ItemRack.ReflectMainScale()
  ItemRack.ReflectMenuScale()
  ItemRack.ReflectLock()
  ItemRack.OptOnSettingsChanged()
end
