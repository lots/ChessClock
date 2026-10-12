--[[
  engine_spec.lua — 计时引擎单元测试（纯 Lua，不依赖 Defold）
  ==================================================================
  与网页版 tests/engine.test.js 一一对应的 30 个用例，用来证明这次
  JavaScript → Lua 的移植没有改变任何计时语义。

  运行（任意 Lua 5.1+ 解释器）：
      lua logic/engine_spec.lua
  在 Defold 里也可以直接丢进编辑器控制台执行。
]]

-- 让脚本无论从哪个目录启动都能 require 到同目录的 engine.lua
local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = here .. "/?.lua;" .. package.path

local E = require("engine")

-- ===================== 迷你测试框架 =====================

local pass, fail = 0, 0
local failures = {}

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    print("  OK   " .. name)
  else
    fail = fail + 1
    table.insert(failures, name .. "\n         " .. tostring(err))
    print("  FAIL " .. name .. "\n         " .. tostring(err))
  end
end

local function eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s\n         expected: %s\n         actual:   %s",
      msg or "values differ", tostring(expected), tostring(actual)), 2)
  end
end

--- 造一局并返回便捷操作对象（时间由我们手动推进，绝对可控）
local function game(config)
  local state = E.newGame(config)
  local now = 1000000
  local g = { state = state }
  function g.at(ms) now = now + ms; return now end
  function g.to(t) now = t; return now end
  function g.now() return now end
  function g.start(side) return E.start(state, now, side) end
  function g.press(side) return E.press(state, side, now) end
  function g.pause() return E.pause(state, now) end
  function g.resume() return E.resume(state, now) end
  function g.flag() return E.checkFlag(state, now) end
  function g.left(side) return E.remainingMs(state, side, now) end
  function g.readout(side) return E.readout(state, side, now) end
  return g
end

-- ===================== 通用计时 =====================

test("initial: both sides have base time, nothing runs before start", function()
  local g = game({ mode = "fischer", baseMs = 300000, incMs = 3000 })
  eq(g.left("w"), 300000)
  eq(g.left("b"), 300000)
  g.at(60000)
  eq(g.left("w"), 300000, "time must not run before the clock is started")
  eq(g.flag(), nil)
end)

test("fischer: increment is added on the move, opponent starts running", function()
  local g = game({ mode = "fischer", baseMs = 300000, incMs = 3000 })
  g.start("w")
  g.at(10000)
  eq(g.press("w").type, "move")
  eq(g.left("w"), 293000, "300 - 10 + 3")
  eq(g.state.moves.w, 1)
  eq(g.state.active, "b")
  g.at(4000)
  g.press("b")
  eq(g.left("b"), 299000, "300 - 4 + 3")
  eq(g.left("w"), 293000, "idle side must not change")
end)

test("fischer: the very first move gets the increment too", function()
  local g = game({ mode = "fischer", baseMs = 60000, incMs = 30000 })
  g.start("w")
  g.at(1000)
  g.press("w")
  eq(g.left("w"), 89000, "60 - 1 + 30")
end)

test("sudden death: a move only costs time", function()
  local g = game({ mode = "sudden", baseMs = 60000, incMs = 5000 })
  g.start("w")
  g.at(2000)
  g.press("w")
  eq(g.left("w"), 58000)
  eq(g.state.cfg.incMs, 0, "increment must be zeroed in sudden death")
end)

test("bronstein: first N seconds of each move are free", function()
  local g = game({ mode = "delay", baseMs = 300000, delayMs = 5000 })
  g.start("w")
  g.at(3000)
  eq(g.left("w"), 300000, "within the delay nothing is charged")
  g.at(5000)
  eq(g.left("w"), 297000, "only the 3 s beyond the delay are charged")
  eq(g.press("w").type, "move")
  eq(g.left("w"), 297000)
  g.at(20000)
  g.press("b")
  eq(g.left("b"), 285000, "300 - (20-5)")
end)

test("press on the idle side does nothing", function()
  local g = game({ mode = "sudden", baseMs = 60000 })
  g.start("w")
  g.at(1000)
  local r = g.press("b")
  eq(r.type, "ignored")
  eq(r.reason, "not-active")
  eq(g.state.moves.b, 0)
  eq(g.state.active, "w")
  eq(g.left("w"), 59000)
end)

