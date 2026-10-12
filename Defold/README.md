# CoQ 棋钟 · Defold 版

> 网页版说明：[English](../README.md) · [华文](../README_CN.md)

这是仓库根目录那个网页棋钟的 **Defold（Lua）移植版**：同一个产品、同一套计时语义，
换成游戏引擎实现，可以打包成 Windows / macOS / Linux / Android / iOS / HTML5 原生应用。

计时逻辑在 `logic/engine.lua` 里是**纯 Lua、无引擎依赖**的模块，与网页版的 `engine.js`
一一对应（连常量都做了自动比对测试），因此两个版本的行为不会漂移。

![设置界面](tests/screenshots/menu.png)
![棋钟界面](tests/screenshots/clock.png)
![超时结算层](tests/screenshots/overlay.png)

---

## 一、已验证到什么程度（先读这个）

我没有只"写完就交"，凡是这台机器能跑的都真跑了：

| 验证项 | 方法 | 结果 |
| --- | --- | --- |
| 计时语义（加秒 / 延时 / 读秒 / 超时） | `lua logic/engine_spec.lua`（与网页版一一对应的 30 个用例，Lua 5.1.5 执行） | **30/30 通过** |
| 资源格式 + Lua 编译 | Defold 1.13.1 自带命令行构建器 `bob` | **build exit 0** |
| 打包成可执行程序 | `bob bundle --platform x86_64-win32` | **生成 ChessClockDefold.exe** |
| 运行期正确性 | 运行打包产物 10 秒，读 `log.txt` | **无 ERROR:SCRIPT**；日志确认两个界面都构建成功、计时源是 `socket.gettime` |
| 界面外观 | `tools/screenshot.ps1` 抓游戏窗口（见上面两张图） | 布局、旋转、配色、按钮均正确 |
| **输入链路（真实点击）** | `tools/click_test.ps1` 往窗口注入真实鼠标点击 | 模式按钮、START GAME、面板开表与走子**全部生效**（见第五节） |
| **超时结算层** | 同上，加 `-PresetId 1 -FlagWaitSeconds 70` | 一方超时后结算卡片正常弹出（曾因 `E.other` 未导出而崩溃），见 `tests/screenshots/overlay.png` |
| 工程静态一致性 | `node tests/run.js` | **10/10 通过**（见第五节） |

**还没验证的**（需要真机或编辑器，属于你接下来要做的事）：

* 真机触摸手感、iOS/Android/HTML5 的导出与实机表现；
* 极端分辨率/宽高比下的排版（设计基准 720×1280，已做自适应与 `window_resized` 重排）；
* Defold 编辑器里首次打开时的资源导入（`bob` 已经说明格式没问题，但编辑器可能提示重建缓存，属正常）。

---

## 二、怎么跑起来

### A. 用 Defold 编辑器（推荐）

