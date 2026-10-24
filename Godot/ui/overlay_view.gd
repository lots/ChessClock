class_name ResultOverlay
extends Control
## overlay_view.gd — 超时结算层 / 返回确认（网页版 #overlay 与 window.confirm 的移植）
##
## 一招两用：overlay.show_result(side) 显示「谁超时、谁获胜」，
## overlay.show_confirm(text) 显示「返回设置会结束当前对局，确定吗？」。

signal rematch_requested
signal back_requested
signal confirmed

var app: Node

var _dim: Panel
var _card: PanelContainer
var _icon: ClockFaceIcon
var _title: Label
var _sub: Label
var _detail: Label
var _actions: VBoxContainer
var _primary: Button
var _secondary: Button
var _mode := "result"


func t(key: String, vars: Dictionary = {}) -> String:
	return app.t(key, vars)


func _ready() -> void:
	build()


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_dim = Panel.new()
	_dim.theme_type_variation = "OverlayDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.fill(_dim))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var pad := UiKit.margin(20, 20, 20, 20)
	center.add_child(pad)

	_card = UiKit.panel("OverlayCard")
	_card.custom_minimum_size = Vector2(320, 0)
	pad.add_child(_card)

	var box := UiKit.vbox(4)
	_card.add_child(box)

	_icon = ClockFaceIcon.new()
	_icon.color = app.palette["muted"]
	var icon_wrap := CenterContainer.new()
	icon_wrap.custom_minimum_size.y = 40
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(_icon)
	box.add_child(icon_wrap)

	_title = UiKit.label("", "OverlayTitle")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)

	_sub = UiKit.label("", "OverlaySub")
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)

	_detail = UiKit.label("", "OverlayDetail")
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail)

	_actions = UiKit.vbox(10)
	_actions.custom_minimum_size.y = 12
	box.add_child(_actions)

	_primary = UiKit.button("", "AccentButton")
	_primary.custom_minimum_size.y = 46
	_primary.pressed.connect(_on_primary)
	_actions.add_child(_primary)

	_secondary = UiKit.button("", "Btn")
	_secondary.custom_minimum_size.y = 42
	_secondary.pressed.connect(_on_secondary)
	_actions.add_child(_secondary)


func show_result(side: String, moves: int, summary: String) -> void:
	_mode = "result"
	var side_label: String = t("side." + side)
	var other_label: String = t("side." + ClockEngine.other(side))
	_icon.visible = true
	_title.text = t("overlay.title", {"side": side_label})
	_sub.text = t("overlay.sub", {"side": other_label})
	_sub.visible = true
	_detail.text = summary + " · " + (t("detail.moveOne") if moves == 1 else t("detail.moves", {"n": moves}))
	_detail.visible = true
	_primary.text = t("overlay.rematch")
	_primary.theme_type_variation = "AccentButton"
	_secondary.text = t("overlay.back")
	_secondary.theme_type_variation = "Btn"
	visible = true


## 确认框：把「继续对局」放在显眼的蓝按钮上，
## 要结束一局必须去点下面那颗灰按钮 —— 棋钟上误触一次就毁一局，值得多这一道。
func show_confirm(text: String) -> void:
	_mode = "confirm"
	_icon.visible = true
	_title.text = text
	_sub.visible = false
	_detail.visible = false
	_primary.text = t("confirm.no")
	_primary.theme_type_variation = "AccentButton"
	_secondary.text = t("confirm.yes")
	_secondary.theme_type_variation = "Btn"
	visible = true


func hide_overlay() -> void:
	visible = false


func apply_palette() -> void:
	if _icon != null:
		_icon.color = app.palette["muted"]
		_icon.queue_redraw()


func _on_primary() -> void:
	if _mode == "result":
		rematch_requested.emit()
	# 确认框里的主按钮是「继续对局」= 取消，什么都不做
	hide_overlay()


func _on_secondary() -> void:
	hide_overlay()
	if _mode == "result":
		back_requested.emit()
	else:
		confirmed.emit()
