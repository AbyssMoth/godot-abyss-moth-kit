@tool
extends VBoxContainer

# Dock-панель менеджера пакетов Abyss Moth Kit.
# Группы studio/fork/external со сворачиванием, секция наборов, редактор каталога,
# установка/обновление/деинсталляция, нативные иконки редактора, лог (дублируется в файл).

const GithubClient := preload("res://addons/abyss_moth/abyss_moth_kit/core/github_client.gd")
const Installer := preload("res://addons/abyss_moth/abyss_moth_kit/core/installer.gd")
const VersionCheck := preload("res://addons/abyss_moth/abyss_moth_kit/core/version_check.gd")
const FolderInit := preload("res://addons/abyss_moth/abyss_moth_kit/core/folder_init.gd")
const KitLogger := preload("res://addons/abyss_moth/abyss_moth_kit/core/logger.gd")
const CatalogStore := preload("res://addons/abyss_moth/abyss_moth_kit/core/catalog_store.gd")
const CatalogEditor := preload("res://addons/abyss_moth/abyss_moth_kit/ui/catalog_editor.gd")

const LOCK_PATH := "res://addons/abyss_moth/abyss_moth_kit/data/abyss_lock.json"

const COL_GREEN := Color(0.45, 0.85, 0.45)
const COL_YELLOW := Color(0.95, 0.8, 0.35)
const COL_RED := Color(0.9, 0.45, 0.45)
const COL_GRAY := Color(1, 1, 1, 0.5)
const COL_WHITE := Color(1, 1, 1, 0.85)
const COL_CATEGORY := Color(0.5, 0.78, 1.0)

const KIND_GROUPS := [
	{"kind": "studio", "title": "Студийные"},
	{"kind": "fork", "title": "Форки"},
	{"kind": "external", "title": "Внешние"},
]

var _http: HTTPRequest
var _client
var _version_check
var _installer
var _folder_init
var _logger

var _catalog: Dictionary = {}
var _rows: Dictionary = {}
var _preset_rows: Dictionary = {}
var _static_buttons: Array = []
var _dynamic_buttons: Array = []
var _dynamic: VBoxContainer
var _log_label: RichTextLabel
var _info_dialog: AcceptDialog
var _confirm_dialog: ConfirmationDialog
var _editor_dialog: AcceptDialog
var _info_url := ""
var _pending_uninstall := ""
var _self_status: Label
var _self_action: Button
var _self_state := "unknown"
var _self_latest := ""
var _busy := false
var _built := false

