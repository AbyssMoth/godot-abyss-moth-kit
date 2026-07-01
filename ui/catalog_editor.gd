@tool
extends AcceptDialog

# Форма добавления репозитория в каталог. Заполняешь поля вместо правки JSON руками.

const CatalogStore := preload("res://addons/abyss_moth/abyss_moth_kit/core/catalog_store.gd")

signal catalog_changed

var _fields: Dictionary = {}
var _kind_select: OptionButton
var _lib_check: CheckBox
var _autoload_check: CheckBox
var _preset_box: VBoxContainer
var _preset_checks: Dictionary = {}
var _error: Label
var _built := false

func _ready() -> void:
	if _built:
		return
	_built = true
	title = "Добавить репозиторий в каталог"
	ok_button_text = "Добавить в каталог"
	_build()
	confirmed.connect(_on_confirmed)

func _build() -> void:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(460, 0)
	add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(grid)

	_add_field(grid, "display_name", "Имя (для показа)", "Godot Reactive")
	_add_field(grid, "owner", "Владелец (GitHub) *", "AbyssMoth")
	_add_field(grid, "repo", "Репозиторий *", "godot-reactive")
	_add_field(grid, "branch", "Ветка", "main")
	_add_field(grid, "install_name", "install_name (папка) *", "reactive")
	_add_field(grid, "plugin_dir", "plugin_dir (под addons/)", "abyss_moth/reactive")
	_add_field(grid, "source_subdir", "source_subdir (опц.)", "напр. plugin/addons/x")
	_add_field(grid, "description", "Описание", "")

	var kind_label := Label.new()
	kind_label.text = "Тип"
	grid.add_child(kind_label)
	_kind_select = OptionButton.new()
	_kind_select.add_item("Студийный")
	_kind_select.set_item_metadata(0, "studio")
	_kind_select.add_item("Форк")
	_kind_select.set_item_metadata(1, "fork")
	_kind_select.add_item("Внешний")
	_kind_select.set_item_metadata(2, "external")
	_kind_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_kind_select)

	_lib_check = CheckBox.new()
	_lib_check.text = "library_style (class_name globals, нужен рестарт)"
	root.add_child(_lib_check)
	_autoload_check = CheckBox.new()
	_autoload_check.text = "declares_autoloads (нужен рестарт)"
	root.add_child(_autoload_check)

	var pl := Label.new()
	pl.text = "Добавить в наборы:"
	root.add_child(pl)
	_preset_box = VBoxContainer.new()
	root.add_child(_preset_box)

	_error = Label.new()
	_error.modulate = Color(1, 0.4, 0.4)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_error)

func _add_field(grid: GridContainer, key: String, label_text: String, placeholder: String) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(edit)
	_fields[key] = edit

func _f(key: String) -> String:
	return (_fields[key] as LineEdit).text.strip_edges()

# Сбрасывает форму и открывает; подтягивает актуальные наборы из каталога.
func open_new(catalog: Dictionary) -> void:
	for key in _fields.keys():
		(_fields[key] as LineEdit).text = ""
	(_fields["branch"] as LineEdit).text = "main"
	_kind_select.select(0)
	_lib_check.button_pressed = false
	_autoload_check.button_pressed = false
	_error.text = ""
	for child in _preset_box.get_children():
		child.queue_free()
	_preset_checks.clear()
	for pname in catalog.get("presets", {}).keys():
		var cb := CheckBox.new()
		cb.text = str(pname)
		_preset_box.add_child(cb)
		_preset_checks[pname] = cb
	popup_centered(Vector2i(500, 0))

func _on_confirmed() -> void:
	var owner := _f("owner")
	var repo := _f("repo")
	var install_name := _f("install_name")
	if owner == "" or repo == "" or install_name == "":
		_error.text = "Обязательны: владелец, репозиторий, install_name."
		call_deferred("popup_centered", Vector2i(500, 0))
		return

	var plugin_dir := _f("plugin_dir")
	if plugin_dir == "":
		plugin_dir = "abyss_moth/" + install_name
	var branch := _f("branch")
	if branch == "":
		branch = "main"
	var display_name := _f("display_name")
	if display_name == "":
		display_name = install_name

	var pkg := {
		"name": install_name,
		"display_name": display_name,
		"kind": str(_kind_select.get_item_metadata(_kind_select.selected)),
		"owner": owner,
		"repo": repo,
		"branch": branch,
		"install_name": install_name,
		"plugin_dir": plugin_dir,
		"repository_url": "https://github.com/%s/%s" % [owner, repo],
		"library_style": _lib_check.button_pressed,
		"public": true,
		"description": _f("description"),
	}
	var subdir := _f("source_subdir")
	if subdir != "":
		pkg["source_subdir"] = subdir
	if _autoload_check.button_pressed:
		pkg["declares_autoloads"] = true

	var selected_presets: Array = []
	for pname in _preset_checks.keys():
		if (_preset_checks[pname] as CheckBox).button_pressed:
			selected_presets.append(pname)

	var cfg := CatalogStore.load_catalog()
	CatalogStore.upsert_package(cfg, pkg)
	CatalogStore.set_presets_for(cfg, install_name, selected_presets)
	if CatalogStore.save_catalog(cfg) == OK:
		catalog_changed.emit()
