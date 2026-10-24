-- Beamazon: data and actions for the fleet app on the RLS phone.
-- The screen is mod/ui/ui-vue/mods/beamazon/PhoneBeamazon.vue; it calls these functions through the UI bridge.

local M = {}

local balance = require('beamazon/balance')

local function vanRow(van)
  local cond = van.condition or 1
  local upgrades = {}
  for _, def in ipairs(balance.vehicleUpgrades or {}) do
    local level = (van.upgrades and van.upgrades[def.id]) or 0
    table.insert(upgrades, {
      id = def.id,
      title = def.title,
      description = def.description,
      level = level,
      maxLevel = def.maxLevel,
      cost = beamazon_fleetManager.getVehicleUpgradeCost(van, def.id),
    })
  end
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
    condition = cond >= 0.999 and 100 or math.max(0, math.min(100, math.floor(cond * 100 + 0.0001))),
    brokenMinutes = (van.brokenFor and van.brokenFor > 0) and math.ceil(van.brokenFor / 60) or 0,
    serviceCost = beamazon_fleetManager.getServiceCost(van),
    breakdowns = tonumber(van.breakdowns) or 0,
    upgrades = upgrades,
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
  local sites = beamazon_hq.getSitesOnThisMap and beamazon_hq.getSitesOnThisMap() or {}
  local sitesByBranch = {}
  for _, s in ipairs(sites) do
    if s.branch then sitesByBranch[s.branch] = s end
  end
  local branches = {}
  for _, b in ipairs(beamazon_fleetManager.getBranches()) do
    local site = sitesByBranch[b.id]
    table.insert(branches, {
      id = b.id,
      name = b.name,
      price = b.price,
      slots = b.slots,
      companyLevel = b.companyLevel,
      owned = b.owned == true,
      onThisMap = site ~= nil,
      siteId = site and site.id or nil,
    })
  end
  data.branches = branches
  return data
end

local function getData()
  if not beamazon_fleetManager.ensureLoaded() then
    return {active = false}
  end
  local vans = {}
  local serviceAllCost = 0
  for _, van in ipairs(beamazon_fleetManager.getVans()) do
    local row = vanRow(van)
    table.insert(vans, row)
    serviceAllCost = serviceAllCost + (row.serviceCost or 0)
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
    repairs = 0,
    bonuses = 0,
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
    historyTotals.repairs = historyTotals.repairs + (bucket.repairs or 0)
    historyTotals.bonuses = historyTotals.bonuses + (bucket.bonuses or 0)
    historyTotals.net = historyTotals.net + (bucket.net or 0)
  end
  return {
    active = true,
    vanPrice = beamazon_fleetManager.getVanPrice(),
    vanLimit = beamazon_fleetManager.getVanLimit(),
    logisticsLevel = beamazon_adapter.getLogisticsLevel(),
    nextVanUnlock = beamazon_fleetManager.getNextVanUnlock(),
    company = companyData(),
    contracts = beamazon_contracts and beamazon_contracts.getView() or nil,
    totals = beamazon_fleetManager.getTotals(),
    netPerVanHour = beamazon_fleetManager.getNetPerVanHour(),
    vans = vans,
    serviceAllCost = serviceAllCost,
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

local function routeToSite(siteId)
  local ok = beamazon_hq.routeToSite and beamazon_hq.routeToSite(siteId) or false
  return result(ok, not ok and 'noRoute' or nil)
end

local function buyTruck() return result(beamazon_fleetManager.buyTruck()) end
local function buyUpgrade(id) return result(beamazon_company.buyUpgrade(id)) end
local function hireDriver()
  local ok, driverOrReason = beamazon_company.hireDriver()
  return result(ok, driverOrReason)
end
local function fireDriver(id) return result(beamazon_company.fireDriver(id)) end
local function serviceVan(id)
  local ok, reason = beamazon_fleetManager.serviceVan(id)
  return result(ok, reason)
end
local function serviceAll()
  beamazon_fleetManager.serviceAll()
  return result(true)
end
local function upgradeVehicle(vanId, upgradeId)
  local ok, reason = beamazon_fleetManager.upgradeVehicle(vanId, upgradeId)
  return result(ok, reason)
end
local function acceptContract()
  if not beamazon_contracts then return result(false, 'careerInactive') end
  return result(beamazon_contracts.accept())
end
local function declineContract()
  if not beamazon_contracts then return result(false, 'careerInactive') end
  return result(beamazon_contracts.decline())
end

M.getData = getData
M.buyTruck = buyTruck
M.buyUpgrade = buyUpgrade
M.hireDriver = hireDriver
M.fireDriver = fireDriver
M.serviceVan = serviceVan
M.serviceAll = serviceAll
M.upgradeVehicle = upgradeVehicle
M.acceptContract = acceptContract
M.declineContract = declineContract
M.routeToHq = routeToHq
M.routeToSite = routeToSite
M.sellVan = sellVan
M.buyVan = buyVan

return M
