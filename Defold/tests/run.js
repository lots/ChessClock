'use strict';
/**
 * tests/run.js — Defold 版的一键测试入口
 *
 *     node tests/run.js
 *
 * 做两件事：
 *   1) 跑 tests/project_spec.js：资源引用、GUI 字体/贴图名、JS↔Lua 常量一致性等静态校验；
 *   2) 如果本机装了 Lua 5.1+（或 LuaJIT），再跑一遍 logic/engine_spec.lua ——
 *      那是与网页版一一对应的 30 个计时用例。没有 Lua 就跳过并提示。
 *
 * 更强的验证（需要本机装有 Defold）：
 *     powershell -ExecutionPolicy Bypass -File tools/build_and_run.ps1
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert');

const ROOT = path.join(__dirname, '..');

// ---------- 1. 静态校验（require 进来即注册用例） ----------
require('./project_spec.js');

// ---------- 2. 计时引擎单测（Lua） ----------
function findLua() {
  if (process.env.CHESS_LUA) { return process.env.CHESS_LUA; }
  const candidates = [
    'lua', 'lua5.1', 'lua51', 'luajit',
    'C:\\Program Files (x86)\\Lua\\5.1\\lua.exe',
    'C:\\Program Files\\Lua\\5.1\\lua.exe',
    '/usr/bin/lua', '/usr/local/bin/lua', '/opt/homebrew/bin/lua',
  ];
  for (const c of candidates) {
    const res = spawnSync(c, ['-v'], { stdio: 'ignore' });
    if (!res.error && res.status === 0) { return c; }
  }
  return null;
}

const lua = findLua();
if (!lua) {
  test('Lua 计时引擎单测', () => {
    console.log('  [skip] 没找到 Lua 解释器：装上 Lua 5.1+ 后重跑，或用 CHESS_LUA 指定路径');
    assert.ok(true);
  });
} else {
  // stdio: 'inherit' 让 Lua 的输出直接显示，返回值给出成败
  const spec = path.join(ROOT, 'logic', 'engine_spec.lua');
  const res = spawnSync(lua, [spec], { stdio: 'inherit', cwd: ROOT });
  test('Lua 计时引擎单测（logic/engine_spec.lua，与网页版同一套 30 个用例）', () => {
    assert.equal(res.status, 0, 'Lua 单测未通过（见上方输出）');
    assert.ok(fs.existsSync(spec), '缺少 logic/engine_spec.lua');
  });
}
