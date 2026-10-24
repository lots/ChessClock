extends SceneTree
## ui_tests.gd — 界面层的集成测试（无头运行，不需要窗口）
##
## 把 main.tscn 真的实例化出来，然后按真实操作顺序走一遍：
## 开始对局 → 拍对侧开表 → 走两手 → 暂停/继续 → 交换两侧 → 对坐旋转 →
## 换主题 / 换语言 → 超时结算 → 再来一局 → 返回设置。
## 每一步都检查界面状态（哪块面板在前、谁被旋转、覆盖层有没有出来、显示的文字对不对）。
##
## 运行：
##   godot --headless --path . --script res://tests/ui_tests.gd

var _passed := 0
var _failed := 0
var _failures: Array[String] = []
var _app: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 用单独的存档文件：跑测试不能顺手把用户的设置改了
	ClockSettings.file_path = "user://ui_test_settings.json"
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("ui_test_settings.json"):
		dir.remove("ui_test_settings.json")

	await process_frame
	_app = load("res://ui/main.tscn").instantiate()
	root.add_child(_app)
	await process_frame
	await process_frame

	_case("启动状态：显示设置页、棋钟页隐藏、没有对局", _check_startup)
	_case("开始对局：进棋钟页、双方各 10 分钟、暂停按钮隐藏", _check_new_game)
	_case("拍黑方的那一半 = 开表，由白方开始计时（不算走子）", _check_start_by_press)
	_case("拍自己那一侧 = 走完一手，时间交给对方", _check_move)
	_case("拍非走棋方没有任何效果", _check_inactive_press)
	_case("暂停 / 继续", _check_pause)
	_case("交换两侧：只换位置，旋转跟着视觉上第一块走", _check_swap)
	_case("对坐模式：竖屏把对侧面板转 180°，关掉就不转", _check_facing)
	_case("时间显示：格式、十分之一秒", _check_time_text)
	_case("换主题：三套配色都落地", _check_themes)
	_case("换语言：文案、面板标题一起变", _check_language)
	_case("超时：停表 + 结算层 + 正确的胜负", _check_flag)
	_case("再来一局：棋钟归零、结算层收起", _check_rematch)
	_case("返回设置：结束对局、回到设置页", _check_back_to_setup)
	_case("怎么用：单独一页，能从设置页进入、返回键退回", _check_help_page)
	_case("按钮接线：设置页与操作条的信号真的连上了", _check_buttons)
	_case("存档：设置真的写进了文件，读回来还是那些值", _check_persistence)
	_case("安卓返回键：先收确认框 / 再回设置，不会直接退出对局", _check_back_button)
	_case("读秒段数条：Byoyomi 才出现，跨过一段变红，倒计时段按比例变红", _check_byoyomi_bar)
	_case("时间可以为 0：读秒模式下主时间 / 读秒各能为 0，但不能同时为 0", _check_zero_times)
	_case("最后 10 秒提示音：主时间与读秒都算，一声只响一次", _check_last_ten_tick)

	print("")
	print("ui: %d 项断言通过, %d 项失败" % [_passed, _failed])
	for line in _failures:
		print("  ✗ " + line)
	_app.queue_free()
	await process_frame
	quit(0 if _failed == 0 else 1)


# ------------------------------------------------------------------ 用例

func _check_startup() -> void:
	_ok(_app.setup_view.visible, "设置页应可见")
	_ok(not _app.clock_view.visible, "棋钟页应隐藏")
	_ok(_app.state.is_empty(), "启动时不应有对局状态")
	_eq(_app.cfg["mode"], "byoyomi", "默认模式")
	_eq(int(_app.cfg["baseMin"]), 10, "默认基础时间")
	_eq(int(_app.cfg["incSec"]), 20, "默认读秒秒数")
	_eq(int(_app.cfg["periods"]), 3, "默认读秒段数")
	_eq(_app.cfg["theme"], "dark", "默认主题")
	_eq(_app.lang, "en", "默认语言")


