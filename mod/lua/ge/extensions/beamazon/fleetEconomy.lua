-- Beamazon: what a trip carries, how long it takes and what it pays.
-- profit = R - (d * c * p_kWh) - (d * m) - (R * t)   (docs/plano.md, "Economia")

local M = {}

local balance = require('beamazon/balance')

-- Draws a parcel type more often the higher its RLS generation chance.
local function pickTemplate(templates)
  local total = 0
  for _, template in ipairs(templates) do total = total + template.chance end
  local roll = math.random() * total
  for _, template in ipairs(templates) do
    roll = roll - template.chance
    if roll <= 0 then return template end
  end
  return templates[#templates]
end

local function roundCents(value)
  return math.floor(value * 100 + 0.5) / 100
end

-- A new trip, or nil when RLS has no parcel types to draw from.
local function rollTrip()
  local templates = beamazon_adapter.getParcelTemplates()
  if #templates == 0 then return nil end

  local parcels, freeSlots, misses = {}, balance.vanCapacitySlots, 0
  while #parcels < balance.maxParcelsPerTrip and misses < 5 do
    local template = pickTemplate(templates)
    local slots = template.slots[math.random(#template.slots)]
    if slots <= freeSlots then
      -- Same +-10% jitter RLS gives its own parcels.
      local rewardWeight = template.weights[math.random(#template.weights)] * (0.9 + math.random() * 0.2)
      table.insert(parcels, {slots = slots, rewardWeight = rewardWeight})
      freeSlots = freeSlots - slots
    else
      misses = misses + 1
    end
  end
  if #parcels == 0 then return nil end

  local routeKm = balance.routeKmMin + math.random() * (balance.routeKmMax - balance.routeKmMin)
  local drivenKm = routeKm * 2
  return {
    routeKm = routeKm,
    drivenKm = drivenKm,
    parcels = parcels,
    durationS = drivenKm / balance.avgSpeedKmh * 3600 + #parcels * balance.handlingMinutesPerParcel * 60,
  }
end

-- Revenue at today's RLS prices, minus the costs. All values in $.
local function settleTrip(trip)
  local revenue, driverXp = 0, 0
  for _, parcel in ipairs(trip.parcels) do
    local parcelMoney, parcelXp = beamazon_adapter.getParcelReward(parcel.slots, parcel.rewardWeight, trip.routeKm * 1000)
    revenue = revenue + (parcelMoney or 0) * balance.fleetPayMultiplier
    driverXp = driverXp + (parcelXp or 0)
  end
  local energy = trip.drivenKm * balance.energyKwhPerKm * balance.energyPricePerKwh
  local wear = trip.drivenKm * balance.wearPerKm
  local commission = revenue * balance.commission
  return {
    revenue = roundCents(revenue),
    energy = roundCents(energy),
    wear = roundCents(wear),
    commission = roundCents(commission),
    net = roundCents(revenue - energy - wear - commission),
    xp = driverXp * balance.fleetXpShare,
  }
end

M.rollTrip = rollTrip
M.settleTrip = settleTrip

return M
