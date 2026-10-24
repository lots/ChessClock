'use strict';
/**
 * project_spec.js — Defold 项目静态校验（只用 Node，不需要安装 Defold）
 *
 *     node tests/project_spec.js
 *
 * 它检查的都是「手工写 Defold 资源文件时最容易犯的错」，也是这次移植时真的踩过的坑：
 *   1) game.project / .collection / .go / .gui / .atlas 里引用的文件是否都存在；
 *   2) .gui 里注册的字体名 / 贴图名，是否正好覆盖 Lua 里 hash("...") 用到的名字
 *      （漏一个，运行期就是一片空白 + ERROR:SCRIPT）；
 *   3) engine.lua 与网页版 engine.js 的常量是否一致（跨语言防漂移）；
 *   4) engine_spec.lua 与 engine.test.js 的用例数是否一致（移植没漏测）；
 *   5) Lua 代码块/括号是否配平（没有 Defold 时的最低限度语法体检）。
 *
 * 更强的校验请用：
 *      node tests/run.js              # 计时引擎单测（Lua）+ 本文件
 *      tools/build_and_run.ps1        # bob 真编译 + 打包 + 冒烟运行
 */
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const WEB_ROOT = path.join(ROOT, '..');          // 网页版所在目录（engine.js 在那里）
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const exists = (p) => fs.existsSync(path.join(ROOT, p));

// 只看工程自己的文件：跳过构建产物与 Defold 生成的目录
const SKIP_DIRS = ['build', 'bundle', '.internal', '.defold', 'node_modules'];

function walk(dir, out) {
  out = out || [];
  for (const e of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
    const rel = dir ? dir + '/' + e.name : e.name;
    if (e.isDirectory()) {
      if (SKIP_DIRS.indexOf(e.name) >= 0) { continue; }
      walk(rel, out);
    } else {
      out.push(rel);
    }
  }
  return out;
}

const FILES = walk('');
const readAll = (ext) => FILES.filter((f) => f.endsWith(ext)).map((f) => ({ file: f, text: read(f) }));
const SKIP_BUILTIN = (p) => p.indexOf('/builtins/') === 0 || p.indexOf('builtins/') === 0;

// ---------------------------------------------------------------- 1. 引用都存在

test('所有资源引用都指向真实存在的文件', () => {
  const missing = [];

  // game.project 里的 resource 字段（Defold 写的是编译后的 *.xxxc，源文件去掉结尾的 c）
  read('game.project').split(/\r?\n/).forEach((line) => {
    const m = line.match(/^\s*(main_collection|render|game_binding|debug_init_script)\s*=\s*(\S+)/);
    if (!m) { return; }
    let p = m[2];
    if (SKIP_BUILTIN(p)) { return; }
    if (/c$/.test(p) && !exists(p)) { p = p.slice(0, -1); }
    if (!exists(p)) { missing.push('game.project -> ' + m[2]); }
  });

  // .collection / .go / .gui / .atlas 内部的引用
  readAll('.collection').concat(readAll('.go')).forEach(({ file, text }) => {
    const re = /(?:component|prototype):\s*"([^"]+)"/g;
    let m;
    while ((m = re.exec(text)) !== null) {
      if (!SKIP_BUILTIN(m[1]) && !exists(m[1]) && !exists(m[1] + '.go')) {
        missing.push(file + ' -> ' + m[1]);
      }
    }
  });

  readAll('.gui').forEach(({ file, text }) => {
    const re = /(?:script|font|texture):\s*"([^"]+)"/g;
    let m;
    while ((m = re.exec(text)) !== null) {
      if (m[1] && !SKIP_BUILTIN(m[1]) && !exists(m[1])) { missing.push(file + ' -> ' + m[1]); }
    }
  });

  readAll('.atlas').forEach(({ file, text }) => {
    const re = /image:\s*"([^"]+)"/g;
    let m;
    while ((m = re.exec(text)) !== null) {
      if (!exists(m[1])) { missing.push(file + ' -> ' + m[1]); }
    }
  });

  assert.deepEqual(missing, [], '引用了不存在的文件：\n  ' + missing.join('\n  '));
});

// ------------------------------------------------- 2. .gui 注册的名字覆盖 Lua 的用法

test('.gui 里注册的字体名与贴图名覆盖 Lua 用到的全部名字', () => {
  const guis = readAll('.gui');
  assert.ok(guis.length >= 2, '应该有两个 GUI 场景（设置页 + 棋钟页）');

  const luaText = readAll('.lua').map((f) => f.text).join('\n') +
    readAll('.gui_script').map((f) => f.text).join('\n');
  const used = new Set();
  const re = /hash\("([A-Za-z0-9_]+)"\)/g;
  let m;
  while ((m = re.exec(luaText)) !== null) { used.add(m[1]); }
  // hash("logo") 之类是贴图名；ui / clock 是字体名。其余（比如事件名）不在这里校验。
  const declaredFonts = new Set();
  const declaredTextures = new Set();
  guis.forEach(({ text }) => {
    let r = /fonts\s*\{[^}]*name:\s*"([^"]+)"/g;
    while ((m = r.exec(text)) !== null) { declaredFonts.add(m[1]); }
    r = /textures\s*\{[^}]*name:\s*"([^"]+)"/g;
    while ((m = r.exec(text)) !== null) { declaredTextures.add(m[1]); }
  });

  ['ui', 'clock'].forEach((name) => {
    assert.ok(used.has(name), 'Lua 里应该用到字体名 ' + name);
    assert.ok(declaredFonts.has(name), '.gui 的 fonts 块缺少字体名：' + name);
  });
  assert.ok(declaredTextures.has('logo'), '.gui 的 textures 块缺少贴图名 logo');

  // 每个 .gui 都要自己注册（两个场景互相独立）
  guis.forEach(({ file, text }) => {
    ['ui', 'clock'].forEach((n) => {
      assert.ok(new RegExp('name:\\s*"' + n + '"').test(text), file + ' 缺少字体声明 ' + n);
    });
    assert.ok(/name:\s*"logo"/.test(text), file + ' 缺少贴图声明 logo');
  });
});

