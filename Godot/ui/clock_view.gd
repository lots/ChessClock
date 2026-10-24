class_name ClockView
extends Control
## clock_view.gd — 棋钟页（网页版 index.html 的 #screen-clock + app.js 的渲染部分）
##
## 布局与网页版一致：
##   竖屏：上黑（对面选手）/ 中间操作条 / 下白
##   横屏：左黑 / 中间操作条 / 右白
## 「交换两侧」只调换三块在容器里的顺序（容器会自己重排）；
## 「对坐模式」把**视觉上排在最前的那一块**的内容整体旋转 180°（横屏不转）。

signal side_pressed(side: String)
signal back_requested
signal toggle_pause_requested
signal sound_toggle_requested
signal facing_toggle_requested
signal swap_toggle_requested
signal fullscreen_requested

var app: Node

var _bg: ColorRect
var _panes: BoxContainer
var _strip: PanelContainer
var _strip_box: BoxContainer
var _strip_items: Array[Control] = []
var _panes_items: Array[Control] = []
var _panes_map := {}

var _inners := {}
var _rings := {}
var _times := {}
var _chips := {}
var _chip_panels := {}
var _feet := {}
var _bars := {}

## 读秒段数条的高度（原本 8，按需求加厚 10%）
const BAR_H := 8.8
var _tags := {}

var _pause_btn: Button
var _sound_btn: Button
var _rotate_btn: Button
var _swap_btn: Button
var _full_btn: Button
var _setup_btn: Button
var _badge: PanelContainer
var _badge_label: Label

var _landscape := false
var _last_text := {"w": "", "b": ""}
var _last_time_color := {"w": Color(0, 0, 0, 0), "b": Color(0, 0, 0, 0)}
var _last_foot_color := {"w": Color(0, 0, 0, 0), "b": Color(0, 0, 0, 0)}
var _last_chip := {"w": "", "b": ""}
var _last_chip_style := {"w": "", "b": ""}
var _last_chip_color := {"w": Color(0, 0, 0, 0), "b": Color(0, 0, 0, 0)}
var _last_foot := {"w": "", "b": ""}
var _strip_state := ""

const CRITICAL := ClockEngine.CRITICAL_TIME_MS
const LOW := ClockEngine.LOW_TIME_MS


func t(key: String, vars: Dictionary = {}) -> String:
	return app.t(key, vars)


func _ready() -> void:
	build()
	_set_orientation(size.x > size.y)
	resized.connect(_on_resized)


# ------------------------------------------------------------------ 搭界面

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_strip_items.clear()
	_panes_items.clear()

	_bg = ColorRect.new()
	_bg.color = app.palette["clock_bg"]
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.fill(_bg))

	_build_panes()
	_build_strip()
	_build_badge()

	_panes_items = [_panes_map["b"], _strip, _panes_map["w"]]
	_pause_btn.visible = false

	_apply_strip_style()
	_apply_chip_style("w")
	_apply_chip_style("b")
	_apply_bar_colors()
	update_sound_icon()


func _build_panes() -> void:
	for side in ["b", "w"]:
		var pane := Button.new()
		pane.theme_type_variation = "PaneB" if side == "b" else "PaneW"
		pane.focus_mode = Control.FOCUS_NONE
		pane.clip_contents = true
		pane.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pane.button_down.connect(func() -> void: side_pressed.emit(side))
		_panes_map[side] = pane

		var inner := Control.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pane.add_child(inner)
		_inners[side] = inner

		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.visible = false
		ring.add_theme_stylebox_override("panel", _ring_box())
		pane.add_child(ring)
		_rings[side] = ring

		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(center)

		var column := UiKit.vbox(6)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(column)

		var head := UiKit.hbox(8)
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(head)

		var tag := UiKit.label("", "SideTag")
		tag.modulate.a = 0.72
		tag.add_theme_color_override("font_color", app.palette[side + "_ink"])
		head.add_child(tag)
		_tags[side] = tag

		var chip_panel := PanelContainer.new()
		chip_panel.custom_minimum_size.y = 20
		chip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(chip_panel)
		_chip_panels[side] = chip_panel

		var chip := UiKit.label("", "ChipLabel")
		chip.add_theme_font_size_override("font_size", 11)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_panel.add_child(chip)
		_chips[side] = chip

		var time_label := Label.new()
		time_label.theme_type_variation = "TimeLabel"
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(time_label)
		_times[side] = time_label

		# 读秒段数条：夹在「数字」与「MOVE 那一行」之间（作为 column 的子节点自然排版，
		# 隐藏时 VBox 不占位；在 Inner 里 → 对坐模式下跟着内容一起旋转）
		var bar := ByoyomiBar.new()
		bar.visible = false
		bar.custom_minimum_size = Vector2(240.0, BAR_H)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(bar)
		_bars[side] = bar

		var foot := UiKit.label("", "FootLabel")
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		foot.modulate.a = 0.62
		column.add_child(foot)
		_feet[side] = foot


