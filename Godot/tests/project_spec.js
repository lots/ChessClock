#!/usr/bin/env node
'use strict';
/**
 * project_spec.js — 静态一致性检查：Godot 版 ↔ 网页版（HTML5 原版）
 *
 *     node tests/project_spec.js
 *
 * 这个移植最容易出的问题不是「写不出来」，而是**两版慢慢漂移**：
 * 词条少了一句、预设少了一档、某个色值抄错、资源路径写错。
 * 所以这里把 Godot 版的关键数据（由 tests/dump_spec.gd 导出成 JSON）与
 * 网页版的 engine.js / i18n.js / app.js / styles.css 逐个比对：
 *
 *   1. 计时引擎的 8 个常量 + 4 个模式名 + 模式标签
 *   2. 双语文案表（key 集合与每个值，逐条比对；允许原生版多出确认框文案）
 *   3. 预设档位（棋类 11 档 / 读秒 8 档：baseMin / incSec / periods / sub / name）
 *   4. 预设按钮上的记法（10+5 / 10+3×20）
 *   5. 默认设置（10 个字段）
 *   6. 三套主题的色值（与 styles.css 的 CSS 变量逐个比对）
 *   7. 工程文件与资源引用是否都存在（project.godot / main.tscn / 图标 / 音效）
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const WEB = path.join(ROOT, '..');           // ChessClock/（网页版）
const DUMP_PATH = path.join(ROOT, 'tests', 'out', 'spec_dump.json');

let passed = 0;
const failures = [];

function ok(cond, msg) {
  if (cond) { passed += 1; } else { failures.push(msg); }
}
function eq(actual, expected, msg) {
  if (actual === expected) { passed += 1; }
  else { failures.push(msg + ' —— 期望 ' + JSON.stringify(expected) + '，实际 ' + JSON.stringify(actual)); }
}

function readText(file) { return fs.readFileSync(file, 'utf8'); }
function exists(rel) { return fs.existsSync(path.join(ROOT, rel)); }

/* ===================== 解析网页版 ===================== */

/** 从 app.js 里把 `var NAME = [ {...}, ... ];` 解析成对象数组 */
function parsePresetArray(source, varName) {
  const start = source.indexOf('var ' + varName + ' = [');
  if (start < 0) { return null; }
  const end = source.indexOf('];', start);
  const body = source.slice(start, end);
  const entries = [];
  const re = /\{([^}]+)\}/g;
  let m;
  while ((m = re.exec(body)) !== null) {
    const b = m[1];
    const str = (k) => {
      const r = b.match(new RegExp(k + ":\\s*'([^']*)'"));
      return r ? r[1] : null;
    };
    const num = (k) => {
      const r = b.match(new RegExp(k + ':\\s*(\\d+)'));
      return r ? Number(r[1]) : null;
    };
    entries.push({
      id: str('id'), baseMin: num('baseMin'), incSec: num('incSec'),
      periods: num('periods'), sub: str('sub'), name: str('name'),
    });
  }
  return entries;
}

/** 网页版预设按钮上的记法（app.js 的 presetLabel） */
function webPresetLabel(p) {
  return p.periods
    ? p.baseMin + '+' + p.periods + '×' + p.incSec
    : p.baseMin + '+' + p.incSec;
}

/** 从 app.js 里解析 DEFAULTS */
function parseDefaults(source) {
  const start = source.indexOf('var DEFAULTS = {');
  const end = source.indexOf('};', start);
  const body = source.slice(start, end);
  const out = {};
  for (const line of body.split('\n')) {
    const m = line.match(/^\s*(\w+):\s*(.+?),(\s*\/\/.*)?$/);
    if (!m) { continue; }
    const raw = m[2].trim();
    if (raw === 'true' || raw === 'false') { out[m[1]] = raw === 'true'; }
    else if (raw === 'null') { out[m[1]] = null; }
    else if (/^-?\d+(\.\d+)?$/.test(raw)) { out[m[1]] = Number(raw); }
    else { out[m[1]] = raw.replace(/^'/, '').replace(/'$/, ''); }
  }
  return out;
}

