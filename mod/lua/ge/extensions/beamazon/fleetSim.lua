-- Beamazon: abstract simulation. Each van is a table; the fleet advances every tickSeconds, never per frame.
-- Test speed-up (not saved): beamazon_fleetSim.setSpeed(60) makes one game second count as a fleet minute.

local M = {}

local logTag = 'beamazon'

local tickSeconds = 2
-- A van whose trip ends mid-advance starts the next one with the leftover time, up to this many trips.
-- Generous on purpose: the offline catch-up (balance.offlineCapHours) runs in one advance.
local maxTripsPerAdvance = 500

local speed = 1
local pendingSeconds = 0

-- Advances one van by dt fleet seconds.
local function advanceVan(van, dt)
  for _ = 1, maxTripsPerAdvance do
    if not van.trip then
      van.trip = beamazon_fleetEconomy.rollTrip()
      van.tripElapsed = 0
      if not van.trip then return end
    end
    van.tripElapsed = van.tripElapsed + dt
    if van.tripElapsed < van.trip.durationS then return end

    dt = van.tripElapsed - van.trip.durationS
    beamazon_fleetManager.recordTrip(van, beamazon_fleetEconomy.settleTrip(van.trip))
    van.trip = nil
    van.tripElapsed = 0
  end
end

local function advanceFleet(dt)
  for _, van in ipairs(beamazon_fleetManager.getVans()) do
    advanceVan(van, dt)
  end
  beamazon_fleetManager.addWorkTime(dt)
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

M.setSpeed = setSpeed
M.onBeamazonSimStep = onBeamazonSimStep

return M
