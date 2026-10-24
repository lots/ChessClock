class_name ClockEngine
extends RefCounted
## engine.gd — 计时引擎（网页版 engine.js 的 GDScript 逐行移植）
##
## 设计原则（与网页版一字不差）：
##  1) 纯逻辑，不依赖任何节点 / 场景树；
##  2) 不自己读取系统时间，所有函数都要求调用方注入 now（毫秒时间戳），
##     因此可以在无头模式下以任意时间步进做单元测试；
##  3) 时间只在「按键换手 / 暂停」的瞬间结算，倒计时永远由
##        剩余 = 已入账时间 - (now - 本手开始时刻)
##     实时算出。这样即使程序被切到后台、定时器被系统冻结，
##     回到前台后剩余时间与超时判定依然完全正确（不会白送时间）。
##
## 读秒（Byoyomi）模型：
##  读秒不是状态机，而是一条连续的「窗口」：
##    主时间余额 > 0                    → 还在主时间阶段；
##    主时间用完后，每 X 秒一个窗口，窗口重置 = 消耗一段；
##    已消耗段数 = floor(读秒已用时间 / X)；
##    已消耗段数 ≥ 本局拥有的段数        → 判负。
##  于是「5 段 × 30 秒 = 可以超时思考 4 次，第 5 次判负」「每步重新满格」
##  都是同一行算术的自然结果，也便于写测试。
##
## 状态的形状与 JS 版完全一致（用 Dictionary 代替对象，语义相同）：
##  {
##    cfg:      {mode, baseMs, incMs, delayMs, byoyomiMs, byoyomiPeriods},
##    ms:       {w, b},     已经入账的主时间（不含当前这一手正在流逝的部分）
##    periods:  {w, b},     剩余读秒段数
##    active:   "w" | "b" | "",
##    running / paused / started / finished: bool,
##    turnStart: int,  moves: {w, b},  flagged: "w" | "b" | "",
##    lastPressAt: int
##  }

## 计时模式
const MODES := {
	"FISCHER": "fischer",  ## 费舍尔加秒：每走完一步，立即给自己加上固定秒数
	"DELAY": "delay",      ## 布朗斯坦延时：每步开始后的前 N 秒不计时
	"BYOYOMI": "byoyomi",  ## 读秒：主时间用完后，每一手重新给固定的 X 秒（可多段）
	"SUDDEN": "sudden",    ## 无加秒（突然死亡）
}

const MODE_LABELS := {
	"fischer": "Fischer 加秒",
	"delay": "Bronstein 延时",
	"byoyomi": "Byoyomi 读秒",
	"sudden": "无加秒（突然死亡）",
}

const LOW_TIME_MS := 60000       ## 低于 1 分钟：黄色警示
const CRITICAL_TIME_MS := 20000  ## 低于 20 秒：红色警示 + 显示十分之一秒
const MIN_PRESS_GAP_MS := 40     ## 防止同一次触摸被重复投递

const SIDES := ["w", "b"]
const MIN_BASE_MS := 1000
const MAX_BASE_MS := 6 * 60 * 60 * 1000  ## 6 小时上限
const MAX_ADD_MS := 180 * 1000           ## 单步加/延时/读秒上限 180 秒
## 读秒**不为 0** 时的最小粒度。0 是合法值，含义是「没有读秒」（只剩主时间，用完即负），
## 所以用法是「> 0 时不得小于 1 秒」，而不是「不得小于 1 秒」。
const MIN_BYOYOMI_MS := 1000
const MAX_PERIODS := 20                  ## 读秒段数上限

## 「还没有按过」：相当于 JS 的 -Infinity，但要留在 int64 里
const NO_PRESS := -1000000000000000000


static func other(side: String) -> String:
	return "b" if side == "w" else "w"


## 把任意输入转成浮点数；取不到就给 NAN（交给 fallback 处理）
static func _to_number(value) -> float:
	match typeof(value):
		TYPE_INT:
			return float(value)
		TYPE_FLOAT:
			return value
		TYPE_BOOL:
			return 1.0 if value else 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var s := String(value).strip_edges()
			return s.to_float() if s.is_valid_float() else NAN
	return NAN


