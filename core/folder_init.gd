@tool
extends RefCounted

# Идемпотентный инициализатор структуры проекта студии.
# Создаёт каноническое дерево папок и проставляет цвета в project.godot.
# Повторный запуск безопасен: существующие папки пропускаются, цвета не затираются.

const RULES_PATH := "res://addons/abyss_moth/abyss_moth_kit/data/folder_rules.json"
const COLOR_KEY := "file_customization/folder_colors"

var _log: Callable

func _init(log_cb: Callable) -> void:
	_log = log_cb

func _emit(msg: String) -> void:
	if _log.is_valid():
		_log.call(msg)

func run() -> Dictionary:
	var rules := _load_rules()
	var folders: Array = rules.get("folders", [])
	var colors: Dictionary = rules.get("colors", {})

	# Фаза 1: папки. make_dir_recursive_absolute идемпотентна сама по себе.
	var created := 0
	var existed := 0
	for path in folders:
		var abs := str(path)
		if DirAccess.dir_exists_absolute(abs):
			existed += 1
			continue
		var err := DirAccess.make_dir_recursive_absolute(abs)
		if err == OK:
			created += 1
		else:
			_emit("  ошибка создания %s (err=%s)" % [abs, err])

	# Фаза 2: цвета. READ-MUTATE-WRITE, чтобы не стереть ручные цвета пользователя.
	var current: Dictionary = ProjectSettings.get_setting(COLOR_KEY, {})
	var color_changes := 0
	for key in colors.keys():
		var norm := str(key)
		if not norm.ends_with("/"):
			norm += "/"
		if str(current.get(norm, "")) != str(colors[key]):
			current[norm] = colors[key]
			color_changes += 1
	if color_changes > 0:
		ProjectSettings.set_setting(COLOR_KEY, current)
		var serr := ProjectSettings.save()
		if serr != OK:
			_emit("  ошибка сохранения project.godot (err=%s)" % serr)

	# Фаза 3: обновление файловой системы.
	var efs := EditorInterface.get_resource_filesystem()
	if not efs.is_scanning():
		efs.scan()

	_emit("Папки: создано %d, уже было %d. Цвета обновлено: %d." % [created, existed, color_changes])
	return {"created": created, "existed": existed, "colors": color_changes}

func _load_rules() -> Dictionary:
	if not FileAccess.file_exists(RULES_PATH):
		return {"folders": [], "colors": {}}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	return data if typeof(data) == TYPE_DICTIONARY else {"folders": [], "colors": {}}
