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

-- 与网页版 styles.css 一一对应的颜色（hex / 255）
M.C = {
  bg     = { 0.039, 0.051, 0.071, 1 },
  card   = { 0.071, 0.098, 0.141, 1 },
  card2  = { 0.055, 0.078, 0.114, 1 },
  line   = { 0.141, 0.173, 0.224, 1 },
  fg     = { 0.914, 0.933, 0.969, 1 },
  muted  = { 0.553, 0.604, 0.682, 1 },
  accent = { 0.243, 0.651, 1.000, 1 },
  ok     = { 0.184, 0.749, 0.443, 1 },
  warn   = { 1.000, 0.690, 0.125, 1 },
  danger = { 1.000, 0.302, 0.310, 1 },
  strip  = { 0.020, 0.027, 0.039, 1 },

  w_face = { 0.929, 0.941, 0.961, 1 },
  w_ink  = { 0.043, 0.059, 0.082, 1 },
  w_low  = { 0.663, 0.361, 0.000, 1 },
  w_crit = { 0.784, 0.118, 0.118, 1 },
  w_byo  = { 0.420, 0.247, 0.831, 1 },

  b_face = { 0.043, 0.055, 0.075, 1 },
  b_ink  = { 0.929, 0.941, 0.961, 1 },
  b_low  = { 1.000, 0.753, 0.275, 1 },
  b_crit = { 1.000, 0.357, 0.357, 1 },
  b_byo  = { 0.706, 0.608, 1.000, 1 },
}

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
  return n
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
  return n
end

--- 建一个贴图节点（例如 logo）。
--- Defold 的 GUI 里没有 new_texture_node：图片 = box 节点 + gui.set_texture（贴图名见 *.gui 的 textures 块）
function M.texture(id, cx, cy, size, texture_name, parent)
  local n = gui.new_box_node(vmath.vector3(cx, cy, 0), vmath.vector3(size, size, 0))
  gui.set_texture(n, texture_name)
  if parent then gui.set_parent(n, parent) end
  if id then gui.set_id(n, id) end
  return n
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
