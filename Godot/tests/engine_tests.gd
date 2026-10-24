extends SceneTree
## engine_tests.gd — 计时引擎单元测试
##
## 与网页版 tests/engine.test.js 的 30 个用例**一一对应**（连用例名都对照），
## 时间由测试自己推进（绝对可控），不依赖真实时钟。
##
## 运行：
##   godot --headless --path . --script res://tests/engine_tests.gd

var _current := ""
var _passed := 0
var _failed := 0
var _failures: Array[String] = []


# ------------------------------------------------------------------ 测试脚手架

## 造一局并返回便捷操作对象（时间由我们手动推进，绝对可控）
class Game:
	var state: Dictionary
	var now: int = 1000000

	func _init(config) -> void:
		state = ClockEngine.new_game(config)

	func at(ms: int) -> int:
		now += ms
		return now

	func to(t: int) -> int:
		now = t
		return now

	func start(side: String) -> Dictionary:
		return ClockEngine.start(state, now, side)

	func press(side: String) -> Dictionary:
		return ClockEngine.press(state, side, now)

	func pause() -> Dictionary:
		return ClockEngine.pause(state, now)

	func resume() -> Dictionary:
		return ClockEngine.resume(state, now)

	func flag() -> String:
		return ClockEngine.check_flag(state, now)

	func left(side: String) -> int:
		return ClockEngine.remaining_ms(state, side, now)

	func readout(side: String) -> Dictionary:
		return ClockEngine.readout(state, side, now)


func eq(actual, expected, msg := "") -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s%s —— 期望 %s，实际 %s" % [
			_current, ("（" + msg + "）") if msg != "" else "", str(expected), str(actual)])


func ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s —— %s" % [_current, msg])


func run_case(label: String, fn: Callable) -> void:
	_current = label
	var failed_before := _failed
	fn.call()
	print(("  PASS  " if _failed == failed_before else "  FAIL  ") + label)


# ------------------------------------------------------------------ 入口

func _initialize() -> void:
	print("ClockEngine 单元测试（SceneTree 无头模式）")
	print("")
	run_case("初始状态：双方都是基础时间，未开表不倒计时", _t_initial)
	run_case("费舍尔加秒：走完一步立即给自己加秒，对方开始倒计时", _t_fischer)
	run_case("第一步也享有加秒（与 FIDE 规则一致）", _t_fischer_first_move)
	run_case("无加秒模式：走一步只扣时间", _t_sudden)
	run_case("布朗斯坦延时：每步前 N 秒不计时", _t_delay)
	run_case("按在非活动方的一侧不产生任何效果", _t_inactive_press)
	run_case("同一次触摸被重复投递时会被去抖忽略", _t_debounce)
	run_case("暂停会先结算已用时间，恢复后继续走", _t_pause)
	run_case("暂停时按钟无效", _t_press_while_paused)
	run_case("超时判定：时间耗尽即判负，之后不再变化", _t_flag)
	run_case("超时后再按钟不会把时间「救回来」", _t_flag_no_rescue)
	run_case("页面被挂起很久（定时器被冻结）后仍能算出正确的超时方", _t_suspended)
	run_case("超时方在最后一刻按键：先判超时，不享受加秒", _t_flag_last_moment)
	run_case("未开表时按任意一方 = 开表，且不算走子", _t_start_by_press)
	run_case("加秒不会因为长时间思考而变成负数", _t_inc_not_negative)
	run_case("时间格式化模仿实体钟：小时/分钟/十分之一秒", _t_format_time)
	run_case("配置规范化：非法输入会被夹到合法区间", _t_normalize)
	run_case("完整一局：10+5 走 60 回合后时间账目正确", _t_full_game)

	run_case("读秒：主时间阶段不消耗段数，主时间用完后才进入读秒", _t_byo_main_phase)
	run_case("读秒：单段制，超出读秒额度即判负", _t_byo_single)
	run_case("读秒：多段制 5×30 秒 = 可以超时思考 4 次，第 5 次判负", _t_byo_multi)
	run_case("读秒：每步重新满格，剩的时间不累积", _t_byo_refill)
	run_case("读秒：主时间中途耗尽时，这一手可用「剩余主时间 + 一格读秒」", _t_byo_handoff)
	run_case("读秒：读秒阶段落子会扣掉已经用掉的段数", _t_byo_commit)
	run_case("读秒：非活动方主时间已耗尽时，钟上预备一格满读秒", _t_byo_prepared)
	run_case("读秒：暂停会扣掉已跨过的段数，恢复后当前窗口重新开始", _t_byo_pause)
	run_case("读秒：超时后再按钟不能把段数「救回来」", _t_byo_no_rescue)
	run_case("读秒：页面被挂起很久后仍能判出正确的超时方", _t_byo_suspended)
	run_case("读秒：配置夹取与文字描述", _t_byo_config)
	run_case("读秒：主时间 0 = 纯读秒，读秒 0 = 只有主时间（两个不能同时为 0）", _t_byo_zero)
	run_case("readout：非读秒模式统一返回主时间阶段", _t_readout_main)

	print("")
	print("engine: %d 项断言通过, %d 项失败（共 31 个用例）" % [_passed, _failed])
	for line in _failures:
		print("  ✗ " + line)
	quit(0 if _failed == 0 else 1)


