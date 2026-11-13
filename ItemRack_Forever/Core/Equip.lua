-- ItemRack Forever: equipping, unequipping and toggling sets.
local _, ns = ...
local L = ns.L
local API = ns.API
local GetItemInfo, GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo, PickupContainerItem =
  API.GetItemInfo, API.GetContainerNumSlots, API.GetContainerItemLink, API.GetContainerItemInfo, API.PickupContainerItem

ItemRack.SwapList = {} -- item IDs waiting to swap in, by slot
ItemRack.AbortSwap = nil -- 1 = no room, 2 = item on cursor, 3 = spell targeting, 4 = item locked
-- English here (the language is only known later): translated when printed
ItemRack.AbortReasons = {
  L["Not enough room."], L["Something is on the cursor."], L["In spell targeting mode."], L["Another swap is in progress."],
}
ItemRack.SetsWaiting = {} -- { {setname, func}, ... } run once the current swap ends

-- gems unique-equipped: items carrying them swap last, after the old ones are off
ItemRack.UniqueGems = {
  [36766] = 3, [36767] = 3, [42142] = 3, [42143] = 3, [42144] = 3, [42145] = 3, [42146] = 3,
  [42148] = 3, [42149] = 3, [42150] = 3, [42151] = 3, [42152] = 3, [42153] = 3, [42154] = 3,
  [42155] = 3, [42156] = 3, [42157] = 3, [42158] = 3, [49110] = 3,
  [27679] = 1, [27777] = 1, [27785] = 1, [27786] = 1, [27809] = 1, [27812] = 1, [27820] = 1,
  [28360] = 1, [28361] = 1, [28556] = 1, [28557] = 1, [30571] = 1, [30598] = 1, [32634] = 1,
  [32635] = 1, [32636] = 1, [32637] = 1, [32638] = 1, [32639] = 1, [32735] = 1, [33131] = 1,
  [33132] = 1, [33133] = 1, [33134] = 1, [33135] = 1, [33137] = 1, [33138] = 1, [33139] = 1,
  [33140] = 1, [33141] = 1, [33142] = 1, [33143] = 1, [33144] = 1, [34256] = 1, [34831] = 1,
  [42701] = 1, [42702] = 1, [44066] = 1,
}
ItemRack.eqBackOfTheBusOffset = 100

function ItemRack.ProcessSetsWaiting()
  local entry = table.remove(ItemRack.SetsWaiting, 1)
  if entry then entry[2](entry[1]) end
end

function ItemRack.AddSetToSetsWaiting(setname, whichequip)
  for _, w in pairs(ItemRack.SetsWaiting) do
    if w[1] == setname and w[2] == whichequip then return end
  end
  table.insert(ItemRack.SetsWaiting, { setname, whichequip })
end

function ItemRack.OrderSwaps(swap)
  local offset = ItemRack.eqBackOfTheBusOffset
  for k, v in pairs(swap) do
    if v and v ~= 0 and k < offset then
      local _, _, gem1, gem2, gem3 = ItemRack.GetEnhancements(v)
      if ItemRack.UniqueGems[gem1] or ItemRack.UniqueGems[gem2] or ItemRack.UniqueGems[gem3] then
        swap[k + offset] = v
        swap[k] = nil
      end
    end
  end
end

local function isInternal(setname) return string.match(setname, "^~") ~= nil end

