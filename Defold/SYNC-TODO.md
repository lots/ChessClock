# Defold 版同步清单（对齐 web 版近期改动）

> 状态：**已执行**（2026-10-20）——第一、二节全部落地，第三节的编译 / 打包 / 截图 / 点击回归
> 都真跑过；逐项证据与遗留项见文末「六、执行记录」
>
> ⚠️ **这份文件是那一天的执行记录，不是当前的界面说明书。** 之后三端又一起改过若干界面，
> 现在的真实行为以 [`Defold/README.md`](README.md) 为准。本清单之后发生的改动（简要）：
>
> | 改动 | 现在的样子 |
> | --- | --- |
> | 时间预设 | 宫格 → **下拉框**（一档一行「10+3×20」，最后多一档「CUSTOM / 自定义」）；读秒档不再有 `sub` 小字 |
> | 「怎么用」 | 从设置页正文搬到**单独一页**，设置页底部留 `HOW TO USE >` 入口 |
> | 读秒段数条 | **数字与步数行之间**一条分段条：绿 = 还剩、红 = 已用；倒计时那一段按本窗口剩余比例由绿变红；厚度比最初加厚 10% |
> | 0 值规则 | 读秒模式下**主时间与读秒秒数各可为 0**（不能同时为 0）：纯读秒 / 只有主时间 |
> | 提示音 | 最后 10 秒每秒「滴」不再只限读秒阶段，**主时间与读秒窗口都算，四种模式通用** |
> | 测试数 | `node tests/run.js` **20/20**；`engine_spec` 31 个用例、`settings_spec` 13 个 |
>
> 下面表格里的「18/18」「仍是英文单语 + 单一样式」等说法，都属于当时的状态。
> web 版基准提交：`ac4ee05`（`lots/ChessClock`）
> 目标：Defold 移植版在**行为与文案**上与 web 版一致；**唯一允许的差异**是它仍是英文单语、且没有主题切换（若要做，另开任务）。

---

## 一、要从 web 版同步过来的行为（按重要性排序）

| # | 项 | web 版的真实行为（Defold 需照此实现） |
| --- | --- | --- |
| 1 | **开局方式**（最重要） | **没有「Start」按钮**。进棋钟页后拍**对侧**面板即开表：拍黑方 → **白方的钟开始走**（反之亦然，拍白方 → 黑方走）。这**第一下不算步数**（两边步数仍 0/0）。此后每次拍自己那一侧 = 走完一手，时间交给对方。 |
| 2 | 暂停/继续按钮 | 只有一颗，**未开表时隐藏**；文案是 **`P`**（进行中）/ **`C`**（已暂停）。悬停/无障碍文案才是完整的 Pause / Resume（Defold 无悬停，可忽略）。 |
| 3 | Byoyomi 预设 | 8 档：`5+3×20`、**`10+3×20`**、`10+3×30`、`15+3×30`、`20+5×30`、`30+5×30`、`30+3×60`、`60+5×60`。记法 = **基础时间 + 段数 × 每手秒数**。 |
| 4 | Byoyomi 默认值 | 首次启动 = `10+3×20`（10 分钟 / 每手 20 秒 / 3 段）。**且从其它模式切到 Byoyomi 时**，若当前时间制式不属于上面 8 档，自动套用 `10+3×20`；已是某档则保留不动。 |
| 5 | 对坐按钮文案 | **`180°`**（原为 `⇅`）。功能不变：竖屏下把对面那块面板数字旋转 180°。 |
| 6 | **新增：交换两侧** | 新按钮 **`⇵`**：交换两块面板的**屏幕位置** —— 横屏左右互换（白左黑右 ⇄ 白右黑左），竖屏上下互换。**旋转必须跟着"视觉上第一块"走**：交换后，被旋转的应变成另一块（web 版用 `.is-far` 类按视觉位置打标，而不是 DOM 顺序）。 |
| 7 | 说明文案 | 「怎么用」里关于裁判的句子要改：**点「开始对局」后没有第二次「开始」**，由不该先走的一方（白先走时是黑方）拍自己那一侧 → 白方的钟开始走；此后谁走完棋拍自己那侧 → 对方的钟开始走。 |
| 8 | 静音/全屏/设置图标 | 与 web 版一致（见下一节的字形/图片决策）。 |
| 9 | 存档迁移 | 旧存档若带 `started=true` 或旧的默认（Fischer 10+5 等），要能平滑读取；必要时加 `settingsVersion` 并用默认值补全。 |

