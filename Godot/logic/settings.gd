class_name ClockSettings
extends RefCounted
## settings.gd — 设置持久化与引擎配置换算（网页版 app.js 的 DEFAULTS / loadSettings /
## saveSettings / engineConfig / describeConfig 移植）
##
## 存档就是一份 JSON，键名与网页版 localStorage 里的 chessclock.settings.v1 完全一致，
## 所以两个版本的存档语义可以逐字段对照（tests/project_spec.js 会核对默认值）。

const FILE_PATH := "user://chessclock_settings.json"

## 实际使用的存档路径。测试会把它指向另一份文件，避免跑一次测试就把用户的设置改了
static var file_path := FILE_PATH

const DEFAULTS := {
	"mode": "byoyomi",        ## 首次打开：围棋读秒制
	"baseMin": 10,
	"incSec": 20,             ## 读秒每手 20 秒
	"periods": 3,             ## 共 3 段
	"presetId": "10+3x20",    ## = 10+3×20
	"sound": true,
	"facing": true,
	"swapped": false,         ## 「交换两侧位置」：false = 默认（竖屏上黑下白 / 横屏左黑右白）
	"keepAwake": true,
	"lang": "en",             ## 首次打开：英文
	"theme": "dark",          ## 深色（最初那套配色）为默认
}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## 读存档；文件不存在 / 损坏 / 权限问题都静默回落到默认值
static func load_from(path := "") -> Dictionary:
	if path == "":
		path = file_path
	var out := defaults()
	if not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for key in DEFAULTS.keys():
		if parsed.has(key) and parsed[key] != null:
			out[key] = parsed[key]
	return out


static func save_to(cfg: Dictionary, path := "") -> bool:
	if path == "":
		path = file_path
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("无法写入设置文件：" + path)
		return false
	file.store_string(JSON.stringify(cfg, "  "))
	file.close()
	return true


## 把任意来源（存档 / 界面输入）的设置夹到合法区间
static func normalize(cfg: Dictionary) -> Dictionary:
	var mode: String = str(cfg.get("mode", DEFAULTS["mode"]))
	if mode not in ClockEngine.MODES.values():
		mode = DEFAULTS["mode"]
	var is_byo := mode == ClockEngine.MODES.BYOYOMI
	var lang := ClockI18n.normalize(cfg.get("lang", DEFAULTS["lang"]))
	if lang == "":
		lang = DEFAULTS["lang"]
	# 读秒模式下「主时间」与「读秒秒数」各可以是 0，但不能同时是 0：
	#   0 主时间 + N 秒读秒 = 纯读秒（每一手都从读秒那一格开始）
	#   M 分钟 + 0 秒读秒   = 只有主时间，用完即负（等价于包干制）
	#   其它模式没有第二个数兜底，主时间仍然至少 1 分钟。
	var base_min := ClockEngine.clamp_int(cfg.get("baseMin"), 1 if not is_byo else 0, 180,
		DEFAULTS["baseMin"])
	var inc_sec := ClockEngine.clamp_int(cfg.get("incSec"), 0, 180, DEFAULTS["incSec"])
	# 两个都 0（或非读秒模式的主时间 0）→ 回落到 1 分钟
	if base_min <= 0 and (not is_byo or inc_sec <= 0):
		base_min = 1
	return {
		"mode": mode,
		"baseMin": base_min,
		"incSec": inc_sec,
		"periods": ClockEngine.clamp_int(cfg.get("periods"), 1, ClockEngine.MAX_PERIODS, DEFAULTS["periods"]),
		"presetId": cfg.get("presetId", null),
		"sound": bool(cfg.get("sound", DEFAULTS["sound"])),
		"facing": bool(cfg.get("facing", DEFAULTS["facing"])),
		"swapped": bool(cfg.get("swapped", DEFAULTS["swapped"])),
		"keepAwake": bool(cfg.get("keepAwake", DEFAULTS["keepAwake"])),
		"lang": lang,
		"theme": ClockTheme.normalize(cfg.get("theme", DEFAULTS["theme"])),
	}


## 设置 → 引擎配置（与网页版 engineConfig() 同一套换算）
static func engine_config(cfg: Dictionary) -> Dictionary:
	var add_sec := ClockEngine.clamp_int(cfg.get("incSec"), 0, 180, 0)
	return {
		"mode": cfg.get("mode", DEFAULTS["mode"]),
		"baseMs": ClockEngine.clamp_int(cfg.get("baseMin"), 0, 180, DEFAULTS["baseMin"]) * 60000,
		"incMs": add_sec * 1000,
		"delayMs": add_sec * 1000,
		"byoyomiMs": add_sec * 1000,
		"byoyomiPeriods": ClockEngine.clamp_int(cfg.get("periods"), 1, 20, DEFAULTS["periods"]),
	}


## 本局用时的可读描述（在界面层拼，因为引擎是纯逻辑、不带语言）：
##   中文「10 分钟 + 读秒 20 秒 × 3 段 · Byoyomi 读秒」
##   英文「10 min + byoyomi 20s × 3 · Byoyomi」
static func summary(lang: String, cfg: Dictionary) -> String:
	var c := engine_config(cfg)
	var base := int(round(c["baseMs"] / 60000.0))
	var add := int(round(int(c["incMs"]) / 1000.0))
	if c["mode"] == ClockEngine.MODES.BYOYOMI:
		var periods := ""
		if int(c["byoyomiPeriods"]) > 1:
			periods = ClockI18n.t(lang, "summary.byoyomi.periods", {"n": c["byoyomiPeriods"]})
		# 0 主时间 = 纯读秒；0 秒读秒 = 只有主时间
		if int(c["baseMs"]) <= 0:
			return ClockI18n.t(lang, "summary.byoyomi.pure", {"add": add, "periods": periods})
		if int(c["byoyomiMs"]) <= 0:
			return ClockI18n.t(lang, "summary.byoyomi.mainonly", {"base": base})
		return ClockI18n.t(lang, "summary.byoyomi", {"base": base, "add": add, "periods": periods})
	if c["mode"] == ClockEngine.MODES.DELAY:
		return ClockI18n.t(lang, "summary.delay", {"base": base, "add": add})
	if c["mode"] == ClockEngine.MODES.SUDDEN:
		return ClockI18n.t(lang, "summary.sudden", {"base": base})
	return ClockI18n.t(lang, "summary.fischer", {"base": base, "add": add})
