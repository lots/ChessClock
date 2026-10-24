extends Control
## main.gd — 总控（网页版 app.js 的顶层：状态 + 界面切换 + 计时循环 + 声音 + 存档）
##
## 计时逻辑在 logic/engine.gd，文案在 logic/i18n.gd，配色在 logic/theme.gd，
## 这里只负责把它们接起来：
##   设置页 ↔ 棋钟页 ↔ 结算层，输入（触摸/鼠标/键盘），声音，屏幕常亮，全屏，存档。
##
## 时间来源：Time.get_ticks_msec()（单调递增，系统休眠时继续走）。
## 与网页版一样**不做 dt 累加**，每帧都用绝对时刻重新推算，所以掉帧、
## 窗口被挂起、引擎被暂停都不会让时间算错。

var cfg := {}
var lang := "en"
var palette := {}
var fonts := {}
var state := {}

var setup_view: SetupView
var help_view: HelpView
var clock_view: ClockView
var overlay: ResultOverlay

var _toast: PanelContainer
var _toast_label: Label
var _toast_until := 0

var _snd := {}
var _alarm_left := 0
var _alarm_next := 0
var _last_tick_key := ""

var _args := {}
var _shot := ""
var _shot_out := "user://shot.png"
var _no_save := false
var _debug := false


func t(key: String, vars: Dictionary = {}) -> String:
	return ClockI18n.t(lang, key, vars)


static func now_ms() -> int:
	return Time.get_ticks_msec()


func _ready() -> void:
	_update_content_scale()
	var win := get_window()
	if win != null:
		win.size_changed.connect(_update_content_scale)
	_boot()
	if _shot != "":
		await _run_shot()


## 设计尺寸按「手机 dp」算：竖屏 390×844、横屏 844×390。
## 每换一次屏幕方向就把虚拟画布换成对应那一套，这样 1 个设计单位在两种方向下
## 都约等于 1 dp —— 否则 Godot 的 canvas_items + expand 会把横屏的界面整体缩小
## （竖屏的 844 高当成基准，横屏只剩 390 高，字号会缩到一半以下）。
func _update_content_scale() -> void:
	var win := get_window()
	if win == null:
		return
	var landscape := win.size.x > win.size.y
	var want := Vector2i(844, 390) if landscape else Vector2i(390, 844)
	if win.content_scale_size != want:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		win.content_scale_size = want


# ------------------------------------------------------------------ 启动

func _boot() -> void:
	_parse_args()

	cfg = ClockSettings.defaults()
	var fresh := _args.has("shot") or _args.has("reset-settings")
	if not fresh:
		cfg = ClockSettings.load_from()
	if _args.has("lang"):
		var forced := ClockI18n.normalize(_args["lang"])
		if forced != "":
			cfg["lang"] = forced
	if _args.has("theme"):
		cfg["theme"] = ClockTheme.normalize(_args["theme"])
	cfg = ClockSettings.normalize(cfg)
	_no_save = _args.has("shot")

	lang = ClockI18n.normalize(cfg["lang"])
	if lang == "":
		lang = ClockI18n.detect()
	cfg["lang"] = lang

	_build_fonts()
	palette = ClockTheme.palette(cfg["theme"])
	theme = ClockTheme.build(cfg["theme"], fonts)

	_build_views()
	_build_sound()
	_build_toast()

	_apply_language(lang, false)
	setup_view.sync_from_cfg()
	show_screen("setup")

	if _args.has("autostart") or _shot in ["clock", "clock-swapped", "clock-paused", "clock-byoyomi", "overlay", "confirm"]:
		if _args.has("demo-quick") or _shot == "overlay":
			_demo_quick()
		if _args.has("demo-swapped") or _shot == "clock-swapped":
			cfg["swapped"] = true
		new_game()
		_demo_moves()
		if _shot == "clock-paused":
			toggle_pause()

	_apply_window_title()
	if _debug:
		print("DBG boot lang=%s theme=%s mode=%s base=%d inc=%d periods=%d facing=%s swapped=%s sound=%s"
			% [lang, cfg["theme"], cfg["mode"], cfg["baseMin"], cfg["incSec"], cfg["periods"],
			cfg["facing"], cfg["swapped"], cfg["sound"]])
		# 版面级的自检：证明「跑起来的这套资源」确实带预设下拉框与「怎么用」入口
		# （导出成 APK/PCK 之后也能用 --debug-input 验一次，字节码里搜不到字符串）
		var sel_text := ""
		if setup_view._preset_select != null and setup_view._preset_select.selected >= 0:
			sel_text = setup_view._preset_select.get_item_text(setup_view._preset_select.selected)
		print("DBG ui preset_select=%s help_link=%s custom_label=%s byo_bar=%s preset_text=[%s]" % [
			setup_view._preset_select != null,
			setup_view._help_button != null,
			t("preset.custom"),
			clock_view._bars["w"] is ByoyomiBar,
			sel_text,
		])


