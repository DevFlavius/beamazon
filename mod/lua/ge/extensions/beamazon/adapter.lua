-- Beamazon: the only layer that knows career internals (RLS Career Overhaul).
-- When the game or RLS updates, fix it here. Function map with paths and lines: docs/api-jogo.md.
-- Beamazon is an RLS addon: without RLS it stays loaded but does nothing.
-- The other modules never see RLS names: they get the relayed hooks onBeamazonCareerActive,
-- onBeamazonBeforeSave, onBeamazonSave and onBeamazonSimStep, plus the functions below.

local M = {}

local logTag = 'beamazon'

-- Every Beamazon money movement lands in the RLS ledger under this category.
local ledgerCategory = 'business'

-- Save files live in <savePath>/career/. Names must be lowercase (BeamNG on Linux lowercases written files).
local saveFolder = '/career/'

local function isRlsPresent()
  return extensions.isExtensionLoaded('overhaul_career_career') and true or false
end

local function isCareerActive()
  return isRlsPresent() and overhaul_career_career.isActive() and true or false
end

local function isValidAmount(amount)
  return type(amount) == 'number' and amount == amount and amount ~= math.huge and amount ~= -math.huge
end

local function ledgerReason(label)
  return {label = label or 'Beamazon', tags = {'beamazon'}, category = ledgerCategory}
end

-- Money ------------------------------------------------------------------------------------------

local function getMoney()
  if not isCareerActive() then return nil end
  return overhaul_career_economy_playerAttributes.getAttributeValue('money')
end

-- Credits (or, with a negative amount, debits) without a balance check.
-- xp (optional) is Logistics skill XP credited in the same entry.
local function addMoney(amount, label, xp)
  if not isValidAmount(amount) then
    log('E', logTag, 'addMoney: invalid amount ' .. tostring(amount))
    return false
  end
  if not isRlsPresent() then
    log('W', logTag, 'addMoney: RLS Career Overhaul is required')
    return false
  end
  if not isCareerActive() then
    log('W', logTag, 'addMoney: career is not active')
    return false
  end
  local change = {money = amount}
  if type(xp) == 'number' and xp > 0 then change['logistics-delivery'] = xp end
  overhaul_career_economy_playerAttributes.addAttributes(change, ledgerReason(label))
  log('I', logTag, string.format('addMoney: %s, %s XP (balance: %s)', tostring(amount), tostring(xp or 0), tostring(getMoney())))
  return true
end

-- Charges the player. False when the balance can't cover it (RLS cheats mode always covers it).
local function pay(amount, label)
  if not isValidAmount(amount) or amount < 0 then
    log('E', logTag, 'pay: invalid amount ' .. tostring(amount))
    return false
  end
  if not isCareerActive() then
    log('W', logTag, 'pay: career is not active (RLS Career Overhaul is required)')
    return false
  end
  local paid = overhaul_career_economy_payment.pay({money = {amount = amount, canBeNegative = false}}, ledgerReason(label))
  return paid and true or false
end

-- Phase 0 hello world. Console (GE Lua): beamazon_adapter.creditTest()
local function creditTest()
  return addMoney(1, 'Beamazon: adapter test')
end

-- Progression ------------------------------------------------------------------------------------

-- RLS looks skills up by path id; plain 'logistics' is the domain branch, with other levels and XP.
local logisticsSkillPathId = 'careerSkills-logistics'

-- The player's Logistics skill level; 0 without an active career.
local function getLogisticsLevel()
  if not isCareerActive() or not overhaul_career_progression_skills then return 0 end
  return tonumber(overhaul_career_progression_skills.getBranchLevel(logisticsSkillPathId)) or 0
end

-- Vehicle market ---------------------------------------------------------------------------------

-- The bands RLS dealers draw listing prices from, as multipliers of the base price.
local function getVehiclePriceRange()
  local calculator = isRlsPresent() and overhaul_career_market_valueCalculator
  local range = calculator and calculator.getVehicleListingPriceRange and calculator.getVehicleListingPriceRange()
  if type(range) ~= 'table' then
    range = {tailLow = 0.70, normalLow = 0.88, normalHigh = 1.12, tailHigh = 1.30}
  end
  return range
