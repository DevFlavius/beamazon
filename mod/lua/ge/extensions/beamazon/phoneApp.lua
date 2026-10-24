-- Beamazon: data and actions for the fleet app on the RLS phone.
-- The screen is mod/ui/ui-vue/mods/beamazon/PhoneBeamazon.vue; it calls these functions through the UI bridge.

local M = {}

local function vanRow(van)
  local row = {
    id = van.id,
    name = van.name,
    trips = van.trips,
    net = van.net,
    onTrip = van.trip ~= nil,
    progress = 0,
    parcels = 0,
    routeKm = 0,
  }
  if van.trip then
    row.progress = math.min(van.tripElapsed / van.trip.durationS, 1)
    row.parcels = #van.trip.parcels
    row.routeKm = van.trip.routeKm
  end
  return row
end

local function getData()
  if not beamazon_fleetManager.ensureLoaded() then
    return {active = false}
  end
  local vans = {}
  for _, van in ipairs(beamazon_fleetManager.getVans()) do
    table.insert(vans, vanRow(van))
  end
  return {
    active = true,
    vanPrice = beamazon_fleetManager.getVanPrice(),
    vanLimit = beamazon_fleetManager.getVanLimit(),
    logisticsLevel = beamazon_adapter.getLogisticsLevel(),
    nextVanUnlock = beamazon_fleetManager.getNextVanUnlock(),
    totals = beamazon_fleetManager.getTotals(),
    netPerVanHour = beamazon_fleetManager.getNetPerVanHour(),
    vans = vans,
  }
end

-- {ok, reason, data}: reason is 'careerInactive', 'vanLimit' or 'notEnoughMoney' when ok is false.
local function buyVan()
  local ok, reason = beamazon_fleetManager.buyVan()
  return {ok = ok, reason = reason, data = getData()}
end

M.getData = getData
M.buyVan = buyVan

return M
