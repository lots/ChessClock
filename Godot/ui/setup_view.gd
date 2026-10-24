class_name SetupView
extends Control
## setup_view.gd — 设置页（网页版 index.html 的 #screen-setup + app.js 的设置部分）
##
## 结构：页头（logo / 标题 / ENG·华文）→ 三张卡片（1 计时模式 · 2 时间 · 3 选项）
## → 「怎么用」入口（内容在 HelpView 那一页）→ 底部「开始对局」。
## 与网页版的有意差异：时间预设从「按钮宫格」改成**下拉框**，说明文字改到单独一页。
## 文案全部来自 i18n，颜色全部来自主题，所以切语言 / 切主题 / 转屏都不需要重建界面。

signal start_requested
signal lang_requested(lang: String)
signal theme_requested(theme_name: String)
signal help_requested
signal settings_changed

var app: Node                       ## main.gd（持有 cfg / lang / palette / t()）

var _bg: TextureRect
var _logo: TextureRect
var _title: Label
var _subtitle: RichTextLabel
var _lang_en: Button
var _lang_zh: Button
var _lang_pill: PanelContainer

var _scroll: ScrollContainer
var _cards_box: VBoxContainer
var _headings := {}                 ## i18n key -> Label
var _mode_grid: GridContainer
var _mode_buttons := {}             ## mode -> Button
var _mode_hint: RichTextLabel
var _preset_select: OptionButton    ## 时间预设下拉框
var _preset_ids := PackedStringArray()  ## 索引 -> 预设 id（最后一档是 ""，代表「自定义」）
var _preset_key := ""               ## mode|lang，去重

var _base_box: VBoxContainer
var _inc_box: VBoxContainer
var _periods_box: VBoxContainer
var _base_label: Label
var _inc_label: Label
var _periods_label: Label
var _base_edit: LineEdit
var _inc_edit: LineEdit
var _periods_edit: LineEdit
var _summary: Label

var _sound_check: CheckBox
var _facing_check: CheckBox
var _sound_label: Label
var _facing_label: Label
var _wake_label: Label
var _wake_check: CheckBox
var _theme_option: OptionButton
var _theme_label: Label
var _keys_hint: RichTextLabel
var _help_button: Button
var _start_button: Button
var _syncing := false
var _non_digits: RegEx


func _ready() -> void:
	build()
	apply_layout()
	resized.connect(apply_layout)


func t(key: String, vars: Dictionary = {}) -> String:
	return app.t(key, vars)


func cfg() -> Dictionary:
	return app.cfg


# ------------------------------------------------------------------ 搭界面

func build() -> void:
	var p: Dictionary = app.palette
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_bg = UiKit.gradient_rect(p["bg_grad_a"], p["bg_grad_b"])
	add_child(UiKit.fill(_bg))

	_non_digits = RegEx.create_from_string("[^0-9]")

	var root := UiKit.margin(16, 10, 16, 0)
	add_child(UiKit.fill(root))

	var page := UiKit.vbox(0)
	root.add_child(page)

	# ---------------- 页头 ----------------
	var header := UiKit.hbox(12)
	header.custom_minimum_size.y = 96
	page.add_child(header)

	_logo = TextureRect.new()
	_logo.texture = load("res://assets/logo-brand.png")
	_logo.custom_minimum_size = Vector2(96, 96)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.add_child(_logo)

	var head_text := UiKit.vbox(4)
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(head_text)

	_title = UiKit.label("", "HeadTitle")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_text.add_child(_title)
	_subtitle = UiKit.rich("", p, 11, p["muted"])
	head_text.add_child(_subtitle)

	# 右上角 ENG / 华文：把当前语言那半边点亮
	_lang_pill = UiKit.panel()
	_lang_pill.add_theme_stylebox_override("panel", ClockTheme.box(p["btn"], p["line"], 999, 1, 4, 2))
	_lang_pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.add_child(_lang_pill)

	var pill_box := UiKit.hbox(0)
	_lang_pill.add_child(pill_box)
	_lang_en = UiKit.button("ENG", "LangButton")
	_lang_en.pressed.connect(func() -> void: lang_requested.emit("en"))
	pill_box.add_child(_lang_en)
	var sep := UiKit.label("/", "")
	sep.add_theme_font_size_override("font_size", 12)
	sep.modulate.a = 0.5
	pill_box.add_child(sep)
	_lang_zh = UiKit.button("华文", "LangButton")
	_lang_zh.pressed.connect(func() -> void: lang_requested.emit("zh"))
	pill_box.add_child(_lang_zh)

	# ---------------- 可滚动卡片区 ----------------
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_scroll)

	var scroll_margin := UiKit.margin(0, 12, 0, 20)
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(scroll_margin)

	_cards_box = UiKit.vbox(12)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_cards_box)
	_style_scrollbar()

	_build_mode_card(p)
	_build_time_card(p)
	_build_options_card(p)
	_build_help_link(p)

	# ---------------- 底部「开始对局」 ----------------
	var footer := UiKit.panel("FooterPanel")
	page.add_child(footer)
	_start_button = UiKit.button("", "AccentButton")
	_start_button.custom_minimum_size.y = 50
	_start_button.pressed.connect(func() -> void: start_requested.emit())
	footer.add_child(_start_button)


