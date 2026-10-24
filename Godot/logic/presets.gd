class_name ClockPresets
extends RefCounted
## presets.gd — 常用比赛用时（网页版 app.js 的 PRESETS_CHESS / PRESETS_BYOYOMI 移植）
##
## name 是 i18n 的 key，不是显示文字。
## tests/project_spec.js 会把这两张表与 ../app.js 逐档比对，防止两边漂移。

## 国际象棋类（Fischer 加秒 / Bronstein 延时 / 无加秒共用）
const CHESS := [
	{"id": "1+0", "baseMin": 1, "incSec": 0, "name": "preset.bullet"},
	{"id": "3+2", "baseMin": 3, "incSec": 2, "name": "preset.blitz"},
	{"id": "5+0", "baseMin": 5, "incSec": 0, "name": "preset.rapid"},
	{"id": "5+3", "baseMin": 5, "incSec": 3, "name": "preset.rapid"},
	{"id": "10+0", "baseMin": 10, "incSec": 0, "name": "preset.rapid"},
	{"id": "10+5", "baseMin": 10, "incSec": 5, "name": "preset.rapid"},
	{"id": "15+10", "baseMin": 15, "incSec": 10, "name": "preset.rapid"},
	{"id": "25+10", "baseMin": 25, "incSec": 10, "name": "preset.classical"},
	{"id": "30+0", "baseMin": 30, "incSec": 0, "name": "preset.classical"},
	{"id": "60+30", "baseMin": 60, "incSec": 30, "name": "preset.classical"},
	{"id": "90+30", "baseMin": 90, "incSec": 30, "name": "preset.classical"},
]

## 围棋（Byoyomi）常用制式。记法：基础时间 + 段数 × 每手秒数
##（10+3×20 = 主时间 10 分钟；之后每手 20 秒、共 3 段，可超时思考 2 次，第 3 次判负）。
## 注意：这里**刻意没有** sub 字段。下拉框里只写主记法「10+3×20」——
## 它已经把主时间 / 段数 / 每手秒数都写全了，再补一句「20s × 3」只是同样的三个数换个顺序，
## 在单行的下拉框里反而让人以为还有别的含义。（棋类那组保留第二段，因为那是「档次」。）
const BYOYOMI := [
	{"id": "5+3x20", "baseMin": 5, "incSec": 20, "periods": 3},
	{"id": "10+3x20", "baseMin": 10, "incSec": 20, "periods": 3},
	{"id": "10+3x30", "baseMin": 10, "incSec": 30, "periods": 3},
	{"id": "15+3x30", "baseMin": 15, "incSec": 30, "periods": 3},
	{"id": "20+5x30", "baseMin": 20, "incSec": 30, "periods": 5},
	{"id": "30+5x30", "baseMin": 30, "incSec": 30, "periods": 5},
	{"id": "30+3x60", "baseMin": 30, "incSec": 60, "periods": 3},
	{"id": "60+5x60", "baseMin": 60, "incSec": 60, "periods": 5},
]


## 当前模式下该显示哪一组预设
static func for_mode(mode: String) -> Array:
	return BYOYOMI if mode == ClockEngine.MODES.BYOYOMI else CHESS


## 预设按钮上的主记法：10+5 / 10+3×20
static func label(p: Dictionary) -> String:
	if p.has("periods"):
		return "%d+%d×%d" % [p["baseMin"], p["periods"], p["incSec"]]
	return "%d+%d" % [p["baseMin"], p["incSec"]]


## 当前三个数字是否正好是某个读秒预设（切模式时决定要不要给 10+3×20 的兜底默认值）
static func is_byoyomi_preset(cfg: Dictionary) -> bool:
	for p in BYOYOMI:
		if int(p["baseMin"]) == int(cfg.get("baseMin", -1)) \
				and int(p["incSec"]) == int(cfg.get("incSec", -1)) \
				and int(p["periods"]) == int(cfg.get("periods", -1)):
			return true
	return false


## 与当前数字匹配的预设 id（没有就返回 ""）
static func match_id(mode: String, cfg: Dictionary) -> String:
	for p in for_mode(mode):
		if int(p["baseMin"]) == int(cfg.get("baseMin", -1)) \
				and int(p["incSec"]) == int(cfg.get("incSec", -1)) \
				and (not p.has("periods") or int(p["periods"]) == int(cfg.get("periods", -1))):
			return str(p["id"])
	return ""
