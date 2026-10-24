class_name HelpView
extends Control
## help_view.gd — 「怎么用」说明页
##
## 网页版把这两段说明直接铺在设置页最后一张卡片里；原生版屏幕更小，
## 所以把它单独拆成一页，设置页只留一个入口按钮（设置页 → 怎么用 → 返回）。
## 文案仍然用同一批 i18n 词条（how.facing / how.byoyomi），所以三种语言、三套主题
## 都与网页版逐字一致。

signal back_requested

var app: Node

var _bg: TextureRect
var _back_btn: Button
var _title: Label
var _scroll: ScrollContainer
var _facing: RichTextLabel
var _byoyomi: RichTextLabel


func _ready() -> void:
	build()


func t(key: String, vars: Dictionary = {}) -> String:
	return app.t(key, vars)


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p: Dictionary = app.palette

	_bg = UiKit.gradient_rect(p["bg_grad_a"], p["bg_grad_b"])
	add_child(UiKit.fill(_bg))

	var root := UiKit.margin(16, 10, 16, 16)
	add_child(UiKit.fill(root))

	var page := UiKit.vbox(0)
	root.add_child(page)

	# ---------------- 页头：返回 + 标题 ----------------
	var header := UiKit.hbox(12)
	header.custom_minimum_size.y = 52
	page.add_child(header)

	_back_btn = UiKit.button("", "Btn")
	_back_btn.custom_minimum_size = Vector2(0, 40)
	_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_btn.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(_back_btn)

	_title = UiKit.label("", "HeadTitle")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title)

	# ---------------- 正文 ----------------
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_scroll)
	UiKit.style_scrollbar(_scroll, p)

	var scroll_margin := UiKit.margin(0, 8, 0, 8)
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(scroll_margin)

	var card := UiKit.panel()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(card)

	var body := UiKit.vbox(14)
	card.add_child(body)

	_facing = UiKit.rich("", p, 13, p["muted"])
	body.add_child(_facing)
	_byoyomi = UiKit.rich("", p, 13, p["muted"])
	body.add_child(_byoyomi)

	refresh_language()


func refresh_language() -> void:
	var p: Dictionary = app.palette
	_back_btn.text = "‹   " + t("overlay.back")
	_title.text = t("setup.how.heading")
	_facing.set_meta("html", t("how.facing"))
	_facing.text = UiKit.bbcode(t("how.facing"), p)
	_byoyomi.set_meta("html", t("how.byoyomi"))
	_byoyomi.text = UiKit.bbcode(t("how.byoyomi"), p)


func apply_palette() -> void:
	var p: Dictionary = app.palette
	remove_child(_bg)
	_bg.queue_free()
	_bg = UiKit.gradient_rect(p["bg_grad_a"], p["bg_grad_b"])
	add_child(_bg)
	move_child(_bg, 0)
	UiKit.style_scrollbar(_scroll, p)
	for node in [_facing, _byoyomi]:
		node.add_theme_color_override("default_color", p["muted"])
		node.text = UiKit.bbcode(str(node.get_meta("html", "")), p)
