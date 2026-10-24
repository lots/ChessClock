class_name ByoyomiBar
extends Control
## byoyomi_bar.gd — 读秒段数指示条（只在对局模式为 Byoyomi 时显示）
##
## 一条由 N 个小段组成的条：左边是**还剩几段**（绿色），右边是**已经用掉几段**（红色）。
## 主时间阶段还有全部段数 → 整条都是绿的；读秒阶段每跨过一段就红掉一段；
## 段数用尽（判负）时整条都红。
##
## **正在倒计时的那一段是「进度条」**：读秒窗口里时间用掉多少，这一段就从右往左红多少
## （20 秒的窗口剩 5 秒 → 75% 红、25% 绿）；窗口用完时整段变红，然后轮到下一段。
## 红色的部分始终贴着右边那些「已经用掉」的段，所以整条读起来是「从右往左烧」。
##
## 它是纯绘制控件（_draw），不建子节点 —— 段数最多 20，
## 每帧只重画一次，比维护 20 个 Panel 便宜。

var total := 3
var left := 3
## 正在倒计时的那一段还剩多少（0..1）；< 0 = 没有段在倒计时（主时间阶段 / 已判负）
var active_left := -1.0
var fill_color := Color(0.18, 0.75, 0.44)
var empty_color := Color(1.0, 0.3, 0.31)

const GAP := 6.0
const RADIUS_MAX := 4.0

var _sb_fill: StyleBoxFlat
var _sb_empty: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## total / left 变了才重画；active_left 是浮点，单独判「变化够不够明显」避免每帧重画
func set_state(p_total: int, p_left: int, p_active_left: float = -1.0) -> void:
	p_total = maxi(1, p_total)
	p_left = clampi(p_left, 0, p_total)
	var changed := (p_total != total or p_left != left)
	var a := clampf(p_active_left, -1.0, 1.0)
	if not changed and absf(a - active_left) < 0.002:
		return
	total = p_total
	left = p_left
	active_left = a
	queue_redraw()


func set_colors(p_fill: Color, p_empty: Color) -> void:
	if p_fill == fill_color and p_empty == empty_color:
		return
	fill_color = p_fill
	empty_color = p_empty
	queue_redraw()


func _ensure_boxes() -> void:
	var radius := int(minf(RADIUS_MAX, size.y * 0.5))
	if _sb_fill == null:
		_sb_fill = StyleBoxFlat.new()
		_sb_empty = StyleBoxFlat.new()
		for sb in [_sb_fill, _sb_empty]:
			sb.set_border_width_all(0)
			sb.set_content_margin_all(0)
	for sb in [_sb_fill, _sb_empty]:
		sb.set_corner_radius_all(radius)
	_sb_fill.bg_color = fill_color
	_sb_empty.bg_color = empty_color


func _draw() -> void:
	if total <= 0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var gap: float = minf(GAP, size.x * 0.06)
	var seg_w: float = (size.x - gap * float(total - 1)) / float(total)
	if seg_w <= 0.0:
		return
	_ensure_boxes()
	# 正在倒计时的是「最后一段绿」，它的右边接着那些已经红掉的段
	var active_idx := (left - 1) if (active_left >= 0.0 and left > 0) else -1
	for i in total:
		var x := float(i) * (seg_w + gap)
		var box := Rect2(x, 0.0, seg_w, size.y)
		if i == active_idx:
			# 左绿（剩余比例）右红（已用比例）：红的贴着右边，整条像从右往左烧
			var keep: float = clampf(active_left, 0.0, 1.0) * seg_w
			draw_style_box(_sb_fill, Rect2(x, 0.0, keep, size.y))
			if keep < seg_w:
				draw_style_box(_sb_empty, Rect2(x + keep, 0.0, seg_w - keep, size.y))
		else:
			draw_style_box(_sb_fill if i < left else _sb_empty, box)