# ------------------------------------------------------------------ 用例

func _t_initial() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 300000, "incMs": 3000})
	eq(g.left("w"), 300000)
	eq(g.left("b"), 300000)
	g.at(60000)  # 开表前干等 60 秒
	eq(g.left("w"), 300000, "未开表不应消耗时间")
	eq(g.flag(), "")


func _t_fischer() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 300000, "incMs": 3000})
	g.start("w")
	g.at(10000)
	var r := g.press("w")
	eq(r["type"], "move")
	eq(g.left("w"), 293000)  # 300 - 10 + 3
	eq(g.state["moves"]["w"], 1)
	eq(g.state["active"], "b")
	g.at(4000)
	g.press("b")
	eq(g.left("b"), 299000)  # 300 - 4 + 3
	eq(g.left("w"), 293000, "非活动方时间不应变化")


func _t_fischer_first_move() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 60000, "incMs": 30000})
	g.start("w")
	g.at(1000)
	g.press("w")
	eq(g.left("w"), 89000)  # 60 - 1 + 30


func _t_sudden() -> void:
	var g := Game.new({"mode": "sudden", "baseMs": 60000, "incMs": 5000})
	g.start("w")
	g.at(2000)
	g.press("w")
	eq(g.left("w"), 58000)
	eq(g.state["cfg"]["incMs"], 0, "无加秒模式下加秒配置应被清零")


func _t_delay() -> void:
	var g := Game.new({"mode": "delay", "baseMs": 300000, "delayMs": 5000})
	g.start("w")
	g.at(3000)
	eq(g.left("w"), 300000, "延时内时间不动")
	g.at(5000)
	eq(g.left("w"), 297000, "只扣超出延时的 3 秒")
	var r := g.press("w")
	eq(r["type"], "move")
	eq(g.left("w"), 297000)
	g.at(20000)
	g.press("b")
	eq(g.left("b"), 285000)  # 300 - (20-5)


func _t_inactive_press() -> void:
	var g := Game.new({"mode": "sudden", "baseMs": 60000})
	g.start("w")
	g.at(1000)
	var r := g.press("b")
	eq(r["type"], "ignored")
	eq(r["reason"], "not-active")
	eq(g.state["moves"]["b"], 0)
	eq(g.state["active"], "w")
	eq(g.left("w"), 59000)


func _t_debounce() -> void:
	var g := Game.new({"mode": "sudden", "baseMs": 60000})
	g.start("w")
	g.at(1000)
	eq(g.press("w")["type"], "move")
	g.at(10)
	var r := g.press("b")
	eq(r["type"], "ignored")
	eq(r["reason"], "debounced")
	eq(g.state["active"], "b", "棋盘状态不应被误改")


func _t_pause() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 300000, "incMs": 0})
	g.start("w")
	g.at(7000)
	g.pause()
	eq(g.left("w"), 293000)
	g.at(600000)
	eq(g.left("w"), 293000, "暂停期间不计时")
	eq(g.flag(), "")
	g.resume()
	g.at(3000)
	eq(g.left("w"), 290000)
	eq(g.state["cfg"]["incMs"], 0)


func _t_press_while_paused() -> void:
	var g := Game.new({"mode": "sudden", "baseMs": 60000})
	g.start("w")
	g.at(1000)
	g.pause()
	var r := g.press("w")
	eq(r["type"], "ignored")
	eq(r["reason"], "paused")


