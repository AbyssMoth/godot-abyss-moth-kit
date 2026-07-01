@tool
extends EditorPlugin

# Abyss Moth Kit - umbrella-инструмент студии (v0.5.0).
# Этот скрипт держит только жизненный цикл dock-панели.
# Вся логика (сеть, установка, каталог, инициализация папок) лежит в core/ и ui/.

const DockPanel := preload("res://addons/abyss_moth/abyss_moth_kit/ui/dock_panel.gd")

var _panel: Control

func _enter_tree() -> void:
	_panel = DockPanel.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _panel)

func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_docks(_panel)
		_panel.queue_free()
		_panel = null
