@tool
extends RefCounted

# Сетевой слой для загрузки zip публичных репозиториев с codeload.
# Проверку версий (sha) делает version_check.gd отдельно (через git ls-remote).

const USER_AGENT := "User-Agent: AbyssMothKit"

var _http: HTTPRequest

func _init(http: HTTPRequest) -> void:
	_http = http

# Качает zip ветки в dest_user_path (например user://abyss_moth_tmp/<name>.zip).
# Возвращает { ok: bool, result: int, code: int }.
func download_branch_zip(owner: String, repo: String, branch: String, dest_user_path: String) -> Dictionary:
	var url := "https://codeload.github.com/%s/%s/zip/refs/heads/%s" % [owner, repo, branch]
	DirAccess.make_dir_recursive_absolute(dest_user_path.get_base_dir())
	_http.download_file = dest_user_path
	var err := _http.request(url, PackedStringArray([USER_AGENT]))
	if err != OK:
		_http.download_file = ""
		return {"ok": false, "result": -1, "code": 0}
	var res: Array = await _http.request_completed
	_http.download_file = ""
	var result: int = res[0]
	var code: int = res[1]
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	return {"ok": ok, "result": result, "code": code}
