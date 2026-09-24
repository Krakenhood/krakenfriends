const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const dir = path.join(__dirname, '..');
const toc = fs.readFileSync(path.join(dir, 'Krakenfriends.toc'), 'utf8').split(/\r?\n/).filter(l => l.trim() && !l.startsWith('#'));

function longString(s) {
  let eq = '';
  while (s.includes(']' + eq + ']')) eq += '=';
  return '[' + eq + '[\n' + s + ']' + eq + ']';
}
let prelude = 'TOC = {' + toc.map(f => JSON.stringify(f)).join(',') + '}\nFILES = {}\n';
for (const f of toc) prelude += 'FILES[' + JSON.stringify(f) + '] = ' + longString(fs.readFileSync(path.join(dir, f), 'utf8')) + '\n';

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const src = prelude + fs.readFileSync(path.join(__dirname, 'mock.lua'), 'utf8') + '\n' + fs.readFileSync(path.join(__dirname, 'driver.lua'), 'utf8');
if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring('=test')) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
  console.error('LUA ERROR:', lua.lua_tojsstring(L, -1));
  process.exit(1);
}
