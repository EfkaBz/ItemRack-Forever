-- ItemRack Forever: core. Saved data, item identification and lookup, timers, the client
-- events, the combat queue, notifications, key bindings, slash commands, bank support.
--
-- A remake of ItemRack (Gello; Classic by Rottenbeer and Roadblock; BCC and Forever by
-- Chairface Chippendale and Cexxal), GPL v3. The global names (ItemRack, ItemRackUser,
-- ItemRackSettings, ItemRackItems, ItemRackEvents, EquipSet, ToggleSet, UnequipSet,
-- IsSetEquipped, the ItemRackButton* frames and the key-binding buttons) are kept, so saved
-- sets, event scripts, macros and key bindings carry over unchanged.
local ADDON, ns = ...
_G.ItemRack = ns
local L = ns.L

local _

-- API: WoW Forever keeps most item calls in C_Item / C_Container ----------------
local C_Item, C_Container = C_Item, C_Container
local GetItemInfo = _G.GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemCount = _G.GetItemCount or (C_Item and C_Item.GetItemCount)
local IsEquippableItem = _G.IsEquippableItem or (C_Item and C_Item.IsEquippableItem)
local GetItemFamily = _G.GetItemFamily or (C_Item and C_Item.GetItemFamily)
local GetAddOnMetadata = _G.GetAddOnMetadata or (C_AddOns and C_AddOns.GetAddOnMetadata)

local GetContainerNumSlots, GetContainerItemLink, GetContainerItemCooldown, GetContainerItemInfo, GetItemCooldown, PickupContainerItem, ContainerIDToInventoryID
if C_Container then
  GetContainerNumSlots = C_Container.GetContainerNumSlots
  GetContainerItemLink = C_Container.GetContainerItemLink
  GetContainerItemCooldown = C_Container.GetContainerItemCooldown
  GetItemCooldown = C_Container.GetItemCooldown or (C_Item and C_Item.GetItemCooldown) or _G.GetItemCooldown
  PickupContainerItem = C_Container.PickupContainerItem
  ContainerIDToInventoryID = C_Container.ContainerIDToInventoryID
  GetContainerItemInfo = function(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then
      return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable, info.hasLoot, info.hyperlink, info.isFiltered, info.hasNoValue, info.itemID, info.isBound
    end
  end
else
  GetContainerNumSlots, GetContainerItemLink, GetContainerItemCooldown, GetContainerItemInfo, GetItemCooldown, PickupContainerItem, ContainerIDToInventoryID =
    _G.GetContainerNumSlots, _G.GetContainerItemLink, _G.GetContainerItemCooldown, _G.GetContainerItemInfo, _G.GetItemCooldown, _G.PickupContainerItem, _G.ContainerIDToInventoryID
end

-- shared with the other files
ns.API = {
  GetItemInfo = GetItemInfo, GetItemCount = GetItemCount, GetItemCooldown = GetItemCooldown,
  GetContainerNumSlots = GetContainerNumSlots, GetContainerItemLink = GetContainerItemLink,
  GetContainerItemCooldown = GetContainerItemCooldown, GetContainerItemInfo = GetContainerItemInfo,
  PickupContainerItem = PickupContainerItem,
  GetItemSpell = _G.GetItemSpell or (C_Item and C_Item.GetItemSpell),
  IsEquippedItem = _G.IsEquippedItem or (C_Item and C_Item.IsEquippedItem),
  GetItemQualityColor = _G.GetItemQualityColor or (C_Item and C_Item.GetItemQualityColor),
}

local wowtoc = select(4, GetBuildInfo())

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
ItemRack.Version = getMetadata and getMetadata(ADDON, "Version") or "?"
ItemRack.IsForever = type(wowtoc) == "number" and wowtoc >= 16000 and wowtoc < 17000
ItemRack.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon"
ItemRack.GEAR = "Interface\\AddOns\\" .. ADDON .. "\\Media\\ItemRackGear"
ItemRack.SCRIPT_ICON = "Interface\\Icons\\INV_Scroll_03"

-- Secret values ------------------------------------------------------------------
-- On Forever the client keeps some values secret from addons: they still answer
-- type() == "number" (or "string"), then throw the moment they are compared or added.

-- a number that can be used, or nil when the client keeps it secret
function ItemRack.Num(value)
  local ok, n = pcall(function() return value + 0 end)
  if ok and n == n then return n end
end

function ItemRack.IsSecret(value)
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, value)
    if ok then return secret and true or false end
  end
  return false
end

-- a yes/no from the client, safe to test: a secret reads as ifSecret
function ItemRack.Flag(value, ifSecret)
  if ItemRack.IsSecret(value) then return ifSecret and true or false end
  return value and true or false
end

-- in combat, by the lockdown or by the unit flag (a secret flag means combat)
function ItemRack.InCombat()
  return InCombatLockdown() or ItemRack.Flag(UnitAffectingCombat("player"), true)
end

-- mounted and not on a flight path: true or false, or nil when the client won't say
function ItemRack.Mounted()
  local mounted, taxi = IsMounted(), UnitOnTaxi("player")
  if ItemRack.IsSecret(mounted) or ItemRack.IsSecret(taxi) then return nil end
  return (mounted and not taxi) and true or false
end

-- start, duration, enable usable in math; a secret cooldown reads as none (the swirl,
-- drawn by the client from the raw values, still shows it)
function ItemRack.ReadCooldown(start, duration, enable)
  local s, d = ItemRack.Num(start), ItemRack.Num(duration)
  if not (s and d) then return 0, 0, enable end
  return s, d, enable
end

-- auras are unreadable in combat on Forever. Returns (known, found)
function ItemRack.FindBuff(name)
  if ItemRack.IsForever and ItemRack.InCombat() then return false end
  local ok, found = pcall(AuraUtil.FindAuraByName, name, "player")
  if not ok then return false end
  local readable = pcall(function() return found == found and (found == nil or found .. "") end)
  if not readable then return false end
  return true, found
end

-- this character's whole name (on Forever UnitName gives the first name and the surname)
function ItemRack.PlayerName()
  local first, second = UnitName("player")
  if ItemRack.IsForever and second and second ~= "" then return first .. " " .. second end
  return first
end

-- the set key-binding buttons' name prefix: exactly ItemRack's, so bindings carry over
function ItemRack.BindingPrefix()
  if not ItemRack.IsForever then return "ItemRack" .. UnitName("player") .. GetRealmName() end
  return "ItemRack" .. ((ItemRack.PlayerName() or "") .. (GetRealmName() or "")):gsub("[%s%p]", "")
end

local GetMouseFocus = _G.GetMouseFocus
if not GetMouseFocus and GetMouseFoci then
  GetMouseFocus = function() return GetMouseFoci()[1] end
end
ItemRack.GetMouseFocus = GetMouseFocus

-- MouseIsOver is gone from newer clients; a frame's own IsMouseOver does the same job
function ItemRack.MouseIsOver(frame)
  if not frame then return false end
  if _G.MouseIsOver then return _G.MouseIsOver(frame) end
  return frame.IsMouseOver and frame:IsMouseOver() or false
end

-- Season of Discovery runes (only where the client engraves)
if C_Engraving and C_Engraving.IsEngravingEnabled and C_Engraving.IsEngravingEnabled() then
  function ItemRack.AppendRuneID(bag, slot)
    local rune
    if slot then
      if not C_Engraving.IsInventorySlotEngravable(bag, slot) then return "" end
      rune = C_Engraving.GetRuneForInventorySlot(bag, slot)
    else
      if not C_Engraving.IsEquipmentSlotEngravable(bag) then return "" end
      rune = C_Engraving.GetRuneForEquipmentSlot(bag)
    end
    return ":runeid:" .. (rune and tostring(rune.skillLineAbilityID) or "0")
  end
end

