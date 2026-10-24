-- Beamazon: the fleet as data. Buying vans, the books per van and the save file.
-- Console (GE Lua): beamazon_fleetManager.buyVan()   beamazon_fleetManager.status()

local M = {}

local logTag = 'beamazon'
local balance = require('beamazon/balance')

local saveFileName = 'beamazon.json'
local saveVersion = 1

-- nil while no career is loaded; the sim only runs when this is set.
local fleet

local function newFleet()
  return {
    version = saveVersion,
    nextVanId = 1,
    vans = {},
    totals = {trips = 0, revenue = 0, costs = 0, net = 0},
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
  return loaded
end

local function setLoaded(active)
  if active then
    fleet = loadFleet()
    log('I', logTag, string.format('fleet loaded: %d van(s)', #fleet.vans))
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

local function buyVan()
  if not ensureLoaded() then
    log('W', logTag, 'buyVan: career is not active (RLS Career Overhaul is required)')
    return false
  end
  local id = fleet.nextVanId
  if not beamazon_adapter.pay(balance.vanPrice, 'Beamazon: van ' .. id) then
    log('W', logTag, string.format('buyVan: not enough money for a van ($%s)', tostring(balance.vanPrice)))
    return false
  end
  fleet.nextVanId = id + 1
  table.insert(fleet.vans, {id = id, name = 'Van ' .. id, trips = 0, net = 0, tripElapsed = 0})
  log('I', logTag, string.format('buyVan: Van %d bought for $%s (fleet: %d)', id, tostring(balance.vanPrice), #fleet.vans))
  return true
end

-- Called by fleetSim when a van finishes a trip: pays the player and keeps the books.
local function recordTrip(van, result)
  local costs = result.energy + result.wear + result.commission
  beamazon_adapter.addMoney(result.net, 'Beamazon: ' .. van.name)
  van.trips = van.trips + 1
  van.net = van.net + result.net
  fleet.totals.trips = fleet.totals.trips + 1
  fleet.totals.revenue = fleet.totals.revenue + result.revenue
  fleet.totals.costs = fleet.totals.costs + costs
  fleet.totals.net = fleet.totals.net + result.net
  log('I', logTag, string.format('%s delivered %d parcel(s) over %.1f km: revenue $%.2f, energy $%.2f, wear $%.2f, commission $%.2f, net $%.2f',
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

local function onBeamazonSave(saveContext)
  if not fleet then return end
  beamazon_adapter.writeSaveFile(saveContext, saveFileName, fleet)
end

local function onExtensionLoaded()
  ensureLoaded()
end

M.ensureLoaded = ensureLoaded
M.getVans = getVans
M.buyVan = buyVan
M.recordTrip = recordTrip
M.status = status
M.onBeamazonCareerActive = onBeamazonCareerActive
M.onBeamazonSave = onBeamazonSave
M.onExtensionLoaded = onExtensionLoaded

return M
