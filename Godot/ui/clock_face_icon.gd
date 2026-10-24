class_name ClockFaceIcon
extends Control
## clock_face_icon.gd — 结算层上那个小钟面
##
## 网页版这里是一个 emoji「⏱」。emoji 在各个平台上会被渲染成彩色位图，
## 既没法跟主题配色统一，大小也不稳，所以原生版改成用代码画一个表盘：
## 一个圆 + 时针 + 分针，颜色跟着主题走。

var color := Color(0.55, 0.6, 0.68)
var stroke := 2.5


func _ready() -> void:
	custom_minimum_size = Vector2(36, 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.42
	draw_arc(center, radius, 0.0, TAU, 48, color, stroke, true)
	# 时针指向上方 7 点方向、分针指向 2 点方向：一眼能看出是钟
	draw_line(center, center + Vector2(-radius * 0.30, -radius * 0.42), color, stroke, true)
	draw_line(center, center + Vector2(radius * 0.40, radius * 0.16), color, stroke, true)
	draw_circle(center, stroke * 0.9, color)
