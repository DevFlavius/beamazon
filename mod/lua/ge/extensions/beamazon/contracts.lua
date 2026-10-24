-- Beamazon: delivery contracts. Clients offer a bonus for completing N trips within H hours.
-- Contracts run on fleet time. State lives in the fleet save (fleet.contracts).

local M = {}

local logTag = 'beamazon'
local balance = require('beamazon/balance')

-- The contracts table inside the fleet save ({offer, active, timer, completed, failed}), or nil.
local function state()
  return beamazon_fleetManager and beamazon_fleetManager.getContractState() or nil
end

-- Accepts the current contract offer.
local function accept()
  local s = state()
  if not s then
    return false, 'noOffer'
  end
  if s.active then
    return false, 'alreadyActive'
  end
  if not s.offer then
    return false, 'noOffer'
  end
  local active = s.offer
  active.done = 0
  active.left = active.seconds
  s.active = active
  s.offer = nil
  log('I', logTag, string.format('contract accepted: %s, %d trips in %d h', active.client, active.trips, math.floor(active.seconds / 3600)))
  return true
end

-- Declines the current contract offer.
local function decline()
  local s = state()
  if not s or not s.offer then
    return false, 'noOffer'
  end
  log('I', logTag, string.format('contract declined: %s', s.offer.client))
  s.offer = nil
  return true
end

-- Generates a new contract offer if the fleet has at least 1 vehicle.
local function rollOffer()
  local s = state()
  if not s then return nil end
  local vans = beamazon_fleetManager and beamazon_fleetManager.getVans() or {}
  if #vans < 1 then return nil end
  local trips = math.max(3, (balance.contractTripsPerVehicle or 3) * #vans)
  local minH = balance.contractHoursMin or 2
  local maxH = balance.contractHoursMax or 3
  local hours = math.random(minH, maxH)
  local seconds = hours * 3600
  local bonusMult = 1 + (beamazon_company and beamazon_company.getEffect('contractBonus') or 0)
  local bonus = math.floor(trips * (balance.contractBonusPerTrip or 400) * bonusMult)
  local penalty = math.floor(bonus * (balance.contractPenaltyShare or 0.2))
  local clients = balance.contractClients or {'Spearleaf Logistics'}
  local client = clients[math.random(1, #clients)]
  local id = (s.completed or 0) + (s.failed or 0) + 1 + os.time()
  local offer = {
    id = id,
    client = client,
    trips = trips,
    seconds = seconds,
    left = balance.contractOfferSeconds or 1800,
    bonus = bonus,
    penalty = penalty,
  }
  s.offer = offer
  if beamazon_company and beamazon_company.hasAutoContracts() and not s.active then
    accept()
    local msg = string.format('Your sales team signed a contract with %s.', client)
    log('I', logTag, msg)
    if guihooks and guihooks.trigger then
      guihooks.trigger('toastrMsg', {type = 'info', title = 'Beamazon', msg = msg})
    end
  else
    local msg = string.format('New contract from %s: %d trips in %d h for $%d. Open the phone to accept.', client, trips, hours, bonus)
    log('I', logTag, msg)
    if guihooks and guihooks.trigger then
      guihooks.trigger('toastrMsg', {type = 'info', title = 'Beamazon', msg = msg})
    end
  end
  return offer
end

-- Completes the active contract, awarding the bonus, company XP and recording in finances.
local function complete()
  local s = state()
  if not s or not s.active then return end
  local active = s.active
  local bonus = active.bonus
  local client = active.client
  beamazon_adapter.addMoney(bonus, 'Beamazon: contract with ' .. client)
  if beamazon_company and beamazon_fleetManager.ownsHq() then
    beamazon_company.addXp(bonus * (balance.contractXpPerDollar or 0.02))
  end
  s.completed = (s.completed or 0) + 1
  s.active = nil
  beamazon_fleetManager.recordBonus(bonus)
  local msg = string.format('Contract completed: %s! $%d bonus earned.', client, bonus)
  log('I', logTag, msg)
  if guihooks and guihooks.trigger then
    guihooks.trigger('toastrMsg', {type = 'success', title = 'Beamazon', msg = msg})
  end
end

-- Fails the active contract, charging the penalty and recording in finances.
local function fail()
  local s = state()
  if not s or not s.active then return end
  local active = s.active
  local penalty = active.penalty
  local client = active.client
  if not beamazon_adapter.pay(penalty, 'Beamazon: missed contract with ' .. client) then
    log('W', logTag, string.format('fail: not enough money to pay penalty ($%d)', penalty))
  end
  beamazon_fleetManager.recordBonus(-penalty)
  s.failed = (s.failed or 0) + 1
  s.active = nil
  local msg = string.format('Contract missed: %s. $%d penalty charged.', client, penalty)
  log('I', logTag, msg)
  if guihooks and guihooks.trigger then
    guihooks.trigger('toastrMsg', {type = 'warning', title = 'Beamazon', msg = msg})
  end
end

-- Called by fleetManager on each fleet advance by dt fleet seconds.
local function onFleetTime(dt)
  local s = state()
  if not s or not dt or dt <= 0 then return end
  if s.active then
    s.active.left = s.active.left - dt
    if s.active.left <= 0 then
      fail()
    end
  elseif s.offer then
    s.offer.left = s.offer.left - dt
    if s.offer.left <= 0 then
      log('I', logTag, string.format('contract offer from %s expired', s.offer.client))
      s.offer = nil
    end
  else
    s.timer = (s.timer or 0) + dt
    if s.timer >= (balance.contractEverySeconds or 3600) then
      s.timer = 0
      rollOffer()
    end
  end
end

-- Called by fleetManager when any fleet vehicle finishes a trip.
local function onTrip(van)
  local s = state()
  if not s or not s.active then return end
  s.active.done = (s.active.done or 0) + 1
  if s.active.done >= s.active.trips then
    complete()
  end
end

-- Contract view for the phone app.
local function getView()
  local s = state()
  if not s then return nil end
  local view = {
    completed = s.completed or 0,
    failed = s.failed or 0,
    offer = nil,
    active = nil,
    nextOfferMinutes = nil,
  }
  if s.offer then
    view.offer = {
      id = s.offer.id,
      client = s.offer.client,
      trips = s.offer.trips,
      seconds = s.offer.seconds,
      left = s.offer.left,
      bonus = s.offer.bonus,
      penalty = s.offer.penalty,
      hours = s.offer.seconds / 3600,
      minutesLeft = math.ceil(s.offer.left / 60),
    }
  end
  if s.active then
    view.active = {
      id = s.active.id,
      client = s.active.client,
      trips = s.active.trips,
      done = s.active.done or 0,
      seconds = s.active.seconds,
      left = s.active.left,
      bonus = s.active.bonus,
      penalty = s.active.penalty,
      minutesLeft = math.ceil(s.active.left / 60),
    }
  end
  if not s.offer and not s.active then
    local remaining = (balance.contractEverySeconds or 3600) - (s.timer or 0)
    view.nextOfferMinutes = math.ceil(remaining / 60)
  end
  return view
end

M.accept = accept
M.decline = decline
M.getView = getView
M.onFleetTime = onFleetTime
M.onTrip = onTrip
M.rollOffer = rollOffer

return M
