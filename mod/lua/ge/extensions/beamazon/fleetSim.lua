-- Beamazon: abstract simulation. Each van is a table; the fleet advances every tickSeconds, never per frame.
-- Test speed-up (not saved; back to x1 whenever a career loads): beamazon_fleetSim.setSpeed(60) makes one game second count as a fleet minute.

local M = {}

local logTag = 'beamazon'

local tickSeconds = 2
-- A van whose trip ends mid-advance starts the next one with the leftover time, up to this many trips.
-- Generous on purpose: the offline catch-up (balance.offlineCapHours) runs in one advance.
local maxTripsPerAdvance = 500

local speed = 1
local pendingSeconds = 0

-- Advances one vehicle by dt fleet seconds. A truck needs a driver; without one it stays parked
-- (its trip in progress waits). A broken vehicle stands still until repaired.
local function advanceVan(van, dt)
  if (van.brokenFor or 0) > 0 then
    local repairUsed = math.min(van.brokenFor, dt)
    van.brokenFor = math.max(van.brokenFor - dt, 0)
    if van.brokenFor > 0 then return false end
    dt = dt - repairUsed
  end
  local driver
  if van.kind == 'truck' then
    driver = beamazon_company.getTruckDriver(van)
    if not driver then return false end
  end
  local mods = beamazon_fleetManager.getVehicleEffects(van)
  for _ = 1, maxTripsPerAdvance do
    if not van.trip then
      van.trip = beamazon_fleetEconomy.rollTrip(van.kind, mods)
      van.tripElapsed = 0
      if not van.trip then return true end
    end
    van.tripElapsed = van.tripElapsed + dt
    if van.tripElapsed < van.trip.durationS then return true end

    dt = van.tripElapsed - van.trip.durationS
    local wageShare = driver and beamazon_company.getDriverWageShare() or nil
    beamazon_fleetManager.recordTrip(van, beamazon_fleetEconomy.settleTrip(van.trip, wageShare, mods), driver)
    van.trip = nil
    van.tripElapsed = 0
    if (van.brokenFor or 0) > 0 then
      local repairUsed = math.min(van.brokenFor, dt)
      van.brokenFor = math.max(van.brokenFor - dt, 0)
      if van.brokenFor > 0 then return true end
      dt = dt - repairUsed
    end
  end
  return true
end

local function advanceFleet(dt)
  local workingVans, workingTrucks = 0, 0
  for _, van in ipairs(beamazon_fleetManager.getVans()) do
    if advanceVan(van, dt) then
      if van.kind == 'truck' then
        workingTrucks = workingTrucks + 1
      else
        workingVans = workingVans + 1
      end
    end
  end
  beamazon_fleetManager.addWorkTime(dt, workingTrucks, workingVans)
end

-- The work done while the player was away, paid as its own ledger entry.
local function catchUpOffline()
  local offline = beamazon_fleetManager.takeOfflineSeconds()
  if offline <= 0 then return end
  beamazon_fleetManager.payOut()
  advanceFleet(offline)
  beamazon_fleetManager.payOut('offline deliveries')
  log('I', logTag, string.format('offline progress: %.1f h', offline / 3600))
end

local function onBeamazonSimStep(dtSim)
  pendingSeconds = pendingSeconds + (dtSim or 0)
  if pendingSeconds < tickSeconds then return end
  local elapsed = pendingSeconds
  pendingSeconds = 0
  if not beamazon_fleetManager.ensureLoaded() then return end
  catchUpOffline()
  advanceFleet(elapsed * speed)
  beamazon_fleetManager.onFleetTick(elapsed)
end

local function setSpeed(value)
  if type(value) ~= 'number' or value <= 0 or value ~= value then
    log('E', logTag, 'setSpeed: expected a positive number, got ' .. tostring(value))
    return false
  end
  speed = value
  log('I', logTag, 'fleet speed x' .. tostring(value))
  return true
end

-- A speed-up from one career must not leak into the next one loaded in the same session.
local function onBeamazonCareerActive()
  speed = 1
  pendingSeconds = 0
end

M.setSpeed = setSpeed
M.onBeamazonCareerActive = onBeamazonCareerActive
M.onBeamazonSimStep = onBeamazonSimStep

return M
