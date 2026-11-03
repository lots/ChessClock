class_name ClockLogos
extends RefCounted
## logos.gd — 标志循环（点一下换成下一个），与网页版 app.js 的 LOGO_ORDER / LOGO_FILES 一一对应
##
##    TARUMT → CoQ → Chess → 围棋 → MWA → 回到 TARUMT
##
## 每一项的 name 是 i18n 里的标志名 key；brand / strip 分别是
## 设置页 96×96 与操作条 48×48 用的位图（TARUMT 沿用原来那张原图，其余用网页版导出的
## 512 / 192 档，位置在 assets/logos/）。
## 当前选的是哪一项存在存档里（cfg.logo），关掉再打开保持不变。

const ORDER := ["tarumt", "coq", "chess", "weiqi", "mwa"]

const FILES := {
	"tarumt": {
		"name": "logo.name.tarumt",
		"brand": "res://assets/logo-brand.png",
		"strip": "res://assets/logo-strip.png",
	},
	"coq": {
		"name": "logo.name.coq",
		"brand": "res://assets/logos/brand_coq.png",
		"strip": "res://assets/logos/strip_coq.png",
	},
	"chess": {
		"name": "logo.name.chess",
		"brand": "res://assets/logos/brand_chess.png",
		"strip": "res://assets/logos/strip_chess.png",
	},
	"weiqi": {
		"name": "logo.name.weiqi",
		"brand": "res://assets/logos/brand_weiqi.png",
		"strip": "res://assets/logos/strip_weiqi.png",
	},
	"mwa": {
		"name": "logo.name.mwa",
		"brand": "res://assets/logos/brand_mwa.png",
		"strip": "res://assets/logos/strip_mwa.png",
	},
}


## 不认识的值回落到第一项（存档里可能是旧版 / 手改的值）
static func normalize(value) -> String:
	var id := str(value)
	return id if FILES.has(id) else ORDER[0]


## 下一个标志（到头绕回第一项）
static func next_id(value) -> String:
	var idx: int = ORDER.find(normalize(value))
	return ORDER[(idx + 1) % ORDER.size()]


static func name_key(value) -> String:
	return str(FILES[normalize(value)]["name"])


static func brand_path(value) -> String:
	return str(FILES[normalize(value)]["brand"])


static func strip_path(value) -> String:
	return str(FILES[normalize(value)]["strip"])