func _check_new_game() -> void:
	_app.new_game()
	_ok(_app.clock_view.visible, "棋钟页应可见")
	_ok(not _app.setup_view.visible, "设置页应隐藏")
	_ok(not bool(_app.state["started"]), "还没开表")
	_eq(int(_app.state["ms"]["w"]), 600000, "白方 10 分钟")
	_eq(int(_app.state["ms"]["b"]), 600000, "黑方 10 分钟")
	_eq(_app.clock_view._times["w"].text, "10:00", "白方显示 10:00")
	_ok(not _app.clock_view._pause_btn.visible, "未开表时暂停按钮隐藏")


func _check_start_by_press() -> void:
	_app.press("b")
	_ok(bool(_app.state["started"]), "应已开表")
	_eq(_app.state["active"], "w", "白方开始走")
	_eq(int(_app.state["moves"]["w"]), 0, "开表那一下不算步数")
	_eq(int(_app.state["moves"]["b"]), 0, "开表那一下不算步数")
	_ok(_app.clock_view._pause_btn.visible, "开表后暂停按钮出现")


func _check_move() -> void:
	_app.press("w")
	_eq(_app.state["active"], "b", "轮到黑方")
	_eq(int(_app.state["moves"]["w"]), 1, "白方走了一手")
	_eq(_app.clock_view._feet["w"].text, "Move 1", "面板上写着第 1 步")


func _check_inactive_press() -> void:
	var moves_before := int(_app.state["moves"]["w"])
	_app.press("w")
	_eq(int(_app.state["moves"]["w"]), moves_before, "步数不变")
	_eq(_app.state["active"], "b", "仍轮到黑方")


func _check_pause() -> void:
	_app.toggle_pause()
	_ok(bool(_app.state["paused"]), "应已暂停")
	_ok(_app.clock_view._badge.visible, "棋钟页应显示「暂停」")
	var before := int(_app.state["moves"]["b"])
	_app.press("b")
	_eq(int(_app.state["moves"]["b"]), before, "暂停时拍钟无效")
	_app.toggle_pause()
	_ok(not bool(_app.state["paused"]), "应已继续")
	_ok(not _app.clock_view._badge.visible, "「暂停」提示应消失")


func _check_swap() -> void:
	_ok(not bool(_app.cfg["swapped"]), "默认不交换")
	_app._toggle_swap()
	_ok(bool(_app.cfg["swapped"]), "应已交换")
	var panes: BoxContainer = _app.clock_view._panes
	_eq(panes.get_child(0).name, _app.clock_view._panes_map["w"].name, "白方应排在最前")
	_eq(panes.get_child(2).name, _app.clock_view._panes_map["b"].name, "黑方应排在最后")
	_ok(absf(_app.clock_view._inners["w"].rotation - PI) < 0.01, "交换后被旋转的应是白方")
	_ok(absf(_app.clock_view._inners["b"].rotation) < 0.01, "黑方不旋转")


func _check_facing() -> void:
	_ok(bool(_app.cfg["facing"]), "默认开启对坐模式")
	_ok(absf(_app.clock_view._inners["w"].rotation - PI) < 0.01, "交换过：被旋转的是白方")
	_app._toggle_facing()
	_ok(absf(_app.clock_view._inners["w"].rotation) < 0.01, "关掉后不再旋转")
	_app._toggle_facing()
	_ok(absf(_app.clock_view._inners["w"].rotation - PI) < 0.01, "再打开又旋转")
	_app._toggle_swap()
	_ok(not bool(_app.cfg["swapped"]), "换回默认位置")
	_ok(absf(_app.clock_view._inners["b"].rotation - PI) < 0.01, "换回后被旋转的是黑方")


func _check_time_text() -> void:
	_app.state["ms"]["b"] = 65000
	_app.state["turnStart"] = Time.get_ticks_msec()
	_app.clock_view.render(_app.state, Time.get_ticks_msec())
	_eq(_app.clock_view._times["b"].text, "1:05", "65 秒显示为 1:05")
	_app.state["ms"]["b"] = 15000
	_app.clock_view.render(_app.state, Time.get_ticks_msec())
	_eq(_app.clock_view._times["b"].text, "15.0", "20 秒内显示十分之一秒")
	_app.state["ms"]["b"] = 600000


