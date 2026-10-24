--[[
  ui.lua — 界面工具箱（配色 / 节点创建 / 命中检测）
  ==================================================================
  与网页版 styles.css 使用同一套配色，方便两个版本看起来是同一个产品。

  Defold 的 GUI 坐标系：原点在左下角、y 轴向上，节点的 position 是它的
  pivot（默认居中）。本模块统一用「左上角 + 宽高」描述矩形（y_top 是从
  屏幕顶部往下量的），内部再换算成中心点，写布局时不容易搞错方向。
]]

local M = {}

-- 字体在 .gui 场景里按「名字」注册（fonts 块），Lua 里用这个短名字引用；
-- 注意 gui.new_text_node 本身不接受字体参数，字体要靠 gui.set_font() 单独设置。
M.FONT_CLOCK = hash("clock")
M.FONT_UI    = hash("ui")

M.FONT_CLOCK_SIZE = 48
M.FONT_UI_SIZE    = 20

local theme = require("logic.theme")

--[[ 当前主题的调色板（0..1 浮点）。与网页版 styles.css 的三个 data-theme 块一一对应
     （色值在 logic/theme.lua 里，故意保留 hex 字符串方便与 ../styles.css 逐条比对）。

     **这张表是原地更新的**：ui.set_theme() 只改内容、不换引用，
     所以到处写的 ui.C.xxx 读到的永远是最新主题的颜色。 ]]
M.C = {}

local C_KEYS = {
  "bg", "card", "card2", "line", "fg", "muted",
  "accent", "accent_ink", "ok", "ok_ink", "warn", "danger",
  "strip", "clock_bg", "pane_edge",
  "w_face", "w_ink", "w_low", "w_crit",
  "b_face", "b_ink", "b_low", "b_crit",
}

local current_theme = nil

--- 切换主题；返回「是否真的换了」（没换就不用重建界面）
function M.set_theme(name)
  name = theme.normalize(name)
  if name == current_theme then return false end
  local pal = theme.get(name)
  for _, k in ipairs(C_KEYS) do
    if pal[k] then M.C[k] = pal[k] end
  end
  -- web 里读秒配色叫 --byo-w / --byo-b，Defold 侧沿用 w_byo / b_byo
  M.C.w_byo = pal.byo_w
  M.C.b_byo = pal.byo_b
  current_theme = name
  return true
end

function M.theme_name()
  return current_theme or theme.DEFAULT
end

M.set_theme(theme.DEFAULT)

--[[ 运行时创建的节点按「界面」登记，用来在换主题时整屏重建。

     为什么按界面分开记：Defold 里所有脚本共用同一个 Lua 状态，require 拿到的
     是**同一张表** —— 两个 GUI 场景（设置页 / 棋钟页）都会往 ui 里建节点。
     如果不分开，删设置页的节点时就会去删棋钟页的节点，报
     "Node used in the wrong scene"（实测踩过）。

     用法：每个界面的 build() 开头调 ui.bind(self)，重建前调 ui.clear_nodes(self)。 ]]
M.by_owner = setmetatable({}, { __mode = "k" })   -- 弱键：界面被销毁时表也跟着回收

local current_owner = nil

function M.bind(owner)
  current_owner = owner
  if not M.by_owner[owner] then M.by_owner[owner] = {} end
  return owner
end

local function track(n)
  if current_owner then
    local list = M.by_owner[current_owner]
    list[#list + 1] = n
  end
  return n
end

--- 删掉某个界面自己建的节点（不传 owner 就用最近一次 bind 的那个）
function M.clear_nodes(owner)
  owner = owner or current_owner
  local list = owner and M.by_owner[owner]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] then gui.delete_node(list[i]) end
  end
  M.by_owner[owner] = {}
end

--- 铺满全屏的底色块（放在最前面建，就永远在最底层）。
--- 换主题时页面底色跟着变，所以不用 .gui 里的 background_color。
function M.backdrop(id, color)
  return track(M.box(id, M.rect(0, 0, 10, 10), color))
end

function M.v4(c, a)
  return vmath.vector4(c[1], c[2], c[3], a or c[4] or 1)
end

--- 亮度缩放：用来表现「这一方没在走棋」（实体钟上是暗下去的那一面）
function M.dim(c, k)
  return { c[1] * k, c[2] * k, c[3] * k, c[4] or 1 }
end

--- 矩形（左上角 + 宽高，y 从上往下量）。只用于排版，不要拿它做命中判定（见 M.pick）
function M.rect(x, y_top, w, h)
  return { x = x, y_top = y_top, w = w, h = h }