static func clamp_int(value, lo: int, hi: int, fallback: int) -> int:
	var n := _to_number(value)
	if is_nan(n) or is_inf(n):
		n = float(fallback)
	var rounded := int(round(n))
	return clampi(rounded, lo, hi)


## 取第一个「有给值」的参数（null / 缺省视为没给）
static func first_number(values: Array):
	for v in values:
		if v != null:
			return v
	return null


## 规范化配置，保证引擎内部数值始终合法
static func normalize_config(config) -> Dictionary:
	if typeof(config) != TYPE_DICTIONARY:
		config = {}
	var mode: String = MODES.FISCHER
	var cfg_mode = config.get("mode")
	if cfg_mode in MODES.values():
		mode = cfg_mode

	# 主时间可以给 0（读秒模式下的「纯读秒」），但**非零时必须 ≥ 1 秒**
	var base_ms := clamp_int(config.get("baseMs"), 0, MAX_BASE_MS, 5 * 60000)
	if base_ms > 0 and base_ms < MIN_BASE_MS:
		base_ms = MIN_BASE_MS

	# 按模式优先取对应的字段：这样把「已归一化的配置」再传进来也是幂等的
	#（归一化后的 byoyomi 配置里 incMs 恒为 0，若先看 incMs 会把读秒读成 0）
	var raw_add
	if mode == MODES.BYOYOMI:
		raw_add = first_number([config.get("byoyomiMs"), config.get("incMs"), config.get("delayMs")])
	elif mode == MODES.DELAY:
		raw_add = first_number([config.get("delayMs"), config.get("incMs"), config.get("byoyomiMs")])
	else:
		raw_add = first_number([config.get("incMs"), config.get("byoyomiMs"), config.get("delayMs")])
	var add_ms := clamp_int(raw_add, 0, MAX_ADD_MS, 0)

	var raw_periods = config.get("byoyomiPeriods")
	if raw_periods == null:
		raw_periods = config.get("periods")
	var periods := clamp_int(raw_periods, 1, MAX_PERIODS, 1)

	var byoyomi_ms := add_ms if mode == MODES.BYOYOMI else 0

	# 读秒模式的两个数各可以是 0，但不能同时是 0：
	#   主时间 0 + 读秒 N 秒   = 纯读秒（每一手都从读秒那一格开始）
	#   主时间 M 分 + 读秒 0 秒 = 只有主时间（用完即负，等价于包干制）
	#   两个都 0 = 什么都不剩，没有意义 → 回落到 1 分钟主时间。
	if mode == MODES.BYOYOMI:
		if base_ms <= 0 and byoyomi_ms <= 0:
			base_ms = 60000
		if byoyomi_ms > 0 and byoyomi_ms < MIN_BYOYOMI_MS:
			byoyomi_ms = MIN_BYOYOMI_MS
	elif base_ms < MIN_BASE_MS:
		# 其它模式没有「另一个数」可以兜底，主时间必须 ≥ 1 秒
		base_ms = MIN_BASE_MS

	return {
		"mode": mode,
		"baseMs": base_ms,
		"incMs": add_ms if mode == MODES.FISCHER else 0,
		"delayMs": add_ms if mode == MODES.DELAY else 0,
		"byoyomiMs": byoyomi_ms,
		"byoyomiPeriods": periods if mode == MODES.BYOYOMI else 1,
	}


## 建立一局新棋（未启动状态，等待第一次 start/press）
static func new_game(config) -> Dictionary:
	var cfg := normalize_config(config)
	return {
		"cfg": cfg,
		"ms": {"w": cfg["baseMs"], "b": cfg["baseMs"]},
		"periods": {"w": cfg["byoyomiPeriods"], "b": cfg["byoyomiPeriods"]},
		"active": "",
		"running": false,
		"paused": false,
		"started": false,
		"turnStart": 0,
		"moves": {"w": 0, "b": 0},
		"flagged": "",
		"finished": false,
		"lastPressAt": NO_PRESS,
	}


