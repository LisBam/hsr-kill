class_name MatchReplayStore
extends RefCounted

## 对局回放文件持久化边界。该组件只负责把录制器产出的回放头与步骤流写入本地 `.lisbam_replay` 文件、
## 枚举与读取已保存回放、按玩家指定路径导出与导入回放；它不读取 GameState、不理解规则语义，
## 也不持有任何节点引用，录制器与界面层通过静态函数按需调用。
## 回放内容的采集由 MatchReplayRecorder 负责，回放播放由 MatchReplayPanel 负责。
##
## 文件格式：使用 FileAccess.open_compressed(GZIP) 容器，先写入一个 store_var 的回放头字典，
## 随后连续写入若干个 store_var 的步骤字典；步骤结构见 MatchReplayRecorder。
## 使用 Godot 二进制变体序列化而不是 JSON，完整保留 64 位整数、类型化数组与字典键类型。

## 回放文件的默认保存目录；所有已保存回放集中于此，测试可通过参数改用独立目录避免污染玩家数据。
const REPLAY_DIRECTORY: String = "user://replays"

## 回放文件的统一扩展名；导出与导入均以该后缀识别《崩铁杀》回放文件。
const REPLAY_FILE_EXTENSION: String = "lisbam_replay"

## 回放头中的固定魔数；读取端先校验该字段，防止把其他 Godot 序列化文件误认为回放。
const REPLAY_FILE_MAGIC: String = "LISBAM_REPLAY"

## 回放格式版本号；回放头或步骤结构发生不兼容变化时必须递增，读取端会拒绝版本不一致的文件。
const REPLAY_FORMAT_VERSION: int = 1

## 回放文件使用的压缩模式；GZIP 在快照流高度重复的场景下压缩率高且为 Godot 内置稳定格式。
const REPLAY_COMPRESSION_MODE: int = FileAccess.COMPRESSION_GZIP


## 确保回放目录存在；返回是否可用。所有写入口径统一先经过本入口，避免各调用方重复建目录。
static func ensure_replay_directory(directory_path: String = REPLAY_DIRECTORY) -> bool:
	if DirAccess.dir_exists_absolute(directory_path):
		return true
	return DirAccess.make_dir_recursive_absolute(directory_path) == OK


## 把回放头与临时步骤流合并写入正式回放文件；返回保存后的文件名（不含目录），失败返回空字符串。
## temp_steps_path 指向录制器以非压缩 store_var 流式写入的临时文件，本函数逐步转存到压缩容器。
static func save_replay_from_temp(header: Dictionary, temp_steps_path: String, directory_path: String = REPLAY_DIRECTORY) -> String:
	if header.is_empty() or not FileAccess.file_exists(temp_steps_path):
		return ""
	if not ensure_replay_directory(directory_path):
		return ""
	# 最终写入的回放文件名；按保存时刻生成并保证目录内唯一，避免连续保存互相覆盖。
	var file_name: String = _build_unique_replay_file_name(directory_path)
	# 压缩输出文件句柄；打开失败时直接放弃保存，不残留半成品文件。
	var output_file: FileAccess = FileAccess.open_compressed("%s/%s" % [directory_path, file_name], FileAccess.WRITE, REPLAY_COMPRESSION_MODE)
	if output_file == null:
		return ""
	# 完整回放头；魔数与版本由存储层统一补写，录制器只负责对局语义字段。
	var stamped_header: Dictionary = header.duplicate(true)
	stamped_header["magic"] = REPLAY_FILE_MAGIC
	stamped_header["format_version"] = REPLAY_FORMAT_VERSION
	output_file.store_var(stamped_header)
	# 临时步骤流句柄；只读打开失败按保存失败处理，并清理刚创建的空回放文件。
	var temp_file: FileAccess = FileAccess.open(temp_steps_path, FileAccess.READ)
	if temp_file == null:
		output_file.close()
		delete_replay(file_name, directory_path)
		return ""
	while temp_file.get_position() < temp_file.get_length():
		# 当前转存步骤；临时流与正式文件使用同一 store_var 结构，逐条搬运即可保持顺序。
		var step_variant: Variant = temp_file.get_var()
		if not step_variant is Dictionary:
			break
		output_file.store_var(step_variant)
	temp_file.close()
	output_file.close()
	return file_name


