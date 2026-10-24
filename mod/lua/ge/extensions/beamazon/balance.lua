-- Beamazon balance numbers, all in one place. Loaded with require('beamazon/balance'), not as an extension.
-- PLACEHOLDERS: Flavio and Bernardo decide the real values (targets in docs/plano.md, "Economia").

return {
  vanPrice = 1000,                -- $ per van
  personalVanLimit = 3,           -- vans the player can own without a company (decided 2026-10-24)

  -- A trip: the van loads parcels at the depot, drives the route, delivers and comes back.
  vanCapacitySlots = 24,          -- cargo slots per trip
  maxParcelsPerTrip = 6,
  routeKmMin = 3,                 -- one-way route length; each parcel pays for this distance
  routeKmMax = 8,
  avgSpeedKmh = 35,               -- covers the route out and back
  handlingMinutesPerParcel = 1,

  -- Costs, per km driven (out and back) or per trip.
  energyKwhPerKm = 0.25,
  energyPricePerKwh = 0.40,       -- $
  wearPerKm = 0.15,               -- $
  commission = 0.25,              -- share of the trip revenue

  -- The fleet gives the player a very small share of the Logistics XP a driver would earn (decided: "muito pouco").
  fleetXpShare = 0.02,

  -- While the player is away, the fleet keeps working up to this many real hours.
  offlineCapHours = 8,
}
