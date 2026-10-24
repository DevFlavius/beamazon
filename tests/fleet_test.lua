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
local elem
for _, e in ipairs(elements) do if e.id == 'beamazonHqWestCoast' then elem = e break end end
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
check(#again == 2, 'HQ: a second POI build reuses the objects')
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
  and type(pd.historyTotals.purchases) == 'number' and type(pd.historyTotals.repairs) == 'number' and type(pd.historyTotals.net) == 'number', 'phone getData().historyTotals exists')
local sumPurchases = 0
for _, b in ipairs(pd.history) do sumPurchases = sumPurchases + b.purchases end
check(pd.historyTotals.purchases == sumPurchases, 'historyTotals.purchases matches sum of buckets')

-- 10. condition, breakdowns and service
local fm = beamazon_fleetManager
local balance = require('beamazon/balance')
local testVan = fm.getVans()[1]

-- condition drops after trips
testVan.condition = 1
local c0 = testVan.condition
local trips0 = testVan.trips
beamazon_fleetSim.setSpeed(60)
quiet = true
for _ = 1, 60 do extensions.hook('onOverhaulCareerSimStep', 1) end
quiet = false
check(testVan.condition < c0 and testVan.trips > trips0, string.format('condition drops after trips: %.3f -> %.3f', c0, testVan.condition))

-- sell value lower when worn
testVan.condition = 1
local valFull = fm.getSellValue(testVan)
testVan.condition = 0.5
local valWorn = fm.getSellValue(testVan)
check(valWorn < valFull, string.format('sell value lower when worn: $%d vs $%d', valWorn, valFull))

-- workshop node lowers service cost
testVan.condition = 0.5
local costBefore = fm.getServiceCost(testVan)
money = 1e6
fm.getCompany().xp = 1e6
check(company.buyUpgrade('workshop'), 'buy workshop upgrade')
local costAfter = fm.getServiceCost(testVan)
check(costAfter < costBefore and math.abs(costAfter - math.ceil(costBefore * 0.85)) <= 1,
  string.format('workshop lowers service cost: $%d -> $%d', costBefore, costAfter))

-- service cost and serviceVan restores 100% and charges
testVan.condition = 0.5
local sc = fm.getServiceCost(testVan)
check(sc > 0, 'service cost is positive: $' .. sc)
money = sc + 500
local m0 = money
local okServ, charged = fm.serviceVan(testVan.id)
check(okServ and charged == sc and money == m0 - sc and testVan.condition == 1,
  'serviceVan restores 100% and charges $' .. sc)

-- alreadyNew refused
local okNew, reasonNew = fm.serviceVan(testVan.id)
check(not okNew and reasonNew == 'alreadyNew', 'alreadyNew refused when condition >= 0.999')

-- serviceAll services worst first and stops when money runs out
local v1 = fm.getVans()[1]
local v2 = fm.getVans()[2]
v1.condition = 0.80
v2.condition = 0.40
local cost1 = fm.getServiceCost(v1)
local cost2 = fm.getServiceCost(v2)
check(cost2 > cost1, 'worse van costs more to service')
money = cost2
local countServ, totalServ = fm.serviceAll()
check(countServ == 1 and totalServ == cost2 and v2.condition == 1 and v1.condition == 0.80 and money == 0,
  'serviceAll services worst first and stops when money runs out')
money = 1e6
countServ, totalServ = fm.serviceAll()
check(countServ >= 1 and v1.condition == 1 and v2.condition == 1, 'serviceAll finishes remaining vehicles')

