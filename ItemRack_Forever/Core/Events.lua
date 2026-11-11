-- ItemRack Forever: events. A set equips (and optionally unequips) on its own:
--   Buff   : a buff is on you (or any mount: Anymount)            NotInPVP, NotInPVE, Unequip
--   Stance : a stance or form (number, or the form's name)        NotInPVP, Unequip
--   Zone   : you are in one of the listed zones or subzones       Unequip
--   Script : Lua run on a client event (Trigger); arg1..arg5 are the event's arguments
-- Definitions are account-wide in ItemRackEvents; which are on and with which set is per
-- character in ItemRackUser.Events.Enabled / .Set.
local _, ns = ...
local L = ns.L

-- raise to push changed default events to existing saved data (other versions of ItemRack
-- may have saved a higher number: theirs are kept)
ItemRack.EventsVersion = 18

ItemRack.DefaultEvents = {
  ["PVP"] = {
    Type = "Zone", Unequip = 1,
    Zones = {
      ["Alterac Valley"] = 1, ["Arathi Basin"] = 1, ["Warsong Gulch"] = 1, ["Eye of the Storm"] = 1,
      ["Ruins of Lordaeron"] = 1, ["Blade's Edge Arena"] = 1, ["Nagrand Arena"] = 1,
    },
  },
  ["City"] = {
    Type = "Zone", Unequip = 1,
    Zones = {
      ["Ironforge"] = 1, ["Stormwind City"] = 1, ["Darnassus"] = 1, ["The Exodar"] = 1, ["Orgrimmar"] = 1,
      ["Thunder Bluff"] = 1, ["Silvermoon City"] = 1, ["Undercity"] = 1, ["Shattrath City"] = 1, ["Dalaran"] = 1,
    },
  },
  ["Mounted"] = { Type = "Buff", Unequip = 1, Anymount = 1 },
  ["Drinking"] = { Type = "Buff", Unequip = 1, Buff = "Drink" },
  ["Evocation"] = { Class = "MAGE", Type = "Buff", Unequip = 1, Buff = "Evocation" },
  ["Warrior Battle"] = { Class = "WARRIOR", Type = "Stance", Stance = 1 },
  ["Warrior Defensive"] = { Class = "WARRIOR", Type = "Stance", Stance = 2 },
  ["Warrior Berserker"] = { Class = "WARRIOR", Type = "Stance", Stance = 3 },
  ["Priest Shadowform"] = { Class = "PRIEST", Type = "Stance", Unequip = 1, Stance = 1 },
  ["Druid Humanoid"] = { Class = "DRUID", Type = "Stance", Stance = 0 },
  ["Druid Bear"] = { Class = "DRUID", Type = "Stance", Stance = 1 },
  ["Druid Aquatic"] = { Class = "DRUID", Type = "Stance", Stance = 2 },
  ["Druid Cat"] = { Class = "DRUID", Type = "Stance", Stance = 3 },
  ["Druid Travel"] = { Class = "DRUID", Type = "Stance", Stance = 4 },
  ["Druid Moonkin"] = { Class = "DRUID", Type = "Stance", Stance = "Moonkin Form" },
  ["Druid Tree of Life"] = { Class = "DRUID", Type = "Stance", Stance = "Tree of Life" },
  ["Rogue Stealth"] = { Class = "ROGUE", Type = "Stance", Unequip = 1, Stance = 1 },
  ["Shaman Ghostwolf"] = { Class = "SHAMAN", Type = "Stance", Unequip = 1, Stance = 1 },
  ["Swimming"] = {
    Type = "Script", Trigger = "MIRROR_TIMER_START",
    Script = "local set = \"Name of set\"\nif IsSwimming() and not IsSetEquipped(set) then\n  EquipSet(set)\n  if not SwimmingEvent then\n    function SwimmingEvent()\n      if not IsSwimming() then\n        ItemRack.StopTimer(\"SwimmingEvent\")\n        UnequipSet(set)\n      end\n    end\n    ItemRack.CreateTimer(\"SwimmingEvent\",SwimmingEvent,.5,1)\n  end\n  ItemRack.StartTimer(\"SwimmingEvent\")\nend\n--[[Equips a set when swimming and breath gauge appears and unequips soon after you stop swimming.]]",
  },
  ["Buffs Gained"] = {
    Type = "Script", Trigger = "UNIT_AURA",
    Script = "if arg1==\"player\" then\n  IRScriptBuffs = IRScriptBuffs or {}\n  local buffs = IRScriptBuffs\n  for i in pairs(buffs) do\n    if not AuraUtil.FindAuraByName(i,\"player\") then\n      buffs[i] = nil\n    end\n  end\n  local i,b = 1,1\n  while b do\n    b = AuraUtil.FindAuraByName(i,\"player\")\n    if b and not buffs[b] then\n      ItemRack.Print(\"Gained buff: \"..b)\n      buffs[b] = 1\n    end\n    i = i+1\n  end\nend\n--[[For script demonstration purposes. Doesn't equip anything just informs when a buff is gained.]]",
  },
  ["After Cast"] = {
    Type = "Script", Trigger = "UNIT_SPELLCAST_SUCCEEDED",
    Script = "local spell = \"Name of spell\"\nlocal set = \"Name of set\"\nif arg1==\"player\" and arg2==spell then\n  EquipSet(set)\nend\n\n--[[This event will equip \"Name of set\" when \"Name of spell\" has finished casting.  Change the names for your own use.]]",
  },
  ["Nefarian's Lair"] = { Type = "Zone", Unequip = 1, Zones = { ["Nefarian's Lair"] = 1 } },
}

local processing = CreateFrame("Frame", "ItemRackEventProcessingFrame")

-- resetDefault: (re)load the default events; resetAll: wipe every event first
function ItemRack.LoadEvents(resetDefault, resetAll)
  local _, playerClass = UnitClass("player")
  local version = tonumber(ItemRackSettings.EventsVersion) or 0
  if ItemRack.EventsVersion > version then
    resetDefault = 1 -- new defaults: load them, custom events stay
    ItemRackSettings.EventsVersion = ItemRack.EventsVersion
  end

  if not ItemRackUser.Events or resetAll then
    ItemRackUser.Events = { Enabled = {}, Set = {} }
  end
  if not ItemRackEvents or resetAll then
    ItemRackEvents = {}
  end
  if resetDefault or resetAll then
    for name, default in pairs(ItemRack.DefaultEvents) do
      if not default.Class or default.Class == playerClass then
        ItemRack.CopyDefaultEvent(name)
      end
    end
  end
  ItemRack.CleanupEvents()
  ItemRack.OptOnEventsChanged()
end

function ItemRack.CopyDefaultEvent(eventName)
  local event, default = {}, ItemRack.DefaultEvents[eventName]
  for k, v in pairs(default) do
    if type(v) == "table" then
      event[k] = {}
      for j, w in pairs(v) do event[k][j] = w end
    else
      event[k] = v
    end
  end
  ItemRackEvents[eventName] = event
end

-- forget the settings of deleted events, and events whose set was deleted
function ItemRack.CleanupEvents()
  local ev = ItemRackUser.Events
  for name in pairs(ev.Set) do
    if not ItemRackEvents[name] or not ItemRackUser.Sets[ev.Set[name]] then
      ev.Set[name] = nil
      ev.Enabled[name] = nil
    end
  end
  for name in pairs(ev.Enabled) do
    if not ItemRackEvents[name] or ev.Enabled[name] == false then
      ev.Set[name] = nil
      ev.Enabled[name] = nil
    end
  end
end

function ItemRack.ResetEvents(resetDefault, resetAll)
  if not resetDefault and not resetAll then
    ns.Skin.Confirm(L["Restore just the default events, or wipe all events and restore the defaults?"], {
      { L["Default"], function() ItemRack.ResetEvents(1) end },
      { L["All"], function() ItemRack.ResetEvents(1, 1) end },
      { L["Cancel"] },
    })
  else
    ItemRack.LoadEvents(resetDefault, resetAll)
    ItemRack.RegisterEvents()
  end
end

function ItemRack.InitEvents()
  ItemRack.LoadEvents()
  ItemRack.CreateTimer("EventsBuffTimer", ItemRack.ProcessBuffEvent, .15)
  ItemRack.CreateTimer("EventsZoneTimer", ItemRack.ProcessZoneEvent, .16)
  ItemRack.CreateTimer("CheckForMountedEvents", ItemRack.CheckForMountedEvents, .5, 1)
  ItemRack.RegisterEvents()
end

function ItemRack.RegisterEvents()
  processing:UnregisterAllEvents()
  if ItemRack.TimerPool.CheckForMountedEvents then ItemRack.StopTimer("CheckForMountedEvents") end
  ItemRack.ReflectEventsRunning()
  if ItemRackUser.EnableEvents == "OFF" then return end

  local function reg(e)
    if not processing:IsEventRegistered(e) then pcall(processing.RegisterEvent, processing, e) end
  end
  for name in pairs(ItemRackUser.Events.Enabled) do
    local ev = ItemRackEvents[name]
    local kind = ev and ev.Type
    if kind == "Buff" then
      reg("UNIT_AURA")
    elseif kind == "Stance" then
      reg("UPDATE_SHAPESHIFT_FORM")
    elseif kind == "Zone" then
      reg("ZONE_CHANGED_NEW_AREA")
      reg("ZONE_CHANGED_INDOORS")
      reg("ZONE_CHANGED") -- outdoor subzones
    elseif kind == "Script" and ev.Trigger and ev.Trigger ~= "" then
      reg(ev.Trigger) -- (pcall: a bad event name must not stop the others)
    end
  end
  if ItemRack.TimerPool.CheckForMountedEvents then ItemRack.StartTimer("CheckForMountedEvents") end

  -- at login zone text and forms aren't known yet: OnEnterWorld runs this sweep
  if ItemRack.EnteredWorld then
    ItemRack.ProcessStanceEvent()
    ItemRack.ProcessZoneEvent()
    ItemRack.ProcessBuffEvent()
  end
end

function ItemRack.ToggleEvents()
  ItemRackUser.EnableEvents = ItemRackUser.EnableEvents == "ON" and "OFF" or "ON"
  if ItemRackUser.EnableEvents == "ON" and not next(ItemRackUser.Events.Enabled) then
    ItemRack.ToggleOptions(true, 3) -- nothing enabled yet: show the events
  end
  ItemRack.RegisterEvents()
  ItemRack.OptOnEventsChanged()
end

-- Processing --------------------------------------------------------------------------
local compiledScripts = {} -- by script text

-- compiles a Script event; returns the function, or nil and the error
function ItemRack.CompileScript(script)
  local method = compiledScripts[script]
  if method == nil then
    local err
    -- older scripts read the event's arguments as arg1..arg5
    method, err = loadstring("local arg1,arg2,arg3,arg4,arg5 = ...; " .. (script or ""))
    compiledScripts[script] = method or false
    if not method then return nil, err end
  end
  return method or nil
end

function ItemRack.ProcessingFrameOnEvent(self, event, ...)
  local events = ItemRackEvents
  local startBuff, startZone, startStance
  local arg1 = ...
  for name in pairs(ItemRackUser.Events.Enabled) do
    local ev = events[name]
    local kind = ev and ev.Type
    if event == "UNIT_AURA" and kind == "Buff" and arg1 == "player" then
      startBuff = 1
    elseif event == "UPDATE_SHAPESHIFT_FORM" and kind == "Stance" then
      startStance = 1
    elseif event == "ZONE_CHANGED_NEW_AREA" and kind == "Zone" then
      startZone = 1
    elseif event == "ZONE_CHANGED_INDOORS" and kind == "Zone" and select(2, IsInInstance()) == "raid" then
      startZone = 1
    elseif event == "ZONE_CHANGED" and kind == "Zone" then
      startZone = 1
    elseif kind == "Script" and ev.Trigger == event then
      local method = ItemRack.CompileScript(ev.Script)
      if method then
        local ok, err = pcall(method, ...)
        if not ok then ItemRack.Print(L["Error in event \"%s\": %s"]:format(name, tostring(err))) end
      end
    end
  end
  if startStance then ItemRack.ProcessStanceEvent() end
  if startBuff then ItemRack.StartTimer("EventsBuffTimer") end
  if startZone then ItemRack.StartTimer("EventsZoneTimer") end
end
processing:SetScript("OnEvent", ItemRack.ProcessingFrameOnEvent)

local function inPVP()
  local _, kind = IsInInstance()
  return kind == "arena" or kind == "pvp"
end

local function inPVE()
  local _, kind = IsInInstance()
  return kind == "party" or kind == "raid"
end

-- unequips first, then equips: with two events matching at once, the order is fixed
local function apply(toUnequip, toEquip)
  for i = 1, #toUnequip do ItemRack.UnequipSet(toUnequip[i]) end
  for i = 1, #toEquip do ItemRack.EquipSet(toEquip[i]) end
end

function ItemRack.GetStanceNumber(name)
  if tonumber(name) then return tonumber(name) end
  for i = 1, GetNumShapeshiftForms() do
    if name == select(2, GetShapeshiftFormInfo(i)) then return i end
  end
end

function ItemRack.ProcessStanceEvent()
  local current = GetShapeshiftForm()
  if ItemRack.IsSecret(current) then return end -- can't compare it: leave the sets alone
  local toEquip, toUnequip = {}, {}
  for name in pairs(ItemRackUser.Events.Enabled) do
    local ev = ItemRackEvents[name]
    if ev and ev.Type == "Stance" and not (ev.NotInPVP and inPVP()) then
      local stance = ItemRack.GetStanceNumber(ev.Stance)
      local setname = ItemRackUser.Events.Set[name]
      -- an unknown form name (form data not loaded yet) is not "left the stance"
      if stance and setname then
        if stance == current and not ItemRack.IsSetEquipped(setname) then
          table.insert(toEquip, setname)
        elseif stance ~= current and ev.Unequip and ItemRack.IsSetEquipped(setname) then
          table.insert(toUnequip, setname)
        end
      end
    end
  end
  apply(toUnequip, toEquip)
end

local zoneRetryPending
function ItemRack.ProcessZoneEvent()
  local zone, subzone = GetRealZoneText(), GetSubZoneText()
  if not zone or zone == "" then
    -- not known yet (login, loading screen): "no zone" would strip Unequip sets
    if not zoneRetryPending then
      zoneRetryPending = true
      C_Timer.After(0.3, function()
        zoneRetryPending = nil
        ItemRack.ProcessZoneEvent()
      end)
    end
    return
  end
  local toEquip, toUnequip = {}, {}
  for name in pairs(ItemRackUser.Events.Enabled) do
    local ev = ItemRackEvents[name]
    local setname = ItemRackUser.Events.Set[name]
    if ev and ev.Type == "Zone" and setname then
      local zones = ev.Zones or {}
      local inZone = zones[zone] or zones[subzone]
      if inZone and not ItemRack.IsSetEquipped(setname) then
        table.insert(toEquip, setname)
      elseif not inZone and ev.Unequip and ItemRack.IsSetEquipped(setname) then
        table.insert(toUnequip, setname)
      end
    end
  end
  apply(toUnequip, toEquip)
end

-- mounting is watched by polling: UNIT_AURA doesn't reliably tell
local lastMounted
function ItemRack.CheckForMountedEvents()
  if ItemRack.Flag(UnitIsDeadOrGhost("player")) or ItemRackUser.EnableEvents == "OFF" then return end
  local mounted = ItemRack.Mounted()
  if mounted == nil then return end -- the client won't say: keep the last known state
  if mounted ~= lastMounted then
    lastMounted = mounted
    ItemRack.ProcessBuffEvent()
  end
end

function ItemRack.ProcessBuffEvent()
  local toEquip, toUnequip = {}, {}
  for name in pairs(ItemRackUser.Events.Enabled) do
    local ev = ItemRackEvents[name]
    if ev and ev.Type == "Buff" and not (ev.NotInPVP and inPVP()) and not (ev.NotInPVE and inPVE()) then
      local known, buff = true, nil
      if ev.Anymount then
        buff = ItemRack.Mounted()
        known = buff ~= nil
      else
        known, buff = ItemRack.FindBuff(ev.Buff) -- unreadable in combat on Forever
      end
      local setname = ItemRackUser.Events.Set[name]
      if setname and known then
        local on = ItemRack.IsSetEquipped(setname)
        if buff and not on then
          table.insert(toEquip, setname)
        elseif not buff and on and ev.Unequip then
          table.insert(toUnequip, setname)
        end
      end
    end
  end
  apply(toUnequip, toEquip)
end

-- the cog on the set button shows events are running
function ItemRack.ReflectEventsRunning()
  local queue = ItemRackUser.Buttons[20] and _G.ItemRackButton20Queue
  if not queue then return end
  if ItemRackUser.EnableEvents == "ON" and next(ItemRackUser.Events.Enabled) then
    queue:Show()
  else
    queue:Hide()
  end
end