-- Saved data ----------------------------------------------------------------------
-- Run at file scope and again at PLAYER_LOGIN (the saved variables replace the globals);
-- only missing values get a default, everything already saved (also by other versions of
-- ItemRack) is kept as it is.
function ItemRack.ApplyDefaults()
  ItemRackUser = ItemRackUser or {}
  local U = ItemRackUser
  U.Sets = U.Sets or {}
  U.ItemsUsed = U.ItemsUsed or {}
  U.Hidden = U.Hidden or {}
  U.Queues = U.Queues or {}
  U.QueuesEnabled = U.QueuesEnabled or {}
  U.Buttons = U.Buttons or {}
  U.Events = U.Events or {}
  U.Events.Enabled = U.Events.Enabled or {}
  U.Events.Set = U.Events.Set or {}
  if U.Locked == nil then U.Locked = "OFF" end
  if U.EnableEvents == nil then U.EnableEvents = "ON" end
  if U.EnableQueues == nil then U.EnableQueues = "ON" end
  if U.EnablePerSetQueues == nil then U.EnablePerSetQueues = "OFF" end
  if U.ButtonSpacing == nil then U.ButtonSpacing = 4 end
  if U.Alpha == nil then U.Alpha = 1 end
  if U.MainScale == nil then U.MainScale = 1 end
  if U.MenuScale == nil then U.MenuScale = .85 end
  if U.SetMenuWrap == nil then U.SetMenuWrap = "OFF" end
  if U.SetMenuWrapValue == nil then U.SetMenuWrapValue = 3 end

  ItemRackSettings = ItemRackSettings or {}
  local S = ItemRackSettings
  S.minimap = S.minimap or { hide = false }
  local defaults = {
    MenuOnShift = "OFF", MenuOnRight = "OFF", HideOOC = "OFF", HidePetBattle = "ON",
    Notify = "ON", NotifyThirty = "OFF", NotifyChatAlso = "OFF", ShowSetInTooltip = "OFF",
    ShowTooltips = "ON", TinyTooltips = "OFF", TooltipFollow = "OFF", CooldownCount = "OFF",
    LargeNumbers = "OFF", AllowEmpty = "ON", HideTradables = "OFF", AllowHidden = "ON",
    ShowMinimap = "ON", TrinketMenuMode = "OFF", AnchorOther = "OFF", EquipToggle = "OFF",
    ShowHotKeys = "OFF", Cooldown90 = "OFF", EquipOnSetPick = "OFF", MinimapTooltip = "ON",
    CharacterSheetMenus = "ON", DisableAltClick = "OFF",
  }
  for k, v in pairs(defaults) do
    if S[k] == nil then S[k] = v end
  end
  -- the language of the addon: English unless French was chosen in the options
  if S.Language ~= "frFR" then S.Language = "enUS" end
  ns.SetLanguage(S.Language)
  -- strings set before the language was known (the slot names) follow it now
  for _, info in pairs(ItemRack.SlotInfo or {}) do
    info.key = info.key or info.real
    info.real = L[info.key]
  end

  -- items with non-standard behavior: keep = pause the auto queue while equipped,
  -- priority = equip as it comes off cooldown, delay = seconds after use before swapping out
  ItemRackItems = ItemRackItems or {}
  for _, id in ipairs({ "11122", "13209", "19812", "12846", "25653" }) do
    if ItemRackItems[id] == nil then ItemRackItems[id] = { keep = 1 } end
  end
end
ItemRack.ApplyDefaults()

ns.ShowTooltips = function() return ItemRackSettings.ShowTooltips == "ON" end

-- Tables ------------------------------------------------------------------------------
ItemRack.NoTitansGrip = { ["Polearms"] = 1, ["Fishing Poles"] = 1, ["Staves"] = 1 }
ItemRack.Menu = {}
ItemRack.LockList = {} -- per bag (-2 = worn): slot -> 1 when already tagged for a swap
ItemRack.BankTabs = {} -- bag ID -> 1 for each Forever bank tab
ItemRack.BankSlots = {}
do
  local index = Enum and Enum.BagIndex
  if ItemRack.IsForever and index then
    -- Forever's bank is the character bank tabs, not a main bank (-1) plus bank bags
    for n = 1, 9 do
      local bag = index["CharacterBankTab_" .. n]
      if bag then
        table.insert(ItemRack.BankSlots, bag)
        ItemRack.BankTabs[bag] = 1
      end
    end
  end
  if #ItemRack.BankSlots == 0 then
    ItemRack.BankSlots = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) and { -1, 5, 6, 7, 8, 9, 10 } or { -1, 5, 6, 7, 8, 9, 10, 11 }
  end
end
ItemRack.KnownItems = {}

ItemRack.SlotInfo = {
  [0] = { name = "AmmoSlot", real = L["Ammo"], INVTYPE_AMMO = 1 },
  [1] = { name = "HeadSlot", real = L["Head"], INVTYPE_HEAD = 1 },
  [2] = { name = "NeckSlot", real = L["Neck"], INVTYPE_NECK = 1 },
  [3] = { name = "ShoulderSlot", real = L["Shoulder"], INVTYPE_SHOULDER = 1 },
  [4] = { name = "ShirtSlot", real = L["Shirt"], INVTYPE_BODY = 1 },
  [5] = { name = "ChestSlot", real = L["Chest"], INVTYPE_CHEST = 1, INVTYPE_ROBE = 1 },
  [6] = { name = "WaistSlot", real = L["Waist"], INVTYPE_WAIST = 1 },
  [7] = { name = "LegsSlot", real = L["Legs"], INVTYPE_LEGS = 1 },
  [8] = { name = "FeetSlot", real = L["Feet"], INVTYPE_FEET = 1 },
  [9] = { name = "WristSlot", real = L["Wrist"], INVTYPE_WRIST = 1 },
  [10] = { name = "HandsSlot", real = L["Hands"], INVTYPE_HAND = 1 },
  [11] = { name = "Finger0Slot", real = L["Top Finger"], INVTYPE_FINGER = 1, other = 12 },
  [12] = { name = "Finger1Slot", real = L["Bottom Finger"], INVTYPE_FINGER = 1, other = 11 },
  [13] = { name = "Trinket0Slot", real = L["Top Trinket"], INVTYPE_TRINKET = 1, other = 14 },
  [14] = { name = "Trinket1Slot", real = L["Bottom Trinket"], INVTYPE_TRINKET = 1, other = 13 },
  [15] = { name = "BackSlot", real = L["Cloak"], INVTYPE_CLOAK = 1 },
  -- every equipment move (weapons too) is protected for addon code in combat on Forever:
  -- in-combat weapon swaps only go through the secure "/equipslot" macro on the set
  -- key-binding buttons (SetSetBindings)
  [16] = { name = "MainHandSlot", real = L["Main hand"], INVTYPE_WEAPONMAINHAND = 1, INVTYPE_2HWEAPON = 1, INVTYPE_WEAPON = 1, other = 17 },
  [17] = { name = "SecondaryHandSlot", real = L["Off hand"], INVTYPE_WEAPON = 1, INVTYPE_WEAPONOFFHAND = 1, INVTYPE_SHIELD = 1, INVTYPE_HOLDABLE = 1, other = 16 },
  [18] = { name = "RangedSlot", real = L["Ranged"], INVTYPE_RANGED = 1, INVTYPE_RANGEDRIGHT = 1, INVTYPE_THROWN = 1, INVTYPE_RELIC = 1 },
  [19] = { name = "TabardSlot", real = L["Tabard"], INVTYPE_TABARD = 1 },
}

ItemRack.CombatQueue = {} -- items waiting to swap in, by slot
ItemRack.RunAfterCombat = {} -- names of ItemRack functions to run when combat ends
ItemRack.BankOpen = nil
ItemRack.EventHandlers = {}
ItemRack.ExternalEventHandlers = {}

-- UI hooks: the interface files replace these
function ItemRack.OptOnInventoryChanged() end
function ItemRack.OptOnCombatChanged() end
function ItemRack.OptOnSetSwapped() end
function ItemRack.OptOnSetsChanged() end
function ItemRack.OptOnEventsChanged() end
function ItemRack.OptOnQueueChanged() end
function ItemRack.OptOnSettingsChanged() end

-- Timers --------------------------------------------------------------------------
-- ItemRack.CreateTimer(name, func, delay, rep): func runs delay seconds after StartTimer,
-- again every delay seconds when rep. (Event scripts use these too.)
local timerFrame = CreateFrame("Frame", "ItemRackFrame")
timerFrame:Hide()
ItemRack.TimerPool = {}
ItemRack.Timers = {}

function ItemRack.InitTimers() end -- (kept for scripts that call it)

function ItemRack.CreateTimer(name, func, delay, rep)
  ItemRack.TimerPool[name] = { func = func, delay = delay, rep = rep, elapsed = delay }
end

-- ItemRack.Timers: the running timers' names, in start order. timerActive mirrors it as a
-- set so the per-frame checks don't scan the list.
local timerActive = {}

function ItemRack.IsTimerActive(name)
  if not timerActive[name] then return end
  for i, j in ipairs(ItemRack.Timers) do
    if j == name then return i end
  end
end

function ItemRack.StartTimer(name, delay)
  local t = ItemRack.TimerPool[name]
  if not t then return end
  t.elapsed = delay or t.delay
  if not timerActive[name] then
    timerActive[name] = true
    table.insert(ItemRack.Timers, name)
    timerFrame:Show()
  end
end

-- starts the timer unless it already runs: events that come in bursts are handled once
-- per delay instead of pushing the timer back each time
function ItemRack.QueueTimer(name)
  if not timerActive[name] then ItemRack.StartTimer(name) end
end

function ItemRack.StopTimer(name)
  if not timerActive[name] then return end
  timerActive[name] = nil
  local timers = ItemRack.Timers
  for i = 1, #timers do
    if timers[i] == name then
      table.remove(timers, i)
      break
    end
  end
  if #timers < 1 then timerFrame:Hide() end
end