func _check_themes() -> void:
	_app._set_theme("light")
	_eq(_app.cfg["theme"], "light", "主题已换成浅色")
	_eq(_app.palette["bg"], ClockTheme.palette("light")["bg"], "调色板跟着换")
	_app._set_theme("medium")
	_eq(_app.cfg["theme"], "medium", "中性主题")
	_app._set_theme("dark")
	_eq(_app.cfg["theme"], "dark", "回到深色")


func _check_language() -> void:
	_app._apply_language("zh")
	_eq(_app.lang, "zh", "语言已切换")
	_eq(_app.clock_view._tags["w"].text, "白方", "白方面板标题")
	_eq(_app.clock_view._tags["b"].text, "黑方", "黑方面板标题")
	_eq(_app.t("setup.start"), "开始对局", "按钮文案")
	_app._apply_language("en")
	_eq(_app.clock_view._tags["w"].text, "White", "换回英文")


func _check_flag() -> void:
	# 读秒模式下主时间用完只是进入读秒，必须把读秒段数也耗光才判负：
	# 10 分钟主时间 + 20 秒 × 3 段 → 661 秒之后黑方才真正超时
	_app.state["ms"]["b"] = 600000
	_app.state["turnStart"] = Time.get_ticks_msec() - 661000
	_app._tick()
	_ok(bool(_app.state["finished"]), "应已结束")
	_eq(_app.state["flagged"], "b", "超时的是黑方（当时轮到黑方）")
	_ok(_app.overlay.visible, "结算层应出现")
	_ok(_app.overlay._title.text.find("Black") >= 0, "标题写着谁超时")


func _check_rematch() -> void:
	_app.new_game()
	_ok(not _app.overlay.visible, "结算层收起")
	_ok(not bool(_app.state["started"]), "新的一局还没开表")
	_eq(int(_app.state["moves"]["w"]), 0, "步数归零")


func _check_back_to_setup() -> void:
	_app.press("b")
	_app._leave_game()
	_ok(_app.state.is_empty(), "对局状态已清空")
	_ok(_app.setup_view.visible, "回到设置页")
	_ok(not _app.clock_view.visible, "棋钟页隐藏")


## 读秒段数条：主时间阶段整条都亮，读秒阶段每用掉一段就暗一段；非读秒模式隐藏。
func _check_byoyomi_bar() -> void:
	_app.cfg["mode"] = "byoyomi"
	_app.cfg["baseMin"] = 10
	_app.cfg["incSec"] = 20
	_app.cfg["periods"] = 3
	_app.new_game()
	var bar: ByoyomiBar = _app.clock_view._bars["w"]
	_ok(bar.visible, "Byoyomi 模式下段数条应可见")
	_eq(bar.total, 3, "段数条的总段数")
	_eq(bar.left, 3, "主时间阶段一段都还没用")

	# 换到 Fischer：条必须隐藏（这个指示器只对读秒有意义）
	_app.cfg["mode"] = "fischer"
	_app.new_game()
	_ok(not _app.clock_view._bars["w"].visible, "非读秒模式应隐藏段数条")

	# 回到读秒，跑过主时间并跨过 1 段
	_app.cfg["mode"] = "byoyomi"
	_app.cfg["baseMin"] = 1
	_app.cfg["incSec"] = 20
	_app.cfg["periods"] = 3
	_app.new_game()
	_app.press("b")
	_app.state["turnStart"] = Time.get_ticks_msec() - 86000
	_app._tick()
	bar = _app.clock_view._bars["w"]
	_ok(bar.visible, "读秒阶段段数条仍可见")
	_eq(bar.left, 2, "跨过 1 段后应剩 2 段")
	# 正在倒计时的那一段按窗口剩余比例显示：还剩 14/20 秒 → 0.7
	_ok(absf(bar.active_left - 0.7) < 0.02, "倒计时段的比例应为 0.7（14/20 秒），实际 %f" % bar.active_left)
	_eq(bar.total, 3, "总段数不随消耗变化")
	# 颜色：还剩的段用绿色（ok），已用掉的段用红色（danger）
	_eq(bar.fill_color, _app.palette["ok"], "剩下的段应是绿色（ok）")
	_eq(bar.empty_color, _app.palette["danger"], "已用掉的段应是红色（danger）")