func _ready() -> void:
	if _built:
		return
	_built = true
	name = "Abyss Moth"
	custom_minimum_size = Vector2(320, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_http = HTTPRequest.new()
	add_child(_http)
	_logger = KitLogger.new()
	_client = GithubClient.new(_http)
	_version_check = VersionCheck.new(self, Callable(self, "_log"))
	_installer = Installer.new(_client, _version_check, Callable(self, "_log"))
	_folder_init = FolderInit.new(Callable(self, "_log"))

	_catalog = CatalogStore.load_catalog()
	_build_static_ui()
	_rebuild_dynamic()
	_log("Готов. Аддонов в каталоге: %d." % _catalog.get("packages", []).size())
	# Фоновая проверка обновления самого kit при открытии.
	call_deferred("_background_self_check")

# --- статичный каркас ---

func _build_static_ui() -> void:
	add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	add_child(header)
	var title := Label.new()
	title.text = "Abyss Moth Kit"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var gear := Button.new()
	gear.icon = _icon("Tools")
	gear.tooltip_text = "Добавить репозиторий в каталог"
	gear.pressed.connect(_open_catalog_editor)
	header.add_child(gear)
	_static_buttons.append(gear)

	var hint := Label.new()
	hint.text = "Менеджер студийных аддонов"
	hint.modulate = Color(1, 1, 1, 0.6)
	add_child(hint)

	# Строка самого kit: версия + статус обновления + кнопка самообновления.
	var self_row := HBoxContainer.new()
	add_child(self_row)
	var self_name := Label.new()
	self_name.text = "Abyss Moth Kit  v%s" % _self_version()
	self_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	self_row.add_child(self_name)
	_self_status = Label.new()
	_self_status.custom_minimum_size = Vector2(74, 0)
	_self_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_self_status.modulate = COL_GRAY
	self_row.add_child(_self_status)
	_self_action = Button.new()
	_self_action.text = "Обновить себя"
	_self_action.icon = _icon("Reload")
	_self_action.visible = false
	_self_action.pressed.connect(_on_self_update)
	self_row.add_child(_self_action)
	_static_buttons.append(_self_action)

	add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_dynamic = VBoxContainer.new()
	_dynamic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_dynamic)

	add_child(HSeparator.new())

	var actions := HBoxContainer.new()
	add_child(actions)
	var check_btn := Button.new()
	check_btn.text = "Проверить обновления"
	check_btn.icon = _icon("Search")
	check_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_btn.pressed.connect(_on_check_updates)
	actions.add_child(check_btn)
	_static_buttons.append(check_btn)
	var updall_btn := Button.new()
	updall_btn.text = "Обновить все"
	updall_btn.icon = _icon("Reload")
	updall_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	updall_btn.pressed.connect(_on_update_all)
	actions.add_child(updall_btn)
	_static_buttons.append(updall_btn)

	var folders_btn := Button.new()
	folders_btn.text = "Инициализировать папки"
	folders_btn.icon = _icon("Folder")
	folders_btn.pressed.connect(_on_init_folders)
	add_child(folders_btn)
	_static_buttons.append(folders_btn)

	add_child(HSeparator.new())

	var log_title := Label.new()
	log_title.text = "Лог"
	add_child(log_title)
	_log_label = RichTextLabel.new()
	_log_label.scroll_active = true
	_log_label.custom_minimum_size = Vector2(0, 110)
	add_child(_log_label)

	_info_dialog = AcceptDialog.new()
	_info_dialog.title = "Аддон"
	_info_dialog.add_button("Открыть на GitHub", true, "github")
	_info_dialog.custom_action.connect(_on_info_action)
	add_child(_info_dialog)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Удалить аддон"
	_confirm_dialog.confirmed.connect(_do_uninstall)
	add_child(_confirm_dialog)

	_editor_dialog = CatalogEditor.new()
	_editor_dialog.catalog_changed.connect(_on_catalog_changed)
	add_child(_editor_dialog)

# --- динамическая часть (наборы + группы) ---

func _rebuild_dynamic() -> void:
	for child in _dynamic.get_children():
		child.queue_free()
	_rows.clear()
	_preset_rows.clear()
	_dynamic_buttons.clear()

	# Наборы (категории)
	var presets: Dictionary = _catalog.get("presets", {})
	if not presets.is_empty():
		var sets_box := _add_foldable(_dynamic, "Наборы (категории)", false)
		for pname in presets.keys():
			_build_preset_row(sets_box, str(pname), presets[pname])

	# Пакеты по типам
	var packages: Array = _catalog.get("packages", [])
	for group in KIND_GROUPS:
		var members: Array = []
		for pkg in packages:
			if str(pkg.get("kind", "studio")) == group["kind"]:
				members.append(pkg)
		if members.is_empty():
			continue
		var box := _add_foldable(_dynamic, "%s (%d)" % [group["title"], members.size()], false)
		for pkg in members:
			_build_row(box, pkg)

	_refresh_status()

func _add_foldable(parent: VBoxContainer, title_text: String, folded: bool) -> VBoxContainer:
	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = not folded
	header.text = title_text
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.flat = true
	var content := VBoxContainer.new()
	content.visible = not folded
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.icon = _icon("GuiTreeArrowDown") if not folded else _icon("GuiTreeArrowRight")
	header.toggled.connect(func(pressed):
		content.visible = pressed
		header.icon = _icon("GuiTreeArrowDown") if pressed else _icon("GuiTreeArrowRight"))
	parent.add_child(header)
	parent.add_child(content)
	return content

