#!/usr/bin/env node
'use strict';
/**
 * export-logo.js —— 把网页版的图标原图栅格化成 Defold 用的位图
 *
 *     node tools/export-logo.js
 *
 * 原图：../assets/logo-source.png（与网页版**同一个源文件**，当前为 TARUMT 校徽）
 * 产出：assets/logo.png（384×384，会被打进 assets/logo.atlas）
 *
 * Defold 的 GUI 只能显示位图贴图，所以位图必须单独导入一次：
 *   原图改了 → 跑本脚本 → 重新编译（tools/build_and_run.ps1 或编辑器 Build & Run）。
 *
 * 界面上两处显示尺寸：设置页 96×96、棋钟操作条 48×48（384 的贴图留了 4 倍余量给高分屏）。
 * 用无头 Chrome/Edge 渲染，不需要安装依赖；也可用 CHROME_PATH 指定浏览器。
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');                       // Defold/
const SOURCE = path.join(ROOT, '..', 'assets', 'logo-source.png'); // 网页版的同一张原图
const PNG_PATH = path.join(ROOT, 'assets', 'logo.png');
const SIZE = 384;   // 显示最大 96×96，4 倍余量给高分屏

function findChrome() {
  if (process.env.CHROME_PATH) { return process.env.CHROME_PATH; }
  const candidates = [
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium'
  ];
  for (const c of candidates) { if (fs.existsSync(c)) { return c; } }
  return null;
}

function main() {
  if (!fs.existsSync(SOURCE)) {
    console.error('找不到原图：' + SOURCE);
    console.error('（它和网页版共用一张图：覆盖 ../assets/logo-source.png 后再跑本脚本）');
    process.exit(1);
  }
  const chrome = findChrome();
  if (!chrome) {
    console.error('没找到 Chrome / Edge，可用 CHROME_PATH 指定浏览器');
    process.exit(1);
  }

  const srcUrl = 'file:///' + SOURCE.replace(/\\/g, '/');
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'defold-logo-'));
  const htmlPath = path.join(tmpDir, 'logo.html');
  fs.writeFileSync(htmlPath, '<!DOCTYPE html><html><head><meta charset="utf-8"><style>' +
    'html,body{margin:0;padding:0;background:transparent;overflow:hidden}' +
    'img{display:block;width:' + SIZE + 'px;height:' + SIZE + 'px}' +
    '</style></head><body><img src="' + srcUrl + '"></body></html>', 'utf8');

  if (fs.existsSync(PNG_PATH)) { fs.unlinkSync(PNG_PATH); }
  const res = spawnSync(chrome, [
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
    '--no-default-browser-check', '--default-background-color=00000000',
    '--user-data-dir=' + path.join(tmpDir, 'profile'),
    '--window-size=' + SIZE + ',' + SIZE,
    '--force-device-scale-factor=1',
    '--virtual-time-budget=2000',
    '--screenshot=' + PNG_PATH,
    'file:///' + htmlPath.replace(/\\/g, '/')
  ], { stdio: 'ignore' });

  if (res.error) { console.error('启动浏览器失败：' + res.error.message); process.exit(1); }
  if (!fs.existsSync(PNG_PATH)) { console.error('渲染失败，未生成 logo.png'); process.exit(1); }
  console.log('OK   assets/logo.png  ' + fs.statSync(PNG_PATH).size + ' bytes  (' + SIZE + 'x' + SIZE + ')');
  console.log('     源图：' + path.relative(ROOT, SOURCE));
  fs.rmSync(tmpDir, { recursive: true, force: true });
}

main();