1. 装 [Defold 1.13+](https://defold.com/download/)；
2. 编辑器里 `File → Open Project…`，选本目录的 **`game.project`**；
3. 按 `F5`（或 `Project → Build and Run`）。

命令行入口脚本 **`tools/build_and_run.ps1`** 需要本机已装过 Defold（它会自动从
`%LOCALAPPDATA%\Defold\installations.json` 找到 bob 与内置 JDK）。

### B. 只用命令行（不打开编辑器）

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_and_run.ps1
```

它会依次：`bob --archive build`（编译全部资源与 Lua）→ `bob bundle`（打包）→
运行产物 10 秒 → 读 `log.txt`，最后打印 `RESULT: ...`。这是 CI 式的完整校验。

### C. 导出到手机 / 网页

编辑器 `Project → Bundle…`，选 Android / iOS / **HTML5** 等平台即可。
命令行的等价做法是 `bob bundle --platform js-web`（HTML5）或 `--platform arm64-android`，
发布版记得加 `--variant release`（此时不会写日志）。

> `game.project` 里的 `write_log_file = 2` 表示"总是写日志"：打包产物会在启动目录留一份很小的
> `log.txt`。这是有意的——自动化验证要靠它核对行为，比赛现场出问题时用户手边也直接有一份日志。
> 想安静就改成 `1`（仅调试版），但那样 `tools/click_test.ps1` 会读不到日志。

---

## 三、操作方式

| 操作 | 说明 |
| --- | --- |
| 拍自己那半屏 | **整块半屏就是按键**（上方黑方、下方白方），点一下即完成一手 |
| 触摸 / 鼠标 | 都映射到同一个 `press` 动作，脚本按坐标判断按的是哪一侧 |
| `A` / `L` | 键盘模拟白方 / 黑方按键（电脑上当棋钟用时很方便） |
| `空格` | 开始 / 暂停 / 继续 |
| `F` | 对坐模式开关（把对面那块面板整体旋转 180°） |
| `ESC` | 返回设置页 |

界面上还有中间操作条：`START / PAUSE / RESUME`、`SFX`（声音）、`FLIP`（对坐）、`MENU`（返回设置）。

* **对坐模式**：默认开启，上方（黑方）面板整体旋转 180°，坐在对面的选手看到的是正的；
  手机上平放两人对坐时就这样用。把手机立起来给裁判/观众看时，按 `F` 或点 `FLIP` 关掉即可。
* **读秒阶段**：数字转紫，步数行显示剩余段数（如 `2/3 SEG`），最后 10 秒每秒滴答一次。
* **超时**：停表 + 警报音 + 结算层（`REMATCH` / `MAIN MENU`）。

---

## 四、目录结构与架构

```
Defold/
├── game.project              工程配置（分辨率、入口集合、输入绑定、写日志策略；无第三方依赖）
├── input/game.input_binding  触摸 / 鼠标 / 键盘 → action（见下）
├── main/
│   ├── main.collection       启动集合
│   ├── game.go               一个 game object 装齐：总控脚本 + 两个界面 + 三份音效
│   └── main.script           总控：设置持久化 + 界面切换
├── menu/
│   ├── menu.gui              GUI 场景（声明字体与贴图、背景色）
│   └── menu.gui_script       设置界面：模式 / 时间步进器 / 预设 / 声音 / 开始
├── clock/
│   ├── clock.gui
│   └── clock.gui_script      棋钟界面：两块面板 + 操作条 + 超时结算层
├── logic/
│   ├── engine.lua            ★ 计时引擎：纯逻辑、时间由外部注入（与 engine.js 等价）
│   ├── engine_spec.lua       ★ 30 个用例，任意 Lua 5.1+ 都能跑
│   ├── ui.lua                配色 / 节点创建 / 指针判定 / 字号自适应
│   ├── text.lua              界面文案（en / zh 两套，见第六节）
│   └── settings.lua          设置读写（sys.save / sys.load）+ 引擎配置换算
├── assets/
│   ├── logo.png / logo.atlas               图标（位图来自网页版同一张原图）
│   ├── fonts/clock.font      大号等宽数字（距离场字体，放大不糊）
│   ├── fonts/ui.font         界面文字字体
│   └── sounds/*.wav          走子音 / 读秒滴答 / 超时警报
├── tools/
│   ├── export-logo.js        ../assets/logo-source.png → assets/logo.png（384×384）
│   ├── make_sounds.py        生成三份 wav（纯 Python，无第三方库）
│   ├── build_and_run.ps1     解析依赖 + 编译 + 打包 + 冒烟运行 + 查日志
│   ├── click_test.ps1        注入真实鼠标点击与按键，验证输入链路（端到端）
│   └── screenshot.ps1        抓游戏窗口截图（视觉回归）
└── tests/
    ├── run.js                一键测试入口
    ├── project_spec.js       静态校验（资源引用、GUI 名字、JS↔Lua 常量与 API 一致…）
    └── screenshots/          截图产物
```

### 界面交互怎么实现的（零第三方依赖）

按钮没有用任何 UI 库：设置界面的每个按钮就是 `logic/ui.lua` 动态创建的两个节点
（色块 + 文字），回调挂在 `wire_buttons()` 里，指针事件在 `on_input` 里逐个 `ui.pick`：

```
ui.pointer_down(action_id, action)   -- 鼠标 "press" / 触摸 "touch_multi" → 取出按下点
  → ui.pick(button, x, y)            -- 内部就是 gui.pick_node（自己换算坐标空间）
    → button.on_click()              -- 命中就执行回调，并消费掉这次事件
```

`input/game.input_binding` 里的动作名：

| 用途 | trigger | action |
| --- | --- | --- |
| 桌面鼠标 | `MOUSE_BUTTON_LEFT` | `press` |
| 移动端触摸 | `TOUCH_MULTI` | `touch_multi` |
| 棋钟快捷键 | `KEY_A` / `KEY_L` / `KEY_SPACE` / `KEY_F` / `KEY_ESC` | `key_a` / `key_l` / `key_space` / `key_f` / `key_esc` |

**触摸与鼠标刻意用不同的 action 名**：Defold 手册说过「触摸不能与其它输入同名」，
而且这样看日志能一眼分辨事件来自鼠标还是手指。

> 历史：这个设置界面曾经接过 [Druid](https://github.com/Insality/druid)（当时是为了它的
> 文本输入框做选手姓名）。姓名功能按需求移除后，按钮部分改回了手写实现，
> 两个依赖（Druid + Defold Event）也一并删掉了 —— 现在 `game.project` 里没有任何
> `dependencies`，第一次构建也不需要联网 `resolve`。

### 为什么是"一个 game object 装两个界面"

界面之间的通信全部走 Defold 的消息（每个 script 有独立 Lua 状态，模块变量不共享）：

| 发起 | 消息 | 处理 |
| --- | --- | --- |
| 设置界面 → 总控 | `start_game {config}` | 存盘、关设置界面、开棋钟界面、发 `begin` |
| 设置界面 → 总控 | `save_settings {config}` | 立刻落盘 |
| 棋钟界面 → 总控 | `back_to_menu` | 切回设置界面并刷新 |
| 总控 → 设置界面 | `settings {config}` | 用设置重建界面 |
| 总控 → 棋钟界面 | `begin {config}` | 建引擎状态、重排布局、开始渲染 |

这样初始化顺序无关紧要（消息在下一帧统一派发），也不用共享变量。

### 计时为什么不会算错

和网页版一样：**不使用累加 `dt`**，也不信任引擎的帧率。
每一帧只是用 `E.readout(state, side, socket.gettime() * 1000)` 重新推算，
所以即使掉帧、被切到后台、窗口被拖动、甚至引擎被暂停，时间与超时判定都仍然正确
（`logic/engine_spec.lua` 里有"挂起 30 分钟后仍能判出正确超时方"的用例）。

---

## 五、测试

```bash
node tests/run.js          # 静态校验 + 调用本机 Lua 跑引擎单测（推荐）
node tests/project_spec.js # 只跑静态校验（不需要 Lua）
powershell -ExecutionPolicy Bypass -File tools/build_and_run.ps1   # 真编译 + 打包 + 运行
powershell -ExecutionPolicy Bypass -File tools/click_test.ps1      # 注入真实点击+按键，验证输入链路
powershell -ExecutionPolicy Bypass -File tools/click_test.ps1 -PresetId 1 -FlagWaitSeconds 70   # 连超时结算层一起验（约 2 分钟）
```

`tools/click_test.ps1` 会以 `--config=chessclock.debug_input=1` 启动打包产物、把窗口置顶，
然后按默认脚本点击「Bronstein 按钮 → START GAME → 白方面板两次」，并从日志里核对：

```
DBG click raw=(462.5,958.5) scene=720x1280 window=720x1061 ... pickHit=mode_delay   ← 点中模式按钮
DBG click raw=(368.7,256.4) ... pickHit=start                                       ← 点中开始按钮
clock screen ready - 10 min - Sudden death                                          ← 真的进入了棋钟界面
DBG clock pointer action=hash: [press] raw=(368.7,256.4) paneB=false paneW=true ... ← 命中下方白方面板
DBG clock press side=w target=w result=move moves=1                                 ← 完成一步走子
```

（注意 `scene=720x1280` 与 `window=704x1001` 并不相等 —— 这就是命中判定必须用
`gui.pick_node()` 而不能手算矩形的原因。）

`tests/project_spec.js` 检查的都是"手写 Defold 资源文件时最容易犯的错"，
也是这次移植真的踩过的坑：

1. `game.project` / `.collection` / `.go` / `.gui` / `.atlas` 里引用的文件是否都存在；
2. `.gui` 里注册的**字体名 / 贴图名**是否覆盖 Lua 里 `hash("...")` 用到的所有名字（漏一个就是运行期一片空白）；
3. `engine.lua` 与网页版 `engine.js` 的 8 个常量是否逐个一致（跨语言防漂移）；
4. `engine_spec.lua` 与 `engine.test.js` 的用例数是否一致（移植没漏测）；
5. Lua 代码块/括号配平（没装 Defold 时的最低限度语法体检）。

---

## 六、常见修改点

| 想改什么 | 改哪里 |
| --- | --- |
| 计时规则（加秒/延时/读秒/超时） | `logic/engine.lua`，然后 `lua logic/engine_spec.lua` 必须仍然是 30/30 |
| 新增一种计时模式 | 上面两处 + `menu/menu.gui_script` 的 `MODES` 列表 |
| 配色 | `logic/ui.lua` 的 `M.C`（与网页版 `styles.css` 一一对应） |
| 界面文案 / 换成中文 | `logic/text.lua`（见下方"中文"） |
| 图标 | 与网页版**共用同一张原图** `../assets/logo-source.png`（当前为 TARUMT 校徽）→ 换图后跑 `node tools/export-logo.js` 重新栅格化成 `assets/logo.png`（384×384），再重新编译。显示尺寸：设置页 96×96、操作条 48×48（测试会核对同源关系） |
| 音效 | `tools/make_sounds.py` 里调频率/时长 → `python tools/make_sounds.py` |
| 分辨率 | `game.project` 的 `display.width / display.height`（竖屏比例） |
| 打包时带应用图标 | `bob bundle --platform x86_64-win32 --icon=assets/logo.ico`（自己把 png 转成 ico） |

### 换成中文界面

Defold 内置字体（Vera Sans Mono Bold）**没有中文字形**，直接显示中文会变成空白，
所以默认界面是英文。想换成中文：

1. 把一个含中文字形的字体（如思源黑体 `NotoSansSC-Regular.ttf`）放进 `assets/fonts/`；
2. 编辑器里右键该 ttf → `New → Font`，勾上需要的字符（或 `All Chars`），存成 `assets/fonts/ui_zh.font`；
3. `logic/text.lua` 里把 `M.LANG` 改成 `"zh"`；
4. `logic/ui.lua` 里把 `M.FONT_UI = hash("ui")` 改成 `hash("ui_zh")`，并在两个 `.gui` 的 `fonts` 块里注册 `ui_zh`。

时间数字用的是 `clock.font`（只有 `0-9` 和 `: .`），不受影响。

---

## 七、与网页版的差异（有意为之）

| 项目 | 网页版 | Defold 版 | 原因 |
| --- | --- | --- | --- |
| 计时语义 | engine.js | engine.lua | 一致，有自动比对 |
| 文本输入（选手姓名） | 有 | **无**（按需求移除） | 现在的设置页只有模式/时间/预设/声音，全部点按即可 |
| 界面语言 | 中文 | 英文 | 内置字体无中文字形（换字体方法见上） |
| 屏幕常亮 | Wake Lock | **无** | Defold 没有该 API，请用系统设置或插件 |
| 设置保存 | localStorage | `sys.save` / `sys.load` | 桌面写存档目录；HTML5 落到浏览器存储 |
| 分发 | 一个 HTML 文件 | 需构建（或导出 HTML5 wasm 包） | 引擎特性 |
| 体积 | ~30 KB | 引擎运行时若干 MB | 引擎特性 |
| 面朝旋转 | CSS transform | `gui.set_rotation` + 四元数 | 见下方踩坑记录 |

---

## 八、踩坑记录（写给以后维护的人）

### 先说会让界面「完全点不动」的三条（都踩过，已修）

1. **`acquire_input_focus` 要发给游戏对象，不是发给组件。**
   手册原话：这条消息会把*该游戏对象下所有能接收输入的组件（脚本组件、GUI 组件…）*压进输入栈。
   我一开始写成 `msg.post("#gui_menu", "acquire_input_focus")` —— 组件根本不处理这条消息，
   于是鼠标点在界面上毫无反应（而游戏对象脚本抢焦点后却能收到输入，这个对比就是排查的突破口）。
   正确写法：`msg.post(".", "acquire_input_focus")`；
   界面切换只靠 `enable` / `disable`（被 disable 的 GUI 不会再收到输入），不用反复抢焦点。
2. **触摸与鼠标不能共用同一个 action 名。** Defold 手册明确列了这个已知问题。
   所以 `input_binding` 里鼠标用 `"press"`、触摸用 `"touch"`，脚本里统一走
   `logic/ui.lua` 的 `ui.pointer_down()`（它会同时处理鼠标和 `TOUCH_MULTI` 的每根手指）。
3. **命中最不能用「手算矩形」，要用 `gui.pick_node()`。**
   引擎派发的是**场景坐标**（`scene=720x1280`），而窗口只有 `704x1001`，两者并不相等，
   还有 display profile 的缩放与留边 —— 手算矩形必然错位。
   `gui.pick_node(节点, x, y)` 会自己处理坐标空间、缩放与旋转，而且 disabled 的节点天然不可点
   （隐藏的按钮不会被误触）。棋钟的「整块半屏就是按键」也是直接 pick 面板自己的背景节点。

### 坐标与窗口尺寸的坑（都会让界面「能看不能点」）

1. **`window.get_size()` 返回两个数，不是 vector3**。写成 `local ws = window.get_size()` 再 `ws.x`
   会报 `attempt to index local 'ws' (a number value)`；而它一旦在 `init` 里报错，整个 GUI 组件就是
   `RESULT_SCRIPT_ERROR` 状态——**画面照样画出来，但再也收不到任何输入**。
   现象极像"按钮没反应"，实际是组件初始化就废了。正确写法：`local w, h = window.get_size()`。
2. **坐标转换函数只有一半**：`gui.screen_to_local(node, pos)` 与 `gui.get_screen_position(node)` 存在，
   **`gui.local_to_screen` 不存在**（1.13 调用会 nil 报错）。要拿控件在窗口里的位置就用后者。
3. **`on_input` 的 `action.x/y` 与节点坐标不是同一套**：实测 action 是「场景坐标、y 自上而下」
   （`action_x = client_x × 场景宽/客户区宽`，`action_y = client_y × 场景高/客户区高`），
   而节点的 `gui.set_position` 用的是「场景坐标、y 自下而上」。
   **别自己按比例换算矩形** —— 直接把这套坐标原样交给 `gui.pick_node()`
   （本项目的 `ui.pick` 就是它），引擎内部会正确处理；`action.y` 直接减场景高那种写法一定错位。
   实测证据：设置界面 330×64 的按钮用 `gui.pick_node` 能稳定点中，
   而同样坐标下自算矩形的版本会整体偏掉。

### 资源格式与 Lua 的坑

1. **`gui.new_text_node(pos, text)` 没有字体参数**。字体要单独 `gui.set_font(node, hash("名字"))，
   而这个名字必须先在 `.gui` 的 `fonts { name: "…" font: "…" }` 块里注册。
   传错参数顺序会报 `bad argument #2 to 'new_text_node' (string expected, got userdata)`。
2. **GUI 里没有 `gui.new_texture_node`**。图片 = `gui.new_box_node(pos, size)` + `gui.set_texture(node, hash("名字"))`，
   贴图同样要在 `.gui` 的 `textures { name: "…" texture: "…atlas" }` 块里注册（`name` 是必填字段，漏了会
   `Message missing required fields: name`）。
3. **`gui.set_rotation` 收的是四元数，不是角度**。传数字会报 `quat expected, got number`；
   本项目统一用 `vmath.quat_rotation_z(math.pi)` 表示 180°，顺便绕开"角度还是弧度"的歧义。
4. **`game.project` 与所有资源文件都不支持注释**（写 `;` 或 `#` 注释会导致 `Could not parse`）。
5. **`---[[` 不是块注释**：它只注释掉当前这一行，后面的中文会被当成代码，
   `bob` 会报 `token recognition error at: '…'`。用 `--[[` 才是块注释。
6. **文字节点默认 pivot 居中**，所以"左对齐"要用文字宽度自己算（`logic/ui.lua` 的 `place_left`，
   等宽字体按 0.602 em/字符估算）；否则标签会被左边的按钮压住（这个 bug 是靠截图发现的）。
7. **`write_log_file` 只认项目配置，且 1 与 2 的区别容易误判**：`1`（"仅调试版"）在**打包产物**里
   其实不写日志（编辑器 Build & Run 才写），要命令行验证就得用 `2`；而运行期用
   `--config=write_log_file=2` 注入太晚、不生效（`bob` 也没有 `--config` 这个选项）。
   `--config=chessclock.autostart=1` 这种游戏自己读的配置则没问题。
8. **打包产物没有控制台**，日志写到 exe 旁边的 `log.txt`（`write_log_file` 控制）。
   补充：引擎其实是往**「启动它的进程的工作目录」**写 `./log.txt`，未必是 exe 目录——
   实测会落到项目根目录，所以 `tools/*.ps1` 两处都找。

### 注入式测试脚本的坑（`tools/click_test.ps1`）

1. **窗口摆位的顺序**：必须先 `ShowWindow(SW_RESTORE)` 再 `MoveWindow`；反过来的话窗口会被还原回
   原位，所有点击整体落偏（而且日志看起来像"按钮没反应"，很容易误判成产品 bug）。
2. **每次点击前重新取一次客户区原点**：`ClientToScreen` 的结果会随窗口移动而变；用同一个旧原点连点，
   头几次点击会落在别处（实测前三次全偏、后面才准）。
3. **坐标别写死**：游戏在 `--config=chessclock.debug_input=1` 时会把每个可点控件的
   `gui.get_screen_position` 打进日志（`DBG pos <id> <x> <y>`），脚本读出来按 id 点击，
   窗口大小 / DPI / 留边怎么变都不怕。断言以日志里的实际行为为准。

---

## 九、后续可以做的事

* **文本输入**：设置页的驱动数据都走"点按"，不需要键盘输入；
* **多时段**：如今只需在 `engine.lua` 里加"时段"概念，界面加一行；
* **双机同步**：两台手机各看自己那块钟（需要联网组件）；
* **PWA/HTML5 优化**：`bob bundle --platform js-web` 后配合 Service Worker 做离线；
* **应用图标**：把 `logo.png` 转成 `.ico`，bundle 时带 `--icon`；
* **真机验证**：Android/iOS 上确认触摸、音频延迟、屏幕常亮（可用扩展）。

## 许可

MIT，与网页版一致。
