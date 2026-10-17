// node tools/screenshots/shots.js
//
// Plays practice mode headless (shots.lua on tests/mock.lua), then draws what the
// addon showed at a few moments as HTML and photographs it with Chromium into
// assets/screenshots/. The layout follows Hud.lua and UI.lua (sizes, offsets,
// colours, the tick layout); fonts, textures and spell icons are stand-ins, since
// the game's own files aren't available outside the game.
const fs = require('fs'), path = require('path'), os = require('os');
const { execFileSync } = require('child_process');
const { lua, lauxlib, lualib, to_luastring } = require(path.join(__dirname, '../../tests/node_modules/fengari'));

const root = path.join(__dirname, '../..');
const out = path.join(root, 'assets/screenshots');
const chromium = process.env.CHROMIUM || '/opt/pw-browsers/chromium';

// ---------------------------------------------------------------- run the addon
const toc = fs.readFileSync(path.join(root, 'Krakenrage.toc'), 'utf8').split(/\r?\n/).filter(l => l.trim() && !l.startsWith('#'));
const longString = s => { let eq = ''; while (s.includes(']' + eq + ']')) eq += '='; return '[' + eq + '[\n' + s + ']' + eq + ']'; };
let src = 'TOC = {' + toc.map(f => JSON.stringify(f)).join(',') + '}\nFILES = {}\n';
for (const f of toc) src += 'FILES[' + JSON.stringify(f) + '] = ' + longString(fs.readFileSync(path.join(root, f), 'utf8')) + '\n';
src += fs.readFileSync(path.join(root, 'tests/mock.lua'), 'utf8') + '\n';
src += 'function DEFAULT_CHAT_FRAME:AddMessage() end\n'; // quiet
src += fs.readFileSync(path.join(__dirname, 'shots.lua'), 'utf8');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring('=shots')) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
  console.error('LUA ERROR:', lua.lua_tojsstring(L, -1));
  process.exit(1);
}
lua.lua_getglobal(L, to_luastring('SHOT_JSON'));
const data = JSON.parse(lua.lua_tojsstring(L, -1));
if (data.errors) { console.error('the addon raised errors while playing'); process.exit(1); }
for (const k of ['op', 'ex', 'full', 'hs']) if (!data.hud[k]) console.warn('no moment found for', k);

// ---------------------------------------------------------------- look
const C = {
  gold: '#ffd100', dim: '#c7b899', faint: '#807561', text: '#fff', good: '#5cdb78', warn: '#f2b84d', bad: '#ff5c4d',
  stone: 'rgba(26,23,20,.92)',
};
// stand-in icons: a tinted tile with the ability's short name
const TINT = {
  hs: ['#e0892b', '#6b2f07'], cleave: ['#d9a23a', '#5e3a0a'], execute: ['#d6342b', '#4a0805'], ms: ['#b52222', '#3d0606'],
  sunder: ['#a87a4f', '#3b2615'], overpower: ['#e8c547', '#6a4f0b'], revenge: ['#4f8fd6', '#13305a'], rend: ['#8f2d2d', '#2c0b0b'],
  hamstring: ['#7aa35a', '#25391a'], tclap: ['#5aa6c9', '#163a4a'], shout: ['#e3b23c', '#5c3c08'], demo: ['#9b6bd1', '#33204d'],
  pummel: ['#9a9a9a', '#333'], intercept: ['#c96f3a', '#4a2310'],
  battle: ['#d9483b', '#4d0f0a'], defensive: ['#5a8fd1', '#14294d'], berserker: ['#e07a2b', '#562508'],
};
const STANCE_SHORT = { battle: 'Bat', defensive: 'Def', berserker: 'Ber' };
function icon(key, short, size, { dim = false, glow = false, top = false } = {}) {
  const [a, b] = TINT[key] || ['#888', '#333'];
  const fsz = Math.max(7, Math.round(size * (short.length > 2 ? 0.32 : 0.42)));
  return `<div class="icon" style="width:${size}px;height:${size}px;background:radial-gradient(circle at 35% 30%, ${a}, ${b});
    ${dim ? 'filter:grayscale(1);opacity:.45;' : ''}${glow ? `box-shadow:0 0 ${size * .35}px ${size * .12}px rgba(255,209,0,.85);` : ''}">
    <span style="font-size:${fsz}px;${top ? 'align-self:flex-start;margin-top:2px' : ''}">${short}</span></div>`;
}
const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;');

