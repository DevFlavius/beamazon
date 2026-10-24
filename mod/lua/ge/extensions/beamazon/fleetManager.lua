-- Beamazon: the fleet as data. Buying vans, the books per van and the save file.
-- Console (GE Lua): beamazon_fleetManager.buyVan()   beamazon_fleetManager.sellVan(id)   beamazon_fleetManager.status()

local M = {}

local logTag = 'beamazon'
local balance = require('beamazon/balance')

local saveFileName = 'beamazon.json'
local saveVersion = 1

-- Trip profits reach the balance in one ledger entry per payoutSeconds (and right before each save).
local payoutSeconds = 60

-- nil while no career is loaded; the sim only runs when this is set.
local fleet

-- Real seconds the player was away since the loaded save; fleetSim takes them once.
local offlineSeconds = 0

-- Trip profits and XP not yet credited. XP goes out in whole points; the fraction waits for the next payout.
local pending = {net = 0, trips = 0, xp = 0}
local payoutTimer = 0

local function newFleet()
  return {
    version = saveVersion,
    nextVanId = 1,
    vans = {},
    -- vanSeconds and timedNet feed the per-van-hour rate; saves from before them start both at 0.
    totals = {trips = 0, revenue = 0, costs = 0, net = 0, vanSeconds = 0, timedNet = 0},
    company = {hq = false},
  }
end

-- A trip in progress survives the save only if it still has everything the sim needs.
local function isValidTrip(trip)
  return type(trip) == 'table' and type(trip.parcels) == 'table' and #trip.parcels > 0
    and type(trip.routeKm) == 'number' and type(trip.drivenKm) == 'number' and type(trip.durationS) == 'number'
end

local function loadFleet()
  local data = beamazon_adapter.readSaveFile(saveFileName)
  if type(data) ~= 'table' or type(data.vans) ~= 'table' then return newFleet() end

  local loaded = newFleet()
  for _, van in ipairs(data.vans) do
    if type(van) == 'table' and type(van.id) == 'number' then
      if not isValidTrip(van.trip) then
        van.trip = nil
        van.tripElapsed = nil
      end
      van.tripElapsed = tonumber(van.tripElapsed) or 0
      van.trips = tonumber(van.trips) or 0
      van.net = tonumber(van.net) or 0
      table.insert(loaded.vans, van)
      loaded.nextVanId = math.max(loaded.nextVanId, van.id + 1)
    end
  end
  if type(data.totals) == 'table' then
    for key in pairs(loaded.totals) do
      loaded.totals[key] = tonumber(data.totals[key]) or 0
    end
  end
  loaded.savedAt = tonumber(data.savedAt)
  loaded.vanOffer = tonumber(data.vanOffer)
  if type(data.company) == 'table' and data.company.hq == true then
    loaded.company = {hq = true, foundedAt = tonumber(data.company.foundedAt)}
  end
  return loaded
end

-- The current van offer as a multiplier of balance.vanPrice, drawn like an RLS dealer listing:
-- 98% of offers fall in the normal band, 1% in each tail.
local function rollVanOffer()
  local range = beamazon_adapter.getVehiclePriceRange()
  local rand = math.random(0, 1000) / 1000
  if rand <= 0.01 then
    return range.tailLow + (range.normalLow - range.tailLow) * (rand / 0.01)
  elseif rand <= 0.99 then
    return range.normalLow + (range.normalHigh - range.normalLow) * ((rand - 0.01) / 0.98)
  end
  return range.normalHigh + (range.tailHigh - range.normalHigh) * ((rand - 0.99) / 0.01)
end