// ------------------------------------------- 3. engine.js ↔ engine.lua 常量一致

test('engine.lua 与网页版 engine.js 的常量完全一致（跨语言防漂移）', () => {
  const js = fs.readFileSync(path.join(WEB_ROOT, 'engine.js'), 'utf8');
  const lua = read('logic/engine.lua');
  const names = ['LOW_TIME_MS', 'CRITICAL_TIME_MS', 'MIN_PRESS_GAP_MS',
    'MIN_BASE_MS', 'MAX_BASE_MS', 'MAX_ADD_MS', 'MIN_BYOYOMI_MS', 'MAX_PERIODS'];

  names.forEach((n) => {
    const mJs = js.match(new RegExp('var\\s+' + n + '\\s*=\\s*([^;]+);'));
    const mLua = lua.match(new RegExp('M\\.' + n + '\\s*=\\s*([^\\r\\n]+)'));
    assert.ok(mJs, 'engine.js 缺少常量 ' + n);
    assert.ok(mLua, 'engine.lua 缺少常量 ' + n);
    const norm = (s) => s.replace(/--.*$/, '').replace(/\/\/.*$/, '').replace(/\s+/g, '');
    assert.equal(norm(mLua[1]), norm(mJs[1]),
      '常量 ' + n + ' 两个版本不一致：lua=' + norm(mLua[1]) + ' js=' + norm(mJs[1]));
  });
});

