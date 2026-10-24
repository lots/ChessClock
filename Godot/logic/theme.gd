class_name ClockTheme
extends RefCounted
## theme.gd — 三套配色 + Godot Theme 资源（网页版 styles.css 的移植）
## ==================================================================
## 网页版的做法是「主题 = 一组 CSS 变量」，切换主题只改 <html data-theme>；
## Godot 里对应的是「主题 = 一个 Theme 资源」，切换主题只是把它换到根节点上，
## 所有子控件自动重绘 —— 同一套思路，所以这里的三份调色板与 styles.css 的
## :root[data-theme="…"] 变量块逐个对应（tests/project_spec.js 会核对色值）。
##
## 两块对局面板始终「黑方深、白方浅」：那是游戏语义，不随主题变
##（浅色主题额外给面板一圈 --pane-edge 细边，免得白色面板糊在页面底色里）。

const NAMES := ["light", "medium", "dark"]   ## 顺序与设置页下拉框一致

static var _cache := {}


static func normalize(name) -> String:
	var s := String(name if name != null else "")
	return s if s in NAMES else "dark"


## 深色是基准：medium / light 只覆盖各自的差异项（对应 CSS 的层叠）
static func _dark() -> Dictionary:
	return {
		"bg": Color("#0a0d12"),
		"bg_grad_a": Color("#0b1018"),
		"bg_grad_b": Color("#080b11"),
		"fg": Color("#e9eef7"),
		"fg_soft": Color("#cfe0f5"),
		"muted": Color("#8d9aae"),
		"line": Color("#242c39"),
		"card": Color("#121924"),
		"sunken": Color("#0c121b"),
		"btn": Color("#101722"),
		"kbd_bg": Color("#0d1420"),
		"field_bg": Color("#0c121b"),
		"accent": Color("#3ea6ff"),
		"accent_ink": Color("#04121f"),
		"accent_soft": Color("#12283d"),
		"accent_soft_fg": Color("#a9d4ff"),
		"ok": Color("#2fbf71"),
		"ok_ink": Color("#04120a"),
		"warn": Color("#ffb020"),
		"danger": Color("#ff4d4f"),

		"w_face": Color("#edf0f5"),
		"w_ink": Color("#0b0f15"),
		"w_low": Color("#a95c00"),
		"w_crit": Color("#c81e1e"),

		"b_face": Color("#0b0e13"),
		"b_ink": Color("#edf0f5"),
		"b_low": Color("#ffc046"),
		"b_crit": Color("#ff5b5b"),

		"pane_edge": Color(0, 0, 0, 0),
		"strip_bg": Color("#05070a"),
		"clock_bg": Color("#000000"),
		"byo_w": Color("#6b3fd4"),
		"byo_b": Color("#b49bff"),
	}


