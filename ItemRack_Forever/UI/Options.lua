-- ItemRack Forever: the options window. The same window as ItemRack's (same frames, same
-- sizes, same places, same behaviour), drawn in the Forever theme. Built the first time
-- it opens.
local _, ns = ...
local L = ns.L
local S = ns.Skin
local C = S.C
local API = ns.API

ItemRackOpt = {
  Icons = {}, -- list of all icons possible for a set
  Inv = {}, -- 0-19 currently chosen items per slot
  HoldInv = {}, -- 0-19 ItemRackOpt.Inv held when picking set
  SetList = {}, -- numerically-indexed list of set names
  EventList = {},
  selectedIcon = 0,
  prevFrame = nil, -- previous subframe a frame should return to
  numSubFrames = 8,
  slotOrder = { 1, 2, 3, 15, 5, 4, 19, 9, 16, 17, 18, 0, 14, 13, 12, 11, 8, 7, 6, 10, 6, 7, 8, 11, 12, 13, 14, 0, 18, 17, 16, 9, 19, 4, 5, 15, 3, 2 },
  currentMarquee = 0,
  spec = 0,
}
local Opt = ItemRackOpt
ns.Opt = Opt
for i = 0, 19 do
  Opt.Inv[i] = {}
  Opt.HoldInv[i] = {}
end

ItemRack.SetnameBlacklist = {
  [_G.CUSTOM or "Custom"] = true, -- used for minimap/panel button display
  ["~CombatQueue"] = true, -- used for internal events
  ["~Unequip"] = true, -- used for internal events
}

local built
local EVENT_TYPES = { "Buff", "Stance", "Zone", "Script" }

-- small helpers --------------------------------------------------------------------------
-- the skin's widgets are created without a name: they get their global here, and keep it
-- in .irName (GetName() stays nil for them)
local function named(obj, name)
  if name then
    _G[name] = obj
    obj.irName = name
  end
  return obj
end

local function text(parent, size, col, str, justify, name)
  local fs = S.Text(parent, size or 11, col or "text")
  if str then fs:SetText(str) end
  if justify then fs:SetJustifyH(justify) end
  return named(fs, name)
end