local firing = {}
function ItemRack.OnUpdate(self, elapsed)
  local timers, pool = ItemRack.Timers, ItemRack.TimerPool
  local n = #timers
  for i = 1, n do firing[i] = timers[i] end
  for i = 1, n do
    local name = firing[i]
    firing[i] = nil
    local t = pool[name]
    if t and timerActive[name] then
      t.elapsed = t.elapsed - elapsed
      if t.elapsed < 0 then
        if t.rep then t.elapsed = t.delay else ItemRack.StopTimer(name) end
        local ok, err = pcall(t.func, elapsed)
        if not ok then geterrorhandler()(err) end
      end
    end
  end
end
timerFrame:SetScript("OnUpdate", ItemRack.OnUpdate)

function ItemRack.TimerDebug()
  local on, off = "|cFF00FF00On", "|cFFFF0000Off"
  ItemRack.Print("ItemRackFrame is " .. (timerFrame:IsShown() and on or off))
  for i in pairs(ItemRack.TimerPool) do
    DEFAULT_CHAT_FRAME:AddMessage(i .. " is " .. (ItemRack.IsTimerActive(i) and on or off))
  end
end

-- Client events ------------------------------------------------------------------
-- a unit event for the player only, where the client can filter it; plain otherwise
function ItemRack.RegisterPlayerEvent(frame, event)
  if frame.RegisterUnitEvent and pcall(frame.RegisterUnitEvent, frame, event, "player") then return end
  pcall(frame.RegisterEvent, frame, event)
end

function ItemRack.OnEvent(self, event, ...)
  local handler = ItemRack.EventHandlers[event]
  if handler then handler(self, event, ...) end
end
timerFrame:SetScript("OnEvent", ItemRack.OnEvent)

-- lets other addons listen to ItemRack events (ITEMRACK_SET_SAVED, ITEMRACK_SET_DELETED)
function ItemRack.RegisterExternalEventListener(self, event, handler)
  local handlers = ItemRack.ExternalEventHandlers[event]
  if not handlers then
    handlers = {}
    ItemRack.ExternalEventHandlers[event] = handlers
  end
  table.insert(handlers, handler)
end

function ItemRack.FireItemRackEvent(self, event, ...)
  local handlers = ItemRack.ExternalEventHandlers[event]
  if handlers then
    for _, handler in pairs(handlers) do handler(event, ...) end
  end
end

function ItemRack.InitEventHandlers()
  local h = ItemRack.EventHandlers
  h.ITEM_LOCK_CHANGED = ItemRack.OnItemLockChanged
  -- these come in bursts (every global cooldown, every slot of a set swap): handled once
  -- per short delay
  h.ACTIONBAR_UPDATE_COOLDOWN = function() ItemRack.QueueTimer("ButtonCooldowns") end
  h.BAG_UPDATE_COOLDOWN = function() ItemRack.QueueTimer("ButtonCooldowns") end
  h.UNIT_INVENTORY_CHANGED = function(_, _, unit)
    if unit == "player" then ItemRack.QueueTimer("InventoryChanged") end
  end
  h.PLAYER_EQUIPMENT_CHANGED = function() ItemRack.QueueTimer("InventoryChanged") end
  h.UPDATE_BINDINGS = function() ItemRack.KeyBindingsChanged() end
  h.PLAYER_REGEN_ENABLED = ItemRack.OnLeavingCombatOrDeath
  h.PLAYER_UNGHOST = ItemRack.OnLeavingCombatOrDeath
  h.PLAYER_ALIVE = ItemRack.OnLeavingCombatOrDeath
  h.PLAYER_REGEN_DISABLED = ItemRack.OnEnteringCombat
  h.BANKFRAME_CLOSED = ItemRack.OnBankClose
  h.BANKFRAME_OPENED = ItemRack.OnBankOpen
  h.UNIT_SPELLCAST_START = ItemRack.OnCastingStart
  h.UNIT_SPELLCAST_CHANNEL_START = ItemRack.OnCastingStart
  h.UNIT_SPELLCAST_STOP = ItemRack.OnCastingStop
  h.UNIT_SPELLCAST_CHANNEL_STOP = ItemRack.OnCastingStop
  h.UNIT_SPELLCAST_SUCCEEDED = ItemRack.OnCastingStop
  h.UNIT_SPELLCAST_INTERRUPTED = ItemRack.OnCastingStop
  h.UNIT_SPELLCAST_FAILED = ItemRack.OnCastingStop
  h.CHARACTER_POINTS_CHANGED = function(...)
    ItemRack.ForgetItemScans()
    ItemRack.UpdateClassSpecificStuff(...)
  end
  h.PLAYER_LEVEL_UP = function() ItemRack.ForgetItemScans() end
  h.SKILL_LINES_CHANGED = function() ItemRack.ForgetItemScans() end
  h.PLAYER_TALENT_UPDATE = ItemRack.UpdateClassSpecificStuff
  h.ACTIVE_TALENT_GROUP_CHANGED = ItemRack.UpdateClassSpecificStuff
  h.PLAYER_ENTERING_WORLD = ItemRack.OnEnterWorld
  h.PLAYER_LOGOUT = ItemRack.OnPlayerLogout
end

function ItemRack.OnPlayerLogin()
  -- Run right at PLAYER_LOGIN: secure set-up still works then, even in combat.
  ItemRack.ApplyDefaults()
  ItemRack.InitEventHandlers()
  ItemRack.InitCore()
  ItemRack.InitButtons()
  ItemRack.InitEvents()
  ItemRack.InitBroker()
  ItemRack.SetSetBindings()
  ItemRack.UpdateCurrentSet()
end

function ItemRack.OnPlayerLogout()
  ItemRack.SetSetBindings()
end

function ItemRack.OnEnterWorld(self, event, isLogin, isReload)
  if isLogin or isReload then
    -- zone text and forms are only known now: RegisterEvents waits for this flag before its
    -- first sweep, or Unequip-flagged event sets would be stripped at every login
    ItemRack.EnteredWorld = 1
    ItemRack.RegisterEvents()
    C_Timer.After(15, function() ItemRack.SetSetBindings() end)
  end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  ItemRack.OnPlayerLogin()
end)

-- Casting: swaps wait until the cast ends ----------------------------------------------
local function PlayerCasting()
  local casting = CastingInfo or function() return UnitCastingInfo("player") end
  local channel = ChannelInfo or function() return UnitChannelInfo("player") end
  return (casting() or channel()) and true or false
end

function ItemRack.OnCastingStart(self, event, unit)
  if unit == "player" and PlayerCasting() then
    ItemRack.NowCasting = true
  end
end

function ItemRack.OnCastingStop(self, event, unit)
  if unit ~= "player" or not ItemRack.NowCasting then return end
  if event == "UNIT_SPELLCAST_CHANNEL_STOP" or not PlayerCasting() then
    ItemRack.NowCasting = nil
    -- a successful cast can put you in combat: wait a moment before the queue
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" and not ItemRack.inCombat then
      ItemRack.ProcessCombatQueue()
    else
      ItemRack.OnSpellSucceed()
    end
  end
end

function ItemRack.OnItemLockChanged()
  ItemRack.StartTimer("LocksChanged")
  ItemRack.LocksHaveChanged = 1
end

function ItemRack.OnSpellSucceed()
  ItemRack.StartTimer("DelayedCombatQueue")
end

function ItemRack.DelayedCombatQueue()
  if ItemRack.inCombat or ItemRack.NowCasting then return end
  ItemRack.ProcessCombatQueue()
end

function ItemRack.OnUnitInventoryChanged(self, event, unit)
  if unit ~= "player" then return end
  ItemRack.UpdateButtons()
  if ItemRackMenuFrame and ItemRackMenuFrame:IsVisible() then
    ItemRack.BuildMenu()
  end
  ItemRack.OptOnInventoryChanged()
end

function ItemRack.OnLeavingCombatOrDeath()
  ItemRack.inCombat = InCombatLockdown()
  if ItemRack.NowCasting then return end
  ItemRack.ProcessCombatQueue()
end

function ItemRack.ProcessCombatQueue()
  if not ItemRack.IsPlayerReallyDead() and next(ItemRack.CombatQueue) then
    local combat = ItemRackUser.Sets["~CombatQueue"].equip
    local queue = ItemRack.CombatQueue
    wipe(combat)
    for i in pairs(queue) do
      combat[i] = queue[i]
      queue[i] = nil
    end
    ItemRackUser.Sets["~CombatQueue"].oldset = ItemRack.CombatSet
    ItemRack.UpdateCombatQueue()
    ItemRack.EquipSet("~CombatQueue")
  end

  -- sets deferred while casting: pick the wait list back up here
  if #ItemRack.SetsWaiting > 0 and not ItemRack.NowCasting and not ItemRack.AnythingLocked() then
    ItemRack.ProcessSetsWaiting()
  end

  if not InCombatLockdown() then
    ItemRack.OptOnCombatChanged(false)
    ItemRack.ReflectHideOOC()
    if next(ItemRack.RunAfterCombat) then
      for i = 1, #ItemRack.RunAfterCombat do
        local fn = ItemRack[ItemRack.RunAfterCombat[i]]
        if fn then fn() end
      end
      wipe(ItemRack.RunAfterCombat)
    end
  end
