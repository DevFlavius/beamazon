-- Beamazon: the fleet as data. Buying vans, the books per van and the save file.
-- Console (GE Lua): beamazon_fleetManager.buyVan()   beamazon_fleetManager.buyTruck()   beamazon_fleetManager.sellVan(id)
--                   beamazon_fleetManager.status()
-- fleet.vans holds every vehicle: kind is 'van' (saves from before trucks have none) or 'truck'.

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
    -- truckSeconds and truckNet are the same for trucks with a driver (kept apart so the van rate stays comparable).
    totals = {trips = 0, revenue = 0, costs = 0, net = 0, vanSeconds = 0, timedNet = 0, truckSeconds = 0, truckNet = 0},
    company = {hq = false},
    history = {},
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
      van.kind = van.kind == 'truck' and 'truck' or 'van'
      van.condition = math.max(balance.minCondition or 0, math.min(1, tonumber(van.condition) or 1))
      van.brokenFor = math.max(tonumber(van.brokenFor) or 0, 0)
      van.breakdowns = tonumber(van.breakdowns) or 0
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
  loaded.truckOffer = tonumber(data.truckOffer)
  -- beamazon_company checks the rest of the company fields when it reads them.
  if type(data.company) == 'table' and data.company.hq == true then
    loaded.company = data.company
    loaded.company.foundedAt = tonumber(data.company.foundedAt)
  end
  if type(data.history) == 'table' then
    local history = {}
    for _, b in ipairs(data.history) do
      if type(b) == 'table' and type(b.hour) == 'number' then
        table.insert(history, {
          hour = b.hour,
          trips = tonumber(b.trips) or 0,
          revenue = tonumber(b.revenue) or 0,
          energy = tonumber(b.energy) or 0,
          wear = tonumber(b.wear) or 0,
          commission = tonumber(b.commission) or 0,
          wages = tonumber(b.wages) or 0,
          purchases = tonumber(b.purchases) or 0,
          repairs = tonumber(b.repairs) or 0,
          net = tonumber(b.net) or 0,
        })
      end
    end
    while #history > balance.historyHours do
      table.remove(history, 1)
    end
    loaded.history = history
  else
    loaded.history = {}
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
    fleet.truckOffer = fleet.truckOffer or rollVanOffer()
    if fleet.savedAt then
      local capHours = balance.offlineCapHours + (beamazon_company and beamazon_company.getEffect('offlineHours') or 0)
      offlineSeconds = math.min(math.max(os.time() - fleet.savedAt, 0), capHours * 3600)
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

-- The company part of the save ({hq = false} without one); beamazon_company reads and changes it.
local function getCompany()
  return fleet and fleet.company or nil
end

local function countKind(kind)
  local count = 0
  for _, vehicle in ipairs(fleet and fleet.vans or {}) do
    if vehicle.kind == kind then count = count + 1 end
  end
  return count
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

-- Called by fleetSim each time the fleet advances by dt fleet seconds, with how many trucks and vans were working.
local function addWorkTime(dt, workingTrucks, workingVans)
  if not fleet then return end
  local vans = workingVans or countKind('van')
  fleet.totals.vanSeconds = fleet.totals.vanSeconds + dt * vans
  fleet.totals.truckSeconds = fleet.totals.truckSeconds + dt * (workingTrucks or 0)
end

-- Net profit per truck-hour with a driver (wage already paid), or nil until one truck-hour of work.
local function getNetPerTruckHour()
  local totals = fleet and fleet.totals
  if not totals or totals.truckSeconds < 3600 then return nil end
  return totals.truckNet / (totals.truckSeconds / 3600)
end

local function ownsHq()
  return fleet ~= nil and fleet.company.hq == true
end

-- How many vehicles (vans and trucks) the player may own: the personal vans the Logistics level unlocks
-- (balance.personalVanUnlocks), plus the HQ slots and the Parking Bays upgrades.
local function getVanLimit()
  local level, limit = beamazon_adapter.getLogisticsLevel(), 0
  for _, unlock in ipairs(balance.personalVanUnlocks) do
    if level >= unlock.level then limit = math.max(limit, unlock.vans) end
  end
  -- The HQ adds its slots on top of the personal vans (Flavio, 2026-10-24: 3 + 5 = 8).
  if ownsHq() then limit = limit + balance.hqSlots + beamazon_company.getEffect('slots') end
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

local function vehicleDiscount()
  return 1 - (beamazon_company and beamazon_company.getEffect('vehicleDiscount') or 0)
end

