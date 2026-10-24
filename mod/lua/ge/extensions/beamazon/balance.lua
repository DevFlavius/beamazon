-- Beamazon balance numbers, all in one place. Loaded with require('beamazon/balance'), not as an extension.
-- PLACEHOLDERS: Flavio and Bernardo decide the real values (targets in docs/plano.md, "Economia").

return {
  vanPrice = 1000,                -- $ per van

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
}