end

--- 建一个矩形色块。rect 用「左上角」描述
function M.box(id, r, color, parent)
  local cx = r.x + r.w * 0.5
  local cy = r.y_top - r.h * 0.5
  local n = gui.new_box_node(vmath.vector3(cx, cy, 0), vmath.vector3(r.w, r.h, 0))
  if parent then gui.set_parent(n, parent) end
  if id then gui.set_id(n, id) end
  if color then gui.set_color(n, M.v4(color)) end
  return track(n)
end

--[[ 建一段文字，以「中心点」定位（文字节点默认 pivot 就是居中）
      size 是希望渲染的字号；内部按字体基准字号做缩放。
      Defold 的 gui.new_text_node(pos, text) 不接受字体，必须再调 gui.set_font。 ]]
function M.text(id, cx, cy, font, base_size, size, str, color, parent)
  local n = gui.new_text_node(vmath.vector3(cx, cy, 0), str)
  gui.set_font(n, font)
  if parent then gui.set_parent(n, parent) end
  if id then gui.set_id(n, id) end
  if color then gui.set_color(n, M.v4(color)) end
  local s = 1
  if size and size > 0 then s = size / base_size end
  gui.set_scale(n, vmath.vector3(s, s, 1))
  return track(n)
end

--- 建一个贴图节点（例如 logo）。
--- Defold 的 GUI 里没有 new_texture_node：图片 = box 节点 + gui.set_texture（贴图名见 *.gui 的 textures 块）
function M.texture(id, cx, cy, size, texture_name, parent)
  local n = gui.new_box_node(vmath.vector3(cx, cy, 0), vmath.vector3(size, size, 0))
  gui.set_texture(n, texture_name)
  if parent then gui.set_parent(n, parent) end
  if id then gui.set_id(n, id) end
  return track(n)
end

--[[ 操作条上的图标（白色 PNG，透明底，由 tools/export-icons.js 生成）。

     为什么这些按钮用图片而不是文字字形：Defold 内置字体是 Vera Sans Mono Bold，
     实测它的 cmap 里**没有** U+21F5(⇵) / U+26F6(⛶) / U+2699(⚙) / U+1F50A(🔊)，
     写进文字节点只会是空白方块。U+00B0(°) 与 U+00D7(×) 有字形，
     所以「180°」「10+3×20」继续用文字（见 logic/text.lua）。

     一个用途一个文件，名字就是 assets/icons.atlas 里的图片名。 ]]
M.ICONS = {
  sound_on  = "sound_on",
  sound_off = "sound_off",
  swap      = "swap",
  settings  = "settings",
}

--- 图标图集在 *.gui 的 textures 块里注册的名字
M.ICON_TEXTURE = hash("icons")

--- 建一个图标节点：box 节点 + 图集贴图 + flipbook（图集里的具体哪一张）
function M.icon(id, cx, cy, size, anim, parent)
  local n = gui.new_box_node(vmath.vector3(cx, cy, 0), vmath.vector3(size, size, 0))
  gui.set_texture(n, M.ICON_TEXTURE)
  gui.play_flipbook(n, hash(anim))
  if parent then gui.set_parent(n, parent) end
  if id then gui.set_id(n, id) end
  gui.set_color(n, vmath.vector4(1, 1, 1, 1))    -- 白色图标，不做主题着色
  return track(n)
end

--[[ 建一个「图标按钮」：色块 + 一张或多张互斥的图标（例如声音开 / 关）。

     anims 是 ui.ICONS 里的动画名列表，全部一次性建好、只显示第一张，
     之后用 b.set_icon(名字) 在它们之间切换 —— 运行期不重新加载图集。 ]]
