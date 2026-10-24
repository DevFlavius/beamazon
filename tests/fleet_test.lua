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
  check(math.abs(scaled - one * 25) < 0.05 and scaled > 0, string.format('pay multiplier: $%.2f x25 = $%.2f', one, scaled))
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
local objects = {}
local function sceneObject(class)
  local o = {class = class}
  function o:setPosition(p) self.pos = p end
  function o:setScale(v) self.scale = v end
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

active = false; extensions.hook('onOverhaulActive', false)
check(beamazon_phoneApp.getData().active == false and beamazon_phoneApp.buyVan().reason == 'careerInactive', 'phone without career')
print('all checks passed')