func _build_preset_row(parent: VBoxContainer, pname: String, members: Array) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Название категории отдельным цветом, чтобы не читалось как имя аддона.
	var name_label := Label.new()
	name_label.text = pname
	name_label.add_theme_color_override("font_color", COL_CATEGORY)
	name_label.custom_minimum_size = Vector2(92, 0)
	name_label.tooltip_text = "Категория (набор аддонов)"
	row.add_child(name_label)

	var names: PackedStringArray = PackedStringArray()
	for m in members:
		names.append(str(m))
	var members_label := Label.new()
	members_label.text = ", ".join(names)
	members_label.modulate = Color(1, 1, 1, 0.6)
	members_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	members_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(members_label)

	var btn := Button.new()
	btn.pressed.connect(_on_install_preset.bind(pname))
	row.add_child(btn)

	parent.add_child(row)
	_dynamic_buttons.append(btn)
	_preset_rows[pname] = {"button": btn, "members": members}
	_update_preset_button(pname)

func _build_row(parent: VBoxContainer, pkg: Dictionary) -> void:
	var install_name: String = pkg.get("install_name", pkg.get("repo", "?"))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_btn := Button.new()
	name_btn.text = pkg.get("display_name", install_name)
	name_btn.icon = _icon("Tools")
	name_btn.flat = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.tooltip_text = "Открыть карточку аддона"
	name_btn.pressed.connect(_on_show_info.bind(install_name))
	row.add_child(name_btn)

	var status := Label.new()
	status.text = "..."
	status.custom_minimum_size = Vector2(74, 0)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(status)

	var action := Button.new()
	action.text = "Установить"
	action.pressed.connect(_on_row_action.bind(install_name))
	row.add_child(action)

	var uninstall := Button.new()
	uninstall.icon = _icon("Remove")
	uninstall.tooltip_text = "Удалить (папка + запись в lock)"
	uninstall.pressed.connect(_on_uninstall.bind(install_name))
	row.add_child(uninstall)

	parent.add_child(row)
	_rows[install_name] = {"pkg": pkg, "status": status, "action": action, "uninstall": uninstall, "state": "absent"}
	_dynamic_buttons.append(action)
	_dynamic_buttons.append(uninstall)

# --- иконки ---

func _icon(icon_name: String) -> Texture2D:
	if has_theme_icon(icon_name, "EditorIcons"):
		return get_theme_icon(icon_name, "EditorIcons")
	return null

# --- пути ---

func _plugin_dir(install_name: String) -> String:
	var pkg: Dictionary = _rows[install_name]["pkg"]
	return pkg.get("plugin_dir", "abyss_moth/" + install_name)

func _install_path(install_name: String) -> String:
	return "res://addons/" + _plugin_dir(install_name)

# --- каталог: редактор ---

func _open_catalog_editor() -> void:
	_editor_dialog.open_new(_catalog)

func _on_catalog_changed() -> void:
	_catalog = CatalogStore.load_catalog()
	_rebuild_dynamic()
	_log("Каталог обновлён. Пакетов: %d." % _catalog.get("packages", []).size())

func _reload_catalog() -> void:
	_catalog = CatalogStore.load_catalog()
	_rebuild_dynamic()

# --- действия ---

func _on_row_action(install_name: String) -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	await _install_batch([_rows[install_name]["pkg"]], true)

func _on_install_preset(pname: String) -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	var members: Array = _catalog.get("presets", {}).get(pname, [])
	var pkgs := _resolve_preset(members)
	if pkgs.is_empty():
		_log("Набор %s пуст или пакеты не найдены." % pname)
		return
	_log("Установка набора %s..." % pname)
	await _install_batch(pkgs, false)

func _on_update_all() -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	# Сначала проверяем (отдельно кнопку проверки жать не нужно), потом обновляем найденное.
	await _check_updates(false)
	var pkgs: Array = []
	for install_name in _rows.keys():
		if _rows[install_name]["state"] == "update":
			pkgs.append(_rows[install_name]["pkg"])
	if pkgs.is_empty():
		if _self_state == "update":
			_log("Обновлений пакетов нет. Для самого kit нажмите 'Обновить себя'.")
		else:
			_log("Всё актуально, обновлять нечего.")
		return
	await _install_batch(pkgs, true)

func _on_init_folders() -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	_log("Инициализация структуры папок...")
	_folder_init.run()