func _build_fonts() -> void:
	var ui := SystemFont.new()
	ui.font_names = PackedStringArray([
		"Segoe UI", "Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
		"Noto Sans CJK SC", "Noto Sans SC", "Source Han Sans SC", "Hiragino Sans GB",
		"DejaVu Sans", "sans-serif",
	])
	ui.allow_system_fallback = true

	var bold := FontVariation.new()
	bold.base_font = ui
	bold.variation_embolden = 0.55

	var mono := SystemFont.new()
	mono.font_names = PackedStringArray([
		"Consolas", "SF Mono", "Menlo", "DejaVu Sans Mono", "Liberation Mono",
		"Courier New", "monospace",
	])
	mono.allow_system_fallback = true

	var mono_bold := FontVariation.new()
	mono_bold.base_font = mono
	mono_bold.variation_embolden = 0.45

	fonts = {"ui": ui, "bold": bold, "mono": mono, "mono_bold": mono_bold}


func _build_views() -> void:
	setup_view = SetupView.new()
	setup_view.name = "SetupScreen"
	setup_view.app = self
	add_child(setup_view)
	setup_view.start_requested.connect(new_game)
	setup_view.lang_requested.connect(func(next: String) -> void: _apply_language(next))
	setup_view.theme_requested.connect(_set_theme)
	setup_view.help_requested.connect(func() -> void: show_screen("help"))
	setup_view.settings_changed.connect(_on_settings_changed)

	help_view = HelpView.new()
	help_view.name = "HelpScreen"
	help_view.app = self
	help_view.visible = false
	add_child(help_view)
	help_view.back_requested.connect(func() -> void: show_screen("setup"))

	clock_view = ClockView.new()
	clock_view.name = "ClockScreen"
	clock_view.app = self
	clock_view.visible = false
	add_child(clock_view)
	clock_view.side_pressed.connect(press)
	clock_view.back_requested.connect(back_to_setup)
	clock_view.toggle_pause_requested.connect(toggle_pause)
	clock_view.sound_toggle_requested.connect(_toggle_sound)
	clock_view.facing_toggle_requested.connect(_toggle_facing)
	clock_view.swap_toggle_requested.connect(_toggle_swap)
	clock_view.fullscreen_requested.connect(_toggle_fullscreen)

	overlay = ResultOverlay.new()
	overlay.name = "Overlay"
	overlay.app = self
	add_child(overlay)
	overlay.rematch_requested.connect(new_game)
	overlay.back_requested.connect(_leave_game)
	overlay.confirmed.connect(_leave_game)


func _build_sound() -> void:
	for key in ["click", "tick", "alarm"]:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://assets/sounds/%s.wav" % key)
		player.volume_db = -3.0
		add_child(player)
		_snd[key] = player


func _build_toast() -> void:
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.anchor_left = 0.0
	wrap.anchor_right = 1.0
	wrap.anchor_top = 1.0
	wrap.anchor_bottom = 1.0
	wrap.offset_left = 20.0
	wrap.offset_right = -20.0
	wrap.offset_top = -86.0
	wrap.offset_bottom = -26.0
	add_child(wrap)

	_toast = UiKit.panel("ToastPanel")
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_toast)

	_toast_label = UiKit.label("", "")
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_child(_toast_label)