const CSS = `
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Carlito', 'Liberation Sans', sans-serif; color: #fff; }
.scene { position: relative; overflow: hidden;
  background: radial-gradient(ellipse at 50% 120%, #3c4a2c 0%, #1f2a1d 35%, #121722 70%, #0b0d14 100%); }
.scene::before { content: ''; position: absolute; inset: 0; opacity: .35;
  background: radial-gradient(circle at 20% 30%, rgba(255,255,255,.06), transparent 40%), radial-gradient(circle at 80% 70%, rgba(0,0,0,.4), transparent 50%); }
.icon { position: absolute; border: 1px solid #ffd100; display: flex; align-items: center; justify-content: center; }
.icon span { font-weight: 700; color: rgba(255,255,255,.92); text-shadow: 0 1px 1px #000, 0 0 2px #000; letter-spacing: -.2px; }
.thin { position: absolute; background: ${C.stone}; border: 2px solid rgba(255,209,0,.85); border-radius: 3px;
  box-shadow: inset 0 0 0 1px rgba(0,0,0,.6), 0 2px 8px rgba(0,0,0,.6); }
.out { text-shadow: -1px -1px 0 #000, 1px -1px 0 #000, -1px 1px 0 #000, 1px 1px 0 #000; }
.dialog { position: absolute; border: 10px solid; border-image: linear-gradient(180deg, #f5d77a, #c99a2e 45%, #7a5714) 1;
  background: #3b342d url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2'/><feColorMatrix values='0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 .55 0'/></filter><rect width='160' height='160' filter='url(%23n)'/></svg>");
  box-shadow: 0 0 0 2px #120e09, 0 10px 30px rgba(0,0,0,.7), inset 0 0 40px rgba(0,0,0,.55); }
.title { font-family: 'Caladea', 'Bitstream Charter', serif; color: ${C.gold}; text-shadow: 1px 1px 1px #000; }
.t { position: absolute; white-space: pre; text-shadow: 1px -1px 0 rgba(0,0,0,.8); }
.wrap { white-space: pre-wrap; line-height: 1.25; }
.flow { position: relative; white-space: pre; text-shadow: 1px -1px 0 rgba(0,0,0,.8); }
.flow.wrap { white-space: pre-wrap; }
.check { position: absolute; width: 16px; height: 16px; border: 1px solid #8a7a50; background: #1a1612; border-radius: 2px; }
.check.on::after { content: ''; position: absolute; left: 4px; top: 0px; width: 5px; height: 10px; border: solid ${C.gold}; border-width: 0 3px 3px 0; transform: rotate(40deg); }
.caption { position: absolute; left: 0; right: 0; bottom: 10px; text-align: center; font-size: 14px; color: #c7b899; text-shadow: 0 1px 2px #000; }
`;