test("duplicate delivery of the same touch is debounced", function()
  local g = game({ mode = "sudden", baseMs = 60000 })
  g.start("w")
  g.at(1000)
  eq(g.press("w").type, "move")
  g.at(10)
  local r = g.press("b")
  eq(r.type, "ignored")
  eq(r.reason, "debounced")
  eq(g.state.active, "b", "state must not be corrupted")
end)

test("pause settles elapsed time first, resume continues", function()
  local g = game({ mode = "fischer", baseMs = 300000, incMs = 0 })
  g.start("w")
  g.at(7000)
  g.pause()
  eq(g.left("w"), 293000)
  g.at(600000)
  eq(g.left("w"), 293000, "no time is consumed while paused")
  eq(g.flag(), nil)
  g.resume()
  g.at(3000)
  eq(g.left("w"), 290000)
end)

test("press while paused is ignored", function()
  local g = game({ mode = "sudden", baseMs = 60000 })
  g.start("w")
  g.at(1000)
  g.pause()
  local r = g.press("w")
  eq(r.type, "ignored")
  eq(r.reason, "paused")
end)

test("flag: runs out of time and stays finished", function()
  local g = game({ mode = "sudden", baseMs = 60000 })
  g.start("w")
  g.at(59000)
  eq(g.flag(), nil)
  g.at(1000)
  eq(g.flag(), "w")
  eq(g.state.finished, true)
  eq(g.left("w"), 0)
  eq(g.left("b"), 60000, "winner's time is untouched")
  g.at(60000)
  eq(g.flag(), nil, "no double flag")
end)

test("flag: pressing after the flag cannot buy the time back", function()
  local g = game({ mode = "fischer", baseMs = 60000, incMs = 30000 })
  g.start("w")
  g.at(60500)
  local r = g.press("w")
  eq(r.type, "flag")
  eq(r.side, "w")
  eq(g.state.moves.w, 0, "the flagged move is not counted")
  eq(g.state.finished, true)
end)

test("flag: still correct after the host was suspended for a long time", function()
  local g = game({ mode = "fischer", baseMs = 180000, incMs = 2000 })
  g.start("w")
  g.at(1000)
  g.press("w")
  eq(g.left("b"), 180000)
  g.at(10 * 60000)
  eq(g.flag(), "b")
  eq(g.state.flagged, "b")
end)

test("flag: pressing at the last moment flags first, no increment", function()
  local g = game({ mode = "fischer", baseMs = 10000, incMs = 5000 })
  g.start("w")
  g.at(10000)
  eq(g.press("w").type, "flag")
  eq(g.left("w"), 0)
end)

test("press before start starts the clock without counting a move", function()
  local g = game({ mode = "sudden", baseMs = 60000 })
  local r = g.press("w")
  eq(r.type, "start")
  eq(r.side, "w")
  eq(g.state.moves.w, 0)
  eq(g.state.started, true)
  eq(E.start(g.state, g.now(), "w").type, "ignored", "cannot start twice")
end)

test("increment never makes the remaining time negative", function()
  local g = game({ mode = "fischer", baseMs = 5000, incMs = 3000 })
  g.start("w")
  g.at(4999)
  g.press("w")
  eq(g.left("w"), 3001, "5 - 4.999 + 3")
end)

test("formatTime mirrors a real clock: hours / minutes / tenths", function()
  eq(E.formatTime(600000), "10:00")
  eq(E.formatTime(599900), "10:00", "rounds up like a real clock")
  eq(E.formatTime(59000), "0:59")
  eq(E.formatTime(3600000), "1:00:00")
  eq(E.formatTime(3661000), "1:01:01")
  eq(E.formatTime(20000), "0:20")
  eq(E.formatTime(19900), "19.9")
  eq(E.formatTime(0), "0.0")
  eq(E.formatTime(-5), "0.0")
  eq(E.formatTime(nil), "0.0")
end)