func _t_flag() -> void:
	var g := Game.new({"mode": "sudden", "baseMs": 60000})
	g.start("w")
	g.at(59000)
	eq(g.flag(), "")
	g.at(1000)
	eq(g.flag(), "w")
	eq(g.state["finished"], true)
	eq(g.left("w"), 0)
	eq(g.left("b"), 60000, "胜方时间不动")
	g.at(60000)
	eq(g.flag(), "", "已结束不再重复判负")


func _t_flag_no_rescue() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 60000, "incMs": 30000})
	g.start("w")
	g.at(60500)
	var r := g.press("w")
	eq(r["type"], "flag")
	eq(r["side"], "w")
	eq(g.state["moves"]["w"], 0, "超时的那一步不算走子")
	eq(g.state["finished"], true)


func _t_suspended() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 180000, "incMs": 2000})
	g.start("w")
	g.at(1000)
	g.press("w")
	eq(g.left("b"), 180000)
	g.at(10 * 60000)
	eq(g.flag(), "b")
	eq(g.state["flagged"], "b")


func _t_flag_last_moment() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 10000, "incMs": 5000})
	g.start("w")
	g.at(10000)
	var r := g.press("w")
	eq(r["type"], "flag")
	eq(g.left("w"), 0)


func _t_start_by_press() -> void:
	var g := Game.new({"mode": "sudden", "baseMs": 60000})
	var r := g.press("w")
	eq(r["type"], "start")
	eq(r["side"], "w")
	eq(g.state["moves"]["w"], 0)
	eq(g.state["started"], true)
	eq(ClockEngine.start(g.state, g.now, "w")["type"], "ignored", "不能重复开表")


func _t_inc_not_negative() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 5000, "incMs": 3000})
	g.start("w")
	g.at(4999)
	g.press("w")
	eq(g.left("w"), 3001)  # 5 - 4.999 + 3


func _t_format_time() -> void:
	eq(ClockEngine.format_time(600000), "10:00")
	eq(ClockEngine.format_time(599900), "10:00", "向上取整")
	eq(ClockEngine.format_time(59000), "0:59")
	eq(ClockEngine.format_time(3600000), "1:00:00")
	eq(ClockEngine.format_time(3661000), "1:01:01")
	eq(ClockEngine.format_time(20000), "0:20")
	eq(ClockEngine.format_time(19900), "19.9")
	eq(ClockEngine.format_time(0), "0.0")
	eq(ClockEngine.format_time(-5), "0.0")
	eq(ClockEngine.format_time(NAN), "0.0")


func _t_normalize() -> void:
	var cfg := ClockEngine.normalize_config({"mode": "nonsense", "baseMs": -1, "incMs": 999999})
	eq(cfg["mode"], "fischer")
	eq(cfg["baseMs"], ClockEngine.MIN_BASE_MS)
	eq(cfg["incMs"], ClockEngine.MAX_ADD_MS)

	var delay_cfg := ClockEngine.normalize_config({"mode": "delay", "baseMs": 60000, "delayMs": 10000})
	eq(delay_cfg["incMs"], 0)
	eq(delay_cfg["delayMs"], 10000)


func _t_full_game() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 600000, "incMs": 5000})
	g.start("w")
	for i in 60:
		g.at(2000)
		eq(g.press("w" if i % 2 == 0 else "b")["type"], "move")
	eq(g.left("w"), 600000 + 30 * 3000)
	eq(g.left("b"), 600000 + 30 * 3000)
	eq(g.state["moves"]["w"], 30)
	eq(g.state["moves"]["b"], 30)


# ------------------------------------------------------------------ 读秒

