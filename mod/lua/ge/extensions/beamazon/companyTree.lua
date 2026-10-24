-- Beamazon: the company skill tree, as data. Loaded with require('beamazon/companyTree'), not as an extension.
-- Same shape as the RLS business trees (gameplay/overhaul/business/skillTrees/tuningShop.json): each node costs money
-- and company XP, has a max level, a cost that grows per level (base + increment * level) and dependencies
-- ({id, level} = that node at least at that level).
-- PROVISIONAL (agent, 2026-10-24 night): nodes, costs and effects wait for Flavio and Bernardo.
-- effect is what one level adds; beamazon_company.getEffect(name) sums it over the levels bought.

return {
  {
    id = 'drivers', title = 'Hire Drivers', group = 'People',
    description = '+1 driver slot. Each truck needs a driver to work.',
    maxLevel = 5, cost = {base = 10000, increment = 10000}, xpCost = {base = 100, increment = 100},
    effect = {driverSlots = 1},
  },
  {
    id = 'driverTraining', title = 'Driver Training', group = 'People',
    description = 'Drivers take 3 points less of each truck trip.',
    maxLevel = 3, cost = {base = 15000, increment = 15000}, xpCost = {base = 200, increment = 100},
    effect = {driverWageShare = -0.03}, dependencies = {{id = 'drivers', level = 1}},
  },
  {
    id = 'bays', title = 'Parking Bays', group = 'HQ',
    description = '+1 fleet slot at the HQ, for a van or a truck.',
    maxLevel = 5, cost = {base = 15000, increment = 15000}, xpCost = {base = 100, increment = 150},
    effect = {slots = 1},
  },
  {
    id = 'fleetDeals', title = 'Fleet Deals', group = 'HQ',
    description = 'Vans and trucks cost 5% less.',
    maxLevel = 4, cost = {base = 10000, increment = 10000}, xpCost = {base = 100, increment = 100},
    effect = {vehicleDiscount = 0.05},
  },
  {
    id = 'nightDispatcher', title = 'Night Dispatcher', group = 'HQ',
    description = '+1 hour of fleet work while you are away (offline).',
    maxLevel = 2, cost = {base = 30000, increment = 30000}, xpCost = {base = 300, increment = 300},
    effect = {offlineHours = 1}, dependencies = {{id = 'bays', level = 1}},
  },
  {
    id = 'routeSoftware', title = 'Route Software', group = 'Operations',
    description = 'Every trip pays 5% more.',
    maxLevel = 5, cost = {base = 20000, increment = 20000}, xpCost = {base = 150, increment = 150},
    effect = {revenue = 0.05},
  },
  {
    id = 'fastCharging', title = 'Fast Charging', group = 'Operations',
    description = 'Trips take 5% less time.',
    maxLevel = 4, cost = {base = 20000, increment = 20000}, xpCost = {base = 200, increment = 150},
    effect = {tripTime = -0.05}, dependencies = {{id = 'routeSoftware', level = 1}},
  },
  {
    id = 'serviceContract', title = 'Service Contract', group = 'Operations',
    description = 'Energy and wear cost 20% less.',
    maxLevel = 3, cost = {base = 15000, increment = 15000}, xpCost = {base = 150, increment = 150},
    effect = {runningCosts = -0.20},
  },
  {
    id = 'workshop', title = 'Own Workshop', group = 'Operations',
    description = 'Servicing costs 15% less.',
    maxLevel = 3, cost = {base = 20000, increment = 20000}, xpCost = {base = 150, increment = 150},
    effect = {serviceCost = -0.15}, dependencies = {{id = 'serviceContract', level = 1}},
  },
  {
    id = 'preventive', title = 'Preventive Maintenance', group = 'Operations',
    description = 'Vehicles wear 15% slower.',
    maxLevel = 3, cost = {base = 25000, increment = 25000}, xpCost = {base = 200, increment = 150},
    effect = {conditionLoss = -0.15}, dependencies = {{id = 'workshop', level = 1}},
  },
  {
    id = 'ownDispatch', title = 'Own Dispatch', group = 'Operations',
    description = 'The delivery platform takes 5 points less commission.',
    maxLevel = 3, cost = {base = 40000, increment = 40000}, xpCost = {base = 400, increment = 200},
    effect = {commission = -0.05}, dependencies = {{id = 'routeSoftware', level = 2}},
  },
  {
    id = 'reputation', title = 'Reputation', group = 'Operations',
    description = 'The company earns 25% more XP.',
    maxLevel = 4, cost = {base = 25000, increment = 25000}, xpCost = {base = 0, increment = 0},
    effect = {xpGain = 0.25}, dependencies = {{id = 'serviceContract', level = 1}},
  },
}