test("normalizeConfig clamps illegal input", function()
  local cfg = E.normalizeConfig({ mode = "nonsense", baseMs = -1, incMs = 999999 })
  eq(cfg.mode, "fischer")
  eq(cfg.baseMs, E.MIN_BASE_MS)
  eq(cfg.incMs, E.MAX_ADD_MS)

  local d = E.normalizeConfig({ mode = "delay", baseMs = 60000, delayMs = 10000 })
  eq(d.incMs, 0)
  eq(d.delayMs, 10000)
end)

test("full game: 10+5 over 60 moves keeps correct books", function()
  local g = game({ mode = "fischer", baseMs = 600000, incMs = 5000 })
  g.start("w")
  for i = 0, 59 do
    g.at(2000)
    local side = (i % 2 == 0) and "w" or "b"
    eq(g.press(side).type, "move")
  end
  eq(g.left("w"), 600000 + 30 * 3000)
  eq(g.left("b"), 600000 + 30 * 3000)
  eq(g.state.moves.w, 30)
  eq(g.state.moves.b, 30)
end)

-- ===================== Byoyomi 读秒 =====================

test("byoyomi: no periods are consumed while main time remains", function()
  local g = game({ mode = "byoyomi", baseMs = 60000, byoyomiMs = 30000, byoyomiPeriods = 1 })
  g.start("w")
  eq(g.readout("w").phase, "main")
  g.at(20000)
  local r = g.readout("w")
  eq(r.phase, "main")
  eq(r.ms, 40000)
  eq(r.periodsLeft, 1)
  g.press("w")
  eq(g.state.periods.w, 1, "moving inside main time consumes nothing")
  eq(g.left("w"), 40000)
end)

test("byoyomi: single period, exceeding it loses", function()
  local g = game({ mode = "byoyomi", baseMs = 10000, byoyomiMs = 30000, byoyomiPeriods = 1 })
  g.start("w")
  g.at(10000 + 29000)
  eq(g.readout("w").phase, "byoyomi")
  eq(g.readout("w").periodsLeft, 1)
  eq(g.readout("w").ms, 1000)
  eq(g.flag(), nil, "not over the byoyomi allowance yet")
  g.at(1000)
  eq(g.flag(), "w")
  eq(g.state.finished, true)
  eq(g.readout("w").ms, 0)
end)

test("byoyomi: 5 x 30 s allows 4 overruns, the 5th loses", function()
  local X = 30000
  local g = game({ mode = "byoyomi", baseMs = 1000, byoyomiMs = X, byoyomiPeriods = 5 })
  g.start("w")
  g.at(1000)
  eq(g.readout("w").phase, "byoyomi")
  eq(g.readout("w").periodsLeft, 5)

  for n = 1, 4 do
    g.at(X)
    local r = g.readout("w")
    eq(r.periodsLeft, 5 - n, "after overrun " .. n)
    eq(r.ms, X, "window restarts full")
    eq(g.flag(), nil, "still has periods left")
  end
  g.at(X)
  eq(g.flag(), "w")
  eq(g.state.periods.w, 0)
end)

test("byoyomi: every move restarts full, nothing accumulates", function()
  local g = game({ mode = "byoyomi", baseMs = 60000, byoyomiMs = 30000, byoyomiPeriods = 1 })
  g.start("w")
  g.at(60000 + 20000)
  eq(g.readout("w").ms, 10000)
  eq(g.press("w").type, "move")
  eq(g.state.periods.w, 1, "no period consumed without overrun")
  eq(g.state.ms.w, 0, "main time is spent")
  g.at(5000)
  g.press("b")
  local info = g.readout("w")
  eq(info.phase, "byoyomi")
  eq(info.ms, 30000, "next move starts a full 30 s window again")
end)

test("byoyomi: main time running out mid-move hands over to byoyomi", function()
  local g = game({ mode = "byoyomi", baseMs = 60000, byoyomiMs = 30000, byoyomiPeriods = 1 })
  g.start("w")
  g.at(58000)
  g.press("w")
  eq(g.left("w"), 2000)
  g.at(5000)
  g.press("b")
  g.at(31000)
  eq(g.readout("w").ms, 1000, "31 s spent: 2 s main + 29 s byoyomi")
  eq(g.flag(), nil)
  g.at(1000)
  eq(g.flag(), "w", "32 s total = 2 s main + 30 s byoyomi")
end)

