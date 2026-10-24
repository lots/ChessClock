--[[
  settings_spec.lua — 设置模块单元测试（纯 Lua，不依赖 Defold）
  ==================================================================
  校验两件最容易在「同步网页版改动」时出错的事：
    1) 首次启动的默认值与网页版 app.js 的 DEFAULTS 一致
       （Byoyomi 10+3×20：10 分钟 / 每手 20 秒 / 3 段）；
    2) 旧存档（v1：没有 settingsVersion、没有 swapped 键）能平滑读取 ——
       缺的键补默认，语义没变的键原样保留。

  sys.save / sys.load 是 Defold 的 API，单测里用一个内存表顶替。

  运行（任意 Lua 5.1+ 解释器）：
      lua tests/settings_spec.lua
]]

-- 让脚本无论从哪个目录启动都能 require 到 ../logic/settings.lua
local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")) or "."
package.path = here .. "/../logic/?.lua;" .. here .. "/?.lua;" .. package.path

-- ===================== Defold 存档 API 的替身 =====================

local store = {}
sys = {
  save = function(file, data) store[file] = data end,
  load = function(file) return store[file] end,
}

local settings = require("settings")

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

-- ===================== 首次启动的默认值 =====================

test("defaults: first launch is Byoyomi 10+3x20 (same as the web version)", function()
  local s = settings.sanitize(nil)
  eq(s.mode, "byoyomi")
  eq(s.baseMin, 10)
  eq(s.addSec, 20)
  eq(s.periods, 3)
  eq(s.sound, true)
  eq(s.facing, true)
  eq(s.swapped, false)
  eq(s.theme, "dark", "默认主题是深色（与网页版 DEFAULTS.theme 一致）")
  eq(s.settingsVersion, settings.SETTINGS_VERSION)
  eq(settings.SETTINGS_VERSION, 2)
end)

test("theme: valid names are kept, junk falls back to dark", function()
  eq(settings.sanitize({ theme = "light" }).theme, "light")
  eq(settings.sanitize({ theme = "medium" }).theme, "medium")
  eq(settings.sanitize({ theme = "dark" }).theme, "dark")
  eq(settings.sanitize({ theme = "neon" }).theme, "dark", "不认识的主题名要回落到默认")
  eq(settings.sanitize({ theme = 42 }).theme, "dark")
  eq(settings.sanitize({}).theme, "dark", "旧存档没有 theme 键 -> 默认深色")
end)

test("toEngineConfig: byoyomi defaults become 10 min + 20 s x 3", function()
  local c = settings.toEngineConfig(nil)
  eq(c.mode, "byoyomi")
  eq(c.baseMs, 600000)
  eq(c.byoyomiMs, 20000)
  eq(c.byoyomiPeriods, 3)
  -- 四个「加时」字段填同一个值，由引擎按 mode 取用（与网页版 engineConfig 一致）
  eq(c.incMs, 20000)
  eq(c.delayMs, 20000)
end)

-- ===================== 旧存档迁移 =====================

test("legacy save (v1, Fischer 10+5) is read as-is and gets the new keys", function()
  -- v1 存档：没有 settingsVersion、没有 swapped；旧默认是 Fischer 10+5
  local s = settings.sanitize({ mode = "fischer", baseMin = 10, addSec = 5, periods = 1,
    sound = false, facing = false })
  eq(s.mode, "fischer", "用户挑过的模式必须保留")
  eq(s.baseMin, 10)
  eq(s.addSec, 5, "用户挑过的加秒必须保留")
  eq(s.periods, 1)
  eq(s.sound, false)
  eq(s.facing, false)
  eq(s.swapped, false, "旧存档没有 swapped 键 -> 默认 false")
  eq(s.settingsVersion, 2, "读一遍就该升到当前版本")
end)

test("legacy save with unknown / junk keys still loads", function()
  local s = settings.sanitize({
    mode = "byoyomi", baseMin = "7", addSec = "15", periods = "5",
    swapped = true, started = true, bogus = { 1, 2, 3 },
  })
  eq(s.mode, "byoyomi")
  eq(s.baseMin, 7, "数字字符串要能读成数字")
  eq(s.addSec, 15)
  eq(s.periods, 5)
  eq(s.swapped, true)
  eq(s.started, nil, "旧版残留的 started 不该被保留")
  eq(s.bogus, nil)
end)