-- breakdown at condition 0 with math.random faked to 0
testVan.condition = 0
testVan.brokenFor = 0
money = 10000
local moneyBeforeBreakdown = money
local repairsBefore = (fm.getHistory()[#fm.getHistory()] or {}).repairs or 0
local origRandom = math.random
math.random = function(...)
  if select('#', ...) == 0 then return 0 else return origRandom(...) end
end
testVan.trip = beamazon_fleetEconomy.rollTrip(testVan.kind)
testVan.tripElapsed = testVan.trip.durationS
fm.recordTrip(testVan, beamazon_fleetEconomy.settleTrip(testVan.trip))
math.random = origRandom
check(testVan.brokenFor == balance.breakdownRepairSeconds, 'vehicle broke down: brokenFor is ' .. tostring(testVan.brokenFor))
check(testVan.breakdowns >= 1, 'breakdowns count incremented')
check(money == moneyBeforeBreakdown - balance.breakdownRepairCost, 'repair cost paid from balance')
local currentB = fm.getHistory()[#fm.getHistory()]
check(currentB.repairs == repairsBefore + balance.breakdownRepairCost, 'repair recorded in finance bucket repairs')

-- broken vehicle stops working for breakdownRepairSeconds and then works again
testVan.trip = nil
testVan.tripElapsed = 0
testVan.brokenFor = 100
beamazon_fleetSim.setSpeed(1)
extensions.hook('onOverhaulCareerSimStep', 30)
check(testVan.brokenFor == 70 and testVan.trip == nil, 'broken vehicle does not work: 70s left')
extensions.hook('onOverhaulCareerSimStep', 80)
check(testVan.brokenFor == 0 and testVan.trip ~= nil, 'repaired vehicle resumes work')

-- condition and brokenFor survive save/reload
testVan.condition = 0.42
testVan.brokenFor = 950
save('/saves/prof/autosave1')
active = false; extensions.hook('onOverhaulActive', false)
active = true; extensions.hook('onOverhaulActive', true, false)
local reloadedVan = fm.getVans()[1]
check(math.abs(reloadedVan.condition - 0.42) < 0.001 and reloadedVan.brokenFor == 950,
  'condition (0.42) and brokenFor (950) survive save and reload')

-- phone rows have condition, serviceCost, brokenMinutes, breakdowns
reloadedVan.condition = 0.75
local pd2 = beamazon_phoneApp.getData()
local phoneRow = pd2.vans[1]
check(phoneRow.condition == 75 and phoneRow.serviceCost == fm.getServiceCost(reloadedVan)
  and phoneRow.brokenMinutes == math.ceil(950 / 60) and type(phoneRow.breakdowns) == 'number',
  'phone rows have condition, serviceCost, brokenMinutes, breakdowns')
check(pd2.serviceAllCost > 0, 'phone getData() has serviceAllCost')

-- phone serviceVan works
money = phoneRow.serviceCost + 1000
local rPhone = beamazon_phoneApp.serviceVan(phoneRow.id)
check(rPhone.ok and rPhone.data.vans[1].condition == 100 and rPhone.data.vans[1].serviceCost == 0,
  'phone serviceVan works and restores condition to 100%')

-- 11. company branches (Dockyards)
local branchPois = {}
hq.onGetRawPoiListForLevel('rls_west_coast', branchPois)
check(#branchPois == 2, 'POI list on rls_west_coast has 2 elements: got ' .. #branchPois)
local branchElem
for _, e in ipairs(branchPois) do
  if e.data.kind == 'branch' then branchElem = e break end
end
check(branchElem and branchElem.data.branch == 'dockyards' and branchElem.data.siteId == 'beamazonDockyardsWestCoast',
  'Dockyards branch POI element found on rls_west_coast')

-- the Dockyards desk object exists
local dockDesk = objects.beamazonDockyardsWestCoast_desk
local dockLaptop = objects.beamazonDockyardsWestCoast_laptop
check(dockDesk and dockDesk.class == 'TSStatic' and dockDesk.shapeName:find('s_office_desk') and dockDesk.canSave == false,
  'Dockyards desk object exists and is TSStatic')
check(dockLaptop and dockLaptop.shapeName:find('s_laptop_ON'), 'Dockyards laptop object exists')

-- the branch card is locked without enough company level (set the company xpEarned low), with the right reason text
local function branchCard()
  local list = {}
  hq.onActivityAcceptGatherData({branchElem.data}, list)
  return list[1]
end

local c11 = fm.getCompany()
c11.xpEarned = 100 -- company level 1 (needs level 3, which is 1500 XP)
money = 1e6
local bc = branchCard()
check(bc and bc.disabled and bc.disableReason == 'Reach company level 3 first',
  'branch card locked without company level: ' .. tostring(bc and bc.disableReason))

-- buyBranch reasons: unknown, companyLevel, notEnoughMoney, success charges 60000 and the limit grows by 4
local okB, whyB = fm.buyBranch('nonexistent')
check(okB == false and whyB == 'unknown', 'buyBranch unknown: ' .. tostring(whyB))

okB, whyB = fm.buyBranch('dockyards')
check(okB == false and whyB == 'companyLevel', 'buyBranch companyLevel: ' .. tostring(whyB))

c11.xpEarned = 1500 -- company level 3
money = 100
okB, whyB = fm.buyBranch('dockyards')
check(okB == false and whyB == 'notEnoughMoney', 'buyBranch notEnoughMoney: ' .. tostring(whyB))
bc = branchCard()
check(bc and bc.disabled and bc.disableReason == 'Not enough money', 'branch card locked without money: ' .. tostring(bc and bc.disableReason))

money = 100000
local limitBeforeBranch = fm.getVanLimit()
bc = branchCard()
check(bc and not bc.disabled and bc.buttonLabel == 'Buy the branch', 'branch card unlocked with level 3 and $100k')
bc.buttonFun()
check(fm.ownsBranch('dockyards'), 'Dockyards branch is now owned')
check(money == 100000 - 60000, 'buyBranch charged $60,000 (money: ' .. money .. ')')
check(fm.getVanLimit() == limitBeforeBranch + 4, 'limit grew by 4 slots (' .. fm.getVanLimit() .. ')')
check(ledger[#ledger][2] == 'Beamazon: Beamazon Dockyards' and ledger[#ledger][3] == 'business', 'purchase recorded in ledger')
fm.status()

-- alreadyOwned
okB, whyB = fm.buyBranch('dockyards')
check(okB == false and whyB == 'alreadyOwned', 'buyBranch alreadyOwned: ' .. tostring(whyB))

-- the branch card once owned says "Open the phone"
bc = branchCard()
check(bc and bc.buttonLabel == 'Open the phone' and not bc.disabled, 'branch card once owned says Open the phone')

-- the branch survives save/reload
save('/saves/prof/autosave1')
active = false; extensions.hook('onOverhaulActive', false)
check(fm.ownsBranch('dockyards') == false, 'career off: no branch owned')
active = true; extensions.hook('onOverhaulActive', true, false)
check(fm.ownsBranch('dockyards') == true and disk['/saves/prof/autosave1/career/beamazon.json'].company.branches.dockyards == true,
  'branch survives save/reload')
check(fm.getVanLimit() == limitBeforeBranch + 4, 'van limit with branch survives save/reload')

-- phone data lists the branch with owned = true and onThisMap = true
local pd3 = beamazon_phoneApp.getData()
check(type(pd3.company.branches) == 'table' and #pd3.company.branches >= 1, 'phone data has company.branches')
local phoneBranch
for _, b in ipairs(pd3.company.branches) do
  if b.id == 'dockyards' then phoneBranch = b break end
end
check(phoneBranch and phoneBranch.owned == true and phoneBranch.onThisMap == true and phoneBranch.siteId == 'beamazonDockyardsWestCoast',
  'phone branch has owned=true and onThisMap=true')

-- phone routeToSite works with the fake freeroam_bigMapMode used by the HQ route tests
navTarget = nil
playerVehicle = nil
check(beamazon_phoneApp.routeToSite(phoneBranch.siteId).ok == false and navTarget == nil, 'routeToSite refused on foot')
playerVehicle = {}
local rSite = beamazon_phoneApp.routeToSite(phoneBranch.siteId)
check(rSite.ok and navTarget and math.abs(navTarget.x - 469.726) < 0.001, 'routeToSite sets GPS to branch pos')

-- 12. per-vehicle upgrades
;(function()
  local fm = beamazon_fleetManager
  local v = fm.getVans()[1]
  v.upgrades = {}
  v.upgradeSpent = 0

  -- buying each upgrade charges base then base+increment
  money = 100000
  check(fm.getVehicleUpgradeCost(v, 'motor') == 1000, 'motor level 0 costs base ($1000)')
  local okUp, costUp = fm.upgradeVehicle(v.id, 'motor')
  check(okUp and costUp == 1000 and v.upgrades.motor == 1 and v.upgradeSpent == 1000, 'motor level 1 bought for $1000')
  check(fm.getVehicleUpgradeCost(v, 'motor') == 2000, 'motor level 1 costs base + increment ($2000)')
  okUp, costUp = fm.upgradeVehicle(v.id, 'motor')
  check(okUp and costUp == 2000 and v.upgrades.motor == 2 and v.upgradeSpent == 3000, 'motor level 2 bought for $2000')

  check(fm.getVehicleUpgradeCost(v, 'battery') == 1500, 'battery level 0 costs base ($1500)')
  okUp, costUp = fm.upgradeVehicle(v.id, 'battery')
  check(okUp and costUp == 1500 and v.upgrades.battery == 1, 'battery level 1 bought for $1500')
  check(fm.getVehicleUpgradeCost(v, 'battery') == 3000, 'battery level 1 costs base + increment ($3000)')

  check(fm.getVehicleUpgradeCost(v, 'cargo') == 2000, 'cargo level 0 costs base ($2000)')
  okUp, costUp = fm.upgradeVehicle(v.id, 'cargo')
  check(okUp and costUp == 2000 and v.upgrades.cargo == 1, 'cargo level 1 bought for $2000')
  check(fm.getVehicleUpgradeCost(v, 'cargo') == 4000, 'cargo level 1 costs base + increment ($4000)')

  check(fm.getVehicleUpgradeCost(v, 'routing') == 2000, 'routing level 0 costs base ($2000)')
  okUp, costUp = fm.upgradeVehicle(v.id, 'routing')
  check(okUp and costUp == 2000 and v.upgrades.routing == 1, 'routing level 1 bought for $2000')
  check(fm.getVehicleUpgradeCost(v, 'routing') == 4000, 'routing level 1 costs base + increment ($4000)')

  -- truck pays x2
  local testTruck = nil
  for _, veh in ipairs(fm.getVans()) do
    if veh.kind == 'truck' then testTruck = veh; break end
  end
  if not testTruck then
    money = 100000
    fm.buyTruck()
    testTruck = fm.getVans()[#fm.getVans()]
  end
  testTruck.upgrades = {}
  testTruck.upgradeSpent = 0
  check(fm.getVehicleUpgradeCost(testTruck, 'motor') == 2000, 'truck pays x2 for upgrades ($2000 for motor 1)')
  local okT, costT = fm.upgradeVehicle(testTruck.id, 'motor')
  check(okT and costT == 2000 and testTruck.upgrades.motor == 1 and testTruck.upgradeSpent == 2000, 'truck upgrade charges 2x base')

  -- maxLevel refused
  check(v.upgrades.cargo == 1, 'cargo is level 1 before reaching max')
  okUp, costUp = fm.upgradeVehicle(v.id, 'cargo')
  check(okUp and v.upgrades.cargo == 2, 'cargo reached maxLevel 2')
  check(fm.getVehicleUpgradeCost(v, 'cargo') == nil, 'cost is nil at max level')
  local okMax, whyMax = fm.upgradeVehicle(v.id, 'cargo')
  check(okMax == false and whyMax == 'maxLevel', 'upgradeVehicle maxLevel refused: ' .. tostring(whyMax))

  -- unknown refused
  local okUnk, whyUnk = fm.upgradeVehicle(v.id, 'nonexistent')
  check(okUnk == false and whyUnk == 'unknown', 'upgradeVehicle unknown refused: ' .. tostring(whyUnk))

  -- noVan refused
  local okNoVan, whyNoVan = fm.upgradeVehicle(99999, 'motor')
  check(okNoVan == false and whyNoVan == 'noVan', 'upgradeVehicle noVan refused: ' .. tostring(whyNoVan))

  -- notEnoughMoney refused and nothing changes
  money = 0
  local spentBeforeNoMoney = v.upgradeSpent
  local routingLvlBefore = v.upgrades.routing
  local okNoMoney, whyNoMoney = fm.upgradeVehicle(v.id, 'routing')
  check(okNoMoney == false and whyNoMoney == 'notEnoughMoney', 'upgradeVehicle notEnoughMoney refused: ' .. tostring(whyNoMoney))
  check(v.upgrades.routing == routingLvlBefore and v.upgradeSpent == spentBeforeNoMoney and money == 0, 'nothing changes on notEnoughMoney')

  -- effects:
  -- with cargo the trips can carry one more parcel than the profile max
  local origRandom = math.random
  math.random = function(...)
    local n = select('#', ...)
    if n == 0 then return 0.01 end
    if n == 1 then return 1 end
    local a, b = ...
    return a
  end
  local normalTrip = beamazon_fleetEconomy.rollTrip('van')
  local cargoTrip = beamazon_fleetEconomy.rollTrip('van', {parcels = 1, tripTime = 0, energy = 0, revenue = 0})
  math.random = origRandom
  check(#normalTrip.parcels == balance.maxParcelsPerTrip, 'normal trip parcels count is maxParcelsPerTrip')
  check(#cargoTrip.parcels == balance.maxParcelsPerTrip + 1, 'cargo mod allows 1 more parcel than profile max')

  -- routing raises revenue for the same trip by 3% per level
  local sampleTrip = beamazon_fleetEconomy.rollTrip('van')
  local baseRes = beamazon_fleetEconomy.settleTrip(sampleTrip)
  local routeRes1 = beamazon_fleetEconomy.settleTrip(sampleTrip, nil, {revenue = 0.03, energy = 0, tripTime = 0, parcels = 0})
  local routeRes2 = beamazon_fleetEconomy.settleTrip(sampleTrip, nil, {revenue = 0.06, energy = 0, tripTime = 0, parcels = 0})
  local effRev = beamazon_company and beamazon_company.getEffect('revenue') or 0
  local rawRevEst = baseRes.revenue / (1 + effRev)
  check(math.abs((routeRes1.revenue - baseRes.revenue) - rawRevEst * 0.03) <= 0.05, 'routing level 1 raises revenue by 3%')
  check(math.abs((routeRes2.revenue - baseRes.revenue) - rawRevEst * 0.06) <= 0.05, 'routing level 2 raises revenue by 6%')

  -- motor lowers energy
  local motorRes = beamazon_fleetEconomy.settleTrip(sampleTrip, nil, {energy = -0.10, revenue = 0})
  check(motorRes.energy < baseRes.energy and math.abs(motorRes.energy - baseRes.energy * 0.90) <= 0.02, 'motor lowers energy by 10%')

  -- battery shortens durationS
  math.randomseed(123)
  local tripNormalTime = beamazon_fleetEconomy.rollTrip('van')
  math.randomseed(123)
  local tripBatteryTime = beamazon_fleetEconomy.rollTrip('van', {tripTime = -0.05})
  check(tripBatteryTime.durationS < tripNormalTime.durationS, 'battery shortens durationS')

  -- upgrades survive save/reload
  local vSavedUpgrades = deepcopy(v.upgrades)
  local vSavedSpent = v.upgradeSpent
  save('/saves/prof/autosave1')
  active = false; extensions.hook('onOverhaulActive', false)
  active = true; extensions.hook('onOverhaulActive', true, false)
  local vReloaded = fm.getVans()[1]
  check(vReloaded.upgradeSpent == vSavedSpent, 'upgradeSpent survives save/reload')
  check(vReloaded.upgrades.motor == vSavedUpgrades.motor and vReloaded.upgrades.cargo == vSavedUpgrades.cargo, 'upgrades table survives save/reload')

  -- the sell value grows by half the upgrade money
  local vNoUp = deepcopy(vReloaded)
  vNoUp.upgradeSpent = 0
  local valWithUp = fm.getSellValue(vReloaded)
  local valNoUp = fm.getSellValue(vNoUp)
  check(valWithUp == valNoUp + math.floor(vReloaded.upgradeSpent * 0.5), 'sell value grows by half the upgrade money')

  -- phone rows list 4 upgrades and phone upgradeVehicle works
  local pd4 = beamazon_phoneApp.getData()
  local phoneVan = pd4.vans[1]
  check(type(phoneVan.upgrades) == 'table' and #phoneVan.upgrades == 4, 'phone row lists 4 vehicle upgrades')
  check(phoneVan.upgrades[1].id == 'motor' and phoneVan.upgrades[1].title == 'Efficient Motor', 'phone upgrade has id and title')
  money = 50000
  local rPhoneUp = beamazon_phoneApp.upgradeVehicle(phoneVan.id, 'routing')
  check(rPhoneUp.ok and rPhoneUp.data.vans[1].upgrades[4].level >= 2, 'phone upgradeVehicle works and returns updated data')
end)()

-- 13. delivery contracts
;(function()
  local fm = beamazon_fleetManager
  local contracts = beamazon_contracts
  local balance = require('beamazon/balance')

  -- Initial state: timer = 0, no offer, no active contract
  local s = fm.getContractState()
  s.timer = 0
  s.offer = nil
  s.active = nil
  s.completed = 0
  s.failed = 0

  -- no offer before contractEverySeconds of fleet time
  contracts.onFleetTime(balance.contractEverySeconds - 1)
  check(s.offer == nil and s.timer == balance.contractEverySeconds - 1, 'no offer before contractEverySeconds of fleet time')

  -- an offer appears after it
  contracts.onFleetTime(1)
  check(s.offer ~= nil and s.timer == 0, 'an offer appears after contractEverySeconds of fleet time')
  check(s.offer.trips >= 3 and s.offer.bonus == s.offer.trips * balance.contractBonusPerTrip, 'offer trips and bonus calculated properly')
  check(s.offer.penalty == math.floor(s.offer.bonus * balance.contractPenaltyShare), 'offer penalty calculated properly')

  -- the offer expires after contractOfferSeconds
  contracts.onFleetTime(balance.contractOfferSeconds)
  check(s.offer == nil, 'the offer expires after contractOfferSeconds')

  -- accept/decline reasons
  local okAcc, whyAcc = contracts.accept()
  check(okAcc == false and whyAcc == 'noOffer', 'accept without offer returns noOffer')
  local okDec, whyDec = contracts.decline()
  check(okDec == false and whyDec == 'noOffer', 'decline without offer returns noOffer')

  -- roll an offer for decline test
  local off = contracts.rollOffer()
  check(off ~= nil and s.offer == off, 'rollOffer generates an offer')
  check(contracts.decline() == true and s.offer == nil, 'decline clears the offer')

  -- roll an offer for accept test
  off = contracts.rollOffer()
  check(contracts.accept() == true, 'accept accepts the offer')
  check(s.offer == nil and s.active ~= nil, 'offer becomes active')
  check(s.active.done == 0 and s.active.left == s.active.seconds, 'active has done = 0 and left = seconds')

  -- alreadyActive reason when trying to accept while one is active
  s.offer = off
  local okAcc2, whyAcc2 = contracts.accept()
  check(okAcc2 == false and whyAcc2 == 'alreadyActive', 'accept while active returns alreadyActive')
  s.offer = nil

  -- accept then trips completes it: money + bonus, completed = 1, history bonuses; company XP rises when company exists
  local activeContract = s.active
  local neededTrips = activeContract.trips
  local bonus = activeContract.bonus
  local moneyBefore = money
  local compXpBefore = (fm.getCompany() and fm.getCompany().xpEarned) or 0
  local currentB = fm.getHistory()[#fm.getHistory()]
  local bonusesBefore = currentB and currentB.bonuses or 0

  for _ = 1, neededTrips - 1 do
    contracts.onTrip(fm.getVans()[1])
    check(s.active ~= nil and s.active.done < neededTrips, 'contract still active before all trips done')
  end
  contracts.onTrip(fm.getVans()[1])
  check(s.active == nil, 'contract completed and active cleared')
  check(s.completed == 1, 'completed count is 1')
  check(money == moneyBefore + bonus, 'bonus money added: $' .. bonus)
  check(ledger[#ledger][2]:find('contract with') ~= nil, 'contract ledger entry recorded')
  local compXpAfter = (fm.getCompany() and fm.getCompany().xpEarned) or 0
  check(math.abs((compXpAfter - compXpBefore) - bonus * balance.contractXpPerDollar) < 0.01,
    'company XP rises when company exists: +' .. (bonus * balance.contractXpPerDollar) .. ' XP')
  currentB = fm.getHistory()[#fm.getHistory()]
  check(currentB.bonuses == bonusesBefore + bonus, 'history bucket bonuses recorded bonus')

  -- a missed contract charges the penalty and counts failed
  off = contracts.rollOffer()
  check(contracts.accept() == true, 'accept second contract')
  local penalty = s.active.penalty
  local moneyBeforeFail = money
  local bonusesBeforeFail = currentB.bonuses
  contracts.onFleetTime(s.active.seconds + 1)
  check(s.active == nil and s.failed == 1, 'missed contract clears active and increments failed')
  check(money == moneyBeforeFail - penalty, 'penalty charged from balance: -$' .. penalty)
  currentB = fm.getHistory()[#fm.getHistory()]
  check(currentB.bonuses == bonusesBeforeFail - penalty, 'history bucket bonuses recorded -penalty')

  -- state survives save/reload
  off = contracts.rollOffer()
  contracts.accept()
  s.active.done = 2
  s.timer = 123
  save('/saves/prof/autosave1')
  active = false; extensions.hook('onOverhaulActive', false)
  check(fm.getContractState() == nil, 'career off: contract state is nil')
  active = true; extensions.hook('onOverhaulActive', true, false)
  local reloadedState = fm.getContractState()
  check(reloadedState ~= nil, 'contract state reloaded')
  check(reloadedState.completed == 1 and reloadedState.failed == 1 and reloadedState.timer == 123, 'completed, failed, timer survive save/reload')
  check(reloadedState.active ~= nil and reloadedState.active.done == 2, 'active contract with progress survives save/reload')

  -- phone getData().contracts and acceptContract work
  local pd = beamazon_phoneApp.getData()
  check(type(pd.contracts) == 'table', 'phone getData().contracts exists')
  check(pd.contracts.active ~= nil and pd.contracts.active.done == 2, 'phone view has active contract with done=2')
  check(pd.contracts.completed == 1 and pd.contracts.failed == 1, 'phone view has completed and failed')

  -- fail the active one so we can test phone acceptContract
  contracts.onFleetTime(reloadedState.active.seconds + 1)
  check(reloadedState.active == nil, 'active contract expired')

  -- test phone view when neither: nextOfferMinutes
  reloadedState.timer = 600
  pd = beamazon_phoneApp.getData()
  check(pd.contracts.nextOfferMinutes == math.ceil((balance.contractEverySeconds - 600) / 60), 'phone view nextOfferMinutes when neither')

  -- roll an offer and test phone acceptContract
  contracts.rollOffer()
  pd = beamazon_phoneApp.getData()
  check(pd.contracts.offer ~= nil, 'phone view has offer')
  check(pd.contracts.offer.hours >= balance.contractHoursMin, 'phone view offer has hours')
  local rAcc = beamazon_phoneApp.acceptContract()
  check(rAcc.ok and rAcc.data.contracts.active ~= nil, 'phone acceptContract works and returns updated active contract')
  local rAccFail = beamazon_phoneApp.acceptContract()
  check(rAccFail.ok == false and rAccFail.reason == 'alreadyActive', 'phone acceptContract while active fails with alreadyActive')

  -- complete it and test phone declineContract
  for _ = 1, reloadedState.active.trips do contracts.onTrip(fm.getVans()[1]) end
  check(reloadedState.active == nil, 'active completed')
  contracts.rollOffer()
  local rDec = beamazon_phoneApp.declineContract()
  check(rDec.ok and rDec.data.contracts.offer == nil, 'phone declineContract works and clears offer')
  local rDecFail = beamazon_phoneApp.declineContract()
  check(rDecFail.ok == false and rDecFail.reason == 'noOffer', 'phone declineContract without offer fails with noOffer')
end)()

-- 14. company automation (manager and sales team)
;(function()
  local fm = beamazon_fleetManager
  local company = beamazon_company
  local contracts = beamazon_contracts
  local balance = require('beamazon/balance')

  -- without the node nothing is automatic
  check(company.hasAutoService() == false, 'without manager node: hasAutoService is false')
  check(company.hasAutoContracts() == false, 'without salesTeam node: hasAutoContracts is false')

  local v = fm.getVans()[1]
  v.condition = 0.1
  local moneyBefore = money
  v.trip = beamazon_fleetEconomy.rollTrip(v.kind)
  v.tripElapsed = v.trip.durationS
  fm.recordTrip(v, beamazon_fleetEconomy.settleTrip(v.trip))
  check(v.condition < 0.2, 'without manager: van at 0.1 condition is not serviced automatically')

  local s = fm.getContractState()
  s.active = nil
  s.offer = nil
  local off = contracts.rollOffer()
  check(s.offer ~= nil and s.active == nil, 'without sales team: rollOffer leaves an offer, does not auto-accept')
  contracts.decline()

  -- buy 'manager' (give the company enough xp and money; dependencies: drivers level 1 may already be bought in earlier sections — check with beamazon_company.getUpgradeLevel and buy what is missing)
  if company.getUpgradeLevel('drivers') < 1 then
    fm.getCompany().xp = 100000
    money = 100000
    company.buyUpgrade('drivers')
  end
  fm.getCompany().xp = 100000
  money = 100000
  check(company.buyUpgrade('manager') == true, 'buy manager upgrade')
  check(company.getUpgradeLevel('manager') == 1, 'manager upgrade level is 1')
  check(company.hasAutoService() == true, 'hasAutoService is true after buying manager')

  -- a van at condition 0.1 that finishes a trip gets serviced to 1 and the money drops by the service cost
  v.condition = 0.1
  money = 50000
  local moneyBeforeService = money
  v.trip = beamazon_fleetEconomy.rollTrip(v.kind)
  v.tripElapsed = v.trip.durationS
  fm.recordTrip(v, beamazon_fleetEconomy.settleTrip(v.trip))
  local charged = moneyBeforeService - money
  check(v.condition == 1, 'van at condition 0.1 serviced to 1')
  check(charged > 0 and money == moneyBeforeService - charged, 'money drops by the service cost: $' .. charged)

  -- turning autoService off stops it
  check(company.setSetting('autoService', false) == true, 'setSetting autoService false')
  check(company.hasAutoService() == false, 'hasAutoService is false when setting is false')
  v.condition = 0.1
  money = 50000
  local moneyBeforeNoService = money
  v.trip = beamazon_fleetEconomy.rollTrip(v.kind)
  v.tripElapsed = v.trip.durationS
  fm.recordTrip(v, beamazon_fleetEconomy.settleTrip(v.trip))
  check(v.condition < 0.2, 'autoService off stops auto servicing')
  check(money == moneyBeforeNoService, 'money unchanged when autoService off')
  company.setSetting('autoService', true)
  check(company.hasAutoService() == true, 'autoService re-enabled')

  -- the wage is charged once per 3600 fleet seconds (call beamazon_fleetManager.addWorkTime(3600, 0, 1) directly) and appears in the history wages
  money = 50000
  local moneyBeforeWage = money
  local bucket = fm.getHistory()[#fm.getHistory()]
  local wagesBefore = bucket and bucket.wages or 0
  fm.addWorkTime(3600, 0, 1)
  check(money == moneyBeforeWage - balance.managerWagePerHour, 'wage charged once per 3600 fleet seconds: $' .. balance.managerWagePerHour)
  bucket = fm.getHistory()[#fm.getHistory()]
  check(bucket.wages == wagesBefore + balance.managerWagePerHour, 'wage appears in history wages')

  -- buy 'salesTeam': rollOffer accepts by itself (state().active set, offer nil) and the bonus is 10% higher than trips * contractBonusPerTrip
  s.active = nil
  s.offer = nil
  fm.getCompany().xp = 100000
  money = 100000
  check(company.buyUpgrade('salesTeam') == true, 'buy salesTeam upgrade')
  check(company.getUpgradeLevel('salesTeam') == 1, 'salesTeam upgrade level is 1')
  check(company.hasAutoContracts() == true, 'hasAutoContracts is true after buying salesTeam')

  off = contracts.rollOffer()
  check(s.active ~= nil and s.offer == nil, 'rollOffer accepts by itself: state().active set, offer nil')
  local expectedBonus = math.floor(s.active.trips * balance.contractBonusPerTrip * 1.10)
  check(s.active.bonus == expectedBonus, 'bonus is 10% higher than trips * contractBonusPerTrip: ' .. s.active.bonus .. ' == ' .. expectedBonus)

  -- with autoContracts off, rollOffer leaves an offer
  s.active = nil
  s.offer = nil
  check(company.setSetting('autoContracts', false) == true, 'setSetting autoContracts false')
  check(company.hasAutoContracts() == false, 'hasAutoContracts is false when setting is false')
  off = contracts.rollOffer()
  check(s.offer ~= nil and s.active == nil, 'with autoContracts off, rollOffer leaves an offer')
  contracts.decline()
  company.setSetting('autoContracts', true)
  check(company.hasAutoContracts() == true, 'autoContracts re-enabled')

  -- settings survive save/reload (copy how other sections do it)
  company.setSetting('autoService', false)
  company.setSetting('autoContracts', true)
  save('/saves/prof/autosave1')
  active = false; extensions.hook('onOverhaulActive', false)
  check(company.getSettings() == nil, 'career off: company settings nil')
  active = true; extensions.hook('onOverhaulActive', true, false)
  local cReloaded = fm.getCompany()
  check(cReloaded and type(cReloaded.settings) == 'table', 'settings table reloaded')
  check(cReloaded.settings.autoService == false and cReloaded.settings.autoContracts == true,
    'settings survive save/reload: autoService=false, autoContracts=true')
  check(company.hasAutoService() == false, 'hasAutoService correctly false after reload')
  check(company.hasAutoContracts() == true, 'hasAutoContracts correctly true after reload')

  -- phone setAutoService(false) works and companyData has hasManager
  company.setSetting('autoService', true)
  local pd = beamazon_phoneApp.getData()
  check(pd.company and pd.company.hasManager == true, 'phone companyData has hasManager == true')
  check(pd.company.hasSalesTeam == true, 'phone companyData has hasSalesTeam == true')
  check(pd.company.managerWagePerHour == balance.managerWagePerHour, 'phone companyData has managerWagePerHour')
  check(pd.company.settings.autoService == true, 'phone companyData settings.autoService is true')

  local rPhone = beamazon_phoneApp.setAutoService(false)
  check(rPhone.ok == true and rPhone.data.company.settings.autoService == false, 'phone setAutoService(false) works')
  check(company.hasAutoService() == false, 'hasAutoService is false after phone setAutoService(false)')

  local rPhoneContracts = beamazon_phoneApp.setAutoContracts(false)
  check(rPhoneContracts.ok == true and rPhoneContracts.data.company.settings.autoContracts == false, 'phone setAutoContracts(false) works')
  check(company.hasAutoContracts() == false, 'hasAutoContracts is false after phone setAutoContracts(false)')

  -- set them back on
  beamazon_phoneApp.setAutoService(true)
  beamazon_phoneApp.setAutoContracts(true)
  check(company.hasAutoService() == true and company.hasAutoContracts() == true, 'automation settings restored to true')
end)()

active = false; extensions.hook('onOverhaulActive', false)
check(beamazon_phoneApp.getData().active == false and beamazon_phoneApp.buyVan().reason == 'careerInactive', 'phone without career')
print('all checks passed')
