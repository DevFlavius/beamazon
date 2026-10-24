-- Beamazon: the company HQ, a point on the map where the player founds the company.
-- A vanilla POI, built like lua/ge/extensions/freeroam/gasStations.lua: a walking marker over two scene
-- objects made at runtime (the area the player walks into and the icon spot), plus the accept card.
-- Nothing is written to the level: the objects live in the loaded scene only.

local M = {}

local balance = require('beamazon/balance')

local poiType = 'beamazonHq'

-- One HQ spot per level. pos is where the player stands to use it; the icon floats above it.
local sites = {
-- desk is the office desk in front of the spot: offset from pos in metres and yaw in degrees (turn it if it clips a wall).
  rls_west_coast = {id = 'beamazonHqWestCoast', name = 'Beamazon HQ', pos = {-126.627, 36.444, 122.440}, desk = {offset = {0, 1.3, 0}, yaw = 180}},
}

-- Game shapes (art_shapes.zip, the same the RLS garages use): an office desk with a laptop on top.
local deskShape = '/art/shapes/garage_and_dealership/garage/s_office_desk.dae'
local laptopShape = '/art/shapes/garage_and_dealership/garage/s_laptop_ON.dae'
local deskTop = 0.78
local laptopOnDesk = {-0.25, 0.1}

local areaScale = {2.5, 2.5, 2}
local iconHeight = 1.2

local function objectNames(site)
  return site.id .. '_area', site.id .. '_icon'
end

-- A TSStatic made at runtime, built like flowgraph/nodes/scene/spawnTSStatic.lua; canSave = false keeps it out of the level file.
local function spawnStatic(name, shape, pos, rot)
  local object = createObject('TSStatic')
  object.shapeName = shape
  object:setPosition(pos)
  local torque = rot:toTorqueQuat()
  object:setField('rotation', 0, torque.x .. ' ' .. torque.y .. ' ' .. torque.z .. ' ' .. torque.w)
  object.canSave = false
  object:registerObject(name)
  scenetree.MissionGroup:addObject(object)
end

-- The desk and the laptop of the HQ, once per loaded level.
local function ensureDesk(site, pos)
  local deskName, laptopName = site.id .. '_desk', site.id .. '_laptop'
  if not site.desk or scenetree.findObject(deskName) then return end
  local rot = quatFromEuler(0, 0, math.rad(site.desk.yaw))
  local deskPos = pos + vec3(site.desk.offset[1], site.desk.offset[2], site.desk.offset[3])
  spawnStatic(deskName, deskShape, deskPos, rot)
  spawnStatic(laptopName, laptopShape, deskPos + rot * vec3(laptopOnDesk[1], laptopOnDesk[2], deskTop), rot)
end

-- Makes the area and icon objects once per loaded level; a Lua reload finds them still there.
local function ensureObjects(site)
  local areaName, iconName = objectNames(site)
  local pos = vec3(site.pos[1], site.pos[2], site.pos[3])
  if not scenetree.findObject(areaName) then
    local area = createObject('BeamNGGameplayArea')
    area:setPosition(pos)
    area:setScale(vec3(areaScale[1], areaScale[2], areaScale[3]))
    area:registerObject(areaName)
    scenetree.MissionGroup:addObject(area)
  end
  if not scenetree.findObject(iconName) then
    local icon = createObject('BeamNGPointOfInterest')
    icon:setPosition(pos + vec3(0, 0, iconHeight))
    icon:registerObject(iconName)
    scenetree.MissionGroup:addObject(icon)
  end
  ensureDesk(site, pos)
  return pos
end

local function currentSite()
  return sites[getCurrentLevelIdentifier() or '']
end

-- Sets the GPS route to the HQ of the loaded level; false when the level has none or there is no player vehicle.
local function routeToHq()
  local site = currentSite()
  if not site or not freeroam_bigMapMode or not getPlayerVehicle(0) then return false end
  freeroam_bigMapMode.setNavFocus(vec3(site.pos[1], site.pos[2], site.pos[3]))
  return true