func _on_uninstall(install_name: String) -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	if not DirAccess.dir_exists_absolute(_install_path(install_name)):
		_log("%s не установлен." % install_name)
		return
	_pending_uninstall = install_name
	_confirm_dialog.dialog_text = "Удалить %s?\nПапка %s и запись в lock будут удалены. Ссылки в проекте на этот аддон перестанут работать." % [install_name, _install_path(install_name)]
	_confirm_dialog.popup_centered()

func _do_uninstall() -> void:
	var install_name := _pending_uninstall
	_pending_uninstall = ""
	if install_name == "" or not _rows.has(install_name):
		return
	var plugin_dir := _plugin_dir(install_name)
	var dir := "res://addons/" + plugin_dir
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	if ("res://addons/" + plugin_dir + "/plugin.cfg") in enabled:
		EditorInterface.set_plugin_enabled(plugin_dir, false)
	Installer._rm_rf(dir)
	_remove_lock_entry(install_name)
	var efs := EditorInterface.get_resource_filesystem()
	if not efs.is_scanning():
		efs.scan()
	_log("Удалён: %s (папка %s + запись в lock)." % [install_name, dir])
	_rebuild_dynamic()

func _remove_lock_entry(install_name: String) -> void:
	var lock := _read_lock()
	var installed: Dictionary = lock.get("installed", {})
	if installed.has(install_name):
		installed.erase(install_name)
		lock["installed"] = installed
		var f := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(lock, "\t"))
			f.close()

func _install_batch(pkgs: Array, force: bool) -> void:
	_busy = true
	_set_buttons_disabled(true)

	var installed_names: Array = []
	var restart_hits: Array = []
	for pkg in pkgs:
		var install_name: String = pkg.get("install_name", pkg.get("repo", ""))
		var present := DirAccess.dir_exists_absolute("res://addons/" + str(pkg.get("plugin_dir", "abyss_moth/" + install_name)))
		if present and not force:
			_log("%s уже установлен, пропускаю." % install_name)
			continue
		var ok_name: String = await _installer.install(pkg)
		if ok_name != "":
			installed_names.append(ok_name)
			if pkg.get("library_style", false) or pkg.get("declares_autoloads", false):
				restart_hits.append(ok_name)

	if installed_names.is_empty():
		_log("Нечего устанавливать.")
	else:
		await _enable_installed(installed_names, restart_hits)

	_set_buttons_disabled(false)
	_busy = false
	_refresh_status()

func _enable_installed(names: Array, restart_hits: Array) -> void:
	_log("Обновляю файловую систему...")
	var efs := EditorInterface.get_resource_filesystem()
	if not efs.is_scanning():
		efs.scan()
	while efs.is_scanning():
		await get_tree().process_frame
	await get_tree().process_frame
	var enabled_list: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	for n in names:
		var plugin_dir := _plugin_dir(n)
		var cfg := "res://addons/" + plugin_dir + "/plugin.cfg"
		if not (cfg in enabled_list):
			EditorInterface.set_plugin_enabled(plugin_dir, true)
	_log("Включено: " + ", ".join(PackedStringArray(names)))
	if not restart_hits.is_empty():
		_log("Подсказка: для [%s] перезапустите редактор (autoload / class_name-глобалы)." % ", ".join(PackedStringArray(restart_hits)))

func _on_check_updates() -> void:
	await _check_updates(false)

