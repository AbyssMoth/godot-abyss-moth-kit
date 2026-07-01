@tool
extends RefCounted

# Простой файловый логгер kit. Пишет историю в logs/kit.log рядом с аддоном,
# чтобы при проблеме можно было открыть папку и посмотреть, что произошло.
# Содержимое logs/ игнорируется git (см. logs/.gitignore).

const LOG_DIR := "res://addons/abyss_moth/abyss_moth_kit/logs"
const LOG_PATH := "res://addons/abyss_moth/abyss_moth_kit/logs/kit.log"
const MAX_BYTES := 1048576  # 1 МБ - простая ротация перезаписью

func write(msg: String) -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var line := "[%s] %s" % [Time.get_datetime_string_from_system(true), msg]
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE
	var f := FileAccess.open(LOG_PATH, mode)
	if f == null:
		return
	if mode == FileAccess.READ_WRITE:
		if f.get_length() > MAX_BYTES:
			f.close()
			f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
			if f == null:
				return
		else:
			f.seek_end()
	f.store_line(line)
	f.close()