-- Today's price for a van: the offer times the live RLS vehicle market, less the Fleet Deals upgrade, in whole dollars.
local function getVanPrice()
  local offer = fleet and fleet.vanOffer or 1
  return math.floor(balance.vanPrice * offer * beamazon_adapter.getVehicleBuyMultiplier() * vehicleDiscount() + 0.5)
end

local function getTruckPrice()
  local offer = fleet and fleet.truckOffer or 1
  return math.floor(balance.truckPrice * offer * beamazon_adapter.getVehicleBuyMultiplier() * vehicleDiscount() + 0.5)
end

-- The bucket for the current hour, appending a new one when the hour rolls over and dropping the ones older than historyHours.
local function currentBucket()
  if not fleet then return nil end
  fleet.history = fleet.history or {}
  local hour = math.floor(os.time() / 3600) * 3600
  local last = fleet.history[#fleet.history]
  if not last or last.hour ~= hour then
    last = {
      hour = hour,
      trips = 0,
      revenue = 0,
      energy = 0,
      wear = 0,
      commission = 0,
      wages = 0,
      purchases = 0,
      repairs = 0,
      net = 0,
    }
    table.insert(fleet.history, last)
  end
  -- hours with no activity have no bucket, so the list is trimmed by age, not by length
  while fleet.history[1] and fleet.history[1].hour <= hour - balance.historyHours * 3600 do
    table.remove(fleet.history, 1)
  end
  return last
end

-- Records a purchase (amount > 0: vehicle, HQ, company upgrade) or a sale (amount < 0) in the current hour's finance bucket.
local function recordPurchase(amount)
  local bucket = currentBucket()
  if not bucket then return end
  local val = tonumber(amount) or 0
  bucket.purchases = bucket.purchases + val
  bucket.net = bucket.net - val
end

-- Records a repair or service cost in the current hour's finance bucket.
local function recordRepair(amount)
  local bucket = currentBucket()
  if not bucket then return end
  local val = tonumber(amount) or 0
  bucket.repairs = bucket.repairs + val
  bucket.net = bucket.net - val
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
  table.insert(fleet.vans, {
    id = id, kind = 'van', name = 'Van ' .. id,
    trips = 0, net = 0, tripElapsed = 0, pricePaid = price,
    condition = 1, brokenFor = 0, breakdowns = 0,
  })
  recordPurchase(price)
  log('I', logTag, string.format('buyVan: Van %d bought for $%d (fleet: %d, next offer $%d)', id, price, #fleet.vans, getVanPrice()))
  return true
end

-- True, or false and the reason: 'careerInactive', 'noCompany', 'vanLimit' or 'notEnoughMoney'.
-- A truck takes a fleet slot like a van and only works while a hired driver is free for it.
local function buyTruck()
  if not ensureLoaded() then
    log('W', logTag, 'buyTruck: career is not active (RLS Career Overhaul is required)')
    return false, 'careerInactive'
  end
  if not ownsHq() then
    log('W', logTag, 'buyTruck: trucks need the company HQ')
    return false, 'noCompany'
  end
  if #fleet.vans >= getVanLimit() then
    log('W', logTag, string.format('buyTruck: fleet limit reached (%d)', getVanLimit()))
    return false, 'vanLimit'
  end
  local id, price = fleet.nextVanId, getTruckPrice()
  if not beamazon_adapter.pay(price, 'Beamazon: truck ' .. id) then
    log('W', logTag, string.format('buyTruck: not enough money for a truck ($%d)', price))
    return false, 'notEnoughMoney'
  end
  fleet.nextVanId = id + 1
  fleet.truckOffer = rollVanOffer()
  table.insert(fleet.vans, {
    id = id, kind = 'truck', name = 'Truck ' .. id,
    trips = 0, net = 0, tripElapsed = 0, pricePaid = price,
    condition = 1, brokenFor = 0, breakdowns = 0,
  })
  recordPurchase(price)
  log('I', logTag, string.format('buyTruck: Truck %d bought for $%d (fleet: %d, next offer $%d)', id, price, #fleet.vans, getTruckPrice()))
  return true
end

local function findVan(id)
  for index, van in ipairs(fleet and fleet.vans or {}) do
    if van.id == id then return van, index end
  end
end

-- What a vehicle sells for now: its price minus the resale loss, times the live RLS vehicle market,
-- scaled by condition (0.5 at condition 0 up to 1.0 at condition 1).
-- Vans bought before prices were stored count at the average price.
local function getSellValue(van)
  local paid = tonumber(van.pricePaid) or (van.kind == 'truck' and balance.truckPrice or balance.vanPrice)
  local conditionFactor = 0.5 + 0.5 * (van.condition or 1)
  return math.floor(paid * balance.vanResaleShare * beamazon_adapter.getVehicleBuyMultiplier() * conditionFactor + 0.5)
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
  recordPurchase(-value)
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
  fleet.company = {hq = true, foundedAt = os.time(), xp = 0, xpEarned = 0, upgrades = {}, drivers = {}, nextDriverId = 1}
  recordPurchase(balance.hqPrice)
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

-- Called by fleetSim when a vehicle finishes a trip: keeps the books; the money goes out in payOut.
-- driver is the truck's driver (nil for a van).
local function recordTrip(van, result, driver)
  local costs = result.energy + result.wear + result.commission + (result.wage or 0)
  pending.net = pending.net + result.net
  pending.trips = pending.trips + 1
  pending.xp = pending.xp + (result.xp or 0)
  van.trips = van.trips + 1
  van.net = van.net + result.net
  fleet.totals.trips = fleet.totals.trips + 1
  fleet.totals.revenue = fleet.totals.revenue + result.revenue
  fleet.totals.costs = fleet.totals.costs + costs
  fleet.totals.net = fleet.totals.net + result.net
  if van.kind == 'truck' then
    fleet.totals.truckNet = fleet.totals.truckNet + result.net
    if driver then beamazon_company.recordDriverTrip(driver, result.wage or 0) end
  else
    fleet.totals.timedNet = fleet.totals.timedNet + result.net
  end
  local bucket = currentBucket()
  if bucket then
    bucket.trips = bucket.trips + 1
    bucket.revenue = bucket.revenue + result.revenue
    bucket.energy = bucket.energy + result.energy
    bucket.wear = bucket.wear + result.wear
    bucket.commission = bucket.commission + result.commission
    bucket.wages = bucket.wages + (result.wage or 0)
    bucket.net = bucket.net + result.net
  end
  if beamazon_company then beamazon_company.addXpFromProfit(result.net) end
  local isTruck = van.kind == 'truck'
  local lossPerKm = isTruck and balance.truckConditionLossPerKm or balance.conditionLossPerKm
  local conditionEffect = beamazon_company and beamazon_company.getEffect('conditionLoss') or 0
  local loss = (van.trip.drivenKm or 0) * lossPerKm * (1 + conditionEffect)
  van.condition = math.max(balance.minCondition or 0, (van.condition or 1) - loss)

  if van.condition < balance.breakdownBelow then
    local chance = balance.breakdownChanceMax * (balance.breakdownBelow - van.condition) / balance.breakdownBelow
    if math.random() < chance then
      van.brokenFor = balance.breakdownRepairSeconds
      local cost = balance.breakdownRepairCost * (isTruck and 2 or 1)
      if not beamazon_adapter.pay(cost, 'Beamazon: ' .. van.name .. ' repair') then
        pending.net = pending.net - cost
      end
      fleet.totals.costs = fleet.totals.costs + cost
      fleet.totals.net = fleet.totals.net - cost
      recordRepair(cost)
      van.breakdowns = (van.breakdowns or 0) + 1
      local minutes = math.ceil(balance.breakdownRepairSeconds / 60)
      local msg = string.format('%s broke down: $%d repair, back in %d min.', van.name, cost, minutes)
      log('I', logTag, msg)
      if guihooks and guihooks.trigger then
        guihooks.trigger('toastrMsg', {type = 'warning', title = 'Beamazon', msg = msg})
      end
    end
  end
  log('D', logTag, string.format('%s delivered %d parcel(s) over %.1f km: revenue $%.2f, energy $%.2f, wear $%.2f, commission $%.2f, net $%.2f',
    van.name, #van.trip.parcels, van.trip.routeKm, result.revenue, result.energy, result.wear, result.commission, result.net))
end

-- Cost in $ to service a vehicle to 100% condition.
local function serviceCost(van)
  local condition = van.condition or 1
  if condition >= 0.999 then return 0 end
  local effect = beamazon_company and beamazon_company.getEffect('serviceCost') or 0
  local mult = van.kind == 'truck' and 2 or 1
  local cost = math.ceil((1 - condition) * 100 * balance.serviceCostPerPoint * mult * math.max(0, 1 + effect))
  return math.max(0, cost)
end

-- True and the cost charged, or false and the reason: 'careerInactive', 'noVan', 'alreadyNew' or 'notEnoughMoney'.
local function serviceVan(id)
  if not ensureLoaded() then
    log('W', logTag, 'serviceVan: career is not active (RLS Career Overhaul is required)')
    return false, 'careerInactive'
  end
  local van = findVan(id)
  if not van then
    log('W', logTag, 'serviceVan: no van with id ' .. tostring(id))
    return false, 'noVan'
  end
  if (van.condition or 1) >= 0.999 then
    return false, 'alreadyNew'
  end
  local cost = serviceCost(van)
  if not beamazon_adapter.pay(cost, 'Beamazon: ' .. van.name .. ' service') then
    log('W', logTag, string.format('serviceVan: not enough money for %s service ($%d)', van.name, cost))
    return false, 'notEnoughMoney'
  end
  van.condition = 1
  recordRepair(cost)
  log('I', logTag, string.format('serviceVan: %s serviced for $%d', van.name, cost))
  return true, cost
end

-- Services every vehicle below 0.999 condition that can be paid, worst condition first.
-- Stops at the first failed payment; returns count, total.
local function serviceAll()
  if not ensureLoaded() then return 0, 0 end
  local candidates = {}
  for _, van in ipairs(fleet.vans) do
    if (van.condition or 1) < 0.999 then
      table.insert(candidates, van)
    end
  end
  table.sort(candidates, function(a, b)
    return (a.condition or 1) < (b.condition or 1)
  end)
  local count, total = 0, 0
  for _, van in ipairs(candidates) do
    local ok, cost = serviceVan(van.id)
    if ok then
      count = count + 1
      total = total + cost
    else
      break
    end
  end
  return count, total
end

local function status()
  if not ensureLoaded() then
    log('W', logTag, 'status: career is not active (RLS Career Overhaul is required)')
    return nil
  end
  local totals = fleet.totals
  log('I', logTag, string.format('fleet: %d/%d vehicle(s) at Logistics level %d, next van $%d, %d trip(s), revenue $%.2f, costs $%.2f, net $%.2f',
    #fleet.vans, getVanLimit(), beamazon_adapter.getLogisticsLevel(), getVanPrice(), totals.trips, totals.revenue, totals.costs, totals.net))
  if ownsHq() then
    local level = beamazon_company.getLevel()
    log('I', logTag, string.format('  company level %d (%.0f XP earned, %.0f to spend), %d/%d driver(s), next truck $%d',
      level.level, level.xpEarned, fleet.company.xp or 0, #beamazon_company.getDrivers(), beamazon_company.getDriverSlots(), getTruckPrice()))
  else
    log('I', logTag, string.format('  no company: HQ at Logistics level %d, $%d', balance.hqUnlockLevel, balance.hqPrice))
  end
  local perTruckHour = getNetPerTruckHour()
  if perTruckHour then log('I', logTag, string.format('  net $%.2f per truck-hour (driver paid)', perTruckHour)) end
  local perHour = getNetPerVanHour()
  log('I', logTag, perHour and string.format('  net $%.2f per van-hour over %.1f van-hours', perHour, totals.vanSeconds / 3600)
    or '  net per van-hour: needs 1 van-hour of work')
  for _, van in ipairs(fleet.vans) do
    local doing = 'idle'
    if (van.brokenFor or 0) > 0 then
      doing = string.format('broken down, %dm left', math.ceil(van.brokenFor / 60))
    elseif van.kind == 'truck' and not beamazon_company.getTruckDriver(van) then
      doing = 'parked, no driver'
    elseif van.trip then
      doing = string.format('on a trip, %d%% done', math.floor(van.tripElapsed / van.trip.durationS * 100))
    end
    local condPct = (van.condition or 1) >= 0.999 and 100 or math.floor((van.condition or 1) * 100)
    log('I', logTag, string.format('  %s (id %d): %s, condition %d%%, %d trip(s), net $%.2f, sells for $%d', van.name, van.id, doing, condPct, van.trips, van.net, getSellValue(van)))
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

-- The hour buckets of the last balance.historyHours hours, oldest first, or {} when not loaded.
local function getHistory()
  return fleet and fleet.history or {}
end

local function onExtensionLoaded()
  ensureLoaded()
end

M.ensureLoaded = ensureLoaded
M.getVans = getVans
M.getTotals = getTotals
M.getCompany = getCompany
M.getHistory = getHistory
M.recordPurchase = recordPurchase
M.countKind = countKind
M.getNetPerTruckHour = getNetPerTruckHour
M.getTruckPrice = getTruckPrice
M.buyTruck = buyTruck
M.getNetPerVanHour = getNetPerVanHour
M.getVanLimit = getVanLimit
M.ownsHq = ownsHq
M.buyHq = buyHq
M.getNextVanUnlock = getNextVanUnlock
M.getVanPrice = getVanPrice
M.addWorkTime = addWorkTime
M.getServiceCost = serviceCost
M.serviceCost = serviceCost
M.serviceVan = serviceVan
M.serviceAll = serviceAll
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
