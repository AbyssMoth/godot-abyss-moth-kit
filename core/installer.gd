@tool
extends RefCounted

# Конвейер установки одного аддона:
# download -> распаковка zip со стрипом верхней папки -> атомарный swap ->
# чтение версии из plugin.cfg + baseline sha через version_check -> запись lock.
# scan() и set_plugin_enabled() выполняет вызывающая панель (один раз на батч).

const ADDONS_ROOT := "res://addons/abyss_moth"
const LOCK_PATH := "res://addons/abyss_moth/abyss_moth_kit/data/abyss_lock.json"
const TMP_DIR := "user://abyss_moth_tmp"

var _client
var _version_check
var _log: Callable

func _init(client, version_check, log_cb: Callable) -> void:
	_client = client
	_version_check = version_check
	_log = log_cb

func _emit(msg: String) -> void:
	if _log.is_valid():
		_log.call(msg)

# Ставит пакет из catalog. Возвращает install_name при успехе, иначе "".
func install(pkg: Dictionary) -> String:
	var owner: String = pkg.get("owner", "")
	var repo: String = pkg.get("repo", "")
	var branch: String = pkg.get("branch", "main")
	var install_name: String = pkg.get("install_name", repo)
	_emit("Установка %s (%s/%s@%s)..." % [install_name, owner, repo, branch])

	var zip_path := "%s/%s.zip" % [TMP_DIR, install_name]
	var dl: Dictionary = await _client.download_branch_zip(owner, repo, branch, zip_path)
	if not dl.get("ok", false):
		_emit("  ошибка загрузки: result=%s code=%s" % [dl.get("result"), dl.get("code")])
		return ""

	# Распаковываем в скрытую временную папку рядом с целью (тот же том - быстрый rename).
	# Имя с ведущей точкой, чтобы Godot не пытался импортировать её во время распаковки.
	var tmp_extract := "%s/.%s__tmp" % [ADDONS_ROOT, install_name]
	_rm_rf(tmp_extract)
	if not _extract_strip_top(zip_path, tmp_extract):
		_emit("  ошибка распаковки zip")
		_rm_rf(tmp_extract)
		return ""

	# Атомарный swap: убираем старую установку и переносим временную на её место.
	var final_dir := "%s/%s" % [ADDONS_ROOT, install_name]
	_rm_rf(final_dir)
	var rename_err := DirAccess.rename_absolute(tmp_extract, final_dir)
	if rename_err != OK:
		_emit("  ошибка переноса в %s (err=%s)" % [final_dir, rename_err])
		_rm_rf(tmp_extract)
		return ""

	var version := _read_installed_version(install_name)
	var sha := ""
	var vr: Dictionary = await _version_check.get_remote_sha(owner, repo, branch)
	if vr.get("ok", false):
		sha = vr.get("sha", "")
	else:
		_emit("  не удалось зафиксировать sha (%s) - трекинг обновлений будет ограничен" % ("нет сети" if vr.get("offline", false) else "ошибка"))

	_write_lock_entry(install_name, pkg, sha, version)
	var tail := ""
	if version != "":
		tail += " v" + version
	if sha != "":
		tail += " @ " + sha.substr(0, 7)
	_emit("  готово: %s%s" % [install_name, tail])
	return install_name

func _extract_strip_top(zip_user_path: String, dest_dir: String) -> bool:
	var reader := ZIPReader.new()
	var abs_zip := ProjectSettings.globalize_path(zip_user_path)
	if reader.open(abs_zip) != OK:
		return false
	var any := false
	for entry in reader.get_files():
		if entry.ends_with("/"):
			continue
		var rel := _strip_top(entry)
		if rel == "":
			continue
		var dest := dest_dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var f := FileAccess.open(dest, FileAccess.WRITE)
		if f != null:
			f.store_buffer(reader.read_file(entry))
			f.close()
			any = true
	reader.close()
	return any

# Срезает верхний сегмент пути ("godot-reactive-main/plugin.cfg" -> "plugin.cfg").
static func _strip_top(entry: String) -> String:
	var idx := entry.find("/")
	if idx == -1:
		return ""
	return entry.substr(idx + 1)

# Читает version из установленного plugin.cfg (если есть).
func _read_installed_version(install_name: String) -> String:
	var cfg_path := "%s/%s/plugin.cfg" % [ADDONS_ROOT, install_name]
	if not FileAccess.file_exists(cfg_path):
		return ""
	var cf := ConfigFile.new()
	if cf.load(cfg_path) != OK:
		return ""
	return str(cf.get_value("plugin", "version", ""))

func _write_lock_entry(install_name: String, pkg: Dictionary, sha: String, version: String) -> void:
	var lock := _read_lock()
	var installed: Dictionary = lock.get("installed", {})
	installed[install_name] = {
		"owner": pkg.get("owner", ""),
		"repo": pkg.get("repo", ""),
		"branch": pkg.get("branch", "main"),
		"plugin_dir": pkg.get("plugin_dir", "abyss_moth/" + install_name),
		"library_style": pkg.get("library_style", false),
		"installed_plugin_version": version,
		"installed_sha": sha,
		"installed_at": Time.get_datetime_string_from_system(true) + "Z",
	}
	lock["installed"] = installed
	_save_lock(lock)

func _read_lock() -> Dictionary:
	if not FileAccess.file_exists(LOCK_PATH):
		return {"schema": 1, "installed": {}}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCK_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return {"schema": 1, "installed": {}}
	if not data.has("installed"):
		data["installed"] = {}
	return data

func _save_lock(lock: Dictionary) -> void:
	var f := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(lock, "\t"))
		f.close()

# Рекурсивное удаление файла или папки по res:// пути.
static func _rm_rf(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var da := DirAccess.open(path)
	if da == null:
		return
	da.include_hidden = true
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if da.current_is_dir():
				_rm_rf(child)
			else:
				DirAccess.remove_absolute(child)
		entry = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
