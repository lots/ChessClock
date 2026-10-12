--[[
  engine.lua — CoQ 棋钟「计时引擎」（Defold / Lua 移植版）
  ==================================================================
  与网页版 logic 完全等价的一份实现，只是语言从 JavaScript 换成 Lua：

  设计原则（与 engine.js 一致）：
   1) 纯逻辑：不 require 任何 Defold API（go / gui / msg / sound 都不碰），
      所以可以拿任意 Lua 5.1+ 解释器直接跑单测：lua logic/engine_spec.lua
   2) 不自己读系统时间：所有函数都要求调用方注入 now（毫秒），
      调用侧用 socket.gettime() * 1000 取到（Defold 自带 LuaSocket）。
   3) 时间只在「按键换手 / 暂停」时结算，倒计时永远由
        剩余 = 已入账时间 - (now - 本手开始时刻)
      实时算出 —— 即使引擎掉帧、被切到后台、甚至定时器被冻结，
      回到前台时剩余时间与超时判定依然完全正确。

  读秒（Byoyomi）模型（与 engine.js 同一套算术）：
    主时间余额 > 0              → 主时间阶段
    主时间用完后每 X 秒一个窗口，窗口重置 = 消耗一段
    已消耗段数 = floor(读秒已用时间 / X)
    已消耗段数 >= 拥有的段数     → 判负
]]

local M = {}

-- ===================== 常量 =====================

M.MODES = {
  FISCHER = "fischer",
  DELAY   = "delay",
  BYOYOMI = "byoyomi",
  SUDDEN  = "sudden",
}

M.MODE_LABELS = {
  fischer = "Fischer",
  delay   = "Bronstein",
  byoyomi = "Byoyomi",
  sudden  = "Sudden death",
}

M.LOW_TIME_MS      = 60000
M.CRITICAL_TIME_MS = 20000
M.MIN_PRESS_GAP_MS = 40
M.SIDES            = { "w", "b" }

M.MIN_BASE_MS    = 1000
M.MAX_BASE_MS    = 6 * 60 * 60 * 1000
M.MAX_ADD_MS     = 180 * 1000
M.MIN_BYOYOMI_MS = 1000
M.MAX_PERIODS    = 20

-- ===================== 内部工具 =====================

local function other(side)
  if side == "w" then return "b" end
  return "w"
end

-- 对外暴露（engine.js 里是对外导出的，Lua 版一度漏了它，
-- 结果超时结算层调用 E.other 直接报错；project_spec 现在会守住这条）
M.other = other