/** 从 styles.css 里把三套主题的 CSS 变量解析出来 */
function parseCssThemes(source) {
  const blocks = {
    dark: /:root,\s*:root\[data-theme="dark"\]\s*\{([\s\S]*?)\n\}/,
    medium: /:root\[data-theme="medium"\]\s*\{([\s\S]*?)\n\}/,
    light: /:root\[data-theme="light"\]\s*\{([\s\S]*?)\n\}/,
  };
  const out = {};
  for (const name of Object.keys(blocks)) {
    const m = source.match(blocks[name]);
    const vars = {};
    if (m) {
      for (const line of m[1].split('\n')) {
        const v = line.match(/^\s*--([\w-]+):\s*([^;]+);/);
        if (v) { vars[v[1]] = v[2].trim(); }
      }
    }
    out[name] = vars;
  }
  return out;
}

/* ===================== 读 Godot 版导出的数据 ===================== */

if (!fs.existsSync(DUMP_PATH)) {
  console.error('缺少 ' + path.relative(ROOT, DUMP_PATH) + '。');
  console.error('请先运行：powershell -ExecutionPolicy Bypass -File tests/run_tests.ps1');
  console.error('（或单独跑：godot --headless --path . --script res://tests/dump_spec.gd）');
  process.exit(2);
}
const dump = JSON.parse(fs.readFileSync(DUMP_PATH, 'utf8'));

const webEngine = require(path.join(WEB, 'engine.js'));
const webI18n = require(path.join(WEB, 'i18n.js'));
const webAppSource = readText(path.join(WEB, 'app.js'));
const webCssSource = readText(path.join(WEB, 'styles.css'));

/* ===================== 1. 计时引擎常量 ===================== */

const engineKeys = [
  'LOW_TIME_MS', 'CRITICAL_TIME_MS', 'MIN_PRESS_GAP_MS',
  'MIN_BASE_MS', 'MAX_BASE_MS', 'MAX_ADD_MS', 'MIN_BYOYOMI_MS', 'MAX_PERIODS',
];
for (const key of engineKeys) {
  eq(dump.engine[key], webEngine[key], 'engine.gd 的常量 ' + key);
}
for (const key of Object.keys(webEngine.MODES)) {
  eq(dump.engine.MODES[key], webEngine.MODES[key], 'engine.gd 的模式 ' + key);
}
eq(JSON.stringify(dump.engine.SIDES), JSON.stringify(webEngine.SIDES), 'engine.gd 的 SIDES');
for (const key of Object.keys(webEngine.MODE_LABELS)) {
  eq(dump.engine.MODE_LABELS[key], webEngine.MODE_LABELS[key], 'engine.gd 的模式标签 ' + key);
}

/* ===================== 2. 双语文案 ===================== */

// 原生版独有的词条：只有确认框那两枚按钮（网页版用的是浏览器自带 confirm）
const NATIVE_ONLY = ['confirm.yes', 'confirm.no'];
for (const lang of webI18n.LANGS) {
  const web = webI18n.DICT[lang];
  const godot = dump.i18n[lang];
  ok(!!godot, 'i18n.gd 缺少语言 ' + lang);
  if (!godot) { continue; }
  for (const key of Object.keys(web)) {
    if (!(key in godot)) { failures.push('i18n.gd[' + lang + '] 缺少词条 ' + key); continue; }
    eq(godot[key], web[key], 'i18n.gd[' + lang + '][' + key + ']');
  }
  const extra = Object.keys(godot).filter((k) => !(k in web) && !NATIVE_ONLY.includes(k));
  ok(extra.length === 0, 'i18n.gd[' + lang + '] 多出奇怪词条：' + extra.join(', '));
  for (const key of NATIVE_ONLY) {
    ok(key in godot, 'i18n.gd[' + lang + '] 缺少原生版词条 ' + key);
  }
}
eq(JSON.stringify(dump.langs), JSON.stringify(webI18n.LANGS), 'i18n.gd 的语言列表');

/* ===================== 3. 预设档位 ===================== */