func _card(heading_key: String) -> VBoxContainer:
	var panel := UiKit.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.add_child(panel)
	var box := UiKit.vbox(10)
	panel.add_child(box)
	var heading := UiKit.label("", "CardTitle")
	box.add_child(heading)
	_headings[heading_key] = heading
	return box


func _build_mode_card(p: Dictionary) -> void:
	var box := _card("setup.mode.heading")

	var seg := UiKit.panel("SegPanel")
	box.add_child(seg)
	_mode_grid = UiKit.grid(2, 6, 6)
	seg.add_child(_mode_grid)

	for m in ["fischer", "delay", "byoyomi", "sudden"]:
		var b := UiKit.button("", "Seg")
		b.set_meta("mode", m)
		b.custom_minimum_size.y = 36
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_mode_pressed.bind(m))
		_mode_grid.add_child(b)
		_mode_buttons[m] = b

	_mode_hint = UiKit.rich("", p, 12, p["muted"])
	box.add_child(_mode_hint)


func _build_time_card(p: Dictionary) -> void:
	var box := _card("setup.time.heading")

	# 预设下拉框：一档一行「记法 · 类别」，最后一档是「自定义」
	_preset_select = OptionButton.new()
	_preset_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_select.custom_minimum_size.y = 44
	_preset_select.fit_to_longest_item = false
	_preset_select.item_selected.connect(_on_preset_selected)
	box.add_child(_preset_select)

	var fields := UiKit.grid(2, 10, 10)
	box.add_child(fields)

	_base_box = UiKit.vbox(6)
	_base_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(_base_box)
	_base_label = UiKit.label("", "FieldLabel")
	_base_box.add_child(_base_label)
	_base_edit = UiKit.line_edit("10")
	_base_edit.text_changed.connect(func(_t: String) -> void: _on_field_typed())
	_base_edit.focus_exited.connect(_on_field_committed)
	_base_edit.text_submitted.connect(func(_t: String) -> void: _on_field_committed())
	_base_box.add_child(_base_edit)

	_inc_box = UiKit.vbox(6)
	_inc_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(_inc_box)
	_inc_label = UiKit.label("", "FieldLabel")
	_inc_box.add_child(_inc_label)
	_inc_edit = UiKit.line_edit("20")
	_inc_edit.text_changed.connect(func(_t: String) -> void: _on_field_typed())
	_inc_edit.focus_exited.connect(_on_field_committed)
	_inc_edit.text_submitted.connect(func(_t: String) -> void: _on_field_committed())
	_inc_box.add_child(_inc_edit)

	_periods_box = UiKit.vbox(6)
	_periods_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(_periods_box)
	_periods_label = UiKit.label("", "FieldLabel")
	_periods_box.add_child(_periods_label)
	_periods_edit = UiKit.line_edit("3")
	_periods_edit.text_changed.connect(func(_t: String) -> void: _on_field_typed())
	_periods_edit.focus_exited.connect(_on_field_committed)
	_periods_edit.text_submitted.connect(func(_t: String) -> void: _on_field_committed())
	_periods_box.add_child(_periods_edit)

	var sum_panel := UiKit.panel("SunkenPanel")
	box.add_child(sum_panel)
	_summary = UiKit.label("", "SummaryLabel")
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum_panel.add_child(_summary)