func _t_byo_zero() -> void:
	# —— 纯读秒：主时间 0，钟上从第一手起就是读秒那一格 ——
	var pure := Game.new({"mode": "byoyomi", "baseMs": 0, "byoyomiMs": 20000, "byoyomiPeriods": 3})
	eq(pure.left("w"), 0)
	var idle := ClockEngine.readout(pure.state, "w", pure.now)
	eq(idle["phase"], "byoyomi", "主时间 0 时空闲状态就显示读秒窗口")
	eq(idle["ms"], 20000, "空闲时显示一整格读秒")
	eq(idle["periodsLeft"], 3)
	pure.start("w")
	pure.at(18000)                       # 白方想了 18 秒
	eq(ClockEngine.readout(pure.state, "w", pure.now)["ms"], 2000)
	var r1 := pure.press("w")
	eq(r1["type"], "move")
	eq(pure.state["periods"]["w"], 3, "没有超过一格，段数不减")
	pure.at(61000)                       # 黑方想了 61 秒 = 跨满 3 格
	eq(pure.flag(), "b", "纯读秒下超时同样按段数判负")
	eq(pure.state["periods"]["b"], 0)

	# —— 只有主时间：读秒 0 秒，用完即负（等价于包干制）——
	var main_only := Game.new({"mode": "byoyomi", "baseMs": 60000, "byoyomiMs": 0, "byoyomiPeriods": 3})
	main_only.start("w")
	main_only.at(59000)
	eq(ClockEngine.readout(main_only.state, "w", main_only.now)["phase"], "main")
	eq(main_only.flag(), "")
	main_only.at(2000)
	eq(main_only.flag(), "w", "没有读秒时主时间归零就判负")

	# —— 两个都是 0：没有意义，回落到 1 分钟主时间 ——
	var none := ClockEngine.normalize_config({"mode": "byoyomi", "baseMs": 0, "byoyomiMs": 0})
	eq(none["baseMs"], 60000, "两个都 0 时回落 1 分钟主时间")
	eq(none["byoyomiMs"], 0)

func _t_byo_main_phase() -> void:
	var g := Game.new({"mode": "byoyomi", "baseMs": 60000, "byoyomiMs": 30000, "byoyomiPeriods": 1})
	g.start("w")
	eq(g.readout("w")["phase"], "main")
	g.at(20000)
	var r := g.readout("w")
	eq(r["phase"], "main")
	eq(r["ms"], 40000)
	eq(r["periodsLeft"], 1)
	g.press("w")
	eq(g.state["periods"]["w"], 1, "主时间内走子不消耗读秒段")
	eq(g.left("w"), 40000)


func _t_byo_single() -> void:
	var g := Game.new({"mode": "byoyomi", "baseMs": 10000, "byoyomiMs": 30000, "byoyomiPeriods": 1})
	g.start("w")
	g.at(10000 + 29000)
	eq(g.readout("w")["phase"], "byoyomi")
	eq(g.readout("w")["periodsLeft"], 1)
	eq(g.readout("w")["ms"], 1000)
	eq(g.flag(), "", "还没超出读秒")
	g.at(1000)
	eq(g.flag(), "w")
	eq(g.state["finished"], true)
	eq(g.readout("w")["ms"], 0)


func _t_byo_multi() -> void:
	var x := 30000
	var g := Game.new({"mode": "byoyomi", "baseMs": 1000, "byoyomiMs": x, "byoyomiPeriods": 5})
	g.start("w")
	g.at(1000)
	eq(g.readout("w")["phase"], "byoyomi")
	eq(g.readout("w")["periodsLeft"], 5)

	for n in range(1, 5):
		g.at(x)
		var r := g.readout("w")
		eq(r["periodsLeft"], 5 - n, "第 %d 次超时后应剩 %d 段" % [n, 5 - n])
		eq(r["ms"], x, "窗口应重新满格")
		eq(g.flag(), "", "还有剩余段数就不该判负")
	g.at(x)
	eq(g.flag(), "w")
	eq(g.state["periods"]["w"], 0)


func _t_byo_refill() -> void:
	var g := Game.new({"mode": "byoyomi", "baseMs": 60000, "byoyomiMs": 30000, "byoyomiPeriods": 1})
	g.start("w")
	g.at(60000 + 20000)
	eq(g.readout("w")["ms"], 10000)
	eq(g.press("w")["type"], "move")
	eq(g.state["periods"]["w"], 1, "没超时就不消耗段数")
	eq(g.state["ms"]["w"], 0, "主时间已耗尽")
	g.at(5000)
	g.press("b")
	var info := g.readout("w")
	eq(info["phase"], "byoyomi")
	eq(info["ms"], 30000, "下一手重新满格，不累积上一手剩下的 10 秒")