local function isFiniteNumber(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clampInt(value, mn, mx, fallback)
  local n = tonumber(value)
  if not isFiniteNumber(n) then n = fallback end
  n = math.floor(n + 0.5)          -- 与 JS Math.round 行为一致
  if n < mn then n = mn end
  if n > mx then n = mx end
  return n
end

local function firstNumber(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v ~= nil then return v end
  end
  return nil
end

local function pad2(n)
  if n < 10 then return "0" .. n end
  return tostring(n)
end

-- ===================== 配置 =====================

--- 规范化配置，保证引擎内部数值始终合法（幂等：可把已规范化的表再传进来）
function M.normalizeConfig(config)
  config = config or {}
  local mode = M.MODES.FISCHER
  if config.mode == M.MODES.DELAY or config.mode == M.MODES.SUDDEN
    or config.mode == M.MODES.FISCHER or config.mode == M.MODES.BYOYOMI then
    mode = config.mode
  end

  local baseMs = clampInt(config.baseMs, M.MIN_BASE_MS, M.MAX_BASE_MS, 5 * 60000)

  -- 按模式优先取对应字段（规范化后的 byoyomi 配置里 incMs 恒为 0）
  local rawAdd
  if mode == M.MODES.BYOYOMI then
    rawAdd = firstNumber(config.byoyomiMs, config.incMs, config.delayMs)
  elseif mode == M.MODES.DELAY then
    rawAdd = firstNumber(config.delayMs, config.incMs, config.byoyomiMs)
  else
    rawAdd = firstNumber(config.incMs, config.byoyomiMs, config.delayMs)
  end
  local addMs = clampInt(rawAdd, 0, M.MAX_ADD_MS, 0)

  local rawPeriods = config.byoyomiPeriods
  if rawPeriods == nil then rawPeriods = config.periods end
  local periods = clampInt(rawPeriods, 1, M.MAX_PERIODS, 1)

  local cfg = {
    mode = mode,
    baseMs = baseMs,
    incMs = 0,
    delayMs = 0,
    byoyomiMs = 0,
    byoyomiPeriods = 1,
  }
  if mode == M.MODES.FISCHER then
    cfg.incMs = addMs
  elseif mode == M.MODES.DELAY then
    cfg.delayMs = addMs
  elseif mode == M.MODES.BYOYOMI then
    cfg.byoyomiMs = math.max(M.MIN_BYOYOMI_MS, addMs)
    cfg.byoyomiPeriods = periods
  end
  return cfg
end

--- 建立一局新棋（未启动状态，等待第一次 start/press）
function M.newGame(config)
  local cfg = M.normalizeConfig(config)
  return {
    cfg = cfg,
    ms = { w = cfg.baseMs, b = cfg.baseMs },                  -- 已入账的主时间
    periods = { w = cfg.byoyomiPeriods, b = cfg.byoyomiPeriods }, -- 剩余读秒段数
    active = nil,
    running = false,
    paused = false,
    started = false,
    turnStart = 0,
    moves = { w = 0, b = 0 },
    flagged = nil,
    finished = false,
    lastPressAt = -math.huge,
  }
end

-- ===================== 时间推算 =====================

--- 当前这一手已经「消耗」掉多少毫秒（延时模式下先白送 delayMs）
local function elapsedCharged(state, now)
  local raw = now - state.turnStart
  if raw < 0 then raw = 0 end
  local delay = 0
  if state.cfg.mode == M.MODES.DELAY then delay = state.cfg.delayMs end
  if delay > 0 then
    raw = raw - delay
    if raw < 0 then raw = 0 end
  end
  return raw
end

--- 某一方此刻的主时间余额（毫秒）；读秒阶段恒为 0
function M.remainingMs(state, side, now)
  if type(now) ~= "number" then now = M.now() end
  if state.finished then
    local v = state.ms[side]
    if v < 0 then v = 0 end
    return v
  end
  if state.running and not state.paused and state.active == side then
    local v = state.ms[side] - elapsedCharged(state, now)
    if v < 0 then v = 0 end
    return v
  end
  local v = state.ms[side]
  if v < 0 then v = 0 end
  return v
end

function M.totalRemainingMs(state, now)
  return M.remainingMs(state, "w", now) + M.remainingMs(state, "b", now)
end

--[[ 读秒阶段实时状态（仅 byoyomi 模式有意义）：
      phase       "main" / "byoyomi"
      ms          界面该显示的毫秒数（读秒阶段 = 当前窗口剩余）
      periodsLeft 剩余段数（0 = 已用尽，再超即判负）
      windowIndex 已重置了几个窗口，用于每秒提示音去重 ]]
function M.byoyomiState(state, side, now)
  local cfg = state.cfg
  local x = cfg.byoyomiMs
  local periods = state.periods[side]

  if state.finished and state.flagged == side then
    return { phase = "byoyomi", ms = 0, periodsLeft = 0, windowIndex = 0 }
  end

  local live = state.running and not state.paused and state.active == side
  if not live then
    if state.ms[side] > 0 then
      return { phase = "main", ms = state.ms[side], periodsLeft = periods, windowIndex = 0 }
    end
    return { phase = "byoyomi", ms = x, periodsLeft = periods, windowIndex = 0 }
  end

  local elapsed = now - state.turnStart
  if elapsed < 0 then elapsed = 0 end
  local mainLeft = state.ms[side] - elapsed
  if mainLeft > 0 then
    return { phase = "main", ms = mainLeft, periodsLeft = periods, windowIndex = 0 }
  end

  local byo = elapsed - state.ms[side]
  if byo < 0 then byo = 0 end
  local overruns = 0
  if x > 0 then overruns = math.floor(byo / x) end
  local inWindow = byo - overruns * x
  local left = periods - overruns
  if left < 0 then left = 0 end
  return {
    phase = "byoyomi",
    ms = x - inWindow,
    periodsLeft = left,
    windowIndex = overruns,
  }
end

--- 界面统一入口：任何模式都返回 { phase, ms, periodsLeft, windowIndex }
function M.readout(state, side, now)
  if type(now) ~= "number" then now = M.now() end
  if state.cfg.mode == M.MODES.BYOYOMI then
    return M.byoyomiState(state, side, now)
  end
  return {
    phase = "main",
    ms = M.remainingMs(state, side, now),
    periodsLeft = nil,
    windowIndex = 0,
  }
end

-- ===================== 状态迁移 =====================

function M.start(state, now, side)
  if state.finished then return { type = "ignored", reason = "finished" } end
  if state.started then return { type = "ignored", reason = "already-started" } end
  if type(now) ~= "number" then now = M.now() end
  state.started = true
  state.running = true
  state.paused = false
  state.active = (side == "b") and "b" or "w"
  state.turnStart = now
  return { type = "start", side = state.active }
end

--- 这一手是否已经用光时间（读秒看段数，其它模式看主时间）
function M.isOutOfTime(state, side, now)
  if state.cfg.mode == M.MODES.BYOYOMI then
    local info = M.byoyomiState(state, side, now)
    return info.phase == "byoyomi" and info.periodsLeft <= 0
  end
  return M.remainingMs(state, side, now) <= 0
end

--- 结算读秒：把这一手跨过的段数扣掉，主时间扣到 0
local function commitByoyomi(state, side, now, consumePeriods)
  local cfg = state.cfg
  local elapsed = now - state.turnStart
  if elapsed < 0 then elapsed = 0 end
  local overrunMs = elapsed - state.ms[side]
  if overrunMs < 0 then overrunMs = 0 end
  local overruns = 0
  if cfg.byoyomiMs > 0 then overruns = math.floor(overrunMs / cfg.byoyomiMs) end
  if consumePeriods and overruns > 0 then
    local left = state.periods[side] - overruns
    if left < 0 then left = 0 end
    state.periods[side] = left
  end
  local mainLeft = state.ms[side] - elapsed
  if mainLeft < 0 then mainLeft = 0 end
  state.ms[side] = mainLeft
  return { overruns = overruns }
end

--- 按下某一方的按键（走完一步）
function M.press(state, side, now)
  if type(now) ~= "number" then now = M.now() end
  if side ~= "w" and side ~= "b" then return { type = "ignored", reason = "bad-side" } end
  if state.finished then return { type = "ignored", reason = "finished" } end
  if state.paused then return { type = "ignored", reason = "paused" } end
  if not state.started then return M.start(state, now, side) end
  if not state.running then return { type = "ignored", reason = "not-running" } end
  if state.active ~= side then return { type = "ignored", reason = "not-active" } end
  if now - state.lastPressAt < M.MIN_PRESS_GAP_MS then
    return { type = "ignored", reason = "debounced" }
  end

  -- 先判超时：读秒段数用尽 / 主时间归零
  if M.isOutOfTime(state, side, now) then
    return { type = "flag", side = M.checkFlag(state, now) }
  end

  state.lastPressAt = now
  if state.cfg.mode == M.MODES.BYOYOMI then
    commitByoyomi(state, side, now, true)
  else
    local remain = M.remainingMs(state, side, now)
    if state.cfg.mode == M.MODES.FISCHER then remain = remain + state.cfg.incMs end
    state.ms[side] = remain
  end
  state.moves[side] = state.moves[side] + 1
  state.active = other(side)
  state.turnStart = now

  return {
    type = "move",
    side = side,
    remainingMs = state.ms[side],
    periodsLeft = state.periods[side],
    active = state.active,
    moves = state.moves[side],
  }
end

function M.pause(state, now)
  if type(now) ~= "number" then now = M.now() end
  if state.finished then return { type = "ignored", reason = "finished" } end
  if not state.started then return { type = "ignored", reason = "not-started" } end
  if state.paused or not state.running then return { type = "ignored", reason = "not-running" } end

  local side = state.active
  if state.cfg.mode == M.MODES.BYOYOMI then
    commitByoyomi(state, side, now, true)
  else
    state.ms[side] = M.remainingMs(state, side, now)
  end
  state.running = false
  state.paused = true
  return { type = "pause", side = side, remainingMs = state.ms[side] }
end

function M.resume(state, now)
  if type(now) ~= "number" then now = M.now() end
  if state.finished then return { type = "ignored", reason = "finished" } end
  if not state.paused then return { type = "ignored", reason = "not-paused" } end
  state.paused = false
  state.running = true
  state.turnStart = now
  return { type = "resume", side = state.active }
end

--- 判定超时，返回超时方（"w" / "b"）或 nil
function M.checkFlag(state, now)
  if type(now) ~= "number" then now = M.now() end
  if not state.running or state.paused or state.finished then return nil end
  local side = state.active
  if not M.isOutOfTime(state, side, now) then return nil end

  state.ms[side] = 0
  if state.cfg.mode == M.MODES.BYOYOMI then state.periods[side] = 0 end
  state.running = false
  state.finished = true
  state.flagged = side
  return side
end

function M.displayMs(state, side, now)
  return M.readout(state, side, now).ms
end

-- ===================== 时间显示 =====================

--[[ 时间格式化，模仿实体棋钟：
      >= 1 小时 → H:MM:SS
      <  1 小时 → M:SS
      <  20 秒  → SS.d（十分之一秒）
    采用向上取整：剩 5:00.0 显示 5:00，走掉 0.1 秒后显示 4:59。 ]]
function M.formatTime(ms)
  if not isFiniteNumber(ms) or ms < 0 then ms = 0 end
  if ms < M.CRITICAL_TIME_MS then
    return string.format("%.1f", math.ceil(ms / 100) / 10)
  end
  local totalSec = math.ceil(ms / 1000)
  local h = math.floor(totalSec / 3600)
  local m = math.floor((totalSec % 3600) / 60)
  local s = totalSec % 60
  if h > 0 then
    return h .. ":" .. pad2(m) .. ":" .. pad2(s)
  end
  return m .. ":" .. pad2(s)
end

local function secs(ms)
  local s = ms / 1000
  if s % 1 == 0 then return string.format("%d", s) end
  return string.format("%.1f", s)
end

--- 把配置描述成一句人话，例如 "10 min + 5s/move - Fischer"
function M.describeConfig(config)
  local cfg = M.normalizeConfig(config)
  local mins = cfg.baseMs / 60000
  local base
  if mins % 1 == 0 then
    base = string.format("%d min", mins)
  else
    base = string.format("%.1f min", mins)
  end

  if cfg.mode == M.MODES.BYOYOMI then
    local txt = base .. " + byoyomi " .. secs(cfg.byoyomiMs) .. "s"
    if cfg.byoyomiPeriods > 1 then
      txt = txt .. " x" .. cfg.byoyomiPeriods
    end
    return txt .. " - " .. M.MODE_LABELS[cfg.mode]
  end

  local add = cfg.delayMs
  if cfg.mode == M.MODES.FISCHER then add = cfg.incMs end
  local addText = ""
  if add > 0 then addText = " + " .. secs(add) .. "s/move" end
  return base .. addText .. " - " .. M.MODE_LABELS[cfg.mode]
end

-- ===================== 时钟来源 =====================

--[[ 取「当前时刻（毫秒）」。
     默认用挂钟时间：Defold 里 socket.gettime() 返回带亚秒精度的秒数；
     在没有 LuaSocket 的裸 Lua 环境（跑单测）时退回 os.time()。
     注意：绝不能把 os.clock（CPU 时间）或累加 dt 当作时钟源。 ]]
local socketOk, socket = pcall(require, "socket")
if socketOk and socket and socket.gettime then
  M.TIME_SOURCE = "socket.gettime"
  function M.now()
    return socket.gettime() * 1000
  end
else
  M.TIME_SOURCE = "os.time (1s resolution)"
  function M.now()
    return os.time() * 1000
  end
end

return M
