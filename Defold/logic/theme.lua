--[[
  theme.lua — 三套界面主题（与网页版 styles.css 的 data-theme 块一一对应）
  ==================================================================
  dark   深色（默认，就是最初那套配色）
  medium 中性（石板灰，亮一点的深色，户外/强光下更清楚）
  light  浅色（白底深字）

  色值**故意保留成 web 的十六进制字符串**：运行时再转成 0..1 的浮点给 Defold 用，
  这样 tests/project_spec.js 可以直接把这里的字符串与 ../styles.css 的变量逐条比对
  （两个版本换主题时不会各改各的）。

  两件事与 web 保持一致：
    · 两块对局面板始终「黑方深、白方浅」（--w-face / --b-face，语义配色，不随主题变），
      light 主题只把白方面板提亮成纯白 + 加一条浅色边（--pane-edge），免得和页面底色糊在一起；
    · 读秒配色（--byo-w / --byo-b）每个主题各有一份。
]]

local M = {}

M.DEFAULT = "dark"

--- 合法值（存档校验用）
M.NAMES = { "dark", "medium", "light" }

--- 设置页里三个按钮的顺序：与网页版下拉框一致（浅色 / 中性 / 深色）
M.ORDER = { "light", "medium", "dark" }

--- 每个主题的原始色值（= styles.css 里 :root[data-theme="…"] 的同名变量）
M.RAW = {
  dark = {
    bg = "#0a0d12", card = "#121924", card2 = "#0e1420", line = "#242c39",
    fg = "#e9eef7", muted = "#8d9aae",
    accent = "#3ea6ff", accent_ink = "#04121f",
    ok = "#2fbf71", ok_ink = "#04120a", warn = "#ffb020", danger = "#ff4d4f",
    strip = "#05070a", clock_bg = "#000000", pane_edge = "#000000",

    w_face = "#edf0f5", w_ink = "#0b0f15", w_low = "#a95c00", w_crit = "#c81e1e",
    b_face = "#0b0e13", b_ink = "#edf0f5", b_low = "#ffc046", b_crit = "#ff5b5b",
    byo_w = "#6b3fd4", byo_b = "#b49bff",
  },
  medium = {
    bg = "#3a4250", card = "#48525f", card2 = "#414a57", line = "#5b6676",
    fg = "#f3f6fa", muted = "#b9c3d2",
    accent = "#7cc4ff", accent_ink = "#062033",
    ok = "#43cf87", ok_ink = "#04170d", warn = "#ffc352", danger = "#ff6b6d",
    strip = "#2c333e", clock_bg = "#2c333e", pane_edge = "#6f7a8b",

    -- medium 在 web 里没有覆盖面板色 → 继承 dark 那套（黑方深、白方浅）
    w_face = "#edf0f5", w_ink = "#0b0f15", w_low = "#a95c00", w_crit = "#c81e1e",
    b_face = "#0b0e13", b_ink = "#edf0f5", b_low = "#ffc046", b_crit = "#ff5b5b",
    byo_w = "#8a6bf5", byo_b = "#d3c2ff",
  },
  light = {
    bg = "#eef1f6", card = "#ffffff", card2 = "#f4f7fb", line = "#ccd5e0",
    fg = "#16202e", muted = "#5d6b7e",
    accent = "#1f7fe0", accent_ink = "#ffffff",
    ok = "#1f9d5a", ok_ink = "#ffffff", warn = "#b26a00", danger = "#d32f2f",
    strip = "#e3e8f1", clock_bg = "#dfe5ee", pane_edge = "#b9c4d2",

    w_face = "#ffffff", w_ink = "#0b0f15", w_low = "#a95c00", w_crit = "#c81e1e",
    b_face = "#0b0e13", b_ink = "#edf0f5", b_low = "#ffc046", b_crit = "#ff5b5b",
    byo_w = "#5b2fc4", byo_b = "#6f4ae0",
  },
}

--- "#rrggbb" -> { r, g, b, 1 }
local function hex(s)
  return {
    tonumber(s:sub(2, 3), 16) / 255,
    tonumber(s:sub(4, 5), 16) / 255,
    tonumber(s:sub(6, 7), 16) / 255,
    1,
  }
end

local converted = {}

--- 取某个主题的调色板（颜色已转成 vmath 可用的 0..1 浮点表）；名字不合法时回落到默认
function M.get(name)
  if not M.RAW[name] then name = M.DEFAULT end
  if not converted[name] then
    local out = {}
    for k, v in pairs(M.RAW[name]) do out[k] = hex(v) end
    converted[name] = out
  end
  return converted[name]
end

--- 名字是否合法（存档里的脏值用它兜一下）
function M.normalize(name)
  if M.RAW[name] then return name end
  return M.DEFAULT
end

return M
