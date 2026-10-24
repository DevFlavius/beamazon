-- MVP checks against a fake RLS (run from tests/: npm install && npm test).
-- Lua 5.3 (fengari) instead of LuaJIT, and the RLS pay formula is a copy: this checks logic, not balance.
-- It never replaces the in-game test.
local MOD = MOD_DIR .. '/lua/ge/extensions/'
package.path = MOD .. '?.lua;' .. package.path
math.randomseed(42)
local now = 1000000
os.time = function() return now end
local quiet = false
function log(level, tag, msg) if not quiet or level ~= 'I' then print(level, tag, msg) end end
function deepcopy(t) if type(t) ~= 'table' then return t end local r = {} for k, v in pairs(t) do r[k] = deepcopy(v) end return r end

-- mini extension system
local loaded, order = {}, {}
extensions = {}
function extensions.isExtensionLoaded(n) return _G[n] ~= nil end
function extensions.load(n)
  local path = n:gsub('^beamazon_', 'beamazon/')
  local m = dofile(MOD .. path .. '.lua'); _G[n] = m; loaded[n] = m; table.insert(order, n)
  if m.onExtensionLoaded then m.onExtensionLoaded() end
end
function extensions.hook(h, ...) for _, n in ipairs(order) do local m = loaded[n]; if m and m[h] then m[h](...) end end end
function setExtensionUnloadMode() end

-- fake disk
local disk = {}
function jsonReadFile(p) return deepcopy(disk[p]) end

-- fake RLS
local money, xp, active, ledger = 0, 0, true, {}
local logisticsLevel, marketIndex = 15, 1
local level = 'rls_west_coast'
function getCurrentLevelIdentifier() return level end
local function installRls()
  overhaul_career_career = {isActive = function() return active end}
  overhaul_career_economy_playerAttributes = {
    getAttributeValue = function() return money end,
    addAttributes = function(c, r)
      money = money + c.money; xp = xp + (c['logistics-delivery'] or 0)
      table.insert(ledger, {c.money, r.label, r.category, c['logistics-delivery']}) end,
  }
  overhaul_career_economy_payment = {pay = function(price, r)
    if price.money.amount > money then return false end
    overhaul_career_economy_playerAttributes.addAttributes({money = -price.money.amount}, r); return true end}
  overhaul_career_progression_skills = {getBranchLevel = function(id)
    -- Like RLS: level, progress, XP needed for next, previous and next thresholds.
    if id ~= 'careerSkills-logistics' then return nil end return logisticsLevel, 0.5, 100, 1400, 2000 end}
  overhaul_career_market_valueCalculator = {
    getVehicleListingPriceRange = function() return {tailLow = 0.70, normalLow = 0.88, normalHigh = 1.12, tailHigh = 1.30} end,
    getVehicleBuyMarketMultiplier = function() return marketIndex end,
  }
  overhaul_career_saveSystem = {
    getCurrentProfile = function() return 'prof', '/saves/prof/autosave1' end,
    getSaveWriter = function() return {exists = function() return true end, mkdir = function() end} end,
    jsonWriteFileSafe = function(p, d) disk[p] = deepcopy(d); return true end,
  }
  local pay = {[16]=37.5,[32]=75,[64]=150,[128]=300}; local refw = {[16]=1.6,[32]=4.2,[64]=8.3,[128]=144.3}
  local function tier(s) return s<=16 and 16 or s<=32 and 32 or s<=64 and 64 or 128 end
  local function wr(w) if w<=10 then return w^0.9 end return 10^0.9+4.7*math.log(1+(w-10)/10) end
  package.preload['overhaul/lib/logistics/calculators'] = function() return {getParcelReward = function(item, m)
    local s, w, km = item.slots, item.data.rewardWeight, m/1000
    local sr = 3^(0.30+math.sqrt(s)/100); local mn = 10+2*math.sqrt(s); local h = s*1.15
    local b = math.max(mn, h+km*sr*(5+wr(w))*1.075); local t = tier(s)
    local ref = math.max(mn, h+4*1.609344*sr*(5+wr(refw[t]))*1.075)
    return {money = b*pay[t]/ref, ['logistics-delivery'] = 10} end} end
  package.preload['overhaul/lib/logistics/templates'] = function() return {getTemplatesByLogisticType = function() return {
    {id='smallPostParcel', slots={1,2,3,4}, weight={1,2,3,4,5}, generationChance=0.3},
    {id='mediumPostParcel', slots={6,8,10,12}, weight={8,10,12}, generationChance=0.25},
    {id='bigPostParcel', slots={16}, weight={10,15,20}, generationChance=0.2},
    {id='specialPostParcel', slots={4,6,8}, weight={4,6,8,10}, generationChance=0.02},
  } end} end
  package.preload['overhaul/lib/save/ensureDir'] = function() return {parentOf = function(w, p) assert(w.exists and p:match('/career/beamazon.json$'), 'bad path ' .. p) end} end
  extensions.load('overhaul_career_career_dummy')