# Проверка обновлений: сам kit + все установленные пакеты. silent=true - для фона
# (минимум логов). Пока идёт проверка, кнопки заблокированы.
func _check_updates(silent: bool) -> void:
	if _busy:
		if not silent:
			_log("Занято, дождитесь завершения.")
		return
	_busy = true
	_set_buttons_disabled(true)
	if not silent:
		_log("Проверка обновлений...")

	await _check_self(silent)

	var installed: Dictionary = _read_lock().get("installed", {})
	var checked := 0
	var updates := 0
	var untracked := 0
	var net_errors := 0

	for install_name in _rows.keys():
		var pkg: Dictionary = _rows[install_name]["pkg"]
		if not (DirAccess.dir_exists_absolute(_install_path(install_name)) and installed.has(install_name)):
			continue
		checked += 1
		var local_sha: String = str(installed[install_name].get("installed_sha", ""))
		var r: Dictionary = await _version_check.get_remote_sha(pkg.get("owner", ""), pkg.get("repo", ""), pkg.get("branch", "main"))
		if not r.get("ok", false):
			net_errors += 1
			if r.get("offline", false):
				_set_state(install_name, "offline", "нет сети")
				if not silent:
					_log("  %s: нет сети." % install_name)
			else:
				_set_state(install_name, "error", "ошибка")
				if not silent:
					_log("  %s: ошибка проверки." % install_name)
			continue
		var remote_sha: String = r.get("sha", "")
		if local_sha == "":
			untracked += 1
			_set_state(install_name, "untracked", "переустан.")
			if not silent:
				_log("  %s: версия не зафиксирована, переустановите (upstream %s)." % [install_name, remote_sha.substr(0, 7)])
		elif remote_sha == local_sha:
			_set_state(install_name, "uptodate", "актуально")
			if not silent:
				_log("  %s: актуально (%s)." % [install_name, local_sha.substr(0, 7)])
		else:
			updates += 1
			_set_state(install_name, "update", "обновление")
			if not silent:
				_log("  %s: обновление %s -> %s." % [install_name, local_sha.substr(0, 7), remote_sha.substr(0, 7)])

	if not silent:
		var summary := ""
		if checked == 0:
			summary = "Установленных аддонов нет."
		else:
			summary = "Проверено: %d. Обновлений: %d." % [checked, updates]
			if updates == 0 and untracked == 0 and net_errors == 0:
				summary += " Всё актуально."
			if untracked > 0:
				summary += " Без трекинга: %d." % untracked
			if net_errors > 0:
				summary += " Ошибок сети: %d." % net_errors
		_log(summary)
	elif updates > 0 or _self_state == "update":
		_log("Найдены обновления. Нажмите Обновить все или Обновить себя.")

	_set_buttons_disabled(false)
	_busy = false

func _check_self(silent: bool) -> void:
	if _self_status == null:
		return
	var sp := _self_pkg()
	var r: Dictionary = await _version_check.get_latest_tag(sp["owner"], sp["repo"])
	var local := _self_version()
	if not r.get("ok", false):
		_self_state = "offline" if r.get("offline", false) else "error"
		_self_status.text = "нет сети" if r.get("offline", false) else "?"
		_self_status.modulate = COL_GRAY
		_self_action.visible = false
		return
	var latest: String = str(r.get("tag", ""))
	_self_latest = latest
	if latest != "" and VersionCheck.version_gt(latest, local):
		_self_state = "update"
		_self_status.text = "-> v%s" % latest
		_self_status.modulate = COL_YELLOW
		_self_action.visible = true
		if not silent:
			_log("Abyss Moth Kit: доступно обновление v%s -> v%s." % [local, latest])
	else:
		_self_state = "uptodate"
		_self_status.text = "актуально"
		_self_status.modulate = COL_GREEN
		_self_action.visible = false
		if not silent:
			_log("Abyss Moth Kit: актуально (v%s)." % local)

func _background_self_check() -> void:
	if _busy:
		return
	await _check_self(false)

func _on_self_update() -> void:
	if _busy:
		_log("Занято, дождитесь завершения.")
		return
	_busy = true
	_set_buttons_disabled(true)
	_log("Обновление Abyss Moth Kit до v%s..." % _self_latest)
	# lock (что установлено) лежит внутри папки kit и стирается swap-ом - сохраняем и вернём.
	var saved_lock := _read_lock()
	var ok_name: String = await _installer.install(_self_pkg())
	if ok_name != "":
		var f := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(saved_lock, "\t"))
			f.close()
		var efs := EditorInterface.get_resource_filesystem()
		if not efs.is_scanning():
			efs.scan()
		_self_action.visible = false
		_log("Abyss Moth Kit обновлён (lock сохранён, каталог обновлён из репо). ПЕРЕЗАПУСТИТЕ РЕДАКТОР.")
	else:
		_log("Не удалось обновить kit.")
	_set_buttons_disabled(false)
	_busy = false

func _self_version() -> String:
	var cf := ConfigFile.new()
	if cf.load("res://addons/abyss_moth/abyss_moth_kit/plugin.cfg") == OK:
		return str(cf.get_value("plugin", "version", ""))
	return "?"