end

-- The live vehicle market index RLS applies to every vehicle purchase (1 = normal market).
local function getVehicleBuyMultiplier()
  local calculator = isCareerActive() and overhaul_career_market_valueCalculator
  local multiplier = calculator and calculator.getVehicleBuyMarketMultiplier and tonumber(calculator.getVehicleBuyMarketMultiplier())
  if not multiplier or multiplier <= 0 or multiplier ~= multiplier then return 1 end
  return multiplier
end

-- Deliveries -------------------------------------------------------------------------------------

-- RLS parcel types as plain data: {id, slots = {...}, weights = {...}, chance}.
local function getParcelTemplates()
  if not isRlsPresent() then return {} end
  local list = {}
  for _, template in ipairs(require('overhaul/lib/logistics/templates').getTemplatesByLogisticType('parcel')) do
    local chance = tonumber(template.generationChance) or 0
    local slots, weights = template.slots, template.weight
    if chance > 0 and type(slots) == 'table' and slots[1] and type(weights) == 'table' and weights[1] then
      table.insert(list, {id = template.id, slots = slots, weights = weights, chance = chance})
    end
  end
  return list
end

-- What RLS pays the player for one parcel over this distance, live economy included: money, Logistics XP.
local function getParcelReward(slots, rewardWeight, distanceMeters)
  if not isCareerActive() then return nil end
  local item = {slots = slots, data = {rewardWeight = rewardWeight}}
  local rewards = require('overhaul/lib/logistics/calculators').getParcelReward(item, distanceMeters)
  if not rewards then return nil end
  return tonumber(rewards.money), tonumber(rewards['logistics-delivery']) or 0
end

-- Save -------------------------------------------------------------------------------------------

local function readSaveFile(fileName)
  if not isCareerActive() then return nil end
  local _, savePath = overhaul_career_saveSystem.getCurrentProfile()
  if not savePath then return nil end
  return jsonReadFile(savePath .. saveFolder .. fileName)
end

-- saveContext comes from onBeamazonSave; only this file looks inside it.
local function writeSaveFile(saveContext, fileName, data)
  local path = saveContext.savePath .. saveFolder .. fileName
  require('overhaul/lib/save/ensureDir').parentOf(saveContext.writer, path)
  return overhaul_career_saveSystem.jsonWriteFileSafe(path, data, true)
end

-- RLS hooks, relayed under Beamazon names --------------------------------------------------------

local function onOverhaulActive(active)
  extensions.hook('onBeamazonCareerActive', active == true)
end

-- Runs before any RLS module writes its save files, so money added here is in the saved balance.
local function onOverhaulSaveCurrentProfileAsyncStart()
  extensions.hook('onBeamazonBeforeSave')
end

local function onOverhaulSaveCurrentProfile(savePath, _, writer)
  extensions.hook('onBeamazonSave', {
    savePath = savePath,
    writer = writer or overhaul_career_saveSystem.getSaveWriter(),
  })
end

local function onOverhaulCareerSimStep(dtSim)
  extensions.hook('onBeamazonSimStep', dtSim)
end

local function onExtensionLoaded()
  log('I', logTag, 'adapter loaded')
end

M.isRlsPresent = isRlsPresent
M.isCareerActive = isCareerActive
M.getMoney = getMoney
M.addMoney = addMoney
M.pay = pay
M.creditTest = creditTest
M.getLogisticsLevel = getLogisticsLevel
M.getVehiclePriceRange = getVehiclePriceRange
M.getVehicleBuyMultiplier = getVehicleBuyMultiplier
M.getParcelTemplates = getParcelTemplates
M.getParcelReward = getParcelReward
M.readSaveFile = readSaveFile
M.writeSaveFile = writeSaveFile
M.onOverhaulActive = onOverhaulActive
M.onOverhaulSaveCurrentProfileAsyncStart = onOverhaulSaveCurrentProfileAsyncStart
M.onOverhaulSaveCurrentProfile = onOverhaulSaveCurrentProfile
M.onOverhaulCareerSimStep = onOverhaulCareerSimStep
M.onExtensionLoaded = onExtensionLoaded

return M