## 段数条的两种颜色：绿 = 还剩几段，红 = 已经用掉。
## 用的是主题里的 ok / danger，和网页版 .byo-bar 的 --ok / --danger 是同一套色值。
func _apply_bar_colors() -> void:
	var fill: Color = app.palette["ok"]
	var used: Color = app.palette["danger"]
	for side in ["w", "b"]:
		_bars[side].set_colors(fill, used)


func _ring_box() -> StyleBoxFlat:
	var p: Dictionary = app.palette
	var sb := ClockTheme.box(Color(0, 0, 0, 0), p["accent"], 12, 3, 0, 0)
	sb.draw_center = false
	return sb


func _build_strip() -> void:
	_strip = UiKit.panel()
	add_child(_strip)

	_pause_btn = UiKit.button("", "IconButton")
	_pause_btn.custom_minimum_size = Vector2(42, 38)
	_pause_btn.pressed.connect(func() -> void: toggle_pause_requested.emit())

	_sound_btn = UiKit.icon_button(load("res://assets/icons/sound_on.png"))
	_sound_btn.pressed.connect(func() -> void: sound_toggle_requested.emit())

	_rotate_btn = UiKit.button("180°", "IconButton")
	_rotate_btn.custom_minimum_size = Vector2(46, 38)
	_rotate_btn.add_theme_font_size_override("font_size", 12)
	_rotate_btn.pressed.connect(func() -> void: facing_toggle_requested.emit())

	_swap_btn = UiKit.icon_button(load("res://assets/icons/swap.png"))
	_swap_btn.pressed.connect(func() -> void: swap_toggle_requested.emit())

	_full_btn = UiKit.icon_button(load("res://assets/icons/fullscreen.png"))
	_full_btn.pressed.connect(func() -> void: fullscreen_requested.emit())

	_setup_btn = UiKit.icon_button(load("res://assets/icons/settings.png"))
	_setup_btn.pressed.connect(func() -> void: back_requested.emit())

	var logo := TextureRect.new()
	logo.texture = load("res://assets/logo-strip.png")
	logo.custom_minimum_size = Vector2(44, 44)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.modulate.a = 0.92
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_strip_items = [logo, _pause_btn, _sound_btn, _rotate_btn, _swap_btn, _full_btn, _setup_btn]
	_rebuild_strip_box()


func _rebuild_strip_box() -> void:
	if _strip_box != null:
		_strip.remove_child(_strip_box)
		_strip_box.queue_free()
	_strip_box = VBoxContainer.new() if _landscape else HBoxContainer.new()
	_strip_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_strip_box.add_theme_constant_override("separation", 6 if _landscape else 8)
	_strip.add_child(_strip_box)
	for item in _strip_items:
		if item.get_parent() != null:
			item.get_parent().remove_child(item)
		_strip_box.add_child(item)


func _build_badge() -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	_badge = UiKit.panel("PausedBadge")
	_badge.visible = false
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_badge)

	_badge_label = UiKit.label("", "PausedLabel")
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_child(_badge_label)


# ------------------------------------------------------------------ 文本 / 主题

