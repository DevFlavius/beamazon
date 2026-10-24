-- Beamazon: what a trip carries, how long it takes and what it pays.
-- profit = R - (d * c * p_kWh) - (d * m) - (R * t)   (docs/plano.md, "Economia")

local M = {}

local balance = require('beamazon/balance')

-- What one kind of vehicle carries and drives. The van profile is the original balance fields.
local profiles = {
  van = {
    capacitySlots = balance.vanCapacitySlots, maxParcels = balance.maxParcelsPerTrip,
    routeKmMin = balance.routeKmMin, routeKmMax = balance.routeKmMax, avgSpeedKmh = balance.avgSpeedKmh,
    handlingMinutesPerParcel = balance.handlingMinutesPerParcel,
    energyKwhPerKm = balance.energyKwhPerKm, wearPerKm = balance.wearPerKm,
  },
  truck = balance.truck,
}

local function profileOf(kind)
  return profiles[kind] or profiles.van
end

-- A company upgrade's summed effect, 0 without the company module or a company.
local function effect(name)
  return beamazon_company and beamazon_company.getEffect(name) or 0
end

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

-- A new trip for a 'van' (default) or a 'truck', or nil when RLS has no parcel types to draw from.
local function rollTrip(kind)
  local profile = profileOf(kind)
  local templates = beamazon_adapter.getParcelTemplates()
  if #templates == 0 then return nil end

  local parcels, freeSlots, misses = {}, profile.capacitySlots, 0
  while #parcels < profile.maxParcels and misses < 5 do
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

  local routeKm = profile.routeKmMin + math.random() * (profile.routeKmMax - profile.routeKmMin)
  local drivenKm = routeKm * 2
  local durationS = drivenKm / profile.avgSpeedKmh * 3600 + #parcels * profile.handlingMinutesPerParcel * 60
  return {
    kind = kind or 'van',
    routeKm = routeKm,
    drivenKm = drivenKm,
    parcels = parcels,
    durationS = durationS * math.max(1 + effect('tripTime'), 0.5),
  }
end

-- Revenue at today's RLS prices, minus the costs. All values in $.
-- A truck trip also pays its driver a share of the revenue (wageShare, from the company).
local function settleTrip(trip, wageShare)
  local profile = profileOf(trip.kind)
  local revenue, driverXp = 0, 0
  for _, parcel in ipairs(trip.parcels) do
    local parcelMoney, parcelXp = beamazon_adapter.getParcelReward(parcel.slots, parcel.rewardWeight, trip.routeKm * 1000)
    revenue = revenue + (parcelMoney or 0) * balance.fleetPayMultiplier
    driverXp = driverXp + (parcelXp or 0)
  end
  revenue = revenue * (1 + effect('revenue'))
  local running = math.max(1 + effect('runningCosts'), 0)
  local energy = trip.drivenKm * profile.energyKwhPerKm * balance.energyPricePerKwh * running
  local wear = trip.drivenKm * profile.wearPerKm * running
  local commission = revenue * math.max(balance.commission + effect('commission'), 0)
  local wage = revenue * (wageShare or 0)
  return {
    revenue = roundCents(revenue),
    energy = roundCents(energy),
    wear = roundCents(wear),
    commission = roundCents(commission),
    wage = roundCents(wage),
    net = roundCents(revenue - energy - wear - commission - wage),
    xp = driverXp * balance.fleetXpShare,
  }
end

M.rollTrip = rollTrip
M.settleTrip = settleTrip

return M
