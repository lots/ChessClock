'use strict';
/**
 * 项目完整性检查：
 *  1) index.html 引用的本地资源都存在；
 *  2) 页面不引用任何外部网络资源（保证断网可用 / 可离线托管）；
 *  3) app.js 里用到的每个元素 id 都能在 index.html 中找到（防拼写错误）；
 *  4) app.js / engine.js 语法可编译；
 *  5) 棋钟界面两块面板（白/黑）的关键节点齐全。
 */
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');

const html = read('index.html');
const css = read('styles.css');
const app = read('app.js');
const engine = read('engine.js');

/**
 * 去掉 JS 里的注释（逐字符跟踪「字符串 / 行注释 / 块注释」三种状态）。
 * 不能只用正则：行尾注释（`code(); // 中文注释`）会被误当成字符串内容，
 * 于是「app.js 里不许有写死中文」这条检查会误报。
 */
function stripJsComments(src) {
  let out = '';
  let i = 0;
  let state = null;          // "'" / '"' / '`' / 'line' / 'block'
  while (i < src.length) {
    const c = src[i];
    const n = src[i + 1];
    if (state === 'line') { if (c === '\n') { state = null; out += c; } i += 1; continue; }
    if (state === 'block') { if (c === '*' && n === '/') { state = null; i += 2; } else { i += 1; } continue; }
    if (state === "'" || state === '"' || state === '`') {
      out += c;
      if (c === '\\') { out += n === undefined ? '' : n; i += 2; continue; }
      if (c === state) { state = null; }
      i += 1;
      continue;
    }
    if (c === '/' && n === '/') { state = 'line'; i += 2; continue; }
    if (c === '/' && n === '*') { state = 'block'; i += 2; continue; }
    if (c === "'" || c === '"' || c === '`') { state = c; }
    out += c;
    i += 1;
  }
  return out;
}

test('index.html 引用的本地资源都存在', () => {
  const refs = [];
  const re = /(?:src|href)\s*=\s*"([^"]+)"/g;
  let m;
  while ((m = re.exec(html)) !== null) { refs.push(m[1]); }
  const local = refs.filter((r) => !/^(data:|https?:|#|mailto:)/.test(r));
  assert.ok(local.length >= 3, '至少应引用 styles.css / engine.js / app.js');
  local.forEach((r) => {
    const p = path.join(ROOT, r.split('?')[0]);
    assert.ok(fs.existsSync(p), '缺少被引用的文件：' + r);
  });
});

