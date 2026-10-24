--[[
  settings.lua — 设置的读写（sys.save / sys.load）
  ==================================================================
  桌面上写到应用存档目录；HTML5 由 Defold 落到浏览器存储（IndexedDB）。
  隐私模式 / 存储被禁用时静默降级为「不保存」，绝不能让存档失败影响比赛。

  存档结构（settingsVersion = 2，与网页版 app.js 的 DEFAULTS 对齐）：
    mode / baseMin / addSec / periods / sound / facing / swapped
  旧存档（v1：没有 settingsVersion、没有 swapped）也能直接读 ——
  缺的键用默认值补上，语义没变的键原样保留，见 M.migrate。
]]

local M = {}

local theme = require("logic.theme")

local FILE = "chessclock_settings"

--- 存档结构版本。存档里没有这个键 = 旧版（v1）存档。
M.SETTINGS_VERSION = 2

--- 与网页版 app.js 的 DEFAULTS 一一对应（tests/project_spec.js 会逐项比对）：
--- 首次启动 = 围棋读秒制 10+3×20（主时间 10 分钟 / 每手 20 秒 / 3 段）
M.DEFAULTS = {
  mode = "byoyomi",
  baseMin = 10,
  addSec = 20,
  periods = 3,
  sound = true,
  facing = true,
  swapped = false,
  theme = "dark",          -- 与网页版 DEFAULTS.theme 一致（深色是默认那套）
}

local function clampInt(v, mn, mx, dflt)
  local n = tonumber(v)
  if n == nil or n ~= n then n = dflt end
  n = math.floor(n + 0.5)
  if n < mn then n = mn end
  if n > mx then n = mx end
  return n
end

--[[ 旧存档迁移（v1 → v2）。

     v1 → v2 只多了一个键 swapped（默认 false）：mode / baseMin / addSec /
     periods / sound / facing 的含义完全没变，所以迁移 = 「补一个版本号」，
     剩下的交给 M.sanitize 用默认值补全。

     两件刻意不做的事：
     1) 不把旧存档里的时间里制式改写成新默认 —— 那是用户自己挑的，与网页版
        一致（网页版也只在「键缺失」时才用 DEFAULTS）；
     2) 不处理「对局进行中」的状态 —— 引擎状态本来就不落盘，一局棋不会跨启动。
        旧版存档里万一有 started 之类的键，sanitize 会直接忽略。 ]]
function M.migrate(raw)
  if type(raw) ~= "table" then return {} end
  local out = {}
  for k, v in pairs(raw) do out[k] = v end
  if out.settingsVersion == nil then
    out.settingsVersion = M.SETTINGS_VERSION
  end
  return out
end

--- 把任意输入夹成一份合法设置（幂等：已规范化的表再传进来结果不变）
function M.sanitize(raw)
  raw = M.migrate(raw)
  local out = {}
  out.settingsVersion = M.SETTINGS_VERSION
  out.mode = raw.mode
  if out.mode ~= "fischer" and out.mode ~= "delay"
    and out.mode ~= "byoyomi" and out.mode ~= "sudden" then
    out.mode = M.DEFAULTS.mode
  end
  -- 读秒模式下「主时间」与「读秒秒数」各可以是 0，但不能同时是 0：
  --   0 主时间 + N 秒读秒 = 纯读秒；M 分钟 + 0 秒读秒 = 只有主时间（用完即负）
  --   其它模式没有第二个数兜底，主时间仍然至少 1 分钟
  local minBase = 0
  if out.mode ~= "byoyomi" then minBase = 1 end
  out.baseMin = clampInt(raw.baseMin, minBase, 180, M.DEFAULTS.baseMin)
  out.addSec = clampInt(raw.addSec, 0, 180, M.DEFAULTS.addSec)
  if out.baseMin <= 0 and (out.mode ~= "byoyomi" or out.addSec <= 0) then
    out.baseMin = 1
  end
  out.periods = clampInt(raw.periods, 1, 20, M.DEFAULTS.periods)
  out.sound = raw.sound ~= false
  out.facing = raw.facing ~= false
  out.swapped = raw.swapped == true          -- 旧存档没有这个键 → false（严格布尔）
  out.theme = theme.normalize(raw.theme)     -- 旧存档没有这个键 / 值不认识 → 默认深色
  if out.mode == "sudden" then out.addSec = 0 end
  return out
end

function M.load()
  local ok, data = pcall(sys.load, FILE)
  if not ok or type(data) ~= "table" then
    return M.sanitize(nil)
  end
  return M.sanitize(data)
end

function M.save(settings)
  pcall(sys.save, FILE, M.sanitize(settings))
end

--- 设置 → 引擎配置（毫秒）。与网页版 app.js 的 engineConfig() 等价
--- （四个「加时」字段都填同一个值，由引擎按 mode 取对应的那个）
function M.toEngineConfig(settings)
  local s = M.sanitize(settings)
  local addMs = s.addSec * 1000
  return {
    mode = s.mode,
    baseMs = s.baseMin * 60000,
    incMs = addMs,
    delayMs = addMs,
    byoyomiMs = addMs,
    byoyomiPeriods = s.periods,
  }
end

return M