## 当前这一手已经「消耗」掉多少毫秒（延时模式下先白送 delayMs）
static func elapsed_charged(state: Dictionary, now: int) -> int:
	var raw := maxi(0, now - int(state["turnStart"]))
	var delay: int = int(state["cfg"]["delayMs"]) if state["cfg"]["mode"] == MODES.DELAY else 0
	if delay > 0:
		raw = maxi(0, raw - delay)
	return raw


## 某一方此刻的主时间余额（毫秒）。
## 只有「正在走棋的一方」才会实时递减；读秒阶段该项恒为 0（读秒另见 readout）。
static func remaining_ms(state: Dictionary, side: String, now: int) -> int:
	if state["finished"]:
		return maxi(0, int(state["ms"][side]))
	if state["running"] and not state["paused"] and state["active"] == side:
		return maxi(0, int(state["ms"][side]) - elapsed_charged(state, now))
	return maxi(0, int(state["ms"][side]))


## 双方主时间之和（便于测试/统计）
static func total_remaining_ms(state: Dictionary, now: int) -> int:
	return remaining_ms(state, "w", now) + remaining_ms(state, "b", now)


## 读秒阶段的实时状态（仅 byoyomi 模式有意义）：
##   phase        "main" 主时间阶段 / "byoyomi" 读秒阶段
##   ms           界面该显示的毫秒数（读秒阶段 = 当前窗口剩余）
##   periodsLeft  剩余段数（0 = 已用尽，再超即判负）
##   windowIndex  已经重置了几个窗口（= 本手已消耗的段数），用于每秒提示音去重
static func byoyomi_state(state: Dictionary, side: String, now: int) -> Dictionary:
	var cfg: Dictionary = state["cfg"]
	var x: int = cfg["byoyomiMs"]
	var periods: int = state["periods"][side]

	# 读秒 0 秒 = 没有读秒：整局只算主时间，用完即负（与包干制一样）
	if x <= 0:
		return {
			"phase": "main",
			"ms": remaining_ms(state, side, now),
			"periodsLeft": 0,
			"windowIndex": 0,
		}

	if state["finished"] and state["flagged"] == side:
		return {"phase": "byoyomi", "ms": 0, "periodsLeft": 0, "windowIndex": 0}

	var live: bool = state["running"] and not state["paused"] and state["active"] == side
	if not live:
		if int(state["ms"][side]) > 0:
			return {"phase": "main", "ms": int(state["ms"][side]), "periodsLeft": periods, "windowIndex": 0}
		# 主时间已经没了，钟上预备好一格完整的读秒
		return {"phase": "byoyomi", "ms": x, "periodsLeft": periods, "windowIndex": 0}

	var elapsed := maxi(0, now - int(state["turnStart"]))
	var main_left := maxi(0, int(state["ms"][side]) - elapsed)
	if main_left > 0:
		return {"phase": "main", "ms": main_left, "periodsLeft": periods, "windowIndex": 0}

	var byo := maxi(0, elapsed - int(state["ms"][side]))
	var overruns := 0 if x <= 0 else int(floor(float(byo) / float(x)))
	var in_window := 0 if x <= 0 else byo - overruns * x
	return {
		"phase": "byoyomi",
		"ms": maxi(0, x - in_window),
		"periodsLeft": maxi(0, periods - overruns),
		"windowIndex": overruns,
	}


## 界面统一入口：不管什么模式，都返回 {phase, ms, periodsLeft, windowIndex}
static func readout(state: Dictionary, side: String, now: int) -> Dictionary:
	if state["cfg"]["mode"] == MODES.BYOYOMI:
		return byoyomi_state(state, side, now)
	return {
		"phase": "main",
		"ms": remaining_ms(state, side, now),
		"periodsLeft": null,
		"windowIndex": 0,
	}


## 开表：默认白方先走
static func start(state: Dictionary, now: int, side: String = "w") -> Dictionary:
	if state["finished"]:
		return {"type": "ignored", "reason": "finished"}
	if state["started"]:
		return {"type": "ignored", "reason": "already-started"}
	state["started"] = true
	state["running"] = true
	state["paused"] = false
	state["active"] = "b" if side == "b" else "w"
	state["turnStart"] = now
	return {"type": "start", "side": state["active"]}


