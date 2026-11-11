-- ItemRack Forever: auto queues. A slot with an enabled queue swaps in the first item of its
-- list that is (nearly) off cooldown once the worn one is on cooldown. 0 in a list = stop.
local _, ns = ...
local API = ns.API
local GetItemCount, GetItemSpell, IsEquippedItem, GetItemCooldown =
  API.GetItemCount, API.GetItemSpell, API.IsEquippedItem, API.GetItemCooldown
local _

function ItemRack.PeriodicQueueCheck()
  if SpellIsTargeting() then return end
  if ItemRackUser.EnableQueues == "ON" then
    for i, v in pairs(ItemRack.GetQueuesEnabled()) do
      if v == true then ItemRack.ProcessAutoQueue(i) end
    end
  end
end

-- the badge on the slot's button: dimmed = waiting on a buff, reddish = "keep" item
local function badge(slot, desaturate, r, g, b)
  local icon = _G["ItemRackButton" .. slot .. "Queue"]
  if icon and not ItemRack.CombatQueue[slot] then
    icon:SetDesaturated(desaturate)
    icon:SetVertexColor(r, g, b)
  end
end

function ItemRack.ProcessAutoQueue(slot)
  if not slot or IsInventoryItemLocked(slot) then return end

  local start, duration, enable = ItemRack.ReadCooldown(GetInventoryItemCooldown("player", slot))
  local timeLeft = math.max(start + duration - GetTime(), 0)
  local baseID = ItemRack.GetIRString(GetInventoryItemLink("player", slot), true, true)
  if not baseID then return end

  local buff = GetItemSpell and GetItemSpell(baseID)
  if buff then
    local known, found = ItemRack.FindBuff(buff)
    if known and found then
      badge(slot, true, .95, .77, .36)
      return -- its effect is still running
    end
  end

  local info = ItemRackItems[baseID]
  if info then
    if info.keep then
      badge(slot, false, 1, .45, .4)
      return
    end
    -- stays on while the rest of its cooldown is shorter than its delay
    if info.delay and start > 0 and timeLeft > 30 and timeLeft <= info.delay then
      badge(slot, true, .95, .77, .36)
      return
    end
  end
  badge(slot, false, .95, .77, .36)

  local ready = ItemRack.ItemNearReady(baseID)
  if ready and ItemRack.CombatQueue[slot] then
    ItemRack.CombatQueue[slot] = nil
    ItemRack.UpdateCombatQueue()
  end

  local list = ItemRack.GetQueues()[slot]
  if not list then return end
  for i = 1, #list do
    local candidate = string.match(tostring(list[i]), "(%d+)")
    if list[i] == 0 then
      break
    elseif ready and candidate == baseID then
      break
    elseif not ready or enable == 0 or (ItemRackItems[candidate] and ItemRackItems[candidate].priority) then
      if ItemRack.ItemNearReady(candidate)
        and (tonumber(GetItemCount(candidate)) or 0) > 0
        and not (IsEquippedItem and IsEquippedItem(candidate)) then
        local _, bag = ItemRack.FindItem(list[i])
        if bag then
          if ItemRack.CombatQueue[slot] ~= list[i] then
            ItemRack.EquipItemByID(list[i], slot)
          end
          break
        end
      end
    end
  end
end

-- off cooldown or less than 30 seconds left
function ItemRack.ItemNearReady(id)
  local baseID = tonumber(id)
  if not baseID or baseID <= 0 then return true end
  local start, duration = GetItemCooldown(baseID)
  -- unknown right after a loading screen, or secret: not ready
  start, duration = ItemRack.Num(start), ItemRack.Num(duration)
  if not (start and duration) then return end
  if start == 0 or math.max(start + duration - GetTime(), 0) <= 30 then
    return true
  end
end

function ItemRack.SetQueue(slot, newQueue)
  if not newQueue then
    ItemRack.GetQueuesEnabled()[slot] = nil
  elseif type(newQueue) == "table" then
    local queues = ItemRack.GetQueues()
    queues[slot] = queues[slot] or {}
    wipe(queues[slot])
    for i = 1, #newQueue do table.insert(queues[slot], newQueue[i]) end
    ItemRack.GetQueuesEnabled()[slot] = true
  end
  ItemRack.UpdateCombatQueue()
end
