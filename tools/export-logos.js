#!/usr/bin/env node
'use strict';
/**
 * export-logos.js —— 把四个标志的 SVG 源文件导出成各设备尺寸的 PNG
 *
 *     node tools/export-logos.js
 *     node tools/export-logos.js --only=mwa      # 只导出一个
 *
 * 输入（矢量源，改设计只改这四个文件）：
 *   assets/logo-coq.svg     CoQ 棋钟
 *   assets/logo-mwa.svg     MWA · Malaysia Weiqi Association
 *   assets/logo-chess.svg   Chess · 国际象棋（车）
 *   assets/logo-weiqi.svg   围棋
 *
 * 输出：每个标志一套 9 档尺寸，覆盖手机 / 8 英寸平板 / 个人电脑的 1× 2× 3×：
 *
 *   32   favicon、16–32 CSS px 的极小位图
 *   48   手机列表 / 操作条 1×（48 CSS px）
 *   64   手机 · 平板 2× 小图标（32 CSS px）
 *   96   手机 3×（32 CSS px）；PC 1×（96 CSS px）
 *   128  8 英寸平板 2×（64 CSS px）
 *   180  iOS 主屏幕图标
 *   192  Android 主屏幕图标
 *   256  PC 2×（128 CSS px）/ 平板 4×
 *   512  主图、商店、文档用大图
 *
 * 和 export-icons.js 一样用无头 Chrome/Edge 渲染，不装任何依赖；
 * 也可用 CHROME_PATH 指定浏览器。
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'assets');

const LOGOS = [
  { id: 'coq', label: 'CoQ', file: 'logo-coq.svg' },
  { id: 'mwa', label: 'MWA', file: 'logo-mwa.svg' },
  { id: 'chess', label: 'Chess', file: 'logo-chess.svg' },
  { id: 'weiqi', label: 'Weiqi', file: 'logo-weiqi.svg' }
];

const SIZES = [
  { px: 32, note: 'favicon / 16–32 CSS px' },
  { px: 48, note: '手机列表 1×（48 CSS px）' },
  { px: 64, note: '手机·平板 2×（32 CSS px）' },
  { px: 96, note: '手机 3×（32）/ PC 1×（96）' },
  { px: 128, note: '8 英寸平板 2×（64）' },
  { px: 180, note: 'iOS 主屏幕图标' },
  { px: 192, note: 'Android 主屏幕图标' },
  { px: 256, note: 'PC 2×（128）/ 平板 4×' },
  { px: 512, note: '主图 / 商店 / 文档' }
];

function parseArgs(argv) {
  const opts = { only: null };
  argv.slice(2).forEach((arg) => {
    const m = /^--only=(.+)$/.exec(arg);
    if (m) { opts.only = m[1]; }
  });
  return opts;
}

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
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser'
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) { return c; }
  }
  return null;
}

function buildHtml(sourceUrl, size) {
  return '<!DOCTYPE html><html><head><meta charset="utf-8"><style>' +
    'html,body{margin:0;padding:0;background:transparent;overflow:hidden}' +
    'img{display:block;width:' + size + 'px;height:' + size + 'px}' +
    '</style></head><body><img src="' + sourceUrl + '"></body></html>';
}

function pngSize(file) {
  const buf = fs.readFileSync(file);
  if (buf.length < 24 || buf.toString('ascii', 1, 4) !== 'PNG') { return null; }
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

function render(chrome, tmpDir, logo, job) {
  const source = path.join(OUT_DIR, logo.file);
  const htmlPath = path.join(tmpDir, logo.id + '-' + job.px + '.html');
  const pngPath = path.join(OUT_DIR, 'logo-' + logo.id + '-' + job.px + '.png');
  const sourceUrl = 'file:///' + source.replace(/\\/g, '/');
  fs.writeFileSync(htmlPath, buildHtml(sourceUrl, job.px), 'utf8');
  if (fs.existsSync(pngPath)) { fs.unlinkSync(pngPath); }

  const res = spawnSync(chrome, [
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-crash-reporter',
    '--disable-breakpad',
    '--default-background-color=00000000',
    '--user-data-dir=' + path.join(tmpDir, 'profile-' + logo.id + '-' + job.px),
    '--window-size=' + job.px + ',' + job.px,
    '--force-device-scale-factor=1',
    '--virtual-time-budget=1500',
    '--screenshot=' + pngPath,
    'file:///' + htmlPath.replace(/\\/g, '/')
  ], { stdio: 'ignore' });

  if (res.error) {
    console.error('启动浏览器失败：' + res.error.message);
    process.exit(1);
  }
  if (!fs.existsSync(pngPath)) { return { ok: false }; }
  const dim = pngSize(pngPath);
  const ok = !!dim && dim.width === job.px && dim.height === job.px;
  return { ok, dim, bytes: fs.statSync(pngPath).size };
}

function main() {
  const opts = parseArgs(process.argv);
  const logos = opts.only ? LOGOS.filter((l) => l.id === opts.only) : LOGOS;
  if (!logos.length) {
    console.error('--only 只接受：' + LOGOS.map((l) => l.id).join(' / '));
    process.exit(1);
  }

  const missing = logos.filter((l) => !fs.existsSync(path.join(OUT_DIR, l.file)));
  if (missing.length) {
    console.error('找不到矢量源：' + missing.map((l) => 'assets/' + l.file).join(', '));
    process.exit(1);
  }

  const chrome = findChrome();
  if (!chrome) {
    console.error('没找到 Chrome / Edge，可用 CHROME_PATH 指定，例如：');
    console.error('  CHROME_PATH="/usr/bin/chromium" node tools/export-logos.js');
    process.exit(1);
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'clock-logos-'));
  let allOk = true;

  logos.forEach((logo) => {
    console.log('\n' + logo.label + '  (' + logo.file + ')');
    SIZES.forEach((job) => {
      const r = render(chrome, tmpDir, logo, job);
      if (!r.ok) { allOk = false; }
      const name = 'logo-' + logo.id + '-' + job.px + '.png';
      console.log('  ' + (r.ok ? 'OK  ' : 'FAIL') + ' ' + name.padEnd(22) +
        String(job.px + '×' + job.px).padEnd(10) +
        (r.bytes ? String(r.bytes).padStart(7) + ' B' : '') +
        '   ' + job.note);
    });
  });

  fs.rmSync(tmpDir, { recursive: true, force: true });
  console.log('\n' + (allOk ? '全部完成' : '有文件导出失败') + ' → ' + path.relative(ROOT, OUT_DIR));
  process.exit(allOk ? 0 : 1);
}

main();