**不需要同步的**：双语（web 版中英切换 ✗）——Defold 版目前是英文单语（内置字体没有中文字形，换字体即可，见 README）。

**原计划外的补充**：清单交出去之后，用户指出「网页版设置页有界面主题，Defold 版没有」，
所以三套主题（light / medium / dark）也一并同步了 —— 见文末「执行记录 · 七」。

---

## 二、按钮字形 vs 图片（用户明确问的那一点）

当前 Defold 版按钮是用**文字字形**画的（`⇅`、`⛶`、`⚙`、`🔊` 等）。风险是**字体覆盖不足 → 显示为空白/豆腐块** ✗，尤其：

| 按钮 | 字符 | 码位 | 风险 |
| --- | --- | --- | --- |
| 对坐 | `180°` | ASCII + U+00B0 | ✅ 几乎零风险（建议**保持文字**） |
| 交换两侧 | `⇵` | U+21F5 | ⚠️ 中等（Arrows 区，很多字体有，但不是全部） |
| 暂停/继续 | `P` / `C` | ASCII | ✅ 零风险（**保持文字**） |
| 全屏 | `⛶` | U+26F6 | ⚠️ 较高（Miscellaneous Symbols 区，常见缺失） |
| 设置 | `⚙` | U+2699 | ⚠️ 较高（同上，且部分字体会渲染成彩色 emoji） |
| 声音 | `🔊` | U+1F50A | ❌ **很高**（emoji 区；文本字体基本没有，或渲染成彩色） |

### 决策流程（先测再改，别凭猜）

1. **先验证**：用 Defold 的 `.font`（`assets/fonts/*.font`，基于某个 TTF 的 distance-field 字体）实际渲染这 6 个字符，截图看有没有缺字/豆腐块。也可以在构建机外先查该 TTF 的 cmap 是否含这些码位。
2. **若全部正常** → 保持文字，收工（零额外资源 ✓）。
3. **若有缺字或渲染不一致** → 按用户建议**改为图片**，推荐做法：
   - 只把**有风险的图标按钮**换成图片；`180°`、`P`、`C`、以及所有正文/数字**继续用文字**（ASCII 永远安全 ✓）。
   - 用 web 版已经验证过的同款工具导出：`tools/export-icons.js`（无头 Chrome）→ 输出**白色**（`currentColor` → `#fff`）透明背景 PNG，按 3 倍尺寸导出（如 24/48/96），与 web 版"一个用途一个文件"的原则一致 ✓。
   - 在 Defold 里打一个 `assets/icons.atlas`（参照现有 `assets/logo.atlas`），按钮用 `gui.new_box_node` / `gui.set_texture` 显示图片，并用 `gui.set_size` 对齐 40×40 的按钮尺寸。
   - 图片**不随主题变色** ✗（可接受：Defold 版没有主题 ✓）；如果将来要做主题，得为每种主题各出一套颜色 ✗。

---

## 三、验证清单（必须真跑，不能只看代码）

1. `Defold/tools/build_and_run.ps1` 用 `bob` 重新构建（注意：`bob` 用 `--settings`，没有 `--config`；有依赖时先 `bob resolve`）。
2. `Defold/tests/run.js` 必须保持 **18/18**（静态校验 16 个 + 引擎与设置两个 Lua 单测入口）
   + **30/30** 引擎用例（与 web 版 `engine.test.js` 一一对应，不能因同步而漂移 ✗）
   + **13/13** 设置用例（默认值 / 旧存档迁移 / 主题）。本轮同步新增的静态校验：字形覆盖、图标资源、
   预设与默认值同源、开局方式（这几条正是本次改动最容易回归的地方）。
3. 打包 exe 跑起来看 `log.txt`（项目 `write_log_file = 2`；引擎把日志写到**启动进程的 CWD**，不是 exe 目录 ✗）。
4. `Defold/tools/screenshot.ps1` 截 **menu / clock / overlay** 三张，人工核对：`180°`、`⇵`、`P`/`C` 显示正确；交换两侧后**被旋转的是另一块**。
5. `Defold/tools/click_test.ps1` 做一次点击回归（已知坑：`acquire_input_focus` 必须发给**游戏对象** `msg.post(".", …)`；`gui.pick_node` 要传**原始 action.x/y**；`window.get_size()` 返回**两个**值）。