// ---------------------------------------------------------------- the rage bar (Hud.lua)
const BAR_W = 240, BAR_H = 18, TICK_ICON = 15, SWING_H = 4, PROC = 34;
function hudHTML(h) {
  const max = h.max || 100, rage = h.rage || 0;
  let s = '';
  // frame around the bar (ThinFrame, 4px out)
  s += `<div class="thin" style="left:-4px;top:-4px;width:${BAR_W + 8}px;height:${BAR_H + 8}px"></div>`;
  const fill = BAR_W * Math.min(1, rage / max);
  s += `<div style="position:absolute;left:0;top:0;width:${fill}px;height:${BAR_H}px;background:linear-gradient(180deg,#e33a2a 0%,#c71f17 45%,#8a100c 100%)"></div>`;
  s += `<div style="position:absolute;left:0;top:0;width:${BAR_W}px;height:${BAR_H / 2}px;background:rgba(255,255,255,.06)"></div>`;
  if (h.keep > 0) s += `<div style="position:absolute;left:${BAR_W * h.keep / max}px;top:0;width:1px;height:${BAR_H}px;background:rgba(255,255,255,.35)"></div>`;
  // ticks: one line per cost, icons above, rows when they'd overlap (BuildTicks)
  const rows = [];
  for (const g of h.ticks) {
    const x = BAR_W * Math.min(1, g.cost / max);
    const afford = rage >= g.cost;
    s += `<div style="position:absolute;left:${x - 1}px;top:0;width:2px;height:${BAR_H}px;background:${afford ? 'rgba(255,209,0,.9)' : 'rgba(0,0,0,.7)'}"></div>`;
    const w = g.icons.length * (TICK_ICON + 1) - 1;
    const left = Math.max(-TICK_ICON / 2, Math.min(BAR_W - w + TICK_ICON / 2, x - w / 2));
    let row = 0;
    while (rows[row] !== undefined && rows[row] > left - 1) row++;
    rows[row] = left + w;
    g.icons.forEach((ic, i) => {
      const bottom = 5 + row * (TICK_ICON + 2);
      s += `<div style="position:absolute;left:${left + i * (TICK_ICON + 1)}px;top:${-bottom - TICK_ICON}px">${icon(ic.key, ic.short, TICK_ICON, { dim: !ic.ready, glow: ic.queued })}</div>`;
    });
  }
  if (rage > 0) s += `<div class="t out" style="left:0;width:${BAR_W}px;top:2px;text-align:center;font-size:12px;font-weight:700">${rage}</div>`;
  // stance icon, left
  if (h.stance) s += `<div style="position:absolute;left:${-8 - (BAR_H + 8)}px;top:-4px">${icon(h.stance, STANCE_SHORT[h.stance], BAR_H + 8)}</div>`;
  // switch cost, right
  if (h.swap) s += `<div class="t out" style="left:${BAR_W + 8}px;top:2px;font-size:11px;font-weight:700;color:${h.swap >= 20 ? C.bad : C.dim}">-${h.swap} on switch</div>`;
  // swing timer
  if (h.swing !== undefined) {
    const col = { gold: C.gold, warn: C.warn, bad: C.bad }[h.swingColor];
    s += `<div style="position:absolute;left:0;top:${BAR_H + 5}px;width:${BAR_W}px;height:${SWING_H}px;background:rgba(0,0,0,.6)"></div>`;
    s += `<div style="position:absolute;left:0;top:${BAR_H + 5}px;width:${BAR_W * h.swing}px;height:${SWING_H}px;background:${col}"></div>`;
  }
  // proc alerts, centred under the bar
  const total = h.procs.length * (PROC + 10) - 10;
  h.procs.forEach((p, i) => {
    const x = BAR_W / 2 - total / 2 + i * (PROC + 10), y = BAR_H + SWING_H + 12;
    const key = p.kind === 'ex' ? 'execute' : 'overpower';
    s += `<div style="position:absolute;left:${x}px;top:${y}px">${icon(key, p.kind === 'ex' ? 'Ex' : 'OP', PROC, { glow: true, top: p.left !== undefined })}</div>`;
    if (p.left !== undefined) s += `<div class="t out" style="left:${x}px;width:${PROC}px;top:${y + PROC - 17}px;text-align:center;font-size:14px;font-weight:700">${p.left.toFixed(1)}</div>`;
    s += `<div class="t out" style="left:${x - 20}px;width:${PROC + 40}px;top:${y + PROC + 3}px;text-align:center;font-size:10px;color:${C.gold}">${p.label}</div>`;
  });
  return `<div style="position:absolute;left:0;top:0;width:${BAR_W}px;height:${BAR_H}px">${s}</div>`;
}

// a target frame, so the bar has its moment around it
function targetHTML(name, hp) {
  return `<div class="thin" style="left:0;top:0;width:200px;height:34px"></div>
    <div class="t" style="left:8px;top:3px;font-size:12px;color:${C.gold}">${esc(name)}</div>
    <div style="position:absolute;left:8px;top:19px;width:184px;height:9px;background:rgba(0,0,0,.6)"></div>
    <div style="position:absolute;left:8px;top:19px;width:${184 * hp / 100}px;height:9px;background:linear-gradient(180deg,#3ad13a,#167a16)"></div>
    <div class="t out" style="left:8px;width:184px;top:16px;text-align:center;font-size:10px">${Math.round(hp)}%</div>`;
}

function hudScene(h, caption, scale = 2) {
  const W = 760, H = 400;
  return { w: W, h: H, html: `<div class="scene" style="width:${W}px;height:${H}px">
    ${h.target ? `<div style="position:absolute;left:${W / 2 - 100}px;top:24px;transform:scale(1.3);transform-origin:top center">${targetHTML(h.target, h.hp ?? 100)}</div>` : ''}
    <div style="position:absolute;left:${W / 2 - BAR_W * scale / 2 - 30}px;top:170px;transform:scale(${scale});transform-origin:top left">${hudHTML(h)}</div>
    <div class="caption">${caption}</div></div>` };
}