func _build_options_card(p: Dictionary) -> void:
	var box := _card("setup.options.heading")

	var sound_row := _switch_row(bool(cfg()["sound"]))
	_sound_check = sound_row[0]
	_sound_label = sound_row[1]
	_sound_check.toggled.connect(_on_sound_toggled)
	box.add_child(sound_row[2])

	var facing_row := _switch_row(bool(cfg()["facing"]))
	_facing_check = facing_row[0]
	_facing_label = facing_row[1]
	_facing_check.toggled.connect(func(v: bool) -> void:
		cfg()["facing"] = v
		settings_changed.emit())
	box.add_child(facing_row[2])

	var wake_row := _switch_row(bool(cfg()["keepAwake"]))
	_wake_check = wake_row[0]
	_wake_label = wake_row[1]
	_wake_check.toggled.connect(func(v: bool) -> void:
		cfg()["keepAwake"] = v
		settings_changed.emit())
	box.add_child(wake_row[2])

	var theme_row := UiKit.hbox(10)
	box.add_child(theme_row)
	_theme_label = UiKit.label("", "MutedLabel")
	_theme_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_theme_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	theme_row.add_child(_theme_label)

	_theme_option = OptionButton.new()
	_theme_option.custom_minimum_size.x = 140
	_theme_option.item_selected.connect(_on_theme_selected)
	theme_row.add_child(_theme_option)

	_keys_hint = UiKit.rich("", p, 12, p["muted"])
	box.add_child(_keys_hint)


## 一行开关：勾选框 + 会自动换行的说明文字（点文字也能勾）
## 网页版的 .switch 也是这样：文字换行、整行可点。
func _switch_row(pressed: bool) -> Array:
	var check := UiKit.checkbox("", pressed)
	var text := UiKit.label("", "")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_STOP
	text.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			check.button_pressed = not check.button_pressed)

	var row := UiKit.hbox(10)
	row.add_child(check)
	row.add_child(text)
	return [check, text, row]


## 「怎么用」入口：说明内容搬到单独的 HelpView 那一页，这里只留一个入口按钮。
## （网页版是把说明直接铺在设置页最后一张卡片里；原生版屏幕更小，单独一页更好读。）
func _build_help_link(p: Dictionary) -> void:
	_help_button = UiKit.button("", "Btn")
	_help_button.custom_minimum_size.y = 46
	_help_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_button.pressed.connect(func() -> void: help_requested.emit())
	_cards_box.add_child(_help_button)


# ------------------------------------------------------------------ 语言 / 主题

func refresh_language() -> void:
	var p: Dictionary = app.palette
	_title.text = t("app.title")
	_subtitle.set_meta("html", t("app.subtitle"))
	_subtitle.text = UiKit.bbcode(t("app.subtitle"), p)

	for key in _headings:
		_headings[key].text = t(key)
	for m in _mode_buttons:
		_mode_buttons[m].text = t("mode." + m)

	_mode_hint.set_meta("html", t("hint." + cfg()["mode"]))
	_mode_hint.text = UiKit.bbcode(t("hint." + cfg()["mode"]), p)

	_base_label.text = t("setup.base.label")
	_periods_label.text = t("setup.periods.label")

	_sound_label.text = t("opt.sound")
	_facing_label.text = t("opt.facing")
	_wake_label.text = t("opt.wake")
	_theme_label.text = t("setup.theme.label")
	_keys_hint.set_meta("html", t("setup.keys.hint"))
	_keys_hint.text = UiKit.bbcode(t("setup.keys.hint"), p)
	_help_button.text = t("setup.how.heading") + "   ›"
	_start_button.text = t("setup.start")

	_fill_theme_options()
	_refresh_mode()
	_mark_language()


func _mark_language() -> void:
	var lang: String = app.lang
	_lang_en.theme_type_variation = "LangButtonOn" if lang == "en" else "LangButton"
	_lang_zh.theme_type_variation = "LangButtonOn" if lang == "zh" else "LangButton"


