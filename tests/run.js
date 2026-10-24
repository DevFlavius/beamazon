// Runs a Lua test file with fengari (Lua in JavaScript): no Lua install needed.
// MOD_DIR points the test at this repo's mod/ folder.
const {lua, lauxlib, lualib, to_luastring} = require('fengari');
const fs = require('fs');
const path = require('path');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(path.resolve(__dirname, '../mod')));
lua.lua_setglobal(L, to_luastring('MOD_DIR'));
const file = process.argv[2];
if (lauxlib.luaL_loadbuffer(L, fs.readFileSync(file), null, to_luastring(file)) || lua.lua_pcall(L, 0, 0, 0)) {
  console.error('LUA ERROR:', lua.lua_tojsstring(L, -1));
  process.exit(1);
}