const webChess = parsePresetArray(webAppSource, 'PRESETS_CHESS');
const webByoyomi = parsePresetArray(webAppSource, 'PRESETS_BYOYOMI');
ok(Array.isArray(webChess) && webChess.length === 11, '网页版棋类预设应有 11 档（解析到 ' +
  (webChess ? webChess.length : 'null') + '）');
ok(Array.isArray(webByoyomi) && webByoyomi.length === 8, '网页版读秒预设应有 8 档（解析到 ' +
  (webByoyomi ? webByoyomi.length : 'null') + '）');

function comparePresets(webList, godotList, label) {
  eq(godotList.length, webList.length, label + ' 的档数');
  webList.forEach((w, i) => {
    const g = godotList[i] || {};
    eq(g.id, w.id, label + ' #' + i + ' 的 id');
    eq(Number(g.baseMin), w.baseMin, label + ' #' + i + ' 的 baseMin');
    eq(Number(g.incSec), w.incSec, label + ' #' + i + ' 的 incSec');
    if (w.periods !== null) { eq(Number(g.periods), w.periods, label + ' #' + i + ' 的 periods'); }
    if (w.sub !== null && w.sub !== undefined) { eq(g.sub, w.sub, label + ' #' + i + ' 的 sub'); }
    if (w.name) { eq(g.name, w.name, label + ' #' + i + ' 的文案 key'); }
  });
}
comparePresets(webChess, dump.presets_chess, 'presets.gd 棋类');
comparePresets(webByoyomi, dump.presets_byoyomi, 'presets.gd 读秒');

// 下拉框条目只写主记法：读秒档不带 sub（否则「10+3×20 · 20s × 3」把同样三个数说了两遍），
// 棋类档保留第二段，因为那是档次（Bullet / Blitz / Rapid / Classical）。
const presetsGd = readText(path.join(ROOT, 'logic', 'presets.gd'));
const setupGd = readText(path.join(ROOT, 'ui', 'setup_view.gd'));
const byoyomiBlock = /const BYOYOMI := \[([\s\S]*?)\n\]/.exec(presetsGd);
ok(byoyomiBlock !== null, '找不到 presets.gd 的 BYOYOMI 表');
if (byoyomiBlock) {
  ok(!/"sub"/.test(byoyomiBlock[1]), '读秒预设不应再有 sub 字段（下拉框只写主记法）');
}
ok(/"name": "preset\./.test(presetsGd.split('const BYOYOMI')[0]),
  '棋类预设应保留档次名（Bullet / Blitz / Rapid / Classical）');
ok(/if extra == "":\s*\n\s*return ClockPresets\.label\(preset\)/.test(setupGd),
  '没有第二段时，下拉框条目只显示主记法（如 10+3×20）');

/* ===================== 4. 预设记法 ===================== */

eq(JSON.stringify(dump.preset_labels_chess), JSON.stringify(webChess.map(webPresetLabel)),
  'presets.gd 棋类预设的记法（如 10+5）');
eq(JSON.stringify(dump.preset_labels_byoyomi), JSON.stringify(webByoyomi.map(webPresetLabel)),
  'presets.gd 读秒预设的记法（如 10+3×20）');

/* ===================== 5. 默认设置 ===================== */

const webDefaults = parseDefaults(webAppSource);
const defaultKeys = Object.keys(webDefaults);
ok(defaultKeys.length >= 10, '网页版 DEFAULTS 应能解析出至少 10 个字段（解析到 ' + defaultKeys.length + '）');
for (const key of defaultKeys) {
  eq(dump.defaults[key], webDefaults[key], 'settings.gd 的默认值 ' + key);
}

/* ===================== 6. 三套主题的色值 ===================== */

const cssThemes = parseCssThemes(webCssSource);

/** CSS 允许 #000 这种三字符简写，比对前先展开成 #000000 */
function expandHex(value) {
  const v = value.toLowerCase();
  if (/^#[0-9a-f]{3}$/.test(v)) {
    return '#' + v[1] + v[1] + v[2] + v[2] + v[3] + v[3];
  }
  return v;
}