## 最后 10 秒的「滴」：主时间（四种模式）与读秒窗口都要响；同一秒只响一次；
## Fischer 加秒后再次进入最后 10 秒要能重新响（key 里带第几手）。
func _check_last_ten_tick() -> void:
	# 主时间最后 10 秒：Sudden death 也要响（以前只有读秒阶段才响）
	_app.cfg["mode"] = "sudden"
	_app.cfg["baseMin"] = 1
	_app.new_game()
	_app.press("b")                    # 开表：白方的钟开始走
	var info := {"ms": 9500, "phase": "main", "periodsLeft": null, "windowIndex": 0}
	_ok(_app.tick_key_for("w", info) != "", "主时间剩 9.5 秒应滴")
	# 同一秒内反复调用只响一次
	var k1: String = _app.tick_key_for("w", info)
	_eq(_app.tick_key_for("w", {"ms": 9100, "phase": "main", "periodsLeft": null, "windowIndex": 0}),
		k1, "同一秒（9.5s → 9.1s 都取整到 10）只响一次")
	# 下一秒换 key
	_ok(_app.tick_key_for("w", {"ms": 8500, "phase": "main", "periodsLeft": null, "windowIndex": 0}) != k1,
		"下一整秒要换 key（再滴一声）")
	# 超过 10 秒不响
	_eq(_app.tick_key_for("w", {"ms": 12000, "phase": "main", "periodsLeft": null, "windowIndex": 0}),
		"", "还剩 12 秒不响")
	# 读秒窗口照样响（原有行为）
	_ok(_app.tick_key_for("w", {"ms": 4000, "phase": "byoyomi", "periodsLeft": 2, "windowIndex": 0}) != "",
		"读秒窗口最后 10 秒仍要滴")
	# 暂停时不响
	_app.toggle_pause()
	_eq(_app.tick_key_for("w", {"ms": 4000, "phase": "main", "periodsLeft": null, "windowIndex": 0}),
		"", "暂停时不响")
	_app.toggle_pause()
	# Fischer：加秒后时间回到 10 秒以上，下一手再次进入最后 10 秒要重新滴
	_app.cfg["mode"] = "fischer"
	_app.cfg["baseMin"] = 1
	_app.cfg["incSec"] = 3
	_app.new_game()
	_app.press("b")
	var before: String = _app.tick_key_for("w", {"ms": 9500, "phase": "main", "periodsLeft": null, "windowIndex": 0})
	_app.state["turnStart"] = Time.get_ticks_msec() - 500          # 走了 0.5 秒
	_app.press("w")                                                # 加秒 3 秒 → 回到 10 秒以上
	_app.press("b")                                                # 再交回白方
	var after: String = _app.tick_key_for("w", {"ms": 9500, "phase": "main", "periodsLeft": null, "windowIndex": 0})
	_ok(after != "" and after != before, "加秒后再次进入最后 10 秒要能重新滴")
	_app.cfg["mode"] = "byoyomi"
	_app.cfg["baseMin"] = 10
	_app.cfg["incSec"] = 20

