@tool
extends RefCounted

# Чтение/запись data/catalog.json и мутации (добавление пакета, привязка к наборам).

const CATALOG_PATH := "res://addons/abyss_moth/abyss_moth_kit/data/catalog.json"

static func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {"schema": 1, "packages": [], "presets": {}}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return {"schema": 1, "packages": [], "presets": {}}
	if not data.has("packages"):
		data["packages"] = []
	if not data.has("presets"):
		data["presets"] = {}
	return data

static func save_catalog(cfg: Dictionary) -> Error:
	var f := FileAccess.open(CATALOG_PATH, FileAccess.WRITE)
	if f == null:
		return FAILED
	f.store_string(JSON.stringify(cfg, "\t"))
	f.close()
	return OK

# Добавляет пакет или заменяет существующий с тем же install_name.
static func upsert_package(cfg: Dictionary, pkg: Dictionary) -> void:
	var packages: Array = cfg.get("packages", [])
	var install_name := str(pkg.get("install_name", ""))
	for i in range(packages.size()):
		if str(packages[i].get("install_name", "")) == install_name:
			packages[i] = pkg
			cfg["packages"] = packages
			return
	packages.append(pkg)
	cfg["packages"] = packages

# Привязывает install_name к выбранным наборам и убирает из остальных.
static func set_presets_for(cfg: Dictionary, install_name: String, preset_names: Array) -> void:
	var presets: Dictionary = cfg.get("presets", {})
	for pname in presets.keys():
		var arr: Array = presets[pname]
		var idx := arr.find(install_name)
		if preset_names.has(pname):
			if idx == -1:
				arr.append(install_name)
		elif idx != -1:
			arr.remove_at(idx)
		presets[pname] = arr
	for pname in preset_names:
		if not presets.has(pname):
			presets[pname] = [install_name]
	cfg["presets"] = presets

# Убирает пакет из каталога и всех наборов (запись метаданных, не файлы аддона).
static func remove_package(cfg: Dictionary, install_name: String) -> void:
	var packages: Array = cfg.get("packages", [])
	for i in range(packages.size()):
		if str(packages[i].get("install_name", "")) == install_name:
			packages.remove_at(i)
			break
	cfg["packages"] = packages
	var presets: Dictionary = cfg.get("presets", {})
	for pname in presets.keys():
		var arr: Array = presets[pname]
		var idx := arr.find(install_name)
		if idx != -1:
			arr.remove_at(idx)
		presets[pname] = arr
	cfg["presets"] = presets