end

function ItemRack.OnEnteringCombat()
  ItemRack.inCombat = 1
  ItemRack.OptOnCombatChanged(true)
  ItemRack.ReflectHideOOC()
end

function ItemRack.OnBankClose()
  ItemRack.BankOpen = nil
  if ItemRackMenuFrame then ItemRackMenuFrame:Hide() end
end

function ItemRack.OnBankOpen()
  ItemRack.BankOpen = 1
end

function ItemRack.UpdateClassSpecificStuff()
  local _, class = UnitClass("player")
  if CanDualWield then
    ItemRack.CanWearOneHandOffHand = CanDualWield() and 1 or nil
  elseif class == "WARRIOR" or class == "ROGUE" or class == "HUNTER" or class == "SHAMAN" or class == "DEATHKNIGHT" then
    ItemRack.CanWearOneHandOffHand = 1
  end
end

-- Dual spec -----------------------------------------------------------------------
-- Forever runs the modern client: the calls live in C_SpecializationInfo there, the old
-- clients have them as globals. All are tried.
local CSI = C_SpecializationInfo

function ItemRack.GetNumSpecs()
  for _, fn in ipairs({ CSI and CSI.GetNumSpecGroups, GetNumSpecGroups, GetNumTalentGroups }) do
    if fn then
      local ok, n = pcall(fn)
      if ok and tonumber(n) and n > 0 then return n end
    end
  end
  if ItemRack.GetActiveSpec() then return 2 end
  return 0
end

function ItemRack.GetActiveSpec()
  for _, fn in ipairs({ CSI and CSI.GetActiveSpecGroup, GetActiveSpecGroup, GetActiveTalentGroup }) do
    if fn then
      local ok, n = pcall(fn)
      if ok and tonumber(n) then return n end
    end
  end
end