// ---------------------------------------------------------------- the coach window (UI.lua)
const WIDTH = 440, HEIGHT = 580, PAD = 18, INNER = WIDTH - PAD * 2, TOP = 66;
function windowHTML(page, body) {
  const tabs = [['fight', 'Last fight'], ['history', 'History'], ['bar', 'Rage bar']];
  let x = PAD - 8, t = '';
  for (const [id, label] of tabs) {
    const w = Math.max(40, label.length * 6.6 + 16);
    t += `<div class="t" style="left:${x}px;top:34px;width:${w}px;height:22px;line-height:22px;text-align:center;font-size:12px;color:${id === page ? C.gold : C.dim};${id === page ? 'background:rgba(255,209,0,.10)' : ''}">${label}</div>`;
    x += w + 4;
  }
  return `<div class="dialog" style="left:-7px;top:-7px;width:${WIDTH + 14}px;height:${HEIGHT + 14}px"></div>
    <div style="position:absolute;left:2px;right:2px;top:2px;height:26px;background:rgba(0,0,0,.45)"></div>
    <div class="t title" style="left:${PAD}px;top:5px;font-size:19px">Krakenrage</div>
    <div class="t" style="left:${PAD + 104}px;top:11px;font-size:11px;color:${C.dim}">the warrior's coach</div>
    <div class="t" style="right:8px;top:4px;font-size:16px;color:${C.dim};font-weight:700">✕</div>
    ${t}
    <div style="position:absolute;left:${PAD}px;right:${PAD}px;top:${TOP - 6}px;height:1px;background:rgba(255,209,0,.22)"></div>
    <div style="position:absolute;left:${PAD}px;top:${TOP}px;width:${INNER}px;height:${HEIGHT - TOP - PAD}px">${body}</div>`;
}

const gradeColor = s => s == null ? C.dim : s >= 85 ? C.good : s >= 70 ? C.gold : s >= 55 ? C.warn : C.bad;
const CLS = { elite: 'Elite', rareelite: 'Rare elite', rare: 'Rare', worldboss: 'Boss' };

// the page is a column of lines, each under the one before (UI:RenderFight), so it flows
function fightPage(f) {
  let s = '';
  const line = (html, size, color, gap, wrap, extra = '') => {
    s += `<div class="flow ${wrap ? 'wrap' : ''}" style="width:${INNER}px;font-size:${size}px;line-height:${wrap ? 1.25 : 1.2};color:${color};margin-bottom:${gap}px;${extra}">${html}</div>`;
  };
  let name = esc(f.target);
  if (CLS[f.cls]) name += `&nbsp; <span style="color:${C.warn}">${CLS[f.cls]}</span>`;
  if (f.practice) name += `&nbsp; <span style="color:${C.faint}">practice</span>`;
  line(name, 16, C.gold, 2, false, `width:${INNER - 70}px`);
  line(`${f.dur} &nbsp;·&nbsp; ${f.ago}`, 11, C.dim, 14);
  s += `<div class="t title" style="right:0;top:-6px;font-size:44px;color:${gradeColor(f.score)}">${f.grade}</div>`;
  s += `<div class="t" style="right:0;top:44px;font-size:11px;color:${C.dim}">${f.score} / 100</div>`;
  line('How it went', 13, C.gold, 6);
  for (const p of f.parts) {
    const pct = Math.round(p.value * 100);
    s += `<div class="flow" style="height:15px;margin-bottom:3px;font-size:12px">${p.label}
      <div style="position:absolute;left:160px;top:4px;width:150px;height:6px;background:rgba(0,0,0,.5)"></div>
      <div style="position:absolute;left:160px;top:4px;width:${Math.max(1, 150 * p.value)}px;height:6px;background:${gradeColor(pct)}"></div>
      <div class="t" style="left:318px;top:0;font-size:11px;color:${C.dim}">${pct}%</div></div>`;
  }
  s += '<div style="height:8px"></div>';
  line('The coach says', 13, C.gold, 6);
  for (const tip of f.tips.slice(0, 6)) {
    const col = tip.level === 'good' ? C.good : tip.level === 'warn' ? C.warn : C.bad;
    line(`<span style="color:${col};font-weight:700">${tip.level === 'good' ? '+' : '!'}</span>&nbsp; ${esc(tip.text)}`, 12, C.text, 6, true);
  }
  s += '<div style="height:6px"></div>';
  line('Rage went into', 13, C.gold, 4);
  line(esc(f.spent), 11, C.dim, 10, true);
  line('Stances', 13, C.gold, 4);
  line(esc(f.stances), 11, C.dim, 0, true);
  return s;
}

