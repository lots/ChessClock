extends SceneTree
## dump_spec.gd — 把 Godot 版的关键数据导出成 JSON，供 tests/project_spec.js 与网页版逐个比对
##
## 导出内容：双语文案表、预设档位、默认设置、引擎常量、三套主题的色值。
## 这样「两个版本有没有漂移」这件事就不靠人眼，靠 Node 脚本比对。
##
## 运行：
##   godot --headless --path . --script res://tests/dump_spec.gd

const OUT_PATH := "res://tests/out/spec_dump.json"


func _initialize() -> void:
	var out := {
		"i18n": ClockI18n.DICT,
		"langs": ClockI18n.LANGS,
		"presets_chess": ClockPresets.CHESS,
		"presets_byoyomi": ClockPresets.BYOYOMI,
		"preset_labels_chess": [],
		"preset_labels_byoyomi": [],
		"defaults": ClockSettings.DEFAULTS,
		"engine": {
			"MODES": ClockEngine.MODES,
			"MODE_LABELS": ClockEngine.MODE_LABELS,
			"SIDES": ClockEngine.SIDES,
			"LOW_TIME_MS": ClockEngine.LOW_TIME_MS,
			"CRITICAL_TIME_MS": ClockEngine.CRITICAL_TIME_MS,
			"MIN_PRESS_GAP_MS": ClockEngine.MIN_PRESS_GAP_MS,
			"MIN_BASE_MS": ClockEngine.MIN_BASE_MS,
			"MAX_BASE_MS": ClockEngine.MAX_BASE_MS,
			"MAX_ADD_MS": ClockEngine.MAX_ADD_MS,
			"MIN_BYOYOMI_MS": ClockEngine.MIN_BYOYOMI_MS,
			"MAX_PERIODS": ClockEngine.MAX_PERIODS,
		},
		"themes": {},
		"theme_names": ClockTheme.NAMES,
	}

	for preset in ClockPresets.CHESS:
		out["preset_labels_chess"].append(ClockPresets.label(preset))
	for preset in ClockPresets.BYOYOMI:
		out["preset_labels_byoyomi"].append(ClockPresets.label(preset))

	for theme_name in ClockTheme.NAMES:
		var palette := ClockTheme.palette(theme_name)
		var colors := {}
		for key in palette:
			var color: Color = palette[key]
			colors[key] = {
				"hex": "#" + color.to_html(false),
				"alpha": color.a,
			}
		out["themes"][theme_name] = colors

	DirAccess.make_dir_recursive_absolute("res://tests/out")
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入 " + OUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(out, "  "))
	file.close()
	print("SPEC dumped -> " + OUT_PATH)
	quit(0)
