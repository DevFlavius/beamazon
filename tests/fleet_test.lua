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
local money, active, ledger = 0, true, {}
local function installRls()
  overhaul_career_career = {isActive = function() return active end}
  overhaul_career_economy_playerAttributes = {
    getAttributeValue = function() return money end,
    addAttributes = function(c, r) money = money + c.money; table.insert(ledger, {c.money, r.label, r.category}) end,
  }
  overhaul_career_economy_payment = {pay = function(price, r)
    if price.money.amount > money then return false end
    overhaul_career_economy_playerAttributes.addAttributes({money = -price.money.amount}, r); return true end}
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
    return {money = b*pay[t]/ref} end} end
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
money = 1500
extensions.hook('onOverhaulActive', true, false)
check(beamazon_fleetManager.buyVan() == true and money == 500, 'buyVan charges $1000')
check(beamazon_fleetManager.buyVan() == false and money == 500, 'buyVan refuses without money')
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
beamazon_fleetManager.status()

-- 3. save and reload
check(disk['/saves/prof/autosave1/career/beamazon.json'].savedAt == now, 'saved to <savePath>/career/beamazon.json with savedAt')
local before = deepcopy(vans)
active = false; extensions.hook('onOverhaulActive', false)
check(#beamazon_fleetManager.getVans() == 0, 'career off: fleet cleared')
beamazon_fleetSim.onBeamazonSimStep(10)
active = true; extensions.hook('onOverhaulActive', true, false)
local after = beamazon_fleetManager.getVans()
check(#after == 2 and after[1].trips == before[1].trips and after[1].tripElapsed == before[1].tripElapsed, 'reload keeps vans and trip progress')
check(beamazon_fleetManager.buyVan() and beamazon_fleetManager.getVans()[3].id == 3, 'ids continue after reload')

-- 4. speed and catch-up
check(beamazon_fleetSim.setSpeed(0) == false and beamazon_fleetSim.setSpeed(60), 'setSpeed validates')
local t0, rows0 = after[1].trips, #ledger
quiet = true; for _ = 1, 60 do extensions.hook('onOverhaulCareerSimStep', 1) end; quiet = false
check(#ledger - rows0 == 1, 'payouts batched: 1 ledger row for a game minute of trips')
check(after[1].trips - t0 >= 1, 'x60: 1 game minute = 1 fleet hour, trips ' .. (after[1].trips - t0))


-- 5. offline progress
beamazon_fleetSim.setSpeed(1)
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
check(gained >= 30 and gained <= 120, '48 h away is capped at 8 h: ' .. gained .. ' trips')
gained = awayFor(-5)
check(gained <= 3, 'clock moved back: no offline progress')
print('all checks passed')
