@tool
extends VBoxContainer

# Dock-панель менеджера пакетов Abyss Moth Kit.
# UI строится программно (без .tscn): прокручиваемый список аддонов из catalog.json
# со статусом и цветом, карточка аддона, установка/обновление, инициализация папок и лог.

const GithubClient := preload("res://addons/abyss_moth/abyss_moth_kit/core/github_client.gd")
const Installer := preload("res://addons/abyss_moth/abyss_moth_kit/core/installer.gd")
const VersionCheck := preload("res://addons/abyss_moth/abyss_moth_kit/core/version_check.gd")
const FolderInit := preload("res://addons/abyss_moth/abyss_moth_kit/core/folder_init.gd")
const KitLogger := preload("res://addons/abyss_moth/abyss_moth_kit/core/logger.gd")

const CATALOG_PATH := "res://addons/abyss_moth/abyss_moth_kit/data/catalog.json"
const LOCK_PATH := "res://addons/abyss_moth/abyss_moth_kit/data/abyss_lock.json"
const ADDONS_ROOT := "res://addons/abyss_moth"

const COL_GREEN := Color(0.45, 0.85, 0.45)
const COL_YELLOW := Color(0.95, 0.8, 0.35)
const COL_RED := Color(0.9, 0.45, 0.45)
const COL_GRAY := Color(1, 1, 1, 0.5)
const COL_WHITE := Color(1, 1, 1, 0.85)

var _http: HTTPRequest
var _client
var _version_check
var _installer
var _folder_init
var _logger

var _catalog: Dictionary = {}
var _rows: Dictionary = {}            # install_name -> { pkg, status: Label, action: Button, state: String }
var _action_buttons: Array = []
var _list_box: VBoxContainer
var _log_label: RichTextLabel
var _info_dialog: AcceptDialog
var _info_url := ""
var _busy := false
var _built := false

