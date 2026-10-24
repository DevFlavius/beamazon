-- Beamazon: the delivery company the HQ founds. Its XP and level, the skill tree (companyTree.lua) and the drivers.
-- The state lives in the fleet save (fleet.company, owned by fleetManager); this module only reads and changes it.
-- Console (GE Lua): beamazon_company.buyUpgrade('bays')   beamazon_company.hireDriver()   beamazon_company.fireDriver(id)

local M = {}

local logTag = 'beamazon'
local balance = require('beamazon/balance')
local tree = require('beamazon/companyTree')

local nodesById = {}
for _, node in ipairs(tree) do nodesById[node.id] = node end

-- Names for hired drivers, drawn in order and then numbered.
local driverNames = {'Alex', 'Sam', 'Jordan', 'Casey', 'Riley', 'Morgan', 'Taylor', 'Jamie', 'Drew', 'Robin', 'Avery', 'Quinn'}

-- The company table inside the fleet save, or nil when there is no career or no HQ.
local function company()
  if not beamazon_fleetManager or not beamazon_fleetManager.ownsHq() then return nil end
  local c = beamazon_fleetManager.getCompany()
  c.xp = tonumber(c.xp) or 0
  c.xpEarned = tonumber(c.xpEarned) or 0
  if type(c.upgrades) ~= 'table' then c.upgrades = {} end
  if type(c.drivers) ~= 'table' then c.drivers = {} end
  c.nextDriverId = tonumber(c.nextDriverId) or 1
  return c
end

local function getUpgradeLevel(id)
  local c = company()
  return c and tonumber(c.upgrades[id]) or 0
end

-- The sum of one effect over every level bought, 0 without a company.
local function getEffect(name)
  local c, total = company(), 0
  if not c then return 0 end
  for id, level in pairs(c.upgrades) do
    local node = nodesById[id]
    if node and node.effect[name] then total = total + node.effect[name] * level end
  end
  return total
end

-- {level, xpEarned, current, next}: the level from the total XP ever earned; next is nil at the top.
local function getLevel()
  local c = company()
  local earned = c and c.xpEarned or 0
  local level = 1
  for index, needed in ipairs(balance.companyLevelXp) do
    if earned >= needed then level = index end
  end
  return {level = level, xpEarned = earned, current = balance.companyLevelXp[level], next = balance.companyLevelXp[level + 1]}
end

-- Called by fleetManager for each trip's net profit.
local function addXpFromProfit(net)
  local c = company()
  if not c or net <= 0 then return end
  local before = getLevel().level
  local gained = net * balance.companyXpPerDollar * (1 + getEffect('xpGain'))
  c.xp = c.xp + gained
  c.xpEarned = c.xpEarned + gained
  local after = getLevel().level
  if after > before then
    log('I', logTag, 'company reached level ' .. after)
    guihooks.trigger('toastrMsg', {type = 'success', title = 'Beamazon', msg = 'Your company reached level ' .. after .. '.'})
  end
end

local function costAt(cost, level)
  return math.floor(cost.base + cost.increment * level + 0.5)
end

-- Whether a node can be bought now; false and the reason when not:
-- 'noCompany', 'unknown', 'maxLevel', 'locked', 'notEnoughXp' (money is checked when paying).
local function canBuy(id)
  local c = company()
  if not c then return false, 'noCompany' end
  local node = nodesById[id]
  if not node then return false, 'unknown' end
  local level = getUpgradeLevel(id)
  if level >= node.maxLevel then return false, 'maxLevel' end
  for _, dep in ipairs(node.dependencies or {}) do
    if getUpgradeLevel(dep.id) < dep.level then return false, 'locked' end
  end
  if c.xp < costAt(node.xpCost, level) then return false, 'notEnoughXp' end
  return true
end