## 读秒模式下「主时间」与「读秒秒数」各可以是 0，但不能同时是 0
## （0 主时间 = 纯读秒；0 读秒 = 只有主时间；两个都 0 → 主时间回落 1 分钟）。
func _check_zero_times() -> void:
	_app.cfg["mode"] = "byoyomi"
	_app.cfg["baseMin"] = 5
	_app.cfg["incSec"] = 20
	_app.cfg["periods"] = 3
	_app.new_game()

	# 只把主时间打 0：读秒还在，合法
	_app.cfg["baseMin"] = 0
	var clean := ClockSettings.normalize(_app.cfg)
	_eq(int(clean["baseMin"]), 0, "0 主时间 + 有读秒 = 纯读秒，应放行")
	_eq(int(clean["incSec"]), 20, "读秒秒数不受影响")
	# 引擎也接受：钟上直接显示读秒那一格
	var st := ClockEngine.new_game(ClockSettings.engine_config(clean))
	_eq(ClockEngine.readout(st, "w", 1000)["phase"], "byoyomi", "主时间 0 时开局就在读秒阶段")

	# 只把读秒打 0：主时间还在，合法
	_app.cfg["baseMin"] = 5
	_app.cfg["incSec"] = 0
	clean = ClockSettings.normalize(_app.cfg)
	_eq(int(clean["incSec"]), 0, "0 读秒 + 有主时间 = 只有主时间，应放行")
	_eq(int(clean["baseMin"]), 5, "主时间不受影响")

	# 两个都 0：没有意义，主时间回落 1 分钟
	_app.cfg["baseMin"] = 0
	_app.cfg["incSec"] = 0
	clean = ClockSettings.normalize(_app.cfg)
	_eq(int(clean["baseMin"]), 1, "两个都 0 时主时间回落 1 分钟")
	# 非读秒模式的主时间下限仍是 1 分钟
	_app.cfg["mode"] = "fischer"
	_app.cfg["baseMin"] = 0
	clean = ClockSettings.normalize(_app.cfg)
	_eq(int(clean["baseMin"]), 1, "非读秒模式主时间至少 1 分钟")
	_app.cfg["mode"] = "byoyomi"
	_app.cfg["baseMin"] = 10
	_app.cfg["incSec"] = 20

## 「怎么用」页：从设置页进入、返回按钮 / 安卓返回键都能退回
func _check_help_page() -> void:
	_app.setup_view._help_button.pressed.emit()
	_ok(_app.help_view.visible, "点「怎么用」应进入说明页")
	_ok(not _app.setup_view.visible, "设置页应隐藏")
	_ok(_app.help_view._facing.text.length() > 40, "说明页有正文（面对面那一段）")
	_ok(_app.help_view._byoyomi.text.length() > 40, "说明页有正文（读秒那一段）")
	_eq(_app.help_view._title.text, _app.t("setup.how.heading"), "标题与入口用同一个词条")

	_app.help_view._back_btn.pressed.emit()
	_ok(_app.setup_view.visible, "点「返回」回到设置页")
	_ok(not _app.help_view.visible, "说明页已隐藏")

	_app.setup_view._help_button.pressed.emit()
	_app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_ok(_app.setup_view.visible, "安卓返回键从说明页退回设置页")