func _t_byo_handoff() -> void:
	var g := Game.new({"mode": "byoyomi", "baseMs": 60000, "byoyomiMs": 30000, "byoyomiPeriods": 1})
	g.start("w")
	g.at(58000)
	g.press("w")
	eq(g.left("w"), 2000)
	g.at(5000)
	g.press("b")
	g.at(31000)
	eq(g.readout("w")["ms"], 1000, "读了 31 秒，读秒窗口还剩 1 秒")
	eq(g.flag(), "")
	g.at(1000)
	eq(g.flag(), "w", "累计 32 秒 = 2 秒主时间 + 30 秒读秒")


func _t_byo_commit() -> void:
	var g := Game.new({"mode": "byoyomi", "baseMs": 1000, "byoyomiMs": 30000, "byoyomiPeriods": 5})
	g.start("w")
	g.at(1000 + 65000)
	eq(g.press("w")["type"], "move")
	eq(g.state["periods"]["w"], 3, "5 - 2 = 3 段")
	eq(g.state["ms"]["w"], 0)
	eq(g.readout("w")["ms"], 30000, "下一手满格")


func _t_byo_prepared() -> void:
	var g := Game.new({"mode": "byoyomi", "baseMs": 5000, "byoyomiMs": 20000, "byoyomiPeriods": 2})
	g.start("w")
	g.at(6000)
	g.press("w")
	var w := g.readout("w")
	eq(w["phase"], "byoyomi")
	eq(w["ms"], 20000)
	eq(w["periodsLeft"], 2)
	var b := g.readout("b")
	eq(b["phase"], "main")
	eq(b["ms"], 5000)


func _t_byo_pause() -> void:
	var g := Game.new({"mode": "byoyomi", "baseMs": 1000, "byoyomiMs": 10000, "byoyomiPeriods": 3})
	g.start("w")
	g.at(1000)
	g.at(12000)
	eq(g.readout("w")["periodsLeft"], 2)
	g.pause()
	eq(g.state["periods"]["w"], 2)
	g.at(50000)
	eq(g.state["periods"]["w"], 2)
	g.resume()
	eq(g.readout("w")["ms"], 10000, "恢复后当前窗口满格，裁判停表不该让选手白丢读秒")
	g.at(10000)
	eq(g.flag(), "")
	eq(g.readout("w")["periodsLeft"], 1)
	g.at(10000)
	eq(g.flag(), "w")


func _t_byo_no_rescue() -> void:
	var g := Game.new({"mode": "byoyomi", "baseMs": 1000, "byoyomiMs": 10000, "byoyomiPeriods": 1})
	g.start("w")
	g.at(1000 + 11000)
	var r := g.press("w")
	eq(r["type"], "flag")
	eq(g.state["periods"]["w"], 0)
	eq(g.state["finished"], true)


func _t_byo_suspended() -> void:
	var g := Game.new({"mode": "byoyomi", "baseMs": 60000, "byoyomiMs": 30000, "byoyomiPeriods": 1})
	g.start("w")
	g.at(61000)
	g.press("w")
	g.at(30 * 60000)
	eq(g.flag(), "b", "黑方主时间早就没了，读秒也早超了")


func _t_byo_config() -> void:
	var cfg := ClockEngine.normalize_config({
		"mode": "byoyomi", "baseMs": 3600000, "byoyomiMs": 30000, "byoyomiPeriods": 5,
	})
	eq(cfg["mode"], "byoyomi")
	eq(cfg["incMs"], 0)
	eq(cfg["delayMs"], 0)
	eq(cfg["byoyomiMs"], 30000)
	eq(cfg["byoyomiPeriods"], 5)
	eq(ClockEngine.describe_config(cfg), "60 分钟 + 读秒 30 秒 × 5 段 · Byoyomi 读秒")

	var single := ClockEngine.normalize_config({
		"mode": "byoyomi", "baseMs": 300000, "byoyomiMs": 0, "byoyomiPeriods": 0,
	})
	eq(single["byoyomiMs"], 0, "读秒 0 秒表示「没有读秒」")
	eq(single["byoyomiPeriods"], 1)
	eq(ClockEngine.describe_config(single), "5 分钟（无读秒） · Byoyomi 读秒")


func _t_readout_main() -> void:
	var g := Game.new({"mode": "fischer", "baseMs": 60000, "incMs": 5000})
	g.start("w")
	g.at(3000)
	var r := g.readout("w")
	eq(r["phase"], "main")
	eq(r["ms"], 57000)
	eq(r["periodsLeft"], null)
	eq(r["windowIndex"], 0)