---

## 四、已知约束（别踩）

- `game.project` 与资源文件**不能有注释** ✗；写文件必须**无 BOM 的 UTF-8** ✗（BOM 会让解析失败）。
- Defold 版**没有**中英双语、没有主题、没有 `swapped` 存档键 —— 新增设置项时同时处理"旧存档缺键"的情况。
- `Defold/` 在 web 仓库里是通过**子目录的 `.gitignore`** 跟踪源码、排除 `build/ bundle/ .internal/ *.log` 的 ✓（见根 `PAGES.md` 与 `Defold/.gitignore`）。

---

## 五、本轮改了哪些文件（速查）

| 文件 | 改动 |
| --- | --- |
| `logic/settings.lua` | 默认值换成 Byoyomi 10+3×20；新增 `swapped`；`settingsVersion = 2` + `M.migrate()` |
| `logic/text.lua` | `P`/`C`、`180°`、两行「没有第二次开始」提示；删掉 START / SFX / FLIP / MENU 文案 |
| `logic/ui.lua` | `ui.ICONS` / `ui.icon()` / `ui.make_icon_button()`（图集 + flipbook） |
| `menu/menu.gui_script` | 预设按模式切换（棋类 11 档 / 读秒 8 档）；切进读秒自动套 10+3×20；提示文案；行数随预设变化 |
| `clock/clock.gui_script` | 拍对侧开表；P/C 未开表隐藏；`180°`；新增交换两侧；操作条 5 颗按钮；图标按钮 |
| `main/main.script` | 窗口 resize → 转发 `relayout`（原来 `window_resized` 分支是死代码）；新增运行期开关 `reset_settings` / `demo_quick` / `demo_swapped` |
| `assets/fonts/ui.font` | characters 增加 `°` `×`（实测 Vera Sans Mono Bold 有这两个字形） |
| `assets/icons/*.png`、`assets/icons.atlas`、两个 `.gui` | 4 张白色透明图标 + 图集 + 贴图注册 |
| `tools/export-icons.js` | 新增：纯 Node 光栅化器，生成上面 4 张图标（不依赖浏览器/npm） |
| `tools/screenshot.ps1`、`tools/click_test.ps1` | 按标题找游戏窗口、藏掉控制台、点击坐标每次重读、点击流程跟着新行为改；截图新增 `clock-swapped`（不用点鼠标）与 `overlay`（键盘 A 开表 + 等 60 秒）两个场景 |
| `tests/project_spec.js` | 新增 5 个静态用例（字形、图标、预设/默认值同源、开局方式） |
| `tests/settings_spec.lua`、`tests/run.js` | 新增设置单测（12 个用例）并接入一键测试 |

---

## 六、执行记录（2026-10-20）

### 一、行为同步（逐项）

| # | 状态 | 实现位置与证据 |
| --- | --- | --- |
| 1 开局方式 | ✅ | `clock/clock.gui_script` 的 `engine_press`：`target = started and side or E.other(side)`；日志 `DBG clock press side=b target=w result=start moves=0`（第一下不算步数）；棋钟页已没有 START 按钮 |
| 2 暂停/继续 | ✅ | 只有一颗按钮，未开表/已结束时整颗隐藏（且不占位，其余按钮左移）；文案 `P` / `C` |
| 3 Byoyomi 预设 | ✅ | 8 档，按钮上写 `10+3×20`（基础 + 段数 × 每手秒数）；棋类模式换成 web 的 11 档；`project_spec` 与 `../app.js` 逐档比对 |
| 4 Byoyomi 默认 | ✅ | `settings.lua` DEFAULTS = byoyomi / 10 / 20 / 3；`seed_byoyomi_default()`：当前数字已是 8 档之一则保留，否则套 10+3×20 |
| 5 对坐文案 | ✅ | `180°`（`°` 已加进 `ui.font` 的 characters） |
| 6 交换两侧 | ✅ | 新按钮（`assets/icons/swap.png`）+ `cfg.swapped`；`layout()` 用 `top_side()` 决定谁在上，`p.flip = facing and side == top` —— 旋转跟随「视觉上第一块」；截图 `tests/screenshots/clock-swapped.png` 就是交换后的样子（白方在上并被旋转，可用 `tools/screenshot.ps1 -Scene clock-swapped` 无鼠标重拍） |
| 7 说明文案 | ✅ | 设置页新增两行：`NO SECOND START: tap the side not to move first (Black) - White's clock runs` / `After your move tap your own side - the opponent's clock runs` |
| 8 图标 | ⚠ 部分 | 声音（开/关）、交换、设置 → 白色 PNG；`180°` / `P` / `C` 保持文字。**全屏按钮没做**：Defold 引擎没有运行期全屏 API（`display.fullscreen` 只能在打包时定），加一颗点不动的按钮不如不加 |
| 9 存档迁移 | ✅ | `settingsVersion = 2` + `M.migrate()`；旧存档缺 `swapped` 补 false，语义没变的键原样保留；`tests/settings_spec.lua` 12 个用例（含「旧存档 Fischer 10+5 原样读取」「损坏存档回落默认」「幂等」） |