## 这一手是否已经用光时间（读秒模式看段数，其它模式看主时间）
static func is_out_of_time(state: Dictionary, side: String, now: int) -> bool:
	if state["cfg"]["mode"] == MODES.BYOYOMI:
		# 没有读秒（0 秒）时判负依据是主时间，和包干制一样
		if int(state["cfg"]["byoyomiMs"]) <= 0:
			return remaining_ms(state, side, now) <= 0
		var info := byoyomi_state(state, side, now)
		return info["phase"] == "byoyomi" and int(info["periodsLeft"]) <= 0
	return remaining_ms(state, side, now) <= 0


## 结算读秒：把这一手跨过的读秒段数扣掉，主时间扣到 0
static func commit_byoyomi(state: Dictionary, side: String, now: int, consume_periods: bool) -> Dictionary:
	var cfg: Dictionary = state["cfg"]
	var elapsed := maxi(0, now - int(state["turnStart"]))
	var overrun_ms := maxi(0, elapsed - int(state["ms"][side]))
	var overruns := 0 if int(cfg["byoyomiMs"]) <= 0 else int(floor(float(overrun_ms) / float(cfg["byoyomiMs"])))
	if consume_periods and overruns > 0:
		state["periods"][side] = maxi(0, int(state["periods"][side]) - overruns)
	state["ms"][side] = maxi(0, int(state["ms"][side]) - elapsed)
	return {"overruns": overruns}


## 按下某一方的按键（走完一步）。
## 返回 {type: "move" | "start" | "flag" | "ignored", ...}
static func press(state: Dictionary, side: String, now: int) -> Dictionary:
	if side != "w" and side != "b":
		return {"type": "ignored", "reason": "bad-side"}
	if state["finished"]:
		return {"type": "ignored", "reason": "finished"}
	if state["paused"]:
		return {"type": "ignored", "reason": "paused"}

	# 尚未开表：按任意一方都视为「开表」，由调用方决定从哪一方开始
	if not state["started"]:
		return start(state, now, side)

	if not state["running"]:
		return {"type": "ignored", "reason": "not-running"}
	# 按在「不是自己」的一侧：实体棋钟上跷跷板已经压在对侧，什么都不会发生
	if state["active"] != side:
		return {"type": "ignored", "reason": "not-active"}
	if now - int(state["lastPressAt"]) < MIN_PRESS_GAP_MS:
		return {"type": "ignored", "reason": "debounced"}

	# 先判超时：读秒段数用尽 / 主时间归零
	if is_out_of_time(state, side, now):
		return {"type": "flag", "side": check_flag(state, now)}

	state["lastPressAt"] = now
	if state["cfg"]["mode"] == MODES.BYOYOMI:
		commit_byoyomi(state, side, now, true)  # 超时思考过的段数要扣掉
	else:
		var remain := remaining_ms(state, side, now)
		state["ms"][side] = remain + (int(state["cfg"]["incMs"]) if state["cfg"]["mode"] == MODES.FISCHER else 0)
	state["moves"][side] = int(state["moves"][side]) + 1
	state["active"] = other(side)
	state["turnStart"] = now
	return {
		"type": "move",
		"side": side,
		"remainingMs": int(state["ms"][side]),
		"periodsLeft": int(state["periods"][side]),
		"active": state["active"],
		"moves": int(state["moves"][side]),
	}


## 暂停：把正在流逝的时间先入账，之后再恢复不会丢时间也不会多走
static func pause(state: Dictionary, now: int) -> Dictionary:
	if state["finished"]:
		return {"type": "ignored", "reason": "finished"}
	if not state["started"]:
		return {"type": "ignored", "reason": "not-started"}
	if state["paused"] or not state["running"]:
		return {"type": "ignored", "reason": "not-running"}

	var side: String = state["active"]
	if state["cfg"]["mode"] == MODES.BYOYOMI:
		# 暂停期间不让选手白丢读秒段：已跨过的段数照扣，恢复后当前窗口重新开始
		commit_byoyomi(state, side, now, true)
	else:
		state["ms"][side] = remaining_ms(state, side, now)
	state["running"] = false
	state["paused"] = true
	return {"type": "pause", "side": side, "remainingMs": int(state["ms"][side])}