local function setLoaded(active)
  pending = {net = 0, trips = 0, xp = 0}
  payoutTimer = 0
  offlineSeconds = 0
  if active then
    fleet = loadFleet()
    -- Saved with the fleet, so reloading the save doesn't draw a new price.
    fleet.vanOffer = fleet.vanOffer or rollVanOffer()
    if fleet.savedAt then
      offlineSeconds = math.min(math.max(os.time() - fleet.savedAt, 0), balance.offlineCapHours * 3600)
    end
    log('I', logTag, string.format('fleet loaded: %d van(s), %.1f h away', #fleet.vans, offlineSeconds / 3600))
  else
    fleet = nil
  end
end

-- Loads the fleet if the career is running but the start hook was missed (e.g. after Ctrl+L).
local function ensureLoaded()
  if not fleet and beamazon_adapter.isCareerActive() then setLoaded(true) end
  return fleet ~= nil
end

local function getVans()
  return fleet and fleet.vans or {}
end

local function getTotals()
  return fleet and fleet.totals or nil
end

-- Net profit per van-hour, or nil until the fleet has worked one van-hour.
local function getNetPerVanHour()
  local totals = fleet and fleet.totals
  if not totals or totals.vanSeconds < 3600 then return nil end
  return totals.timedNet / (totals.vanSeconds / 3600)
end

-- Called by fleetSim each time the fleet advances by dt fleet seconds.
local function addWorkTime(dt)
  if not fleet then return end
  fleet.totals.vanSeconds = fleet.totals.vanSeconds + dt * #fleet.vans
end

local function ownsHq()
  return fleet ~= nil and fleet.company.hq == true
end

-- How many vans the player may own. Without a company the Logistics level unlocks them (balance.personalVanUnlocks);
-- the HQ's slots replace that limit, never lowering it.
local function getVanLimit()
  local level, limit = beamazon_adapter.getLogisticsLevel(), 0
  for _, unlock in ipairs(balance.personalVanUnlocks) do
    if level >= unlock.level then limit = math.max(limit, unlock.vans) end
  end
  -- The HQ adds its slots on top of the personal vans (Flavio, 2026-10-24: 3 + 5 = 8).
  if ownsHq() then limit = limit + balance.hqSlots end
  return limit
end

-- The next personal unlock above the current limit, {level, vans}, or nil when none is left.
local function getNextVanUnlock()
  local limit, nextUnlock = getVanLimit(), nil
  for _, unlock in ipairs(balance.personalVanUnlocks) do
    if unlock.vans > limit and (not nextUnlock or unlock.level < nextUnlock.level) then nextUnlock = unlock end
  end
  return nextUnlock
end

-- Today's price for a van: the offer times the live RLS vehicle market, in whole dollars.
local function getVanPrice()
  local offer = fleet and fleet.vanOffer or 1
  return math.floor(balance.vanPrice * offer * beamazon_adapter.getVehicleBuyMultiplier() + 0.5)
end

-- True, or false and the reason: 'careerInactive', 'vanLimit' or 'notEnoughMoney'.
local function buyVan()
  if not ensureLoaded() then
    log('W', logTag, 'buyVan: career is not active (RLS Career Overhaul is required)')
    return false, 'careerInactive'
  end
  if #fleet.vans >= getVanLimit() then
    log('W', logTag, string.format('buyVan: van limit reached (%d at Logistics level %d)', getVanLimit(), beamazon_adapter.getLogisticsLevel()))
    return false, 'vanLimit'
  end
  local id, price = fleet.nextVanId, getVanPrice()
  if not beamazon_adapter.pay(price, 'Beamazon: van ' .. id) then
    log('W', logTag, string.format('buyVan: not enough money for a van ($%d)', price))
    return false, 'notEnoughMoney'
  end
  fleet.nextVanId = id + 1
  fleet.vanOffer = rollVanOffer()
  table.insert(fleet.vans, {id = id, name = 'Van ' .. id, trips = 0, net = 0, tripElapsed = 0, pricePaid = price})
  log('I', logTag, string.format('buyVan: Van %d bought for $%d (fleet: %d, next offer $%d)', id, price, #fleet.vans, getVanPrice()))
  return true
end

local function findVan(id)
  for index, van in ipairs(fleet and fleet.vans or {}) do
    if van.id == id then return van, index end
  end
end

-- What a van sells for now: its price minus the resale loss, times the live RLS vehicle market.
-- Vans bought before prices were stored count at the average price.
local function getSellValue(van)
  local paid = tonumber(van.pricePaid) or balance.vanPrice
  return math.floor(paid * balance.vanResaleShare * beamazon_adapter.getVehicleBuyMultiplier() + 0.5)
end

-- True and the money received, or false and the reason: 'careerInactive' or 'noVan'.
-- The trip in progress is dropped with the van; trips already finished are still paid.
local function sellVan(id)
  if not ensureLoaded() then
    log('W', logTag, 'sellVan: career is not active (RLS Career Overhaul is required)')
    return false, 'careerInactive'
  end
  local van, index = findVan(id)
  if not van then
    log('W', logTag, 'sellVan: no van with id ' .. tostring(id))
    return false, 'noVan'
  end
  local value = getSellValue(van)
  if not beamazon_adapter.addMoney(value, 'Beamazon: sold ' .. van.name) then return false, 'careerInactive' end
  table.remove(fleet.vans, index)
  log('I', logTag, string.format('sellVan: %s sold for $%d (fleet: %d)', van.name, value, #fleet.vans))
  return true, value
end

-- True, or false and the reason: 'careerInactive', 'alreadyOwned', 'logisticsLevel' or 'notEnoughMoney'.
local function buyHq()
  if not ensureLoaded() then
    log('W', logTag, 'buyHq: career is not active (RLS Career Overhaul is required)')
    return false, 'careerInactive'
  end
  if ownsHq() then return false, 'alreadyOwned' end
  local level = beamazon_adapter.getLogisticsLevel()
  if level < balance.hqUnlockLevel then
    log('W', logTag, string.format('buyHq: needs Logistics level %d (player: %d)', balance.hqUnlockLevel, level))
    return false, 'logisticsLevel'
  end
  if not beamazon_adapter.pay(balance.hqPrice, 'Beamazon: company HQ') then
    log('W', logTag, string.format('buyHq: not enough money ($%d)', balance.hqPrice))
    return false, 'notEnoughMoney'
  end
  fleet.company = {hq = true, foundedAt = os.time()}
  log('I', logTag, string.format('buyHq: company founded for $%d (van limit: %d)', balance.hqPrice, getVanLimit()))
  return true
end

local function takeOfflineSeconds()
  local seconds = offlineSeconds
  offlineSeconds = 0
  return seconds
end

-- Puts the pending trip profits in the balance as one ledger entry.
local function payOut(label)
  if pending.trips == 0 then return end
  local xp = math.floor(pending.xp)
  beamazon_adapter.addMoney(pending.net, string.format('Beamazon: %s (%d)', label or 'fleet deliveries', pending.trips), xp)
  pending = {net = 0, trips = 0, xp = pending.xp - xp}
end

-- Called by fleetSim after each tick with the game seconds that passed.
local function onFleetTick(dt)
  payoutTimer = payoutTimer + dt
  if payoutTimer < payoutSeconds then return end
  payoutTimer = 0
  payOut()
end

-- Called by fleetSim when a van finishes a trip: keeps the books; the money goes out in payOut.
local function recordTrip(van, result)
  local costs = result.energy + result.wear + result.commission
  pending.net = pending.net + result.net
  pending.trips = pending.trips + 1
  pending.xp = pending.xp + (result.xp or 0)
  van.trips = van.trips + 1
  van.net = van.net + result.net
  fleet.totals.trips = fleet.totals.trips + 1
  fleet.totals.revenue = fleet.totals.revenue + result.revenue
  fleet.totals.costs = fleet.totals.costs + costs
  fleet.totals.net = fleet.totals.net + result.net
  fleet.totals.timedNet = fleet.totals.timedNet + result.net
  log('D', logTag, string.format('%s delivered %d parcel(s) over %.1f km: revenue $%.2f, energy $%.2f, wear $%.2f, commission $%.2f, net $%.2f',
    van.name, #van.trip.parcels, van.trip.routeKm, result.revenue, result.energy, result.wear, result.commission, result.net))
end

local function status()
  if not ensureLoaded() then
    log('W', logTag, 'status: career is not active (RLS Career Overhaul is required)')
    return nil
  end
  local totals = fleet.totals
  log('I', logTag, string.format('fleet: %d/%d van(s) at Logistics level %d, next van $%d, %d trip(s), revenue $%.2f, costs $%.2f, net $%.2f',
    #fleet.vans, getVanLimit(), beamazon_adapter.getLogisticsLevel(), getVanPrice(), totals.trips, totals.revenue, totals.costs, totals.net))
  log('I', logTag, ownsHq() and string.format('  company HQ owned (%d slots)', balance.hqSlots)
    or string.format('  no company: HQ at Logistics level %d, $%d', balance.hqUnlockLevel, balance.hqPrice))
  local perHour = getNetPerVanHour()
  log('I', logTag, perHour and string.format('  net $%.2f per van-hour over %.1f van-hours', perHour, totals.vanSeconds / 3600)
    or '  net per van-hour: needs 1 van-hour of work')
  for _, van in ipairs(fleet.vans) do
    local doing = 'idle'
    if van.trip then
      doing = string.format('on a trip, %d%% done', math.floor(van.tripElapsed / van.trip.durationS * 100))
    end
    log('I', logTag, string.format('  %s (id %d): %s, %d trip(s), net $%.2f, sells for $%d', van.name, van.id, doing, van.trips, van.net, getSellValue(van)))
  end
  return fleet
end

local function onBeamazonCareerActive(active)
  setLoaded(active)
end

local function onBeamazonBeforeSave()
  payOut()
end

local function onBeamazonSave(saveContext)
  if not fleet then return end
  fleet.savedAt = os.time()
  beamazon_adapter.writeSaveFile(saveContext, saveFileName, fleet)
end

local function onExtensionLoaded()
  ensureLoaded()
end

M.ensureLoaded = ensureLoaded
M.getVans = getVans
M.getTotals = getTotals
M.getNetPerVanHour = getNetPerVanHour
M.getVanLimit = getVanLimit
M.ownsHq = ownsHq
M.buyHq = buyHq
M.getNextVanUnlock = getNextVanUnlock
M.getVanPrice = getVanPrice
M.addWorkTime = addWorkTime
M.buyVan = buyVan
M.getSellValue = getSellValue
M.sellVan = sellVan
M.takeOfflineSeconds = takeOfflineSeconds
M.payOut = payOut
M.onFleetTick = onFleetTick
M.recordTrip = recordTrip
M.status = status
M.onBeamazonCareerActive = onBeamazonCareerActive
M.onBeamazonBeforeSave = onBeamazonBeforeSave
M.onBeamazonSave = onBeamazonSave
M.onExtensionLoaded = onExtensionLoaded

return M