end
local function check(c, msg) if not c then error('FAIL: ' .. msg) end print('ok  ' .. msg) end

-- 1. without RLS
dofile(MOD_DIR .. '/scripts/beamazon/modScript.lua')
check(beamazon_fleetManager.buyVan() == false, 'no RLS: buyVan refuses')
beamazon_fleetSim.onBeamazonSimStep(5)
check(beamazon_adapter.addMoney(1) == false, 'no RLS: addMoney refuses')
check(beamazon_phoneApp.getData().active == false, 'no RLS: phone shows career not active')

-- 2. with RLS
_G.overhaul_career_career_dummy = nil
overhaul_career_career = {isActive = function() return active end}
extensions.load = (function(orig) return function(n) if n == 'overhaul_career_career_dummy' then return end orig(n) end end)(extensions.load)
installRls()
-- Stands in for RLS playerAttributes. First in hook order: the worst case, it saves the balance before Beamazon's save hook.
loaded.rls_attributes = {onOverhaulSaveCurrentProfile = function(p) disk[p .. '/career/playerattributes.json'] = {money = money} end}
table.insert(order, 1, 'rls_attributes')
local function save(path)
  extensions.hook('onOverhaulSaveCurrentProfileAsyncStart')
  extensions.hook('onOverhaulSaveCurrentProfile', path, nil, overhaul_career_saveSystem.getSaveWriter())
end
local function totalTrips() local n = 0 for _, v in ipairs(beamazon_fleetManager.getVans()) do n = n + v.trips end return n end
extensions.hook('onOverhaulActive', true, false)
do
  local balance = require('beamazon/balance')
  local trip = beamazon_fleetEconomy.rollTrip()
  local function revenueAt(k) balance.fleetPayMultiplier = k return beamazon_fleetEconomy.settleTrip(trip).revenue end
  local one, scaled = revenueAt(1), revenueAt(25)
  check(math.abs(scaled - one * 25) <= 0.25 and scaled > 0, string.format('pay multiplier: $%.2f x25 = $%.2f', one, scaled))
end
local fm = beamazon_fleetManager
local function limitAt(level) logisticsLevel = level return fm.getVanLimit() end
check(limitAt(0) == 0 and limitAt(4) == 0 and limitAt(5) == 1 and limitAt(9) == 1 and limitAt(10) == 2 and limitAt(15) == 3 and limitAt(40) == 3,
  'van limit by Logistics level: 0 below 5, then 1, 2, 3 at 5, 10, 15')