function historyPage(d) {
  let s = `<div class="t" style="left:0;top:0;font-size:13px;color:${C.gold}">${d.total > 10 ? 'Your last 10 fights, against the 10 before' : 'Your fights so far'}</div>`;
  const fmt = (f, v) => (f.includes('%d') ? f.replace('%d', Math.round(v)) : f.replace('%.1f', v.toFixed(1))).replace('%%', '%');
  d.trends.forEach((tr, i) => {
    const y = 20 + i * 17;
    const word = tr.better === true ? `<span style="color:${C.good}">better</span>` : tr.better === false ? `<span style="color:${C.bad}">worse</span>` : 'same';
    s += `<div class="t" style="left:0;top:${y}px;font-size:12px">${tr.label}</div>
      <div class="t" style="left:190px;width:70px;text-align:right;top:${y}px;font-size:12px">${fmt(tr.fmt, tr.now)}</div>
      <div class="t" style="left:270px;top:${y}px;font-size:11px;color:${C.dim}">${tr.before != null ? `${word} (was ${fmt(tr.fmt, tr.before)})` : ''}</div>`;
  });
  const listTop = 20 + 5 * 17 + 14;
  s += `<div class="t" style="left:0;top:${listTop}px;font-size:13px;color:${C.gold}">Recent fights (${d.total} kept)</div>`;
  d.history.forEach((r, i) => {
    const y = listTop + 20 + i * 20;
    let name = esc(r.target);
    if (CLS[r.cls]) name += ` <span style="color:${C.warn}">(${CLS[r.cls]})</span>`;
    if (r.practice) name += ` <span style="color:${C.faint}">practice</span>`;
    s += `${i === 1 ? `<div style="position:absolute;left:0;top:${y}px;width:${INNER}px;height:20px;background:rgba(255,209,0,.10)"></div>` : ''}
      <div class="t title" style="left:4px;top:${y + 1}px;font-size:15px;color:${gradeColor(r.score)}">${r.grade}</div>
      <div class="t" style="left:30px;top:${y + 3}px;font-size:12px">${name}</div>
      <div class="t" style="left:250px;width:46px;text-align:right;top:${y + 4}px;font-size:11px;color:${C.dim}">${r.dur}</div>
      <div class="t" style="right:4px;top:${y + 4}px;font-size:11px;color:${C.dim}">${r.ago}</div>`;
  });
  return s;
}

function barPage(d) {
  const st = d.settings;
  const opts = [['Lock the bar', st.locked], ['Swing timer (experimental)', st.swing], ['Overpower, Revenge and Execute alerts', st.procs],
    ['Stance and what a switch costs', st.stance], ['Dim out of combat', st.fade], ['A note after each fight', st.toasts], ['Minimap button', st.minimap]];
  let s = `<div class="t" style="left:0;top:0;font-size:13px;color:${C.gold}">The bar</div>`;
  opts.forEach(([label, on], i) => {
    const x = 0, y = 22 + i * 22;
    s += `<div class="check ${on ? 'on' : ''}" style="left:${x}px;top:${y}px"></div><div class="t" style="left:${x + 22}px;top:${y + 1}px;font-size:12px">${label}</div>`;
  });
  const tickTop = 20 + opts.length * 22 + 14;
  s += `<div class="t" style="left:0;top:${tickTop}px;font-size:13px;color:${C.gold}">Ticks on the bar</div>
    <div class="t" style="left:0;top:${tickTop + 18}px;font-size:11px;color:${C.dim}">Abilities you know, at their real rage cost.</div>`;
  d.abilities.forEach((a, i) => {
    const x = i % 2 === 0 ? 0 : INNER / 2, y = tickTop + 40 + Math.floor(i / 2) * 22;
    s += `<div class="check ${a.on ? 'on' : ''}" style="left:${x}px;top:${y}px"></div>
      <div style="position:absolute;left:${x + 22}px;top:${y}px">${icon(a.key, a.short, 16)}</div>
      <div class="t" style="left:${x + 44}px;top:${y + 1}px;font-size:12px">${esc(a.name)} &nbsp;<span style="color:#b8ad99">${a.cost}</span></div>`;
  });
  return s;
}