function ItemRack.EquipSet(setname)
  if not setname or not ItemRackUser.Sets[setname] then
    ItemRack.Print(L["Set \"%s\" doesn't exist."]:format(tostring(setname)))
    return
  end
  if ItemRack.NowCasting or ItemRack.AnythingLocked() then
    -- a swap is in progress: wait for it
    ItemRack.AddSetToSetsWaiting(setname, ItemRack.EquipSet)
    return
  end
  local set = ItemRackUser.Sets[setname]

  -- the spec change is a cast that blocks the gear moves: the gear goes on first, the spec
  -- changes once the swap is over (EndSetSwap)
  local wantSpec = tonumber(set.spec)
  if wantSpec and wantSpec > 0 and not isInternal(setname) then
    if ItemRack.InCombat() then
      ItemRack.ChangeSpecForSet(wantSpec, setname) -- (only says it can't)
    else
      ItemRack.PendingSpec = { spec = wantSpec, set = setname }
    end
  end

  local swap = ItemRack.SwapList
  wipe(swap)
  local couldntFind
  for i in pairs(set.equip) do
    if ItemRack.GetID(i) ~= set.equip[i] then -- not worn (exact match)
      local inv, bag = ItemRack.FindItem(set.equip[i])
      if not inv and not bag then
        couldntFind = (couldntFind or L["Could not find:"]) .. " [" .. tostring(ItemRack.GetInfoByID(set.equip[i])) .. "]"
      elseif inv ~= i then
        swap[i] = set.equip[i]
      end
    end
  end
  ItemRack.Print(couldntFind)

  if not next(swap) then
    ItemRack.EndSetSwap(setname) -- already equipped
    return
  end

  -- set.old remembers what the set replaced, for Unequip and Toggle. On a retry of the
  -- same set some slots already hold the new items: keep the first attempt's records.
  set.old = set.old or {}
  local isRetry = ItemRack.SetSwapRetrying == setname and (ItemRack.SetSwapRetryCount or 0) > 0
  if not isRetry then wipe(set.old) end
  if not isInternal(setname) then
    set.oldset = ItemRackUser.CurrentSet
  end

  -- in combat or dead every equipment move is protected on Forever: queue all of it
  -- (in-combat weapon swaps go through the secure set key-binding macro)
  if ItemRack.InCombat() or ItemRack.IsPlayerReallyDead() then
    local queued
    for i in pairs(swap) do
      -- assigned directly: AddToCombatQueue toggles, which would drop items each second
      -- time an event re-equips the same set while it still waits in the queue
      ItemRack.CombatQueue[i] = swap[i]
      if set.old[i] == nil then set.old[i] = ItemRack.GetID(i) end
      swap[i] = nil
      queued = true
    end
    if queued then
      ItemRack.CombatSet = setname
      ItemRack.UpdateCombatQueue()
    end
  end
  if not next(swap) then return end

  ItemRack.OrderSwaps(swap)
  ItemRack.IterateSwapList(setname)
  if not next(swap) then
    ItemRack.EndSetSwap(setname)
    return
  end
  -- a second pass runs from ITEM_LOCK_CHANGED (LockChangedDuringSetSwap)
  ItemRack.SetSwapping = setname
end

function ItemRack.AnythingLocked()
  for i = 1, 19 do
    if IsInventoryItemLocked(i) then return 1 end
  end
  for i = 0, 4 do
    for j = 1, GetContainerNumSlots(i) do
      if select(3, GetContainerItemInfo(i, j)) then return 1 end
    end
  end
end

function ItemRack.LockChangedDuringSetSwap()
  if not ItemRack.AnythingLocked() then
    local setname = ItemRack.SetSwapping
    ItemRack.SetSwapping = nil
    ItemRack.IterateSwapList(setname)
    ItemRack.EndSetSwap(setname)
  end
end

function ItemRack.IterateSwapList(setname)
  local set = ItemRackUser.Sets[setname]
  local swap = ItemRack.SwapList
  local offset = ItemRack.eqBackOfTheBusOffset

  ItemRack.AbortSwap = nil
  ItemRack.ClearLockList()

  local function remember(i)
    if set.old and set.old[i] == nil then set.old[i] = ItemRack.GetID(i) end
  end

  local skip
  for k = 0, 19 + offset do
    local i = k >= offset and k - offset or k
    if skip or ItemRack.AbortSwap then
      skip = nil
    elseif swap[k] then
      if swap[k] == 0 then -- the slot is to be emptied
        local bag, slot = ItemRack.FindSpace()
        if bag then
          remember(i)
          ItemRack.MoveItem(i, nil, bag, slot)
          swap[k] = nil
        else
          ItemRack.AbortSwap = 1
          break
        end
      else
        local inv, bag, slot = ItemRack.FindItem(swap[k], 1)
        if bag then
          local treatAs2H
          if i == 16 and ItemRack.HasTitansGrip then
            local subtype = select(7, GetItemInfo(GetContainerItemLink(bag, slot)))
            if subtype and ItemRack.NoTitansGrip[subtype] then treatAs2H = 1 end
          end
          if (not ItemRack.HasTitansGrip or treatAs2H) and select(3, ItemRack.GetInfoByID(swap[k])) == "INVTYPE_2HWEAPON" then
            -- a two-hander: clear the off hand first
            remember(i)
            remember(i + 1)
            if GetInventoryItemLink("player", 17) then
              local freeBag, freeSlot = ItemRack.FindSpace()
              if freeBag then
                ItemRack.MoveItem(17, nil, freeBag, freeSlot)
              else
                ItemRack.AbortSwap = 1
              end
            end
            if not ItemRack.AbortSwap then
              ItemRack.MoveItem(bag, slot, 16, nil)
              swap[k] = nil
              swap[k + 1] = nil
            end
            skip = 1
          else
            remember(i)
            ItemRack.MoveItem(bag, slot, i, nil)
            swap[k] = nil
          end
        elseif inv == (i + 1) and ItemRack.SameID(swap[k + 1], ItemRack.GetID(i)) then
          -- the two partner slots trade places
          remember(i)
          remember(i + 1)
          ItemRack.MoveItem(i, nil, i + 1, nil)
          swap[k] = nil
          swap[k + 1] = nil
          skip = 1
        elseif inv and inv ~= i and not ItemRack.SameID(set.equip[inv], swap[k]) then
          -- worn in the partner slot, which isn't meant to keep it: to a bag first (no
          -- move means no lock change and the swap would stall); the second pass equips it
          local freeBag, freeSlot = ItemRack.FindSpace()
          if freeBag then
            remember(inv)
            ItemRack.MoveItem(inv, nil, freeBag, freeSlot)
          else
            ItemRack.AbortSwap = 1
          end
        end
      end
    end
  end
  if ItemRack.AbortSwap then
    ItemRack.Print(L["Swap stopped."] .. " " .. L[ItemRack.AbortReasons[ItemRack.AbortSwap] or ""])
  end