func apply_palette() -> void:
	var p: Dictionary = app.palette
	remove_child(_bg)
	_bg.queue_free()
	_bg = UiKit.gradient_rect(p["bg_grad_a"], p["bg_grad_b"])
	add_child(_bg)
	move_child(_bg, 0)
	_lang_pill.add_theme_stylebox_override("panel", ClockTheme.box(p["btn"], p["line"], 999, 1, 4, 2))
	for node in [_subtitle, _mode_hint, _keys_hint]:
		node.add_theme_color_override("default_color", p["muted"])
		node.text = UiKit.bbcode(str(node.get_meta("html")), p)
	_rebuild_presets()


func _fill_theme_options() -> void:
	_theme_option.clear()
	for i in ClockTheme.NAMES.size():
		_theme_option.add_item(t("theme." + ClockTheme.NAMES[i]), i)
	var idx: int = ClockTheme.NAMES.find(cfg()["theme"])
	if idx < 0:
		idx = 0
	_theme_option.select(idx)


func _on_theme_selected(index: int) -> void:
	theme_requested.emit(ClockTheme.NAMES[index])


# ------------------------------------------------------------------ 预设下拉框

func _preset_key_now() -> String:
	return str(cfg()["mode"]) + "|" + str(app.lang)


## 一档一行：棋类「10+5  ·  Blitz」，围棋只有主记法「10+3×20」（没有档次可写）。
## 与网页版 buildPresetOptions() 的拼法一致：第二段有内容才拼上去。
func _preset_item_text(preset: Dictionary) -> String:
	var extra := str(preset.get("sub", ""))
	if extra == "" and preset.has("name"):
		extra = t(str(preset["name"]))
	if extra == "":
		return ClockPresets.label(preset)
	return "%s   ·   %s" % [ClockPresets.label(preset), extra]


func _rebuild_presets() -> void:
	_preset_key = _preset_key_now()
	_preset_select.clear()
	_preset_ids.clear()

	for preset in ClockPresets.for_mode(cfg()["mode"]):
		_preset_select.add_item(_preset_item_text(preset))
		_preset_ids.append(str(preset["id"]))

	# 最后一档是「自定义」：数字被手改过、对不上任何预设时就停在这里
	_preset_select.add_item(t("preset.custom"))
	_preset_ids.append("")

	_refresh_preset_selection()


## 让下拉框跟着 cfg 走：对得上某个预设就选中它，否则落到「自定义」
func _refresh_preset_selection() -> void:
	var match_id := ClockPresets.match_id(cfg()["mode"], cfg())
	cfg()["presetId"] = match_id if match_id != "" else null
	var wanted: int = _preset_ids.find(match_id)
	if wanted < 0:
		wanted = _preset_ids.size() - 1          # 「自定义」
	if _preset_select.selected != wanted:
		_preset_select.select(wanted)


func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= _preset_ids.size():
		return
	var id := _preset_ids[index]
	if id == "":
		return                                    # 选了「自定义」：保留当前数字
	_apply_preset(id)


func _apply_preset(id: String) -> void:
	for preset in ClockPresets.for_mode(cfg()["mode"]):
		if str(preset["id"]) != id:
			continue
		cfg()["baseMin"] = int(preset["baseMin"])
		cfg()["incSec"] = int(preset["incSec"])
		if preset.has("periods"):
			cfg()["periods"] = int(preset["periods"])
		cfg()["presetId"] = id
		sync_from_cfg()
		settings_changed.emit()
		return


# ------------------------------------------------------------------ 模式 / 输入

func _on_mode_pressed(mode: String) -> void:
	var prev: String = cfg()["mode"]
	if prev == mode:
		return
	cfg()["mode"] = mode
	# 从别的模式第一次切进读秒：给 Byoyomi 默认 10+3×20
	#（当前数字本来就是某个读秒预设的话，保留用户挑的那档）
	if mode == ClockEngine.MODES.BYOYOMI and not ClockPresets.is_byoyomi_preset(cfg()):
		cfg()["baseMin"] = 10
		cfg()["incSec"] = 20
		cfg()["periods"] = 3
		cfg()["presetId"] = "10+3x20"
	# 切到读秒时给个合理的默认额度：主时间 0（纯读秒）再配 0 秒读秒等于什么都没配
	if mode == ClockEngine.MODES.BYOYOMI and int(cfg()["baseMin"]) < 1 and int(cfg()["incSec"]) < 1:
		cfg()["incSec"] = 30
	# 切走读秒时主时间必须 ≥ 1 分钟（别的模式没有第二个数兜底）
	if mode != ClockEngine.MODES.BYOYOMI and int(cfg()["baseMin"]) < 1:
		cfg()["baseMin"] = 1
	sync_from_cfg()
	settings_changed.emit()


