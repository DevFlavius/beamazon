-- Beamazon: data and actions for the fleet app on the RLS phone.
-- The screen is mod/ui/ui-vue/mods/beamazon/PhoneBeamazon.vue; it calls these functions through the UI bridge.

local M = {}

local balance = require('beamazon/balance')

local function vanRow(van)
  local row = {
    id = van.id,
    kind = van.kind,
    name = van.name,
    trips = van.trips,
    net = van.net,
    onTrip = van.trip ~= nil,
    progress = 0,
    parcels = 0,
    routeKm = 0,
    sellValue = beamazon_fleetManager.getSellValue(van),
  }
  if van.kind == 'truck' then
    local driver = beamazon_company.getTruckDriver(van)
    row.driver = driver and driver.name or nil
  end
  if van.trip then
    row.progress = math.min(van.tripElapsed / van.trip.durationS, 1)
    row.parcels = #van.trip.parcels
    row.routeKm = van.trip.routeKm
  end
  return row
end

local function driverRow(driver)
  return {id = driver.id, name = driver.name, trips = tonumber(driver.trips) or 0, earned = tonumber(driver.earned) or 0}
end

local function companyData()
  local data = {
    hq = beamazon_fleetManager.ownsHq(),
    hqPrice = balance.hqPrice,
    hqUnlockLevel = balance.hqUnlockLevel,
    hqSlots = balance.hqSlots,
    hqOnThisMap = beamazon_hq.hasSite(),
  }
  if not data.hq then return data end
  local c = beamazon_fleetManager.getCompany()
  local drivers = {}
  for _, driver in ipairs(beamazon_company.getDrivers()) do table.insert(drivers, driverRow(driver)) end
  data.level = beamazon_company.getLevel()
  data.xp = math.floor(tonumber(c.xp) or 0)
  data.drivers = drivers
  data.driverSlots = beamazon_company.getDriverSlots()
  data.driverWageShare = beamazon_company.getDriverWageShare()
  data.trucks = beamazon_fleetManager.countKind('truck')
  data.truckPrice = beamazon_fleetManager.getTruckPrice()
  data.netPerTruckHour = beamazon_fleetManager.getNetPerTruckHour()
  data.tree = beamazon_company.getTreeView()
  return data
end

local function getData()
  if not beamazon_fleetManager.ensureLoaded() then
    return {active = false}
  end
  local vans = {}
  for _, van in ipairs(beamazon_fleetManager.getVans()) do
    table.insert(vans, vanRow(van))
  end
  local history = beamazon_fleetManager.getHistory()
  local historyTotals = {
    trips = 0,
    revenue = 0,
    energy = 0,
    wear = 0,
    commission = 0,
    wages = 0,
    purchases = 0,
    net = 0,
  }
  for _, bucket in ipairs(history) do
    historyTotals.trips = historyTotals.trips + (bucket.trips or 0)
    historyTotals.revenue = historyTotals.revenue + (bucket.revenue or 0)
    historyTotals.energy = historyTotals.energy + (bucket.energy or 0)
    historyTotals.wear = historyTotals.wear + (bucket.wear or 0)
    historyTotals.commission = historyTotals.commission + (bucket.commission or 0)
    historyTotals.wages = historyTotals.wages + (bucket.wages or 0)
    historyTotals.purchases = historyTotals.purchases + (bucket.purchases or 0)
    historyTotals.net = historyTotals.net + (bucket.net or 0)
  end
  return {
    active = true,
    vanPrice = beamazon_fleetManager.getVanPrice(),
    vanLimit = beamazon_fleetManager.getVanLimit(),
    logisticsLevel = beamazon_adapter.getLogisticsLevel(),
    nextVanUnlock = beamazon_fleetManager.getNextVanUnlock(),
    company = companyData(),
    totals = beamazon_fleetManager.getTotals(),
    netPerVanHour = beamazon_fleetManager.getNetPerVanHour(),
    vans = vans,
    history = history,
    historyTotals = historyTotals,
  }
end

-- {ok, reason, data}: reason is 'careerInactive', 'vanLimit' or 'notEnoughMoney' when ok is false.
local function buyVan()
  local ok, reason = beamazon_fleetManager.buyVan()
  return {ok = ok, reason = reason, data = getData()}
end

-- {ok, reason, value, data}: reason is 'careerInactive' or 'noVan' when ok is false.
local function sellVan(id)
  local ok, result = beamazon_fleetManager.sellVan(id)
  return {ok = ok, reason = not ok and result or nil, value = ok and result or nil, data = getData()}
end

-- {ok, data}: ok is false when this map has no HQ or the player is on foot without a vehicle.
local function routeToHq()
  return {ok = beamazon_hq.routeToHq(), data = getData()}
end

-- {ok, reason, data} for each company action; reason is the module's reason string when ok is false.
local function result(ok, reason)
  return {ok = ok == true, reason = not ok and reason or nil, data = getData()}
end

local function buyTruck() return result(beamazon_fleetManager.buyTruck()) end
local function buyUpgrade(id) return result(beamazon_company.buyUpgrade(id)) end
local function hireDriver()
  local ok, driverOrReason = beamazon_company.hireDriver()
  return result(ok, driverOrReason)
end
local function fireDriver(id) return result(beamazon_company.fireDriver(id)) end

M.getData = getData
M.buyTruck = buyTruck
M.buyUpgrade = buyUpgrade
M.hireDriver = hireDriver
M.fireDriver = fireDriver
M.routeToHq = routeToHq
M.sellVan = sellVan
M.buyVan = buyVan

return M
