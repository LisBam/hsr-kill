class_name ConquestSaveStore
extends RefCounted

## 过关斩将存档持久化边界。该组件只负责把控制器生成的可序列化存档字典写入本地文件、读取并做基础校验、以及清除存档；
## 它不读取 GameState、不理解规则语义，也不持有任何节点引用，规则层与界面层通过静态函数按需调用。
## 存档内容的构建与恢复分别由 MatchController 的 _build_conquest_save_data() 与 resume_conquest_match() 负责。

## 存档文件的默认保存路径；使用 var_to_str 文本格式保存，完整保留64位整数与类型化数组，避免JSON浮点精度丢失。
const SAVE_FILE_PATH: String = "user://conquest_save.dat"

## 存档格式版本号；存档结构发生不兼容变化时必须递增，读取端会拒绝版本不一致的旧文件。
const SAVE_FORMAT_VERSION: int = 1


## 判断当前是否存在一份可解析的过关斩将存档；主菜单据此把“开始游戏”切换为“继续上次游戏”。
static func has_save(file_path: String = SAVE_FILE_PATH) -> bool:
	return not read_save(file_path).is_empty()


## 读取并校验存档文件；文件缺失、无法解析或版本与模式不匹配时统一返回空字典，调用方不需要区分失败原因。
static func read_save(file_path: String = SAVE_FILE_PATH) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	# 存档文件句柄；只读打开失败时按无存档处理，不向上传播文件系统错误。
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	# 存档原始文本；var_to_str 生成的Godot文本序列化格式，保留整数精度与字典键类型。
	var raw_text: String = file.get_as_text()
	file.close()
	# 反序列化结果；损坏文件会得到 null 或非字典值，统一按无效存档处理。
	var parsed: Variant = str_to_var(raw_text)
	if not parsed is Dictionary:
		return {}
	# 存档字典；基础结构校验只看版本与模式，深层内容校验由控制器恢复入口负责。
	var save_data: Dictionary = parsed as Dictionary
	if int(save_data.get("save_version", -1)) != SAVE_FORMAT_VERSION:
		return {}
	if str(save_data.get("match_mode", "")) != IdentityRules.MODE_CONQUEST:
		return {}
	if (save_data.get("players", []) as Array).is_empty():
		return {}
	return save_data


## 把控制器生成的存档字典写入文件；返回是否写入成功，失败时不残留半成品文件内容。
static func write_save(save_data: Dictionary, file_path: String = SAVE_FILE_PATH) -> bool:
	if save_data.is_empty():
		return false
	# 存档文件句柄；WRITE 模式会截断旧文件，写入完成后立即关闭确保落盘。
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(var_to_str(save_data))
	file.close()
	return true


## 删除存档文件；文件不存在时静默成功，终局清档与损坏存档清理共用本入口。
static func clear_save(file_path: String = SAVE_FILE_PATH) -> void:
	if not FileAccess.file_exists(file_path):
		return
	# 用户目录访问器；存档固定位于 user:// 下，目录打开失败时放弃删除而不抛错。
	var directory: DirAccess = DirAccess.open("user://")
	if directory != null:
		directory.remove(file_path)
