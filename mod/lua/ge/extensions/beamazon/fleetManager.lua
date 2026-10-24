-- Beamazon: the fleet as data. Buying vans, the books per van and the save file.
-- Console (GE Lua): beamazon_fleetManager.buyVan()   beamazon_fleetManager.status()

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

-- Trip profits not yet in the balance.
local pending = {net = 0, trips = 0}
local payoutTimer = 0

local function newFleet()
  return {
    version = saveVersion,
    nextVanId = 1,
    vans = {},
    -- vanSeconds and timedNet feed the per-van-hour rate; saves from before them start both at 0.
    totals = {trips = 0, revenue = 0, costs = 0, net = 0, vanSeconds = 0, timedNet = 0},
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
  return loaded
end

local function setLoaded(active)
  pending = {net = 0, trips = 0}
  payoutTimer = 0
  offlineSeconds = 0
  if active then
    fleet = loadFleet()
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

-- True, or false and the reason: 'careerInactive' or 'notEnoughMoney'.
local function buyVan()
  if not ensureLoaded() then
    log('W', logTag, 'buyVan: career is not active (RLS Career Overhaul is required)')
    return false, 'careerInactive'
  end
  local id = fleet.nextVanId
  if not beamazon_adapter.pay(balance.vanPrice, 'Beamazon: van ' .. id) then
    log('W', logTag, string.format('buyVan: not enough money for a van ($%s)', tostring(balance.vanPrice)))
    return false, 'notEnoughMoney'
  end
  fleet.nextVanId = id + 1
  table.insert(fleet.vans, {id = id, name = 'Van ' .. id, trips = 0, net = 0, tripElapsed = 0})
  log('I', logTag, string.format('buyVan: Van %d bought for $%s (fleet: %d)', id, tostring(balance.vanPrice), #fleet.vans))
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
  beamazon_adapter.addMoney(pending.net, string.format('Beamazon: %s (%d)', label or 'fleet deliveries', pending.trips))
  pending = {net = 0, trips = 0}
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
  log('I', logTag, string.format('fleet: %d van(s), %d trip(s), revenue $%.2f, costs $%.2f, net $%.2f',
    #fleet.vans, totals.trips, totals.revenue, totals.costs, totals.net))
  local perHour = getNetPerVanHour()
  log('I', logTag, perHour and string.format('  net $%.2f per van-hour over %.1f van-hours', perHour, totals.vanSeconds / 3600)
    or '  net per van-hour: needs 1 van-hour of work')
  for _, van in ipairs(fleet.vans) do
    local doing = 'idle'
    if van.trip then
      doing = string.format('on a trip, %d%% done', math.floor(van.tripElapsed / van.trip.durationS * 100))
    end
    log('I', logTag, string.format('  %s: %s, %d trip(s), net $%.2f', van.name, doing, van.trips, van.net))
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
M.addWorkTime = addWorkTime
M.buyVan = buyVan
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
