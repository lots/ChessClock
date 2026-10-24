class_name UiKit
extends RefCounted
## ui_kit.gd — 建控件的小工具（网页版里那些 CSS 规则的等价物）
##
## 界面是**用代码搭**的（不用 .tscn）：语言、主题、横竖屏、面板交换都要在运行时重排，
## 代码里搭一次比在编辑器里连一大堆节点更直接，也与网页版「一个 app.js 管全部 DOM」同构。
## 颜色与字号一律走 ClockTheme 的 Theme 变体（对应 CSS 里的 class），
## 只有真正与「哪一方、什么状态」相关的颜色才在渲染时逐帧覆盖。

static func vbox(sep := 0) -> VBoxContainer:
	var n := VBoxContainer.new()
	n.add_theme_constant_override("separation", sep)
	return n


static func hbox(sep := 0) -> HBoxContainer:
	var n := HBoxContainer.new()
	n.add_theme_constant_override("separation", sep)
	return n


static func grid(columns: int, sep_h := 8, sep_v := 8) -> GridContainer:
	var n := GridContainer.new()
	n.columns = columns
	n.add_theme_constant_override("h_separation", sep_h)
	n.add_theme_constant_override("v_separation", sep_v)
	return n


static func margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var n := MarginContainer.new()
	n.add_theme_constant_override("margin_left", left)
	n.add_theme_constant_override("margin_top", top)
	n.add_theme_constant_override("margin_right", right)
	n.add_theme_constant_override("margin_bottom", bottom)
	return n


static func label(text: String, variation := "MutedLabel") -> Label:
	var n := Label.new()
	n.text = text
	n.theme_type_variation = variation
	return n


static func button(text: String, variation := "Btn") -> Button:
	var n := Button.new()
	n.text = text
	n.theme_type_variation = variation
	n.focus_mode = Control.FOCUS_NONE
	n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return n


static func checkbox(text: String, pressed := false) -> CheckBox:
	var n := CheckBox.new()
	n.text = text
	n.button_pressed = pressed
	n.focus_mode = Control.FOCUS_NONE
	n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return n


static func line_edit(text: String = "") -> LineEdit:
	var n := LineEdit.new()
	n.text = text
	n.theme_type_variation = "FieldEdit"
	n.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	n.alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.select_all_on_focus = true
	return n


static func panel(variation := "") -> PanelContainer:
	var n := PanelContainer.new()
	if variation != "":
		n.theme_type_variation = variation
	return n


## 富文本（把网页版带 <strong>/<br>/<kbd> 的文案转成 BBCode）
static func rich(html: String, palette: Dictionary, size := 12, color := Color(0, 0, 0, 0),
		font: Font = null) -> RichTextLabel:
	var n := RichTextLabel.new()
	n.bbcode_enabled = true
	n.fit_content = true
	n.scroll_active = false
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		n.add_theme_font_size_override(k, size)
	if font != null:
		n.add_theme_font_override("normal_font", font)
		n.add_theme_font_override("bold_font", font)
	n.set_meta("html", html)
	n.set_meta("size", size)
	if color.a > 0.0:
		n.add_theme_color_override("default_color", color)
	else:
		n.add_theme_color_override("default_color", palette["muted"])
	n.text = bbcode(html, palette)
	return n


## HTML 片段 → BBCode。只处理这四种标签（i18n 词条里出现的全部），其余原样剥掉。
## 这样 i18n.gd 里的文案可以与网页版 i18n.js **逐字相同**。
static func bbcode(html: String, palette: Dictionary) -> String:
	var s := html
	s = s.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
	s = s.replace("<strong>", "[b]").replace("</strong>", "[/b]")
	s = s.replace("<em>", "[i]").replace("</em>", "[/i]")
	var kbd_color := "#%s" % palette["muted"].to_html(false)
	var kbd_bg := "#%s" % palette["kbd_bg"].to_html(false)
	s = s.replace("<kbd>", "[bgcolor=%s][color=%s] " % [kbd_bg, kbd_color])
	s = s.replace("</kbd>", " [/color][/bgcolor]")
	# 兜底：把没映射到的标签整段去掉
	var re := RegEx.create_from_string("<[^>]+>")
	s = re.sub(s, "", true)
	return s


## 顶到满屏 / 满格
static func fill(node: Control) -> Control:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## 竖直渐变底板（网页版 body 的 linear-gradient）
static func gradient_rect(top: Color, bottom: Color) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([top, bottom])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 8
	tex.height = 256
	var n := TextureRect.new()
	n.texture = tex
	n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	n.stretch_mode = TextureRect.STRETCH_SCALE
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n


## 图标按钮（贴图来自 assets/icons，白色 + 透明底，按主题色染色）
static func icon_button(icon_texture: Texture2D) -> Button:
	var n := button("", "IconButton")
	n.icon = icon_texture
	n.expand_icon = true
	n.add_theme_constant_override("icon_max_width", 22)
	n.custom_minimum_size = Vector2(40, 38)
	return n


## 细一点的滚动条（网页版的滚动条是系统覆盖式，不占版面）
static func style_scrollbar(scroll: ScrollContainer, palette: Dictionary) -> void:
	if scroll == null:
		return
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 6
	var clear := Color(0, 0, 0, 0)
	bar.add_theme_stylebox_override("scroll", ClockTheme.box(clear, clear, 3, 0))
	bar.add_theme_stylebox_override("grabber",
		ClockTheme.box(Color(palette["line"].r, palette["line"].g, palette["line"].b, 0.9), clear, 3, 0))
	bar.add_theme_stylebox_override("grabber_highlight", ClockTheme.box(palette["muted"], clear, 3, 0))
	bar.add_theme_stylebox_override("grabber_pressed", ClockTheme.box(palette["muted"], clear, 3, 0))