func refresh_language() -> void:
	_badge_label.text = t("chip.paused")
	_tags["w"].text = t("side.w")
	_tags["b"].text = t("side.b")
	_rotate_btn.tooltip_text = t("clock.facing.title")
	_swap_btn.tooltip_text = t("clock.swap.title")
	_full_btn.tooltip_text = t("clock.full.title")
	_setup_btn.tooltip_text = t("clock.setup.title")
	# 步数 / 状态徽标 / 暂停按钮的文字由 render() 重画
	_last_foot = {"w": "", "b": ""}
	_last_chip = {"w": "", "b": ""}
	_last_text = {"w": "", "b": ""}
	_strip_state = ""
	update_sound_icon()


func apply_palette() -> void:
	_bg.color = app.palette["clock_bg"]
	_apply_strip_style()
	for side in ["w", "b"]:
		_rings[side].add_theme_stylebox_override("panel", _ring_box())
		_last_time_color[side] = Color(0, 0, 0, 0)
		_last_foot_color[side] = Color(0, 0, 0, 0)
		_last_chip_style[side] = ""
		_last_chip_color[side] = Color(0, 0, 0, 0)
		_apply_chip_style(side)
	_apply_bar_colors()
	update_sound_icon()


func _apply_strip_style() -> void:
	var p: Dictionary = app.palette
	var pad: int = 4 if _landscape else 8
	var sb := ClockTheme.box(p["strip_bg"], p["line"], 0, 0, pad, 0)
	if _landscape:
		sb.border_width_left = 1
		sb.border_width_right = 1
	else:
		sb.border_width_top = 1
		sb.border_width_bottom = 1
	_strip.add_theme_stylebox_override("panel", sb)


func _apply_chip_style(side: String) -> void:
	var active: bool = _rings[side].visible
	var key := "on" if active else "off"
	if _last_chip_style[side] == key:
		return
	_last_chip_style[side] = key
	var p: Dictionary = app.palette
	var color: Color = p["accent"] if active else p["fg"]
	_chip_panels[side].add_theme_stylebox_override("panel",
		ClockTheme.box(Color(0, 0, 0, 0), Color(color.r, color.g, color.b, 0.55), 999, 1, 7, 1))


func update_sound_icon() -> void:
	var on: bool = bool(app.cfg.get("sound", true))
	var path := "res://assets/icons/sound_on.png" if on else "res://assets/icons/sound_off.png"
	if _sound_btn.icon != load(path):
		_sound_btn.icon = load(path)
	_sound_btn.tooltip_text = t("clock.sound.off") if on else t("clock.sound.on")


func update_strip(state: Dictionary) -> void:
	var live: bool = not state.is_empty() and bool(state["started"]) and not bool(state["finished"])
	# 每帧都设一遍 theme_type_variation / text 会不断触发主题变更通知，得不偿失：
	# 只在「隐藏 / 运行中 / 已暂停」三种状态之间切换时才动它
	var key := "hidden"
	if live:
		key = "paused" if bool(state["paused"]) else "running"
	if key == _strip_state:
		return
	_strip_state = key

	_pause_btn.visible = live
	if not live:
		return
	var paused: bool = key == "paused"
	_pause_btn.theme_type_variation = "PauseOnButton" if paused else "IconButton"
	_pause_btn.text = t("clock.resume") if paused else t("clock.pause")
	_pause_btn.tooltip_text = t("clock.resume.title") if paused else t("clock.pause.title")


func set_badge_visible(on: bool) -> void:
	_badge.visible = on


# ------------------------------------------------------------------ 朝向 / 交换 / 对坐

func _on_resized() -> void:
	_set_orientation(size.x > size.y)
	_fit_all()


func _set_orientation(landscape: bool) -> void:
	if _panes != null and landscape == _landscape:
		return
	_landscape = landscape

	var old := _panes
	_panes = HBoxContainer.new() if landscape else VBoxContainer.new()
	_panes.name = "Panes"
	_panes.add_theme_constant_override("separation", 0)
	_panes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panes)
	move_child(_panes, 1)

	for item in _panes_items:
		if item.get_parent() != null:
			item.get_parent().remove_child(item)
		_panes.add_child(item)

	if old != null:
		remove_child(old)
		old.queue_free()

	_strip.custom_minimum_size = Vector2(58, 0) if landscape else Vector2(0, 54)
	_apply_strip_style()
	_rebuild_strip_box()
	_apply_order()
	_update_facing()
	_fit_all()