### 二、字形 vs 图片（用实测数据定案）

用 Node 解析 Defold 内置字体 `vera_mo_bd.ttf` 的 cmap 表（ 代码见提交历史，结论如下）：

| 字符 | 码位 | 字体里有字形？ | 结论 |
| --- | --- | --- | --- |
| `°` | U+00B0 | ✅ 有 | 文字：`180°` |
| `×` | U+00D7 | ✅ 有 | 文字：`10+3×20` |
| `P` / `C` | ASCII | ✅ 有 | 文字 |
| `⇵` | U+21F5 | ❌ 没有 | 图片 `assets/icons/swap.png` |
| `⚙` | U+2699 | ❌ 没有 | 图片 `assets/icons/settings.png` |
| `🔊` / `🔇` | U+1F50A | ❌ 没有 | 图片 `sound_on.png` / `sound_off.png` |
| `⛶` | U+26F6 | ❌ 没有 | 未使用（全屏按钮没做） |

所以按第二节的决策流程走到「有缺字 → 改图片」这一支，但只改有风险的四个，
`180°`、`P`/`C`、所有正文与数字继续用文字。`tests/project_spec.js` 现在会：
① 检查界面上用到的每个非 ASCII 字符都在 `ui.font` 的 characters 里；
② 禁止 `⇵ ⛶ ⚙ 🔊` 出现在 Lua 字符串里（注释不算）。

### 三、验证（都是真跑，不是只看代码）

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 依赖 / 编译 / 打包 / 冒烟 | `tools/build_and_run.ps1` | resolve OK、build OK、bundle OK，跑 10 秒无 `ERROR:SCRIPT`；日志 `clock screen ready - 10 min + byoyomi 20s x3 - Byoyomi` |
| 测试 | `node tests/run.js` | **18/18**（静态 16 + 两个 Lua 单测入口）；引擎 **30/30**、设置 **13/13** |
| 截图 | `tools/screenshot.ps1 -Scene menu` / `-Scene clock` | 见 `tests/screenshots/menu.png`、`clock.png`；`180°`、`⇵`、`⚙`、`🔊` 显示正确，无豆腐块 |
| 点击回归 | `tools/click_test.ps1` | 一次完整通过：5 项断言全 [OK]（mode 按钮 / 拍对侧开表 `side=b target=w result=start` / 走一手 `result=move` / 交换两侧 `swapped=true` / P↔C 暂停继续），无脚本错误。⚠️ 之后在本会话里注入的鼠标点击开始被系统吞掉（窗口拿不到前台、坐标对不上），脚本会按「预期日志出现」重试 8 次，可能仍有 FAIL —— 这是环境问题，已在 README 里写明 |
| 超时结算层 | `tools/screenshot.ps1 -Scene overlay`（`demo_quick` 1 分钟无加秒 + 用键盘 A 开表，等 60 秒） | 结算卡片正常弹出：`BLACK TIME UP / WHITE WINS / 1 min - Sudden death - 0 MOVE`，截图存 `tests/screenshots/overlay.png`（键盘不依赖光标，比注入鼠标可靠） |
| 交换两侧的样子 | `tools/screenshot.ps1 -Scene clock-swapped`（`demo_swapped`） | 不用点鼠标就能拍到：白方在上并被旋转、黑方在下，截图存 `tests/screenshots/clock-swapped.png` |