test("byoyomi allows 0 s per move (main time only) but never 0 main time too", function()
  -- 5 分钟 + 0 秒读秒是合法的：只有主时间，用完即负
  local mainOnly = settings.sanitize({ mode = "byoyomi", baseMin = 5, addSec = 0, periods = 3 })
  eq(mainOnly.addSec, 0)
  eq(mainOnly.baseMin, 5)
  -- 0 主时间 + 20 秒读秒 = 纯读秒
  local pure = settings.sanitize({ mode = "byoyomi", baseMin = 0, addSec = 20, periods = 3 })
  eq(pure.baseMin, 0)
  eq(pure.addSec, 20)
  -- 两个都 0 没有意义 → 主时间回落 1 分钟
  local none = settings.sanitize({ mode = "byoyomi", baseMin = 0, addSec = 0, periods = 3 })
  eq(none.baseMin, 1)
  eq(none.addSec, 0)
  -- 非读秒模式的主时间仍然至少 1 分钟
  eq(settings.sanitize({ mode = "fischer", baseMin = 0, addSec = 0 }).baseMin, 1)
end)

test("sudden death always carries 0 s increment", function()
  eq(settings.sanitize({ mode = "sudden", baseMin = 20, addSec = 30 }).addSec, 0)
end)

test("unknown mode falls back to the default mode", function()
  eq(settings.sanitize({ mode = "kaboom" }).mode, "byoyomi")
end)

test("swapped is a strict boolean", function()
  eq(settings.sanitize({ swapped = true }).swapped, true)
  eq(settings.sanitize({ swapped = "yes" }).swapped, false)
  eq(settings.sanitize({ swapped = 1 }).swapped, false)
  eq(settings.sanitize({}).swapped, false)
end)

test("numbers are clamped into the legal ranges", function()
  -- 用 Fischer 试夹取：Byoyomi 下 0 秒读秒是合法的（见上一个用例），Fischer 的主时间下限仍是 1
  local s = settings.sanitize({ mode = "fischer", baseMin = 0, addSec = -5, periods = 99 })
  eq(s.baseMin, 1)
  eq(s.addSec, 0)
  eq(s.periods, 20)
  local big = settings.sanitize({ baseMin = 999, addSec = 999, periods = 0 })
  eq(big.baseMin, 180)
  eq(big.addSec, 180)
  eq(big.periods, 1)
end)

test("sanitize is idempotent", function()
  local once = settings.sanitize({ mode = "delay", baseMin = 15, addSec = 10, swapped = true })
  local twice = settings.sanitize(once)
  for _, k in ipairs({ "mode", "baseMin", "addSec", "periods", "sound", "facing",
      "swapped", "settingsVersion" }) do
    eq(twice[k], once[k], "sanitize 第二次改变了 " .. k)
  end
end)

-- ===================== 存取 =====================

test("save then load round-trips through sys.save / sys.load", function()
  settings.save({ mode = "fischer", baseMin = 3, addSec = 2, periods = 1, swapped = true })
  local s = settings.load()
  eq(s.mode, "fischer")
  eq(s.baseMin, 3)
  eq(s.addSec, 2)
  eq(s.swapped, true)
  eq(s.settingsVersion, 2)
end)

test("a corrupt save falls back to the defaults", function()
  store["chessclock_settings"] = "not a table"
  local s = settings.load()
  eq(s.mode, "byoyomi")
  eq(s.baseMin, 10)
  store["chessclock_settings"] = nil
  eq(settings.load().mode, "byoyomi", "没有存档时也是默认值")
end)

-- ===================== 汇总 =====================

print("")
print(string.format("settings_spec: %d passed, %d failed, %d total", pass, fail, pass + fail))
if fail > 0 then
  print("")
  for _, f in ipairs(failures) do print("FAILED: " .. f) end
  os.exit(1)
end