static func palette(name: String) -> Dictionary:
	var n := normalize(name)
	if _cache.has(n):
		return _cache[n]
	var p := _dark()
	match n:
		"medium":
			p.merge({
				"bg": Color("#3a4250"), "bg_grad_a": Color("#434c5c"), "bg_grad_b": Color("#343b48"),
				"fg": Color("#f3f6fa"), "fg_soft": Color("#dde6f2"), "muted": Color("#b9c3d2"),
				"line": Color("#5b6676"), "card": Color("#48525f"), "sunken": Color("#3f4956"),
				"btn": Color("#525d6c"), "kbd_bg": Color("#3c4553"), "field_bg": Color("#3c4553"),
				"accent": Color("#7cc4ff"), "accent_ink": Color("#062033"),
				"accent_soft": Color("#6d8fb5"), "accent_soft_fg": Color("#f0f7ff"),
				"ok": Color("#43cf87"), "ok_ink": Color("#04170d"),
				"warn": Color("#ffc352"), "danger": Color("#ff6b6d"),
				"pane_edge": Color(1, 1, 1, 0.14),
				"strip_bg": Color("#2c333e"), "clock_bg": Color("#2c333e"),
				"byo_w": Color("#8a6bf5"), "byo_b": Color("#d3c2ff"),
			}, true)
		"light":
			p.merge({
				"bg": Color("#eef1f6"), "bg_grad_a": Color("#f8fafc"), "bg_grad_b": Color("#e5eaf2"),
				"fg": Color("#16202e"), "fg_soft": Color("#2b3a4d"), "muted": Color("#5d6b7e"),
				"line": Color("#ccd5e0"), "card": Color("#ffffff"), "sunken": Color("#f1f4f9"),
				"btn": Color("#ffffff"), "kbd_bg": Color("#eef2f7"), "field_bg": Color("#ffffff"),
				"accent": Color("#1f7fe0"), "accent_ink": Color("#ffffff"),
				"accent_soft": Color("#d7e9ff"), "accent_soft_fg": Color("#0f5aa8"),
				"ok": Color("#1f9d5a"), "ok_ink": Color("#ffffff"),
				"warn": Color("#b26a00"), "danger": Color("#d32f2f"),
				"w_face": Color("#ffffff"),
				"pane_edge": Color(15.0 / 255.0, 32.0 / 255.0, 56.0 / 255.0, 0.14),
				"strip_bg": Color("#e3e8f1"), "clock_bg": Color("#dfe5ee"),
				"byo_w": Color("#5b2fc4"), "byo_b": Color("#6f4ae0"),
			}, true)
	_cache[n] = p
	return p