## 「交换两侧」：只换三块在容器里的顺序，不改朝向
func _apply_order() -> void:
	if _panes == null:
		return
	var swapped: bool = bool(app.cfg.get("swapped", false))
	var order: Array = [_panes_map["w"], _strip, _panes_map["b"]] if swapped \
		else [_panes_map["b"], _strip, _panes_map["w"]]
	for i in order.size():
		_panes.move_child(order[i], i)


func apply_swap() -> void:
	_apply_order()
	_update_facing()
	_fit_all()


func apply_facing() -> void:
	_update_facing()
	_fit_all()


## 对坐模式：旋转「视觉上排在最前的那一块」（竖屏=上方、横屏=左侧）。
## 视觉顺序由 swapped 决定，与容器里的节点顺序无关 —— 与网页版 .is-far 同一套规则。
func _update_facing() -> void:
	var far_side: String = "w" if bool(app.cfg.get("swapped", false)) else "b"
	for side in ["w", "b"]:
		var inner: Control = _inners[side]
		var rotate: bool = bool(app.cfg.get("facing", true)) and not _landscape and side == far_side
		# 旋转永远绕面板中心；布局变了（转屏 / 改尺寸）要重新算一次轴心
		inner.pivot_offset = inner.size * 0.5
		inner.rotation = PI if rotate else 0.0


# ------------------------------------------------------------------ 渲染

func render(state: Dictionary, now: int) -> void:
	if state.is_empty():
		return
	var p: Dictionary = app.palette
	var running: bool = bool(state["running"]) and not bool(state["paused"])
	var finished: bool = bool(state["finished"])

	for side in ["w", "b"]:
		var info: Dictionary = ClockEngine.readout(state, side, now)
		var ms: int = int(info["ms"])
		var txt := ClockEngine.format_time(ms)
		var label: Label = _times[side]

		if _last_text[side] != txt:
			var len_changed: bool = _last_text[side] == "" or str(_last_text[side]).length() != txt.length()
			_last_text[side] = txt
			label.text = txt
			if len_changed:
				_fit_time(side)

		var byoyomi: bool = str(info["phase"]) == "byoyomi"
		var flagged: bool = finished and str(state["flagged"]) == side
		var active: bool = running and str(state["active"]) == side

		# —— 时间颜色（与 CSS 层叠顺序一致：读秒紫 → 告急琥珀 → 20 秒内红）——
		var color: Color = p[side + "_ink"]
		if finished:
			color = p[side + "_crit"] if flagged else p[side + "_ink"]
		elif ms <= CRITICAL:
			color = p[side + "_crit"]
		elif (not byoyomi) and ms <= LOW:
			color = p[side + "_low"]
		elif byoyomi:
			color = p["byo_" + side]
		if _last_time_color[side] != color:
			_last_time_color[side] = color
			label.add_theme_color_override("font_color", color)

		# 走棋方高亮、其余一方数字略暗；最后 20 秒呼吸闪烁
		var alpha := 1.0 if active else 0.78
		if (not finished) and ms <= CRITICAL:
			var phase := float(Time.get_ticks_msec() % 1000) / 1000.0
			alpha = 0.55 + 0.45 * absf(sin(phase * PI))
		label.modulate.a = alpha

		_rings[side].visible = active
		_apply_chip_style(side)

		var foot: String = t("moves.n", {"n": int(state["moves"][side])})
		if byoyomi and not finished and int(state["cfg"]["byoyomiPeriods"]) > 1:
			foot += " · " + t("foot.byoyomi", {
				"left": int(info["periodsLeft"]),
				"total": int(state["cfg"]["byoyomiPeriods"]),
			})
		if _last_foot[side] != foot:
			_last_foot[side] = foot
			_feet[side].text = foot
		var foot_color: Color = p["byo_" + side] if (byoyomi and not finished) else p[side + "_ink"]
		if _last_foot_color[side] != foot_color:
			_last_foot_color[side] = foot_color
			_feet[side].add_theme_color_override("font_color", foot_color)

		# 读秒段数条：只在 Byoyomi 模式出现（主时间阶段整条都亮着 = 一段都还没用）
		var bar: ByoyomiBar = _bars[side]
		# 读秒 0 秒 = 没有读秒，段数条也就没有意义
		var byo_ms: int = int(state["cfg"]["byoyomiMs"])
		var byo_mode: bool = str(state["cfg"]["mode"]) == ClockEngine.MODES.BYOYOMI and byo_ms > 0
		bar.visible = byo_mode
		if byo_mode:
			# 正在倒计时的那一段按「本窗口还剩多少」显示成进度条：
			# 窗口剩 5/20 秒 → 这一段 25% 绿、75% 红；主时间阶段没有段在倒计时 → -1
			var ratio := -1.0
			if str(info["phase"]) == "byoyomi" and int(info["periodsLeft"]) > 0:
				ratio = clampf(float(int(info["ms"])) / float(byo_ms), 0.0, 1.0)
			bar.set_state(int(state["cfg"]["byoyomiPeriods"]), int(info["periodsLeft"]), ratio)

		var chip: String = _chip_text(side, info, state)
		if _last_chip[side] != chip:
			_last_chip[side] = chip
			_chips[side].text = chip
		var chip_color: Color = p[side + "_ink"]
		if flagged:
			chip_color = p["danger"]
		elif active:
			chip_color = p["accent"]
		var chip_tint := Color(chip_color.r, chip_color.g, chip_color.b, 1.0 if (active or flagged) else 0.66)
		if _last_chip_color[side] != chip_tint:
			_last_chip_color[side] = chip_tint
			_chips[side].add_theme_color_override("font_color", chip_tint)

	update_strip(state)
	set_badge_visible(bool(state["paused"]))