-- tooltips go through ItemRack.OnTooltip, like the original (follows the tooltip settings)
local function tooltip(frame, title, body)
  frame:HookScript("OnEnter", function(self)
    local t, b = title, body
    if type(t) == "function" then t, b = t(self) end
    ItemRack.OnTooltip(self, t, b)
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ItemRackOptButtonTemplate
local function button(parent, name, label, width, height, onClick, primary)
  return named(S.Button(parent, label, width or 55, height or 24, onClick, primary), name)
end

-- ItemRackSmallButtonTemplate: a glyph
local function small(parent, name, glyph, size, onClick, rotation)
  return named(S.GlyphButton(parent, glyph, size or 16, onClick, rotation), name)
end

-- the bordered inner boxes (lists, icon grid)
local function box(parent, name)
  local f = CreateFrame("Frame", name, parent)
  S.Well(f)
  return f
end

-- a check button with its label to the right
local function check(parent, name, label, size, onClick)
  local c = S.Check(parent, label, (size or 16) + 6, onClick)
  return named(c, name)
end

local function setHighlight(frame, on)
  if frame and frame.SetLocked then frame:SetLocked(on) end
end

function Opt.MakeEscable(frame, add)
  local found
  for i in pairs(UISpecialFrames) do
    if UISpecialFrames[i] == frame then found = i end
  end
  if not found and add == "add" then
    table.insert(UISpecialFrames, frame)
  elseif found and add == "remove" then
    table.remove(UISpecialFrames, found)
  end
end

--[[ Paperdoll ]]---------------------------------------------------------------------------

function Opt.InvOnEnter(self)
  local id = self:GetID()
  if ItemRack.IsTimerActive("SlotMarquee") then
    self.icon:SetVertexColor(1, 1, 1, 1)
    return
  end
  local menuDock, mainDock, menuOrient = "TOPRIGHT", "TOPLEFT", "HORIZONTAL"
  if id == 0 or (id >= 16 and id <= 18) then
    menuDock, mainDock, menuOrient = "TOPLEFT", "BOTTOMLEFT", "VERTICAL"
  elseif id >= 6 and id <= 14 and id ~= 9 then
    menuDock, mainDock = "TOPLEFT", "TOPRIGHT"
  end
  ItemRack.DockWindows(menuDock, self, mainDock, menuOrient)
  ItemRack.BuildMenu(id, ItemRackSettings.EquipOnSetPick == "OFF" and 1 or nil)
  ItemRack.IDTooltip(self, Opt.Inv[id].id)
end

function Opt.InvOnLeave(self)
  ItemRack.ClearTooltip()
  if ItemRack.IsTimerActive("SlotMarquee") then
    self.icon:SetVertexColor(.25, .25, .25, 1)
  end
end

function Opt.UpdateInv()
  if not built or ItemRack.IsTimerActive("SlotMarquee") then return end
  for i = 0, 19 do
    local item = _G["ItemRackOptInv" .. i]
    local inv = Opt.Inv[i]
    local texture, state
    if inv.id and inv.id ~= 0 then
      texture = select(2, ItemRack.GetInfoByID(inv.id))
      if inv.selected and ItemRack.GetCountByID(inv.id) == 0 then
        state = ItemRack.FindInBank(inv.id) and C.bank or C.bad
      end
    end
    if not texture then texture = select(2, GetInventorySlotInfo(ItemRack.SlotInfo[i].name)) end
    item.icon:SetTexture(texture)
    item:SetStateBorder(state)
    item:UnlockHighlight()
    if inv.selected then
      item.icon:SetVertexColor(1, 1, 1)
      if inv.id == 0 then item:LockHighlight() end
    else
      item.icon:SetVertexColor(.25, .25, .25)
    end
  end
  Opt.PopulateInvIcons()
  Opt.ValidateSetButtons()
  ItemRackOptSetsCurrentSet.icon:SetTexture(Opt.selectedIcon)
end

function Opt.ToggleInvSelect(self)
  local id = self:GetID()
  if ItemRack.IsTimerActive("SlotMarquee") or ItemRackOptSubFrame4:IsVisible() then
    if ItemRackOptSubFrame6:IsVisible() then
      Opt.BindSlot(id)
    else
      Opt.SetupQueue(id)
    end
  elseif IsShiftKeyDown() then
    ItemRack.ChatLinkID(Opt.Inv[id].id)
  else
    Opt.Inv[id].selected = not Opt.Inv[id].selected or nil
    Opt.UpdateInv()
  end
end

function Opt.ToggleAll()
  local state = not Opt.Inv[1].selected or nil
  for i = 0, 19 do Opt.Inv[i].selected = state end
  Opt.UpdateInv()
end

-- an item picked from the menu of a slot of the options' paperdoll
function ItemRack.OptOnMenuPick(slot, item)
  if not built or not ItemRackOptFrame:IsVisible() or not slot or slot > 19 then return end
  Opt.Inv[slot].id = item
  Opt.Inv[slot].selected = 1
  Opt.UpdateInv()
end

--[[ Icon choices ]]------------------------------------------------------------------------

function Opt.PopulateInvIcons()
  for i = 0, 19 do
    local texture
    if Opt.Inv[i].id and Opt.Inv[i].id ~= 0 then
      texture = select(2, ItemRack.GetInfoByID(Opt.Inv[i].id))
    end
    Opt.Icons[i + 1] = texture or select(2, GetInventorySlotInfo(ItemRack.SlotInfo[i].name))
  end
  Opt.SetsIconScrollFrameUpdate()
end

function Opt.PopulateInitialIcons()
  wipe(Opt.Icons)
  for i = 0, 19 do table.insert(Opt.Icons, "Interface\\Icons\\INV_Misc_QuestionMark") end
  Opt.PopulateInvIcons()
  table.insert(Opt.Icons, "Interface\\Icons\\INV_Banner_02")
  table.insert(Opt.Icons, "Interface\\Icons\\INV_Banner_03")
  -- the macro icons. Clients answer this three different ways, and WoW Forever's
  -- IconDataProvider is broken (and taints shared state), so each way is tried in turn,
  -- inside a pcall, and the first that gives icons is used
  local function add(texture)
    if type(texture) == "number" then
      table.insert(Opt.Icons, texture)
    elseif type(texture) == "string" and texture ~= "" then
      table.insert(Opt.Icons, texture:find("\\") and texture or "Interface\\Icons\\" .. texture)
    end
  end
  local before = #Opt.Icons
  local sources = {
    function()
      if not (GetNumMacroIcons and GetMacroIconInfo) then return end
      for i = 1, (GetNumMacroIcons() or 0) do add(GetMacroIconInfo(i)) end
    end,
    function()
      if not (RefreshPlayerSpellIconInfo and GetMacroIcons and GetSpellorMacroIconInfo) then return end
      RefreshPlayerSpellIconInfo()
      for i = 1, #GetMacroIcons(MACRO_ICON_FILENAMES) do add(GetSpellorMacroIconInfo(i)) end
    end,
    function()
      local spells, items = {}, {}
      for _, fill in ipairs({ { GetLooseMacroIcons, spells }, { GetMacroIcons, spells },
        { GetLooseMacroItemIcons, items }, { GetMacroItemIcons, items } }) do
        if type(fill[1]) == "function" then pcall(fill[1], fill[2]) end
      end
      for _, list in ipairs({ spells, items }) do
        for _, texture in ipairs(list) do add(tonumber(texture) or texture) end
      end
    end,
  }
  for _, source in ipairs(sources) do
    pcall(source)
    if #Opt.Icons > before then break end
    for i = #Opt.Icons, before + 1, -1 do Opt.Icons[i] = nil end
  end
end

function Opt.SetsIconScrollFrameUpdate()
  if not built then return end
  local scroll = ItemRackOptSetsIconScrollFrame
  scroll:SetCount(math.ceil(#Opt.Icons / 5))
  local offset = scroll:GetOffset()
  for i = 1, 20 do
    local item = _G["ItemRackOptSetsIcon" .. i]
    local idx = offset * 5 + i
    if idx <= #Opt.Icons then
      local texture = Opt.Icons[idx]
      item.icon:SetTexture(texture)
      item:Show()
      if texture == Opt.selectedIcon then item:LockHighlight() else item:UnlockHighlight() end
    else
      item:Hide()
    end
  end
end

function Opt.SetsIconOnClick(self)
  local idx = self:GetID() + ItemRackOptSetsIconScrollFrame:GetOffset() * 5
  Opt.selectedIcon = Opt.Icons[idx]
  ItemRackOptSetsCurrentSet.icon:SetTexture(Opt.selectedIcon)
  Opt.SetsIconScrollFrameUpdate()
end

--[[ Sets ]]--------------------------------------------------------------------------------

function Opt.SaveSet()
  ItemRackOptSetsName:ClearFocus()
  local setname = ItemRackOptSetsName:GetText()
  ItemRackUser.Sets[setname] = ItemRackUser.Sets[setname] or {}
  local set = ItemRackUser.Sets[setname]
  set.icon = Opt.selectedIcon
  set.oldset = nil
  set.old = {}
  set.equip = {}
  for i = 0, 19 do
    if Opt.Inv[i].selected then set.equip[i] = Opt.Inv[i].id end
  end
  Opt.ReconcileSetBindings()
  Opt.ValidateSetButtons()
  ItemRack.UpdateCurrentSet()
  ItemRack:FireItemRackEvent("ITEMRACK_SET_SAVED", setname)
end

function Opt.ValidateSetButtons()
  if not built then return end
  ItemRackOptSetsSaveButton:Disable()
  ItemRackOptSetsBindButton:Disable()
  ItemRackOptSetsDeleteButton:Disable()
  ItemRackOptSetsHideCheckButton:Disable()
  ItemRackOptSetsHideCheckButton:SetChecked(false)

  local setname = ItemRackOptSetsName:GetText() or ""
  if string.len(setname) > 0 and not ItemRack.SetnameBlacklist[setname] then
    for i = 0, 19 do
      if Opt.Inv[i].selected then
        ItemRackOptSetsSaveButton:Enable()
        break
      end
    end
  end
  local set = ItemRackUser.Sets[setname]
  if set then
    ItemRackOptSetsDeleteButton:Enable()
    if not InCombatLockdown() then ItemRackOptSetsBindButton:Enable() end
    ItemRackOptSetsHideCheckButton:Enable()
    ItemRackOptSetsHideCheckButton:SetChecked(ItemRack.IsHidden(setname))
    ItemRackOptSetsCurrentSet.icon:SetTexture(set.icon)
  end
  Opt.UpdateSpec(set and setname)
end

-- dual spec: which spec the set switches to (the drop-down under the set name)
function Opt.UpdateSpec(setname)
  local drop = ItemRackOptSetsSpecDrop
  if setname and ItemRackUser.Sets[setname] then
    Opt.spec = tonumber(ItemRackUser.Sets[setname].spec) or 0
    drop:SetDropEnabled(true)
  else
    Opt.spec = 0
    drop:SetDropEnabled(false)
  end
  drop:Refresh()
end

function Opt.SpecOnSelect(value)
  local set = ItemRackUser.Sets[ItemRackOptSetsName:GetText()]
  if not set then return end
  Opt.spec = value
  set.spec = value > 0 and value or nil
end

function Opt.LoadSet()
  ItemRackOptSetsName:ClearFocus()
  local setname = ItemRackOptSetsName:GetText()
  if ItemRackUser.Sets[setname] then
    local set = ItemRackUser.Sets[setname].equip
    for i = 0, 19 do
      Opt.Inv[i].selected = nil
      if set[i] then
        Opt.Inv[i].id = set[i]
        Opt.Inv[i].selected = 1
      end
    end
    Opt.selectedIcon = ItemRackUser.Sets[setname].icon
    Opt.UpdateInv()
  end
end

function Opt.DeleteSet()
  local setname = ItemRackOptSetsName:GetText()
  ItemRackUser.Sets[setname] = nil
  Opt.PopulateSetList()
  ItemRack.CleanupEvents()
  Opt.PopulateEventList()
  ItemRack.UpdateCurrentSet()
  ItemRack:FireItemRackEvent("ITEMRACK_SET_DELETED", setname)
end

function Opt.HideSet()
  local setname = ItemRackOptSetsName:GetText()
  if setname and ItemRackUser.Sets[setname] then
    if ItemRackOptSetsHideCheckButton:GetChecked() then
      ItemRack.AddHidden(setname)
    else
      ItemRack.RemoveHidden(setname)
    end
  end
end

function Opt.SaveInv()
  for i = 0, 19 do
    Opt.HoldInv[i].id = Opt.Inv[i].id
    Opt.HoldInv[i].selected = Opt.Inv[i].selected
  end
end

function Opt.RestoreInv()
  for i = 0, 19 do
    Opt.Inv[i].id = Opt.HoldInv[i].id
    Opt.Inv[i].selected = Opt.HoldInv[i].selected
  end
  Opt.UpdateInv()
end

-- the set chooser
function Opt.PickSetOnShow()
  Opt.MakeEscable("ItemRackOptSubFrame5", "add")
  Opt.MakeEscable("ItemRackOptFrame", "remove")
  Opt.HideCurrentSubFrame(5)
  Opt.SaveInv()
  Opt.PopulateSetList()
end

function Opt.PickSetOnHide()
  Opt.MakeEscable("ItemRackOptSubFrame5", "remove")
  Opt.MakeEscable("ItemRackOptFrame", "add")
  Opt.ShowPrevSubFrame()
  if Opt.EventSelected and Opt.prevFrame == ItemRackOptSubFrame3 then
    local entry = Opt.EventList[Opt.EventSelected]
    local event = entry and entry[1]
    -- back to the events with the selected event enabled but without a set: disable it
    if event and ItemRackEvents[event] and ItemRackEvents[event].Type ~= "Script" and not ItemRackUser.Events.Set[event] then
      ItemRackUser.Events.Enabled[event] = nil
      Opt.PopulateEventList()
    end
  end
  Opt.RestoreInv()
end

function Opt.SetListOnEnter(self)
  local name = Opt.SetList[self:GetID() + ItemRackOptSetListScrollFrame:GetOffset()]
  local set = name and ItemRackUser.Sets[name]
  if not set then return end
  for i = 0, 19 do
    if set.equip[i] then
      Opt.Inv[i].id = set.equip[i]
      Opt.Inv[i].selected = 1
    else
      Opt.Inv[i].id = Opt.HoldInv[i].id
      Opt.Inv[i].selected = nil
    end
  end
  Opt.UpdateInv()
end

function Opt.SetListScrollFrameUpdate()
  if not built then return end
  local scroll = ItemRackOptSetListScrollFrame
  scroll:SetCount(#Opt.SetList)
  local offset = scroll:GetOffset()
  for i = 1, 10 do
    local item = _G["ItemRackOptSetList" .. i]
    local idx = offset + i
    if idx <= #Opt.SetList then
      local name = Opt.SetList[idx]
      local set = ItemRackUser.Sets[name]
      item.name:SetText(name)
      item.icon:SetTexture(set.icon)
      item.key:SetText(set.key or "")
      if ItemRack.IsHidden(name) then
        item.name:SetTextColor(S.Color(C.dim))
      else
        item.name:SetTextColor(S.Color(C.text))
      end
      item:Show()
    else
      item:Hide()
    end
  end
end

function Opt.PopulateSetList()
  wipe(Opt.SetList)
  for name in pairs(ItemRackUser.Sets) do
    if not string.match(name, "^~") then table.insert(Opt.SetList, name) end
  end
  table.sort(Opt.SetList)
  Opt.SetListScrollFrameUpdate()
end

-- a set chosen in the set list
function Opt.SelectSetList(self)
  local setname = Opt.SetList[self:GetID() + ItemRackOptSetListScrollFrame:GetOffset()]
  if not setname then return end
  if Opt.prevFrame == ItemRackOptSubFrame3 then
    -- picking an event's set
    local event = Opt.EventList[Opt.EventSelected][1]
    if not ItemRackUser.Events.Set[event] then
      ItemRackUser.Events.Enabled[event] = true
    end
    ItemRackUser.Events.Set[event] = setname
    Opt.PopulateEventList()
  else
    -- picking a set to build: it replaces what was there
    local set = ItemRackUser.Sets[setname]
    for i = 0, 19 do
      Opt.HoldInv[i].id = set.equip[i] or Opt.HoldInv[i].id
      Opt.HoldInv[i].selected = set.equip[i] and 1 or nil
    end
    Opt.selectedIcon = set.icon
    ItemRackOptSetsName:SetText(setname)
    if ItemRackSettings.EquipOnSetPick == "ON" then ItemRack.EquipSet(setname) end
  end
  ItemRackOptSubFrame5:Hide()
end

--[[ Options list ]]-------------------------------------------------------------------------

local function GetOptValue(opt)
  if not opt or not opt.variable then return nil end
  if ItemRackUser[opt.variable] ~= nil then return ItemRackUser[opt.variable] end
  if ItemRackSettings[opt.variable] ~= nil then return ItemRackSettings[opt.variable] end
end

local function dependOff(opt)
  return opt.depend and GetOptValue({ variable = opt.depend }) == "OFF"
end

function Opt.ListScrollFrameUpdate()
  if not built or not Opt.OptInfo then return end
  local scroll = ItemRackOptListScrollFrame
  scroll:SetCount(#Opt.OptInfo)
  local offset = scroll:GetOffset()
  local combat = InCombatLockdown() or ItemRack.inCombat

  for i = 1, #Opt.OptInfo do
    local b = Opt.OptInfo[i].button
    if b then b:Hide() end
  end
  Opt.OptInfo[1].label = L["%s's settings"]:format(ItemRack.PlayerName() or UnitName("player"))

  for i = 1, 11 do
    local row = _G["ItemRackOptList" .. i]
    row.label:Hide()
    row.checkText:Hide()
    row.check:Hide()
    row.numberLabel:Hide()
    row.underline:Hide()
    local opt = Opt.OptInfo[offset + i]
    if opt then
      local lock = combat and opt.combatlock
      row:SetAlpha(lock and .5 or 1)
      if opt.type == "label" then
        row.label:SetText(opt.label)
        S.FitText(row.label, 150, 12)
        row.label:Show()
        if string.len(opt.label) > 1 then row.underline:Show() end
      elseif opt.type == "check" then
        local item = row.checkText
        item:SetWidth(opt.depend and 116 or 128)
        item:SetText(opt.label)
        item:SetTextColor(S.Color(dependOff(opt) and C.dim or C.text))
        item:Show()
        row.check:SetChecked(GetOptValue(opt) == "ON")
        row.check:SetEnabled(not (lock or dependOff(opt)))
        row.check:Show()
      elseif opt.type == "drop" then
        row.numberLabel:SetText(opt.label)
        row.numberLabel:SetTextColor(S.Color(C.text))
        row.numberLabel:Show()
        opt.button:ClearAllPoints()
        opt.button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        opt.button:SetFrameLevel(row:GetFrameLevel() + 3)
        opt.button.Refresh()
        opt.button:Show()
      elseif opt.type == "number" or opt.type == "slider" or opt.type == "button" then
        local off = dependOff(opt)
        local b = opt.button
        b:ClearAllPoints()
        if opt.type == "number" then
          row.numberLabel:SetText(opt.label)
          row.numberLabel:SetTextColor(S.Color(off and C.dim or C.text))
          row.numberLabel:Show()
          b:SetPoint("LEFT", row.numberLabel, "RIGHT", 16, -1)
        elseif opt.type == "slider" then
          b:SetPoint("LEFT", row, "LEFT", 32, 4)
        else
          b:SetPoint("LEFT", row, "LEFT", 16, 0)
        end
        b:SetFrameLevel(row:GetFrameLevel() + 3)
        b:EnableMouse(not (lock or off))
        b:SetAlpha((lock or off) and .5 or 1)
        b:Show()
      end
      row:Show()
    else
      row:Hide()
    end
  end
end

function Opt.UpdateSlider(name)
  if not Opt.OptInfo then return end
  local slider = _G["ItemRackOpt" .. name .. "Slider"]
  local value = ItemRackUser[name]
  local number = _G["ItemRackOpt" .. name]
  if slider and value and number then
    number:SetText(string.format(slider.form or "%s", value))
    if name == "ButtonSpacing" then
      ItemRack.ConstructLayout()
    elseif name == "Alpha" then
      ItemRack.ReflectAlpha()
    elseif name == "MenuScale" then
      ItemRack.ReflectMenuScale()
    elseif name == "MainScale" then
      ItemRack.ReflectMainScale(1)
    end
  end
end

function Opt.InitializeSliders()
  if not Opt.OptInfo then return end
  for _, opt in ipairs(Opt.OptInfo) do
    if opt.type == "slider" and ItemRackUser[opt.variable] then
      opt.button:SetValueSilently(ItemRackUser[opt.variable])
      local number = _G["ItemRackOpt" .. opt.variable]
      if number and not number:HasFocus() then number:SetText(string.format(opt.form, ItemRackUser[opt.variable])) end
    end
  end
end

function Opt.NumberEditBoxOnEnter(self)
  self:ClearFocus()
  local name = self.variable
  local newValue = tonumber(self:GetText())
  local slider = _G["ItemRackOpt" .. name .. "Slider"]
  if newValue and newValue >= slider.min and newValue <= slider.max then
    ItemRackUser[name] = newValue
    slider:SetValueSilently(newValue)
  end
  Opt.UpdateSlider(name)
end

function Opt.NumberEditBoxOnEscape(self)
  self:ClearFocus()
  Opt.UpdateSlider(self.variable)
end

function Opt.OptListCheckButtonOnClick(self)
  local value = self:GetChecked() and "ON" or "OFF"
  local opt = Opt.OptInfo[self:GetParent():GetID() + ItemRackOptListScrollFrame:GetOffset()]
  if not opt or not opt.variable then return end
  if ItemRackUser[opt.variable] ~= nil then
    ItemRackUser[opt.variable] = value
  elseif ItemRackSettings[opt.variable] ~= nil then
    ItemRackSettings[opt.variable] = value
  else
    opt.optset()[opt.variable] = value
  end
  local v = opt.variable
  if v == "Locked" then
    ItemRack.ReflectLock()
  elseif v == "MenuOnRight" then
    ItemRack.ReflectMenuOnRight()
  elseif v == "HideOOC" then
    ItemRack.ReflectHideOOC()
  elseif v == "CooldownCount" then
    for i in pairs(ItemRackUser.Buttons) do
      local t = _G["ItemRackButton" .. i .. "Time"]
      if t then t:SetText("") end
    end
    for i = 1, #ItemRack.Menu do
      local t = _G["ItemRackMenu" .. i .. "Time"]
      if t then t:SetText("") end
    end
    ItemRack.WriteButtonCooldowns()
    ItemRack.WriteMenuCooldowns()
  elseif v == "LargeNumbers" then
    ItemRack.ReflectCooldownFont()
  elseif v == "ShowMinimap" then
    ItemRack.ShowMinimap()
  elseif v == "EnableQueues" or v == "EnablePerSetQueues" then
    ItemRack.UpdateCombatQueue()
  elseif v == "ShowHotKeys" then
    ItemRack.KeyBindingsChanged()
  elseif v == "EnableEvents" then
    ItemRack.RegisterEvents()
  elseif v == "DisableAltClick" then
    ItemRack.UpdateDisableAltClick()
  end
  Opt.ListScrollFrameUpdate()
end

function Opt.OptListOnEnter(self, id)
  local opt
  if type(id) == "number" then
    opt = Opt.OptInfo[id + ItemRackOptListScrollFrame:GetOffset()]
  else
    for i = 1, #Opt.OptInfo do
      if Opt.OptInfo[i].button == self then opt = Opt.OptInfo[i] break end
    end
  end
  if opt and opt.tooltip then ItemRack.OnTooltip(self, opt.label, opt.tooltip) end
end

-- clicking a row clicks its check
function Opt.OptListOnClick(self)
  local c = self.check
  if c:IsVisible() and c:IsEnabled() then
    c:SetChecked(not c:GetChecked())
    c:GetScript("PostClick")(c)
    Opt.OptListCheckButtonOnClick(c)
  end
end

--[[ Tabs and subframes ]]--------------------------------------------------------------------

function Opt.TabOnClick(self, override)
  ItemRackOptBindFrame:Hide()
  for i = Opt.numSubFrames, 1, -1 do
    _G["ItemRackOptSubFrame" .. i]:Hide()
  end
  local which = override or self:GetID()
  for i = 1, 4 do
    _G["ItemRackOptTab" .. i]:SetSelected(which == i)
  end
  _G["ItemRackOptSubFrame" .. which]:Show()
end

-- hides the shown subframes except one (ie 5, to hide all but the set picker)
function Opt.HideCurrentSubFrame(except)
  local prev
  for i = Opt.numSubFrames, 1, -1 do
    if i ~= except then
      local frame = _G["ItemRackOptSubFrame" .. i]
      if frame:IsVisible() then
        frame:Hide()
        prev = prev or frame
      end
    end
  end
  Opt.prevFrame = prev
end

function Opt.ShowPrevSubFrame()
  if not ItemRackOptFrame:IsShown() then return end
  if Opt.prevFrame then
    Opt.prevFrame:Show()
  else
    ItemRackOptSubFrame1:Show()
  end
end

--[[ Key bindings ]]------------------------------------------------------------------------

function Opt.BindSet()
  local setname = ItemRackOptSetsName:GetText()
  Opt.Binding = { type = "Set", name = L["Set \"%s\""]:format(setname), buttonName = ItemRack.BindingPrefix() .. setname }
  Opt.Binding.button = _G[Opt.Binding.buttonName] or CreateFrame("Button", Opt.Binding.buttonName, nil, "SecureActionButtonTemplate")
  ItemRackOptBindFrame:Show()
end

function Opt.BindFrameOnShow()
  if not Opt.Binding then return end
  Opt.HideCurrentSubFrame()
  Opt.Binding.currentKey = GetBindingKey("CLICK " .. Opt.Binding.buttonName .. ":LeftButton") or L["Not bound"]
  ItemRackOptBindFrameBindee:SetText(Opt.Binding.name)
  ItemRackOptBindFrameCurrently:SetText(L["Currently:"] .. " |cFFF2C45C" .. Opt.Binding.currentKey .. "|r")
  Opt.ResetBindFrame()
end

function Opt.BindFrameOnHide()
  Opt.ShowPrevSubFrame()
  Opt.ReconcileSetBindings()
  Opt.Binding = nil
  ItemRack.KeyBindingsChanged()
end

local MOUSE_KEYS = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local MODIFIER_KEYS = { UNKNOWN = 1, LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1 }

function Opt.BindFrameOnKeyDown(self, key)
  if key == "ESCAPE" then
    self:Hide()
    return
  end
  local screenshotKey = GetBindingKey("SCREENSHOT")
  if screenshotKey and key == screenshotKey then
    Screenshot()
    return
  end
  local keyPressed = MOUSE_KEYS[key] or key
  if keyPressed == "BUTTON1" or keyPressed == "BUTTON2" or MODIFIER_KEYS[keyPressed] then return end
  if IsShiftKeyDown() then keyPressed = "SHIFT-" .. keyPressed end
  if IsControlKeyDown() then keyPressed = "CTRL-" .. keyPressed end
  if IsAltKeyDown() then keyPressed = "ALT-" .. keyPressed end
  Opt.Binding.keyPressed = keyPressed
  local oldAction = GetBindingAction(keyPressed)
  if oldAction ~= "" and keyPressed ~= Opt.Binding.currentKey then
    local gold = function(s) return "|cFFF2C45C" .. s .. "|r" end
    ItemRackOptBindFrame:EnableKeyboard(false)
    ItemRackOptBindFrame:EnableMouse(false)
    ItemRackOptBindCancel:Disable()
    ItemRackOptBindUnbind:Disable()
    S.Confirm(L["%s is currently bound to %s.\n\nDo you want to bind %s to %s?"]:format(gold(keyPressed),
      gold(GetBindingText(oldAction, "BINDING_NAME_") or ""), gold(keyPressed), gold(Opt.Binding.name)), {
      { L["Yes"], Opt.SetKeyBinding },
      { L["No"], Opt.ResetBindFrame },
    })
  else
    Opt.SetKeyBinding()
  end
end

function Opt.SetKeyBinding()
  if InCombatLockdown() then
    ItemRack.Print(L["Sorry, you can't bind keys while in combat."])
  elseif Opt.Binding and Opt.Binding.keyPressed and Opt.Binding.buttonName then
    Opt.UnbindKey()
    SetBindingClick(Opt.Binding.keyPressed, Opt.Binding.buttonName, "LeftButton")
    local bindingSet = GetCurrentBindingSet()
    if bindingSet == 1 or bindingSet == 2 then SaveBindings(bindingSet) end
  end
  Opt.ResetBindFrame()
  ItemRackOptBindFrame:Hide()
end

function Opt.ResetBindFrame()
  ItemRackOptBindFrame:EnableKeyboard(true)
  ItemRackOptBindFrame:EnableMouse(true)
  ItemRackOptBindCancel:Enable()
  ItemRackOptBindUnbind:Enable()
end

function Opt.UnbindKey()
  if InCombatLockdown() or not Opt.Binding or not Opt.Binding.buttonName then return end
  for _, action in ipairs({ "CLICK " .. Opt.Binding.buttonName .. ":LeftButton", "CLICK " .. Opt.Binding.buttonName }) do
    local guard = 0
    while GetBindingKey(action) and guard < 10 do
      SetBinding(GetBindingKey(action))
      guard = guard + 1
    end
  end
  if Opt.prevFrame == ItemRackOptSubFrame6 then Opt.prevFrame = nil end
end

function Opt.ReconcileSetBindings()
  for name, set in pairs(ItemRackUser.Sets) do
    set.key = nil
    local buttonName = ItemRack.BindingPrefix() .. name
    if _G[buttonName] then
      local key = GetBindingKey("CLICK " .. buttonName .. ":LeftButton")
      if key and key ~= "" then set.key = key end
    end
  end
  ItemRack.SetSetBindings()
end

--[[ Slot bindings ]]

function Opt.SlotBindFrameOnShow()
  Opt.MakeEscable("ItemRackOptSubFrame6", "add")
  Opt.MakeEscable("ItemRackOptFrame", "remove")
  Opt.HideCurrentSubFrame(6)
  Opt.StartMarquee()
end

function Opt.SlotBindFrameOnHide()
  Opt.MakeEscable("ItemRackOptSubFrame6", "remove")
  Opt.MakeEscable("ItemRackOptFrame", "add")
  Opt.ShowPrevSubFrame()
  Opt.StopMarquee()
end

function Opt.StartMarquee()
  if not ItemRack.TimerPool.SlotMarquee then
    ItemRack.CreateTimer("SlotMarquee", function() Opt.SlotMarquee() end, .1, 1)
  end
  if ItemRack.IsTimerActive("SlotMarquee") then return end
  Opt.SaveInv()
  for i = 0, 19 do Opt.Inv[i].selected = nil end
  ItemRackOptToggleInvAll:Hide()
  Opt.UpdateInv()
  Opt.currentMarquee = 0
  ItemRack.StartTimer("SlotMarquee")
end

function Opt.StopMarquee()
  if not ItemRack.IsTimerActive("SlotMarquee") then return end
  ItemRack.StopTimer("SlotMarquee")
  _G["ItemRackOptInv" .. Opt.slotOrder[Opt.currentMarquee + 1]]:UnlockHighlight()
  Opt.RestoreInv()
  ItemRackOptToggleInvAll:Show()
end

function Opt.SlotMarquee()
  _G["ItemRackOptInv" .. Opt.slotOrder[Opt.currentMarquee + 1]]:UnlockHighlight()
  Opt.currentMarquee = (Opt.currentMarquee + 1) % #Opt.slotOrder
  _G["ItemRackOptInv" .. Opt.slotOrder[Opt.currentMarquee + 1]]:LockHighlight()
end

function Opt.BindSlot(slot)
  Opt.Binding = { type = "Slot", name = ItemRack.SlotInfo[slot].real, buttonName = "ItemRackUseButton" .. slot }
  Opt.Binding.button = _G[Opt.Binding.buttonName]
  ItemRackOptBindFrame:Show()
end

--[[ Auto queues ]]--------------------------------------------------------------------------

function Opt.QueuesFrameOnShow() Opt.StartMarquee() end
function Opt.QueuesFrameOnHide() Opt.StopMarquee() end

function Opt.SlotQueueFrameOnShow()
  Opt.MakeEscable("ItemRackOptSubFrame7", "add")
  Opt.MakeEscable("ItemRackOptFrame", "remove")
  Opt.HideCurrentSubFrame(7)
  for i = 0, 19 do _G["ItemRackOptInv" .. i]:Hide() end
  ItemRackOptToggleInvAll:Hide()
end

function Opt.SlotQueueFrameOnHide()
  Opt.MakeEscable("ItemRackOptSubFrame7", "remove")
  Opt.MakeEscable("ItemRackOptFrame", "add")
  Opt.ShowPrevSubFrame()
  for i = 0, 19 do _G["ItemRackOptInv" .. i]:Show() end
  ItemRackOptToggleInvAll:Show()
end

function Opt.SetupQueue(id)
  ItemRackUser.Queues[id] = ItemRackUser.Queues[id] or {}
  if ItemRackUser.EnablePerSetQueues == "ON" then
    for name, set in pairs(ItemRackUser.Sets) do
      if not string.match(name, "^~") then
        set.Queues = set.Queues or {}
        set.Queues[id] = set.Queues[id] or {}
      end
    end
  end
  local queues = ItemRack.GetQueues()
  queues[id] = queues[id] or {}
  Opt.SelectedSlot = id
  Opt.SortSelected = nil
  ItemRackOptSlotQueueName:SetText(ItemRack.SlotInfo[id].real)
  Opt.PopulateSortList(id)
  ItemRackOptSubFrame7:Show()
  Opt.ValidateSortButtons()
end

-- every item that can go in the slot (worn and in the bags) joins its queue
function Opt.PopulateSortList(slot)
  local sortList = ItemRack.GetQueues()[slot]
  local function add(id)
    if not id or id == 0 then return end
    for i = 1, #sortList do
      if sortList[i] == id then return end
    end
    table.insert(sortList, id)
  end
  add(ItemRack.GetID(slot))
  local other = ItemRack.SlotInfo[slot].other
  if other then add(ItemRack.GetID(other)) end
  for bag = 0, 4 do
    for j = 1, (API.GetContainerNumSlots(bag) or 0) do
      local id = ItemRack.GetID(bag, j)
      if id ~= 0 then
        local _, _, equipSlot = ItemRack.GetInfoByID(id)
        if equipSlot and ItemRack.SlotInfo[slot][equipSlot] and ItemRack.PlayerCanWear(slot, bag, j) then add(id) end
      end
    end
  end
  ItemRackOptSortListScrollFrame:SetOffset(0)
  Opt.SortListScrollFrameUpdate()
end

function Opt.SortListScrollFrameUpdate()
  if not built then return end
  local sortList = Opt.SelectedSlot and ItemRack.GetQueues()[Opt.SelectedSlot]
  local scroll = ItemRackOptSortListScrollFrame
  scroll:SetCount(sortList and #sortList or 0)
  local offset = scroll:GetOffset()
  for i = 1, 11 do
    local item = _G["ItemRackOptSortList" .. i]
    local idx = offset + i
    if sortList and idx <= #sortList then
      local name, texture, quality
      if sortList[idx] == 0 then
        name, texture = L["-- stop queue here --"], "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
        item.icon:SetTexCoord(0, 1, 0, 1)
        item.icon:SetVertexColor(1, 1, 1)
        item.name:SetTextColor(1, 1, 1)
      else
        name, texture, _, quality = ItemRack.GetInfoByID(sortList[idx])
        item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        item.icon:SetVertexColor(1, 1, 1)
        local r, g, b = 1, 1, 1
        if API.GetItemQualityColor then r, g, b = API.GetItemQualityColor(quality or 1) end
        item.name:SetTextColor(r or 1, g or 1, b or 1, 1)
      end
      item.name:SetText(name or "")
      item.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
      setHighlight(item, idx == Opt.SortSelected)
      item:Show()
    else
      item:Hide()
    end
  end
end

function Opt.SortListOnClick(self)
  local idx = ItemRackOptSortListScrollFrame:GetOffset() + self:GetID()
  Opt.SortSelected = (Opt.SortSelected ~= idx) and idx or nil
  Opt.SortListScrollFrameUpdate()
  Opt.ValidateSortButtons()
end

function Opt.ValidateSortButtons()
  local selected = Opt.SortSelected
  local list = ItemRack.GetQueues()[Opt.SelectedSlot] or {}
  ItemRackOptSortMoveTop:Enable()
  ItemRackOptSortMoveUp:Enable()
  ItemRackOptSortMoveDown:Enable()
  ItemRackOptSortMoveBottom:Enable()
  if not selected or #list < 2 then
    ItemRackOptSortMoveTop:Disable()
    ItemRackOptSortMoveUp:Disable()
    ItemRackOptSortMoveDown:Disable()
    ItemRackOptSortMoveBottom:Disable()
  elseif selected == 1 then
    ItemRackOptSortMoveTop:Disable()
    ItemRackOptSortMoveUp:Disable()
  elseif selected == #list then
    ItemRackOptSortMoveDown:Disable()
    ItemRackOptSortMoveBottom:Disable()
  end
  if selected and list[selected] and list[selected] ~= 0 then
    ItemRackOptSortMoveDelete:Enable()
    ItemRackOptItemStatsFrame:Show()
    ItemRackOptSlotQueueName:Hide()
    ItemRackOptQueueEnable:Hide()
    local info = ItemRackItems[ItemRack.GetIRString(list[selected], true)]
    ItemRackOptItemStatsPriority:SetChecked(info and info.priority)
    ItemRackOptItemStatsKeepEquipped:SetChecked(info and info.keep)
    ItemRackOptItemStatsDelay.silent = true
    ItemRackOptItemStatsDelay:SetText(tostring(info and info.delay or "0"))
    ItemRackOptItemStatsDelay.silent = nil
  else
    ItemRackOptSortMoveDelete:SetEnabled(selected and list[selected] == 0 or false)
    ItemRackOptItemStatsFrame:Hide()
    ItemRackOptSlotQueueName:Show()
    ItemRackOptQueueEnable:Show()
  end
  -- keep the selection in view (unless Shift is down)
  if not IsShiftKeyDown() and selected then
    local scroll = ItemRackOptSortListScrollFrame
    local offset = scroll:GetOffset()
    if selected <= offset then
      scroll:SetOffset(selected - 1)
      Opt.SortListScrollFrameUpdate()
    elseif selected > offset + 11 then
      scroll:SetOffset(selected - 11)
      Opt.SortListScrollFrameUpdate()
    end
  end
  ItemRackOptQueueEnable:SetChecked(ItemRack.GetQueuesEnabled()[Opt.SelectedSlot])
end

function Opt.SortMove(self)
  local dir = ((self == ItemRackOptSortMoveUp) and -1) or ((self == ItemRackOptSortMoveTop) and "top")
    or ((self == ItemRackOptSortMoveDown) and 1) or ((self == ItemRackOptSortMoveBottom) and "bottom")
  local list = ItemRack.GetQueues()[Opt.SelectedSlot]
  local idx1 = Opt.SortSelected
  if not list or not idx1 then return end
  if dir then
    local idx2 = ((dir == "top") and 1) or ((dir == "bottom") and #list) or idx1 + dir
    local temp = list[idx1]
    if tonumber(dir) then
      list[idx1] = list[idx2]
      list[idx2] = temp
    elseif dir == "top" then
      table.remove(list, idx1)
      table.insert(list, 1, temp)
    elseif dir == "bottom" then
      table.remove(list, idx1)
      table.insert(list, temp)
    end
    Opt.SortSelected = idx2
  elseif self == ItemRackOptSortMoveDelete then
    table.remove(list, idx1)
    Opt.SortSelected = nil
  end
  Opt.ValidateSortButtons()
  Opt.SortListScrollFrameUpdate()
end

function Opt.SortListOnEnter(self)
  local idx = ItemRackOptSortListScrollFrame:GetOffset() + self:GetID()
  local list = ItemRack.GetQueues()[Opt.SelectedSlot]
  if list and list[idx] then
    if list[idx] == 0 then
      ItemRack.OnTooltip(self, L["Stop Queue Here"], L["Move this to mark an explicit end to an order. ie, if you have a clickable trinket with a passive effect, and would like to use the passive effect if no better trinkets are off cooldown."])
    else
      ItemRack.IDTooltip(self, list[idx])
    end
  end
end

-- an ItemRackItems entry with nothing but default values goes away
function Opt.ItemStatsCleanup(id)
  local item = ItemRackItems[id]
  if item and not item.delay and not item.priority and not item.keep then ItemRackItems[id] = nil end
end

local function selectedBaseID()
  local list = ItemRack.GetQueues()[Opt.SelectedSlot]
  local id = list and Opt.SortSelected and list[Opt.SortSelected]
  if id and id ~= 0 then return ItemRack.GetIRString(id, true) end
end

function Opt.ItemStatsDelayOnTextChanged(self)
  if self.silent then return end
  local baseID = selectedBaseID()
  if not baseID then return end
  local value = tonumber(self:GetText() or "") or 0
  if value ~= 0 then
    ItemRackItems[baseID] = ItemRackItems[baseID] or {}
    ItemRackItems[baseID].delay = value
  else
    if ItemRackItems[baseID] then ItemRackItems[baseID].delay = nil end
    Opt.ItemStatsCleanup(baseID)
  end
end

function Opt.ItemStatsCheckOnClick(self)
  local baseID = selectedBaseID()
  if not baseID then return end
  local which = self == ItemRackOptItemStatsPriority and "priority" or "keep"
  if self:GetChecked() then
    ItemRackItems[baseID] = ItemRackItems[baseID] or {}
    ItemRackItems[baseID][which] = 1
  else
    if ItemRackItems[baseID] then ItemRackItems[baseID][which] = nil end
    Opt.ItemStatsCleanup(baseID)
  end
end

function Opt.QueueEnableSlotOnClick(self)
  ItemRack.GetQueuesEnabled()[Opt.SelectedSlot] = self:GetChecked() and true or nil
  ItemRack.UpdateCombatQueue()
end

--[[ Events ]]-------------------------------------------------------------------------------

function Opt.PopulateEventList()
  if not built or not ItemRackEvents or not ItemRackUser or not ItemRackUser.Events then return end
  local list = Opt.EventList
  local user = ItemRackUser.Events
  local oldevent = Opt.EventSelected and list[Opt.EventSelected] and list[Opt.EventSelected][1] or nil
  Opt.EventSelected = nil
  local safeToRegister = true
  wipe(list)
  for name, ev in pairs(ItemRackEvents) do
    local setname
    if user.Set[name] then
      setname = user.Set[name]
    elseif ev.Type == "Script" and user.Enabled[name] then
      setname = "zzz" -- a fake set name for sorting
    end
    if user.Enabled[name] and not setname then safeToRegister = false end
    table.insert(list, { name, ev.Type, user.Enabled[name], setname })
  end
  table.sort(list, function(e1, e2)
    if e1[4] and not e2[4] then return true end
    if e2[4] and not e1[4] then return false end
    return e1[1] < e2[1]
  end)
  if oldevent then
    for i = 1, #list do
      if list[i][1] == oldevent then Opt.EventSelected = i break end
    end
  end
  Opt.EventListScrollFrameUpdate()
  Opt.ValidateEventListButtons()
  if safeToRegister then ItemRack.RegisterEvents() end
end

function Opt.EventListScrollFrameUpdate()
  if not built then return end
  local scroll = ItemRackOptEventListScrollFrame
  local list = Opt.EventList
  scroll:SetCount(#list)
  local offset = scroll:GetOffset()
  for i = 1, 9 do
    local item = _G["ItemRackOptEventList" .. i]
    local idx = offset + i
    if idx <= #list then
      local name = list[idx][1]
      local setname = ItemRackUser.Events.Set[name]
      local texture
      if list[idx][2] == "Script" then
        texture = ItemRack.SCRIPT_ICON
      elseif setname and ItemRackUser.Sets[setname] then
        texture = ItemRackUser.Sets[setname].icon
      else
        texture = "Interface\\Icons\\INV_Misc_QuestionMark"
      end
      item.name:SetText(name)
      item.iconButton.icon:SetTexture(texture)
      item.enabled:SetChecked(ItemRackUser.Events.Enabled[name])
      setHighlight(item, idx == Opt.EventSelected)
      item:Show()
    else
      item:Hide()
    end
  end
end

function Opt.EventListOnClick(self)
  local idx = ItemRackOptEventListScrollFrame:GetOffset() + self:GetID()
  Opt.EventSelected = (Opt.EventSelected ~= idx) and idx or nil
  Opt.EventListScrollFrameUpdate()
  Opt.ValidateEventListButtons()
end

function Opt.EventListOnDoubleClick(self)
  Opt.EventSelected = nil
  Opt.EventListOnClick(self)
  ItemRackOptSubFrame8:Show()
end

function Opt.EventListOnEnter(self, row)
  local entry = Opt.EventList[ItemRackOptEventListScrollFrame:GetOffset() + row:GetID()]
  if not entry then return end
  local eventName, eventType = entry[1], entry[2]
  local event = ItemRackEvents[eventName]
  if not event then return end
  local desc
  if eventType == "Buff" then
    desc = event.Anymount and L["Equips a set when riding any mount."] or L["Equips a set when gaining the buff %s."]:format(tostring(event.Buff))
  elseif eventType == "Stance" then
    desc = (event.Stance == 0 or event.Stance == "0") and L["Equips a set when leaving forms."] or L["Equips a set when entering stance: %s."]:format(tostring(event.Stance))
  elseif eventType == "Zone" then
    desc = L["Equips a set when entering one of the following zones:"]
    for zone in pairs(event.Zones or {}) do desc = desc .. "\n" .. zone end
  else
    desc = L["Script event triggered on %s"]:format(tostring(event.Trigger))
    local comment = string.match(event.Script or "", "%-%-%[%[(.+)%]%]")
    if comment then desc = desc .. "\n" .. comment end
  end
  desc = "|cFFBBBBBB" .. desc
  if event.NotInPVP then desc = desc .. "\n|cFF888888" .. L["Except in PVP instances."] end
  if event.Unequip then desc = desc .. "\n|cFF888888" .. L["Unequips when condition ends."] end
  ItemRack.OnTooltip(self, eventName, desc)
end

function Opt.ValidateEventListButtons()
  if not built then return end
  ItemRackOptEventEdit:SetEnabled(Opt.EventSelected ~= nil)
  ItemRackOptEventDelete:SetEnabled(Opt.EventSelected ~= nil)
end

function Opt.EventListIconOnClick(row)
  Opt.EventSelected = ItemRackOptEventListScrollFrame:GetOffset() + row:GetID()
  Opt.EventListScrollFrameUpdate()
  Opt.ValidateEventListButtons()
  if Opt.EventList[Opt.EventSelected][2] ~= "Script" then
    ItemRackOptSubFrame5:Show() -- Buff, Stance or Zone event: go pick a set
  else
    ItemRackOptSubFrame8:Show() -- Script event: straight to editing it
  end
end

function Opt.EventListEnabledOnClick(self)
  local row = self:GetParent()
  local idx = ItemRackOptEventListScrollFrame:GetOffset() + row:GetID()
  local entry = Opt.EventList[idx]
  if not entry then return end
  Opt.EventSelected = idx
  local checked = self:GetChecked()
  local name = entry[1]
  ItemRackUser.Events.Enabled[name] = checked and true or nil
  if checked then
    ItemRackUser.EnableEvents = "ON"
    ItemRack.ReflectEventsRunning()
    if entry[2] ~= "Script" and not ItemRackUser.Events.Set[name] then
      Opt.EventListIconOnClick(row) -- an event without a set: choose one
      return
    end
  else
    Opt.EventSelected = nil
  end
  Opt.PopulateEventList()
  Opt.ListScrollFrameUpdate()
end

function Opt.EventEditOnShow()
  Opt.MakeEscable("ItemRackOptSubFrame8", "add")
  Opt.MakeEscable("ItemRackOptFrame", "remove")
  Opt.HideCurrentSubFrame(8)
  Opt.EventEditPopulateFrame()
end

function Opt.EventEditOnHide()
  if ItemRackFloatingEditor:IsShown() then ItemRackFloatingEditor:Hide() end
  Opt.MakeEscable("ItemRackOptSubFrame8", "remove")
  Opt.MakeEscable("ItemRackOptFrame", "add")
  Opt.ShowPrevSubFrame()
end

function Opt.SetEventType(kind)
  Opt.EventType = kind
  ItemRackOptEventEditTypeDrop.Refresh()
  if not kind then ItemRackOptEventEditTypeDrop:SetText(L["Pick one"]) end
end

function Opt.EventEditClearFrame()
  ItemRackOptEventEditNameEdit:SetText("")
  Opt.SetEventType(nil)
  ItemRackOptEventEditBuffName:SetText("")
  ItemRackOptEventEditBuffAnyMount:SetChecked(false)
  ItemRackOptEventEditBuffUnequip:SetChecked(false)
  ItemRackOptEventEditBuffNotInPVP:SetChecked(false)
  ItemRackOptEventEditBuffNotInPVE:SetChecked(false)
  ItemRackOptEventEditStanceName:SetText("")
  ItemRackOptEventEditStanceUnequip:SetChecked(false)
  ItemRackOptEventEditStanceNotInPVP:SetChecked(false)
  ItemRackOptEventEditZoneEditBox:SetText("")
  ItemRackOptEventEditZoneUnequip:SetChecked(false)
  ItemRackOptEventEditScriptTrigger:SetText("")
  ItemRackOptEventEditScriptEditBox:SetText("")
end

function Opt.ConvertZoneTableToList(t)
  local list = ""
  for zone in pairs(t or {}) do list = list .. zone .. "\n" end
  return list
end

function Opt.ConvertZoneListToTable(list, t)
  for line in string.gmatch(list .. "\n", "(.-)\n") do
    if strlen(line) > 0 then t[line] = 1 end
  end
end

function Opt.EventEditPopulateFrame()
  local idx = Opt.EventSelected
  local eventName = idx and Opt.EventList[idx] and Opt.EventList[idx][1]
  local event = eventName and ItemRackEvents[eventName]
  Opt.EventEditClearFrame()
  if event then
    ItemRackOptEventEditNameEdit:SetText(eventName)
    ItemRackOptEventEditNameEdit:SetCursorPosition(0)
    Opt.SetEventType(event.Type)
    ItemRackOptEventEditBuffName:SetText(event.Buff or "")
    ItemRackOptEventEditBuffName:SetCursorPosition(0)
    if event.Anymount then
      ItemRackOptEventEditBuffAnyMount:SetChecked(true)
      ItemRackOptEventEditBuffName:SetText(L["Any mount"])
    end
    ItemRackOptEventEditBuffUnequip:SetChecked(event.Unequip)
    ItemRackOptEventEditBuffNotInPVP:SetChecked(event.NotInPVP)
    ItemRackOptEventEditBuffNotInPVE:SetChecked(event.NotInPVE)
    ItemRackOptEventEditStanceName:SetText(event.Stance and tostring(event.Stance) or "")
    ItemRackOptEventEditStanceUnequip:SetChecked(event.Unequip)
    ItemRackOptEventEditStanceNotInPVP:SetChecked(event.NotInPVP)
    ItemRackOptEventEditZoneEditBox:SetText(Opt.ConvertZoneTableToList(event.Zones))
    ItemRackOptEventEditZoneEditBox:SetCursorPosition(0)
    ItemRackOptEventEditZoneUnequip:SetChecked(event.Unequip)
    ItemRackOptEventEditScriptTrigger:SetText(event.Trigger or "")
    ItemRackOptEventEditScriptTrigger:SetCursorPosition(0)
    ItemRackOptEventEditScriptEditBox:SetText(event.Script or "")
    ItemRackOptEventEditScriptEditBox:SetCursorPosition(0)
  else
    ItemRackOptEventEditNameEdit:SetFocus()
  end
  Opt.EventEditAnyMountChanged()
  Opt.EventEditDisplayType()
end

function Opt.EventEditDisplayType()
  for _, kind in ipairs(EVENT_TYPES) do
    _G["ItemRackOptEventEdit" .. kind .. "Frame"]:SetShown(kind == Opt.EventType)
  end
  Opt.EventEditValidateButtons()
end

function Opt.EventEditAnyMountChanged()
  local item = ItemRackOptEventEditBuffName
  if ItemRackOptEventEditBuffAnyMount:GetChecked() then
    item:EnableMouse(false)
    item:SetTextColor(S.Color(C.dim))
    item:ClearFocus()
  else
    item:EnableMouse(true)
    item:SetTextColor(S.Color(C.text))
  end
  Opt.EventEditValidateButtons()
end

function Opt.EventEditValidateButtons()
  if not built then return end
  local safe = true
  if strlen(ItemRackOptEventEditNameEdit:GetText() or "") < 1 then safe = false end
  local eventType = Opt.EventType
  if eventType == "Buff" then
    if not ItemRackOptEventEditBuffAnyMount:GetChecked() then
      local test = ItemRackOptEventEditBuffName:GetText() or ""
      if test == L["Any mount"] or strlen(test) < 1 then safe = false end
    end
  elseif eventType == "Stance" then
    if strlen(ItemRackOptEventEditStanceName:GetText() or "") < 1 then safe = false end
  elseif eventType == "Zone" then
    if strlen(ItemRackOptEventEditZoneEditBox:GetText() or "") < 1 then safe = false end
  elseif eventType == "Script" then
    local test = ItemRackFloatingEditor:IsShown() and ItemRackFloatingEditorEditBox:GetText() or ItemRackOptEventEditScriptEditBox:GetText()
    if strlen(ItemRackOptEventEditScriptTrigger:GetText() or "") < 1 or strlen(test or "") < 1 then safe = false end
  else
    safe = false
  end
  ItemRackOptEventEditSave:SetEnabled(safe)
  ItemRackFloatingEditorSave:SetEnabled(safe)
  return safe
end

function Opt.EventEditSave(override)
  if ItemRackFloatingEditor:IsShown() then ItemRackFloatingEditor:Hide() end
  ItemRackOptEventEditNameEdit:ClearFocus()
  local eventName = ItemRackOptEventEditNameEdit:GetText()
  if not override then
    local oldName = Opt.EventSelected and Opt.EventList[Opt.EventSelected] and Opt.EventList[Opt.EventSelected][1]
    if ItemRackEvents[eventName] and oldName ~= eventName then
      ItemRackOptEventEditSave:Disable()
      ItemRackOptEventEditCancel:Disable()
      local function restore()
        ItemRackOptEventEditCancel:Enable()
        Opt.EventEditValidateButtons()
      end
      S.Confirm(L["An event with that name already exists.\nDo you want to overwrite it?"], {
        { L["Yes"], function() restore() Opt.EventEditSave(1) end },
        { L["No"], restore },
      })
      return
    end
  end
  ItemRackEvents[eventName] = {}
  local event = ItemRackEvents[eventName]
  event.Type = Opt.EventType
  if event.Type == "Buff" then
    event.Anymount = ItemRackOptEventEditBuffAnyMount:GetChecked() and 1 or nil
    event.Buff = not event.Anymount and ItemRackOptEventEditBuffName:GetText() or nil
    event.Unequip = ItemRackOptEventEditBuffUnequip:GetChecked() and 1 or nil
    event.NotInPVP = ItemRackOptEventEditBuffNotInPVP:GetChecked() and 1 or nil
    event.NotInPVE = ItemRackOptEventEditBuffNotInPVE:GetChecked() and 1 or nil
  elseif event.Type == "Stance" then
    event.Stance = ItemRackOptEventEditStanceName:GetText()
    if tonumber(event.Stance) then event.Stance = tonumber(event.Stance) end
    event.Unequip = ItemRackOptEventEditStanceUnequip:GetChecked() and 1 or nil
    event.NotInPVP = ItemRackOptEventEditStanceNotInPVP:GetChecked() and 1 or nil
  elseif event.Type == "Zone" then
    event.Unequip = ItemRackOptEventEditZoneUnequip:GetChecked() and 1 or nil
    event.Zones = {}
    Opt.ConvertZoneListToTable(ItemRackOptEventEditZoneEditBox:GetText(), event.Zones)
  elseif event.Type == "Script" then
    event.Trigger = ItemRackOptEventEditScriptTrigger:GetText()
    event.Script = ItemRackOptEventEditScriptEditBox:GetText()
    ItemRackUser.Events.Enabled[eventName] = true
    ItemRackUser.EnableEvents = "ON"
    ItemRack.ReflectEventsRunning()
  end
  ItemRack.Print(L["Event \"%s\" saved."]:format(eventName))
  ItemRackOptSubFrame8:Hide()
  Opt.PopulateEventList()
  for i = 1, #Opt.EventList do
    if Opt.EventList[i][1] == eventName then Opt.EventSelected = i break end
  end
  Opt.EventListScrollFrameUpdate()
  Opt.ValidateEventListButtons()
end

function Opt.EventEditDelete(override)
  local eventName = Opt.EventList[Opt.EventSelected][1]
  -- a tagged event first loses its set and enabled state
  if ItemRackUser.Events.Set[eventName] or ItemRackUser.Events.Enabled[eventName] then
    ItemRackUser.Events.Set[eventName] = nil
    ItemRackUser.Events.Enabled[eventName] = nil
    Opt.PopulateEventList()
    return
  end
  if not override then
    ItemRackOptEventEdit:Disable()
    ItemRackOptEventDelete:Disable()
    ItemRackOptEventNew:Disable()
    local function restore() ItemRackOptEventNew:Enable() Opt.ValidateEventListButtons() end
    S.Confirm(L["Are you sure you want to delete the event \"%s\"?"]:format(eventName), {
      { L["Yes"], function() restore() Opt.EventEditDelete(1) end },
      { L["No"], restore },
    })
    return
  end
  ItemRackEvents[eventName] = nil
  Opt.EventSelected = nil
  ItemRack.CleanupEvents()
  Opt.PopulateEventList()
  ItemRack.Print(L["Event \"%s\" deleted."]:format(eventName))
end

function Opt.ToggleEventEditor()
  if not ItemRackFloatingEditor:IsShown() then
    ItemRackFloatingEditorEditBox:SetText(ItemRackOptEventEditScriptEditBox:GetText())
    Opt.MakeEscable("ItemRackFloatingEditor", "add")
    Opt.MakeEscable("ItemRackOptSubFrame8", "remove")
    ItemRackOptEventEditScriptEditLabel:Hide()
    ItemRackOptEventEditScriptEditBackdrop:Hide()
    ItemRackFloatingEditor:Show()
  else
    ItemRackFloatingEditor:Hide()
  end
end

function Opt.FloatingEditorOnHide()
  Opt.MakeEscable("ItemRackFloatingEditor", "remove")
  if ItemRackOptEventEditScriptFrame:IsVisible() then
    Opt.MakeEscable("ItemRackOptSubFrame8", "add")
  end
  ItemRackOptEventEditScriptEditBox:SetText(ItemRackFloatingEditorEditBox:GetText())
  ItemRackOptEventEditScriptEditLabel:Show()
  ItemRackOptEventEditScriptEditBackdrop:Show()
end

--[[ Window ]]-------------------------------------------------------------------------------

function Opt.OnShow()
  for i = 0, 19 do Opt.Inv[i].id = ItemRack.GetID(i) end
  local current = ItemRackUser.CurrentSet
  if current and ItemRackUser.Sets[current] then
    ItemRackOptSetsName:SetText(current)
    Opt.selectedIcon = ItemRackUser.Sets[current].icon
    for i = 0, 19 do
      local id = ItemRackUser.Sets[current].equip[i]
      Opt.Inv[i].selected = id and 1 or nil
      if id then Opt.Inv[i].id = id end
    end
  else
    ItemRackOptSetsName:SetText("")
    for i = 0, 19 do Opt.Inv[i].selected = nil end
    Opt.selectedIcon = Opt.Icons[math.random(math.max(1, #Opt.Icons - 22)) + 22] or ItemRack.ICON
  end
  Opt.UpdateInv()
  ItemRackOptSubFrame5:Hide()
  Opt.ListScrollFrameUpdate()
end

function Opt.ChangeEditingSet()
  local setname = ItemRackUser.CurrentSet
  if setname and ItemRackUser.Sets[setname] then
    local set = ItemRackUser.Sets[setname].equip
    for i = 0, 19 do
      if set[i] then
        Opt.Inv[i].id = set[i]
        Opt.Inv[i].selected = 1
      else
        Opt.Inv[i].selected = nil
        Opt.Inv[i].id = ItemRack.GetID(i)
      end
    end
    ItemRackOptSetsName:SetText(setname)
    Opt.selectedIcon = ItemRackUser.Sets[setname].icon
    Opt.UpdateInv()
    ItemRackOptSubFrame5:Hide()
  end
end

-- central handler for the buttons of the window
function Opt.ButtonOnClick(self)
  local b = self.irName or self:GetName()
  if b == "ItemRackOptToggleInvAll" then
    Opt.ToggleAll()
  elseif b == "ItemRackOptClose" then
    ItemRackOptFrame:Hide()
  elseif b == "ItemRackOptSetsSaveButton" then
    Opt.SaveSet()
  elseif b == "ItemRackOptSetsDeleteButton" then
    Opt.DeleteSet()
    Opt.ValidateSetButtons()
  elseif b == "ItemRackOptSetsBindButton" then
    Opt.BindSet()
  elseif b == "ItemRackOptSetsDropDownButton" then
    ItemRackOptSubFrame5:Show()
  elseif b == "ItemRackOptSetListClose" then
    ItemRackOptSubFrame5:Hide()
  elseif b == "ItemRackOptSlotBindCancel" then
    ItemRackOptSubFrame6:Hide()
  elseif b == "ItemRackOptBindCancel" then
    ItemRackOptBindFrame:Hide()
  elseif b == "ItemRackOptBindUnbind" then
    Opt.UnbindKey()
    ItemRackOptBindFrame:Hide()
  elseif b == "ItemRackOptKeyBindings" then
    ItemRackOptSubFrame6:Show()
  elseif b == "ItemRackOptSortListClose" then
    ItemRackOptSubFrame7:Hide()
  elseif b == "ItemRackOptResetBar" then
    ItemRack.ResetButtons()
  elseif b == "ItemRackOptResetEverything" then
    ItemRack.ResetEverything()
  elseif b == "ItemRackOptResetEvents" then
    ItemRack.ResetEvents()
  elseif b == "ItemRackOptEventNew" then
    Opt.EventSelected = nil
    Opt.EventListScrollFrameUpdate()
    Opt.ValidateEventListButtons()
    ItemRackOptSubFrame8:Show()
  elseif b == "ItemRackOptEventEdit" then
    ItemRackOptSubFrame8:Show()
  elseif b == "ItemRackOptEventDelete" then
    Opt.EventEditDelete()
  elseif b == "ItemRackOptEventEditSave" then
    Opt.EventEditSave()
  elseif b == "ItemRackOptEventEditCancel" then
    ItemRackOptSubFrame8:Hide()
  elseif b == "ItemRackOptEventEditExpand" then
    Opt.ToggleEventEditor()
  elseif b == "ItemRackFloatingEditorClose" then
    ItemRackFloatingEditor:Hide()
  elseif b == "ItemRackFloatingEditorSave" then
    ItemRackFloatingEditor:Hide()
    Opt.EventEditSave()
  elseif b == "ItemRackFloatingEditorTest" then
    local method, err = loadstring("local arg1,arg2,arg3,arg4,arg5 = ...; " .. ItemRackFloatingEditorEditBox:GetText())
    if not method then
      ItemRack.Print("|cFFFF6A5A" .. tostring(err) .. "|r")
    else
      local ok, runErr = pcall(method)
      ItemRack.Print(ok and L["The script ran without errors."] or ("|cFFFF6A5A" .. tostring(runErr) .. "|r"))
    end
  elseif b == "ItemRackFloatingEditorUndo" then
    ItemRackFloatingEditorEditBox:SetText(ItemRackOptEventEditScriptEditBox:GetText())
  end
end
local click = function(self) Opt.ButtonOnClick(self) end

--[[ Building the window ]]------------------------------------------------------------------

-- the tabs (ItemRackTabTemplate, 46x24, running leftward from the close button): the
-- chosen one is drawn disabled, joined to the window
local TABS = S.MEDIA .. "ItemRackOptTabs"
local function makeTab(parent, id, label)
  local t = CreateFrame("Button", "ItemRackOptTab" .. id, parent)
  t:SetSize(46, 24)
  t:SetID(id)
  t:SetNormalTexture(TABS)
  t:GetNormalTexture():SetTexCoord(0, .765625, 0, .375)
  t:SetDisabledTexture(TABS)
  t:GetDisabledTexture():SetTexCoord(0, .765625, .5, .875)
  t:SetHighlightTexture(TABS, "ADD")
  t:GetHighlightTexture():SetTexCoord(0, .765625, 0, .375)
  t:GetHighlightTexture():SetAlpha(.4)
  t:SetNormalFontObject(GameFontHighlightSmall)
  t:SetHighlightFontObject(GameFontHighlightSmall)
  t:SetDisabledFontObject(GameFontHighlightSmall)
  t:SetText(label)
  t.text = t:GetFontString()
  t.text:ClearAllPoints()
  t.text:SetPoint("CENTER", 0, -1)
  t.text:SetWordWrap(false)
  t.text:SetWidth(44)
  t.text:SetTextColor(.75, .75, .75)
  function t:SetSelected(on)
    self.selected = on
    if on then self:Disable() else self:Enable() end
    local c = on and 1 or .75
    self.text:SetTextColor(c, c, c)
  end
  t:SetScript("OnEnter", function(self) if not self.selected then self.text:SetTextColor(1, 1, 1) end end)
  t:SetScript("OnLeave", function(self) if not self.selected then self.text:SetTextColor(.75, .75, .75) end end)
  t:SetScript("OnClick", function(self)
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841)
    Opt.TabOnClick(self)
  end)
  return t
end

-- ItemRackOptSubFrameTemplate: 194x282 under the tabs
local function subFrame(name, w, h)
  local f = CreateFrame("Frame", name, ItemRackOptFrame)
  f:SetSize(w or 194, h or 282)
  f:SetPoint("TOP", ItemRackOptFrame, "TOP", 0, -21)
  S.Panel(f)
  f:Hide()
  return f
end

-- a list with a thin scroll bar at its right edge
local function faux(holder, visible, update, name, step)
  local scroll = S.FauxScroll(holder, visible, update, step)
  scroll.bar:SetPoint("TOPLEFT", holder, "TOPRIGHT", 3, 0)
  scroll.bar:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", 3, 0)
  return named(scroll, name)
end

local function buildPaperdoll(f)
  local function inv(id)
    local b = CreateFrame("Button", "ItemRackOptInv" .. id, f)
    b:SetSize(36, 36)
    b:SetID(id)
    S.SkinItemButton(b, "ItemRackOptInv" .. id)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self)
      PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
      Opt.ToggleInvSelect(self)
    end)
    b:HookScript("OnEnter", Opt.InvOnEnter)
    b:HookScript("OnLeave", Opt.InvOnLeave)
    ItemRack.MenuMouseoverFrames["ItemRackOptInv" .. id] = 1
    return b
  end
  local prev
  for _, id in ipairs({ 1, 2, 3, 15, 5, 4, 19, 9 }) do
    local b = inv(id)
    if prev then b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4) else b:SetPoint("TOPLEFT", 8, -24) end
    prev = b
  end
  prev = nil
  for _, id in ipairs({ 10, 6, 7, 8, 11, 12, 13, 14 }) do
    local b = inv(id)
    if prev then b:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -4) else b:SetPoint("TOPRIGHT", -8, -24) end
    prev = b
  end
  inv(16):SetPoint("BOTTOM", -38, 8)
  inv(17):SetPoint("BOTTOMLEFT", ItemRackOptInv16, "BOTTOMRIGHT", 4, 0)
  inv(18):SetPoint("BOTTOMLEFT", ItemRackOptInv17, "BOTTOMRIGHT", 4, 0)
  inv(0):SetPoint("LEFT", ItemRackOptInv18, "RIGHT", 6, 0)
  ItemRackOptInv0:SetScale(.8)

  local all = small(f, "ItemRackOptToggleInvAll", "ToggleAll", 24, click)
  all:SetPoint("TOPRIGHT", ItemRackOptInv16, "TOPLEFT", -10, -8)
  tooltip(all, L["Toggle All"], L["This will toggle between selecting all slots and selecting no slots."])
end

-- SubFrame1: the settings list
local function buildConfig()
  local sf = subFrame("ItemRackOptSubFrame1")
  local holder = CreateFrame("Frame", nil, sf)
  holder:SetPoint("TOPLEFT", 8, -10)
  holder:SetSize(156, 11 * 24)
  for i = 1, 11 do
    local row = CreateFrame("Button", "ItemRackOptList" .. i, holder)
    row:SetSize(156, 24)
    row:SetID(i)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.label:SetJustifyH("LEFT")
    row.label:SetPoint("LEFT", 2, 0)
    row.underline = row:CreateTexture(nil, "BACKGROUND")
    row.underline:SetPoint("BOTTOMLEFT", 0, 3)
    row.underline:SetPoint("BOTTOMRIGHT", 0, 3)
    row.underline:SetHeight(1)
    row.underline:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    S.Gradient(row.underline, { .25, .25, .25, 1 }, { 0, 0, 0, 1 }, false, true)
    row.checkText = text(row, 10, "text", nil, "LEFT")
    row.checkText:SetSize(128, 24)
    row.checkText:SetPoint("RIGHT")
    row.checkText:SetWordWrap(false)
    row.numberLabel = text(row, 10, "text", nil, "LEFT")
    row.numberLabel:SetPoint("LEFT", 24, 0)
    row.check = S.Check(row, nil, 24, Opt.OptListCheckButtonOnClick)
    row.check:SetPoint("RIGHT", row.checkText, "LEFT", 0, 0)
    row.check:HookScript("OnEnter", function(self) Opt.OptListOnEnter(self, row:GetID()) end)
    row.check:HookScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", Opt.OptListOnClick)
    row:SetScript("OnMouseDown", function()
      if not (row.check:IsVisible() and row.check:IsEnabled()) then ItemRackOptFrame:StartMoving() end
    end)
    row:SetScript("OnMouseUp", function() ItemRackOptFrame:GetScript("OnMouseUp")(ItemRackOptFrame) end)
    row:SetScript("OnEnter", function(self)
      Opt.OptListOnEnter(self, self:GetID())
      if self.check:IsVisible() and self.check:IsEnabled() then self.check:LockHighlight() end
    end)
    row:SetScript("OnLeave", function(self)
      GameTooltip:Hide()
      self.check:UnlockHighlight()
    end)
  end
  faux(holder, 11, function() Opt.ListScrollFrameUpdate() end, "ItemRackOptListScrollFrame")

  -- the widgets the list places on its rows
  local function listButton(name, label)
    local b = button(sf, name, label, 128, 22, click, true)
    b:SetNormalFontObject(GameFontNormalSmall)
    b:HookScript("OnEnter", function(self) Opt.OptListOnEnter(self) end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
  end
  listButton("ItemRackOptKeyBindings", L["Slot Key Bindings"])
  listButton("ItemRackOptResetBar", L["Reset Buttons"])
  listButton("ItemRackOptResetEvents", L["Reset Events"])
  listButton("ItemRackOptResetEverything", L["Reset Everything"])

  local function numberPair(variable, min, max, step, form)
    local e = S.EditBox(sf, 32, 20, "number")
    named(e, "ItemRackOpt" .. variable)
    e.variable = variable
    e:SetJustifyH("CENTER")
    e:SetScript("OnEnterPressed", Opt.NumberEditBoxOnEnter)
    e:SetScript("OnEscapePressed", Opt.NumberEditBoxOnEscape)
    e:SetScript("OnEnter", function(self) Opt.OptListOnEnter(self) end)
    e:SetScript("OnLeave", function() GameTooltip:Hide() end)
    e:Hide()
    local s = S.Slider(sf, 96, min, max, step, form, "", function(value)
      if ItemRackUser[variable] ~= nil then
        ItemRackUser[variable] = value
        Opt.UpdateSlider(variable)
      end
    end)
    named(s, "ItemRackOpt" .. variable .. "Slider")
    s.label:Hide()
    s.value:Hide()
    s.form, s.min, s.max = form, min, max
    local lo = text(s, 10, "muted", form:format(min), "RIGHT")
    lo:SetPoint("RIGHT", s, "LEFT", -2, 0)
    local hi = text(s, 10, "muted", form:format(max), "LEFT")
    hi:SetPoint("LEFT", s, "RIGHT", 2, 0)
    s:HookScript("OnEnter", function(self) Opt.OptListOnEnter(self) end)
    s:HookScript("OnLeave", function() GameTooltip:Hide() end)
    s:Hide()
  end
  -- the language of the addon (applied on reload)
  local lang = S.Dropdown(sf, 84, function() return ns.LANGUAGES end,
    function() return ItemRackSettings.Language end, function(v)
      if v == ItemRackSettings.Language then return end
      ItemRackSettings.Language = v
      S.Confirm(L["The language changes once the interface is reloaded.\nReload now?"], {
        { L["Reload"], ReloadUI },
        { L["Later"] },
      })
    end)
  named(lang, "ItemRackOptLanguage")
  lang:SetHeight(20)
  lang:HookScript("OnEnter", function(self) Opt.OptListOnEnter(self) end)
  lang:HookScript("OnLeave", function() GameTooltip:Hide() end)
  lang:Hide()

  numberPair("ButtonSpacing", 0, 24, 1, "%d")
  numberPair("Alpha", .1, 1, .05, "%.2f")
  numberPair("MainScale", .5, 2, .05, "%.2f")
  numberPair("MenuScale", .5, 2, .05, "%.2f")
  numberPair("SetMenuWrapValue", 1, 30, 1, "%d")

  local U = function() return ItemRackUser end
  local G = function() return ItemRackSettings end
  -- type = "label", "check", "number", "slider", "button"; depend = needs that setting ON;
  -- combatlock = can't be changed in combat
  Opt.OptInfo = {
    { type = "label", label = "" },
    { type = "check", optset = U, variable = "Locked", label = L["Lock Buttons"], tooltip = L["Prevent buttons and menus from being moved."] },
    { type = "check", optset = U, variable = "EnableEvents", label = L["Enable events"], tooltip = L["Enable events to automatically swap gear."] },
    { type = "check", optset = U, variable = "EnableQueues", label = L["Enable auto queues"], tooltip = L["Enables auto queues to automatically swap gear."] },
    { type = "check", optset = U, variable = "EnablePerSetQueues", depend = "EnableQueues", label = L["Enable per-set queues"], tooltip = L["Enable individual auto queues per set."] },
    { type = "number", variable = "ButtonSpacing", button = ItemRackOptButtonSpacing, label = L["Button spacing"], tooltip = L["Padding distance between buttons."], combatlock = 1 },
    { type = "slider", variable = "ButtonSpacing", button = ItemRackOptButtonSpacingSlider, label = L["Button spacing"], tooltip = L["Padding distance between buttons."], form = "%d", combatlock = 1 },
    { type = "number", variable = "Alpha", button = ItemRackOptAlpha, label = L["Transparency"], tooltip = L["Transparency (alpha) of the buttons and menu."] },
    { type = "slider", variable = "Alpha", button = ItemRackOptAlphaSlider, label = L["Transparency"], tooltip = L["Transparency (alpha) of the buttons and menu."], form = "%.2f" },
    { type = "number", variable = "MainScale", button = ItemRackOptMainScale, label = L["Button scale"], tooltip = L["Scale size of the item buttons."], combatlock = 1 },
    { type = "slider", variable = "MainScale", button = ItemRackOptMainScaleSlider, label = L["Button scale"], tooltip = L["Scale size of the item buttons."], form = "%.2f", combatlock = 1 },
    { type = "number", variable = "MenuScale", button = ItemRackOptMenuScale, label = L["Menu scale"], tooltip = L["Scale size of the menu in relation to the button it's docked to."] },
    { type = "slider", variable = "MenuScale", button = ItemRackOptMenuScaleSlider, label = L["Menu scale"], tooltip = L["Scale size of the menu in relation to the button it's docked to."], form = "%.2f" },
    { type = "check", optset = U, variable = "SetMenuWrap", label = L["Set menu wrap"], tooltip = L["Check this to set a fixed value when the menu wraps to a new row.  Uncheck to let ItemRack decide."] },
    { type = "number", variable = "SetMenuWrapValue", depend = "SetMenuWrap", button = ItemRackOptSetMenuWrapValue, label = L["When to wrap"], tooltip = L["When 'Set menu wrap' checked, this is the number of menu items before wrapping to a new row/column."] },
    { type = "slider", variable = "SetMenuWrapValue", depend = "SetMenuWrap", button = ItemRackOptSetMenuWrapValueSlider, label = L["When to wrap"], tooltip = L["When 'Set menu wrap' checked, this is the number of menu items before wrapping to a new row/column."], form = "%d" },
    { type = "label", label = L["Global Settings"] },
    { type = "drop", button = ItemRackOptLanguage, label = L["Language"], tooltip = L["Language of the addon (English or French). The interface is reloaded to apply it."] },
    { type = "check", optset = G, variable = "MenuOnShift", label = L["Menu on Shift"], tooltip = L["Only show menu while Shift is held down."] },
    { type = "check", optset = G, variable = "MenuOnRight", label = L["Menu on right click"], tooltip = L["Open menu by right clicking buttons."], combatlock = 1 },
    { type = "check", optset = G, variable = "HideOOC", label = L["Hide out of combat"], tooltip = L["Hide the buttons while out of combat."], combatlock = 1 },
    { type = "check", optset = G, variable = "Notify", label = L["Notify when ready"], tooltip = L["Announce when an item you used comes off cooldown."] },
    { type = "check", optset = G, variable = "NotifyThirty", label = L["Notify at 30"], tooltip = L["Announce when an item you used is at 30 seconds cooldown."] },
    { type = "check", optset = G, variable = "NotifyChatAlso", label = L["Notify chat also"], tooltip = L["Send cooldown notifications to chat also."] },
    { type = "check", optset = G, variable = "ShowSetInTooltip", label = L["Show set info in tooltips"], tooltip = L["Show which set an item belongs to in the tooltip."] },
    { type = "check", optset = G, variable = "ShowTooltips", label = L["Show tooltips"], tooltip = L["Show tooltips like the one you're reading now."] },
    { type = "check", optset = G, variable = "TinyTooltips", depend = "ShowTooltips", label = L["Tiny Tooltips"], tooltip = L["Shrink item tooltips to display only name, cooldown and durability."] },
    { type = "check", optset = G, variable = "TooltipFollow", depend = "ShowTooltips", label = L["Tooltips at pointer"], tooltip = L["Show tooltips near the mouse."] },
    { type = "check", optset = G, variable = "CooldownCount", label = L["Cooldown numbers"], tooltip = L["Display the cooldown time as a number over items."] },
    { type = "check", optset = G, variable = "LargeNumbers", depend = "CooldownCount", label = L["Large numbers"], tooltip = L["Use a larger font for cooldown numbers."] },
    { type = "check", optset = G, variable = "Cooldown90", depend = "CooldownCount", label = L["Countdown at 90"], tooltip = L["Use seconds instead of minutes starting at 90 seconds remaining."] },
    { type = "check", optset = G, variable = "AllowEmpty", label = L["Allow empty slots"], tooltip = L["Add an empty slot to menus of equipped items."] },
    { type = "check", optset = G, variable = "AllowHidden", label = L["Allow hidden items"], tooltip = L["Enable Alt+clicking of menu items to hide/show them in the menu.  Hold Alt as you enter a menu to show all."] },
    { type = "check", optset = G, variable = "HideTradables", label = L["Hide tradables"], tooltip = L["Prevent tradable items from showing up in the menu."] },
    { type = "check", optset = G, variable = "ShowMinimap", label = L["Show minimap button"], tooltip = L["Show the minimap button to access options or change sets."] },
    { type = "check", optset = G, variable = "MinimapTooltip", depend = "ShowMinimap", label = L["Show minimap tooltip"], tooltip = L["If tooltips enabled, show what mouse clicks will do when clicking the minimap button."] },
    { type = "check", optset = G, variable = "TrinketMenuMode", label = L["TrinketMenu mode"], tooltip = L["When mouseover of either trinket slot, open anchored to the top trinket.  Left click of a menu item will equip to the top trinket.  Right click will equip to the bottom trinket."] },
    { type = "check", optset = G, variable = "AnchorOther", depend = "TrinketMenuMode", label = L["Anchor other trinket"], tooltip = L["In TrinketMenu mode, trinket menus dock to the top trinket.  Check this to anchor them to the bottom trinket."] },
    { type = "check", optset = G, variable = "EquipToggle", label = L["Toggle sets on equip"], tooltip = L["When a set is equipped, if it's already equipped, unequip it."] },
    { type = "check", optset = G, variable = "ShowHotKeys", label = L["Show key bindings"], tooltip = L["Display key bindings on buttons"] },
    { type = "check", optset = G, variable = "EquipOnSetPick", label = L["Equip in options"], tooltip = L["Check this to equip sets and items when selecting items in options or from the dropdown in the Sets tab."] },
    { type = "check", optset = G, variable = "CharacterSheetMenus", label = L["Character sheet menus"], tooltip = L["While this is checked, mouseover of slots on the character sheet will pop out a menu of items that can go in that slot."] },
    { type = "check", optset = G, variable = "DisableAltClick", label = L["Disable Alt+Click"], tooltip = L["Alt+Click on buttons dragged from the character sheet toggles auto queue for that slot.  Check this to disable that behavior. (ie to use Alt+click to self cast instead.)"], combatlock = 1 },
    { type = "label", label = "" },
    { type = "button", button = ItemRackOptKeyBindings, label = L["Slot Key Bindings"], tooltip = L["Set key bindings to use slots."], combatlock = 1 },
    { type = "button", button = ItemRackOptResetBar, label = L["Reset Buttons"], tooltip = L["Remove all buttons and restore to default alpha and scale."], combatlock = 1 },
    { type = "button", button = ItemRackOptResetEvents, label = L["Reset Events"], tooltip = L["Restore default events or wipe all events to default settings."] },
    { type = "button", button = ItemRackOptResetEverything, label = L["Reset Everything"], tooltip = L["Wipe all settings, sets and events to restore mod to a default state."], combatlock = 1 },
  }
  sf:SetScript("OnShow", function() Opt.ListScrollFrameUpdate() end)
end

-- SubFrame2: name, icon and options of the set being built
local function buildSets()
  local sf = subFrame("ItemRackOptSubFrame2")
  local label = text(sf, 10, "muted", L["Choose a name and icon:"], "LEFT", "ItemRackOptSetsChooseLabel")
  label:SetPoint("TOP", 0, -8)
  local name = S.EditBox(sf, 120, 20, "big")
  named(name, "ItemRackOptSetsName")
  -- name + its arrow (5 + 18) centered as one row
  name:SetPoint("TOP", sf, "TOP", -12, -23)
  name:SetMaxLetters(64)
  name:SetScript("OnTextChanged", function() Opt.ValidateSetButtons() end)
  name:SetScript("OnEnterPressed", function(self) self:ClearFocus() Opt.LoadSet() end)
  local drop = small(sf, "ItemRackOptSetsDropDownButton", "Down", 18, click)
  drop:SetPoint("LEFT", name, "RIGHT", 5, 0)
  tooltip(drop, L["Saved sets"], L["Pick a saved set to edit it. Hover the list to preview the sets on the left."])
  -- (Forever) the set's specialization, under the name: don't change, spec 1 or spec 2
  local spec = S.Dropdown(sf, 120, function()
    return { { 0, L["Don't change"] }, { 1, L["Spec 1 (Primary)"] }, { 2, L["Spec 2 (Secondary)"] } }
  end, function() return Opt.spec or 0 end, function(v) Opt.SpecOnSelect(v) end)
  named(spec, "ItemRackOptSetsSpecDrop")
  -- its arrow outside the box, on the right, like the set name's
  spec.arrow:ClearAllPoints()
  spec.arrow:SetPoint("LEFT", spec, "RIGHT", 5, 0)
  spec.text:SetPoint("RIGHT", -2, 0)
  spec:SetPoint("TOP", sf, "TOP", -12, -49)
  tooltip(spec, L["Specialization"],
    L["Switch to this specialization when the set is equipped (out of combat, outside battlegrounds)."])

  local iconFrame = box(sf, "ItemRackOptSetsIconFrame")
  iconFrame:SetSize(178, 128)
  iconFrame:SetPoint("TOP", 0, -76)
  local grid = CreateFrame("Frame", nil, iconFrame)
  grid:SetPoint("TOPLEFT", 8, -8)
  grid:SetSize(140, 112)
  for i = 1, 20 do
    local b = CreateFrame("Button", "ItemRackOptSetsIcon" .. i, grid)
    b:SetSize(28, 28)
    b:SetID(i)
    b:SetPoint("TOPLEFT", ((i - 1) % 5) * 28, -math.floor((i - 1) / 5) * 28)
    S.SkinItemButton(b, "ItemRackOptSetsIcon" .. i, true)
    b:SetScript("OnClick", Opt.SetsIconOnClick)
  end
  local scroll = faux(grid, 4, function() Opt.SetsIconScrollFrameUpdate() end, "ItemRackOptSetsIconScrollFrame")
  scroll.bar:ClearAllPoints()
  scroll.bar:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", -10, -8)
  scroll.bar:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -10, 8)

  local save = button(sf, "ItemRackOptSetsSaveButton", L["Save"], 55, 26, click)
  save:SetPoint("TOPRIGHT", iconFrame, "BOTTOMRIGHT", -4, -6)
  tooltip(save, L["Save Set"], L["Save this set. Some settings like key binding and whether it's hidden can only be changed to a saved set."])
  local bind = button(sf, "ItemRackOptSetsBindButton", L["Bind Key"], 55, 26, click)
  bind:SetPoint("TOPRIGHT", save, "BOTTOMRIGHT", 0, -4)
  tooltip(bind, L["Bind Key to Set"], L["This will let you bind a key or key combination to equip a set."])
  local delete = button(sf, "ItemRackOptSetsDeleteButton", L["Delete"], 55, 26, click)
  delete:SetPoint("TOPRIGHT", bind, "TOPLEFT", -4, 0)
  tooltip(delete, L["Delete Set"], L["Delete this set definition. If you want to remove it from the menu and may want it again in the future, check 'Hide' to the left."])

  local current = CreateFrame("Button", "ItemRackOptSetsCurrentSet", sf)
  current:SetSize(36, 36)
  current:SetPoint("TOPLEFT", iconFrame, "BOTTOMLEFT", 8, -8)
  S.SkinItemButton(current, "ItemRackOptSetsCurrentSet")
  current:EnableMouse(false)

  local hide = check(sf, "ItemRackOptSetsHideCheckButton", L["Hide"], 14, function() Opt.HideSet() end)
  hide:FitLabel(36) -- the Delete button starts right after
  hide:SetPoint("TOPLEFT", current, "BOTTOMLEFT", -2, -6)
  tooltip(hide, L["Hide"], L["Hide this set in menus. (Equivalent of Alt+clicking the set in the menu)"])
  sf:SetScript("OnShow", function() Opt.SetsIconScrollFrameUpdate() end)
end

-- SubFrame3: the events
local function buildEvents()
  local sf = subFrame("ItemRackOptSubFrame3")
  local label = text(sf, 10, "muted", L["Check an event to enable it:"], "LEFT", "ItemRackOptEventsLabel")
  label:SetPoint("TOPLEFT", 20, -8)
  local list = box(sf, "ItemRackOptEventListFrame")
  list:SetSize(178, 230)
  list:SetPoint("TOP", 0, -20)
  local holder = CreateFrame("Frame", nil, list)
  holder:SetPoint("TOPLEFT", 8, -7)
  holder:SetSize(152, 9 * 24)
  for i = 1, 9 do
    local row = CreateFrame("Button", "ItemRackOptEventList" .. i, holder)
    row:SetSize(152, 24)
    row:SetID(i)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
    S.RowHighlight(row)
    row.name = text(row, 10, "text", nil, "LEFT")
    row.name:SetPoint("TOPLEFT", 48, 0)
    row.name:SetPoint("BOTTOMRIGHT", -2, 0)
    row.name:SetWordWrap(false)
    row.enabled = S.Check(row, nil, 24, Opt.EventListEnabledOnClick)
    row.enabled:SetPoint("LEFT", -1, 0)
    local ib = CreateFrame("Button", nil, row)
    ib:SetSize(22, 22)
    ib:SetPoint("TOPLEFT", 23, -1)
    S.SkinItemButton(ib, nil, true)
    ib:SetScript("OnClick", function() Opt.EventListIconOnClick(row) end)
    row.iconButton = ib
    row:SetScript("OnClick", Opt.EventListOnClick)
    row:SetScript("OnDoubleClick", Opt.EventListOnDoubleClick)
    for _, w in ipairs({ row, row.enabled, ib }) do
      w:HookScript("OnEnter", function(self)
        Opt.EventListOnEnter(self, row)
        if w ~= row then
          row.hovered = true
          row.highlight:Show()
        end
      end)
      w:HookScript("OnLeave", function()
        GameTooltip:Hide()
        if w ~= row then
          row.hovered = nil
          if not row.locked then row.highlight:Hide() end
        end
      end)
    end
  end
  faux(holder, 9, function() Opt.EventListScrollFrameUpdate() end, "ItemRackOptEventListScrollFrame")

  local edit = button(sf, "ItemRackOptEventEdit", L["Edit"], 55, 26, click)
  edit:SetPoint("BOTTOM", 0, 4)
  tooltip(edit, L["Edit Event"], L["Edit this event. Note: if you edit the name and save, it will create a copy of the event with the new name."])
  local delete = button(sf, "ItemRackOptEventDelete", L["Delete"], 55, 26, click)
  delete:SetPoint("RIGHT", edit, "LEFT", -4, 0)
  tooltip(delete, L["Delete Event"], L["If this event is enabled or has a set associated with it, it will remove the tags and drop it in the list.  If this is an untagged event, it will delete it entirely."])
  local new = button(sf, "ItemRackOptEventNew", L["New"], 55, 26, click)
  new:SetPoint("LEFT", edit, "RIGHT", 4, 0)
  tooltip(new, L["New Event"], L["Create a new event."])
  sf:SetScript("OnShow", function() Opt.PopulateEventList() end)
end

-- SubFrame4: the auto queue intro (pick a slot)
local function buildQueue()
  local sf = subFrame("ItemRackOptSubFrame4")
  local t = text(sf, 12, "text", L["Choose a slot to set up its auto queue order."], "CENTER")
  t:SetSize(120, 100)
  t:SetPoint("TOP", 0, -40)
  sf:SetScript("OnShow", Opt.QueuesFrameOnShow)
  sf:SetScript("OnHide", Opt.QueuesFrameOnHide)
end

-- SubFrame5: the set chooser
local function buildSetList()
  local sf = subFrame("ItemRackOptSubFrame5")
  local label = text(sf, 10, "muted", L["Choose a set:"], "LEFT", "ItemRackOptPickSetsChooseLabel")
  label:SetPoint("TOP", 0, -8)
  local list = box(sf)
  list:SetSize(178, 256)
  list:SetPoint("TOP", 0, -20)
  local holder = CreateFrame("Frame", nil, list)
  holder:SetPoint("TOPLEFT", 8, -8)
  holder:SetSize(152, 10 * 24)
  for i = 1, 10 do
    local row = CreateFrame("Button", "ItemRackOptSetList" .. i, holder)
    row:SetSize(152, 24)
    row:SetID(i)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
    S.RowHighlight(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("TOPLEFT", 3, -1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.key = text(row, 9, "gold", nil, "RIGHT")
    row.key:SetSize(50, 22)
    row.key:SetPoint("TOPRIGHT", -1, -1)
    row.name = text(row, 10, "text", nil, "LEFT")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, 0)
    row.name:SetPoint("BOTTOMRIGHT", row.key, "BOTTOMLEFT", 0, 0)
    row.name:SetWordWrap(false)
    row:HookScript("OnEnter", Opt.SetListOnEnter)
    row:SetScript("OnClick", Opt.SelectSetList)
  end
  local close = small(sf, "ItemRackOptSetListClose", "Close", 18, click)
  close:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", 0, 1)
  close:SetFrameLevel(list:GetFrameLevel() + 5)
  tooltip(close, L["Close"])
  faux(holder, 10, function() Opt.SetListScrollFrameUpdate() end, "ItemRackOptSetListScrollFrame")
  sf:SetScript("OnShow", Opt.PickSetOnShow)
  sf:SetScript("OnHide", Opt.PickSetOnHide)
end

-- SubFrame6: slot bindings (click a slot)
local function buildSlotBind()
  local sf = subFrame("ItemRackOptSubFrame6")
  local t = text(sf, 12, "text", L["Select a slot to bind to a key."], "CENTER")
  t:SetSize(128, 60)
  t:SetPoint("TOP", 0, -40)
  local cancel = button(sf, "ItemRackOptSlotBindCancel", L["Cancel"], 60, 26, click)
  cancel:SetPoint("BOTTOMRIGHT", -8, 8)
  sf:SetScript("OnShow", Opt.SlotBindFrameOnShow)
  sf:SetScript("OnHide", Opt.SlotBindFrameOnHide)
end

-- BindFrame: press a key
local function buildBindFrame()
  local sf = CreateFrame("Frame", "ItemRackOptBindFrame", ItemRackOptFrame)
  sf:SetSize(194, 282)
  sf:SetPoint("TOP", ItemRackOptFrame, "TOP", 0, -21)
  S.Backdrop(sf, "dialog", 0.5)
  sf:SetFrameLevel(ItemRackOptFrame:GetFrameLevel() + 10)
  sf:Hide()
  local t = text(sf, 12, "muted", L["Press a key to bind"], "CENTER")
  t:SetPoint("TOP", 0, -40)
  local bindee = text(sf, 14, "title", nil, "CENTER", "ItemRackOptBindFrameBindee")
  bindee:SetSize(170, 50)
  bindee:SetPoint("TOP", 0, -60)
  local currently = text(sf, 12, "text", nil, "CENTER", "ItemRackOptBindFrameCurrently")
  currently:SetSize(170, 50)
  currently:SetPoint("TOP", 0, -120)
  local cancel = button(sf, "ItemRackOptBindCancel", L["Cancel"], 60, 26, click)
  cancel:SetPoint("BOTTOMRIGHT", -8, 8)
  local unbind = button(sf, "ItemRackOptBindUnbind", L["Unbind"], 60, 26, click)
  unbind:SetPoint("BOTTOMRIGHT", cancel, "BOTTOMLEFT", -8, 0)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnShow", function(self)
    Opt.BindFrameOnShow()
  end)
  sf:SetScript("OnHide", Opt.BindFrameOnHide)
  sf:SetScript("OnKeyDown", Opt.BindFrameOnKeyDown)
  sf:SetScript("OnMouseUp", function(self, b) Opt.BindFrameOnKeyDown(self, b) end)
  sf:SetScript("OnMouseWheel", function(self, delta)
    Opt.BindFrameOnKeyDown(self, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
  end)
end

-- SubFrame7: the queue of a slot (covers the window)
local function buildSlotQueue()
  local sf = subFrame("ItemRackOptSubFrame7", 276, 320)
  local name = text(sf, 13, "title", nil, "LEFT", "ItemRackOptSlotQueueName")
  name:SetPoint("TOPLEFT", 14, -14)
  local enable = check(sf, "ItemRackOptQueueEnable", L["Auto Queue This Slot"], 15, Opt.QueueEnableSlotOnClick)
  enable:SetPoint("TOPRIGHT", -128, -12)
  tooltip(enable, L["Auto Queue This Slot"], L["Check this to allow this slot to auto queue.  When an item goes on cooldown, it will swap for an item higher on the list that's off cooldown."])

  local list = box(sf, "ItemRackOptQueueListFrame")
  list:SetSize(228, 280)
  list:SetPoint("BOTTOMRIGHT", -8, 8)
  local holder = CreateFrame("Frame", nil, list)
  holder:SetPoint("TOPLEFT", 8, -8)
  holder:SetSize(200, 11 * 24)
  for i = 1, 11 do
    local row = CreateFrame("Button", "ItemRackOptSortList" .. i, holder)
    row:SetSize(i == 1 and 180 or 200, 24)
    row:SetID(i)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
    S.RowHighlight(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("TOPLEFT", 3, -1)
    row.name = text(row, 10, "text", nil, "LEFT")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", -2, 0)
    row.name:SetWordWrap(false)
    row:SetScript("OnClick", Opt.SortListOnClick)
    row:HookScript("OnEnter", Opt.SortListOnEnter)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local close = small(list, "ItemRackOptSortListClose", "Close", 16, click)
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetFrameLevel(holder:GetFrameLevel() + 5)
  tooltip(close, L["Close"])
  local scroll = faux(holder, 11, function() Opt.SortListScrollFrameUpdate() end, "ItemRackOptSortListScrollFrame")
  scroll.bar:SetPoint("TOPLEFT", holder, "TOPRIGHT", 3, -24)

  -- the selected item's behaviour (in place of the slot name)
  local stats = CreateFrame("Frame", "ItemRackOptItemStatsFrame", sf)
  stats:SetPoint("TOPLEFT")
  stats:SetPoint("BOTTOMRIGHT", sf, "TOPRIGHT", 0, -36)
  stats:Hide()
  local delay = S.EditBox(stats, 28, 20, "number")
  named(delay, "ItemRackOptItemStatsDelay")
  delay:SetPoint("BOTTOMLEFT", 52, 3)
  delay:SetNumeric(true)
  delay:SetMaxLetters(4)
  delay:SetJustifyH("CENTER")
  delay:SetScript("OnTextChanged", Opt.ItemStatsDelayOnTextChanged)
  tooltip(delay, L["Delay"], L["Seconds left on its cooldown under which this item stays equipped instead of being swapped."])
  local dl = text(stats, 10, "text", L["Delay"], "RIGHT")
  dl:SetPoint("RIGHT", delay, "LEFT", -6, 0)
  local ds = text(stats, 10, "muted", L["sec"], "LEFT")
  ds:SetPoint("LEFT", delay, "RIGHT", 4, 0)
  local priority = check(stats, "ItemRackOptItemStatsPriority", L["Priority"], 14, Opt.ItemStatsCheckOnClick)
  priority:SetPoint("TOPLEFT", delay, "TOPRIGHT", 36, -3)
  tooltip(priority, L["Priority"], L["Check this to make this item auto equip when it comes off cooldown even if the equipped item is off cooldown and waiting to be used."])
  local keep = check(stats, "ItemRackOptItemStatsKeepEquipped", L["Pause Queue"], 14, Opt.ItemStatsCheckOnClick)
  keep:SetPoint("LEFT", priority.text, "RIGHT", 14, 0)
  tooltip(keep, L["Pause Queue"], L["Check this to suspend the auto queue for this slot until the item is unequipped. (For instance if you have another mod handling the auto equip of a riding crop."])

  -- top, up, down, bottom, delete
  local function mover(name, glyph, title, anchor, gap)
    local b = small(sf, name, glyph, 26, Opt.SortMove)
    if anchor then b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap) else b:SetPoint("TOPLEFT", 10, -64) end
    tooltip(b, title)
    return b
  end
  mover("ItemRackOptSortMoveTop", "Top", L["Move to the top"])
  mover("ItemRackOptSortMoveUp", "Up", L["Move up"], ItemRackOptSortMoveTop, 8)
  mover("ItemRackOptSortMoveDown", "Down", L["Move down"], ItemRackOptSortMoveUp, 8)
  mover("ItemRackOptSortMoveBottom", "Bottom", L["Move to the bottom"], ItemRackOptSortMoveDown, 8)
  mover("ItemRackOptSortMoveDelete", "Delete", L["Remove from the list"], ItemRackOptSortMoveBottom, 24)
  sf:SetScript("OnShow", function(self)
    Opt.SlotQueueFrameOnShow()
  end)
  sf:SetScript("OnHide", Opt.SlotQueueFrameOnHide)
end

-- SubFrame8: the event editor
local function buildEventEdit()
  local sf = subFrame("ItemRackOptSubFrame8")
  local validate = function() Opt.EventEditValidateButtons() end
  local function edit(parent, name, anchor)
    local e = S.EditBox(parent, 150, 20, "big")
    named(e, name)
    e:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, -15)
    e:SetScript("OnTextChanged", validate)
    return e
  end
  local nameLabel = text(sf, 10, "muted", L["Name of event:"], "LEFT", "ItemRackOptEventEditNameLabel")
  nameLabel:SetPoint("TOPLEFT", 20, -12)
  local typeLabel = text(sf, 10, "muted", L["Type of event:"], "LEFT", "ItemRackOptEventEditTypeLabel")
  typeLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -32)
  edit(sf, "ItemRackOptEventEditNameEdit", nameLabel)
  local drop = S.Dropdown(sf, 150, function()
    local o = {}
    for _, kind in ipairs(EVENT_TYPES) do o[#o + 1] = { kind, L[kind] } end
    return o
  end, function() return Opt.EventType end, function(v)
    Opt.EventType = v
    Opt.EventEditDisplayType()
  end)
  named(drop, "ItemRackOptEventEditTypeDrop")
  drop:SetHeight(20)
  drop:SetPoint("TOPLEFT", typeLabel, "TOPLEFT", -2, -15)

  local save = button(sf, "ItemRackOptEventEditSave", L["Save"], 55, 26, click)
  save:SetPoint("BOTTOM", 0, 4)
  tooltip(save, L["Save Event"], L["Saves changes to this event.  Note: if you edit the name and save, it will create a copy of the event with the new name."])
  local cancel = button(sf, "ItemRackOptEventEditCancel", L["Cancel"], 55, 26, click)
  cancel:SetPoint("LEFT", save, "RIGHT", 4, 0)
  tooltip(cancel, L["Cancel Changes"], L["Cancel any changes just made to this event and return to event list."])

  local function kindFrame(kind)
    local fr = CreateFrame("Frame", "ItemRackOptEventEdit" .. kind .. "Frame", sf)
    fr:SetPoint("TOPLEFT", 0, -92)
    fr:SetPoint("BOTTOMRIGHT", 0, 28)
    fr:Hide()
    return fr
  end
  local function opt(parent, name, label, anchor, x, y)
    local c = check(parent, name, label, 14, validate)
    c:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
    return c
  end

  -- Buff
  local buff = kindFrame("Buff")
  local bl = text(buff, 10, "muted", L["Name of the buff:"], "LEFT", "ItemRackOptEventEditBuffLabel")
  bl:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -36)
  local bn = edit(buff, "ItemRackOptEventEditBuffName", bl)
  local any = opt(buff, "ItemRackOptEventEditBuffAnyMount", L["Any mount"], bn, 2, -8)
  any:SetScript("OnClick", function() Opt.EventEditAnyMountChanged() end)
  tooltip(any, L["Any mount"], L["Checking this will check if any mount is active instead of a specific buff."])
  local pvp = opt(buff, "ItemRackOptEventEditBuffNotInPVP", L["Except in PVP instances"], any, 0, -6)
  local pve = opt(buff, "ItemRackOptEventEditBuffNotInPVE", L["Except in PVE instances"], pvp, 0, -6)
  opt(buff, "ItemRackOptEventEditBuffUnequip", L["Unequip when buff fades"], pve, 0, -6)

  -- Stance
  local stance = kindFrame("Stance")
  local sl = text(stance, 10, "muted", L["Which stance or form:"], "LEFT", "ItemRackOptEventEditStanceLabel")
  sl:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -36)
  local sn = edit(stance, "ItemRackOptEventEditStanceName", sl)
  local note = text(stance, 9, "dim", L["You can use the stance number or the name of the stance/form. The name will only work for Druids, Rogues and Warriors."], "LEFT", "ItemRackOptEventEditStanceNote")
  note:SetSize(160, 60)
  note:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", -4, -30)
  note:SetJustifyV("TOP")
  local spvp = opt(stance, "ItemRackOptEventEditStanceNotInPVP", L["Except in PVP instances"], sn, 2, -60)
  opt(stance, "ItemRackOptEventEditStanceUnequip", L["Unequip on leaving stance"], spvp, 0, -6)

  -- Zone
  local zone = kindFrame("Zone")
  local zl = text(zone, 10, "muted", L["List zone(s), one per line:"], "LEFT", "ItemRackOptEventEditZoneLabel")
  zl:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -36)
  local zh, ze = S.MultiEdit(zone)
  named(zh, "ItemRackOptEventEditZoneEditBackdrop")
  named(ze, "ItemRackOptEventEditZoneEditBox")
  ze.onChange = validate
  zh:SetSize(170, 108)
  zh:SetPoint("TOP", 0, -20)
  opt(zone, "ItemRackOptEventEditZoneUnequip", L["Unequip on leaving zone"], zh, 0, -6)

  -- Script
  local script = kindFrame("Script")
  local tl = text(script, 10, "muted", L["Event Trigger:"], "LEFT", "ItemRackOptEventEditScriptTriggerLabel")
  tl:SetPoint("TOPLEFT", typeLabel, "BOTTOMLEFT", 0, -36)
  local el = text(script, 10, "muted", L["Event Script:"], "LEFT", "ItemRackOptEventEditScriptEditLabel")
  el:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, -32)
  edit(script, "ItemRackOptEventEditScriptTrigger", tl)
  local sh, se = S.MultiEdit(script)
  named(sh, "ItemRackOptEventEditScriptEditBackdrop")
  named(se, "ItemRackOptEventEditScriptEditBox")
  se.onChange = validate
  sh:SetSize(170, 92)
  sh:SetPoint("TOP", -1, -62)
  local expand = button(script, "ItemRackOptEventEditExpand", L["Editor"], 55, 26, click)
  expand:SetPoint("RIGHT", save, "LEFT", -4, 0)
  tooltip(expand, L["Edit in Editor"], L["This will detach the script edit box above to a resizable text editor."])

  sf:SetScript("OnShow", Opt.EventEditOnShow)
  sf:SetScript("OnHide", Opt.EventEditOnHide)
end

-- the script in a big, resizable window
local function buildFloatingEditor()
  local fl = CreateFrame("Frame", "ItemRackFloatingEditor", UIParent)
  fl:SetSize(400, 300)
  fl:SetPoint("CENTER")
  fl:SetFrameStrata("DIALOG")
  fl:SetMovable(true)
  fl:SetResizable(true)
  fl:SetClampedToScreen(true)
  fl:EnableMouse(true)
  if fl.SetResizeBounds then fl:SetResizeBounds(250, 110) elseif fl.SetMinResize then fl:SetMinResize(250, 110) end
  S.Backdrop(fl, "dialog", 0.3)
  fl:Hide()
  local function remember()
    fl:StopMovingOrSizing()
    local p, rel, rp, x, y = fl:GetPoint(1)
    fl.home = { p, rel, rp, x, y }
  end
  fl:SetScript("OnMouseDown", function(self) self:StartMoving() end)
  fl:SetScript("OnMouseUp", remember)
  local title = text(fl, 11, "muted", L["Event Script:"], "LEFT")
  title:SetFontObject(SubSpellFont or GameFontNormal)
  title:SetTextColor(.65, .65, .65)
  title:SetPoint("TOPLEFT", 16, -9)
  local holder, edit = S.MultiEdit(fl)
  named(edit, "ItemRackFloatingEditorEditBox")
  named(holder, "ItemRackFloatingEditorEditFrame")
  holder:SetPoint("TOPLEFT", 8, -26)
  holder:SetPoint("BOTTOMRIGHT", -8, 8)
  edit.onChange = function() Opt.EventEditValidateButtons() end
  local close = S.CloseButton(fl, click)
  named(close, "ItemRackFloatingEditorClose")
  close:SetSize(16, 16)
  close:SetPoint("TOPRIGHT", -6, -5)
  local save = button(fl, "ItemRackFloatingEditorSave", L["Save"], 46, 18, click)
  save:SetPoint("TOPRIGHT", -28, -4)
  tooltip(save, L["Save Event"], L["Save changes to this event and return to the event list."])
  local test = button(fl, "ItemRackFloatingEditorTest", L["Test"], 46, 18, click)
  test:SetPoint("RIGHT", save, "LEFT", -4, 0)
  tooltip(test, L["Test"], L["Run the text below as a script to make sure there are no syntax errors.\nNote: This test cannot simulate any condition or test for expected behavior other than the ability to run."])
  local undo = button(fl, "ItemRackFloatingEditorUndo", L["Undo"], 46, 18, click)
  undo:SetPoint("RIGHT", test, "LEFT", -4, 0)
  tooltip(undo, L["Undo"], L["Revert the text to its last saved state."])
  local grip = CreateFrame("Button", "ItemRackFloatingEditorResizeGrip", fl)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel(holder:GetFrameLevel() + 5)
  grip:SetNormalTexture(S.BUTTONS)
  grip:GetNormalTexture():SetTexCoord(.75, .875, 0, .125)
  grip:SetScript("OnMouseDown", function() fl:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", remember)
  fl:SetScript("OnShow", function(self)
    edit:SetFocus()
    Opt.EventEditValidateButtons()
  end)
  fl:SetScript("OnHide", Opt.FloatingEditorOnHide)
end

local function build()
  if built then return end
  local f = CreateFrame("Frame", "ItemRackOptFrame", UIParent)
  f:SetSize(288, 348)
  -- the original layout, drawn bigger (the grip at the bottom right changes the size)
  f:SetScale(tonumber(ItemRackSettings.OptScale) or 1.6)
  f:SetPoint("CENTER", 0, 50)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:SetToplevel(true)
  f:SetFrameStrata("MEDIUM")
  S.Backdrop(f, "window")
  f:Hide()
  table.insert(UISpecialFrames, "ItemRackOptFrame")
  f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
  f:SetScript("OnMouseUp", function(self)
    self:StopMovingOrSizing()
    local p, rel, rp, x, y = self:GetPoint(1)
    self.home = { p, rel, rp, x, y }
  end)

  local title = text(f, 11, "muted", "IR " .. (ItemRack.Version or ""), "LEFT", "ItemRackOptFrameTitle")
  title:SetFontObject(SubSpellFont or GameFontNormal)
  title:SetTextColor(.65, .65, .65)
  title:SetPoint("TOPLEFT", 8, -9)
  local close = S.CloseButton(f, click)
  named(close, "ItemRackOptClose")
  close:SetSize(16, 16)
  close:SetPoint("TOPRIGHT", -6, -6)

  local tab1 = makeTab(f, 1, L["Config"])
  tab1:SetPoint("TOPRIGHT", -52, -6)
  makeTab(f, 2, L["Sets"]):SetPoint("TOPRIGHT", tab1, "TOPLEFT")
  makeTab(f, 3, L["Events"]):SetPoint("TOPRIGHT", ItemRackOptTab2, "TOPLEFT")
  makeTab(f, 4, L["Queue"]):SetPoint("TOPRIGHT", ItemRackOptTab3, "TOPLEFT")

  buildPaperdoll(f)
  buildConfig()
  buildSets()
  buildEvents()
  buildQueue()
  buildSetList()
  buildSlotBind()
  buildSlotQueue()
  buildEventEdit()
  buildBindFrame()
  buildFloatingEditor()

  -- resize grip: drag to make the whole window bigger or smaller (its top left stays put)
  local grip = CreateFrame("Button", "ItemRackOptResizeGrip", f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel(f:GetFrameLevel() + 40)
  grip:SetNormalTexture(S.BUTTONS)
  grip:GetNormalTexture():SetTexCoord(.75, .875, 0, .125)
  grip:SetHighlightTexture(S.BUTTONS, "ADD")
  grip:GetHighlightTexture():SetTexCoord(.75, .875, 0, .125)
  grip:SetScript("OnEnter", function(self)
    ItemRack.OnTooltip(self, L["Resize"], L["Drag to make the window bigger or smaller."])
  end)
  grip:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)
  local MIN_SCALE, MAX_SCALE = 0.8, 3
  local function setScale(scale)
    local old = f:GetScale()
    local left, top = f:GetLeft(), f:GetTop()
    f:SetScale(scale)
    if left and top then
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
      local p, rel, rp, x, y = f:GetPoint(1)
      f.home = { p, rel, rp, x, y }
    end
  end
  grip:SetScript("OnMouseDown", function(self)
    self.sizing = true
    local x, y = GetCursorPosition()
    local s = f:GetEffectiveScale()
    self.start = { x = x, y = y, w = f:GetWidth() * s, h = f:GetHeight() * s, scale = f:GetScale() }
    self:SetScript("OnUpdate", function()
      local cx, cy = GetCursorPosition()
      local st = self.start
      local ratio = ((st.w + cx - st.x) / st.w + (st.h + st.y - cy) / st.h) / 2
      setScale(math.max(MIN_SCALE, math.min(MAX_SCALE, st.scale * ratio)))
    end)
  end)
  grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    self.sizing = nil
    ItemRackSettings.OptScale = math.floor(f:GetScale() * 100 + 0.5) / 100
  end)

  built = true
  Opt.PopulateInitialIcons()
  Opt.InitializeSliders()
  Opt.TabOnClick(nil, 1)

  f:SetScript("OnShow", function(self)
    Opt.OnShow()
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
  end)
  f:SetScript("OnHide", function()
    if ItemRackMenuFrame and ItemRackMenuFrame:IsShown() and ItemRack.menuInclude then ItemRack.HideMenu() end
    ItemRackFloatingEditor:Hide()
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
  end)
end

-- the window: toggled; or shown on a tab (and on the queue of a slot)
function ItemRack.ToggleOptions(forceShow, tab, slot)
  build()
  if ItemRackOptFrame:IsShown() and not forceShow then
    ItemRackOptFrame:Hide()
    return
  end
  if not ItemRackOptFrame:IsShown() then ItemRackOptFrame:Show() end
  if tab then Opt.TabOnClick(nil, tab) end
  if slot and tab == 4 then Opt.SetupQueue(slot) end
end

--[[ What the rest of ItemRack tells the window ]]------------------------------------------

local function visible() return built and ItemRackOptFrame:IsShown() end

ItemRack.OptOnInventoryChanged = function()
  if not visible() then return end
  for i = 0, 19 do
    if not Opt.Inv[i].selected then Opt.Inv[i].id = ItemRack.GetID(i) end
  end
  Opt.UpdateInv()
  if ItemRackOptSubFrame7:IsShown() then Opt.SortListScrollFrameUpdate() end
end

ItemRack.OptOnCombatChanged = function()
  if not visible() then return end
  Opt.ListScrollFrameUpdate()
  Opt.ValidateSetButtons()
end

ItemRack.OptOnSetSwapped = function()
  if visible() then Opt.ChangeEditingSet() end
end

ItemRack.OptOnEventsChanged = function()
  if not visible() then return end
  Opt.PopulateEventList()
  Opt.ListScrollFrameUpdate()
end

ItemRack.OptOnSetsChanged = function()
  if not visible() then return end
  Opt.PopulateSetList()
  Opt.ValidateSetButtons()
  Opt.EventListScrollFrameUpdate()
end

ItemRack.OptOnQueueChanged = function()
  if visible() and ItemRackOptSubFrame7:IsShown() and Opt.SelectedSlot then
    ItemRackOptQueueEnable:SetChecked(ItemRack.GetQueuesEnabled()[Opt.SelectedSlot])
  end
end

ItemRack.OptOnSettingsChanged = function()
  if not built then return end
  Opt.InitializeSliders()
  Opt.ListScrollFrameUpdate()
end