end

-- the spec EquipSet put off, now that the set's gear is on (or as on as it gets)
local function applyPendingSpec(setname)
  local pending = ItemRack.PendingSpec
  if not pending or pending.set ~= setname then return end
  ItemRack.PendingSpec = nil
  C_Timer.After(0.3, function() ItemRack.ChangeSpecForSet(pending.spec, setname) end)
end

local function findEquippedSet()
  for name in pairs(ItemRackUser.Sets) do
    if not isInternal(name) and ItemRack.IsSetEquipped(name) then return name end
  end
end

function ItemRack.EndSetSwap(setname)
  ItemRack.SetSwapping = nil
  ItemRack.SwapPending = true -- keeps UpdateButtons from changing the current set meanwhile
  if setname then
    -- not fully on (an item was busy)? try again a few times
    if not isInternal(setname) and ItemRackUser.Sets[setname] then
      if not ItemRack.IsSetEquipped(setname) and not ItemRack.AnythingLocked() then
        local retryCount = ItemRack.SetSwapRetryCount or 0
        if retryCount < 3 then
          ItemRack.SetSwapRetryCount = retryCount + 1
          ItemRack.SetSwapRetrying = setname
          C_Timer.After(0.3, function()
            if not ItemRack.IsSetEquipped(setname) then
              ItemRack.EquipSet(setname)
            else
              ItemRack.SetSwapRetryCount = 0
              ItemRack.SetSwapRetrying = nil
              ItemRackUser.CurrentSet = setname
              ItemRack.UpdateCurrentSet(setname)
              ItemRack.OptOnSetSwapped()
              applyPendingSpec(setname)
            end
          end)
          return
        end
      end
      ItemRack.SetSwapRetryCount = 0
      ItemRack.SetSwapRetrying = nil
      applyPendingSpec(setname)
    end

    if not isInternal(setname) then
      ItemRackUser.CurrentSet = setname
      ItemRack.UpdateCurrentSet(setname)
    else
      -- internal set (~Unequip, ~CombatQueue): back to the set worn before, if any
      local oldset = ItemRackUser.Sets[setname] and ItemRackUser.Sets[setname].oldset
      if oldset then
        ItemRackUser.CurrentSet = oldset
        ItemRackUser.Sets[setname].oldset = nil
        ItemRack.UpdateCurrentSet(oldset)
      else
        C_Timer.After(0.5, function()
          ItemRackUser.CurrentSet = findEquippedSet()
          ItemRack.UpdateCurrentSet(ItemRackUser.CurrentSet)
        end)
      end
    end
    ItemRack.OptOnSetSwapped()
    ItemRack.UpdateCombatQueue() -- the badges follow the set with per-set queues
  end
  C_Timer.After(0.5, function() ItemRack.SwapPending = nil end)