-- the ways to change the active spec group, in order: { name, function(index) }
local function specSetters()
  local list = {}
  local function add(name, fn) if type(fn) == "function" then list[#list + 1] = { name, fn } end end
  add("C_SpecializationInfo.SetActiveSpecGroup", CSI and CSI.SetActiveSpecGroup)
  add("SetActiveSpecGroup", SetActiveSpecGroup)
  add("SetActiveTalentGroup", SetActiveTalentGroup)
  local slash = SlashCmdList and SlashCmdList.USE_TALENT_SPEC
  if slash then add("/usetalents", function(i) slash(tostring(i)) end) end
  return list
end

-- the game's talent window (whichever this client has)
local function openTalentWindow()
  local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
  if PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then
    return pcall(PlayerSpellsUtil.OpenToClassTalentsTab)
  end
  if ToggleTalentFrame then return pcall(ToggleTalentFrame) end
  if not PlayerTalentFrame and load then pcall(load, "Blizzard_TalentUI") end
  if PlayerTalentFrame then return pcall(ShowUIPanel, PlayerTalentFrame) end
  return false
end

function ItemRack.SetActiveSpec(specIndex)
  local errors = {}
  for _, setter in ipairs(specSetters()) do
    local ok, err = pcall(setter[2], specIndex)
    if ok then return true end
    errors[#errors + 1] = setter[1] .. ": " .. tostring(err)
  end
  -- old clients: through the talent window's spec tabs
  local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
  if not PlayerTalentFrame and load then pcall(load, "Blizzard_TalentUI") end
  if PlayerTalentFrame and _G["PlayerSpecTab" .. specIndex] then
    ShowUIPanel(PlayerTalentFrame)
    C_Timer.After(0.1, function()
      _G["PlayerSpecTab" .. specIndex]:Click()
      C_Timer.After(0.2, function()
        if PlayerTalentFrameActivateButton and PlayerTalentFrameActivateButton:IsEnabled() then
          PlayerTalentFrameActivateButton:Click()
        end
        C_Timer.After(0.3, function() HideUIPanel(PlayerTalentFrame) end)
      end)
    end)
    return true
  end
  -- nothing worked: say why and open the talents to switch by hand
  ItemRack.Print(L["Could not switch spec automatically: switch it in the talent window."])
  for _, e in ipairs(errors) do ItemRack.Print("|cFFFF6A5A" .. e .. "|r") end
  if #errors == 0 then ItemRack.Print(L["Type /itemrack specinfo and send the result to the author."]) end
  openTalentWindow()
  return false
end

-- /itemrack specinfo: what this client offers for dual spec
function ItemRack.SpecInfo()
  local function has(v) return v and "|cFF00FF00yes|r" or "|cFFFF6A5Ano|r" end
  ItemRack.Print("Active spec group: " .. tostring(ItemRack.GetActiveSpec()) .. ", groups: " .. tostring(ItemRack.GetNumSpecs()))
  local names = {}
  if CSI then for k in pairs(CSI) do if tostring(k):find("Spec") or tostring(k):find("Group") then names[#names + 1] = k end end end
  table.sort(names)
  ItemRack.Print("C_SpecializationInfo: " .. (#names > 0 and table.concat(names, ", ") or "-"))
  for _, n in ipairs({ "SetActiveSpecGroup", "SetActiveTalentGroup", "GetActiveTalentGroup", "GetNumTalentGroups", "ToggleTalentFrame" }) do
    ItemRack.Print(n .. ": " .. has(_G[n]))
  end
  ItemRack.Print("/usetalents: " .. has(SlashCmdList and SlashCmdList.USE_TALENT_SPEC))
  ItemRack.Print("PlayerSpellsUtil: " .. has(PlayerSpellsUtil) .. ", PlayerTalentFrame: " .. has(PlayerTalentFrame))
  local slashes = {}
  for k in pairs(SlashCmdList or {}) do
    if tostring(k):find("TALENT") or tostring(k):find("SPEC") then slashes[#slashes + 1] = k end
  end
  table.sort(slashes)
  ItemRack.Print("Slash commands: " .. (#slashes > 0 and table.concat(slashes, ", ") or "-"))
end

function ItemRack.ChangeSpecForSet(targetSpec, setname)
  if InCombatLockdown() then
    ItemRack.Print(L["Cannot change spec while in combat. Gear will be equipped, but spec change skipped."])
    return
  end
  local inInstance, instanceType = IsInInstance()
  if inInstance and (instanceType == "pvp" or instanceType == "arena") then
    ItemRack.Print(L["Specialization cannot be changed in battlegrounds or arenas. Gear will be equipped, but spec change skipped."])
    return
  end
  targetSpec = tonumber(targetSpec)
  if not targetSpec or targetSpec <= 0 then return end
  local current = ItemRack.GetActiveSpec()
  if current and tonumber(current) == targetSpec then return end
  ItemRack.Print(L["Switching to spec %d for set \"%s\""]:format(targetSpec, tostring(setname)))
  ItemRack.SetActiveSpec(targetSpec)
end

-- Sets in item tooltips ------------------------------------------------------------
do
  local found = {}
  function ItemRack.ListSetsHavingItem(tooltip, id, exact)
    if ItemRackSettings.ShowSetInTooltip ~= "ON" then return end
    if not id or id == 0 then return end
    for name, set in pairs(ItemRackUser.Sets) do
      if not name:match("^~") and set.equip then
        for _, item in pairs(set.equip) do
          if exact then
            if ItemRack.UpdateIRString(item) == id then found[name] = true end
          elseif ItemRack.SameID(item, id) then
            found[name] = true
          end
        end
      end
    end
    local any
    for name in pairs(found) do
      tooltip:AddDoubleLine(L["ItemRack set:"], name, 0.95, 0.77, 0.36, 0.95, 0.77, 0.36)
      found[name] = nil
      any = true
    end
    if any then tooltip:Show() end
  end
end

function ItemRack.OnSetBagItem(tooltip, bag, slot)
  ItemRack.ListSetsHavingItem(tooltip, ItemRack.GetID(bag, slot), true)
end

function ItemRack.OnSetInventoryItem(tooltip, unit, invSlot)
  if unit == "player" then ItemRack.ListSetsHavingItem(tooltip, ItemRack.GetID(invSlot), true) end
end

function ItemRack.OnSetHyperlink(tooltip, link)
  if type(link) == "string" then ItemRack.ListSetsHavingItem(tooltip, link:match("item:(.+)")) end
end

-- Start-up ----------------------------------------------------------------------------
function ItemRack.InitCore()
  ItemRackUser.Sets["~Unequip"] = { equip = {} }
  ItemRackUser.Sets["~CombatQueue"] = { equip = {} }

  ItemRack.UpdateClassSpecificStuff()

  ItemRack.DURABILITY_PATTERN = string.match(DURABILITY_TEMPLATE or "", "(.+) .+/.+") or ""
  ItemRack.REQUIRES_PATTERN = (string.gsub(ITEM_MIN_SKILL or "", "%%.", ".+"))

  -- "%d Charge|4s" style patterns, split in singular and plural
  local function split(str, t)
    local start, stop, single, plural = str:find("\1244(.-):(.-);")
    if start then
      split(str:sub(1, start - 1) .. single .. str:sub(stop + 1), t)
      split(str:sub(1, start - 1) .. plural .. str:sub(stop + 1), t)
    else
      tinsert(t, (str:gsub("%%d", "%%d+")))
    end
    return t
  end
  ItemRack.CHARGES_PATTERNS = {}
  if ITEM_SPELL_CHARGES then split(ITEM_SPELL_CHARGES, ItemRack.CHARGES_PATTERNS) end
  if ITEM_SPELL_CHARGES_NONE then tinsert(ItemRack.CHARGES_PATTERNS, ITEM_SPELL_CHARGES_NONE) end

  ItemRack.CreateTimer("MenuMouseover", ItemRack.MenuMouseover, .25, 1)
  ItemRack.CreateTimer("TooltipUpdate", ItemRack.TooltipUpdate, 1, 1)
  ItemRack.CreateTimer("CooldownUpdate", ItemRack.CooldownUpdate, 1, 1)
  ItemRack.CreateTimer("LocksChanged", ItemRack.LocksChanged, .2)
  ItemRack.CreateTimer("DelayedCombatQueue", ItemRack.DelayedCombatQueue, .1)
  ItemRack.CreateTimer("ButtonCooldowns", function() ItemRack.UpdateButtonCooldowns() end, .1)
  ItemRack.CreateTimer("InventoryChanged", function()
    ItemRack.ForgetItemScans(true) -- equipping binds an item
    ItemRack.OnUnitInventoryChanged(nil, nil, "player")
  end, .05)

  for i = -2, 11 do ItemRack.LockList[i] = {} end
  for bag in pairs(ItemRack.BankTabs) do ItemRack.LockList[bag] = ItemRack.LockList[bag] or {} end
  for _, bag in ipairs(ItemRack.BankSlots) do ItemRack.LockList[bag] = ItemRack.LockList[bag] or {} end

  -- hook only what this client has (Forever has no global UseItemByName)
  local function HookGlobal(name, fn)
    if type(_G[name]) == "function" then hooksecurefunc(name, fn) return true end
  end
  HookGlobal("UseInventoryItem", ItemRack.newUseInventoryItem)
  HookGlobal("UseAction", ItemRack.newUseAction)
  if not HookGlobal("UseItemByName", ItemRack.newUseItemByName)
    and C_Item and type(C_Item.UseItemByName) == "function" then
    hooksecurefunc(C_Item, "UseItemByName", ItemRack.newUseItemByName)
  end
  HookGlobal("PaperDollFrame_OnShow", function() ItemRack.UpdateCombatQueue() end)
  hooksecurefunc(GameTooltip, "SetBagItem", ItemRack.OnSetBagItem)
  hooksecurefunc(GameTooltip, "SetInventoryItem", ItemRack.OnSetInventoryItem)
  hooksecurefunc(GameTooltip, "SetHyperlink", ItemRack.OnSetHyperlink)

  for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_UNGHOST", "PLAYER_ALIVE",
    "BANKFRAME_CLOSED", "BANKFRAME_OPENED", "CHARACTER_POINTS_CHANGED", "PLAYER_LOGOUT",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
    pcall(timerFrame.RegisterEvent, timerFrame, e)
  end
  -- casts: only the player's (in a group the others' casts would wake us all the time)
  for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    ItemRack.RegisterPlayerEvent(timerFrame, e)
  end
  for _, e in ipairs({ "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do
    pcall(timerFrame.RegisterEvent, timerFrame, e)
  end
  ItemRack.StartTimer("CooldownUpdate")

  SlashCmdList["ItemRack"] = ItemRack.SlashHandler
  SLASH_ItemRack1 = "/itemrack"

  -- short names for macros and event scripts
  EquipSet = ItemRack.EquipSet
  ToggleSet = ItemRack.ToggleSet
  UnequipSet = ItemRack.UnequipSet
  IsSetEquipped = ItemRack.IsSetEquipped
end

function ItemRack.Print(msg)
  if msg then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFF2C45CItemRack|r|cFF9A8F7A:|r |cFFFFFFFF" .. msg)
  end
end

-- the set button (20) and the broker show the current set ------------------------------
function ItemRack.UpdateCurrentSet(forceSet)
  local texture = ItemRack.ICON
  local setname = forceSet or ItemRackUser.CurrentSet or _G.CUSTOM
  if setname and setname ~= _G.CUSTOM then
    local equipped = forceSet or ItemRack.IsSetEquipped(setname)
    if equipped then
      texture = ItemRack.GetTextureBySlot(20)
    else
      setname = _G.CUSTOM
    end
  end
  if ItemRackButton20 and ItemRackUser.Buttons[20] then
    ItemRackButton20Icon:SetTexture(texture)
    ItemRackButton20Name:SetText(setname)
  end
  if ItemRack.Broker then
    ItemRack.Broker.icon = texture
    ItemRack.Broker.text = setname
  end
end

-- Item identification -------------------------------------------------------------
function ItemRack.GetTextureBySlot(slot)
  if slot == 20 then
    local set = ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet]
    return set and set.icon or ItemRack.ICON
  end
  local texture = GetInventoryItemTexture("player", slot)
  if texture then return texture end
  _, texture = GetInventorySlotInfo(ItemRack.SlotInfo[slot].name)
  return texture
end

-- ItemRack-style IDs are item strings without "item:" ("62384:0:4041:...:85:146").
-- GetIRString(link) -> IR ID; GetIRString(irID, true) -> base item ID;
-- GetIRString(link, true, true) -> base item ID of a regular link. 0 when nothing matches.
ItemRack.iSPatternRegularToIR = "item:(.-)\124h"
ItemRack.iSPatternBaseIDFromIR = "^(%-?%d+)"
ItemRack.iSPatternBaseIDFromRegular = "item:(%-?%d+)"
ItemRack.iSPatternEnhancementsFromIR = "^(%-?%d+):(%-?%d*):(%-?%d*):(%-?%d*):(%-?%d*)"
function ItemRack.GetIRString(inputString, baseid, regular)
  return string.match(inputString or "", (baseid and (regular and ItemRack.iSPatternBaseIDFromRegular or ItemRack.iSPatternBaseIDFromIR) or ItemRack.iSPatternRegularToIR)) or 0
end

-- brings the player level (field 9) of a saved ID up to date, so a set saved at a lower
-- level still matches the exact item. Fields can be empty on this client ("6948::::::::70:").
function ItemRack.UpdateIRString(itemRackID)
  itemRackID = tostring(itemRackID or "")
  local prefix, level, rest = string.match(itemRackID, "^(" .. strrep("[^:]*:", 8) .. ")([^:]*)(.*)")
  if not prefix or level == "" then return itemRackID end
  local playerLevel = ItemRack.Num(UnitLevel("player"))
  if not playerLevel then return itemRackID end
  return prefix .. playerLevel .. rest
end

function ItemRack.IRStringToItemString(itemRackID)
  return "item:" .. (itemRackID or "")
end

-- IR ID of what's in a slot (bag,nil = worn slot; bag,slot = container), 0 for none
function ItemRack.GetID(bag, slot)
  local itemLink
  if slot then
    itemLink = GetContainerItemLink(bag, slot)
  elseif bag == INVSLOT_AMMO then
    local id = GetInventoryItemID("player", bag)
    _, itemLink = GetItemInfo(id or 0)
  else
    itemLink = GetInventoryItemLink("player", bag)
  end
  local rune = ItemRack.AppendRuneID and ItemRack.AppendRuneID(bag, slot) or ""
  if rune ~= "" then return ItemRack.GetIRString(itemLink) .. rune end
  return ItemRack.GetIRString(itemLink)
end

function ItemRack.SameID(id1, id2)
  return ItemRack.GetIRString(id1, true) == ItemRack.GetIRString(id2, true)
end

-- name, texture, equip slot, quality of an IR ID
function ItemRack.GetInfoByID(id)
  local name, texture, equip, quality
  if id and id ~= 0 then
    name, _, quality, _, _, _, _, _, equip, texture = GetItemInfo(ItemRack.IRStringToItemString(ItemRack.UpdateIRString(id)))
  else
    name, texture, quality = L["(empty)"], "Interface\\Icons\\INV_Misc_QuestionMark", 0
  end
  return name, texture, equip, quality
end

function ItemRack.GetEnhancements(itemRackID)
  local itemID, enchantID, gem1, gem2, gem3 = 0, 0, 0, 0, 0
  if itemRackID and itemRackID ~= "" and itemRackID ~= 0 then
    itemID, enchantID, gem1, gem2, gem3 = tostring(itemRackID):match(ItemRack.iSPatternEnhancementsFromIR)
  end
  return tonumber(itemID), tonumber(enchantID), tonumber(gem1), tonumber(gem2), tonumber(gem3)
end

-- how many you carry of that base item
function ItemRack.GetCountByID(id)
  return tonumber(GetItemCount(ItemRack.GetIRString(id, true))) or 0
end

-- where an item is: inv (worn slot) or nil,bag,slot; exact match first, then same base ID.
-- lock: tag the found place so a second copy of an item resolves elsewhere
function ItemRack.FindItem(id, lock)
  local locklist, getid, sameid = ItemRack.LockList, ItemRack.GetID, ItemRack.SameID
  id = ItemRack.UpdateIRString(id)

  local known = ItemRack.KnownItems[id]
  if known then
    if known <= 0 then -- worn: stored as -slot
      local invslot = -known
      if id == getid(invslot) and (not lock or not locklist[-2][invslot]) then
        if lock then locklist[-2][invslot] = 1 end
        return invslot
      end
    else -- bag: stored as bag*100+slot
      local bag, slot = math.floor(known / 100), known % 100
      if slot > 0 and id == getid(bag, slot) and (not lock or not locklist[bag][slot]) then
        if lock then locklist[bag][slot] = 1 end
        return nil, bag, slot
      end
    end
  end

  for i = 4, 0, -1 do
    for j = 1, GetContainerNumSlots(i) do
      if id == getid(i, j) and (not lock or not locklist[i][j]) then
        if lock then locklist[i][j] = 1 end
        return nil, i, j
      end
    end
  end
  for i = 0, 19 do
    if id == getid(i) and (not lock or not locklist[-2][i]) then
      if lock then locklist[-2][i] = 1 end
      return i
    end
  end
  for i = 4, 0, -1 do
    for j = 1, GetContainerNumSlots(i) do
      if sameid(id, getid(i, j)) and (not lock or not locklist[i][j]) then
        if lock then locklist[i][j] = 1 end
        return nil, i, j
      end
    end
  end
  for i = 0, 19 do
    if sameid(id, getid(i)) and (not lock or not locklist[-2][i]) then
      if lock then locklist[-2][i] = 1 end
      return i
    end
  end
end

-- bag,slot of an item in the open bank (exact, then same base ID)
function ItemRack.FindInBank(id, lock)
  if not ItemRack.BankOpen then return end
  local locklist, getid, sameid = ItemRack.LockList, ItemRack.GetID, ItemRack.SameID
  id = ItemRack.UpdateIRString(id)
  for pass = 1, 2 do
    for _, i in pairs(ItemRack.BankSlots) do
      if ItemRack.ValidBag(i) then
        locklist[i] = locklist[i] or {}
        for j = 1, GetContainerNumSlots(i) do
          local here = getid(i, j)
          local match = (pass == 1 and id == here) or (pass == 2 and sameid(id, here))
          if match and (not lock or not locklist[i][j]) then
            if lock then locklist[i][j] = 1 end
            return i, j
          end
        end
      end
    end
  end
end

-- a plain container (not a quiver or an ammo pouch)
function ItemRack.ValidBag(bagid)
  if bagid == 0 or bagid == -1 or ItemRack.BankTabs[bagid] then return 1 end
  local invID = ContainerIDToInventoryID and ContainerIDToInventoryID(bagid)
  if not invID then return end
  local baseID = ItemRack.GetIRString(GetInventoryItemLink("player", invID), true, true)
  if baseID ~= 0 and GetItemFamily(baseID) == 0 then return 1 end
end

function ItemRack.ClearLockList()
  for _, list in pairs(ItemRack.LockList) do wipe(list) end
  if ItemRack.LocksHaveChanged then
    ItemRack.LocksHaveChanged = nil
    ItemRack.PopulateKnownItems()
  end
end

function ItemRack.FindSpace()
  for i = 4, 0, -1 do
    if ItemRack.ValidBag(i) then
      for j = 1, GetContainerNumSlots(i) do
        if not GetContainerItemLink(i, j) and not ItemRack.LockList[i][j] then
          ItemRack.LockList[i][j] = 1
          return i, j
        end
      end
    end
  end
end

function ItemRack.FindBankSpace()
  if not ItemRack.BankOpen then return end
  for _, i in pairs(ItemRack.BankSlots) do
    if ItemRack.ValidBag(i) then
      ItemRack.LockList[i] = ItemRack.LockList[i] or {}
      for j = 1, GetContainerNumSlots(i) do
        if not GetContainerItemLink(i, j) and not ItemRack.LockList[i][j] then
          ItemRack.LockList[i][j] = 1
          return i, j
        end
      end
    end
  end
end

-- Wearability, read from a hidden tooltip ---------------------------------------------
local scanTip = CreateFrame("GameTooltip", "ItemRackTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function scanBagItem(bag, slot)
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  local i = 1
  while _G["ItemRackTooltipTextLeft" .. i] do -- ClearLines keeps colours
    _G["ItemRackTooltipTextLeft" .. i]:SetTextColor(0, 0, 0)
    _G["ItemRackTooltipTextRight" .. i]:SetTextColor(0, 0, 0)
    i = i + 1
  end
  scanTip:ClearLines()
  scanTip:SetBagItem(bag, slot)
end

function ItemRack.IsRed(which)
  local fs = _G["ItemRackTooltipText" .. which]
  if not fs then return end
  local r, g, b = fs:GetTextColor()
  if r > .9 and g < .2 and b < .2 then return 1 end
end

-- What the tooltip said about an item, kept from out of combat: on Forever the scan
-- tooltip's text and colours turn secret in combat and can't be compared.
-- canWear[id] / soulbound[id] = true or false
local wearCache, boundCache = {}, {}

local function scanCanWear(bag, slot)
  scanBagItem(bag, slot)
  for i = 2, scanTip:NumLines() do
    local txt = _G["ItemRackTooltipTextLeft" .. i]:GetText() or ""
    -- red text that isn't durability or a profession requirement: can't be worn
    if (ItemRack.IsRed("Left" .. i) or ItemRack.IsRed("Right" .. i)) and not string.find(txt, ItemRack.DURABILITY_PATTERN)
      and not string.match(txt, ItemRack.REQUIRES_PATTERN) then
      return false
    end
  end
  return true
end

local function scanSoulbound(bag, slot)
  scanBagItem(bag, slot)
  for i = 2, 5 do
    local fs = _G["ItemRackTooltipTextLeft" .. i]
    local text = fs and fs:GetText()
    if text == ITEM_SOULBOUND or text == ITEM_BIND_QUEST or text == ITEM_CONJURED then
      return true
    end
  end
  return false
end

-- forget the answers (level, skills or binding changed); kept in combat, where they
-- can't be read again
function ItemRack.ForgetItemScans(boundOnly)
  if ItemRack.InCombat() then return end
  if not boundOnly then wipe(wearCache) end
  wipe(boundCache)
  ItemRack.PopulateKnownItems() -- learns them again
end

-- the cached answer, else the scan's, else ifUnknown (unreadable and never seen)
local function cachedScan(cache, scan, bag, slot, ifUnknown)
  local id = ItemRack.GetID(bag, slot)
  if id ~= 0 and cache[id] ~= nil then return cache[id] end
  local ok, result = pcall(scan, bag, slot)
  if ok then
    if id ~= 0 then cache[id] = result end
    return result
  end
  local known = cache[id]
  if known == nil then return ifUnknown end
  return known
end

function ItemRack.PlayerCanWear(invslot, bag, slot)
  if not cachedScan(wearCache, scanCanWear, bag, slot, true) then return nil end
  local _, _, itemType = ItemRack.GetInfoByID(ItemRack.GetID(bag, slot))
  if itemType == "INVTYPE_WEAPON" and invslot == 17 and not ItemRack.CanWearOneHandOffHand then
    return nil
  end
  return 1
end

function ItemRack.IsSoulbound(bag, slot)
  return cachedScan(boundCache, scanSoulbound, bag, slot, true) and 1 or nil
end

-- .2 seconds after the last ITEM_LOCK_CHANGED
function ItemRack.LocksChanged()
  ItemRack.UpdateButtonLocks()
  if ItemRack.SetSwapping then
    ItemRack.LockChangedDuringSetSwap()
  elseif ItemRackMenuFrame and ItemRackMenuFrame:IsVisible() and ItemRack.BankOpen and not ItemRack.AnythingLocked() then
    ItemRack.BuildMenu()
  elseif #ItemRack.SetsWaiting > 0 and not ItemRack.AnythingLocked() then
    ItemRack.ProcessSetsWaiting()
  end
end

-- cache of where each worn and carried equippable item is
function ItemRack.PopulateKnownItems()
  local known = ItemRack.KnownItems
  wipe(known)
  local getid = ItemRack.GetID
  for i = 0, 19 do
    local id = getid(i)
    if id ~= 0 then known[id] = -i end
  end
  for i = 0, 4 do
    for j = 1, GetContainerNumSlots(i) do
      local id = getid(i, j)
      if id ~= 0 and IsEquippableItem(ItemRack.GetIRString(id, true)) then
        known[id] = i * 100 + j
        -- learn its tooltip now, so the menu can still filter it in combat
        if (wearCache[id] == nil or boundCache[id] == nil) and not ItemRack.InCombat() then
          pcall(ItemRack.PlayerCanWear, 1, i, j)
          pcall(ItemRack.IsSoulbound, i, j)
        end
      end
    end
  end
end

-- Equipping one item ------------------------------------------------------------------
function ItemRack.EquipItemByID(id, slot)
  if not id then return end
  -- every equipment move is protected for addon code in combat on Forever: in combat or
  -- while dead, everything waits in the combat queue
  if ItemRack.NowCasting or ItemRack.InCombat() or ItemRack.IsPlayerReallyDead() then
    ItemRack.AddToCombatQueue(slot, id)
  elseif not GetCursorInfo() and not SpellIsTargeting() then
    if id ~= 0 then
      local _, b, s = ItemRack.FindItem(id)
      if b then
        local _, _, isLocked = GetContainerItemInfo(b, s)
        if not isLocked and not IsInventoryItemLocked(slot) then
          local _, _, equipSlot = ItemRack.GetInfoByID(id)
          if equipSlot ~= "INVTYPE_2HWEAPON" or (ItemRack.HasTitansGrip and not ItemRack.NoTitansGrip[select(7, GetItemInfo(GetContainerItemLink(b, s))) or ""]) or not GetInventoryItemLink("player", 17) then
            PickupContainerItem(b, s)
            PickupInventoryItem(slot)
          else
            local bfree, sfree = ItemRack.FindSpace()
            if bfree then
              PickupInventoryItem(17)
              PickupContainerItem(bfree, sfree)
              PickupInventoryItem(slot)
              PickupContainerItem(b, s)
            else
              ItemRack.Print(L["Not enough room to perform swap."])
            end
          end
        end
      end
    else
      local b, s = ItemRack.FindSpace()
      if b and not IsInventoryItemLocked(slot) then
        PickupInventoryItem(slot)
        PickupContainerItem(b, s)
      else
        ItemRack.Print(L["Not enough room to perform swap."])
      end
    end
  end
end

-- a chat edit box is open
function ItemRack.ChatOpen()
  local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  if box then return true end
  return ChatFrame1EditBox and ChatFrame1EditBox:IsVisible() and true or false
end

-- puts a link in the chat edit box; true when there was one to put it in
function ItemRack.InsertLink(link)
  if not link then return end
  if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return true end
  local box = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() or ChatFrame1EditBox
  if box and box:IsVisible() then box:Insert(link) return true end
end

function ItemRack.ChatLinkID(itemID)
  local inv, bag, slot = ItemRack.FindItem(itemID)
  if bag then
    ItemRack.InsertLink(GetContainerItemLink(bag, slot))
  elseif inv then
    ItemRack.InsertLink(GetInventoryItemLink("player", inv))
  else
    local _, itemLink = GetItemInfo(ItemRack.IRStringToItemString(ItemRack.UpdateIRString(itemID)))
    ItemRack.InsertLink(itemLink)
  end
end

-- Item use outside the addon ------------------------------------------------------
ItemRack.ReflectClicked = {}

function ItemRack.ReflectItemUse(id)
  if ItemRackUser.Buttons[id] and _G["ItemRackButton" .. id] then
    _G["ItemRackButton" .. id]:SetChecked(true)
    ItemRack.ReflectClicked[id] = 1
    ItemRack.StartTimer("ReflectClickedUpdate")
  end
  local baseID = ItemRack.GetIRString(GetInventoryItemLink("player", id), true, true)
  if baseID and baseID ~= 0 then
    ItemRackUser.ItemsUsed[baseID] = 1
  end
end

function ItemRack.newUseInventoryItem(slot)
  ItemRack.ReflectItemUse(slot)
end

function ItemRack.newUseAction(slot)
  if IsEquippedAction(slot) then
    local actionType, actionId = GetActionInfo(slot)
    if actionType == "item" then
      for i = 0, 19 do
        if tonumber(ItemRack.GetIRString(GetInventoryItemLink("player", i), true, true)) == actionId then
          ItemRack.ReflectItemUse(i)
          break
        end
      end
    end
  end
end

function ItemRack.newUseItemByName(name)
  for i = 0, 19 do
    if name == GetItemInfo(GetInventoryItemLink("player", i) or 0) then
      ItemRack.ReflectItemUse(i)
      break
    end
  end
end

-- Combat queue ------------------------------------------------------------------------
function ItemRack.IsPlayerReallyDead()
  -- (a secret answer reads as alive: it is only secret in combat, where everything queues)
  local dead = ItemRack.Flag(UnitIsDeadOrGhost("player"))
  if ItemRack.Flag(UnitIsFeignDeath("player")) then dead = false end
  return dead
end

function ItemRack.AddToCombatQueue(slot, id)
  if ItemRack.CombatQueue[slot] == id then
    ItemRack.CombatQueue[slot] = nil
  else
    ItemRack.CombatQueue[slot] = id
  end
  ItemRack.UpdateCombatQueue()
end

-- the badge in a button's corner: the queued item, or a cog when the slot auto queues
function ItemRack.UpdateCombatQueue()
  local enabled = ItemRack.GetQueuesEnabled()
  for i in pairs(ItemRackUser.Buttons) do
    local queue = _G["ItemRackButton" .. i .. "Queue"]
    if queue then
      if ItemRack.CombatQueue[i] then
        queue:SetTexture(select(2, ItemRack.GetInfoByID(ItemRack.CombatQueue[i])))
        queue:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        queue:SetVertexColor(1, 1, 1)
        queue:SetAlpha(1)
        queue:Show()
      elseif enabled[i] then
        queue:SetTexture(ItemRack.GEAR)
        queue:SetTexCoord(0, 1, 0, 1)
        queue:SetVertexColor(1, 1, 1)
        queue:SetAlpha(ItemRackUser.EnableQueues == "ON" and 1 or .4)
        queue:Show()
      elseif i ~= 20 then
        queue:Hide()
      end
    end
  end
  for i = 1, 19 do
    local queue = _G["Character" .. ItemRack.SlotInfo[i].name .. "Queue"]
    if queue then
      if ItemRack.CombatQueue[i] then
        queue:SetTexture(select(2, ItemRack.GetInfoByID(ItemRack.CombatQueue[i])))
        queue:Show()
      else
        queue:Hide()
      end
    end
  end
  ItemRack.OptOnQueueChanged()
end

-- Cooldown notices ------------------------------------------------------------------
function ItemRack.Notify(msg)
  PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
  if SCT_Display then
    SCT_Display(msg, { r = .95, g = .77, b = .36 })
  elseif CombatText_AddMessage and SHOW_COMBAT_TEXT == "1" then
    CombatText_AddMessage(msg, CombatText_StandardScroll, .95, .77, .36)
  else
    UIErrorsFrame:AddMessage(msg, .95, .77, .36, 1, UIERRORS_HOLD_TIME)
  end
  if ItemRackSettings.NotifyChatAlso == "ON" then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFF2C45C" .. msg)
  end
end

function ItemRack.CooldownUpdate()
  for i, state in pairs(ItemRackUser.ItemsUsed) do
    local start, duration = GetItemCooldown(i)
    if start then start, duration = ItemRack.ReadCooldown(start, duration) end
    if start and state < 3 then
      ItemRackUser.ItemsUsed[i] = state + 1 -- wait 3 seconds before trusting the cooldown
    elseif start then
      local remain = 0
      if start > 0 then
        remain = duration - (GetTime() - start)
        if state < 5 then
          if remain > 29 then
            ItemRackUser.ItemsUsed[i] = 30 -- tag for the 30 s and the 0 notices
          elseif remain > 5 then
            ItemRackUser.ItemsUsed[i] = 5 -- tag for the 0 notice
          end
        end
      end
      state = ItemRackUser.ItemsUsed[i]
      if state == 30 and start > 0 and remain < 30 then
        if ItemRackSettings.NotifyThirty == "ON" then
          local name = GetItemInfo(i)
          if name then ItemRack.Notify(L["%s ready soon!"]:format(name)) end
        end
        ItemRackUser.ItemsUsed[i] = 5
      elseif state == 5 and start == 0 then
        if ItemRackSettings.Notify == "ON" then
          local name = GetItemInfo(i)
          if name then ItemRack.Notify(L["%s ready!"]:format(name)) end
        end
      end
      if start == 0 then ItemRackUser.ItemsUsed[i] = nil end
    end
  end

  if ItemRackSettings.CooldownCount == "ON" then
    ItemRack.WriteButtonCooldowns()
    ItemRack.WriteMenuCooldowns()
  end
  if ItemRack.PeriodicQueueCheck then
    ItemRack.PeriodicQueueCheck()
  end
end

-- Hidden menu entries (items and sets) --------------------------------------------
function ItemRack.AddHidden(id)
  if not id then return end
  for i = 1, #ItemRackUser.Hidden do
    if ItemRackUser.Hidden[i] == id then return end
  end
  table.insert(ItemRackUser.Hidden, id)
end

function ItemRack.RemoveHidden(id)
  for i = 1, #ItemRackUser.Hidden do
    if ItemRackUser.Hidden[i] == id then
      table.remove(ItemRackUser.Hidden, i)
      break
    end
  end
end

function ItemRack.IsHidden(id)
  for i = 1, #ItemRackUser.Hidden do
    if ItemRackUser.Hidden[i] == id then return true end
  end
end

function ItemRack.ToggleHidden(id)
  if ItemRack.IsHidden(id) then ItemRack.RemoveHidden(id) else ItemRack.AddHidden(id) end
end

-- Key bindings ------------------------------------------------------------------------
-- Each bound set has a secure button named BindingPrefix()..setname (as in ItemRack).
-- PreClick runs EquipSet in and out of combat (in combat it can only queue); the macro
-- swaps weapons in combat, the one thing the protected environment still allows.
local retryCount = 0
function ItemRack.SetSetBindings()
  if InCombatLockdown() then
    ItemRack.Print(L["Cannot save hotkeys in combat, please try again out of combat!"])
    return
  end
  for name, set in pairs(ItemRackUser.Sets) do
    if set.key then
      local buttonName = ItemRack.BindingPrefix() .. name
      local button = _G[buttonName] or CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")
      button.setName = name
      button:RegisterForClicks("AnyDown") -- a key delivers a down and an up click
      button:SetScript("PreClick", function(self) ItemRack.RunSetBinding(self.setName) end)
      button:SetAttribute("type", "macro")
      local macrotext = "/stopmacro [nocombat]\n"
      if set.equip then
        for slot = 16, 18 do
          local baseID = tonumber(ItemRack.GetIRString(set.equip[slot] or 0, true))
          if baseID and baseID > 0 then
            macrotext = macrotext .. "/equipslot " .. slot .. " item:" .. baseID .. "\n"
          end
        end
      end
      button:SetAttribute("macrotext", macrotext)
      SetBindingClick(set.key, buttonName)
    end
  end
  -- 0 or nil: bindings not loaded yet at login; keep them for this session and retry
  local bindingSet = GetCurrentBindingSet()
  if bindingSet == 1 or bindingSet == 2 then
    SaveBindings(bindingSet)
    retryCount = 0
  elseif retryCount < 4 then
    retryCount = retryCount + 1
    C_Timer.After(5, function() ItemRack.SetSetBindings() end)
  end
end

function ItemRack.RunSetBinding(setname)
  if ItemRackSettings.EquipToggle == "ON" then
    ItemRack.ToggleSet(setname)
  else
    ItemRack.EquipSet(setname)
  end
end

-- Slash command -------------------------------------------------------------------------
function ItemRack.SlashHandler(arg1)
  arg1 = arg1 or ""
  if string.match(arg1, "^%s*equip") then
    local set = string.match(arg1, "equip (.+)")
    if not set then
      ItemRack.Print(L["Usage: /itemrack equip set name"])
    else
      ItemRack.EquipSet(set)
    end
    return
  elseif string.match(arg1, "^%s*toggle") then
    local sets = string.match(arg1, "toggle (.+)")
    if not sets then
      ItemRack.Print(L["Usage: /itemrack toggle set name[, second set name]"])
    else
      local set1, set2 = string.match(sets, "(.+), ?(.+)")
      if not set1 then
        ItemRack.ToggleSet(sets)
      elseif ItemRack.IsSetEquipped(set1) then
        ItemRack.EquipSet(set2)
      else
        ItemRack.EquipSet(set1)
      end
    end
    return
  elseif string.match(arg1, "^%s*unequip") then
    local set = string.match(arg1, "unequip (.+)") or ItemRackUser.CurrentSet
    if set then ItemRack.UnequipSet(set) end
    return
  end

  arg1 = string.lower(arg1):gsub("^%s+", ""):gsub("%s+$", "")
  if arg1 == "reset" then
    ItemRack.ResetButtons()
  elseif arg1 == "reset everything" then
    ItemRack.ResetEverything()
  elseif arg1 == "lock" then
    ItemRackUser.Locked = "ON"
    ItemRack.ReflectLock()
    ItemRack.OptOnSettingsChanged()
  elseif arg1 == "unlock" then
    ItemRackUser.Locked = "OFF"
    ItemRack.ReflectLock()
    ItemRack.OptOnSettingsChanged()
  elseif arg1 == "" or arg1 == "opt" or arg1 == "options" or arg1 == "config" then
    ItemRack.ToggleOptions()
  elseif arg1 == "sets" then
    ItemRack.ToggleOptions(nil, 2)
  elseif arg1 == "events" then
    ItemRack.ToggleOptions(nil, 3)
  elseif arg1 == "queue" or arg1 == "queues" then
    ItemRack.ToggleOptions(nil, 4)
  elseif arg1 == "specinfo" then
    ItemRack.SpecInfo()
  elseif string.match(arg1, "^spec ?(%d*)$") then
    local specNum = tonumber(string.match(arg1, "^spec ?(%d*)$"))
    if specNum and specNum >= 1 and specNum <= 3 then
      ItemRack.SetActiveSpec(specNum)
    else
      ItemRack.Print(L["Usage: /itemrack spec 1 or /itemrack spec 2"])
      ItemRack.Print(L["Current spec: %s"]:format(tostring(ItemRack.GetActiveSpec() or "?")))
    end
  else
    ItemRack.Print(L["/itemrack : options window."])
    ItemRack.Print(L["/itemrack sets, events, queue : opens that tab."])
    ItemRack.Print(L["/itemrack equip set name : equips that set."])
    ItemRack.Print(L["/itemrack unequip [set name] : unequips that set (or the current one)."])
    ItemRack.Print(L["/itemrack toggle set name[, second set] : toggles that set."])
    ItemRack.Print(L["/itemrack spec 1|2 : switches spec."])
    ItemRack.Print(L["/itemrack lock/unlock : locks/unlocks the buttons."])
    ItemRack.Print(L["/itemrack reset : removes the buttons and resets their settings."])
    ItemRack.Print(L["/itemrack reset everything : wipes ItemRack to its default state."])
  end
end

-- Bank ------------------------------------------------------------------------------------
-- 1 if a set has an item in the bank, 0 if an item is missing entirely, nil if all carried
function ItemRack.MissingItems(setname)
  if not setname or not ItemRackUser.Sets[setname] then return end
  local missing
  for _, i in pairs(ItemRackUser.Sets[setname].equip) do
    if i ~= 0 and ItemRack.GetCountByID(i) == 0 then
      missing = 0
      if ItemRack.FindInBank(i) then return 1 end
    end
  end
  return missing
end

function ItemRack.GetBankedSet(setname)
  if ItemRack.MissingItems(setname) ~= 1 or SpellIsTargeting() or GetCursorInfo() then return end
  ItemRack.ClearLockList()
  for _, i in pairs(ItemRackUser.Sets[setname].equip) do
    local bag, slot = ItemRack.FindInBank(i, 1)
    if bag then
      local freeBag, freeSlot = ItemRack.FindSpace()
      if freeBag then
        PickupContainerItem(bag, slot)
        PickupContainerItem(freeBag, freeSlot)
      else
        ItemRack.Print(L["Not enough room in bags to pull all items from '%s'."]:format(setname))
        return
      end
    end
  end
end

function ItemRack.PutBankedSet(setname)
  if SpellIsTargeting() or GetCursorInfo() then return end
  ItemRack.ClearLockList()
  for _, i in pairs(ItemRackUser.Sets[setname].equip) do
    if i ~= 0 then
      local freeBag, freeSlot = ItemRack.FindBankSpace()
      if freeBag then
        local inv, bag, slot = ItemRack.FindItem(i, 1)
        if inv then
          PickupInventoryItem(inv)
        elseif bag then
          PickupContainerItem(bag, slot)
        end
        if CursorHasItem() then
          PickupContainerItem(freeBag, freeSlot)
        end
      else
        ItemRack.Print(L["Not enough room in bank to store all items from '%s'."]:format(setname))
        return
      end
    end
  end
end

function ItemRack.ResetEverything()
  ns.Skin.Confirm(L["This will restore ItemRack to its default state, wiping all sets, buttons, events and settings.\nThe interface will be reloaded. Continue?"], {
    { L["Reset"], function()
      ItemRackUser, ItemRackSettings, ItemRackItems, ItemRackEvents = nil, nil, nil, nil
      ReloadUI()
    end },
    { L["Cancel"] },
  })
end

-- Auto queues: per set, or shared ----------------------------------------------------------
function ItemRack.GetQueues()
  if ItemRackUser.EnablePerSetQueues == "ON" then
    local set = ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet]
    if not set then return ItemRackUser.Queues end
    set.Queues = set.Queues or {}
    return set.Queues
  end
  return ItemRackUser.Queues
end

function ItemRack.GetQueuesEnabled()
  if ItemRackUser.EnablePerSetQueues == "ON" then
    local set = ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet]
    if not set then return ItemRackUser.QueuesEnabled end
    set.QueuesEnabled = set.QueuesEnabled or {}
    return set.QueuesEnabled
  end
  return ItemRackUser.QueuesEnabled
end
