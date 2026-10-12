--[[
  settings.lua — 设置的读写（sys.save / sys.load）
  ==================================================================
  桌面上写到应用存档目录；HTML5 由 Defold 落到浏览器存储（IndexedDB）。
  隐私模式 / 存储被禁用时静默降级为「不保存」，绝不能让存档失败影响比赛。
]]

local M = {}

local FILE = "chessclock_settings"

M.DEFAULTS = {
  mode = "fischer",
  baseMin = 10,
  addSec = 5,
  periods = 1,
  sound = true,
  facing = true,
}

local function clampInt(v, mn, mx, dflt)
  local n = tonumber(v)
  if n == nil or n ~= n then n = dflt end
  n = math.floor(n + 0.5)
  if n < mn then n = mn end
  if n > mx then n = mx end
  return n
end

--- 把任意输入夹成一份合法设置
function M.sanitize(raw)
  raw = raw or {}
  local out = {}
  out.mode = raw.mode
  if out.mode ~= "fischer" and out.mode ~= "delay"
    and out.mode ~= "byoyomi" and out.mode ~= "sudden" then
    out.mode = M.DEFAULTS.mode
  end
  out.baseMin = clampInt(raw.baseMin, 1, 180, M.DEFAULTS.baseMin)
  out.addSec = clampInt(raw.addSec, 0, 180, M.DEFAULTS.addSec)
  out.periods = clampInt(raw.periods, 1, 20, M.DEFAULTS.periods)
  out.sound = raw.sound ~= false
  out.facing = raw.facing ~= false
  if out.mode == "byoyomi" and out.addSec < 1 then out.addSec = 30 end
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