## 统一造 StyleBoxFlat：背景 / 边框 / 圆角 / 内距
static func box(bg: Color, border := Color(0, 0, 0, 0), radius := 0,
		border_width := 0, pad_x := 0.0, pad_y := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	if pad_x > 0.0 or pad_y > 0.0:
		sb.content_margin_left = pad_x
		sb.content_margin_right = pad_x
		sb.content_margin_top = pad_y
		sb.content_margin_bottom = pad_y
	sb.anti_aliasing = true
	return sb


static func _fill(sb: StyleBoxFlat, bg: Color) -> StyleBoxFlat:
	sb.bg_color = bg
	return sb


## 造一个可直接挂到根节点上的主题资源。
## fonts = {ui, bold, mono, mono_bold}（由 main.gd 建一次，三套主题共用）
static func build(theme_name: String, fonts: Dictionary) -> Theme:
	var p := palette(theme_name)
	var ui: Font = fonts["ui"]
	var bold: Font = fonts["bold"]
	var mono: Font = fonts["mono"]
	var radius: int = 16

	var th := Theme.new()
	th.default_font = ui
	th.default_font_size = 13

	# ---------------- 文本 ----------------
	th.set_color("font_color", "Label", p["fg"])
	th.set_font_size("font_size", "Label", 13)

	th.set_color("default_color", "RichTextLabel", p["fg"])
	th.set_font("normal_font", "RichTextLabel", ui)
	th.set_font("bold_font", "RichTextLabel", bold)
	th.set_font("italics_font", "RichTextLabel", ui)
	th.set_font("bold_italics_font", "RichTextLabel", bold)
	th.set_font("mono_font", "RichTextLabel", mono)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		th.set_font_size(k, "RichTextLabel", 12)
	th.set_font_size("mono_font_size", "RichTextLabel", 12)
	th.set_constant("line_separation", "RichTextLabel", 3)

	# ---------------- 卡片 / 底板 ----------------
	th.set_stylebox("panel", "PanelContainer", box(p["card"], p["line"], radius, 1, 14, 14))
	th.set_stylebox("panel", "Panel", box(p["card"], p["line"], radius, 1, 0, 0))
	th.set_stylebox("panel", "ScrollContainer", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 0))

	# ---------------- 普通按钮 ----------------
	th.set_type_variation("Btn", "Button")
	th.set_stylebox("normal", "Btn", box(p["card"], p["line"], 12, 1, 14, 11))
	th.set_stylebox("hover", "Btn", box(p["card"].lightened(0.10), p["line"], 12, 1, 14, 11))
	th.set_stylebox("pressed", "Btn", box(p["card"].darkened(0.10), p["line"], 12, 1, 14, 11))
	th.set_stylebox("disabled", "Btn", box(p["card"], p["line"], 12, 1, 14, 11))
	th.set_stylebox("focus", "Btn", box(Color(0, 0, 0, 0), p["accent"], 12, 2, 0, 0))
	th.set_font("font", "Btn", bold)
	th.set_font_size("font_size", "Btn", 14)
	th.set_color("font_color", "Btn", p["fg"])
	th.set_color("font_hover_color", "Btn", p["fg"])
	th.set_color("font_pressed_color", "Btn", p["fg"])
	th.set_color("font_focus_color", "Btn", p["fg"])
	th.set_color("font_disabled_color", "Btn", Color(p["fg"].r, p["fg"].g, p["fg"].b, 0.45))

	# 主按钮（开始对局 / 再来一局）
	th.set_type_variation("AccentButton", "Button")
	th.set_stylebox("normal", "AccentButton", box(p["accent"], p["accent"], 12, 1, 18, 14))
	th.set_stylebox("hover", "AccentButton", box(p["accent"].lightened(0.10), p["accent"], 12, 1, 18, 14))
	th.set_stylebox("pressed", "AccentButton", box(p["accent"].darkened(0.10), p["accent"], 12, 1, 18, 14))
	th.set_stylebox("disabled", "AccentButton", box(p["accent"], p["accent"], 12, 1, 18, 14))
	th.set_stylebox("focus", "AccentButton", box(Color(0, 0, 0, 0), p["fg"], 12, 2, 0, 0))
	th.set_font("font", "AccentButton", bold)
	th.set_font_size("font_size", "AccentButton", 17)
	th.set_color("font_color", "AccentButton", p["accent_ink"])
	th.set_color("font_hover_color", "AccentButton", p["accent_ink"])
	th.set_color("font_pressed_color", "AccentButton", p["accent_ink"])
	th.set_color("font_focus_color", "AccentButton", p["accent_ink"])

	# 模式分段按钮（未选中 / 选中）
	th.set_type_variation("Seg", "Button")
	th.set_stylebox("normal", "Seg", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 9, 0, 6, 10))
	th.set_stylebox("hover", "Seg", box(p["card"], Color(0, 0, 0, 0), 9, 0, 6, 10))
	th.set_stylebox("pressed", "Seg", box(p["card"], Color(0, 0, 0, 0), 9, 0, 6, 10))
	th.set_stylebox("focus", "Seg", box(Color(0, 0, 0, 0), p["accent"], 9, 2, 6, 10))
	th.set_font("font", "Seg", bold)
	th.set_font_size("font_size", "Seg", 12)
	th.set_color("font_color", "Seg", p["muted"])
	th.set_color("font_hover_color", "Seg", p["fg"])
	th.set_color("font_pressed_color", "Seg", p["fg"])
	th.set_color("font_focus_color", "Seg", p["fg"])

	th.set_type_variation("SegOn", "Button")
	th.set_stylebox("normal", "SegOn", box(p["accent"], Color(0, 0, 0, 0), 9, 0, 6, 10))
	th.set_stylebox("hover", "SegOn", box(p["accent"].lightened(0.08), Color(0, 0, 0, 0), 9, 0, 6, 10))
	th.set_stylebox("pressed", "SegOn", box(p["accent"].darkened(0.08), Color(0, 0, 0, 0), 9, 0, 6, 10))
	th.set_stylebox("focus", "SegOn", box(p["accent"], p["fg"], 9, 2, 6, 10))
	th.set_font("font", "SegOn", bold)
	th.set_font_size("font_size", "SegOn", 12)
	th.set_color("font_color", "SegOn", p["accent_ink"])
	th.set_color("font_hover_color", "SegOn", p["accent_ink"])
	th.set_color("font_pressed_color", "SegOn", p["accent_ink"])
	th.set_color("font_focus_color", "SegOn", p["accent_ink"])

	# 预设档位（未选中 / 选中）
	th.set_type_variation("Preset", "Button")
	th.set_stylebox("normal", "Preset", box(p["sunken"], p["line"], 12, 1, 4, 9))
	th.set_stylebox("hover", "Preset", box(p["sunken"].lightened(0.08), p["accent"], 12, 1, 4, 9))
	th.set_stylebox("pressed", "Preset", box(p["sunken"].darkened(0.08), p["accent"], 12, 1, 4, 9))
	th.set_stylebox("focus", "Preset", box(Color(0, 0, 0, 0), p["accent"], 12, 2, 4, 9))
	th.set_font("font", "Preset", bold)
	th.set_font_size("font_size", "Preset", 16)
	th.set_color("font_color", "Preset", p["fg"])
	th.set_color("font_hover_color", "Preset", p["fg"])
	th.set_color("font_pressed_color", "Preset", p["fg"])
	th.set_color("font_focus_color", "Preset", p["fg"])

	th.set_type_variation("PresetOn", "Button")
	th.set_stylebox("normal", "PresetOn", box(p["accent_soft"], p["accent"], 12, 2, 4, 9))
	th.set_stylebox("hover", "PresetOn", box(p["accent_soft"].lightened(0.06), p["accent"], 12, 2, 4, 9))
	th.set_stylebox("pressed", "PresetOn", box(p["accent_soft"].darkened(0.06), p["accent"], 12, 2, 4, 9))
	th.set_stylebox("focus", "PresetOn", box(p["accent_soft"], p["fg"], 12, 2, 4, 9))
	th.set_font("font", "PresetOn", bold)
	th.set_font_size("font_size", "PresetOn", 16)
	th.set_color("font_color", "PresetOn", p["accent_soft_fg"])
	th.set_color("font_hover_color", "PresetOn", p["accent_soft_fg"])
	th.set_color("font_pressed_color", "PresetOn", p["accent_soft_fg"])
	th.set_color("font_focus_color", "PresetOn", p["accent_soft_fg"])

	# 操作条图标按钮
	th.set_type_variation("IconButton", "Button")
	th.set_stylebox("normal", "IconButton", box(p["btn"], p["line"], 10, 1, 5, 0))
	th.set_stylebox("hover", "IconButton", box(p["btn"].lightened(0.12), p["line"], 10, 1, 5, 0))
	th.set_stylebox("pressed", "IconButton", box(p["btn"].darkened(0.12), p["line"], 10, 1, 5, 0))
	th.set_stylebox("focus", "IconButton", box(Color(0, 0, 0, 0), p["accent"], 10, 2, 5, 0))
	th.set_font("font", "IconButton", bold)
	th.set_font_size("font_size", "IconButton", 13)
	th.set_color("font_color", "IconButton", p["fg"])
	th.set_color("font_hover_color", "IconButton", p["fg"])
	th.set_color("font_pressed_color", "IconButton", p["fg"])
	th.set_color("font_focus_color", "IconButton", p["fg"])
	# 操作条图标是白色 PNG，这里按主题染色：深色主题用浅色、浅色主题用深色
	th.set_color("icon_normal_color", "IconButton", p["fg"])
	th.set_color("icon_hover_color", "IconButton", p["fg"])
	th.set_color("icon_pressed_color", "IconButton", p["fg"])
	th.set_color("icon_disabled_color", "IconButton", Color(p["fg"].r, p["fg"].g, p["fg"].b, 0.45))

	# 暂停中：那颗按钮变绿（网页版 .icon-btn.primary）
	th.set_type_variation("PauseOnButton", "Button")
	th.set_stylebox("normal", "PauseOnButton", box(p["ok"], p["ok"], 10, 1, 5, 0))
	th.set_stylebox("hover", "PauseOnButton", box(p["ok"].lightened(0.10), p["ok"], 10, 1, 5, 0))
	th.set_stylebox("pressed", "PauseOnButton", box(p["ok"].darkened(0.10), p["ok"], 10, 1, 5, 0))
	th.set_stylebox("focus", "PauseOnButton", box(Color(0, 0, 0, 0), p["fg"], 10, 2, 5, 0))
	th.set_font("font", "PauseOnButton", bold)
	th.set_font_size("font_size", "PauseOnButton", 13)
	th.set_color("font_color", "PauseOnButton", p["ok_ink"])
	th.set_color("font_hover_color", "PauseOnButton", p["ok_ink"])
	th.set_color("font_pressed_color", "PauseOnButton", p["ok_ink"])
	th.set_color("font_focus_color", "PauseOnButton", p["ok_ink"])
	th.set_color("icon_normal_color", "PauseOnButton", p["ok_ink"])
	th.set_color("icon_hover_color", "PauseOnButton", p["ok_ink"])
	th.set_color("icon_pressed_color", "PauseOnButton", p["ok_ink"])

	# 语言胶囊（未选中 / 选中）
	th.set_type_variation("LangButton", "Button")
	th.set_stylebox("normal", "LangButton", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 999, 0, 8, 5))
	th.set_stylebox("hover", "LangButton", box(p["card"], Color(0, 0, 0, 0), 999, 0, 8, 5))
	th.set_stylebox("pressed", "LangButton", box(p["card"], Color(0, 0, 0, 0), 999, 0, 8, 5))
	th.set_stylebox("focus", "LangButton", box(Color(0, 0, 0, 0), p["accent"], 999, 1, 8, 5))
	th.set_font("font", "LangButton", bold)
	th.set_font_size("font_size", "LangButton", 12)
	th.set_color("font_color", "LangButton", Color(p["muted"].r, p["muted"].g, p["muted"].b, 0.75))
	th.set_color("font_hover_color", "LangButton", p["fg"])
	th.set_color("font_pressed_color", "LangButton", p["fg"])
	th.set_color("font_focus_color", "LangButton", p["fg"])

	th.set_type_variation("LangButtonOn", "Button")
	th.set_stylebox("normal", "LangButtonOn", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 999, 0, 8, 5))
	th.set_stylebox("hover", "LangButtonOn", box(p["card"], Color(0, 0, 0, 0), 999, 0, 8, 5))
	th.set_stylebox("pressed", "LangButtonOn", box(p["card"], Color(0, 0, 0, 0), 999, 0, 8, 5))
	th.set_stylebox("focus", "LangButtonOn", box(Color(0, 0, 0, 0), p["accent"], 999, 1, 8, 5))
	th.set_font("font", "LangButtonOn", bold)
	th.set_font_size("font_size", "LangButtonOn", 12)
	th.set_color("font_color", "LangButtonOn", p["accent"])
	th.set_color("font_hover_color", "LangButtonOn", p["accent"])
	th.set_color("font_pressed_color", "LangButtonOn", p["accent"])
	th.set_color("font_focus_color", "LangButtonOn", p["accent"])

	# ---------------- 对局面板 ----------------
	for side in ["W", "B"]:
		var variation: String = "Pane" + str(side)
		var face: Color = p[side.to_lower() + "_face"]
		th.set_type_variation(variation, "Button")
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var bg := face
			if state == "pressed":
				bg = face.darkened(0.06)
			elif state == "hover":
				bg = face
			th.set_stylebox(state, variation, box(bg, p["pane_edge"], 0, 1 if p["pane_edge"].a > 0.0 else 0, 0, 0))
		th.set_font_size("font_size", variation, 1)

	# ---------------- 卡片内部的派生文本 ----------------
	th.set_type_variation("CardTitle", "Label")
	th.set_font("font", "CardTitle", bold)
	th.set_font_size("font_size", "CardTitle", 15)
	th.set_color("font_color", "CardTitle", p["fg_soft"])

	th.set_type_variation("HeadTitle", "Label")
	th.set_font("font", "HeadTitle", bold)
	th.set_font_size("font_size", "HeadTitle", 19)
	th.set_color("font_color", "HeadTitle", p["fg"])

	th.set_type_variation("SubTitle", "Label")
	th.set_font_size("font_size", "SubTitle", 11)
	th.set_color("font_color", "SubTitle", p["muted"])

	th.set_type_variation("MutedLabel", "Label")
	th.set_font_size("font_size", "MutedLabel", 12)
	th.set_color("font_color", "MutedLabel", p["muted"])

	th.set_type_variation("FieldLabel", "Label")
	th.set_font_size("font_size", "FieldLabel", 12)
	th.set_color("font_color", "FieldLabel", p["muted"])

	th.set_type_variation("SummaryLabel", "Label")
	th.set_font_size("font_size", "SummaryLabel", 13)
	th.set_color("font_color", "SummaryLabel", p["fg_soft"])

	th.set_type_variation("SunkenPanel", "PanelContainer")
	th.set_stylebox("panel", "SunkenPanel", box(p["sunken"], p["line"], 10, 1, 12, 9))

	th.set_type_variation("SegPanel", "PanelContainer")
	th.set_stylebox("panel", "SegPanel", box(p["sunken"], p["line"], 12, 1, 4, 4))

	th.set_type_variation("OverlayCard", "PanelContainer")
	th.set_stylebox("panel", "OverlayCard", box(p["card"], p["line"], 20, 1, 22, 22))

	th.set_type_variation("ToastPanel", "PanelContainer")
	th.set_stylebox("panel", "ToastPanel", box(Color(p["card"].r, p["card"].g, p["card"].b, 0.97), p["line"], 12, 1, 16, 11))

	th.set_type_variation("FooterPanel", "PanelContainer")
	th.set_stylebox("panel", "FooterPanel", box(p["sunken"], p["line"], 0, 0, 16, 12))
	var f: StyleBoxFlat = th.get_stylebox("panel", "FooterPanel")
	f.border_width_top = 1

	# ---------------- 输入控件 ----------------
	th.set_stylebox("normal", "LineEdit", box(p["field_bg"], p["line"], 10, 1, 12, 10))
	th.set_stylebox("focus", "LineEdit", box(p["field_bg"], p["accent"], 10, 2, 12, 10))
	th.set_stylebox("read_only", "LineEdit", box(p["sunken"], p["line"], 10, 1, 12, 10))
	th.set_font("font", "LineEdit", ui)
	th.set_font_size("font_size", "LineEdit", 16)
	th.set_color("font_color", "LineEdit", p["fg"])
	th.set_color("font_placeholder_color", "LineEdit", p["muted"])
	th.set_color("caret_color", "LineEdit", p["accent"])
	th.set_color("selection_color", "LineEdit", Color(p["accent"].r, p["accent"].g, p["accent"].b, 0.35))

	th.set_type_variation("FieldEdit", "LineEdit")
	th.set_font("font", "FieldEdit", mono)
	th.set_font_size("font_size", "FieldEdit", 16)

	th.set_stylebox("normal", "OptionButton", box(p["field_bg"], p["line"], 10, 1, 12, 9))
	th.set_stylebox("hover", "OptionButton", box(p["field_bg"].lightened(0.06), p["accent"], 10, 1, 12, 9))
	th.set_stylebox("pressed", "OptionButton", box(p["field_bg"].darkened(0.06), p["accent"], 10, 1, 12, 9))
	th.set_stylebox("focus", "OptionButton", box(p["field_bg"], p["accent"], 10, 2, 12, 9))
	th.set_font("font", "OptionButton", ui)
	th.set_font_size("font_size", "OptionButton", 14)
	th.set_color("font_color", "OptionButton", p["fg"])
	th.set_color("font_hover_color", "OptionButton", p["fg"])
	th.set_color("font_pressed_color", "OptionButton", p["fg"])
	th.set_color("font_focus_color", "OptionButton", p["fg"])

	th.set_stylebox("panel", "PopupMenu", box(p["card"], p["line"], 10, 1, 6, 6))
	th.set_stylebox("hover", "PopupMenu", box(p["accent"], Color(0, 0, 0, 0), 6, 0, 6, 4))
	th.set_color("font_color", "PopupMenu", p["fg"])
	th.set_color("font_hover_color", "PopupMenu", p["accent_ink"])
	th.set_color("font_separator_color", "PopupMenu", p["muted"])
	th.set_font_size("font_size", "PopupMenu", 14)

	th.set_color("font_color", "CheckBox", p["fg"])
	th.set_color("font_hover_color", "CheckBox", p["fg"])
	th.set_color("font_pressed_color", "CheckBox", p["fg"])
	th.set_color("font_focus_color", "CheckBox", p["fg"])
	th.set_font_size("font_size", "CheckBox", 13)
	th.set_constant("h_separation", "CheckBox", 10)

	# ---------------- 棋钟页 ----------------
	th.set_type_variation("SideTag", "Label")
	th.set_font("font", "SideTag", bold)
	th.set_font_size("font_size", "SideTag", 12)
	th.set_color("font_color", "SideTag", p["fg"])

	th.set_type_variation("ChipLabel", "Label")
	th.set_font("font", "ChipLabel", bold)
	th.set_font_size("font_size", "ChipLabel", 10)
	th.set_color("font_color", "ChipLabel", p["fg"])

	th.set_type_variation("FootLabel", "Label")
	th.set_font("font", "FootLabel", mono)
	th.set_font_size("font_size", "FootLabel", 11)
	th.set_color("font_color", "FootLabel", p["fg"])

	th.set_type_variation("TimeLabel", "Label")
	th.set_font("font", "TimeLabel", mono)
	th.set_font_size("font_size", "TimeLabel", 120)
	th.set_color("font_color", "TimeLabel", p["fg"])

	th.set_type_variation("PausedBadge", "PanelContainer")
	th.set_stylebox("panel", "PausedBadge", box(Color(6.0 / 255.0, 9.0 / 255.0, 14.0 / 255.0, 0.92),
		p["line"], 999, 1, 22, 10))

	th.set_type_variation("PausedLabel", "Label")
	th.set_font("font", "PausedLabel", bold)
	th.set_font_size("font_size", "PausedLabel", 17)
	th.set_color("font_color", "PausedLabel", p["warn"])

	th.set_type_variation("ActiveRing", "Panel")
	var ring := box(Color(0, 0, 0, 0), p["accent"], 12, 3, 0, 0)
	ring.draw_center = false
	th.set_stylebox("panel", "ActiveRing", ring)

	th.set_type_variation("OverlayDim", "Panel")
	th.set_stylebox("panel", "OverlayDim", box(Color(4.0 / 255.0, 6.0 / 255.0, 10.0 / 255.0, 0.86),
		Color(0, 0, 0, 0), 0, 0, 0, 0))

	th.set_type_variation("OverlayIcon", "Label")
	th.set_font_size("font_size", "OverlayIcon", 30)
	th.set_color("font_color", "OverlayIcon", p["muted"])

	th.set_type_variation("OverlayTitle", "Label")
	th.set_font("font", "OverlayTitle", bold)
	th.set_font_size("font_size", "OverlayTitle", 24)
	th.set_color("font_color", "OverlayTitle", p["fg"])

	th.set_type_variation("OverlaySub", "Label")
	th.set_font("font", "OverlaySub", bold)
	th.set_font_size("font_size", "OverlaySub", 17)
	th.set_color("font_color", "OverlaySub", p["accent"])

	th.set_type_variation("OverlayDetail", "Label")
	th.set_font_size("font_size", "OverlayDetail", 12)
	th.set_color("font_color", "OverlayDetail", p["muted"])

	return th
