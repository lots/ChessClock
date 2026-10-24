#!/usr/bin/env node
'use strict';
/**
 * export-icons.js — 生成操作条上的白色图标（PNG，透明底）
 *
 *     node tools/export-icons.js
 *
 * 网页版这几颗按钮用的是 emoji / 几何字符（🔊 🔇 ⇵ ⛶ ⚙）。
 * Godot 内置字体与多数系统字体对这些码位要么没有字形、要么只有彩色 emoji 版本
 * （无法按主题染色），所以与 Defold 版一样**换成图片**：
 *   - 白色 + 透明底，界面上按主题色 modulate（深色主题显示白、浅色主题显示深灰）；
 *   - 96×96 导出，界面里按 22px 显示（3 倍以上余量）。
 *
 * 产出：
 *   assets/icons/sound_on.png   声音开（扬声器 + 声波）
 *   assets/icons/sound_off.png  声音关（扬声器 + 叉）
 *   assets/icons/swap.png       交换两侧（⇵ 的图形化：上箭头 + 下箭头）
 *   assets/icons/settings.png   返回设置（齿轮）
 *   assets/icons/fullscreen.png 全屏（四个角括号 ⛶）
 *
 * 画法：图标在 24×24 坐标系里用「多边形 / 圆 / 折线画笔」描述，
 * 由下面这段**纯 Node 光栅化器**以 4×4 超采样填成 96×96 的抗锯齿 PNG。
 * 不依赖任何 npm 包 —— 换图标就改下面的 ICONS 再跑一次。
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.join(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'assets', 'icons');
const SIZE = 96;      // 导出像素
const SS = 4;         // 超采样倍数（4×4 = 16 级抗锯齿）
const UNIT = 24;      // 设计坐标系边长

/* ===================== 图标定义（24×24 坐标系，y 向下） ===================== */

/** 圆上的一段弧，采样成折线 */
function arc(cx, cy, r, deg0, deg1, steps) {
  const pts = [];
  const n = steps || 24;
  for (let i = 0; i <= n; i++) {
    const a = (deg0 + (deg1 - deg0) * (i / n)) * Math.PI / 180;
    pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  return pts;
}

/** 齿轮轮廓：外圈 8 个齿 + 中间挖一个圆孔（even-odd 填充即可挖空） */
function gearPolygon() {
  const cx = 12, cy = 12, rOut = 10.4, rIn = 7.6, teeth = 8, ht = 0.20;
  const step = (Math.PI * 2) / teeth;
  const pt = (r, a) => [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  const ring = [];
  for (let i = 0; i < teeth; i++) {
    const a = i * step - Math.PI / 2;
    ring.push(pt(rOut, a - ht), pt(rOut, a + ht));
    ring.push(pt(rIn, a + step / 2 - ht * 1.15), pt(rIn, a + step / 2 + ht * 1.15));
  }
  return [ring, arc(cx, cy, 3.2, 0, 360, 48)];
}

/** 四个角的括号（全屏图标 ⛶） */
function fullscreenPolys() {
  const near = 9.6, far = 17.4, len = 3.0, w = 1.5;
  const out = [];
  const corner = (x, y, sx, sy) => {
    // 横臂
    out.push([[
      [x, y], [x + sx * len, y], [x + sx * len, y + sy * w], [x, y + sy * w]
    ]]);
    // 竖臂
    out.push([[
      [x, y], [x + sx * w, y], [x + sx * w, y + sy * len], [x, y + sy * len]
    ]]);
  };
  corner(near - 1.5, near - 1.5, 1, 1);
  corner(far + 1.5, near - 1.5, -1, 1);
  corner(near - 1.5, far + 1.5, 1, -1);
  corner(far + 1.5, far + 1.5, -1, -1);
  return out;
}

const SPEAKER = [[[4, 9.2], [7.1, 9.2], [12, 5.4], [12, 18.6], [7.1, 14.8], [4, 14.8]]];

const ICONS = [
  {
    name: 'sound_on',
    note: '声音开（扬声器 + 两道声波）',
    polys: [SPEAKER],
    strokes: [
      { pts: arc(11.5, 12, 4.8, -55, 55), w: 1.8 },
      { pts: arc(11.5, 12, 8.4, -55, 55), w: 1.8 }
    ]
  },
  {
    name: 'sound_off',
    note: '声音关（扬声器 + 叉）',
    polys: [SPEAKER],
    strokes: [
      { pts: [[15.2, 9.0], [20.6, 14.4]], w: 1.8 },
      { pts: [[20.6, 9.0], [15.2, 14.4]], w: 1.8 }
    ]
  },
  {
    name: 'swap',
    note: '交换两侧（左箭头向下 + 右箭头向上 = ⇵）',
    polys: [
      [[[8.5, 17.4], [4.9, 13.0], [12.1, 13.0]]],
      [[[15.5, 6.6], [11.9, 11.0], [19.1, 11.0]]]
    ],
    strokes: [
      { pts: [[8.5, 5.5], [8.5, 16.2]], w: 2 },
      { pts: [[15.5, 18.5], [15.5, 7.8]], w: 2 }
    ]
  },
  {
    name: 'settings',
    note: '返回设置（齿轮）',
    polys: [gearPolygon()]
  },
  {
    name: 'fullscreen',
    note: '全屏（四角括号 ⛶）',
    polys: fullscreenPolys()
  }
];

/* ===================== 极简光栅化器（多边形 + 圆 + 折线画笔） ===================== */

/** 扫描线填充（even-odd；奇偶规则天然支持「外轮廓 + 中孔」这种多环形状） */
function fillRings(mask, W, H, rings) {
  const edges = [];
  rings.forEach((pts) => {
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i], b = pts[(i + 1) % pts.length];
      if (a[1] !== b[1]) { edges.push([a, b]); }
    }
  });
  for (let y = 0; y < H; y++) {
    const yc = y + 0.5;
    const xs = [];
    for (let i = 0; i < edges.length; i++) {
      const a = edges[i][0], b = edges[i][1];
      const y0 = Math.min(a[1], b[1]), y1 = Math.max(a[1], b[1]);
      if (yc < y0 || yc >= y1) { continue; }
      xs.push(a[0] + (yc - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
    }
    xs.sort((p, q) => p - q);
    for (let i = 0; i + 1 < xs.length; i += 2) {
      const x0 = Math.max(0, Math.ceil(xs[i] - 0.5));
      const x1 = Math.min(W - 1, Math.ceil(xs[i + 1] - 0.5) - 1);
      for (let x = x0; x <= x1; x++) { mask[y * W + x] = 1; }
    }
  }
}

/** 实心圆（画圆头笔帽 / 圆角接头用） */
function fillCircle(mask, W, H, cx, cy, r) {
  const x0 = Math.max(0, Math.floor(cx - r - 1)), x1 = Math.min(W - 1, Math.ceil(cx + r + 1));
  const y0 = Math.max(0, Math.floor(cy - r - 1)), y1 = Math.min(H - 1, Math.ceil(cy + r + 1));
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      if (dx * dx + dy * dy <= r * r) { mask[y * W + x] = 1; }
    }
  }
}