test("byoyomi: making a move charges the periods it crossed", function()
  local g = game({ mode = "byoyomi", baseMs = 1000, byoyomiMs = 30000, byoyomiPeriods = 5 })
  g.start("w")
  g.at(1000 + 65000)
  eq(g.press("w").type, "move")
  eq(g.state.periods.w, 3, "5 - 2 = 3")
  eq(g.state.ms.w, 0)
  eq(g.readout("w").ms, 30000)
end)

test("byoyomi: idle side with spent main time shows a full window", function()
  local g = game({ mode = "byoyomi", baseMs = 5000, byoyomiMs = 20000, byoyomiPeriods = 2 })
  g.start("w")
  g.at(6000)
  g.press("w")
  local w = g.readout("w")
  eq(w.phase, "byoyomi")
  eq(w.ms, 20000)
  eq(w.periodsLeft, 2)
  local b = g.readout("b")
  eq(b.phase, "main")
  eq(b.ms, 5000)
end)

test("byoyomi: pause charges crossed periods, resume restarts the window", function()
  local g = game({ mode = "byoyomi", baseMs = 1000, byoyomiMs = 10000, byoyomiPeriods = 3 })
  g.start("w")
  g.at(1000)
  g.at(12000)
  eq(g.readout("w").periodsLeft, 2)
  g.pause()
  eq(g.state.periods.w, 2)
  g.at(50000)
  eq(g.state.periods.w, 2, "nothing runs while paused")
  g.resume()
  eq(g.readout("w").ms, 10000, "the arbiter stopping the clock must not cost a period")
  g.at(10000)
  eq(g.flag(), nil)
  eq(g.readout("w").periodsLeft, 1)
  g.at(10000)
  eq(g.flag(), "w")
end)

test("byoyomi: pressing after the flag cannot buy periods back", function()
  local g = game({ mode = "byoyomi", baseMs = 1000, byoyomiMs = 10000, byoyomiPeriods = 1 })
  g.start("w")
  g.at(1000 + 11000)
  local r = g.press("w")
  eq(r.type, "flag")
  eq(g.state.periods.w, 0)
  eq(g.state.finished, true)
end)

test("byoyomi: still correct after a 30 minute suspension", function()
  local g = game({ mode = "byoyomi", baseMs = 60000, byoyomiMs = 30000, byoyomiPeriods = 1 })
  g.start("w")
  g.at(61000)
  g.press("w")
  g.at(30 * 60000)
  eq(g.flag(), "b", "black spent main time and byoyomi long ago")
end)

test("byoyomi: config clamping and description", function()
  local cfg = E.normalizeConfig({
    mode = "byoyomi", baseMs = 3600000, byoyomiMs = 30000, byoyomiPeriods = 5,
  })
  eq(cfg.mode, "byoyomi")
  eq(cfg.incMs, 0)
  eq(cfg.delayMs, 0)
  eq(cfg.byoyomiMs, 30000)
  eq(cfg.byoyomiPeriods, 5)
  eq(E.describeConfig(cfg), "60 min + byoyomi 30s x5 - Byoyomi")

  local single = E.normalizeConfig({
    mode = "byoyomi", baseMs = 300000, byoyomiMs = 0, byoyomiPeriods = 0,
  })
  eq(single.byoyomiMs, E.MIN_BYOYOMI_MS, "0 s byoyomi clamps to the minimum")
  eq(single.byoyomiPeriods, 1)
  eq(E.describeConfig(single), "5 min + byoyomi 1s - Byoyomi")
end)

test("readout: non-byoyomi modes always report the main phase", function()
  local g = game({ mode = "fischer", baseMs = 60000, incMs = 5000 })
  g.start("w")
  g.at(3000)
  local r = g.readout("w")
  eq(r.phase, "main")
  eq(r.ms, 57000)
  eq(r.periodsLeft, nil)
  eq(r.windowIndex, 0)
  -- other() 必须是对外 API（超时结算层要用）
  eq(E.other("w"), "b")
  eq(E.other("b"), "w")
end)

-- ===================== 汇总 =====================

print("")
print(string.format("engine_spec: %d passed, %d failed, %d total", pass, fail, pass + fail))
if fail > 0 then
  print("")
  for _, f in ipairs(failures) do print("FAILED: " .. f) end
  os.exit(1)
end