## 前面的用例直接调方法，这里改为**发射控件自己的信号**，
## 相当于真的点了一下 —— 用来确认「节点 → 信号 → 总控」这一层没有接错。
func _check_buttons() -> void:
	var seg: Button = _app.setup_view._mode_buttons["fischer"]
	seg.pressed.emit()
	_eq(_app.cfg["mode"], "fischer", "模式按钮生效")

	# 时间预设：下拉框里选「10+5」
	var dd: OptionButton = _app.setup_view._preset_select
	var idx: int = _app.setup_view._preset_ids.find("10+5")
	_ok(idx >= 0, "棋类模式的下拉框里应有 10+5 这一档")
	if idx >= 0:
		dd.select(idx)
		dd.item_selected.emit(idx)
		_eq(int(_app.cfg["baseMin"]), 10, "下拉框选预设：基础时间")
		_eq(int(_app.cfg["incSec"]), 5, "下拉框选预设：加秒")

	# 手改数字 → 下拉框落到「自定义」
	# （程序里赋 .text 不会发 text_changed，手动发一次，等价于用户真的敲键盘）
	_app.setup_view._base_edit.text = "17"
	_app.setup_view._base_edit.text_changed.emit("17")
	_eq(_app.setup_view._preset_ids[dd.selected], "", "手改数字后下拉框应落到「自定义」")
	_ok(_app.setup_view._preset_select.get_item_text(dd.selected) == _app.t("preset.custom"),
		"「自定义」那一档的文字来自 i18n")

	_app.setup_view._lang_zh.pressed.emit()
	_eq(_app.lang, "zh", "语言按钮切到中文")
	_ok(_app.setup_view._preset_select.get_item_text(0).find("·") > 0,
		"切语言后下拉框条目仍在")
	_app.setup_view._lang_en.pressed.emit()
	_eq(_app.lang, "en", "语言按钮切回英文")

	_app.setup_view._start_button.pressed.emit()
	_ok(_app.clock_view.visible, "「开始对局」按钮生效")

	var pane_b: Button = _app.clock_view._panes_map["b"]
	pane_b.button_down.emit()
	_ok(bool(_app.state["started"]), "拍黑方面板 = 开表")
	_eq(_app.state["active"], "w", "白方开始走")

	var pane_w: Button = _app.clock_view._panes_map["w"]
	pane_w.button_down.emit()
	_eq(int(_app.state["moves"]["w"]), 1, "拍白方面板 = 走一手")

	_app.clock_view._pause_btn.pressed.emit()
	_ok(bool(_app.state["paused"]), "暂停按钮生效")
	_app.clock_view._pause_btn.pressed.emit()
	_ok(not bool(_app.state["paused"]), "再按一次继续")

	var facing := bool(_app.cfg["facing"])
	_app.clock_view._rotate_btn.pressed.emit()
	_eq(bool(_app.cfg["facing"]), not facing, "180° 按钮切换对坐模式")

	var swapped := bool(_app.cfg["swapped"])
	_app.clock_view._swap_btn.pressed.emit()
	_eq(bool(_app.cfg["swapped"]), not swapped, "⇵ 按钮切换两侧")

	var sound := bool(_app.cfg["sound"])
	_app.clock_view._sound_btn.pressed.emit()
	_eq(bool(_app.cfg["sound"]), not sound, "声音按钮切换开关")


func _check_persistence() -> void:
	_app.cfg["mode"] = "fischer"
	_app.cfg["baseMin"] = 25
	_app.cfg["theme"] = "medium"
	_app.save_settings()

	_ok(FileAccess.file_exists(ClockSettings.file_path), "存档文件应已写出：" + ClockSettings.file_path)
	var loaded := ClockSettings.load_from()
	_eq(loaded["mode"], "fischer", "读回来的模式")
	_eq(int(loaded["baseMin"]), 25, "读回来的基础时间")
	_eq(loaded["theme"], "medium", "读回来的主题")
	ok_has(loaded, "lang", _app.lang)


# ------------------------------------------------------------------ 脚手架

func _case(label: String, fn: Callable) -> void:
	var failed_before := _failed
	fn.call()
	print(("  PASS  " if _failed == failed_before else "  FAIL  ") + label)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(msg)


func _eq(actual, expected, msg := "") -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s —— 期望 %s，实际 %s" % [msg, str(expected), str(actual)])


func ok_has(dict: Dictionary, key: String, expected) -> void:
	if dict.has(key) and dict[key] == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("存档字段 %s —— 期望 %s，实际 %s" % [key, str(expected), str(dict.get(key))])


## 安卓返回键：这条路径在桌面上永远不会被触发（所以只能这样直接发通知来测）。
## 在设置页上它才会真的退出程序，那一步不在这里测 —— 测了测试进程就没了。
func _check_back_button() -> void:
	_app.new_game()
	_app.press("b")
	_ok(bool(_app.state["started"]), "先开一局")

	_app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_ok(_app.overlay.visible, "对局中按返回 → 先弹确认框")
	_ok(not _app.state.is_empty(), "对局还在，没有直接退出")
	_eq(_app.state["moves"]["w"], 0, "对局状态没有被改动")

	_app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_ok(not _app.overlay.visible, "再按一次 → 收起确认框")
	_ok(_app.clock_view.visible, "仍停在棋钟页")

	_app._leave_game()
	_ok(_app.setup_view.visible, "回到设置页")
