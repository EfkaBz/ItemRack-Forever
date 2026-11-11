-- Baganator: shows ItemRack sets on the items in the bags (and the "Equipment Sets"
-- categories). Baganator only knows an addon called "ItemRack", so the sets are given
-- to it here, through its item set API.
local ADDON, ns = ...

local dirty = true
local guidToSets = {}
local setNames = {}

local function getGUID(location)
  if not (location and C_Item.DoesItemExist(location)) then return end
  local ok, guid = pcall(C_Item.GetItemGUID, location)
  if ok then return guid end
end

-- every item carried (worn, bags, bank when open): { guid, irID, baseID }
local function carriedItems()
  local items = {}
  local function add(irID, location)
    if not irID or irID == 0 then return end
    local guid = getGUID(location)
    if guid then
      items[#items + 1] = { guid = guid, id = ItemRack.UpdateIRString(irID), base = ItemRack.GetIRString(irID, true) }
    end
  end
  for slot = 1, 19 do
    add(ItemRack.GetID(slot), ItemLocation:CreateFromEquipmentSlot(slot))
  end
  local lastBag = ItemRack.BankOpen and 20 or (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
  for bag = ItemRack.BankOpen and -1 or 0, lastBag do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      add(ItemRack.GetID(bag, slot), ItemLocation:CreateFromBagAndSlot(bag, slot))
    end
  end
  return items
end

-- like ItemRack equipping a set: the exact item first, then any with the same item ID
local function rebuild()
  dirty = false
  wipe(guidToSets)
  wipe(setNames)
  local items = carriedItems()
  for name, set in pairs(ItemRackUser and ItemRackUser.Sets or {}) do
    if name:sub(1, 1) ~= "~" and set.equip then
      setNames[#setNames + 1] = name
      local info = { name = name, iconTexture = set.icon }
      local used = {}
      local pending = {}
      for _, ref in pairs(set.equip) do
        if ref and ref ~= 0 then pending[#pending + 1] = ItemRack.UpdateIRString(ref) end
      end
      local function take(match)
        for i = #pending, 1, -1 do
          for _, item in ipairs(items) do
            if not used[item.guid] and match(item, pending[i]) then
              used[item.guid] = true
              guidToSets[item.guid] = guidToSets[item.guid] or {}
              table.insert(guidToSets[item.guid], info)
              table.remove(pending, i)
              break
            end
          end
        end
      end
      take(function(item, ref) return item.id == ref end)
      take(function(item, ref) return item.base == ItemRack.GetIRString(ref, true) end)
    end
  end
  for _, list in pairs(guidToSets) do
    table.sort(list, function(a, b) return a.name < b.name end)
  end
  table.sort(setNames)
end

local function changed()
  dirty = true
  if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
    Baganator.API.RequestItemButtonsRefresh()
  end
end

local registered
local function register()
  if registered or not (Baganator and Baganator.API and Baganator.API.RegisterItemSetSource) then return end
  if not (ItemLocation and C_Item and C_Item.GetItemGUID) then return end
  registered = true
  Baganator.API.RegisterItemSetSource("ItemRack Forever", "item_rack_forever", function(_, guid)
    if not guid then return end
    if dirty then rebuild() end
    return guidToSets[guid]
  end, function()
    if dirty then rebuild() end
    return setNames
  end)
  ItemRack:RegisterExternalEventListener("ITEMRACK_SET_SAVED", changed)
  ItemRack:RegisterExternalEventListener("ITEMRACK_SET_DELETED", changed)
  local watch = CreateFrame("Frame")
  for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYERBANKSLOTS_CHANGED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
    pcall(watch.RegisterEvent, watch, e)
  end
  -- the set list is rebuilt the next time Baganator asks (ItemRack.BankOpen is set by then)
  watch:SetScript("OnEvent", changed)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
  if event == "PLAYER_LOGIN" or name == "Baganator" then
    pcall(register)
    if registered then self:UnregisterAllEvents() changed() end
  end
end)