logisticsLevel = 4
check(fm.getNextVanUnlock().level == 5 and fm.buyVan() == false, 'level 4: no van, next unlock at level 5')
logisticsLevel = 12
check(fm.getNextVanUnlock().level == 15, 'level 12: next unlock at level 15')
logisticsLevel = 15
check(fm.getNextVanUnlock() == nil, 'level 15: no personal unlock left')
local price = fm.getVanPrice()
check(price >= 7500 * 0.70 and price <= 7500 * 1.30 and price == math.floor(price), 'van price near $7500: $' .. price)
marketIndex = 1.2
check(math.abs(fm.getVanPrice() - price * 1.2) <= 1, 'van price follows the RLS vehicle market')
marketIndex = 1
money = price + 500
check(fm.buyVan() == true and money == 500, 'buyVan charges the offer price $' .. price)
check(fm.buyVan() == false and money == 500, 'buyVan refuses without money')
money = 1000000
check(beamazon_fleetManager.buyVan() == true, 'second van')
local base = money
quiet = true
for _ = 1, 3600 do extensions.hook('onOverhaulCareerSimStep', 1) end
quiet = false
local vans = beamazon_fleetManager.getVans()
check(vans[1].trips > 0 and vans[2].trips > 0, string.format('1 h of sim: trips %d and %d', vans[1].trips, vans[2].trips))
-- A trip ends right before the save, so its profit is still waiting for the next payout.
local paidBefore = money
vans[1].tripElapsed = vans[1].trip.durationS - 1
extensions.hook('onOverhaulCareerSimStep', 2)
check(money == paidBefore, 'a finished trip waits for the payout')
save('/saves/prof/autosave1')
check(math.abs(money - base - (vans[1].net + vans[2].net)) < 0.01, 'after a save, money matches the vans net')
check(disk['/saves/prof/autosave1/career/playerattributes.json'].money == money, 'saved balance includes every trip')
check(ledger[#ledger][3] == 'business', 'ledger category business')
check(xp >= 1 and xp == math.floor(xp) and xp <= totalTrips() * 6 * 10 * 0.02, 'fleet gives a little whole-point Logistics XP: ' .. xp)
beamazon_fleetManager.status()
local totals = beamazon_fleetManager.getTotals()
local perHour = beamazon_fleetManager.getNetPerVanHour()
check(math.abs(totals.vanSeconds - 2 * 3602) < 0.01, 'van time: 2 vans x 3602 s, got ' .. totals.vanSeconds)
check(perHour and math.abs(perHour - totals.timedNet / (totals.vanSeconds / 3600)) < 0.01 and perHour > 0, 'net per van-hour: $' .. tostring(perHour))

-- 3. save and reload
check(disk['/saves/prof/autosave1/career/beamazon.json'].savedAt == now, 'saved to <savePath>/career/beamazon.json with savedAt')
local before = deepcopy(vans)
local priceBeforeReload = beamazon_fleetManager.getVanPrice()
active = false; extensions.hook('onOverhaulActive', false)
check(#beamazon_fleetManager.getVans() == 0, 'career off: fleet cleared')
beamazon_fleetSim.onBeamazonSimStep(10)
active = true; extensions.hook('onOverhaulActive', true, false)
local after = beamazon_fleetManager.getVans()
check(beamazon_fleetManager.getVanPrice() == priceBeforeReload, 'reload keeps the van offer')
check(#after == 2 and after[1].trips == before[1].trips and after[1].tripElapsed == before[1].tripElapsed, 'reload keeps vans and trip progress')
check(beamazon_fleetManager.buyVan() and beamazon_fleetManager.getVans()[3].id == 3, 'ids continue after reload')

-- 4. speed and catch-up
check(beamazon_fleetSim.setSpeed(0) == false and beamazon_fleetSim.setSpeed(60), 'setSpeed validates')
local t0, rows0 = after[1].trips, #ledger
quiet = true; for _ = 1, 60 do extensions.hook('onOverhaulCareerSimStep', 1) end; quiet = false
check(#ledger - rows0 == 1, 'payouts batched: 1 ledger row for a game minute of trips')
check(after[1].trips - t0 >= 1, 'x60: 1 game minute = 1 fleet hour, trips ' .. (after[1].trips - t0))


-- 5. offline progress
save('/saves/prof/autosave1')
active = false; extensions.hook('onOverhaulActive', false)
active = true; extensions.hook('onOverhaulActive', true, false)
local t1 = totalTrips()
quiet = true; for _ = 1, 60 do extensions.hook('onOverhaulCareerSimStep', 1) end; quiet = false
check(totalTrips() - t1 <= 3, 'loading a career resets the x60 speed-up')
local function awayFor(hours)
  save('/saves/prof/autosave1')
  active = false; extensions.hook('onOverhaulActive', false)
  now = now + hours * 3600
  active = true; extensions.hook('onOverhaulActive', true, false)
  local trips0, rows = totalTrips(), #ledger
  quiet = true; extensions.hook('onOverhaulCareerSimStep', 2); quiet = false
  return totalTrips() - trips0, #ledger - rows
end
local gained, rows = awayFor(2)
check(gained >= 6 and gained <= 30, '2 h away with 3 vans: ' .. gained .. ' trips')
check(rows == 1 and ledger[#ledger][2]:find('offline') ~= nil, 'offline profit is one ledger entry: ' .. ledger[#ledger][2])
local again = totalTrips(); extensions.hook('onOverhaulCareerSimStep', 2)
check(totalTrips() - again <= 3, 'offline time is used once')
gained = awayFor(48)
check(gained >= 6 and gained <= 30, '48 h away is capped at 2 h: ' .. gained .. ' trips')
gained = awayFor(-5)
check(gained <= 3, 'clock moved back: no offline progress')

-- 6. phone app
local d = beamazon_phoneApp.getData()
check(d.active and #d.vans == 3 and d.vanPrice == beamazon_fleetManager.getVanPrice() and d.logisticsLevel == 15 and d.totals.trips > 0 and d.netPerVanHour > 0, 'phone data: vans, price, totals and rate')
check(d.vans[1].progress >= 0 and d.vans[1].progress <= 1 and type(d.vans[1].name) == 'string', 'phone data: van rows')
check(d.vanLimit == 3, 'phone data: van limit')
money = 5000
local ok, why = beamazon_fleetManager.buyVan()
check(ok == false and why == 'vanLimit' and money == 5000 and #beamazon_fleetManager.getVans() == 3, 'personal limit: a 4th van is refused and not charged')
local r = beamazon_phoneApp.buyVan()
check(r.ok == false and r.reason == 'vanLimit' and #r.data.vans == 3, 'phone buy at the limit: reason, no van')
local balance = require('beamazon/balance')
table.insert(balance.personalVanUnlocks, {level = 15, vans = 10})
money = 0
r = beamazon_phoneApp.buyVan()
check(r.ok == false and r.reason == 'notEnoughMoney' and #r.data.vans == 3, 'phone buy without money: reason, no van')
local p = beamazon_fleetManager.getVanPrice()
money = p
r = beamazon_phoneApp.buyVan()
check(r.ok and #r.data.vans == 4 and money == 0, 'phone buy adds a van and charges $' .. p)
-- Offers drawn like an RLS dealer listing: almost all within 12% of the average, a few in the tails.
balance.personalVanUnlocks[#balance.personalVanUnlocks].vans = 1000
money = 1e9
local low, high, inBand, sum, n = math.huge, 0, 0, 0, 300
quiet = true
for _ = 1, n do
  local before = money; beamazon_fleetManager.buyVan(); local paid = before - money
  low, high, sum = math.min(low, paid), math.max(high, paid), sum + paid
  if paid >= 7500 * 0.88 - 1 and paid <= 7500 * 1.12 + 1 then inBand = inBand + 1 end
end
quiet = false
check(low >= 7500 * 0.70 and high <= 7500 * 1.30 and inBand >= n * 0.95 and math.abs(sum / n - 7500) < 300,
  string.format('%d offers: $%d to $%d, average $%d, %d within 12%%', n, low, high, math.floor(sum / n), inBand))
table.remove(balance.personalVanUnlocks)
-- Selling: 85% of the price paid, times the RLS vehicle market.
local fm = beamazon_fleetManager
local sold = fm.getVans()[#fm.getVans()]
check(sold.pricePaid and fm.getSellValue(sold) == math.floor(sold.pricePaid * 0.85 + 0.5), 'sell value: 85% of $' .. tostring(sold.pricePaid))
marketIndex = 1.1
check(fm.getSellValue(sold) == math.floor(sold.pricePaid * 0.85 * 1.1 + 0.5), 'sell value follows the RLS vehicle market')
marketIndex = 1
local count, before, value = #fm.getVans(), money, fm.getSellValue(sold)
r = beamazon_phoneApp.sellVan(sold.id)
check(r.ok and r.value == value and money == before + value and #r.data.vans == count - 1, 'phone sell: van gone, $' .. value .. ' credited')
check(ledger[#ledger][2] == 'Beamazon: sold ' .. sold.name and ledger[#ledger][3] == 'business', 'sale is one business ledger entry')
r = beamazon_phoneApp.sellVan(sold.id)
check(r.ok == false and r.reason == 'noVan' and money == before + value, 'selling the same van twice is refused')
local first = fm.getVans()[1]
first.pricePaid = nil
first.condition = 1
check(fm.getSellValue(first) == math.floor(7500 * 0.85 + 0.5), 'a van saved before prices were stored sells at the average')
local kept = fm.getVans()[2]
save('/saves/prof/autosave1')
active = false; extensions.hook('onOverhaulActive', false)
active = true; extensions.hook('onOverhaulActive', true, false)
check(fm.getVans()[2].pricePaid == kept.pricePaid and fm.getSellValue(fm.getVans()[2]) == fm.getSellValue(kept), 'price paid survives the save')

-- 7. company HQ
local V = {}
V.__index = V
V.__add = function(a, b) return setmetatable({x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}, V) end
function vec3(x, y, z) return setmetatable({x = x, y = y, z = z}, V) end
-- a yaw-only quaternion: enough for the HQ desk
local Q = {}
Q.__index = Q
Q.__mul = function(q, v)
  local c, si = math.cos(q.yaw), math.sin(q.yaw)
  return vec3(v.x * c - v.y * si, v.x * si + v.y * c, v.z)
end
function Q:toTorqueQuat() return {x = 0, y = 0, z = 1, w = self.yaw} end
function quatFromEuler(x, y, z) return setmetatable({yaw = z}, Q) end
local objects = {}
local function sceneObject(class)
  local o = {class = class}
  function o:setPosition(p) self.pos = p end
  function o:setScale(v) self.scale = v end
  function o:setField(name, index, value) self[name] = value end
  function o:registerObject(name) self.name = name; objects[name] = self end
  return o
end
function createObject(class) return sceneObject(class) end
scenetree = {findObject = function(name) return objects[name] end, MissionGroup = {addObject = function() end}}
local toasts = {}
guihooks = {trigger = function(name, data) if name == 'toastrMsg' then table.insert(toasts, data) end end}
local phoneOpened = false
overhaul_shell_gameMode = {openPhone = function() phoneOpened = true return true end}
local hq = beamazon_hq
local elements = {}
hq.onGetRawPoiListForLevel('west_coast_usa', elements)
check(#elements == 0, 'HQ: no marker on a level without a spot')
hq.onGetRawPoiListForLevel('rls_west_coast', elements)
local elem = elements[1]
check(elem and elem.data.type == 'beamazonHq' and objects.beamazonHqWestCoast_area.class == 'BeamNGGameplayArea'
  and objects.beamazonHqWestCoast_icon.class == 'BeamNGPointOfInterest' and elem.markerInfo.walkingMarker.doors[1][2] == 'beamazonHqWestCoast_icon',
  'HQ: marker and its area and icon objects on rls_west_coast')
check(math.abs(objects.beamazonHqWestCoast_icon.pos.z - (122.440 + 1.2)) < 0.001, 'HQ: icon above the spot')
local desk, laptop = objects.beamazonHqWestCoast_desk, objects.beamazonHqWestCoast_laptop
check(desk and desk.class == 'TSStatic' and desk.shapeName:find('s_office_desk') and desk.canSave == false and desk.rotation,
  'HQ: office desk next to the spot, not saved in the level')
check(laptop and laptop.shapeName:find('s_laptop_ON') and math.abs(laptop.pos.z - (desk.pos.z + 0.78)) < 0.001, 'HQ: laptop on the desk')
local again = {}
hq.onGetRawPoiListForLevel('rls_west_coast', again)
check(#again == 1, 'HQ: a second POI build reuses the objects')
local function card() local list = {} hq.onActivityAcceptGatherData({elem.data}, list) return list[1] end
logisticsLevel = 19; money = 1e6
local c = card()
check(c.disabled and c.disableReason:find('20') and c.props[1].valueLabel == '$80,000', 'HQ card: price, locked below Logistics level 20')
logisticsLevel = 20; money = 1000
check(card().disableReason == 'Not enough money', 'HQ card: locked without money')
local limitBefore = beamazon_fleetManager.getVanLimit()
money = 100000
c = card()
check(not c.disabled and c.buttonLabel == 'Buy the company', 'HQ card: open at level 20 with money')
c.buttonFun()
check(beamazon_fleetManager.ownsHq() and money == 20000 and toasts[#toasts].type == 'success', 'HQ bought: $80,000 charged')
check(ledger[#ledger][2] == 'Beamazon: company HQ' and ledger[#ledger][3] == 'business', 'HQ purchase is a business ledger entry')
check(beamazon_fleetManager.getVanLimit() == limitBefore + 5, 'HQ: the HQ adds 5 slots to the personal vans (' .. beamazon_fleetManager.getVanLimit() .. ')')
local ok, why = beamazon_fleetManager.buyHq()
check(ok == false and why == 'alreadyOwned' and money == 20000, 'HQ: a second purchase is refused')
c = card()
check(c.buttonLabel == 'Open the phone' and not c.disabled, 'HQ card once owned')
c.buttonFun()
check(phoneOpened, 'HQ card opens the phone')
check(beamazon_phoneApp.getData().company.hq == true, 'phone shows the company')
local navTarget
freeroam_bigMapMode = {setNavFocus = function(pos) navTarget = pos end}
local playerVehicle = nil
function getPlayerVehicle() return playerVehicle end
check(beamazon_phoneApp.routeToHq().ok == false and navTarget == nil, 'HQ route: refused on foot')
playerVehicle = {}
local route = beamazon_phoneApp.routeToHq()
check(route.ok and navTarget and math.abs(navTarget.x + 126.627) < 0.001 and route.data.company.hqOnThisMap, 'HQ route: GPS set to the HQ')
level = 'italy'
check(beamazon_phoneApp.getData().company.hqOnThisMap == false and beamazon_phoneApp.routeToHq().ok == false, 'HQ route: none on a map without an HQ')
level = 'rls_west_coast'
save('/saves/prof/autosave1')
active = false; extensions.hook('onOverhaulActive', false)
check(beamazon_fleetManager.ownsHq() == false, 'career off: no company')
active = true; extensions.hook('onOverhaulActive', true, false)
check(beamazon_fleetManager.ownsHq() and disk['/saves/prof/autosave1/career/beamazon.json'].company.hq == true, 'HQ survives the save')
logisticsLevel = 15

-- 8. company: XP, skill tree, trucks and drivers
local company = beamazon_company
-- Section 6 left hundreds of vans from the price draw; keep 2.
do local vs = beamazon_fleetManager.getVans() for i = #vs, 3, -1 do table.remove(vs, i) end end
local function run(minutes) quiet = true; for _ = 1, minutes * 60 do extensions.hook('onOverhaulCareerSimStep', 1) end; quiet = false end
check(company.getLevel().level == 1 and company.getDriverSlots() == 1 and #company.getDrivers() == 0, 'company starts at level 1 with 1 driver slot')
beamazon_fleetSim.setSpeed(60)
local xp0, net0 = beamazon_fleetManager.getCompany().xpEarned or 0, beamazon_fleetManager.getTotals().net
run(1)
local xpGain, netGain = beamazon_fleetManager.getCompany().xpEarned - xp0, beamazon_fleetManager.getTotals().net - net0
check(netGain > 0 and math.abs(xpGain - netGain * 0.01) < 0.01, string.format('company XP: %.1f from $%.0f of profit', xpGain, netGain))
local ok8, why8 = company.buyUpgrade('fastCharging')
check(not ok8 and why8 == 'locked', 'upgrade behind a dependency is locked')
beamazon_fleetManager.getCompany().xp = 0
ok8, why8 = company.buyUpgrade('bays')
check(not ok8 and why8 == 'notEnoughXp', 'upgrade needs company XP')
beamazon_fleetManager.getCompany().xp = 100000
money = 1000
ok8, why8 = company.buyUpgrade('bays')
check(not ok8 and why8 == 'notEnoughMoney' and (company.getUpgradeLevel('bays') == 0), 'upgrade needs money')
money = 1e6
local limit0 = beamazon_fleetManager.getVanLimit()
check(company.buyUpgrade('bays') and money == 1e6 - 15000 and beamazon_fleetManager.getCompany().xp == 100000 - 100, 'Parking Bays 1: $15,000 and 100 XP')
check(beamazon_fleetManager.getVanLimit() == limit0 + 1, 'Parking Bays adds a fleet slot')
check(company.buyUpgrade('bays') and money == 1e6 - 15000 - 30000, 'the next level costs more ($30,000)')
for _ = 1, 3 do company.buyUpgrade('bays') end
ok8, why8 = company.buyUpgrade('bays')
check(not ok8 and why8 == 'maxLevel' and company.getUpgradeLevel('bays') == 5, 'Parking Bays stops at level 5')
local tree = company.getTreeView()
check(#tree >= 10 and tree[1].id == 'drivers' and tree[1].canBuy and tree[3].level == 5 and tree[3].reason == 'maxLevel', 'tree view for the app')

-- effects
local trip = beamazon_fleetEconomy.rollTrip()
math.randomseed(7); local base = beamazon_fleetEconomy.settleTrip(trip)
company.buyUpgrade('routeSoftware'); company.buyUpgrade('routeSoftware')
math.randomseed(7); local better = beamazon_fleetEconomy.settleTrip(trip)
check(math.abs(better.revenue - base.revenue * 1.10) < 0.05, 'Route Software 2: trips pay 10% more')
company.buyUpgrade('ownDispatch')
math.randomseed(7); local cheaper = beamazon_fleetEconomy.settleTrip(trip)
check(math.abs(cheaper.commission - cheaper.revenue * 0.20) < 0.05, 'Own Dispatch: commission 25% -> 20%')
company.buyUpgrade('serviceContract')
math.randomseed(7); local served = beamazon_fleetEconomy.settleTrip(trip)
check(math.abs(served.energy - cheaper.energy * 0.8) < 0.02 and math.abs(served.wear - cheaper.wear * 0.8) < 0.02, 'Service Contract: energy and wear -20%')
local d0 = beamazon_fleetEconomy.rollTrip().durationS
company.buyUpgrade('fastCharging')
check(company.getEffect('tripTime') == -0.05, 'Fast Charging: trips 5% shorter')
local vanPrice0 = beamazon_fleetManager.getVanPrice()
company.buyUpgrade('fleetDeals')
check(math.abs(beamazon_fleetManager.getVanPrice() - vanPrice0 * 0.95) <= 1, 'Fleet Deals: vans 5% cheaper')

-- trucks and drivers
local vans0 = #beamazon_fleetManager.getVans()
local truckPrice = beamazon_fleetManager.getTruckPrice()
check(truckPrice > 12000 and truckPrice < 24000, 'truck price near $18,000 less Fleet Deals: $' .. truckPrice)
money = 1e6
check(beamazon_fleetManager.buyTruck() and money == 1e6 - truckPrice, 'buy a truck')
local truck = beamazon_fleetManager.getVans()[vans0 + 1]
check(truck.kind == 'truck' and truck.name:find('Truck') and company.getTruckDriver(truck) == nil, 'a new truck has no driver')
run(1)
check(truck.trips == 0, 'a truck without a driver stays parked')
local okHire, driver = company.hireDriver()
check(okHire and driver.name == 'Alex' and company.getTruckDriver(truck) == driver, 'hire a driver: the truck gets one')
ok8, why8 = company.hireDriver()
check(not ok8 and why8 == 'driverSlots', 'a 2nd driver needs the Hire Drivers upgrade')
check(company.buyUpgrade('drivers') and company.getDriverSlots() == 2 and company.hireDriver(), 'Hire Drivers 1: 2nd driver')
local sum0 = beamazon_fleetManager.getTotals()
local truckNet0 = sum0.truckNet
run(3)
check(truck.trips >= 3 and driver.trips == truck.trips and driver.earned > 0, string.format('truck works with a driver: %d trips, driver paid $%.0f', truck.trips, driver.earned))
local perTruck = beamazon_fleetManager.getNetPerTruckHour()
local perVan = beamazon_fleetManager.getNetPerVanHour()
check(perTruck and perTruck > perVan, string.format('a truck nets more per hour than a van after the wage: $%.0f vs $%.0f', perTruck, perVan))
check(company.fireDriver(driver.id) and company.getTruckDriver(truck) ~= nil, 'firing a driver: the other one takes the truck')
check(company.fireDriver(999) == false, 'firing an unknown driver is refused')

-- the phone's company tab
local pd = beamazon_phoneApp.getData()
check(pd.company.level.level >= 1 and #pd.company.drivers == 1 and pd.company.driverSlots == 2 and #pd.company.tree >= 10 and pd.company.trucks == 1, 'phone data: company, drivers and tree')
local truckRow
for _, row in ipairs(pd.vans) do if row.kind == 'truck' then truckRow = row end end
check(truckRow and truckRow.driver ~= nil, 'phone data: a truck row names its driver')
local r = beamazon_phoneApp.hireDriver()
check(r.ok and #r.data.company.drivers == 2, 'phone: hire a driver')
r = beamazon_phoneApp.fireDriver(r.data.company.drivers[2].id)
check(r.ok and #r.data.company.drivers == 1, 'phone: fire a driver')
r = beamazon_phoneApp.buyUpgrade('nope')
check(not r.ok and r.reason == 'unknown', 'phone: unknown upgrade refused')

-- offline cap with the Night Dispatcher
company.buyUpgrade('nightDispatcher')
check(company.getEffect('offlineHours') == 1, 'Night Dispatcher: +1 h offline')

-- the company survives the save
local upgrades = deepcopy(beamazon_fleetManager.getCompany().upgrades)
save('/saves/prof/autosave1')
active = false; extensions.hook('onOverhaulActive', false)
active = true; extensions.hook('onOverhaulActive', true, false)
local c = beamazon_fleetManager.getCompany()
check(c.upgrades.bays == 5 and c.upgrades.routeSoftware == 2 and #c.drivers == 1 and c.nextDriverId == 4, 'upgrades and drivers survive the save')
local kinds = {}
for _, v in ipairs(beamazon_fleetManager.getVans()) do
  kinds[v.kind] = (kinds[v.kind] or 0) + 1
  if v.kind == 'truck' then v.condition = 1; truck = v end
end
check(kinds.truck == 1 and kinds.van == vans0, 'trucks survive the save')
local okSell, value = beamazon_fleetManager.sellVan(truck.id)
check(okSell and value == math.floor(truckPrice * 0.85 + 0.5), 'a truck sells for 85% of its price: $' .. tostring(value))

-- 9. fleet finance history
local h = beamazon_fleetManager.getHistory()
local bucketWithTrips
for _, b in ipairs(h) do
  if b.trips > 0 then bucketWithTrips = b; break end
end
check(bucketWithTrips ~= nil and bucketWithTrips.trips > 0, 'history has a bucket with trips')
local calcNet = bucketWithTrips.revenue - bucketWithTrips.energy - bucketWithTrips.wear - bucketWithTrips.commission - bucketWithTrips.wages - bucketWithTrips.purchases
check(math.abs(calcNet - bucketWithTrips.net) <= 0.02 * bucketWithTrips.trips, string.format('bucket net matches revenue - costs: %.2f vs %.2f', calcNet, bucketWithTrips.net))

local currentB = h[#h]
local purchasesBefore = currentB.purchases
local vanPrice = beamazon_fleetManager.getVanPrice()
money = vanPrice + 1000
check(beamazon_fleetManager.buyVan() == true, 'buy a van for history test')
check(currentB.purchases == purchasesBefore + vanPrice, 'buying a van adds its price to purchases')

local historyBefore = deepcopy(beamazon_fleetManager.getHistory())
save('/saves/prof/autosave1')
active = false; extensions.hook('onOverhaulActive', false)
active = true; extensions.hook('onOverhaulActive', true, false)
local historyAfter = beamazon_fleetManager.getHistory()
check(#historyAfter == #historyBefore, 'history count survives save/reload')
check(historyAfter[#historyAfter].purchases == historyBefore[#historyBefore].purchases, 'history purchases survive save/reload')
check(historyAfter[#historyAfter].net == historyBefore[#historyBefore].net, 'history net survives save/reload')

local origTime = os.time
local simHour = 5000000
os.time = function() return simHour end
for _ = 1, balance.historyHours + 10 do
  simHour = simHour + 3600
  beamazon_fleetManager.recordPurchase(10)
end
check(#beamazon_fleetManager.getHistory() == balance.historyHours, string.format('bucket list never exceeds %d: got %d', balance.historyHours, #beamazon_fleetManager.getHistory()))

simHour = simHour + 30 * 3600
beamazon_fleetManager.recordPurchase(10)
check(#beamazon_fleetManager.getHistory() == 1, 'buckets older than historyHours are dropped after a long gap')
os.time = origTime
beamazon_fleetManager.getCompany().xp = 1e6
money = 1e6
local spent = beamazon_fleetManager.getHistory()
local before = (spent[#spent] and spent[#spent].hour == math.floor(os.time() / 3600) * 3600) and spent[#spent].purchases or 0
check(company.buyUpgrade('driverTraining'), 'buy an upgrade for the history test')
spent = beamazon_fleetManager.getHistory()
check(spent[#spent].purchases - before == 15000, 'a company upgrade counts as a purchase')

local pd = beamazon_phoneApp.getData()
check(type(pd.history) == 'table' and #pd.history >= 1, 'phone getData().history exists')
check(type(pd.historyTotals) == 'table' and type(pd.historyTotals.trips) == 'number' and type(pd.historyTotals.revenue) == 'number'
  and type(pd.historyTotals.purchases) == 'number' and type(pd.historyTotals.net) == 'number', 'phone getData().historyTotals exists')
local sumPurchases = 0
for _, b in ipairs(pd.history) do sumPurchases = sumPurchases + b.purchases end
check(pd.historyTotals.purchases == sumPurchases, 'historyTotals.purchases matches sum of buckets')

active = false; extensions.hook('onOverhaulActive', false)
check(beamazon_phoneApp.getData().active == false and beamazon_phoneApp.buyVan().reason == 'careerInactive', 'phone without career')
print('all checks passed')