## 与网页版 chipText() 同一套判断
func _chip_text(side: String, info: Dictionary, state: Dictionary) -> String:
	if bool(state["finished"]):
		return t("chip.flagged") if str(state["flagged"]) == side else t("chip.won")
	if bool(state["paused"]):
		return t("chip.paused")
	if not bool(state["started"]):
		return t("chip.ready")
	var byoyomi: bool = str(info["phase"]) == "byoyomi"
	if str(state["active"]) == side:
		return t("chip.byoyomiRunning") if byoyomi else t("chip.running")
	return t("chip.byoyomiWaiting") if byoyomi else t("chip.waiting")


## 让时间数字尽量占满面板：先按 100 号字实测文本宽度，再按面板可用宽/高反推字号。
## 与网页版 fitTime() 用的是同一个公式（实测才可靠，不同平台字体宽度不一样）。
func _fit_time(side: String) -> void:
	var pane: Control = _panes_map[side]
	var label: Label = _times[side]
	var w: float = pane.size.x
	var h: float = pane.size.y
	if w <= 1.0 or h <= 1.0:
		return

	var mono: Font = app.fonts["mono"]
	var probe: float = mono.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	if probe <= 0.0:
		probe = 100.0 * maxf(4.0, float(label.text.length())) * 0.62

	var px: int = int(clampf(minf((w * 0.92) / (probe / 100.0), h * 0.56), 18.0, 512.0))
	if label.get_theme_font_size("font_size") != px:
		label.add_theme_font_size_override("font_size", px)

	var bar: ByoyomiBar = _bars[side]
	var bar_w: float = minf(w * 0.72, 240.0)
	bar.custom_minimum_size = Vector2(bar_w, BAR_H)


func _fit_all() -> void:
	_fit_time("w")
	_fit_time("b")
	_update_facing()


## 供总控在切到棋钟页时调用（那一帧面板尺寸还没算好，重排一次字号）
func refit() -> void:
	_fit_all()
	call_deferred("_fit_all")


## 排障用：把三块的实际尺寸打进日志（--debug-input）
func debug_sizes() -> String:
	return "landscape=%s panes=%s strip_min=%s strip=%s b=%s w=%s" % [
		_landscape, _panes.size, _strip.custom_minimum_size, _strip.size,
		_panes_map["b"].size, _panes_map["w"].size,
	]