func _self_pkg() -> Dictionary:
	return {
		"owner": "AbyssMoth",
		"repo": "godot-abyss-moth-kit",
		"branch": "main",
		"install_name": "abyss_moth_kit",
		"plugin_dir": "abyss_moth/abyss_moth_kit",
		"display_name": "Abyss Moth Kit",
	}

func _on_show_info(install_name: String) -> void:
	var pkg: Dictionary = _rows[install_name]["pkg"]
	var entry: Dictionary = _read_lock().get("installed", {}).get(install_name, {})
	_info_url = pkg.get("repository_url", "")
	_info_dialog.title = pkg.get("display_name", install_name)

	var lines: Array = []
	lines.append(str(pkg.get("description", "")))
	lines.append("")
	lines.append("Тип: %s" % _kind_ru(str(pkg.get("kind", "studio"))))
	lines.append("Репозиторий: %s/%s" % [pkg.get("owner", ""), pkg.get("repo", "")])
	lines.append("Ветка: %s" % pkg.get("branch", "main"))
	lines.append("Ставится в: %s" % _install_path(install_name))
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
	_info_dialog.popup_centered(Vector2i(460, 0))

func _on_info_action(action: StringName) -> void:
	if action == "github" and _info_url != "":
		OS.shell_open(_info_url)

func _kind_ru(kind: String) -> String:
	match kind:
		"external": return "внешний"
		"fork": return "форк"
		_: return "студийный"

# --- статус ---

func _refresh_status() -> void:
	var installed: Dictionary = _read_lock().get("installed", {})
	for install_name in _rows.keys():
		var present := DirAccess.dir_exists_absolute(_install_path(install_name))
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
	_refresh_presets()

func _is_installed(install_name: String) -> bool:
	if not _rows.has(install_name):
		return false
	return DirAccess.dir_exists_absolute(_install_path(install_name))

func _refresh_presets() -> void:
	for pname in _preset_rows.keys():
		_update_preset_button(pname)

func _update_preset_button(pname: String) -> void:
	var entry: Dictionary = _preset_rows[pname]
	var btn: Button = entry["button"]
	var members: Array = entry["members"]
	var total := members.size()
	var installed := 0
	for m in members:
		if _is_installed(str(m)):
			installed += 1
	if total == 0:
		btn.text = "пусто"
		btn.icon = null
		btn.disabled = true
	elif installed >= total:
		btn.text = "Установлено"
		btn.icon = _icon("StatusSuccess")
		btn.disabled = true
	elif installed == 0:
		btn.text = "Установить"
		btn.icon = _icon("Add")
		btn.disabled = false
	else:
		btn.text = "Доставить (%d)" % (total - installed)
		btn.icon = _icon("Add")
		btn.disabled = false

func _set_state(install_name: String, state: String, text: String) -> void:
	var row: Dictionary = _rows[install_name]
	row["state"] = state
	var status: Label = row["status"]
	var action: Button = row["action"]
	var uninstall: Button = row["uninstall"]
	status.text = text
	uninstall.visible = state != "absent"
	match state:
		"absent":
			status.modulate = COL_GRAY
			action.text = "Установить"
			action.icon = _icon("Add")
		"update":
			status.modulate = COL_YELLOW
			action.text = "Обновить"
			action.icon = _icon("Reload")
		"uptodate":
			status.modulate = COL_GREEN
			action.text = "Переустановить"
			action.icon = _icon("Reload")
		"untracked":
			status.modulate = COL_YELLOW
			action.text = "Переустановить"
			action.icon = _icon("Reload")
		"offline":
			status.modulate = COL_GRAY
			action.text = "Переустановить"
			action.icon = _icon("Reload")
		"error":
			status.modulate = COL_RED
			action.text = "Переустановить"
			action.icon = _icon("Reload")
		_:
			status.modulate = COL_WHITE
			action.text = "Переустановить"
			action.icon = _icon("Reload")

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
	for btn in _static_buttons:
		btn.disabled = value
	for btn in _dynamic_buttons:
		if is_instance_valid(btn):
			btn.disabled = value

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