func _ready() -> void:
	if _built:
		return
	_built = true
	name = "Abyss Moth"
	custom_minimum_size = Vector2(300, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_http = HTTPRequest.new()
	add_child(_http)
	_logger = KitLogger.new()
	_client = GithubClient.new(_http)
	_version_check = VersionCheck.new(self, Callable(self, "_log"))
	_installer = Installer.new(_client, _version_check, Callable(self, "_log"))
	_folder_init = FolderInit.new(Callable(self, "_log"))

	_catalog = _load_catalog()
	_build_ui()
	_refresh_status()
	_log("Готов. Аддонов в каталоге: %d." % _catalog.get("packages", []).size())

# --- построение UI ---

func _build_ui() -> void:
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Abyss Moth Kit"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var hint := Label.new()
	hint.text = "Менеджер студийных аддонов"
	hint.modulate = Color(1, 1, 1, 0.6)
	add_child(hint)

	add_child(HSeparator.new())

	# Прокручиваемый список - на случай десятков аддонов.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	for pkg in _catalog.get("packages", []):
		_build_row(pkg)

	add_child(HSeparator.new())

	var base_btn := Button.new()
	base_btn.text = "Установить набор base"
	base_btn.pressed.connect(_on_install_base)
	add_child(base_btn)
	_action_buttons.append(base_btn)

	var bottom := HBoxContainer.new()
	add_child(bottom)
	var check_btn := Button.new()
	check_btn.text = "Проверить обновления"
	check_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_btn.pressed.connect(_on_check_updates)
	bottom.add_child(check_btn)
	_action_buttons.append(check_btn)
	var updall_btn := Button.new()
	updall_btn.text = "Обновить все"
	updall_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	updall_btn.pressed.connect(_on_update_all)
	bottom.add_child(updall_btn)
	_action_buttons.append(updall_btn)

	var folders_btn := Button.new()
	folders_btn.text = "Инициализировать папки"
	folders_btn.pressed.connect(_on_init_folders)
	add_child(folders_btn)
	_action_buttons.append(folders_btn)

	add_child(HSeparator.new())

	var log_title := Label.new()
	log_title.text = "Лог"
	add_child(log_title)

	_log_label = RichTextLabel.new()
	_log_label.scroll_active = true
	_log_label.custom_minimum_size = Vector2(0, 120)
	add_child(_log_label)

	_info_dialog = AcceptDialog.new()
	_info_dialog.title = "Аддон"
	_info_dialog.add_button("Открыть на GitHub", true, "github")
	_info_dialog.custom_action.connect(_on_info_action)
	add_child(_info_dialog)

func _build_row(pkg: Dictionary) -> void:
	var install_name: String = pkg.get("install_name", pkg.get("repo", "?"))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Имя - кнопка, открывает карточку аддона (инфо + ссылка на GitHub).
	var name_btn := Button.new()
	name_btn.text = pkg.get("display_name", install_name)
	name_btn.flat = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.tooltip_text = "Открыть карточку аддона"
	name_btn.pressed.connect(_on_show_info.bind(install_name))
	row.add_child(name_btn)

	var status := Label.new()
	status.text = "..."
	status.custom_minimum_size = Vector2(78, 0)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(status)

	var action := Button.new()
	action.text = "Установить"
	action.pressed.connect(_on_row_action.bind(install_name))
	row.add_child(action)

	_list_box.add_child(row)
	_rows[install_name] = {"pkg": pkg, "status": status, "action": action, "state": "absent"}
	_action_buttons.append(action)

# --- действия ---

func _on_row_action(install_name: String) -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	await _install_batch([_rows[install_name]["pkg"]], true)

func _on_install_base() -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	var pkgs := _resolve_preset(_catalog.get("presets", {}).get("base", []))
	if pkgs.is_empty():
		_log("Набор base пуст или не найден в catalog.json.")
		return
	await _install_batch(pkgs, false)

func _on_update_all() -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	var pkgs: Array = []
	for install_name in _rows.keys():
		if _rows[install_name]["state"] == "update":
			pkgs.append(_rows[install_name]["pkg"])
	if pkgs.is_empty():
		_log("Нет аддонов с доступным обновлением. Сначала нажмите Проверить обновления.")
		return
	await _install_batch(pkgs, true)

func _on_init_folders() -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	_log("Инициализация структуры папок...")
	_folder_init.run()

# force=false: пропускать уже установленные (защита кнопки base).
# force=true: явная (пере)установка или обновление по клику в строке.
func _install_batch(pkgs: Array, force: bool) -> void:
	_busy = true
	_set_buttons_disabled(true)

	var installed_names: Array = []
	var library_hits: Array = []
	for pkg in pkgs:
		var install_name: String = pkg.get("install_name", pkg.get("repo", ""))
		var present := DirAccess.dir_exists_absolute("%s/%s" % [ADDONS_ROOT, install_name])
		if present and not force:
			_log("%s уже установлен, пропускаю (для обновления: Проверить обновления)." % install_name)
			continue
		var ok_name: String = await _installer.install(pkg)
		if ok_name != "":
			installed_names.append(ok_name)
			if pkg.get("library_style", false):
				library_hits.append(ok_name)

	if installed_names.is_empty():
		_log("Нечего устанавливать.")
	else:
		await _enable_installed(installed_names, library_hits)

	_set_buttons_disabled(false)
	_busy = false
	_refresh_status()

func _enable_installed(names: Array, library_hits: Array) -> void:
	_log("Обновляю файловую систему...")
	var efs := EditorInterface.get_resource_filesystem()
	if not efs.is_scanning():
		efs.scan()
	while efs.is_scanning():
		await get_tree().process_frame
	await get_tree().process_frame
	var enabled_list: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	for n in names:
		var cfg := "res://addons/abyss_moth/%s/plugin.cfg" % n
		if not (cfg in enabled_list):
			EditorInterface.set_plugin_enabled("abyss_moth/" + n, true)
	_log("Включено: " + ", ".join(PackedStringArray(names)))
	if not library_hits.is_empty():
		_log("Подсказка: для [%s] перезапустите редактор, чтобы class_name-глобалы подхватились." % ", ".join(PackedStringArray(library_hits)))

func _on_check_updates() -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	_busy = true
	_set_buttons_disabled(true)
	_log("Проверка обновлений...")

	var installed: Dictionary = _read_lock().get("installed", {})
	var checked := 0
	var updates := 0
	var untracked := 0
	var net_errors := 0

	for install_name in _rows.keys():
		var pkg: Dictionary = _rows[install_name]["pkg"]
		var present := DirAccess.dir_exists_absolute("%s/%s" % [ADDONS_ROOT, install_name])
		if not (present and installed.has(install_name)):
			continue
		checked += 1
		var local_sha: String = str(installed[install_name].get("installed_sha", ""))
		var r: Dictionary = await _version_check.get_remote_sha(pkg.get("owner", ""), pkg.get("repo", ""), pkg.get("branch", "main"))
		if not r.get("ok", false):
			net_errors += 1
			if r.get("offline", false):
				_set_state(install_name, "offline", "нет сети")
				_log("  %s: нет сети, проверка недоступна." % install_name)
			else:
				_set_state(install_name, "error", "ошибка")
				_log("  %s: ошибка проверки." % install_name)
			continue
		var remote_sha: String = r.get("sha", "")
		if local_sha == "":
			untracked += 1
			_set_state(install_name, "untracked", "переустан.")
			_log("  %s: версия не зафиксирована. Переустановите 1 раз для трекинга (upstream %s)." % [install_name, remote_sha.substr(0, 7)])
		elif remote_sha == local_sha:
			_set_state(install_name, "uptodate", "актуально")
			_log("  %s: актуально (%s)." % [install_name, local_sha.substr(0, 7)])
		else:
			updates += 1
			_set_state(install_name, "update", "обновление")
			_log("  %s: доступно обновление %s -> %s." % [install_name, local_sha.substr(0, 7), remote_sha.substr(0, 7)])

	var summary := ""
	if checked == 0:
		summary = "Установленных аддонов нет - проверять нечего."
	else:
		summary = "Проверено: %d. Обновлений: %d." % [checked, updates]
		if updates == 0 and untracked == 0 and net_errors == 0:
			summary += " Всё актуально."
		if untracked > 0:
			summary += " Без трекинга: %d." % untracked
		if net_errors > 0:
			summary += " Ошибок сети: %d." % net_errors
	_log(summary)

	_set_buttons_disabled(false)
	_busy = false

func _on_show_info(install_name: String) -> void:
	var pkg: Dictionary = _rows[install_name]["pkg"]
	var entry: Dictionary = _read_lock().get("installed", {}).get(install_name, {})
	_info_url = pkg.get("repository_url", "")
	_info_dialog.title = pkg.get("display_name", install_name)

	var lines: Array = []
	lines.append(str(pkg.get("description", "")))
	lines.append("")
	lines.append("Репозиторий: %s/%s" % [pkg.get("owner", ""), pkg.get("repo", "")])
	lines.append("Ветка: %s" % pkg.get("branch", "main"))
	if entry.is_empty():
		lines.append("Статус: не установлен")
	else:
		var ver: String = str(entry.get("installed_plugin_version", ""))
		var sha: String = str(entry.get("installed_sha", ""))
		lines.append("Установлен: %s" % (("v" + ver) if ver != "" else "(версия неизвестна)"))
		lines.append("Commit: %s" % (sha.substr(0, 12) if sha != "" else "(не зафиксирован)"))
		lines.append("Дата: %s" % str(entry.get("installed_at", "")))
	lines.append("")
	lines.append("URL: %s" % _info_url)
	_info_dialog.dialog_text = "\n".join(PackedStringArray(lines))
	_info_dialog.popup_centered(Vector2i(440, 0))

func _on_info_action(action: StringName) -> void:
	if action == "github" and _info_url != "":
		OS.shell_open(_info_url)

# --- статус и вспомогательное ---

func _refresh_status() -> void:
	var installed: Dictionary = _read_lock().get("installed", {})
	for install_name in _rows.keys():
		var present := DirAccess.dir_exists_absolute("%s/%s" % [ADDONS_ROOT, install_name])
		if present and installed.has(install_name):
			var entry: Dictionary = installed[install_name]
			var ver: String = str(entry.get("installed_plugin_version", ""))
			var sha: String = str(entry.get("installed_sha", ""))
			if sha == "":
				_set_state(install_name, "untracked", "переустан.")
			else:
				_set_state(install_name, "installed", ("v" + ver) if ver != "" else sha.substr(0, 7))
		elif present:
			_set_state(install_name, "installed", "есть папка")
		else:
			_set_state(install_name, "absent", "нет")

func _set_state(install_name: String, state: String, text: String) -> void:
	var row: Dictionary = _rows[install_name]
	row["state"] = state
	var status: Label = row["status"]
	var action: Button = row["action"]
	status.text = text
	match state:
		"absent":
			status.modulate = COL_GRAY
			action.text = "Установить"
		"installed":
			status.modulate = COL_WHITE
			action.text = "Переустановить"
		"untracked":
			status.modulate = COL_YELLOW
			action.text = "Переустановить"
		"uptodate":
			status.modulate = COL_GREEN
			action.text = "Переустановить"
		"update":
			status.modulate = COL_YELLOW
			action.text = "Обновить"
		"offline":
			status.modulate = COL_GRAY
			action.text = "Переустановить"
		"error":
			status.modulate = COL_RED
			action.text = "Переустановить"

func _resolve_preset(names: Array) -> Array:
	var by_name: Dictionary = {}
	for pkg in _catalog.get("packages", []):
		by_name[pkg.get("install_name", pkg.get("repo", ""))] = pkg
	var out: Array = []
	for n in names:
		if by_name.has(n):
			out.append(by_name[n])
	return out

func _set_buttons_disabled(value: bool) -> void:
	for btn in _action_buttons:
		btn.disabled = value

func _load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _read_lock() -> Dictionary:
	if not FileAccess.file_exists(LOCK_PATH):
		return {"schema": 1, "installed": {}}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCK_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return {"schema": 1, "installed": {}}
	return data

func _log(msg: String) -> void:
	if _log_label != null:
		_log_label.append_text(msg + "\n")
	if _logger != null:
		_logger.write(msg)
	print("[AbyssMothKit] ", msg)