## 枚举目录中全部可解析回放；返回按保存时间倒序的条目数组，每项包含回放头、文件名与文件字节数。
static func list_replays(directory_path: String = REPLAY_DIRECTORY) -> Array[Dictionary]:
	# 回放条目结果；目录缺失或为空时返回空数组，调用方不需要区分失败原因。
	var entries: Array[Dictionary] = []
	# 回放目录访问器；目录不存在时按无回放处理，不向上传播文件系统错误。
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return entries
	for file_name: String in directory.get_files():
		if file_name.get_extension() != REPLAY_FILE_EXTENSION:
			continue
		# 当前文件的回放头；无法解析的文件直接跳过，保证列表内条目全部可播放。
		var header: Dictionary = read_replay_header("%s/%s" % [directory_path, file_name])
		if header.is_empty():
			continue
		entries.append({
			"file_name": file_name,
			"header": header,
			"file_size": _get_file_size("%s/%s" % [directory_path, file_name]),
		})
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int((left.get("header", {}) as Dictionary).get("saved_at_unix", 0)) > int((right.get("header", {}) as Dictionary).get("saved_at_unix", 0)))
	return entries


## 读取并校验单个回放文件的回放头；文件缺失、魔数不符或版本不一致时统一返回空字典。
static func read_replay_header(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	# 压缩回放文件句柄；非本格式文件在打开或首个 get_var 阶段即失败，统一按无效回放处理。
	var file: FileAccess = FileAccess.open_compressed(file_path, FileAccess.READ, REPLAY_COMPRESSION_MODE)
	if file == null:
		return {}
	# 回放头反序列化结果；损坏文件会得到 null 或非字典值。
	var header_variant: Variant = file.get_var()
	file.close()
	if not header_variant is Dictionary:
		return {}
	# 回放头字典；只做魔数与版本校验，深层字段由播放界面按需读取并自行兜底。
	var header: Dictionary = header_variant as Dictionary
	if str(header.get("magic", "")) != REPLAY_FILE_MAGIC:
		return {}
	if int(header.get("format_version", -1)) != REPLAY_FORMAT_VERSION:
		return {}
	return header


## 读取单个回放文件的全部步骤；返回按录制顺序排列的步骤字典数组，文件无效时返回空数组。
## 播放界面一次性载入全部步骤以支持时间轴任意拖动；步骤结构见 MatchReplayRecorder 的步骤常量。
static func read_replay_steps(file_path: String) -> Array[Dictionary]:
	# 步骤结果数组；回放头校验失败时保持为空，播放界面据此提示文件损坏。
	var steps: Array[Dictionary] = []
	if read_replay_header(file_path).is_empty():
		return steps
	# 压缩回放文件句柄；回放头刚校验通过，此处再次打开并跳过头部逐条读取步骤。
	var file: FileAccess = FileAccess.open_compressed(file_path, FileAccess.READ, REPLAY_COMPRESSION_MODE)
	if file == null:
		return steps
	file.get_var()
	while file.get_position() < file.get_length():
		# 当前步骤反序列化结果；遇到损坏尾部立即停止，已读出的完整前缀仍可播放。
		var step_variant: Variant = file.get_var()
		if not step_variant is Dictionary:
			break
		steps.append(step_variant as Dictionary)
	file.close()
	return steps


## 把目录内指定回放导出到玩家给定的绝对路径；返回是否导出成功。
## 导出为逐字节复制，目标路径缺少统一后缀时自动补齐，目标目录不存在时按失败处理。
static func export_replay(file_name: String, destination_path: String, directory_path: String = REPLAY_DIRECTORY) -> bool:
	# 源回放完整路径；源文件必须是本目录内已保存的合法回放。
	var source_path: String = "%s/%s" % [directory_path, file_name]
	if read_replay_header(source_path).is_empty():
		return false
	# 规范化后的导出目标路径；统一补齐 .lisbam_replay 后缀，保证导出文件可被再次识别导入。
	var normalized_destination: String = destination_path.strip_edges()
	if normalized_destination.is_empty():
		return false
	if normalized_destination.get_extension() != REPLAY_FILE_EXTENSION:
		normalized_destination = "%s.%s" % [normalized_destination, REPLAY_FILE_EXTENSION]
	return _copy_file_bytes(source_path, normalized_destination)


## 从玩家给定的绝对路径导入一份回放文件；成功返回导入后的目录内文件名，失败返回空字符串。
## 导入前完整校验魔数与版本，文件名与现有回放冲突时自动追加序号，不覆盖已有回放。
static func import_replay(source_path: String, directory_path: String = REPLAY_DIRECTORY) -> String:
	if read_replay_header(source_path).is_empty():
		return ""
	if not ensure_replay_directory(directory_path):
		return ""
	# 导入后的目标文件名；沿用源文件基础名便于玩家辨认，冲突时由唯一化入口追加序号。
	var target_name: String = _build_available_file_name(source_path.get_file().get_basename(), directory_path)
	if not _copy_file_bytes(source_path, "%s/%s" % [directory_path, target_name]):
		return ""
	return target_name


## 删除目录内指定回放文件；文件不存在时静默成功，界面删除与保存失败清理共用本入口。
static func delete_replay(file_name: String, directory_path: String = REPLAY_DIRECTORY) -> bool:
	# 待删除回放完整路径；只允许删除回放目录内的文件，不接受任意绝对路径。
	var target_path: String = "%s/%s" % [directory_path, file_name]
	if not FileAccess.file_exists(target_path):
		return true
	# 回放目录访问器；目录打开失败时放弃删除而不抛错。
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return false
	return directory.remove(file_name) == OK


## 生成目录内唯一的新回放文件名；以保存时刻的日期时间命名，同秒重复保存时追加递增序号。
static func _build_unique_replay_file_name(directory_path: String) -> String:
	# 当前系统日期时间字典；仅用于生成可读文件名，不进入回放头的权威时间字段。
	var now: Dictionary = Time.get_datetime_dict_from_system()
	# 文件基础名；固定“replay_年月日_时分秒”格式，保证按名称排序与按时间排序一致。
	var base_name: String = "replay_%04d%02d%02d_%02d%02d%02d" % [int(now.get("year", 0)), int(now.get("month", 0)), int(now.get("day", 0)), int(now.get("hour", 0)), int(now.get("minute", 0)), int(now.get("second", 0))]
	return _build_available_file_name(base_name, directory_path)


## 把期望基础名规范化为目录内未被占用的完整文件名；冲突时追加“_2”“_3”等递增序号。
static func _build_available_file_name(preferred_base_name: String, directory_path: String) -> String:
	# 清理后的基础名；移除路径分隔符等非法字符，空结果回退固定前缀，防止构造出目录穿越路径。
	var sanitized_base: String = preferred_base_name.validate_filename().strip_edges()
	if sanitized_base.is_empty():
		sanitized_base = "replay"
	# 候选文件名；先尝试无序号原名，占用时从 2 开始追加序号直到可用。
	var candidate_name: String = "%s.%s" % [sanitized_base, REPLAY_FILE_EXTENSION]
	# 冲突递增序号；从 2 开始符合“同名文件副本”的常见命名习惯。
	var suffix_index: int = 2
	while FileAccess.file_exists("%s/%s" % [directory_path, candidate_name]):
		candidate_name = "%s_%d.%s" % [sanitized_base, suffix_index, REPLAY_FILE_EXTENSION]
		suffix_index += 1
	return candidate_name


## 逐字节复制文件；源不可读或目标不可写时返回 false，不残留半成品目标文件内容。
static func _copy_file_bytes(source_path: String, destination_path: String) -> bool:
	# 源文件句柄；读取失败直接失败，压缩容器按普通字节流整体复制即可保持格式。
	var source_file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return false
	# 源文件完整字节；回放文件为压缩容器，实际字节量远小于快照原始体积，可一次读入。
	var buffer: PackedByteArray = source_file.get_buffer(source_file.get_length())
	source_file.close()
	# 目标文件句柄；WRITE 模式会截断旧文件，写入完成后立即关闭确保落盘。
	var destination_file: FileAccess = FileAccess.open(destination_path, FileAccess.WRITE)
	if destination_file == null:
		return false
	destination_file.store_buffer(buffer)
	destination_file.close()
	return true


## 读取文件字节数；文件不可读时返回 0，仅用于回放列表的体积展示。
static func _get_file_size(file_path: String) -> int:
	# 只读文件句柄；打开失败按 0 字节处理，不影响列表其余条目。
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return 0
	# 文件长度；读取后立即关闭句柄。
	var length: int = file.get_length()
	file.close()
	return length