-- True, or false and the reason (canBuy's, or 'notEnoughMoney').
local function buyUpgrade(id)
  local ok, reason = canBuy(id)
  if not ok then
    log('W', logTag, 'buyUpgrade ' .. tostring(id) .. ': ' .. reason)
    return false, reason
  end
  local c, node, level = company(), nodesById[id], getUpgradeLevel(id)
  local price, xpCost = costAt(node.cost, level), costAt(node.xpCost, level)
  if not beamazon_adapter.pay(price, 'Beamazon: ' .. node.title .. ' ' .. (level + 1)) then
    log('W', logTag, string.format('buyUpgrade %s: not enough money ($%d)', id, price))
    return false, 'notEnoughMoney'
  end
  c.xp = c.xp - xpCost
  c.upgrades[id] = level + 1
  log('I', logTag, string.format('buyUpgrade: %s level %d for $%d and %d XP', node.title, level + 1, price, xpCost))
  return true
end

-- The tree for the app: every node with its level, next costs and why it can't be bought.
local function getTreeView()
  local view = {}
  for _, node in ipairs(tree) do
    local level = getUpgradeLevel(node.id)
    local ok, reason = canBuy(node.id)
    local requires = {}
    for _, dep in ipairs(node.dependencies or {}) do
      table.insert(requires, {title = nodesById[dep.id].title, level = dep.level})
    end
    table.insert(view, {
      id = node.id, title = node.title, group = node.group, description = node.description,
      level = level, maxLevel = node.maxLevel,
      price = level < node.maxLevel and costAt(node.cost, level) or nil,
      xpCost = level < node.maxLevel and costAt(node.xpCost, level) or nil,
      canBuy = ok, reason = not ok and reason or nil, requires = requires,
    })
  end
  return view
end

-- Drivers ----------------------------------------------------------------------------------------

local function getDriverSlots()
  if not company() then return 0 end
  return balance.driversAtFounding + getEffect('driverSlots')
end

local function getDrivers()
  local c = company()
  return c and c.drivers or {}
end

-- The share of each truck trip's revenue that goes to its driver.
local function getDriverWageShare()
  return math.max(balance.driverWageShare + getEffect('driverWageShare'), 0)
end

-- True and the driver, or false and the reason: 'noCompany' or 'driverSlots'.
local function hireDriver()
  local c = company()
  if not c then return false, 'noCompany' end
  if #c.drivers >= getDriverSlots() then
    log('W', logTag, string.format('hireDriver: all %d driver slot(s) are taken', getDriverSlots()))
    return false, 'driverSlots'
  end
  local id = c.nextDriverId
  local name = driverNames[id] or ('Driver ' .. id)
  local driver = {id = id, name = name, hiredAt = os.time(), trips = 0, earned = 0}
  c.nextDriverId = id + 1
  table.insert(c.drivers, driver)
  log('I', logTag, string.format('hireDriver: %s hired (%d/%d)', name, #c.drivers, getDriverSlots()))
  return true, driver
end

-- True, or false and the reason: 'noCompany' or 'noDriver'. The truck the driver had stops after its trip is lost.
local function fireDriver(id)
  local c = company()
  if not c then return false, 'noCompany' end
  for index, driver in ipairs(c.drivers) do
    if driver.id == id then
      table.remove(c.drivers, index)
      log('I', logTag, 'fireDriver: ' .. driver.name .. ' left the company')
      return true
    end
  end
  return false, 'noDriver'
end

-- Trucks work in id order while there are drivers: the first #drivers trucks have one.
-- Returns the driver of this truck, or nil when it is parked.
local function getTruckDriver(truck)
  local drivers = getDrivers()
  local index = 0
  for _, vehicle in ipairs(beamazon_fleetManager.getVans()) do
    if vehicle.kind == 'truck' then
      index = index + 1
      if vehicle == truck then return drivers[index] end
    end
  end
  return nil
end

-- Called by fleetManager when a truck finishes a trip, to keep the driver's books.
local function recordDriverTrip(driver, wage)
  driver.trips = (tonumber(driver.trips) or 0) + 1
  driver.earned = (tonumber(driver.earned) or 0) + wage
end

M.getUpgradeLevel = getUpgradeLevel
M.getEffect = getEffect
M.getLevel = getLevel
M.addXpFromProfit = addXpFromProfit
M.canBuy = canBuy
M.buyUpgrade = buyUpgrade
M.getTreeView = getTreeView
M.getDriverSlots = getDriverSlots
M.getDrivers = getDrivers
M.getDriverWageShare = getDriverWageShare
M.hireDriver = hireDriver
M.fireDriver = fireDriver
M.getTruckDriver = getTruckDriver
M.recordDriverTrip = recordDriverTrip

return M
