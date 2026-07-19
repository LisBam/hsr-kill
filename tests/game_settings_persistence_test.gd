extends Node

## GameSettings 本地持久化验证。测试使用独立 user:// 文件，不读取或改写玩家实际设置文件。

## 待测试的 GameSettings 脚本；独立实例用于模拟一次完整的“保存后重新启动”读取过程。
const GAME_SETTINGS_SCRIPT: Script = preload("res://scripts/autoload/game_settings.gd")

## 测试专用配置文件路径；只在 user:// 目录创建，结束后必须删除以免影响后续测试。
const TEST_SETTINGS_FILE_PATH: String = "user://game_settings_persistence_test.cfg"

## 测试保存的玩家名称；前后空白用于验证恢复时仍走联机名称标准化流程。
const TEST_PLAYER_NAME: String = "  存档测试玩家  "

## 测试保存的联机形象 ID；使用当前数据库已登记的稳定武将 ID，恢复后不应被纹理路径替代。
const TEST_AVATAR_CHARACTER_ID: String = "xier"

## 测试保存的下一局人数；值位于2至10的合法范围，验证游戏设置与联机资料共同写入一个文件。
const TEST_NEXT_MATCH_PLAYER_COUNT: int = 6


## 创建独立设置节点、写入所有需要持久化的选项、重新实例化读取并校验字段。
func _ready() -> void:
	_cleanup_test_file()
	# 首次运行设置节点；在进入场景树前指定独立文件路径，避免自动加载流程读取真实玩家存档。
	var saving_settings: Node = GAME_SETTINGS_SCRIPT.new() as Node
	saving_settings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)
	add_child(saving_settings)
	saving_settings.call("set_card_name_mode", GameSettings.NameMode.ORIGINAL)
	saving_settings.call("set_ai_response_delay_seconds", 0.65)
	saving_settings.call("set_game_speed_interval_seconds", 0.8)
	saving_settings.call("set_ui_style", UIStyleRegistry.STYLE_DECADE_WOOD)
	saving_settings.call("set_auto_identity_marking_enabled", false)
	saving_settings.call("set_next_match_player_count", TEST_NEXT_MATCH_PLAYER_COUNT)
	saving_settings.call("set_online_player_name", TEST_PLAYER_NAME)
	saving_settings.call("set_online_avatar_character_id", TEST_AVATAR_CHARACTER_ID)
	if FileAccess.file_exists(TEST_SETTINGS_FILE_PATH):
		_fail("save_should_be_deferred")
		return
	# 合并保存刷新；设置层公开入口确保测试不依赖真实时间等待，并验证最终一次写盘包含全部字段。
	saving_settings.call("flush_pending_settings")
	# 已写入的配置读取器；直接核对磁盘字段，确保测试没有只验证同一内存节点。
	var saved_file: ConfigFile = ConfigFile.new()
	if saved_file.load(TEST_SETTINGS_FILE_PATH) != OK:
		_fail("save_file_missing")
		return
	if int(saved_file.get_value(GameSettings.SETTINGS_METADATA_SECTION, "schema_version", 0)) != GameSettings.SETTINGS_SCHEMA_VERSION or int(saved_file.get_value(GameSettings.GAMEPLAY_SETTINGS_SECTION, "next_match_player_count", 0)) != TEST_NEXT_MATCH_PLAYER_COUNT or str(saved_file.get_value(GameSettings.ONLINE_SETTINGS_SECTION, "player_name", "")) != "存档测试玩家" or str(saved_file.get_value(GameSettings.ONLINE_SETTINGS_SECTION, "avatar_character_id", "")) != TEST_AVATAR_CHARACTER_ID:
		_fail("saved_fields")
		return
	saving_settings.queue_free()
	await get_tree().process_frame
	# 模拟下一次程序启动的设置节点；进入树时自动读取同一独立配置文件。
	var restored_settings: Node = GAME_SETTINGS_SCRIPT.new() as Node
	restored_settings.set("_settings_file_path", TEST_SETTINGS_FILE_PATH)
	add_child(restored_settings)
	await get_tree().process_frame
	if int(restored_settings.get("card_name_mode")) != int(GameSettings.NameMode.ORIGINAL) or not is_equal_approx(float(restored_settings.get("ai_response_delay_seconds")), 0.65) or not is_equal_approx(float(restored_settings.get("game_speed_interval_seconds")), 0.8) or str(restored_settings.get("ui_style_id")) != UIStyleRegistry.STYLE_DECADE_WOOD or bool(restored_settings.get("auto_identity_marking_enabled")) or int(restored_settings.get("next_match_player_count")) != TEST_NEXT_MATCH_PLAYER_COUNT or str(restored_settings.get("online_player_name")) != "存档测试玩家" or str(restored_settings.get("online_avatar_character_id")) != TEST_AVATAR_CHARACTER_ID:
		_fail("restored_fields")
		return
	restored_settings.queue_free()
	_cleanup_test_file()
	print("GAME_SETTINGS_PERSISTENCE_PASS")
	get_tree().quit()


## 删除测试专用文件；文件不存在时也视为正常，保证测试可重复运行。
func _cleanup_test_file() -> void:
	# 测试文件绝对路径；DirAccess 的静态删除接口需要本机文件系统路径而不是 user:// 别名。
	var absolute_test_file_path: String = ProjectSettings.globalize_path(TEST_SETTINGS_FILE_PATH)
	if FileAccess.file_exists(TEST_SETTINGS_FILE_PATH):
		DirAccess.remove_absolute(absolute_test_file_path)


## 输出稳定失败标识并清理临时文件；任何失败都不应在用户目录残留测试设置。
func _fail(reason: String) -> void:
	_cleanup_test_file()
	printerr("GAME_SETTINGS_PERSISTENCE_FAIL %s" % reason)
	get_tree().quit(1)