static func resume(state: Dictionary, now: int) -> Dictionary:
	if state["finished"]:
		return {"type": "ignored", "reason": "finished"}
	if not state["paused"]:
		return {"type": "ignored", "reason": "not-paused"}
	state["paused"] = false
	state["running"] = true
	state["turnStart"] = now
	return {"type": "resume", "side": state["active"]}


## 判定超时。返回超时的一方（"w" / "b"）或 ""。
## 因为时间由绝对时刻推算，即使程序被挂起很久，回到前台调用一次即可得到正确结果。
static func check_flag(state: Dictionary, now: int) -> String:
	if not state["running"] or state["paused"] or state["finished"]:
		return ""
	var side: String = state["active"]
	if not is_out_of_time(state, side, now):
		return ""

	state["ms"][side] = 0
	if state["cfg"]["mode"] == MODES.BYOYOMI:
		state["periods"][side] = 0
	state["running"] = false
	state["finished"] = true
	state["flagged"] = side
	return side


## 供界面显示用的毫秒数（读秒模式下返回当前窗口剩余）
static func display_ms(state: Dictionary, side: String, now: int) -> int:
	return int(readout(state, side, now)["ms"])


static func _pad2(n: int) -> String:
	return "0" + str(n) if n < 10 else str(n)


## 时间格式化，模仿实体棋钟的显示习惯：
##   ≥ 1 小时 → H:MM:SS
##   < 1 小时 → M:SS
##   < 20 秒  → SS.d（十分之一秒）
## 采用「向上取整」，与实体钟一致：剩 5:00.0 时显示 5:00，走掉 0.1 秒后显示 4:59。
static func format_time(ms) -> String:
	var value := _to_number(ms)
	if is_nan(value) or value < 0:
		value = 0.0
	if value < CRITICAL_TIME_MS:
		var tenths := int(ceil(value / 100.0))
		return "%d.%d" % [tenths / 10, tenths % 10]
	var total_sec := int(ceil(value / 1000.0))
	var h := total_sec / 3600
	var m := (total_sec % 3600) / 60
	var s := total_sec % 60
	if h > 0:
		return "%d:%s:%s" % [h, _pad2(m), _pad2(s)]
	return "%d:%s" % [m, _pad2(s)]


static func _secs(ms: int) -> String:
	var s := ms / 1000.0
	if fmod(s, 1.0) == 0.0:
		return str(int(s))
	return "%.1f" % s


## 把配置描述成一句人话，例如「10 分钟 + 每步 5 秒 · Fischer 加秒」
## （引擎是纯逻辑、不带语言；界面文案走 i18n.gd，这里只给测试与日志用）
static func describe_config(config) -> String:
	var cfg := normalize_config(config)
	var mins: float = float(cfg["baseMs"]) / 60000.0
	var base := (str(int(mins)) if fmod(mins, 1.0) == 0.0 else "%.1f" % mins) + " 分钟"

	if cfg["mode"] == MODES.BYOYOMI:
		# 主时间 0 → 纯读秒（不再说「0 分钟 + …」）；读秒 0 → 只有主时间
		var byo := (" + 读秒 " + _secs(int(cfg["byoyomiMs"])) + " 秒") if int(cfg["byoyomiMs"]) > 0 else ""
		if int(cfg["byoyomiMs"]) > 0 and int(cfg["byoyomiPeriods"]) > 1:
			byo += " × " + str(cfg["byoyomiPeriods"]) + " 段"
		if int(cfg["baseMs"]) <= 0:
			return "纯读秒" + byo.replace(" + 读秒 ", " ") + " · " + str(MODE_LABELS[cfg["mode"]])
		if int(cfg["byoyomiMs"]) <= 0:
			base = base + "（无读秒）"
		return base + byo + " · " + str(MODE_LABELS[cfg["mode"]])
	var add: int = int(cfg["incMs"]) if cfg["mode"] == MODES.FISCHER else int(cfg["delayMs"])
	var add_text := (" + 每步 " + _secs(add) + " 秒") if add > 0 else ""
	return base + add_text + " · " + str(MODE_LABELS[cfg["mode"]])