### 四、顺手修掉的两个真 bug（不在清单里，但会挡住验证）

1. **`window_resized` 从来没有被发送过**：`main.script` 与两个 GUI 里的 `on_message` 分支是死代码。
   现在用 `window.set_listener` 接住 resized，下一帧的 `update` 里转发自定义消息 `relayout`。
   两个坑：window 回调里不能直接 `msg.post`；消息名也不能用引擎内置的 `window_resized`
   （它是带 width/height/display_profile 必填字段的 DDF 消息，空表发出去会报
   `Field %s not specified in table`）。
2. **调试版 exe 的控制台窗口**会被 `Process.MainWindowHandle` 选中，还会压在游戏窗口上——
   截图截到控制台、点击被它吃掉。`tools/screenshot.ps1` 与 `tools/click_test.ps1` 现在都
   按「同进程 + 标题里不含 `.exe`」找游戏窗口，并把控制台 `ShowWindow(…, 0)` 藏掉。

另外，`tools/click_test.ps1` 的点击坐标改成**每次点击前重新读**（窗口尺寸 / 界面切换都会让
layout 重算），并在开跑前删掉 `bundle` 里上一轮留下的 `chessclock_settings`——否则上一轮
测试打开的「交换两侧」会带进这一轮，导致点 pane_b 点到白方那块。

### 七、追加：界面主题（原清单外，用户提出后补做）

| 项 | 实现 |
| --- | --- |
| 三套配色 | `logic/theme.lua`：浅色 / 中性 / 深色，色值**直接沿用 styles.css 的十六进制字符串**（运行时才转 0..1），`tests/project_spec.js` 与 styles.css 的三个 `data-theme` 块**逐值比对** |
| 设置页 | 新增「COLOUR THEME」一行：LIGHT / MEDIUM / DARK 三个按钮（与网页版下拉框同序），选中项高亮；选择存进 `settings.theme`，默认 `dark`（与网页版 `DEFAULTS.theme` 一致） |
| 棋钟页 | 换主题时两个界面各自**整屏重建**（颜色是建节点时写死的，Defold 没法按变量重刷） |
| 对局语义 | 两块面板始终「黑方深、白方浅」（不随主题变），light 主题把白方面板提亮成纯白并加一条浅色描边（对应 web 的 `--pane-edge`） |
| 图标 | 白色 PNG 用 `set_color` 染色：浅色主题染成深色，蓝色按钮上用 `accent-ink` |
| 两个坑（都踩过） | ① 所有脚本共享同一个 Lua 状态 → `ui` 里的节点登记必须**按界面分开**，否则删设置页节点时会报 `Node used in the wrong scene`；② 「主题变没变」也必须**按界面**记（`self.theme`），因为另一个界面可能已经把共享调色板换掉了 |
| 验证 | `menu-light.png` / `menu-medium.png` / `clock-light.png` 三张截图人工核对；`node tests/run.js` **18/18** |

### 五、环境问题（已绕过，不是代码问题）

`build/default/game.arci` 与 `game.arcd` 带着「不继承父目录权限」的 ACL（应该是更早一次
**沙箱外**构建留下的），bob 重建这两个文件时报 `AccessDeniedException`，而文件对当前用户
其实是 FullControl。把整个 `build/` 挪走再编译即可（本次就是这么做的）。

### 六、仍未做 / 未验证

- **真机**：Android / iOS / HTML5 的触摸手感、音频延迟、导出流程（需要真机或浏览器）；
- **横屏**：Defold 版固定竖屏上下分屏（`display.dynamic_orientation = 0`），
  「交换两侧」在它是上下互换；web 的横屏左右分屏没做；
- **全屏**：引擎没有运行期 API（见上文第 8 项）；
- **主题 / 双语**：仍按清单不做（本版英文单语 + 单一样式）；
- **标志点击循环**：网页版点 logo 会在 TARUMT → CoQ → Chess → 围棋 → MWA 之间循环、并存进设置；
  Defold 版仍是 `assets/logo.png` 一张静态贴图（`menu.gui` / `clock.gui` 各一个 `texture` 节点），
  要移植时：把五张图并进 `logo.atlas`（或用 5 个贴图），给菜单和操作条的 logo 节点加 `pick_node` 命中，
  状态存进 `logic/settings.lua` 的同名字段。