func _on_sound_toggled(on: bool) -> void:
	cfg()["sound"] = on
	settings_changed.emit()


## 打字时不做夹取（免得打断输入），只把非数字丢掉；失焦 / 回车时再统一校正
func _on_field_typed() -> void:
	if _syncing:
		return
	_syncing = true
	for edit in [_base_edit, _inc_edit, _periods_edit]:
		var clean: String = _non_digits.sub(edit.text, "", true)
		if clean != edit.text:
			var caret: int = edit.caret_column
			edit.text = clean
			edit.caret_column = mini(caret, clean.length())
	cfg()["baseMin"] = _int_or(_base_edit.text, int(cfg()["baseMin"]))
	cfg()["incSec"] = _int_or(_inc_edit.text, int(cfg()["incSec"]))
	cfg()["periods"] = _int_or(_periods_edit.text, int(cfg()["periods"]))
	cfg()["presetId"] = null
	_syncing = false
	refresh_summary()
	_refresh_preset_selection()


func _on_field_committed() -> void:
	var clean := ClockSettings.normalize(cfg())
	cfg()["baseMin"] = clean["baseMin"]
	cfg()["incSec"] = clean["incSec"]
	cfg()["periods"] = clean["periods"]
	sync_from_cfg()
	settings_changed.emit()


static func _int_or(text: String, fallback: int) -> int:
	return text.to_int() if text.is_valid_int() else fallback


# ------------------------------------------------------------------ 刷新

## 把 cfg 完整写回控件（选预设 / 模式切换 / 开始对局前都走这里）
func sync_from_cfg() -> void:
	_base_edit.text = str(cfg()["baseMin"])
	_inc_edit.text = str(cfg()["incSec"])
	_periods_edit.text = str(cfg()["periods"])
	_sound_check.set_pressed_no_signal(bool(cfg()["sound"]))
	_facing_check.set_pressed_no_signal(bool(cfg()["facing"]))
	_wake_check.set_pressed_no_signal(bool(cfg()["keepAwake"]))
	_refresh_mode()


func _refresh_mode() -> void:
	var mode: String = cfg()["mode"]
	var p: Dictionary = app.palette
	for m in _mode_buttons:
		_mode_buttons[m].theme_type_variation = "SegOn" if m == mode else "Seg"

	if str(_mode_hint.get_meta("html", "")) != t("hint." + mode):
		_mode_hint.set_meta("html", t("hint." + mode))
		_mode_hint.text = UiKit.bbcode(t("hint." + mode), p)

	var is_byo := mode == ClockEngine.MODES.BYOYOMI
	_inc_label.text = t("inc.byoyomi" if is_byo else (
		"inc.delay" if mode == ClockEngine.MODES.DELAY else (
			"inc.sudden" if mode == ClockEngine.MODES.SUDDEN else "inc.fischer")))
	_inc_edit.editable = mode != ClockEngine.MODES.SUDDEN
	_inc_edit.modulate.a = 0.45 if mode == ClockEngine.MODES.SUDDEN else 1.0
	_periods_box.visible = is_byo

	# 下拉框里的档位取决于「模式 + 语言」，两者没变就只重新选一下，不重建控件
	if _preset_key != _preset_key_now() or _preset_ids.is_empty():
		_rebuild_presets()
	else:
		_refresh_preset_selection()
	refresh_summary()


func refresh_summary() -> void:
	_summary.text = t("summary.prefix") + ClockSettings.summary(app.lang, cfg())


# ------------------------------------------------------------------ 横竖屏

func apply_layout() -> void:
	_mode_grid.columns = 2 if size.x < 620.0 else 4


## 把设置页滚到底（截图 / 目视检查页面最下面那一块，比如「怎么用」入口）
func scroll_to_bottom() -> void:
	_scroll.scroll_vertical = 1 << 24


## 滚动条：细一点、低调一点（见 UiKit.style_scrollbar）
func _style_scrollbar() -> void:
	UiKit.style_scrollbar(_scroll, app.palette)
