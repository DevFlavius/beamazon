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
  vanResaleShare = 0.85,          -- a sold vehicle returns this share of its price, times the RLS vehicle market (decided 2026-10-24)

  -- The company HQ (decided 2026-10-24): bought on the map at Logistics level 20; its slots hold vans or trucks.
  hqPrice = 80000,
  hqUnlockLevel = 20,
  hqSlots = 5,                    -- example from Bernardo, still provisional; added to the personal vans (3 + 5 = 8)

  -- Everything below this line up to "A trip" is PROVISIONAL (agent, 2026-10-24 night), waiting for the brothers.
  -- The company earns its own XP from the fleet's profit and spends it, with money, on the skill tree (companyTree.lua),
  -- like the RLS business trees.
  companyXpPerDollar = 0.01,      -- 1 company XP per $100 of fleet net profit (~50 XP per van-hour)
  -- Total XP earned for each company level (shown in the app; the tree spends XP, levels never go down).
  companyLevelXp = {0, 500, 1500, 3500, 7000, 12000, 20000, 32000, 50000, 75000},

  -- The H-Series truck: needs the company and a hired driver; parked (no income, no cost) without one.
  truckPrice = 18000,             -- $ average, drawn like the van
  driversAtFounding = 1,          -- Bernardo: buying the HQ gives 1 driver; the tree adds more
  driverWageShare = 0.30,         -- the driver's pay is this share of each truck trip's revenue ("proporcional ao que rende")
  truck = {
    capacitySlots = 96,
    maxParcels = 14,
    routeKmMin = 8,
    routeKmMax = 20,
    avgSpeedKmh = 45,
    handlingMinutesPerParcel = 1.5,
    energyKwhPerKm = 0.9,         -- diesel priced as energy, to keep one cost model
    wearPerKm = 0.45,
  },

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

  -- PROVISIONAL (agent, 2026-10-24 night): condition and breakdowns, waiting for Flavio and Bernardo.
  conditionLossPerKm = 0.0015,      -- 1.0 = 100%; a van at ~40 km per trip loses ~6% per trip
  truckConditionLossPerKm = 0.001,
  breakdownBelow = 0.5,             -- below this condition, each finished trip may break down
  breakdownChanceMax = 0.25,        -- chance per trip at condition 0, scaling linearly to 0 at breakdownBelow
  breakdownRepairSeconds = 1800,    -- a broken vehicle stands still this many fleet seconds
  breakdownRepairCost = 600,        -- $ for a van; a truck pays x2
  serviceCostPerPoint = 20,         -- $ per percentage point restored (van); a truck pays x2
  minCondition = 0.0,

  -- How many hours of fleet finance history to keep (shown in the phone's Finances tab).
  historyHours = 24,

  -- PROVISIONAL (agent, 2026-10-24 night): branches, waiting for Flavio and Bernardo.
  branches = {
    dockyards = {name = 'Beamazon Dockyards', price = 60000, slots = 4, companyLevel = 3},
  },
  branchOrder = {'dockyards'},   -- display order

  -- PROVISIONAL (agent, 2026-10-24 night): per-vehicle upgrades, waiting for Flavio and Bernardo.
  vehicleUpgrades = {
    {id = 'motor', title = 'Efficient Motor', description = 'Uses 10% less energy.', maxLevel = 3, cost = {base = 1000, increment = 1000}, effect = {energy = -0.10}},
    {id = 'battery', title = 'Big Battery', description = 'Fewer charging stops: trips 5% shorter.', maxLevel = 3, cost = {base = 1500, increment = 1500}, effect = {tripTime = -0.05}},
    {id = 'cargo', title = 'Bigger Cargo Box', description = '+1 parcel per trip.', maxLevel = 2, cost = {base = 2000, increment = 2000}, effect = {parcels = 1}},
    {id = 'routing', title = 'Route Computer', description = 'Every trip pays 3% more.', maxLevel = 3, cost = {base = 2000, increment = 2000}, effect = {revenue = 0.03}},
  },
  truckUpgradeCostMultiplier = 2,
  upgradeResaleShare = 0.5,       -- share of the upgrade money a sale gives back

  -- PROVISIONAL (agent, 2026-10-24 night): contracts, waiting for Flavio and Bernardo.
  contractEverySeconds = 3600,     -- fleet seconds between new offers (when there is none)
  contractOfferSeconds = 1800,     -- an offer not accepted disappears after this
  contractTripsPerVehicle = 3,     -- trips asked = this * vehicles (at least 3)
  contractHoursMin = 2, contractHoursMax = 3,
  contractBonusPerTrip = 400,
  contractPenaltyShare = 0.2,      -- share of the bonus charged when a contract is missed
  contractXpPerDollar = 0.02,      -- company XP for a completed contract, per bonus dollar
  contractClients = {'Spearleaf Logistics', 'Belasco Pharmacy', 'Firwood Market', 'Jefferson Motors Parts', 'Hirochi Electronics', 'Gavril Hardware'},
}