function windowScene(page, body, caption) {
  const W = WIDTH + 120, H = HEIGHT + 110;
  return { w: W, h: H, html: `<div class="scene" style="width:${W}px;height:${H}px">
    <div style="position:absolute;left:60px;top:36px;width:${WIDTH}px;height:${HEIGHT}px">${windowHTML(page, body)}</div>
    <div class="caption">${caption}</div></div>` };
}

function toastScene(t, h) {
  const W = 760, H = 400, scale = 2;
  const grade = t.grade, col = gradeColor(data.fight && data.fight.grade === grade ? data.fight.score : 60);
  return { w: W, h: H, html: `<div class="scene" style="width:${W}px;height:${H}px">
    <div style="position:absolute;left:${W / 2 - 150 * 1.6}px;top:30px;transform:scale(1.6);transform-origin:top left">
      <div class="thin" style="left:0;top:0;width:300px;height:48px"></div>
      <div class="t title" style="left:12px;top:8px;font-size:28px;color:${col}">${esc(grade)}</div>
      <div class="t" style="left:48px;top:8px;font-size:12px;color:${C.gold}">${esc(t.title)}</div>
      <div class="t" style="left:48px;top:26px;font-size:11px;color:${C.dim}">${esc(t.text)}</div>
    </div>
    <div style="position:absolute;left:${W / 2 - BAR_W * scale / 2 - 30}px;top:240px;transform:scale(${scale});transform-origin:top left;opacity:.35">${hudHTML({ ...h, procs: [], swing: undefined, swap: null })}</div>
    <div class="caption">After the fight: a short note above the bar. Click it to open the coach.</div></div>` };
}

// ---------------------------------------------------------------- photograph
const scenes = [];
const H = data.hud;
if (H.op) scenes.push(['1-rage-bar-overpower', hudScene(H.op, 'The target dodged: Overpower lights up with its 5-second countdown. Each icon sits at its rage cost; lit = affordable, right stance, ready.')]);
if (H.hs) scenes.push(['2-rage-bar-heroic-strike', hudScene(H.hs, 'Heroic Strike queued (glow). The swing timer turns amber, red if it would leave too little rage for Mortal Strike.')]);
if (H.full) scenes.push(['3-rage-bar-full', hudScene(H.full, 'Rage capped at 100. Right of the bar: what a stance switch would cost right now.')]);
if (H.ex) scenes.push(['4-rage-bar-execute', hudScene(H.ex, 'Target below 20%: the Execute alert.')]);
if (data.toast) scenes.push(['5-after-fight-note', toastScene(data.toast, H.op || H.ex)]);
if (data.fight) scenes.push(['6-coach-last-fight', windowScene('fight', fightPage(data.fight), 'The coach grades the fight and says what to work on, worst first.')]);
scenes.push(['7-coach-history', windowScene('history', historyPage(data), 'History: trends over your last fights, and every fight to open again.')]);
scenes.push(['8-coach-rage-bar-settings', windowScene('bar', barPage(data), 'The bar\'s settings, and which abilities get a tick.')]);

fs.mkdirSync(out, { recursive: true });
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'krshots-'));
for (const [name, sc] of scenes) {
  const html = path.join(tmp, name + '.html');
  fs.writeFileSync(html, `<!doctype html><html><head><meta charset="utf-8"><style>${CSS}</style></head><body>${sc.html}</body></html>`);
  const raw = path.join(tmp, name + '.png');
  execFileSync(chromium, ['--headless', '--no-sandbox', '--disable-gpu', '--hide-scrollbars', `--window-size=${sc.w},${sc.h + 200}`,
    '--force-device-scale-factor=1', `--screenshot=${raw}`, 'file://' + html], { stdio: 'ignore' });
  // crop the extra height Chromium needs for its own frame
  execFileSync('python3', ['-c', `from PIL import Image; Image.open(r'${raw}').crop((0,0,${sc.w},${sc.h})).save(r'${path.join(out, name + '.png')}')`]);
  console.log('wrote', path.relative(root, path.join(out, name + '.png')));
}
fs.writeFileSync(path.join(tmp, 'data.json'), JSON.stringify(data, null, 1));
console.log('state used:', path.join(tmp, 'data.json'));