end

local function onGetRawPoiListForLevel(levelIdentifier, elements)
  local site = sites[levelIdentifier]
  if not site or not beamazon_adapter.isCareerActive() then return end
  local areaName, iconName = objectNames(site)
  local pos = ensureObjects(site)
  table.insert(elements, {
    id = site.id,
    data = {type = poiType, siteId = site.id, name = site.name},
    markerInfo = {
      walkingMarker = {doors = {{areaName, iconName}}, icon = 'poi_laptop_round', pos = pos, radius = 6, iconLift = 0.2, iconOffsetHeight = 0.15},
      bigmapMarker = {pos = pos, icon = 'poi_laptop_round', name = site.name, description = 'Found your delivery company here.', cardIcon = 'laptop'},
    },
  })
end

local function money(amount)
  return '$' .. tostring(math.floor(amount)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

-- The accept card for the HQ: buy it, or what the company has once it's owned.
local function buildCard(elem)
  local card = {
    icon = 'poi_laptop_round',
    heading = elem.name,
    preheadings = {'Delivery company'},
    sorting = {type = elem.type, id = elem.siteId},
    buttonSoundClass = 'bng_hover_generic',
  }
  if beamazon_fleetManager.ownsHq() then
    card.props = {
      {icon = 'checkmark', keyLabel = 'Your company headquarters'},
      {icon = 'checkmark', keyLabel = 'Fleet slots', valueLabel = tostring(balance.hqSlots)},
      {icon = 'checkmark', keyLabel = 'Vans', valueLabel = string.format('%d / %d', #beamazon_fleetManager.getVans(), beamazon_fleetManager.getVanLimit())},
    }
    card.buttonLabel = 'Open the phone'
    card.buttonFun = function() beamazon_adapter.openPhone() end
    return card
  end

  local level = beamazon_adapter.getLogisticsLevel()
  card.props = {
    {icon = 'checkmark', keyLabel = 'Price', valueLabel = money(balance.hqPrice)},
    {icon = 'checkmark', keyLabel = 'Logistics level', valueLabel = string.format('%d required (yours: %d)', balance.hqUnlockLevel, level)},
    {icon = 'checkmark', keyLabel = 'Fleet slots', valueLabel = tostring(balance.hqSlots)},
  }
  card.buttonLabel = 'Buy the company'
  if level < balance.hqUnlockLevel then
    card.disabled = true
    card.disableReason = string.format('Reach Logistics level %d first', balance.hqUnlockLevel)
  elseif (beamazon_adapter.getMoney() or 0) < balance.hqPrice then
    card.disabled = true
    card.disableReason = 'Not enough money'
  end
  card.buttonFun = function()
    local ok = beamazon_fleetManager.buyHq()
    guihooks.trigger('toastrMsg', ok
      and {type = 'success', title = 'Beamazon', msg = 'Company founded: +' .. balance.hqSlots .. ' fleet slots.'}
      or {type = 'warning', title = 'Beamazon', msg = 'Could not buy the company.'})
  end
  return card
end

local function onActivityAcceptGatherData(elemData, activityData)
  for _, elem in ipairs(elemData) do
    if elem.type == poiType and beamazon_fleetManager.ensureLoaded() then
      table.insert(activityData, buildCard(elem))
    end
  end
end

-- The HQ marker exists only while a career runs, so the POI list is rebuilt when one starts or stops.
local function onBeamazonCareerActive()
  if gameplay_rawPois then gameplay_rawPois.clear() end
end

local function onExtensionLoaded()
  if gameplay_rawPois then gameplay_rawPois.clear() end
end

M.buildCard = buildCard
M.hasSite = function() return currentSite() ~= nil end
M.routeToHq = routeToHq
M.onGetRawPoiListForLevel = onGetRawPoiListForLevel
M.onActivityAcceptGatherData = onActivityAcceptGatherData
M.onBeamazonCareerActive = onBeamazonCareerActive
M.onExtensionLoaded = onExtensionLoaded

return M