func _parse_args() -> void:
	var all: Array = []
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	for raw in all:
		var arg := str(raw)
		if not arg.begins_with("--"):
			continue
		arg = arg.substr(2)
		var eq := arg.find("=")
		if eq >= 0:
			_args[arg.substr(0, eq)] = arg.substr(eq + 1)
		else:
			_args[arg] = ""
	_shot = str(_args.get("shot", ""))
	_shot_out = str(_args.get("shot-out", "user://shot.png"))
	_debug = _args.has("debug-input")


# ------------------------------------------------------------------ 语言 / 主题

func _apply_language(next: String, save := true) -> void:
	var code := ClockI18n.normalize(next)
	if code == "":
		code = "en"
	lang = code
	cfg["lang"] = code
	setup_view.refresh_language()
	help_view.refresh_language()
	clock_view.refresh_language()
	_apply_window_title()
	if save:
		save_settings()
	if not state.is_empty():
		clock_view.render(state, now_ms())


func _apply_window_title() -> void:
	var win := get_window()
	if win != null:
		win.title = t("app.title")


func _set_theme(name: String) -> void:
	cfg["theme"] = ClockTheme.normalize(name)
	palette = ClockTheme.palette(cfg["theme"])
	theme = ClockTheme.build(cfg["theme"], fonts)
	setup_view.apply_palette()
	help_view.apply_palette()
	clock_view.apply_palette()
	overlay.apply_palette()
	if not state.is_empty():
		clock_view.render(state, now_ms())
	save_settings()


func _on_settings_changed() -> void:
	save_settings()
	if not state.is_empty():
		clock_view.apply_facing()
		clock_view.apply_swap()


func save_settings() -> void:
	if _no_save:
		return
	ClockSettings.save_to(cfg)


# ------------------------------------------------------------------ 界面切换

func show_screen(name: String) -> void:
	setup_view.visible = name == "setup"
	help_view.visible = name == "help"
	clock_view.visible = name == "clock"
	if name == "clock":
		clock_view.refit()


## 开始新的一局（「开始对局」与「再来一局」都走这里）
func new_game() -> void:
	cfg = ClockSettings.normalize(cfg)
	_stop_alarm()
	overlay.hide_overlay()

	state = ClockEngine.new_game(ClockSettings.engine_config(cfg))
	_last_tick_key = ""
	clock_view.apply_facing()
	clock_view.apply_swap()
	clock_view.set_badge_visible(false)

	show_screen("clock")
	clock_view.render(state, now_ms())
	_request_wake()
	save_settings()


func back_to_setup() -> void:
	if not state.is_empty() and bool(state["started"]) and not bool(state["finished"]):
		overlay.show_confirm(t("confirm.leave"))
		return
	_leave_game()


func _leave_game() -> void:
	_stop_alarm()
	overlay.hide_overlay()
	_release_wake()
	state = {}
	show_screen("setup")
	setup_view.sync_from_cfg()
	save_settings()


# ------------------------------------------------------------------ 拍钟 / 暂停 / 超时

## 按钟：整块面板就是那个跷跷板。
## 未开表时拍某一侧 = 开表，**由对侧开始计时**（拍黑方 → 白方的钟开始走），这一下不算步数。
## 开表之后：拍自己那一侧 = 走完一手；拍非走棋方不产生任何效果（引擎里就是这样判的）。
func press(side: String) -> void:
	if state.is_empty() or bool(state["finished"]):
		return
	var now := now_ms()

	if not bool(state["started"]):
		var res0 := ClockEngine.start(state, now, ClockEngine.other(side))
		if str(res0["type"]) == "start":
			_play("click")
			_request_wake()
		clock_view.render(state, now)
		return

	var res := ClockEngine.press(state, side, now)
	var kind := str(res["type"])
	if kind == "move" or kind == "start":
		_play("click")
		_request_wake()
	elif kind == "flag":
		_tick()
		return
	clock_view.render(state, now)


func toggle_pause() -> void:
	if state.is_empty() or bool(state["finished"]) or not bool(state["started"]):
		return
	if bool(state["paused"]):
		ClockEngine.resume(state, now_ms())
		_request_wake()
	else:
		ClockEngine.pause(state, now_ms())
	clock_view.render(state, now_ms())