let colorChecks = 0;
for (const themeName of Object.keys(cssThemes)) {
  const css = cssThemes[themeName];
  const godot = dump.themes[themeName];
  ok(!!godot, 'theme.gd 缺少主题 ' + themeName);
  if (!godot) { continue; }
  ok(Object.keys(css).length > 15, 'styles.css 的 ' + themeName + ' 主题变量解析不足（' +
    Object.keys(css).length + ' 个）');
  for (const varName of Object.keys(css)) {
    const value = css[varName];
    if (!/^#[0-9a-fA-F]{3,8}$/.test(value)) { continue; }   // 跳过 54px / rgba() / 999 之类
    const key = varName.replace(/-/g, '_');
    const entry = godot[key];
    if (!entry) { failures.push('theme.gd ' + themeName + ' 缺少颜色 ' + varName); continue; }
    eq(entry.hex.toLowerCase(), expandHex(value), 'theme.gd ' + themeName + '.' + key + '（--' + varName + '）');
    colorChecks += 1;
  }
}
ok(colorChecks >= 60, '三套主题应核对到至少 60 个色值（实际 ' + colorChecks + '）');

eq(JSON.stringify(dump.theme_names), JSON.stringify(['light', 'medium', 'dark']),
  'theme.gd 的主题顺序（与设置页下拉框一致）');

/* ===================== 7. 工程文件与资源引用 ===================== */

const projectFile = readText(path.join(ROOT, 'project.godot'));
const mainScene = (projectFile.match(/run\/main_scene="res:\/\/([^"]+)"/) || [])[1];
ok(!!mainScene, 'project.godot 里应有 run/main_scene');
if (mainScene) { ok(exists(mainScene), '主场景文件不存在：' + mainScene); }

for (const rel of [
  'assets/logo-brand.png', 'assets/logo-strip.png', 'assets/icon.png',
  'assets/icons/sound_on.png', 'assets/icons/sound_off.png',
  'assets/icons/swap.png', 'assets/icons/settings.png', 'assets/icons/fullscreen.png',
  'assets/sounds/click.wav', 'assets/sounds/tick.wav', 'assets/sounds/alarm.wav',
  'logic/engine.gd', 'logic/i18n.gd', 'logic/theme.gd', 'logic/settings.gd', 'logic/presets.gd',
  'ui/main.tscn', 'ui/main.gd', 'ui/setup_view.gd', 'ui/clock_view.gd', 'ui/overlay_view.gd',
]) {
  ok(exists(rel), '缺少文件 ' + rel);
}

// 代码里引用的每个 res:// 资源都要真的存在（拼错路径在运行期只会显示空白）
function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === '.godot' || entry.name === '.userdata' || entry.name === 'build') { continue; }
      walk(full, out);
    } else if (entry.name.endsWith('.gd')) {
      out.push(full);
    }
  }
  return out;
}
let resourceRefs = 0;
for (const file of walk(ROOT, [])) {
  const source = readText(file);
  const re = /"res:\/\/([^"]+)"/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    const rel = m[1];
    if (rel.includes('%')) { continue; }               // 动态拼接的路径单独测
    resourceRefs += 1;
    ok(exists(rel), path.relative(ROOT, file) + ' 引用的 res://' + rel + ' 不存在');
  }
}
ok(resourceRefs >= 8, '应检查到至少 8 处 res:// 资源引用（实际 ' + resourceRefs + '）');

/* ===================== 汇总 ===================== */

console.log('网页版对照检查（' + path.basename(WEB) + ' ↔ Godot/）：');
console.log('  引擎常量 ' + engineKeys.length + ' 个 · 文案 ' +
  (Object.keys(webI18n.DICT.en).length + Object.keys(webI18n.DICT.zh).length) + ' 条 · 预设 ' +
  ((webChess || []).length + (webByoyomi || []).length) + ' 档 · 默认值 ' + defaultKeys.length +
  ' 个 · 色值 ' + colorChecks + ' 个 · 资源 ' + resourceRefs + ' 处');
console.log('  ' + passed + ' 项通过, ' + failures.length + ' 项失败');
if (failures.length > 0) {
  console.log('');
  for (const line of failures) { console.log('  ✗ ' + line); }
  process.exit(1);
}
console.log('RESULT: OK');
