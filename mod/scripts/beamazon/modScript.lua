-- Runs when the mod is activated (core_modmanager executes every scripts/*/modScript.lua).
-- The adapter loads first: the other modules call it.
local modules = {'beamazon_adapter', 'beamazon_fleetEconomy', 'beamazon_fleetManager', 'beamazon_fleetSim', 'beamazon_phoneApp', 'beamazon_hq'}
for _, name in ipairs(modules) do
  setExtensionUnloadMode(name, "manual")
end
for _, name in ipairs(modules) do
  extensions.load(name)
end