test('不引用任何外部网络资源（断网也能用）', () => {
  const external = html.match(/(?:src|href)\s*=\s*"https?:\/\/[^"]+"/g) || [];
  assert.deepEqual(external, [], 'index.html 不应引用外部 URL：' + external.join(', '));
  assert.ok(!/@import\s+url\(\s*['"]?https?:/.test(css), 'styles.css 不应 @import 外部样式');
  assert.ok(!/fonts\.googleapis|cdn\./.test(html + css + app), '不应依赖任何 CDN');
});

test('app.js 引用的元素 id 在 index.html 中都存在', () => {
  const ids = new Set();
  const re = /\$\$?\(\s*'#([A-Za-z0-9_-]+)/g;
  let m;
  while ((m = re.exec(app)) !== null) { ids.add(m[1]); }
  assert.ok(ids.size > 10, '应能解析出若干 id，实际：' + ids.size);
  ids.forEach((id) => {
    assert.ok(
      new RegExp('id="' + id + '"').test(html),
      'index.html 缺少 app.js 需要的 id：#' + id
    );
  });
});

test('棋钟界面关键节点齐全（白/黑两块面板）', () => {
  ['w', 'b'].forEach((side) => {
    assert.ok(html.includes('class="pane pane-' + side + '" data-side="' + side + '"'), '缺少 ' + side + ' 方面板');
    assert.ok(html.includes('class="time" data-side="' + side + '"'), '缺少 ' + side + ' 方时间显示');
    assert.ok(html.includes('class="side-tag" data-i18n="side.' + side + '"'), '缺少 ' + side + ' 方的「白方/黑方」标签（应带 data-i18n）');
    assert.ok(!html.includes('class="pane-name"'), '姓名输入功能已移除，面板上不该再有姓名节点');
    assert.ok(html.includes('class="moves" data-side="' + side + '"'), '缺少 ' + side + ' 方步数显示');
    assert.ok(html.includes('class="state-chip" data-side="' + side + '"'), '缺少 ' + side + ' 方状态标记');
  });
  ['btnToggle', 'btnSound', 'btnRotate', 'btnSwap', 'btnFull', 'btnSetup', 'btnStartGame', 'btnRematch', 'btnLang'].forEach((id) => {
    assert.ok(html.includes('id="' + id + '"'), '缺少按钮：#' + id);
  });
});

/* ================= 双语（i18n） ================= */

const I18N = require(path.join(ROOT, 'i18n.js'));

test('i18n：中英词条的 key 完全一致（少一个就会露出 key 本身）', () => {
  const zh = Object.keys(I18N.DICT.zh).sort();
  const en = Object.keys(I18N.DICT.en).sort();
  const missingInEn = zh.filter((k) => !(k in I18N.DICT.en));
  const missingInZh = en.filter((k) => !(k in I18N.DICT.zh));
  assert.deepEqual(missingInEn, [], '英文缺少这些词条：' + missingInEn.join(', '));
  assert.deepEqual(missingInZh, [], '中文缺少这些词条：' + missingInZh.join(', '));
  assert.deepEqual(zh, en, '两种语言的 key 集合不一致');
  I18N.LANGS.forEach((l) => { assert.ok(I18N.DICT[l], '缺少语言表：' + l); });
});

test('i18n：页面与 JS 里用到的 key 都存在，且占位符能对上', () => {
  const dicts = [I18N.DICT.zh, I18N.DICT.en];

  // 1) index.html 上的 data-i18n* 标记（先去掉 HTML 注释，注释里举例的 key 不算）
  const htmlCode = html.replace(/<!--[\s\S]*?-->/g, '');
  const used = new Set();
  const reAttr = /data-i18n(?:-html|-title|-aria-label|-alt|-placeholder)?="([^"]+)"/g;
  let m;
  while ((m = reAttr.exec(htmlCode)) !== null) { used.add(m[1]); }

  // 2) app.js 里的 t('key')（先去掉注释，免得注释里举例的 t('key') 被当成调用）
  const appCode = stripJsComments(app);
  const reCall = /\bt\('([a-z][\w]*\.[a-z][\w.]*)'/g;
  while ((m = reCall.exec(appCode)) !== null) { used.add(m[1]); }
  ['fischer', 'delay', 'byoyomi', 'sudden'].forEach((mode) => { used.add('hint.' + mode); });

  // 3) app.js 里 PRESETS 的类别名（预设按钮上显示的那行字）
  const rePreset = /name:\s*'(preset\.[a-z]+)'/g;
  while ((m = rePreset.exec(app)) !== null) { used.add(m[1]); }

  assert.ok(used.size > 40, '解析出的词条太少（' + used.size + '），检查上面的正则是否失效');

  const missing = [];
  dicts.forEach((d, i) => {
    const name = i === 0 ? 'zh' : 'en';
    used.forEach((k) => { if (d[k] === undefined) { missing.push(name + ':' + k); } });
  });
  assert.deepEqual(missing, [], '这些词条缺失：' + missing.join(', '));

  // 占位符必须两种语言一致（否则切换语言会出现 {n} 字样）
  used.forEach((k) => {
    const holders = (s) => (String(s).match(/\{(\w+)\}/g) || []).sort().join(',');
    assert.equal(holders(I18N.DICT.en[k]), holders(I18N.DICT.zh[k]),
      k + ' 的占位符两种语言不一致：' + I18N.DICT.zh[k] + ' / ' + I18N.DICT.en[k]);
  });
});

test('i18n：语言按钮、脚本顺序与「不许再写死文案」的防线', () => {
  // ENG / 华文 按钮：两个语言各一个可点亮的名字
  assert.ok(/class="lang-btn"[^>]*id="btnLang"/.test(html), '设置页应有 ENG / 华文 语言按钮');
  I18N.LANGS.forEach((l) => {
    assert.ok(html.includes('data-lang-name="' + l + '"'), '语言按钮缺少 ' + l + ' 那一半');
  });
  assert.ok(/data-i18n-aria-label="lang\.button\.aria"/.test(html), '语言按钮缺少无障碍标签');

  // i18n.js 必须在 app.js 之前加载
  const i18nAt = html.indexOf('src="i18n.js"');
  const appAt = html.indexOf('src="app.js"');
  assert.ok(i18nAt > 0 && appAt > i18nAt, 'index.html 里 i18n.js 必须在 app.js 之前');

  // app.js 里除了「i18n 还没加载」时的双语告警，不该再有写死的中文
  const stripped = stripJsComments(app);
  const hard = [];
  const reStr = /'([^'\\]*)'|"([^"\\]*)"/g;
  let m;
  while ((m = reStr.exec(stripped)) !== null) {
    const s = m[1] !== undefined ? m[1] : m[2];
    if (!/[\u4e00-\u9fff]/.test(s)) { continue; }
    // 启动早期（i18n 尚未就绪）用于提示脚本加载失败的整句，允许直接写成双语
    if (/engine\.js|i18n\.js/.test(s)) { continue; }
    hard.push(s.trim());
  }
  assert.deepEqual(hard, [],
    'app.js 里还有写死的中文文案，请挪进 i18n.js 并改用 t(\'key\')：\n  ' + hard.join('\n  '));
});

test('app.js 与 engine.js 语法可编译', () => {
  assert.doesNotThrow(() => { new Function(app); }, 'app.js 存在语法错误');
  assert.doesNotThrow(() => { new Function(engine); }, 'engine.js 存在语法错误');
});

test('页面具备移动端必需的基础设置', () => {
  assert.ok(/<meta\s+name="viewport"[^>]*viewport-fit=cover/.test(html), '缺少适配刘海屏的 viewport');
  assert.ok(/user-scalable=no/.test(html), '应禁止用户缩放，避免误触放大');
  assert.ok(/touch-action:\s*manipulation/.test(css), 'CSS 应设置 touch-action: manipulation 去掉点击延迟');
  assert.ok(/orientation:\s*landscape/.test(css), 'CSS 应处理横屏布局');
  assert.ok(/-webkit-tap-highlight-color/.test(css), 'CSS 应去掉移动端点击高亮');
});

test('对坐模式只旋转竖屏下「对面」那块面板（几何正确性）', () => {
  // 手机平放桌面时，读向正常的是近侧玩家；只有对面那一块的数字需要转 180°。
  // 竖屏布局是上下分屏，对面 = **视觉上排在最前**的那块。注意视觉顺序由 CSS order 决定
  // （「交换两侧位置」用的就是 order），不再等于 DOM 顺序，所以由 app.js 打 .is-far 来指定。
  assert.ok(css.includes('@media (orientation: portrait)'), '缺少竖屏专用规则');
  assert.ok(
    css.includes('.facing .pane.is-far .pane-inner { transform: rotate(180deg); }'),
    '竖屏应旋转「视觉上第一块」面板（.facing .pane.is-far）'
  );
  assert.ok(!/\.pane:first-child/.test(css),
    '不该再用 .pane:first-child 判断对面那块：交换两侧后 DOM 顺序不再等于视觉顺序');
  // 横屏是左右分屏，两块面板都在同一侧视线上，任何单面板旋转都无法让两人同时读正，
  // 因此横屏不旋转（见 README「摆放方式」）。
  assert.ok(!/rotate\(180deg\)/.test(css.split('@media (orientation: portrait)')[0]), '竖屏规则之外不应出现 180° 旋转');

  // 黑方在前 → 竖屏在上（对面选手）、横屏在左；白方在后 → 竖屏在下（近侧）
  const panes = html.slice(html.indexOf('class="panes"'));
  assert.ok(
    panes.indexOf('pane pane-b') < panes.indexOf('pane pane-w'),
    '黑方面板应排在白方面板之前（DOM 顺序不变，屏幕上的位置交给 CSS order）'
  );
  assert.ok(!/rotate-black/.test(css + app), '已废弃的 rotate-black 类名不应残留');
});

test('交换两侧位置（⇵）：order 接线正确，被旋转的始终是视觉上第一块', () => {
  /* ---------- 1) 两颗按钮：180° 与 ⇵ ---------- */
  assert.ok(/<button[^>]*id="btnRotate"[^>]*>180°<\/button>/.test(html),
    '#btnRotate 应显示 180°（而不是旧的 ⇅ 字形）');
  assert.ok(/<button[^>]*id="btnSwap"[^>]*>⇵<\/button>/.test(html), '#btnSwap 的文字应为 ⇵（U+21F5）');
  assert.ok(/id="btnSwap"[^>]*data-i18n-title="clock\.swap\.title"/.test(html),
    '#btnSwap 的标题应走 i18n 词条 clock.swap.title');
  assert.ok(html.indexOf('id="btnRotate"') < html.indexOf('id="btnSwap"'),
    '#btnSwap 应紧跟在 #btnRotate 之后（顺序也是工具栏的视觉顺序）');
  assert.ok(!html.includes('⇅'), 'index.html 里不该再出现旧的 ⇅ 字样');
  assert.equal(I18N.DICT.zh['clock.swap.title'], '交换两侧位置', '中文词条 clock.swap.title 不对');
  assert.equal(I18N.DICT.en['clock.swap.title'], 'Swap sides', '英文词条 clock.swap.title 不对');

  /* ---------- 2) 位置交换只靠 CSS order（不动 DOM），操作条恒在中间 ---------- */
  // order 只有在 flex 容器里才有意义：竖屏是纵向排列（上→下）、横屏是横向（左→右）
  assert.ok(/\.panes\s*\{[^}]*display:\s*flex[^}]*flex-direction:\s*column/.test(css),
    '竖屏的两块面板应是纵向 flex 容器（order 才决定上下）');
  assert.ok(/@media \(orientation: landscape\)[\s\S]*?\.panes\s*\{\s*flex-direction:\s*row/.test(css),
    '横屏的两块面板应是横向 flex 容器（order 才决定左右）');
  const orderOf = (sel) => {
    const re = new RegExp(sel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*\\{[^}]*?order:\\s*(-?\\d+)');
    const m = re.exec(css);
    return m ? Number(m[1]) : null;
  };
  // DOM 顺序始终是 黑 → 操作条 → 白：交换只改 order，绝不重排节点
  const panesDom = html.slice(html.indexOf('class="panes"'));
  assert.ok(
    panesDom.indexOf('pane pane-b') < panesDom.indexOf('class="strip"') &&
    panesDom.indexOf('class="strip"') < panesDom.indexOf('pane pane-w'),
    'DOM 顺序应保持「黑方面板 → 操作条 → 白方面板」（交换靠 order，不重排节点）'
  );
  const orders = (swapped) => ({
    b: orderOf(swapped ? '#screen-clock.is-swapped .pane-b' : '.pane-b'),
    w: orderOf(swapped ? '#screen-clock.is-swapped .pane-w' : '.pane-w'),
    strip: orderOf('.strip')
  });
  // 视觉顺序 = order 顺序（竖屏自上而下 / 横屏自左而右都是这个顺序）
  const visual = (swapped) => {
    const o = orders(swapped);
    return ['b', 'w'].filter((s) => o[s] !== null).sort((x, y) => o[x] - o[y]);
  };
  assert.deepEqual(visual(false), ['b', 'w'], '默认应「黑方在前」（竖屏在上 / 横屏在左）');
  assert.deepEqual(visual(true), ['w', 'b'], '交换后应「白方在前」（竖屏在上 / 横屏在左）');
  [false, true].forEach((swapped) => {
    const o = orders(swapped);
    assert.ok(o.strip !== null && o.w !== null && o.b !== null,
      '两块面板与操作条都必须显式写 order（交换状态：' + swapped + '）');
    assert.ok((o.strip > o[visual(swapped)[0]]) && (o.strip < o[visual(swapped)[1]]),
      '操作条必须夹在两块面板之间（交换状态：' + swapped + '）');
  });

  /* ---------- 3) 对面 = 视觉上第一块：交换后换成另一块被旋转 ---------- */
  const farExpr = /var farSide = ([^;]+);/.exec(app);
  assert.ok(farExpr, 'app.js 应显式算出「对面」那一侧（var farSide = …）');
  const farSideFor = (swapped) => new Function('cfg', 'return ' + farExpr[1])({ swapped: swapped });
  assert.equal(farSideFor(false), visual(false)[0], '没交换时应旋转视觉上第一块（黑方）');
  assert.equal(farSideFor(true), visual(true)[0], '交换后应改旋转视觉上第一块（白方）');
  assert.ok(/classList\.toggle\('is-far', side === farSide\)/.test(app),
    'app.js 应把 is-far 只打在「对面」那块面板上');

  /* ---------- 4) 状态、持久化与「再来一局后仍保持」 ---------- */
  assert.ok(/classList\.toggle\('is-swapped', !!cfg\.swapped\)/.test(app),
    'app.js 应把 is-swapped 打到 #screen-clock 上（CSS 据此改 order）');
  const defs = /var DEFAULTS = \{([\s\S]*?)\n  \};/.exec(app)[1];
  assert.ok(/swapped:\s*false/.test(defs), 'DEFAULTS 里应有 swapped: false（默认不交换）');
  assert.ok(/\$\('#btnSwap'\)\.addEventListener\('click'/.test(app), '#btnSwap 应绑定点击');
  assert.ok(/cfg\.swapped = !cfg\.swapped;[\s\S]{0,160}?saveSettings\(\);/.test(app),
    '切换后应立刻 saveSettings()（和别的选项一样存进 localStorage）');
  assert.ok(/applySwap\(\);/.test(app), '应调用 applySwap() 套用交换状态');
  const readUI = /function readSetupUI\(\) \{([\s\S]*?)\n  \}/.exec(app);
  assert.ok(readUI, '找不到 readSetupUI()');
  assert.ok(!/swapped/.test(readUI[1]),
    'readSetupUI() 不该覆盖 swapped：每局开始（newGame）都读一遍设置，被打回默认就「活不过再来一局」了');
  assert.ok(/function newGame\(\) \{[\s\S]*?applySwap\(\);/.test(app),
    'newGame() 应重新套用交换状态，这样再来一局不会被重置');

  /* ---------- 5) 新按钮沿用 .icon-btn 的既有行为（失焦、i18n 标题） ---------- */
  assert.ok(/\$\$\('\.icon-btn, \.btn'\)/.test(app), '新按钮应复用 .icon-btn 的统一处理（点击后 blur）');
  assert.ok(/class="icon-btn" id="btnSwap"/.test(html), '#btnSwap 的类名应是 .icon-btn（否则样式/行为都接不上）');
});

/* ================= 界面主题 ================= */

test('主题：下拉框三项与三套 CSS 变量一一对应（另含首屏防闪脚本）', () => {
  const THEME_KEYS = ['light', 'medium', 'dark'];

  assert.ok(/<select id="themeSelect"/.test(html), '设置页缺少主题下拉框 #themeSelect');
  const opts = [];
  const optRe = /<option value="(\w+)" data-i18n="theme\.(\w+)"/g;
  let m;
  while ((m = optRe.exec(html)) !== null) {
    assert.equal(m[1], m[2], '选项值与词条名应一致：' + m[1] + ' / theme.' + m[2]);
    opts.push(m[1]);
  }
  assert.deepEqual(opts, THEME_KEYS, '主题下拉框应有且仅有 light / medium / dark 三项');

  const listMatch = /var THEMES = \[([^\]]+)\]/.exec(app);
  assert.ok(listMatch, 'app.js 里应有 THEMES 列表');
  const jsKeys = listMatch[1].split(',').map((s) => s.trim().replace(/['"]/g, ''));
  assert.deepEqual(jsKeys, THEME_KEYS, 'app.js 的 THEMES 应与下拉框完全一致（含顺序）');

  // 每套主题都要在 styles.css 里落地；浅色/中性必须显式覆盖 --bg，否则切了看不出变化
  THEME_KEYS.forEach((k) => {
    const block = new RegExp(':root\\[data-theme="' + k + '"\\][\\s\\S]*?\\}').exec(css);
    assert.ok(block, 'styles.css 缺少 :root[data-theme="' + k + '"] 变量块');
    if (k !== 'dark') {
      assert.ok(/--bg:\s*#[0-9a-f]{3,8}/i.test(block[0]), '主题 ' + k + ' 必须显式覆盖 --bg');
      assert.ok(/--fg:\s*#[0-9a-f]{3,8}/i.test(block[0]), '主题 ' + k + ' 必须显式覆盖 --fg');
      assert.ok(/--card:\s*#[0-9a-f]{3,8}/i.test(block[0]), '主题 ' + k + ' 必须显式覆盖 --card');
    }
  });

  // 首屏防闪：<head> 里要有「读存档 → 设 data-theme」的内联脚本（在样式表之后）
  const head = html.slice(0, html.indexOf('</head>'));
  assert.ok(/data-theme/.test(head) && /chessclock\.settings\.v1/.test(head),
    '缺少首屏主题内联脚本（否则选了浅色的人每次打开都会先闪一下深色）');
  assert.ok(head.indexOf('styles.css') < head.indexOf('data-theme'),
    '主题脚本应放在样式表之后');

  // ?theme= 覆盖（截图三个主题时用得上）
  assert.ok(/queryParam\('theme'\)/.test(app), 'app.js 应支持 ?theme= 覆盖');
});

/* ================= 首次打开的默认值 / 围棋预设 ================= */

test('首次打开：英文 + Byoyomi 10+3×20，且围棋预设恰好是那 8 档', () => {
  const defs = /var DEFAULTS = \{([\s\S]*?)\n  \};/.exec(app);
  assert.ok(defs, '找不到 app.js 的 DEFAULTS');
  const d = defs[1];
  assert.ok(/mode:\s*'byoyomi'/.test(d), '默认计时模式应为 Byoyomi');
  assert.ok(/baseMin:\s*10\b/.test(d), '默认基础时间应为 10 分钟');
  assert.ok(/incSec:\s*20\b/.test(d), '默认读秒应为每手 20 秒');
  assert.ok(/periods:\s*3\b/.test(d), '默认读秒段数应为 3');
  assert.ok(/presetId:\s*'10\+3x20'/.test(d), '默认预设应为 10+3×20');
  assert.ok(/lang:\s*'en'/.test(d), '默认语言应为英文');
  assert.ok(!/lang:\s*I18N\.detect\(\)/.test(d),
    '默认语言不应该再跟随浏览器（需求：首次打开固定 ENG）');

  // 围棋预设 = 需求给的那 8 档，顺序也保持
  const block = /var PRESETS_BYOYOMI = \[([\s\S]*?)\n  \];/.exec(app);
  assert.ok(block, '找不到 PRESETS_BYOYOMI');
  const got = [];
  const re = /\{ id:\s*'([^']+)',\s*baseMin:\s*(\d+),\s*incSec:\s*(\d+),\s*periods:\s*(\d+)/g;
  let m;
  while ((m = re.exec(block[1])) !== null) {
    got.push(m[2] + '+' + m[4] + '×' + m[3]);      // 基础时间 + 段数×每手秒数
  }
  assert.deepEqual(got, [
    '5+3×20', '10+3×20', '10+3×30', '15+3×30',
    '20+5×30', '30+5×30', '30+3×60', '60+5×60'
  ], '围棋预设应恰好是这 8 档（含顺序）');

  // 读秒档不再有 sub：下拉框里只写主记法「10+3×20」，
  // 否则单行下拉框里会变成「10+3×20 · 20s × 3」（同样三个数说两遍）。
  assert.ok(!/sub:\s*'/.test(block[1]), '读秒预设不应再有 sub 字段');
  assert.ok(/var extra = p\.sub \|\| \(p\.name \? t\(p\.name\) : ''\)/.test(app),
    '下拉框第二段应「有才拼」（棋类有档次，读秒没有）');
  assert.ok(/o\.textContent = extra \?\s*presetLabel\(p\) \+ '  ·  ' \+ extra : presetLabel\(p\)/.test(app),
    '没有第二段时下拉框条目只显示主记法');
  // 这组预设只用在 Byoyomi；其它模式仍用国际象棋那组
  assert.ok(/mode === E\.MODES\.BYOYOMI \? PRESETS_BYOYOMI : PRESETS_CHESS/.test(app),
    'presetsFor() 应只把围棋预设用在 Byoyomi 模式');
  assert.ok(/var PRESETS_CHESS = \[/.test(app), '应保留国际象棋那组预设给其它模式');

  // 静态兜底与默认一致：没有 JS / 首屏时不会看到另一套默认值
  assert.ok(/<html lang="en">/.test(html), '静态 HTML 的语言应为英文（默认语言）');
  assert.ok(/id="incSec"[^>]*value="20"/.test(html), '静态 HTML 的读秒输入框应为 20');
  assert.ok(/id="periods"[^>]*value="3"/.test(html), '静态 HTML 的段数输入框应为 3');
  assert.ok(/data-mode="byoyomi"[^>]*aria-pressed="true"/.test(html), '静态 HTML 应默认选中 Byoyomi');
  assert.ok(!/id="periodsField"[^>]*hidden/.test(html), 'Byoyomi 是默认模式，段数字段不该默认隐藏');
});

test('切进 Byoyomi 自动落到默认档 10+3×20（已挑过读秒预设则不动）', () => {
  // 1) helper 存在
  const fn = /function seedByoyomiDefault\(\) \{([\s\S]*?)\n  \}/.exec(app);
  assert.ok(fn, '找不到 app.js 的 seedByoyomiDefault()');

  // 2) 只有「定义 1 处 + 调用 1 处」：启动时恢复存档那条路径不许调用
  const calls = app.match(/seedByoyomiDefault\(\)/g) || [];
  assert.equal(calls.length, 2,
    'seedByoyomiDefault 应只有定义 1 处 + 模式按钮里调用 1 处（恢复存档时不许 seed）');

  // 3) 接线：在模式按钮的 click 里、syncSetupUI() 之前，且只在「真的变成 Byoyomi」时
  const handler = new RegExp("\\$\\$\\('#modeGroup \\.seg'\\)\\.forEach\\(function \\(b\\) \\{\\n" +
    "      b\\.addEventListener\\('click', function \\(\\) \\{([\\s\\S]*?)\\n      \\}\\);").exec(app);
  assert.ok(handler, '找不到模式按钮的 click 处理函数');
  const h = handler[1];
  assert.ok(/var prevMode = cfg\.mode;/.test(h), '模式处理函数应先记下 prevMode 再改 cfg.mode');
  const seedAt = h.indexOf('seedByoyomiDefault()');
  const syncAt = h.indexOf('syncSetupUI()');
  assert.ok(seedAt >= 0, '模式处理函数应调用 seedByoyomiDefault()');
  assert.ok(syncAt > seedAt, 'seed 必须在 syncSetupUI() 之前调用（输入框与预设高亮才会跟着变）');
  assert.ok(/saveSettings\(\);/.test(h), '模式切换后仍要 saveSettings()');

  // 调用点必须同时判断「模式确实变了」与「目标是 Byoyomi」：
  // 切走 / 重按当前模式 / 切到 Fischer·Delay·Sudden 都不许播种。
  const callLine = h.split('\n').filter((l) => l.indexOf('seedByoyomiDefault()') >= 0)[0];
  assert.ok(/prevMode !== cfg\.mode/.test(callLine) && /E\.MODES\.BYOYOMI/.test(callLine),
    'seed 的触发条件应是「prevMode !== cfg.mode && 目标是 Byoyomi」，别的模式一律不播种');

  // 4) 播种值就是 DEFAULTS 那组：10 / 20 / 3 / '10+3x20'
  const body = fn[1];
  assert.ok(/cfg\.baseMin = 10;/.test(body), '应播种 baseMin = 10');
  assert.ok(/cfg\.incSec = 20;/.test(body), '应播种 incSec = 20');
  assert.ok(/cfg\.periods = 3;/.test(body), '应播种 periods = 3');
  assert.ok(/cfg\.presetId = '10\+3x20';/.test(body), "应播种 presetId = '10+3x20'");

  // 5) 守卫：先查当前值是不是 PRESETS_BYOYOMI 里的某一档，是就不覆盖
  assert.ok(/PRESETS_BYOYOMI\.forEach/.test(body),
    '守卫应遍历 PRESETS_BYOYOMI 判断当前 (baseMin, incSec, periods) 是否已是读秒预设');
  assert.ok(/if \(isPreset\) \{ return/.test(body),
    '当前值已是读秒预设时应直接返回，不覆盖用户挑的那档');
  const writeAt = body.indexOf('cfg.baseMin = 10;');
  const guardAt = body.indexOf('if (isPreset)');
  assert.ok(guardAt >= 0 && guardAt < writeAt, '守卫必须写在写入之前（先判断后覆盖）');
});

/* ================= 截图场景（视觉验证台） ================= */

test('截图场景：每个场景显式设模式，且不会写进用户设置', () => {
  const driver = read('tests/visual/build.js');

  // 场景页靠真实交互驱动界面 → 会触发 saveSettings()。
  // 必须把 setItem 打桩，否则谁用普通浏览器打开 _scene-*.html，谁的设置就被改了。
  assert.ok(/localStorage\.setItem = function \(\) \{\}/.test(driver),
    '场景脚本应把 localStorage.setItem 打桩（否则打开 _scene-*.html 会覆盖用户设置）');

  // 每个非 setup 场景都要显式选模式：不能依赖默认值，默认值是会变的
  ['measure', 'midgame', 'byoyomi', 'critical', 'states', 'ready'].forEach((s) => {
    const re = new RegExp('scene === "' + s + '"[\\s\\S]{0,500}?mode\\("');
    assert.ok(re.test(driver), '场景 ' + s + ' 应显式调用 mode("…")，不要依赖默认模式');
  });

  // 读秒场景的读秒部分应与默认档 10+3×20 一致（20 秒 × 3 段），免得看图的人以为默认是别的
  assert.ok(/setNum\("baseMin", 1\); setNum\("incSec", 20\); setNum\("periods", 3\);/.test(driver),
    'byoyomi 场景的读秒应为 20 秒 × 3 段（与默认档的读秒部分一致）');
});

/* ================= 开局方式：拍面板，没有「开始」按钮 ================= */

test('开局：没有「开始」按钮，拍对侧那一半让自己的钟开始走', () => {
  // 1) 那颗按钮只剩「暂停 / 继续」，且未开表时是隐藏的
  assert.ok(/id="btnToggle"[^>]*hidden/.test(html),
    '#btnToggle 初始应隐藏（未开表时不该出现「开始」按钮）');
  assert.ok(/id="btnToggleLabel" data-i18n="clock\.pause"/.test(html),
    '按钮文案应走 clock.pause 词条（不是 Start）');
  assert.ok(/id="btnToggleLabel" data-i18n="clock\.pause">P<\/span>/.test(html),
    '没有 JS 时的静态兜底文案应是短标签 P（与 clock.pause 的英文值一致）');
  assert.ok(!/clock\.start/.test(html) && !/clock\.start/.test(app),
    'index.html 与 app.js 都不该再引用 clock.start');

  // 2) 未开表时按某一侧 → 由**对侧**开始计时（拍黑方 → 白方的钟开始走）
  assert.ok(/E\.start\(S, Date\.now\(\), E\.other\(side\)\)/.test(app),
    '未开表时应调用 E.start(S, now, E.other(side))');
  assert.ok(!/var target = S\.started \? side : 'w'/.test(app),
    '旧的「按任意一侧都由白方开始」逻辑应已移除');

  // 3) 暂停按钮不再兼职开表
  assert.ok(/if \(!S \|\| S\.finished \|\| !S\.started\) \{ return; \}/.test(app),
    'togglePause 在未开表时应直接返回，不再借它开表');
  assert.ok(!/if \(!S\.started\) \{ handlePress\('w'\); return; \}/.test(app),
    '旧的「暂停兼开表」逻辑应已移除');

  // 4) 按钮的显示逻辑只关心「是否正在进行」
  assert.ok(/btn\.hidden = !live;/.test(app), '未开表 / 一局结束时该按钮应隐藏');

  // 5) 截图场景也按新方式开局（不能再点 #btnToggle）
  const driver = read('tests/visual/build.js');
  assert.ok(/function startClock\(\) \{ press\("b"\); \}/.test(driver),
    '场景应通过拍黑方面板来开局（白方随即开始计时）');
  assert.ok(!/getElementById\("btnToggle"\)/.test(driver), '场景不该再点 #btnToggle 开局');

  // 6) 可见文案只有一个字，完整含义靠 title / aria-label 说全
  assert.equal(I18N.DICT.zh['clock.pause'], '停', '中文 clock.pause 应是「停」');
  assert.equal(I18N.DICT.en['clock.pause'], 'P', '英文 clock.pause 应是 P');
  assert.equal(I18N.DICT.zh['clock.resume'], '续', '中文 clock.resume 应是「续」');
  assert.equal(I18N.DICT.en['clock.resume'], 'C', '英文 clock.resume 应是 C');

  // 说全的那些词条：两种语言都得有（key 集合一致性另有专门用例把关）
  assert.equal(I18N.DICT.zh['clock.pause.title'], '暂停', '中文 clock.pause.title 应是「暂停」');
  assert.equal(I18N.DICT.en['clock.pause.title'], 'Pause', '英文 clock.pause.title 应是 Pause');
  assert.equal(I18N.DICT.zh['clock.resume.title'], '继续', '中文 clock.resume.title 应是「继续」');
  assert.equal(I18N.DICT.en['clock.resume.title'], 'Resume', '英文 clock.resume.title 应是 Resume');

  // app.js 用这些词条设置按钮的 title / aria-label（不许写死文案）
  const toggleFn = /function updateToggleButton\(\) \{([\s\S]*?)\n  \}/.exec(app);
  assert.ok(toggleFn, '找不到 app.js 的 updateToggleButton()');
  assert.ok(/t\('clock\.pause\.title'\)/.test(toggleFn[1]) && /t\('clock\.resume\.title'\)/.test(toggleFn[1]),
    'updateToggleButton() 应从 clock.pause.title / clock.resume.title 取说全的文案');
  assert.ok(/btn\.setAttribute\('title', spelled\)/.test(toggleFn[1]),
    '#btnToggle 应把 title 设成说全的文案（长按/悬停能看到 Pause / Resume）');
  assert.ok(/btn\.setAttribute\('aria-label', spelled\)/.test(toggleFn[1]),
    '#btnToggle 应把 aria-label 设成说全的文案（读屏软件念「暂停 / 继续」）');
});

/* ================= 图标 / logo ================= */

test('logo：原图 → 各尺寸 PNG，每个用途只有一个文件且不用 srcset', () => {
  // 原图（换 logo 就覆盖它，再跑 node tools/export-icons.js）
  assert.ok(fs.existsSync(path.join(ROOT, 'assets', 'logo-source.png')),
    '缺少原图 assets/logo-source.png');

  // 两处显示位置各引用一个 PNG
  assert.ok(
    /class="brand-logo"[^>]*assets\/logo-brand\.png[^>]*width="96"[^>]*height="96"/.test(html),
    '设置页应引用 assets/logo-brand.png（按 96×96 显示）'
  );
  assert.ok(
    /class="strip-logo"[^>]*assets\/logo-strip\.png[^>]*width="48"[^>]*height="48"/.test(html),
    '棋钟页应引用 assets/logo-strip.png（按 48×48 显示）'
  );

  // ⚠️ 这条是那次「PC 正常、手机没图」事故的回归防线：
  // srcset 一旦出现 2x 候选，手机就只会取 2x 那个文件；手工只换 1x 就会两边不一致。
  assert.ok(!/class="(brand|strip)-logo"[^>]*srcset=/.test(html),
    'logo 不要用 srcset（手机只会取 2x 候选，手换 1x 会「PC 正常、手机没图」）；' +
    '改成单个文件按 3 倍尺寸导出，见 assets/README.md');

  assert.ok(/\.brand-logo\s*\{[^}]*width:\s*96px/.test(css), 'CSS 应把 .brand-logo 固定为 96px');
  assert.ok(/\.strip-logo\s*\{[^}]*width:\s*48px/.test(css), 'CSS 应把 .strip-logo 固定为 48px');

  // PNG 的**像素尺寸**必须和显示尺寸成 3 倍关系（直接读 PNG 头里的 IHDR，别信文件名）
  const pngSize = (file) => {
    const b = fs.readFileSync(path.join(ROOT, 'assets', file));
    assert.equal(b.slice(12, 16).toString('ascii'), 'IHDR', file + ' 不是合法 PNG');
    return [b.readUInt32BE(16), b.readUInt32BE(20)];
  };
  assert.deepEqual(pngSize('logo-brand.png'), [288, 288],
    'logo-brand.png 应是 288×288（页面显示 96×96 的 3 倍）；换图后请重跑 node tools/export-icons.js');
  assert.deepEqual(pngSize('logo-strip.png'), [144, 144],
    'logo-strip.png 应是 144×144（页面显示 48×48 的 3 倍）；换图后请重跑 node tools/export-icons.js');
});

test('标志：点一下循环 TARUMT → CoQ → Chess → 围棋 → MWA，并记住选择', () => {
  // 1) 两处 logo 都包在按钮里（能点、能聚焦、键盘也能按）
  assert.ok(
    /<button[^>]*id="btnLogoBrand"[^>]*>[\s\S]{0,240}?class="brand-logo"/.test(html),
    '设置页 logo 应包在 #btnLogoBrand 按钮里（可点击）'
  );
  assert.ok(
    /<button[^>]*id="btnLogoStrip"[^>]*>[\s\S]{0,240}?class="strip-logo"/.test(html),
    '棋钟操作条 logo 应包在 #btnLogoStrip 按钮里（可点击）'
  );
  assert.ok(/\.logo-btn\s*\{[^}]*padding:\s*0/.test(css),
    '.logo-btn 不该有内距，否则会把操作条撑宽 / 页头撑高');

  // 2) 顺序：TARUMT → CoQ → Chess → 围棋 → MWA
  const m = /var LOGO_ORDER = \[([^\]]+)\]/.exec(app);
  assert.ok(m, 'app.js 应有 LOGO_ORDER');
  const order = (m[1].match(/'([a-z]+)'/g) || []).map((s) => s.replace(/'/g, ''));
  assert.deepEqual(order, ['tarumt', 'coq', 'chess', 'weiqi', 'mwa'],
    '循环顺序应是 TARUMT → CoQ → Chess → 围棋 → MWA');

  // 3) 默认 TARUMT；每次点击换下一个并存盘
  assert.ok(/logo:\s*'tarumt'/.test(app), '没选过时应显示 TARUMT');
  const cycle = /function cycleLogo\(\) \{([\s\S]*?)\n  \}/.exec(app);
  assert.ok(cycle, '找不到 cycleLogo()');
  assert.ok(/\(i \+ 1\) % LOGO_ORDER\.length/.test(cycle[1]),
    'cycleLogo() 应取下一个，数组末尾回到第一个');
  assert.ok(/saveSettings\(\)/.test(cycle[1]),
    'cycleLogo() 应调用 saveSettings()，否则关掉再打开就忘了');
  assert.ok(/applyLogo\(\)/.test(cycle[1]), 'cycleLogo() 应立刻重画');

  // 4) 启动时就套用上次选的（init 第一件事）
  assert.ok(/function init\(\) \{\s*applyLogo\(\)/.test(app),
    'init() 应先把上次选的标志应用上去（避免先闪一下 TARUMT）');

  // 5) 两处 <img> 由同一份状态驱动
  assert.ok(/brand\.src = files\.brand/.test(app) && /strip\.src = files\.strip/.test(app),
    'applyLogo() 应同时更新设置页与操作条两处 logo');

  // 6) 名字 / 无障碍文案走 i18n，中英各一份，且带 {name} 占位符
  order.forEach((id) => {
    assert.ok(I18N.DICT.zh['logo.name.' + id], '中文缺少 logo.name.' + id);
    assert.ok(I18N.DICT.en['logo.name.' + id], '英文缺少 logo.name.' + id);
  });
  assert.ok(/\{name\}/.test(I18N.DICT.zh['logo.button.aria']));
  assert.ok(/\{name\}/.test(I18N.DICT.en['logo.button.aria']));

  // 7) 每个标志引用的两张位图都真的存在（brand 96×96 / strip 48×48）
  const files = [...app.matchAll(/'(assets\/logo-[a-z0-9-]+\.png)'/g)].map((x) => x[1]);
  assert.ok(files.length >= 10, '应能解析出每个标志的两张图，实际：' + files.length);
  files.forEach((f) => {
    assert.ok(fs.existsSync(path.join(ROOT, f)), '缺少标志位图：' + f);
  });
});

test('窄屏页头：标题与副标题各占整行，不再被语言按钮挤成一词一行', () => {
  // 旧版把 logo / 标题 / 语言按钮挤在同一行：320px 下标题列只剩 67px，
  // 「CoQ Chess & Weiqi Clock」和副标题都被压成一词一行，页头高 266px
  //（截图 screenshots/Too_Big.jpeg）。现在 ≤560px 走两行网格：
  //   第一行 logo + 标题 + 语言按钮，第二行副标题独占整行。
  const media = /@media \(max-width: 560px\) \{([\s\S]*?)\n\}/.exec(css);
  assert.ok(media, 'styles.css 应有 ≤560px 的页头媒体查询');
  const block = media[1];

  assert.ok(
    /\.app-head\s*\{[\s\S]*?grid-template-areas:\s*"logo title lang"\s*"sub\s+sub\s+sub"/.test(block),
    '窄屏页头应是两行网格：logo/title/lang，副标题跨整行'
  );
  assert.ok(/\.app-head-text\s*\{\s*display:\s*contents/.test(block),
    '要让 h1/.sub 直接成为网格项，.app-head-text 需 display: contents');
  assert.ok(/\.app-head \.brand-logo\s*\{[^}]*width:\s*56px/.test(block),
    '窄屏 logo 应收小到 56px，给标题让出宽度');
  assert.ok(/\.app-head \.sub\s*\{[^}]*grid-area:\s*sub/.test(block),
    '副标题应占整行（不再被语言按钮挤窄）');
  assert.ok(/\.app-head \.lang-btn\s*\{[^}]*grid-area:\s*lang/.test(block),
    '语言按钮固定在右上角那一格');
  assert.ok(/\.brand-logo\s*\{[^}]*width:\s*96px/.test(css),
    '大屏仍保持 96×96');
});

test('站点图标（favicon / iOS 主屏）都指向 logo 资源，且 PNG 已生成', () => {
  // 标签页图标统一用从原图导出的 PNG（不再挂那个旧版 CoQ 的 SVG）
  assert.ok(!/rel="icon"[^>]*assets\/logo\.svg/.test(html),
    'favicon 不该再指向旧的 logo.svg（那是 CoQ 旧图形，当前图形在 logo-source.png）');
  assert.ok(/rel="icon"[^>]*sizes="32x32"[^>]*assets\/icon-32\.png/.test(html), '缺少 32×32 PNG favicon');
  assert.ok(/rel="apple-touch-icon"[^>]*assets\/icon-180\.png/.test(html), '缺少 iOS 主屏图标');
  assert.ok(fs.existsSync(path.join(ROOT, 'tools', 'export-icons.js')), '缺少图标导出脚本');
  ['icon-32.png', 'icon-64.png', 'icon-180.png'].forEach((f) => {
    assert.ok(
      fs.existsSync(path.join(ROOT, 'assets', f)),
      '缺少 assets/' + f + '（运行 node tools/export-icons.js 生成）'
    );
  });
});

test('最后 10 秒提示音：主时间也响，四种模式通用', () => {
  assert.ok(/var TICK_LAST_MS = 10000/.test(app), 'app.js 应有 10 秒提示音的窗口常量');
  assert.ok(/function lastTenTick/.test(app), 'app.js 应有 lastTenTick()');
  // 关键：不再把「相位」限制在读秒
  assert.ok(!/info\.phase !== 'byoyomi'\) \{ return/.test(app),
    '提示音不应只对读秒阶段生效');
  assert.ok(/var turn = S\.moves\.w \+ S\.moves\.b/.test(app),
    'key 里要带「第几手」，否则 Fischer 加秒后再次进入最后 10 秒不会重新响');
  assert.ok(/lastTenTick\(side, info\)/.test(app), 'render() 里每帧都要过一遍提示音判定');
  // 提示音在四种模式都该工作：只依赖 ms，与 cfg.mode 无关
  const fn = app.slice(app.indexOf('function lastTenTick'), app.indexOf('function lastTenTick') + 900);
  assert.ok(fn.indexOf('cfg.mode') < 0, 'lastTenTick 不应按模式分支（所有模式都滴）');
});
test('读秒段数条：两块面板各一条，只在 Byoyomi 模式点亮', () => {
  // 结构：每块面板底部各一条（.pane-inner 里，跟着对坐一起转）
  assert.equal((html.match(/class="byo-bar"/g) || []).length, 2,
    'index.html 里两块面板应各有一条 .byo-bar');
  assert.ok(/<span class="byo-bar" data-side="w"/.test(html), '白方面板缺段数条');
  assert.ok(/<span class="byo-bar" data-side="b"/.test(html), '黑方面板缺段数条');
  // 样式：默认隐藏，.pane.has-byo-bar 才显示；一格一段，亮/暗两态
  assert.ok(/\.byo-bar\s*\{[\s\S]{0,240}?display:\s*flex/.test(css), '.byo-bar 应是横向一排格子');
  assert.ok(/\.pane\.has-byo-bar \.byo-bar\s*\{\s*display:\s*flex/.test(css),
    '应由 .pane.has-byo-bar 控制显隐（只在 Byoyomi 模式出现）');
  // 位置：夹在「数字」与「MOVE 那一行」之间（DOM 里 .time 之后、.pane-foot 之前），且不绝对定位
  assert.ok(/\.time" data-side="[wb]">[^<]*<\/span>\s*<span class="byo-bar"/.test(html) ||
            /<span class="time" data-side="[wb]">[\s\S]{0,40}<span class="byo-bar" data-side="[wb]"/.test(html),
    '段数条应紧跟在时间数字之后（DOM 顺序）');
  assert.ok(/<span class="byo-bar"[^>]*><\/span>\s*<span class="pane-foot"/.test(html),
    '段数条应在「MOVE 那一行」之前（DOM 顺序）');
  assert.ok(!/\.byo-bar\s*\{[\s\S]{0,200}?position:\s*absolute/.test(css),
    '段数条应在正常流里排版，不再绝对定位到面板底部');
  // 颜色：还剩的段是绿色，已用掉的段是红色（和 Godot / Defold 两版同一套语义）
  assert.ok(/\.byo-bar i\s*\{[\s\S]{0,120}?background:\s*var\(--danger\)/.test(css),
    '已用掉的段应是红色（--danger）');
  assert.ok(/\.byo-bar i\.is-on\s*\{\s*background:\s*var\(--ok\)/.test(css),
    '还剩的段应是绿色（--ok）');
  // 段数条不再用面板的读秒紫，而是独立的绿/红两色（见下）
  // 逻辑：render 里按模式开关，格数跟着 byoyomiPeriods，亮几格 = 还剩几段
  assert.ok(/function updateByoBar/.test(app), 'app.js 应有 updateByoBar()');
  assert.ok(/has-byo-bar/.test(app), 'render() 应按模式给面板加 has-byo-bar');
  assert.ok(/S\.cfg\.mode !== E\.MODES\.BYOYOMI/.test(app), '非 Byoyomi 模式不画段数条');
  assert.ok(/builtBarPeriods\[side\] !== total/.test(app), '段数变了要重建格子');
  assert.ok(/classList\.toggle\('is-on', k < left\)/.test(app), '亮着的格数应等于剩余段数');
  // 正在倒计时的那一段按窗口剩余比例画成进度条：绿在前、红贴右
  assert.ok(/linear-gradient\(to right, var\(--ok\) 0 ' \+ pct \+ '%, var\(--danger\)/.test(app),
    '倒计时中的那一段应是绿→红渐变（比例取自本窗口剩余时间）');
  assert.ok(/ratio = Math\.max\(0, Math\.min\(1, info\.ms \/ S\.cfg\.byoyomiMs\)\)/.test(app),
    '比例应 = 本窗口剩余 / 读秒秒数');
});
test('读秒模式在引擎 / 设置项 / 文案 / 时间字段四处都接上了', () => {
  assert.ok(/BYOYOMI:\s*'byoyomi'/.test(engine), 'engine.js 应定义 byoyomi 模式');
  assert.ok(/data-mode="byoyomi"/.test(html), 'index.html 缺少读秒模式按钮');
  assert.ok(/t\('hint\.'\s*\+/.test(app), 'app.js 应按模式取说明（t(\'hint.\' + mode)）');
  assert.ok(/'hint\.byoyomi'/.test(fs.readFileSync(path.join(ROOT, 'i18n.js'), 'utf8')),
    'i18n.js 缺少读秒说明词条 hint.byoyomi');
  assert.ok(/id="periodsField"/.test(html), 'index.html 缺少读秒段数字段');
  assert.ok(/id="periods"/.test(html), 'index.html 缺少读秒段数输入框');
  assert.ok(/byoyomiMs/.test(app) && /byoyomiPeriods/.test(app), 'app.js 应把读秒参数传给引擎');
  assert.ok(/is-byoyomi/.test(css) && /is-byoyomi/.test(app), '读秒阶段应有独立的显示样式');
});

/* ================= README 里引用的图片 ================= */

test('README 引用的图片都存在，且 screenshots/ 与截图产物逐字节一致', () => {
  const shots = ['midgame-portrait.png', 'byoyomi-portrait.png', 'midgame-landscape.png'];

  // 1) README 里每个 <img src> 都必须真实存在，并且不能指向 tests/（发布站点时那个目录不发布）
  ['README.md', 'README_CN.md'].forEach((name) => {
    const refs = [];
    const re = /<img[^>]*src="([^"]+)"/g;
    let m;
    while ((m = re.exec(read(name))) !== null) { refs.push(m[1]); }
    assert.equal(refs.length, 3, name + ' 应有 3 张示意图，实际 ' + refs.length);
    refs.forEach((rel) => {
      assert.ok(fs.existsSync(path.join(ROOT, rel)), name + ' 引用的图片不存在：' + rel);
      assert.ok(!/^tests\//.test(rel),
        name + ' 不该引用 tests/ 下的路径（发布 GitHub Pages 时那里会破图）：' + rel);
    });
  });

  // 2) screenshots/ 是 README 用的那一份，必须与 tests/visual/out/ 的产物一致
  shots.forEach((f) => {
    const a = path.join(ROOT, 'screenshots', f);
    const b = path.join(ROOT, 'tests', 'visual', 'out', f);
    assert.ok(fs.existsSync(a) && fs.existsSync(b), '缺少截图：' + f);
    assert.deepEqual(fs.readFileSync(a), fs.readFileSync(b),
      'screenshots/' + f + ' 与 tests/visual/out/' + f + ' 不一致（跑 npm run shots 会自动同步）');
  });
});