function M.make_icon_button(store, id, anims, on_click, box_color, size)
  local b = {
    id = id,
    box = M.box(id .. "_box", M.rect(0, 0, 10, 10), box_color or M.C.card2),
    icon_nodes = {},
    icons = {},
    icon_size = size or 30,
    rect = M.rect(0, 0, 10, 10),
    on_click = on_click,
    box_color = box_color or M.C.card2,
  }
  for i, anim in ipairs(anims) do
    local n = M.icon(id .. "_icon_" .. i, 0, 0, b.icon_size, anim)
    b.icon_nodes[i] = n
    b.icons[anim] = n
    gui.set_enabled(n, i == 1)
  end
  b.current_icon = anims[1]
  --[[ 图标是白色 PNG，颜色靠 set_color 染色：
       dark 主题下白图标直接可见，light 主题下必须染成深色，否则白底白图看不见。
       传进来的 color 会被乘到纹理上（白色 × 颜色 = 该颜色）。 ]]
  b.icon_color = nil
  function b.set_icon_color(color)
    if b.icon_color == color then return end
    b.icon_color = color
    for _, n in ipairs(b.icon_nodes) do gui.set_color(n, M.v4(color)) end
  end
  function b.set_icon(anim)
    if b.current_icon == anim or not b.icons[anim] then return end
    gui.set_enabled(b.icons[b.current_icon], false)
    gui.set_enabled(b.icons[anim], true)
    b.current_icon = anim
  end
  store[#store + 1] = b
  return b
end

--[[ Vera Sans Mono Bold 是等宽字体，每个字符的前进宽度是 0.602 em。
     用它可以把「时间数字撑满面板」算出来，不依赖任何图片资源。 ]]
M.MONO_ADVANCE = 0.602

--- 估算一段等宽文字渲染后的宽度（像素）
function M.text_width(str, size)
  return #tostring(str) * (size or 20) * M.MONO_ADVANCE
end

--- 把文字节点摆成「左对齐」：x_left 是左边缘，cy 是垂直中心
function M.place_left(node, x_left, cy, str, size)
  gui.set_position(node, vmath.vector3(x_left + M.text_width(str, size) * 0.5, cy, 0))
end

--- 同时显示/隐藏一个按钮（色块 + 文字）
function M.enable_button(b, on)
  gui.set_enabled(b.box, on)
  gui.set_enabled(b.label, on)
end

--[[ 命中的正确做法：用 gui.pick_node(节点, action.x, action.y)。
     它自己会处理「场景坐标 vs 屏幕坐标」的换算、节点的缩放与旋转，
     而且 disabled 的节点天然不可点（隐藏的按钮不会误触）。
     不要自己用矩形去算坐标 —— 场景尺寸与窗口尺寸不一致时那样一定错。 ]]
function M.pick(b, x, y)
  return gui.pick_node(b.box, x, y)
end

--[[ 统一的「指针按下」判定，返回 pressed, x, y。
     桌面鼠标 → "press"，移动端触摸 → "touch_multi"（TOUCH_MULTI）。
     两者刻意用不同的 action 名：Defold 手册明确说过「触摸不能与其它输入同名」，
     而且这样在日志里一眼就能看出事件是鼠标还是手指。 ]]
local ACTION_PRESS = hash("press")
local ACTION_MULTITOUCH = hash("touch_multi")

function M.pointer_down(action_id, action)
  if action_id == ACTION_PRESS then
    if action.pressed then return true, action.x, action.y end
    return false
  end
  if action_id == ACTION_MULTITOUCH then
    -- TOUCH_MULTI：每根手指一项，按下信息在 action.touch 里
    if action.touch then
      for i = 1, #action.touch do
        local t = action.touch[i]
        if t.pressed then return true, t.x, t.y end
      end
    end
    if action.pressed then return true, action.x, action.y end
  end
  return false
end

--[[ 建一个按钮（色块 + 居中文字）并登记到 store 里，返回按钮表：
      { id, box, label, rect, on_click, box_color, text_color }
      两个界面都用它，保证按钮外观和命中检测方式完全一致。 ]]
function M.make_button(store, id, label, on_click, box_color, text_color, size)
  local b = {
    id = id,
    box = M.box(id .. "_box", M.rect(0, 0, 10, 10), box_color or M.C.card2),
    label = M.text(id .. "_txt", 0, 0, M.FONT_UI, M.FONT_UI_SIZE, size or 22,
      label or "", text_color or M.C.fg),
    rect = M.rect(0, 0, 10, 10),
    on_click = on_click,
    box_color = box_color or M.C.card2,
    text_color = text_color or M.C.fg,
  }
  store[#store + 1] = b
  return b
end

--- 计算能把 str 塞进 (max_w, max_h) 的最大字号（近似值，等宽字体够用）
function M.fit_text_size(str, max_w, max_h)
  local len = #tostring(str)
  if len < 4 then len = 4 end
  local by_w = (max_w * 0.92) / (len * M.MONO_ADVANCE)
  local by_h = max_h * 0.56
  local size = by_w
  if by_h < size then size = by_h end
  if size < 10 then size = 10 end
  return size
end

--- 屏幕尺寸（GUI 场景的逻辑分辨率）
function M.screen()
  return gui.get_width(), gui.get_height()
end

return M
