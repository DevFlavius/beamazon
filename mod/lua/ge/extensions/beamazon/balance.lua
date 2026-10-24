-- Beamazon balance numbers, all in one place. Loaded with require('beamazon/balance'), not as an extension.
-- PLACEHOLDERS: Flavio and Bernardo decide the real values (targets in docs/plano.md, "Economia").

return {
  vanPrice = 7500,                -- $ average per van (decided 2026-10-24); each offer varies like an RLS dealer listing
  -- Vans the player can own without a company, unlocked by the RLS Logistics skill level (decided 2026-10-24).
  personalVanUnlocks = {
    {level = 5, vans = 1},
    {level = 10, vans = 2},
    {level = 15, vans = 3},
  },
  vanResaleShare = 0.85,

  -- The company HQ (decided 2026-10-24): bought on the map at Logistics level 20; its slots hold vans or trucks.
  hqPrice = 80000,
  hqUnlockLevel = 20,
  hqSlots = 5,                    -- example from Bernardo, still provisional
          -- a sold van returns this share of its price, times the RLS vehicle market (decided 2026-10-24)

  -- A trip: the van loads parcels at the depot, drives the route, delivers and comes back.
  vanCapacitySlots = 24,          -- cargo slots per trip
  maxParcelsPerTrip = 6,
  routeKmMin = 3,                 -- one-way route length; each parcel pays for this distance
  routeKmMax = 8,
  avgSpeedKmh = 35,               -- covers the route out and back
  handlingMinutesPerParcel = 1,

  -- Multiplies what RLS would pay a driver for the van's parcels. Target (decided 2026-10-24): ~$5,000 net per
  -- van per real hour. At 1 the fleet measured $193 net per van-hour in game, so 25 lands near the target.
  fleetPayMultiplier = 25,

  -- Costs, per km driven (out and back) or per trip.
  energyKwhPerKm = 0.25,
  energyPricePerKwh = 0.40,       -- $
  wearPerKm = 0.15,               -- $
  commission = 0.25,              -- share of the trip revenue

  -- The fleet gives the player a very small share of the Logistics XP a driver would earn (decided: "muito pouco").
  fleetXpShare = 0.02,

  -- While the player is away, the fleet keeps working up to this many real hours.
  offlineCapHours = 2,             -- lowered from 8 (Flavio, 2026-10-24): at ~$5,000 per van-hour, 8 h paid up to $120,000 with 3 vans
}
