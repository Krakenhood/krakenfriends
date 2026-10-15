// node compat.js <path to a Krakenfriends.lua SavedVariables file>
// Loads a real save into the current addon code and checks that nothing was lost or changed.
const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const file = process.argv[2];
if (!file) { console.error('usage: node compat.js <path to Krakenfriends.lua>'); process.exit(2); }
const dir = path.join(__dirname, '..');
const toc = fs.readFileSync(path.join(dir, 'Krakenfriends.toc'), 'utf8').split(/\r?\n/).filter(l => l.trim() && !l.startsWith('#'));

function longString(s) {
  let eq = '';
  while (s.includes(']' + eq + ']')) eq += '=';
  return '[' + eq + '[\n' + s + ']' + eq + ']';
}
let prelude = 'TOC = {' + toc.map(f => JSON.stringify(f)).join(',') + '}\nFILES = {}\n';
for (const f of toc) prelude += 'FILES[' + JSON.stringify(f) + '] = ' + longString(fs.readFileSync(path.join(dir, f), 'utf8')) + '\n';
prelude += 'SV_TEXT = ' + longString(fs.readFileSync(file, 'utf8')) + '\n';

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const src = prelude + fs.readFileSync(path.join(__dirname, 'mock.lua'), 'utf8') + '\n' + fs.readFileSync(path.join(__dirname, 'compat.lua'), 'utf8');
if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring('=compat')) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
  console.error('LUA ERROR:', lua.lua_tojsstring(L, -1));
  process.exit(1);
}