end

-- moves an item from bag,slot to bag,slot (slot nil = a worn slot)
function ItemRack.MoveItem(fromBag, fromSlot, toBag, toSlot)
  local abort
  if CursorHasItem() then
    abort = 2
  elseif SpellIsTargeting() then
    abort = 3
  elseif (not fromSlot and IsInventoryItemLocked(fromBag)) or (not toSlot and IsInventoryItemLocked(toBag)) then
    abort = 4
  elseif (fromSlot and select(3, GetContainerItemInfo(fromBag, fromSlot))) or (toSlot and select(3, GetContainerItemInfo(toBag, toSlot))) then
    abort = 4
  end
  if abort then
    ItemRack.AbortSwap = abort
    return
  end

  -- combat began while a swap was already under way: queue instead of being blocked
  if ItemRack.InCombat() and (not fromSlot or not toSlot) then
    if not toSlot then
      local invslot = (toBag == INVSLOT_AMMO) and INVSLOT_RANGED or toBag
      ItemRack.CombatQueue[invslot] = ItemRack.GetID(fromBag, fromSlot)
    else
      ItemRack.CombatQueue[fromBag] = 0
    end
    ItemRack.UpdateCombatQueue()
    return
  end

  if fromSlot then
    PickupContainerItem(fromBag, fromSlot)
  else
    PickupInventoryItem(fromBag)
  end
  if toSlot then
    PickupContainerItem(toBag, toSlot)
  else
    if toBag == INVSLOT_AMMO then toBag = INVSLOT_RANGED end -- the ammo slot takes it this way
    PickupInventoryItem(toBag)
  end
end

function ItemRack.IsSetEquipped(setname, exact)
  if setname and ItemRackUser.Sets[setname] then
    local equip = ItemRackUser.Sets[setname].equip
    for i in pairs(equip) do
      local id = ItemRack.GetID(i)
      if (exact and equip[i] ~= id) or (not exact and not ItemRack.SameID(equip[i], id)) then
        return false
      end
    end
    return true
  end
end

function ItemRack.UnequipSet(setname)
  local set = setname and ItemRackUser.Sets[setname]
  if set and set.old then
    if ItemRack.AnythingLocked() then
      ItemRack.AddSetToSetsWaiting(setname, ItemRack.UnequipSet)
      return
    end
    local unequip = ItemRackUser.Sets["~Unequip"].equip
    wipe(unequip)
    for i, id in pairs(set.old) do unequip[i] = id end
    ItemRackUser.Sets["~Unequip"].oldset = set.oldset
    ItemRack.EquipSet("~Unequip")
  end
end

function ItemRack.ToggleSet(setname, exact)
  if ItemRack.IsSetEquipped(setname, exact) then
    ItemRack.UnequipSet(setname)
  else
    ItemRack.EquipSet(setname)
  end
end
