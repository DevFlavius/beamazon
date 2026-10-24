-- Beamazon: the only layer that knows career internals (RLS Career Overhaul).
-- When the game or RLS updates, fix it here. Function map with paths and lines: docs/api-jogo.md.
-- Beamazon is an RLS addon: without RLS it stays loaded but does nothing.
-- The other modules never see RLS names: they get the relayed hooks onBeamazonCareerActive,
-- onBeamazonSave and onBeamazonSimStep, plus the functions below.

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
local function addMoney(amount, label)
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
  overhaul_career_economy_playerAttributes.addAttributes({money = amount}, ledgerReason(label))
  log('I', logTag, string.format('addMoney: %s (balance: %s)', tostring(amount), tostring(getMoney())))
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

-- What RLS pays the player for one parcel over this distance, live economy included.
local function getParcelReward(slots, rewardWeight, distanceMeters)
  if not isCareerActive() then return nil end
  local item = {slots = slots, data = {rewardWeight = rewardWeight}}
  local rewards = require('overhaul/lib/logistics/calculators').getParcelReward(item, distanceMeters)
  return rewards and tonumber(rewards.money) or nil
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
M.getParcelTemplates = getParcelTemplates
M.getParcelReward = getParcelReward
M.readSaveFile = readSaveFile
M.writeSaveFile = writeSaveFile
M.onOverhaulActive = onOverhaulActive
M.onOverhaulSaveCurrentProfile = onOverhaulSaveCurrentProfile
M.onOverhaulCareerSimStep = onOverhaulCareerSimStep
M.onExtensionLoaded = onExtensionLoaded

return M