test('engine.lua 导出了 engine.js 的全部 API，且脚本用到的 E.xxx 都存在', () => {
  const js = fs.readFileSync(path.join(WEB_ROOT, 'engine.js'), 'utf8');
  const lua = read('logic/engine.lua');

  // engine.js 的返回对象：`other: other,` / `formatTime: formatTime,`
  // 注意要用最后一个 `return {`（文件里函数内部还有别的 return 表）
  const jsApi = new Set();
  const reJs = /([A-Za-z_][A-Za-z0-9_]*)\s*:/g;
  let m;
  const tail = js.slice(js.lastIndexOf('return {'));
  while ((m = reJs.exec(tail)) !== null) { jsApi.add(m[1]); }
  assert.ok(jsApi.size > 15, '解析 engine.js 的导出失败，只拿到 ' + jsApi.size + ' 个');

  // engine.lua：`M.xxx = ...` 与 `function M.xxx(...)`
  const luaApi = new Set();
  const reLua = /(?:^|\n)\s*(?:function\s+)?M\.([A-Za-z_][A-Za-z0-9_]*)\s*[=(]/g;
  while ((m = reLua.exec(lua)) !== null) { luaApi.add(m[1]); }

  const missing = [...jsApi].filter((n) => !luaApi.has(n));
  assert.deepEqual(missing, [],
    'engine.lua 缺少导出：' + missing.join(', ') + '（脚本里 E.xxx 会直接 nil 报错）');

  // 反向：Defold 脚本里用到的 E.xxx 必须真的存在
  const used = new Set();
  FILES.filter((f) => /\.(lua|gui_script|script)$/.test(f)
      && f !== 'logic/engine.lua' && f !== 'logic/engine_spec.lua')
    .forEach((f) => {
      const reUse = /\bE\.([A-Za-z_][A-Za-z0-9_]*)/g;
      let x;
      while ((x = reUse.exec(read(f))) !== null) { used.add(x[1]); }
    });
  const badUse = [...used].filter((n) => !luaApi.has(n));
  assert.deepEqual(badUse, [], '脚本用了 engine.lua 没导出的 API：' + badUse.join(', '));
});

test('零第三方依赖：没有库依赖，按钮与命中判定都是自己实现', () => {
  const gp = read('game.project');
  assert.ok(!/^dependencies/m.test(gp),
    'game.project 不应再有库依赖（Druid 与 Defold Event 已移除）');

  const menu = read('menu/menu.gui_script');
  assert.ok(!/druid/i.test(menu), '设置界面不应再引用 Druid');
  assert.ok(!/require\("event\./.test(menu), '设置界面不应引用 Defold Event');
  assert.ok(/wire_buttons\(/.test(menu), '按钮回调应在 wire_buttons 里挂');
  assert.ok(/ui\.pick\(/.test(menu), '命中判定应走 ui.pick（内部 gui.pick_node）');
  assert.ok(/gui\.pick_node/.test(read('logic/ui.lua')), 'ui.pick 内部应使用 gui.pick_node');

  // 选手姓名输入功能已移除
  assert.ok(!/new_input\(/.test(menu), '不该再有文本输入框');
  const st = read('logic/settings.lua');
  assert.ok(!/nameW|nameB/.test(st), '设置里不该再有选手姓名字段');
  const clock = read('clock/clock.gui_script');
  assert.ok(!/nameW|nameB/.test(clock), '棋钟界面不该再引用选手姓名');
  assert.ok(/side_label/.test(clock), '棋钟界面应仍有白方/黑方标签');
});

test('最后 10 秒提示音：主时间也响，四种模式通用（与网页 lastTenTick 对称）', () => {
  const clock = read('clock/clock.gui_script');
  const webApp = fs.readFileSync(path.join(WEB_ROOT, 'app.js'), 'utf8');
  // 关键：不再要求 phase == "byoyomi"
  assert.ok(!/info\.phase == "byoyomi" and st\.running/.test(clock),
    '提示音不应只对读秒阶段生效');
  assert.ok(/ms <= 10000/.test(clock), 'clock.gui_script 应有 10 秒窗口');
  assert.ok(/local turn = st\.moves\.w \+ st\.moves\.b/.test(clock),
    'key 里要带「第几手」，否则 Fischer 加秒后不会重新滴');
  assert.ok(/#sfx_tick/.test(clock), '仍应播 #sfx_tick');
  // 两端窗口一致
  assert.ok(/TICK_LAST_MS = 10000/.test(webApp), '网页版的窗口也应是 10000ms');
});
test('读秒段数条：每块面板一排段，只在 Byoyomi 模式显示（与网页 .byo-bar 对称）', () => {
  const clock = read('clock/clock.gui_script');
  const st = read('logic/settings.lua');
  // 段数上限必须与 settings.lua 的 clamp(1, 20) 一致，否则多的段永远显示不出来
  assert.ok(/periods, 1, 20,/.test(st), 'settings.lua 的段数上限应为 20');
  assert.ok(/MAX_SEGS\s*=\s*20/.test(clock), 'clock.gui_script 的 MAX_SEGS 应等于 20');
  assert.ok(/function layout_pane_bar/.test(clock), '应有 layout_pane_bar()（几何与对坐镜像）');
  assert.ok(/self\.cfg\.mode == "byoyomi"/.test(clock), '非读秒模式应收起段数条');
  assert.ok(/p\.byo_on\[i\] ~= on/.test(clock), '每段颜色只在状态翻转时更新（不逐帧刷）');
  assert.ok(/i <= left/.test(clock), '亮着的格数应等于剩余段数');
  // 颜色：还剩的段绿色（ok）、用掉的段红色（danger）——与网页 --ok / --danger 同一套
  assert.ok(/ui\.C\.ok or ui\.C\.danger/.test(clock), '段数条应是绿/红两色（ok / danger）');
  // 倒计时中的那一段是进度条：红色覆盖块宽度 = 1 - 剩余比例
  assert.ok(/p\.byo_used = ui\.box/.test(clock), '应有一块「已用部分」覆盖色块');
  assert.ok(/local used_w = g\.w \* \(1 - ratio\)/.test(clock),
    '红色宽度应按「1 - 本窗口剩余比例」计算');
  assert.ok(/ui\.C\.ok or ui\.C\.danger/.test(read('clock/clock.gui_script')),
    '段数条颜色应在 clock.gui_script 里设置');
});

test('Defold 图标与网页版同源（都由 ../assets/logo-source.png 导出）', () => {
  const webSource = path.join(WEB_ROOT, 'assets', 'logo-source.png');
  assert.ok(fs.existsSync(webSource), '缺少网页版原图 assets/logo-source.png');

  // 导出脚本必须指向同一张原图 —— 这是「两个版本不会各换各的」的唯一保证
  const script = read('tools/export-logo.js');
  assert.ok(/logo-source\.png/.test(script), 'export-logo.js 应从 ../assets/logo-source.png 导出');
  assert.ok(!/logo\.svg/.test(script), 'export-logo.js 不该再依赖旧的 logo.svg');

  // 旧的 CoQ 矢量图在 Defold 侧已不再需要（网页版还留着一份作参考）
  assert.ok(!fs.existsSync(path.join(ROOT, 'assets', 'logo.svg')),
    'Defold/assets/logo.svg 应已删除（当前图形来自 logo-source.png）');

  // 贴图必须是合法的正方形 PNG，且对两处显示（96 / 48）留足高分屏余量
  const b = fs.readFileSync(path.join(ROOT, 'assets', 'logo.png'));
  assert.equal(b.slice(12, 16).toString('ascii'), 'IHDR', 'assets/logo.png 不是合法 PNG');
  const w = b.readUInt32BE(16);
  const h = b.readUInt32BE(20);
  assert.equal(w, h, 'assets/logo.png 应是正方形（当前 ' + w + '×' + h + '）');
  assert.ok(w >= 192,
    'assets/logo.png 至少 192×192（设置页 96 的 2 倍余量），当前 ' + w + '×' + h +
    '；换图后请重跑 node tools/export-logo.js');
});

test('两个版本的测试用例数一致（移植没漏测）', () => {
  const jsCount = (fs.readFileSync(path.join(WEB_ROOT, 'tests/engine.test.js'), 'utf8')
    .match(/\ntest\(/g) || []).length + 1;   // 文件首个 test( 前没有换行
  const luaCount = (read('logic/engine_spec.lua').match(/\ntest\("/g) || []).length + 1;
  assert.ok(jsCount >= 25, 'engine.test.js 用例数偏少：' + jsCount);
  assert.equal(luaCount, jsCount, 'engine_spec.lua 与 engine.test.js 用例数不一致：' +
    luaCount + ' vs ' + jsCount);
});

// ------------------------------------------------------- 4. Lua 语法体检（无 Defold 时）

function stripLua(text) {
  // 去掉注释与字符串，剩下的才是语法关键字
  return text
    .replace(/--\[\[[\s\S]*?\]\]/g, ' ')      // 块注释
    .replace(/--\[=*\[[\s\S]*?\]=*\]/g, ' ')
    .replace(/--[^\r\n]*/g, ' ')              // 行注释
    .replace(/\[\[[\s\S]*?\]\]/g, '""')       // 长字符串
    .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
    .replace(/'(?:[^'\\\n]|\\.)*'/g, '""');
}

function countWords(text, word) {
  return (text.match(new RegExp('\\b' + word + '\\b', 'g')) || []).length;
}

test('Lua 代码块与括号配平（最低限度语法体检）', () => {
  const luaFiles = FILES.filter((f) => f.endsWith('.lua') || f.endsWith('.gui_script') ||
    f.endsWith('.script'));
  assert.ok(luaFiles.length >= 6, 'Lua 文件太少：' + luaFiles.length);

  luaFiles.forEach((f) => {
    const raw = read(f);
    const code = stripLua(raw);
    // for / while 自带 do，所以只数 do；if 用 if...end 配对
    const openers = countWords(code, 'function') + countWords(code, 'if') + countWords(code, 'do');
    const enders = countWords(code, 'end');
    assert.equal(openers, enders, f + ' 里 function/if/do 与 end 不配平：' +
      openers + ' vs ' + enders);
    assert.equal(countWords(code, 'repeat'), countWords(code, 'until'),
      f + ' 里 repeat 与 until 不配平');
    ['(', ')', '{', '}', '[', ']'].reduce((acc, ch) => {
      acc[ch] = (code.match(new RegExp('\\' + ch, 'g')) || []).length;
      return acc;
    }, {});
    const pairs = [['(', ')'], ['{', '}'], ['[', ']']];
    pairs.forEach(([open, close]) => {
      const a = (code.match(new RegExp('\\' + open, 'g')) || []).length;
      const b = (code.match(new RegExp('\\' + close, 'g')) || []).length;
      assert.equal(a, b, f + ' 里 ' + open + close + ' 不配平：' + a + ' vs ' + b);
    });
    assert.ok(!/---\[\[/.test(raw), f + ' 里有 ---[[ （会关掉块注释，导致中文被当代码）');
  });
});

// ------------------------------------------------------------ 5. 工程结构完整性

test('工程结构完整（入口 / 输入 / 两个界面 / 图标 / 工具）', () => {
  const need = [
    'game.project',
    'input/game.input_binding',
    'main/main.collection',
    'main/game.go',
    'main/main.script',
    'menu/menu.gui', 'menu/menu.gui_script',
    'clock/clock.gui', 'clock/clock.gui_script',
    'logic/engine.lua', 'logic/engine_spec.lua', 'logic/ui.lua',
    'logic/text.lua', 'logic/settings.lua', 'logic/theme.lua',
    'assets/logo.png', 'assets/logo.atlas',
    'assets/fonts/clock.font', 'assets/fonts/ui.font',
    'assets/icons.atlas', 'assets/icons/sound_on.png', 'assets/icons/sound_off.png',
    'assets/icons/swap.png', 'assets/icons/settings.png',
    'assets/sounds/click.wav', 'assets/sounds/tick.wav', 'assets/sounds/alarm.wav',
    'tools/export-logo.js', 'tools/export-icons.js', 'tools/make_sounds.py',
    'tools/build_and_run.ps1', 'tools/screenshot.ps1', 'tools/click_test.ps1',
    'tools/sound_test.ps1',
    'tests/run.js', 'tests/project_spec.js', 'tests/settings_spec.lua', 'README.md',
  ];
  const missing = need.filter((p) => !exists(p));
  assert.deepEqual(missing, [], '缺少文件：' + missing.join(', '));

  const project = read('game.project');
  assert.ok(/main_collection\s*=\s*\/main\/main\.collectionc/.test(project), 'game.project 的入口集合不对');
  assert.ok(/game_binding\s*=\s*\/input\/game\.input_bindingc/.test(project), 'game.project 没绑定输入');

  const bind = read('input/game.input_binding');
  ['press', 'touch_multi', 'key_esc', 'key_a', 'key_l', 'key_space', 'key_f'].forEach((a) => {
    assert.ok(bind.indexOf('"' + a + '"') >= 0, '输入绑定缺少 action：' + a);
  });
  assert.ok(/touch_trigger/.test(bind), '输入绑定缺少触摸');
  assert.ok(/mouse_trigger/.test(bind), '输入绑定缺少鼠标');
  assert.ok(!/text_trigger/.test(bind), '文本输入已移除，绑定里不该再有 text_trigger');

  // main/game.go 必须挂上两个界面与三个声音（一个 game object 装齐，见 README 的架构说明）
  const go = read('main/game.go');
  ['/main/main.script', '/menu/menu.gui', '/clock/clock.gui',
    '/assets/sounds/click.wav', '/assets/sounds/tick.wav', '/assets/sounds/alarm.wav']
    .forEach((c) => assert.ok(go.indexOf(c) >= 0, 'main/game.go 缺少组件：' + c));

  // 两个界面脚本必须处理彼此约定的消息
  const clock = read('clock/clock.gui_script');
  assert.ok(/hash\("begin"\)/.test(clock), '棋钟界面没有处理 begin 消息');
  assert.ok(/back_to_menu/.test(clock), '棋钟界面没有返回设置页的消息');
  const menu = read('menu/menu.gui_script');
  assert.ok(/hash\("settings"\)/.test(menu), '设置界面没有处理 settings 消息');
  assert.ok(/start_game/.test(menu), '设置界面没有发出 start_game 消息');
  const main = read('main/main.script');
  ['start_game', 'back_to_menu', 'save_settings', 'request_settings'].forEach((k) => {
    assert.ok(main.indexOf(k) >= 0, 'main.script 缺少消息处理：' + k);
  });
});

test('输入链路：焦点发给游戏对象、鼠标与触摸分开命名、命中一律用 pick_node', () => {
  // 这一组是「界面完全点不动」那次事故的回归防线，三条都可能单独让点击失效：
  const main = read('main/main.script');

  // 1) acquire_input_focus 必须发给「游戏对象」：它会把该对象下所有能接收输入的组件
  //    （脚本 + GUI）一起压进输入栈；发给 GUI 组件是无效的。
  assert.ok(/msg\.post\("\."\s*,\s*"acquire_input_focus"\)/.test(main),
    'main.script 必须用 msg.post(".", "acquire_input_focus") 抢焦点（发给 GUI 组件无效）');
  assert.ok(!/msg\.post\("#gui[A-Za-z_]*"\s*,\s*"acquire_input_focus"\)/.test(main),
    'acquire_input_focus 不能发给 GUI 组件');

  // 2) 指针动作：桌面鼠标 → "press"，触摸 → "touch_multi"。
  //    两者刻意不同名 —— Defold 手册说过「触摸不能与其它输入同名」。
  const bind = read('input/game.input_binding');
  assert.ok(/mouse_trigger\s*\{[\s\S]*?MOUSE_BUTTON_LEFT[\s\S]*?action:\s*"press"/.test(bind),
    '鼠标左键应绑到 press');
  assert.ok(/touch_trigger\s*\{[\s\S]*?action:\s*"touch_multi"/.test(bind),
    '触摸应绑到 touch_multi（不与鼠标同名）');

  // 3) 命中最不能用「手算矩形」：GUI 场景尺寸（如 720×1280）与窗口尺寸（如 704×1001）
  //    并不相同，引擎派发的坐标与节点坐标也不是同一套，手算必然错位。
  //    两个界面都走 ui.pointer_down + gui.pick_node（设置界面经 ui.pick 包装）。
  const clockSrc = read('clock/clock.gui_script');
  assert.ok(/ui\.pointer_down\(/.test(clockSrc), '棋钟界面的指针输入应走 ui.pointer_down（鼠标+触摸）');
  assert.ok(!/h\s*-\s*action\.y/.test(clockSrc), '不要手算坐标做命中判定（场景≠窗口尺寸时一定错位）');
  assert.ok(/gui\.pick_node/.test(read('clock/clock.gui_script')),
    '棋钟面板命中应使用 gui.pick_node');
  const menuSrc = read('menu/menu.gui_script');
  assert.ok(/ui\.pointer_down\(/.test(menuSrc), '设置界面的指针输入应走 ui.pointer_down');
  assert.ok(/ui\.pick\(/.test(menuSrc), '设置界面的按钮命中应走 ui.pick（内部 gui.pick_node）');
  assert.ok(!/h\s*-\s*action\.y/.test(menuSrc), '设置界面也不要手算坐标做命中判定');
});

// ------------------------------------- 6. 界面字符 vs 字体字形（防豆腐块）

/** 取一段 Lua 源码里的字符串字面量（先去掉注释，中文注释不该参与校验） */
function luaStrings(src) {
  const code = src
    .replace(/--\[\[[\s\S]*?\]\]/g, ' ')
    .replace(/--[^\r\n]*/g, ' ');
  const out = [];
  const re = /"((?:[^"\\\n]|\\.)*)"/g;
  let m;
  while ((m = re.exec(code)) !== null) { out.push(m[1]); }
  return out;
}

test('界面用到的非 ASCII 字符都在 ui.font 里（否则运行期是空白方块）', () => {
  const fontSrc = read('assets/fonts/ui.font');
  const m = fontSrc.match(/characters:\s*"((?:[^"\\]|\\.)*)"/);
  assert.ok(m, 'ui.font 缺少 characters 声明');
  const declared = new Set(Array.from(m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\')));

  // 只看「真正会显示出来」的文案：text.lua 的英文表 + 两个界面的脚本。
  // （text.lua 里的 zh 表是给换字体后用的，默认不加载，所以不参与校验。）
  const textAll = read('logic/text.lua');
  const enStart = textAll.indexOf('en = {');
  const zhStart = textAll.indexOf('zh = {');
  const enBlock = enStart >= 0 && zhStart > enStart ? textAll.slice(enStart, zhStart) : textAll;
  const sources = [
    { file: 'logic/text.lua (en)', src: enBlock },
    { file: 'clock/clock.gui_script', src: read('clock/clock.gui_script') },
    { file: 'menu/menu.gui_script', src: read('menu/menu.gui_script') }
  ];

  const missing = [];
  sources.forEach(({ file, src }) => {
    luaStrings(src).forEach((s) => {
      Array.from(s).forEach((ch) => {
        if (ch.codePointAt(0) > 127 && !declared.has(ch)) { missing.push(file + ': ' + ch); }
      });
    });
  });
  assert.deepEqual([...new Set(missing)], [],
    '这些字符没有字形，显示出来会是空白：\n  ' + [...new Set(missing)].join('\n  ') +
    '\n  （要么写进 assets/fonts/ui.font 的 characters，要么改用 assets/icons 里的图片）');

  // ° 与 × 是界面上确实要用的（180° / 10+3×20），必须真的声明了
  ['°', '×'].forEach((ch) => {
    assert.ok(declared.has(ch), 'ui.font 的 characters 里缺 ' + ch);
  });

  // Vera Sans Mono Bold 没有这些字形：绝不能写进界面文案，只能走图片
  // （注释里提一下没关系——这里先去掉注释，只看真正会显示的字符串）
  const stripComments = (s) => s
    .replace(/--\[\[[\s\S]*?\]\]/g, ' ')
    .replace(/--[^\r\n]*/g, ' ');
  const allLua = FILES.filter((f) => f.endsWith('.lua') || f.endsWith('.gui_script') || f.endsWith('.script'))
    .map((f) => stripComments(read(f))).join('\n');
  ['⇵', '⇅', '⛶', '⚙', '🔊', '🔇'].forEach((ch) => {
    assert.ok(allLua.indexOf(ch) < 0,
      ch + ' 在 Lua 里出现了：内置字体没有这个字形，图标应改用 assets/icons 里的 PNG');
  });
});

// ------------------------------------------------------- 7. 图标资源

test('图标：assets/icons、icons.atlas 与两个 .gui 的注册一一对应', () => {
  const pngs = FILES.filter((f) => f.indexOf('assets/icons/') === 0 && f.endsWith('.png'));
  assert.ok(pngs.length >= 4, 'assets/icons 里的图标太少：' + pngs.length);

  const atlas = read('assets/icons.atlas');
  pngs.forEach((f) => assert.ok(atlas.indexOf('/' + f) >= 0, 'icons.atlas 缺少 ' + f));

  // 白色 + 透明底 + 正方形 + 至少 96（界面按 32 显示 → 3 倍余量）
  pngs.forEach((f) => {
    const b = fs.readFileSync(path.join(ROOT, f));
    assert.equal(b.slice(12, 16).toString('ascii'), 'IHDR', f + ' 不是合法 PNG');
    const w = b.readUInt32BE(16);
    const h = b.readUInt32BE(20);
    assert.equal(w, h, f + ' 应是正方形（当前 ' + w + '×' + h + '）');
    assert.ok(w >= 96, f + ' 至少 96×96（换图标后重跑 node tools/export-icons.js）');
  });

  // 两个 GUI 场景各自都要注册图集贴图名 icons
  readAll('.gui').forEach(({ file, text }) => {
    assert.ok(new RegExp('textures\\s*\\{[^}]*name:\\s*"icons"').test(text),
      file + ' 缺少贴图声明 icons');
  });

  // ui.ICONS 的键和值必须与图集里的图片名一致，界面用到的名字都必须在图集里
  const uiSrc = read('logic/ui.lua');
  const block = (uiSrc.match(/M\.ICONS = \{([\s\S]*?)\n\}/) || [])[1] || '';
  const pairs = [];
  block.replace(/([a-z_]+)\s*=\s*"([a-z_]+)"/g, (all, k, v) => { pairs.push([k, v]); return all; });
  assert.ok(pairs.length >= 4, 'ui.ICONS 解析失败（应至少有 4 个图标）');
  pairs.forEach(([k, v]) => assert.equal(k, v, 'ui.ICONS.' + k + ' 的值应与图片名一致'));

  const images = new Set();
  atlas.replace(/image:\s*"([^"]+)"/g, (all, f) => { images.add(path.basename(f, '.png')); return all; });
  const used = new Set();
  const re = /ICONS\.([a-z_]+)/g;
  const luaAll = read('logic/ui.lua') + read('clock/clock.gui_script');
  let m;
  while ((m = re.exec(luaAll)) !== null) { used.add(m[1]); }
  assert.ok(used.size >= 4, '界面上用到的图标太少：' + used.size);
  [...used].forEach((n) => assert.ok(images.has(n),
    'icons.atlas 里没有 ' + n + '.png（ui.ICONS.' + n + '），运行期会是一张空白'));
});

// ------------------------------------------- 8. 与网页版的行为对齐

test('预设档位与网页版 app.js 一一对应（棋类 11 档 / 读秒 8 档）', () => {
  const app = fs.readFileSync(path.join(WEB_ROOT, 'app.js'), 'utf8');
  const menu = read('menu/menu.gui_script');

  function webPresets(name) {
    const start = app.indexOf('var ' + name + ' = [');
    assert.ok(start >= 0, 'app.js 里找不到 ' + name);
    const body = app.slice(start, app.indexOf('];', start));
    const out = [];
    const re = /\{\s*id:\s*'([^']+)',\s*baseMin:\s*(\d+),\s*incSec:\s*(\d+)(?:,\s*periods:\s*(\d+))?/g;
    let m;
    while ((m = re.exec(body)) !== null) {
      out.push({ id: m[1], baseMin: +m[2], addSec: +m[3], periods: m[4] ? +m[4] : 0 });
    }
    return out;
  }

  function luaPresets(name) {
    const start = menu.indexOf('local ' + name + ' = {');
    assert.ok(start >= 0, 'menu.gui_script 里找不到 ' + name);
    const body = menu.slice(start, menu.indexOf('\n}', start));
    const out = [];
    const re = /\{\s*baseMin\s*=\s*(\d+),\s*addSec\s*=\s*(\d+)(?:,\s*periods\s*=\s*(\d+))?/g;
    let m;
    while ((m = re.exec(body)) !== null) {
      out.push({ id: (m[3] ? m[1] + '+' + m[3] + 'x' + m[2] : m[1] + '+' + m[2]),
        baseMin: +m[1], addSec: +m[2], periods: m[3] ? +m[3] : 0 });
    }
    return out;
  }

  [['PRESETS_CHESS', 11], ['PRESETS_BYOYOMI', 8]].forEach(([name, count]) => {
    const web = webPresets(name);
    const lua = luaPresets(name);
    assert.equal(web.length, count, 'app.js 的 ' + name + ' 档数变了：' + web.length);
    assert.deepEqual(lua, web, name + ' 与网页版不一致（两边必须同一套档位）');
  });
});

test('默认设置与网页版 DEFAULTS 一致（Byoyomi 10+3×20）', () => {
  const app = fs.readFileSync(path.join(WEB_ROOT, 'app.js'), 'utf8');
  const dStart = app.indexOf('var DEFAULTS = {');
  assert.ok(dStart >= 0, 'app.js 里找不到 DEFAULTS');
  const dBody = app.slice(dStart, app.indexOf('};', dStart));
  const webVal = (k) => {
    const m = dBody.match(new RegExp('\\b' + k + ':\\s*([^,\\n]+)'));
    // app.js 的某些默认值后面跟着 // 注释，去掉再比
    return m ? m[1].replace(/\/\/.*$/, '').trim() : null;
  };

  const st = read('logic/settings.lua');
  const sStart = st.indexOf('M.DEFAULTS = {');
  assert.ok(sStart >= 0, 'settings.lua 里找不到 M.DEFAULTS');
  const sBody = st.slice(sStart, st.indexOf('}', sStart));
  const luaVal = (k) => {
    const m = sBody.match(new RegExp('\\b' + k + '\\s*=\\s*([^,\\n]+)'));
    return m ? m[1].replace(/--.*$/, '').trim() : null;
  };

  assert.equal(webVal('mode'), "'byoyomi'");
  assert.equal(luaVal('mode'), '"byoyomi"', '首次启动的模式应与网页版一致');
  assert.equal(luaVal('baseMin'), webVal('baseMin'), '默认基础时间与网页版不一致');
  assert.equal(luaVal('addSec'), webVal('incSec'), '默认每手秒数与网页版不一致');
  assert.equal(luaVal('periods'), webVal('periods'), '默认段数与网页版不一致');
  assert.equal(luaVal('sound'), webVal('sound'));
  assert.equal(luaVal('facing'), webVal('facing'));
  assert.equal(luaVal('swapped'), webVal('swapped'), '交换两侧的默认值应与网页版一致');
  assert.equal(webVal('theme'), "'dark'");
  assert.equal(luaVal('theme'), '"dark"', '默认主题应与网页版一致（深色）');
});

test('三套主题的色值与网页版 styles.css 一致（还有主题名与顺序）', () => {
  const css = fs.readFileSync(path.join(WEB_ROOT, 'styles.css'), 'utf8');
  const app = fs.readFileSync(path.join(WEB_ROOT, 'app.js'), 'utf8');
  const lua = read('logic/theme.lua');

  // 主题名与顺序：web 的 THEMES 数组 ↔ theme.lua 的 M.ORDER
  const mThemes = app.match(/var THEMES = \[([^\]]+)\]/);
  assert.ok(mThemes, 'app.js 里找不到 THEMES');
  const webThemes = mThemes[1].split(',').map((s) => s.trim().replace(/['"]/g, '')).filter(Boolean);
  const orderBlock = (lua.match(/M\.ORDER = \{([^}]+)\}/) || [])[1];
  assert.ok(orderBlock, 'theme.lua 里找不到 M.ORDER');
  const luaOrder = orderBlock.split(',').map((s) => s.trim().replace(/['"]/g, '')).filter(Boolean);
  assert.deepEqual(luaOrder, webThemes, '主题按钮的顺序应与网页版的 THEMES 一致');

  // 每个主题块的变量 vs theme.lua 里的十六进制字符串
  function cssVars(themeName) {
    const start = css.indexOf(':root[data-theme="' + themeName + '"] {');
    assert.ok(start >= 0, 'styles.css 缺少主题 ' + themeName);
    const body = css.slice(start, css.indexOf('}', start));
    const vars = {};
    body.replace(/--([a-z0-9-]+):\s*([^;]+);/g, (all, k, v) => { vars[k] = v.trim().toLowerCase(); return all; });
    return vars;
  }
  function luaVars(themeName) {
    const start = lua.indexOf('  ' + themeName + ' = {');
    assert.ok(start >= 0, 'theme.lua 缺少主题 ' + themeName);
    const body = lua.slice(start, lua.indexOf('}', start));
    const vars = {};
    body.replace(/([a-z_]+) = "(#[0-9a-fA-F]{6})"/g, (all, k, v) => { vars[k] = v.toLowerCase(); return all; });
    return vars;
  }

  // theme.lua 的键 -> styles.css 的变量名（故意用不同的名字：card2 / clock_bg 是 Defold 侧自己的）
  const MAP = {
    bg: 'bg', card: 'card', line: 'line', fg: 'fg', muted: 'muted',
    accent: 'accent', accent_ink: 'accent-ink', ok: 'ok', warn: 'warn', danger: 'danger',
    strip: 'strip-bg', clock_bg: 'clock-bg',
    w_face: 'w-face', w_ink: 'w-ink', w_low: 'w-low', w_crit: 'w-crit',
    b_face: 'b-face', b_ink: 'b-ink', b_low: 'b-low', b_crit: 'b-crit',
    byo_w: 'byo-w', byo_b: 'byo-b',
  };

  // styles.css 里可能用 #000 这种三位简写，统一展开成六位再比
  const expand = (hex) => (hex.length === 4
    ? '#' + hex[1] + hex[1] + hex[2] + hex[2] + hex[3] + hex[3]
    : hex);

  webThemes.forEach((name) => {
    const cv = cssVars(name);
    const lv = luaVars(name);
    Object.keys(MAP).forEach((luaKey) => {
      const rawCss = cv[MAP[luaKey]];
      if (!rawCss || rawCss.charAt(0) !== '#') { return; }   // 该主题没覆盖这个变量（继承 dark）→ 跳过
      const cssVal = expand(rawCss);
      assert.equal(lv[luaKey], expand(cssVal),
        name + ' 主题的 ' + luaKey + ' 与 styles.css 的 --' + MAP[luaKey] + ' 不一致：' +
        lv[luaKey] + ' vs ' + cssVal);
    });
  });
});

test('开局方式：没有 Start 按钮，拍对侧开表且第一下不算步数', () => {
  const clock = read('clock/clock.gui_script');
  const T = read('logic/text.lua');

  // 棋钟页没有「开始」按钮（开局靠拍面板）
  assert.ok(!/btn_start/.test(clock), '棋钟界面不该再有 START 按钮');
  assert.ok(!/btn_start/.test(T), 'text.lua 里不该再有 btn_start 文案');
  assert.ok(/E\.other\(side\)/.test(clock), '未开表时应由「对侧」开表（E.other(side)）');
  assert.ok(/not self\.state\.started then return end/.test(read('clock/clock.gui_script')),
    '未开表时暂停按钮应是空操作');

  // 暂停/继续只写一个字：P / C；对坐按钮写 180°
  assert.ok(/btn_pause\s*=\s*"P"/.test(T), '暂停按钮的文案应是 P');
  assert.ok(/btn_resume\s*=\s*"C"/.test(T), '继续按钮的文案应是 C');
  assert.ok(/btn_facing\s*=\s*"180°"/.test(T), '对坐按钮的文案应是 180°');

  // 新增的「交换两侧」：设置里有键、界面有按钮、旋转跟着视觉第一块走
  assert.ok(/swapped\s*=\s*false/.test(read('logic/settings.lua')), '设置里应有 swapped（默认 false）');
  assert.ok(/toggle_swap/.test(clock), '棋钟界面应有交换两侧的按钮回调');
  assert.ok(/ui\.ICONS\.swap/.test(clock), '交换两侧应是图标按钮');
  assert.ok(/cfg\.swapped/.test(clock), '布局应按 swapped 决定哪一块在上');
  assert.ok(/side == top/.test(clock),
    '对坐旋转必须跟随「视觉上第一块」，不能固定给某一方');

  // 未开表 / 已结束 → 整颗暂停按钮隐藏
  assert.ok(/gui\.set_enabled\(self\.btn_toggle\.box, live\)/.test(clock),
    '未开表时暂停按钮应隐藏（只有开表后才出现 P / C）');
});