func _tick() -> void:
	if state.is_empty():
		return
	var now := now_ms()
	var flagged := ClockEngine.check_flag(state, now)
	clock_view.render(state, now)
	if flagged != "":
		_on_flag(flagged)


func _on_flag(side: String) -> void:
	_start_alarm()
	_release_wake()
	var now := now_ms()
	clock_view.render(state, now)
	var moves: int = int(state["moves"]["w"]) + int(state["moves"]["b"])
	overlay.show_result(side, moves, ClockSettings.summary(lang, cfg))
	if _debug:
		print("DBG clock flag side=%s moves=%d" % [side, moves])


# ------------------------------------------------------------------ 计时循环

func _process(_delta: float) -> void:
	var now := now_ms()
	_process_alarm(now)

	if _toast_until > 0 and now >= _toast_until:
		_toast.visible = false
		_toast_until = 0

	if state.is_empty() or not clock_view.visible:
		return

	var flagged := ClockEngine.check_flag(state, now)
	clock_view.render(state, now)
	if flagged != "":
		_on_flag(flagged)
		return

	for side in ["w", "b"]:
		if bool(state["running"]) and str(state["active"]) == side:
			_maybe_tick(side, ClockEngine.readout(state, side, now))


## 最后 10 秒每秒提示一次（实体读秒钟就是这样滴答的）。
##
## 不只是读秒阶段：**主时间（base time）的最后 10 秒同样要滴**，四种模式都适用 ——
## 那正是「这块表马上要没时间了」的听觉提示，读秒只是其中一种倒计时。
##
## key 里带上「第几手」（双方步数之和）：Fischer 加秒之后剩余时间可能又回到 10 秒以上，
## 下一手再次进入最后 10 秒时必须能重新滴满；读秒窗口用 windowIndex 区分。
## 单独拆成 tick_key_for() 是为了能在无头测试里直接验判定（不真的播音）。
const TICK_LAST_MS := 10000


## 这一帧该不该「滴」：该响时返回去重用的 key，不该响返回空串
func tick_key_for(side: String, info: Dictionary) -> String:
	if state.is_empty() or not bool(state["running"]) or bool(state["paused"]):
		return ""
	var ms := int(info["ms"])
	if ms <= 0 or ms > TICK_LAST_MS:
		return ""
	var sec := int(ceil(ms / 1000.0))
	if sec < 1 or sec > 10:
		return ""
	var turn: int = int(state["moves"]["w"]) + int(state["moves"]["b"])
	return "%s:%d:%s:%d:%d" % [side, turn, str(info["phase"]), int(info["windowIndex"]), sec]


func _maybe_tick(side: String, info: Dictionary) -> void:
	var key := tick_key_for(side, info)
	if key == "" or key == _last_tick_key:
		return
	_last_tick_key = key
	_play("tick")


# ------------------------------------------------------------------ 声音

func _play(key: String) -> void:
	if not bool(cfg.get("sound", true)):
		return
	var player: AudioStreamPlayer = _snd.get(key)
	if player != null:
		player.play()


func _start_alarm() -> void:
	_stop_alarm()
	_play("alarm")
	_alarm_left = 5
	_alarm_next = now_ms() + 240


func _stop_alarm() -> void:
	_alarm_left = 0
	var player: AudioStreamPlayer = _snd.get("alarm")
	if player != null:
		player.stop()


func _process_alarm(now: int) -> void:
	if _alarm_left > 0 and now >= _alarm_next:
		_play("alarm")
		_alarm_left -= 1
		_alarm_next = now + 240


# ------------------------------------------------------------------ 开关

func _toggle_sound() -> void:
	cfg["sound"] = not bool(cfg["sound"])
	save_settings()
	clock_view.update_sound_icon()
	if bool(cfg["sound"]):
		_play("click")


func _toggle_facing() -> void:
	cfg["facing"] = not bool(cfg["facing"])
	save_settings()
	clock_view.apply_facing()
	setup_view.sync_from_cfg()


func _toggle_swap() -> void:
	cfg["swapped"] = not bool(cfg["swapped"])
	save_settings()
	clock_view.apply_swap()


