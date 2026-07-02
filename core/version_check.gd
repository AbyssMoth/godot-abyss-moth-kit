@tool
extends RefCounted

# Определение версии аддона в upstream (для кнопки обновления).
# Основной путь - git ls-remote (нет лимита GitHub, нет авторизации для публичных репо).
# Фолбэк - REST api.github.com (лимит 60/час без токена), на машинах без git.

const GIT_CANDIDATES := ["git", "/opt/homebrew/bin/git", "/usr/bin/git", "/usr/local/bin/git"]

var _host: Node          # для временных HTTPRequest в REST-фолбэке
var _log: Callable
var _git_cached := "?"   # "?" - ещё не искали, "" - git не найден

func _init(host: Node, log_cb: Callable) -> void:
	_host = host
	_log = log_cb

# Возвращает { ok: bool, sha: String, source: String, offline: bool }.
func get_remote_sha(owner: String, repo: String, branch: String) -> Dictionary:
	var url := "https://github.com/%s/%s.git" % [owner, repo]
	var git := _find_git()
	if git != "":
		var out: Array = []
		var code := OS.execute(git, ["ls-remote", url, "refs/heads/" + branch], out, true)
		var text := ""
		for chunk in out:
			text += str(chunk)
		text = text.strip_edges()
		if code == 0 and text != "":
			var first := text.split("\n")[0]
			var sha := first.split("\t")[0].strip_edges()
			if sha.length() >= 7:
				return {"ok": true, "sha": sha, "source": "git", "offline": false}
		var offline := text.findn("could not resolve") != -1 or text.findn("unable to access") != -1 or text == ""
		return {"ok": false, "sha": "", "source": "git", "offline": offline}
	return await _rest_sha(owner, repo, branch)

func _find_git() -> String:
	if _git_cached != "?":
		return _git_cached
	for candidate in GIT_CANDIDATES:
		var out: Array = []
		if OS.execute(candidate, ["--version"], out) == 0:
			_git_cached = candidate
			return candidate
	_git_cached = ""
	return ""

func _rest_sha(owner: String, repo: String, branch: String) -> Dictionary:
	if _host == null:
		return {"ok": false, "sha": "", "source": "rest", "offline": true}
	var http := HTTPRequest.new()
	_host.add_child(http)
	var url := "https://api.github.com/repos/%s/%s/commits/%s" % [owner, repo, branch]
	var headers := PackedStringArray(["User-Agent: AbyssMothKit", "Accept: application/vnd.github.sha"])
	var err := http.request(url, headers)
	if err != OK:
		http.queue_free()
		return {"ok": false, "sha": "", "source": "rest", "offline": true}
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var body: PackedByteArray = res[3]
	var offline := result == HTTPRequest.RESULT_CANT_CONNECT or result == HTTPRequest.RESULT_CANT_RESOLVE
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		return {"ok": true, "sha": body.get_string_from_utf8().strip_edges(), "source": "rest", "offline": false}
	return {"ok": false, "sha": "", "source": "rest", "offline": offline}

# --- версия/тег (для самообновления kit) ---

# a > b как semver ("0.5.10" > "0.5.3"). Префикс v игнорируется, нечисловые части = 0.
static func version_gt(a: String, b: String) -> bool:
	var pa := a.strip_edges().trim_prefix("v").split(".")
	var pb := b.strip_edges().trim_prefix("v").split(".")
	var n := maxi(pa.size(), pb.size())
	for i in range(n):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na > nb
	return false

static func _is_semver_tag(tag: String) -> bool:
	var t := tag.strip_edges().trim_prefix("v")
	if t == "":
		return false
	for part in t.split("."):
		if not part.is_valid_int():
			return false
	return true

# Наибольший semver-тег репозитория. Возвращает { ok, tag (без v), offline }.
func get_latest_tag(owner: String, repo: String) -> Dictionary:
	var url := "https://github.com/%s/%s.git" % [owner, repo]
	var git := _find_git()
	if git != "":
		var out: Array = []
		var code := OS.execute(git, ["ls-remote", "--tags", url], out, true)
		var text := ""
		for chunk in out:
			text += str(chunk)
		if code == 0:
			var best := ""
			for line in text.split("\n"):
				var idx := line.find("refs/tags/")
				if idx == -1:
					continue
				var tag := line.substr(idx + 10).strip_edges().trim_suffix("^{}").trim_prefix("v")
				if _is_semver_tag(tag) and (best == "" or version_gt(tag, best)):
					best = tag
			if best != "":
				return {"ok": true, "tag": best, "offline": false}
		var offline := text.findn("could not resolve") != -1 or text.strip_edges() == ""
		return {"ok": false, "tag": "", "offline": offline}
	return await _rest_latest_release(owner, repo)

func _rest_latest_release(owner: String, repo: String) -> Dictionary:
	if _host == null:
		return {"ok": false, "tag": "", "offline": true}
	var http := HTTPRequest.new()
	_host.add_child(http)
	var url := "https://api.github.com/repos/%s/%s/releases/latest" % [owner, repo]
	var headers := PackedStringArray(["User-Agent: AbyssMothKit", "Accept: application/vnd.github+json"])
	var err := http.request(url, headers)
	if err != OK:
		http.queue_free()
		return {"ok": false, "tag": "", "offline": true}
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var body: PackedByteArray = res[3]
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			return {"ok": true, "tag": str(data.get("tag_name", "")).trim_prefix("v"), "offline": false}
	var offline := result == HTTPRequest.RESULT_CANT_CONNECT or result == HTTPRequest.RESULT_CANT_RESOLVE
	return {"ok": false, "tag": "", "offline": offline}