/** 折线画笔：每段画成矩形（四边形），每个顶点补一个圆 → 圆角接头与圆头端点 */
function strokePath(mask, W, H, pts, width) {
  const hw = width / 2;
  for (let i = 0; i + 1 < pts.length; i++) {
    const a = pts[i], b = pts[i + 1];
    const dx = b[0] - a[0], dy = b[1] - a[1];
    const len = Math.hypot(dx, dy);
    if (len === 0) { continue; }
    const nx = -dy / len * hw, ny = dx / len * hw;
    fillRings(mask, W, H, [[
      [a[0] + nx, a[1] + ny], [b[0] + nx, b[1] + ny],
      [b[0] - nx, b[1] - ny], [a[0] - nx, a[1] - ny]
    ]]);
  }
  for (let i = 0; i < pts.length; i++) { fillCircle(mask, W, H, pts[i][0], pts[i][1], hw); }
}

/* ===================== PNG 编码（RGBA8，无依赖） ===================== */

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) { c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1); }
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) { c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8); }
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function encodePNG(width, height, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const raw = Buffer.alloc((width * 4 + 1) * height);
  let o = 0;
  for (let y = 0; y < height; y++) {
    raw[o++] = 0;
    rgba.copy(raw, o, y * width * 4, (y + 1) * width * 4);
    o += width * 4;
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

/* ===================== 渲染 ===================== */

function renderIcon(icon) {
  const W = SIZE * SS, H = SIZE * SS;
  const mask = new Uint8Array(W * H);
  const s = SIZE / UNIT * SS;
  const scalePts = (pts) => pts.map((p) => [p[0] * s, p[1] * s]);

  (icon.polys || []).forEach((shape) => fillRings(mask, W, H, shape.map(scalePts)));
  (icon.strokes || []).forEach((st) => {
    strokePath(mask, W, H, scalePts(st.pts), st.w * s);
  });

  const rgba = Buffer.alloc(SIZE * SIZE * 4);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      let hits = 0;
      for (let sy = 0; sy < SS; sy++) {
        const row = (y * SS + sy) * W;
        for (let sx = 0; sx < SS; sx++) { hits += mask[row + x * SS + sx]; }
      }
      const a = Math.round(255 * hits / (SS * SS));
      const i = (y * SIZE + x) * 4;
      rgba[i] = 255; rgba[i + 1] = 255; rgba[i + 2] = 255; rgba[i + 3] = a;
    }
  }
  return encodePNG(SIZE, SIZE, rgba);
}

function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  ICONS.forEach((icon) => {
    const png = renderIcon(icon);
    const out = path.join(OUT_DIR, icon.name + '.png');
    fs.writeFileSync(out, png);
    console.log('OK   ' + (icon.name + '.png').padEnd(16) +
      String(SIZE + '×' + SIZE).padEnd(10) + String(png.length + ' bytes').padEnd(12) + icon.note);
  });
  console.log('\nRESULT: 图标已导出到 assets/icons/（白色 + 透明底，3 倍尺寸）');
}

main();