func _toggle_fullscreen() -> void:
	# 网页版在 iOS Safari 上没有全屏，会弹一条提示；原生端对应的「做不到」是没有窗口系统
	if DisplayServer.get_name() == "headless":
		_toast_message(t("toast.fullscreenUnsupported"))
		return
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _request_wake() -> void:
	if not bool(cfg.get("keepAwake", true)):
		return
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.screen_set_keep_on(true)


func _release_wake() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.screen_set_keep_on(false)


func _toast_message(msg: String) -> void:
	_toast_label.text = msg
	_toast.visible = true
	_toast_until = now_ms() + 3200


# ------------------------------------------------------------------ 系统返回键（Android）

## 安卓的硬件返回键 / 返回手势会发这个通知。默认行为是直接退出程序 ——
## 对棋钟来说那是灾难：一局正在下，误触一下就没了。
## 所以按「能退一步就退一步」处理：结算层 → 说明页 → 棋钟页（对局中会弹确认框）→ 最后才退出。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()


func _handle_back_request() -> void:
	if overlay.visible:
		overlay.hide_overlay()
		return
	if help_view.visible:
		show_screen("setup")
		return
	if clock_view.visible:
		back_to_setup()
		return
	_release_wake()
	get_tree().quit()


# ------------------------------------------------------------------ 键盘

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	if overlay.visible:
		if key.keycode == KEY_ESCAPE:
			overlay.hide_overlay()
		return

	# 说明页：ESC / 退格 都退回设置页
	if help_view.visible:
		if key.keycode == KEY_ESCAPE or key.keycode == KEY_BACKSPACE:
			show_screen("setup")
		return

	if not clock_view.visible:
		return

	match key.keycode:
		KEY_A, KEY_LEFT:
			press("w")
		KEY_L, KEY_RIGHT:
			press("b")
		KEY_SPACE, KEY_ENTER:
			toggle_pause()
		KEY_F:
			_toggle_fullscreen()
		KEY_ESCAPE:
			back_to_setup()
		_:
			pass


# ------------------------------------------------------------------ 截图 / 演示模式

func _demo_quick() -> void:
	cfg["mode"] = ClockEngine.MODES.SUDDEN
	cfg["baseMin"] = 1
	cfg["incSec"] = 0
	cfg["presetId"] = null


## 截图用：走两步并把时钟往回拨一点，让画面看起来像一局进行中的棋
func _demo_moves() -> void:
	if state.is_empty() or _shot == "" or _shot == "overlay":
		return
	press("b")                                    # 开表：白方的钟开始走
	state["turnStart"] = int(state["turnStart"]) - 27500
	press("w")                                    # 白方走一手 → 黑方开始走
	state["turnStart"] = int(state["turnStart"]) - 4000
	clock_view.render(state, now_ms())


func _run_shot() -> void:
	await get_tree().process_frame
	_setup_shot_scene()

	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_out)
	print("SHOT %s -> %s (err=%d, %dx%d)" % [_shot, _shot_out, err, image.get_width(), image.get_height()])
	if _debug:
		print("DBG layout " + clock_view.debug_sizes())
	if err != OK:
		push_error("截图保存失败：" + _shot_out)
	get_tree().quit(0 if err == OK else 1)


func _setup_shot_scene() -> void:
	match _shot:
		"menu", "setup":
			show_screen("setup")
		"menu-bottom":
			show_screen("setup")
			setup_view.scroll_to_bottom()
		"help":
			show_screen("help")
		"confirm":
			overlay.show_confirm(t("confirm.leave"))
		"clock-byoyomi":
			# 读秒阶段：1 分钟主时间用尽 + 读秒跨过 1 段，用来核对段数条（剩 2/3）
			cfg["mode"] = ClockEngine.MODES.BYOYOMI
			cfg["baseMin"] = 1
			cfg["incSec"] = 20
			cfg["periods"] = 3
			new_game()
			press("b")
			state["turnStart"] = now_ms() - 86000
			_tick()
		"overlay":
			press("b")                                  # 开表：白方的钟开始走
			state["turnStart"] = now_ms() - 61000       # 假装已经过了一分钟
			_tick()
		_:
			pass
