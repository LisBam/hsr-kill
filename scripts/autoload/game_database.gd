extends Node

## 统一数据仓库。卡牌、武将与技能从 game_data 对应目录自动发现，牌堆与势力继续使用纯数据文件。
## 目录中的每个源码定义既提供静态元数据，也保留自身规则入口；新增内容不需要修改本仓库或集中注册表。

## 卡牌源码目录；每个 `.gd` 文件必须实例化为 CardDefinition，并提供全项目唯一 ID。
const CARDS_DIRECTORY: String = "res://game_data/cards"

## 武将源码目录；每个 `.gd` 文件必须实例化为 CharacterDefinition，并直接引用所需技能脚本。
const CHARACTERS_DIRECTORY: String = "res://game_data/characters"

## 武将插画自动发现目录；插画基础名必须与对应武将脚本文件名完全一致，运行时不需要在武将元数据中手填路径。
const CHARACTER_IMAGE_DIRECTORY: String = CHARACTERS_DIRECTORY + "/image"

## 武将插画格式检查顺序；同时存在同名文件时优先使用支持透明通道的 PNG，其次使用 JPG。
const CHARACTER_IMAGE_EXTENSIONS: Array[String] = ["png", "jpg"]

## 技能源码目录；每个 `.gd` 文件必须实例化为 SkillDefinition，运行时会为每名持有者创建独立实例。
const SKILLS_DIRECTORY: String = "res://game_data/skills"

## 角色持续效果源码目录；每个 `.gd` 文件必须实例化为 PlayerEffect，并提供全项目唯一 ID。
## 效果与技能分属不同目录，因为二者生命周期不同：技能实例跟随持有者武将，
## 而效果实例挂在被施加的角色身上，施加者阵亡、换将或被非锁定技失效压制都不应撤回它。
const PLAYER_EFFECTS_DIRECTORY: String = "res://game_data/effects"

## 牌堆配置文件路径；牌堆条目只保存花色、点数与稳定卡牌 ID，不重复保存卡牌规则。
const DECKS_PATH: String = "res://data/decks.json"

## 势力展示配置文件路径；势力只提供名称、简称与颜色，不承载武将或技能逻辑。
const FACTIONS_PATH: String = "res://game_data/factions.json"

## 每种卡牌名称模式最多缓存的完整说明文本数量；512足以覆盖现有静态技能与界面说明，并限制异常动态文本增长。
const MAX_RESOLVED_CARD_TEXT_CACHE_ENTRIES_PER_MODE: int = 512

## 以卡牌 ID 为键的卡牌元数据索引；界面、AI、网络与规则查询只读取深拷贝。
var cards: Dictionary = {}:
	get:
		_ensure_loaded()
		return cards

## 原版牌名或项目牌名到卡牌元数据的只读索引；数据库重载时重建，用于说明文本常数时间解析。
var _card_definitions_by_display_name: Dictionary = {}

## 卡牌名称模式到“原始说明→解析结果”的缓存；字符串不可变，重复展示同一技能时可安全直接复用。
var _resolved_card_text_cache_by_mode: Dictionary = {}

## 以卡牌 ID 为键的卡牌源码定义对象；效果解析器通过该索引调用对应卡牌文件的函数。
var card_definitions: Dictionary = {}:
	get:
		_ensure_loaded()
		return card_definitions

## 以卡牌 ID 为键的卡牌脚本资源索引；装备等持续区域效果会由该脚本创建独立运行时实例。
var card_scripts: Dictionary = {}:
	get:
		_ensure_loaded()
		return card_scripts

## 以牌堆 ID 为键的牌堆配置索引；牌堆条目只引用卡牌 ID，逻辑不重复存储。
var decks: Dictionary = {}:
	get:
		_ensure_loaded()
		return decks

## 以武将 ID 为键的武将元数据索引；技能数组由武将源码直接引用的技能脚本自动生成。
var characters: Dictionary = {}:
	get:
		_ensure_loaded()
		return characters

## 以武将 ID 为键的武将源码定义对象；用于校验技能脚本引用并为工具链提供源码入口。
var character_definitions: Dictionary = {}:
	get:
		_ensure_loaded()
		return character_definitions

## 以势力 ID 为键的势力展示元数据索引；不参与身份、距离、伤害或胜负规则。
var factions: Dictionary = {}:
	get:
		_ensure_loaded()
		return factions

## 以技能 ID 为键的技能元数据索引；技能栏、网络与回放只读取该字典的深拷贝。
var skills: Dictionary = {}:
	get:
		_ensure_loaded()
		return skills

## 以技能 ID 为键的技能脚本资源索引；每局会通过 create_skill 创建互不共享状态的运行时实例。
var skill_scripts: Dictionary = {}:
	get:
		_ensure_loaded()
		return skill_scripts

## 以效果 ID 为键的角色持续效果元数据索引；界面与工具链只读取该字典的深拷贝。
var player_effects: Dictionary = {}:
	get:
		_ensure_loaded()
		return player_effects

## 以效果 ID 为键的效果脚本资源索引；对局开始时按角色身上的持久状态重建实例。
var player_effect_scripts: Dictionary = {}:
	get:
		_ensure_loaded()
		return player_effect_scripts

## 最近一次载入产生的错误列表；为空表示全部源码定义、牌堆和势力引用均可安全使用。
var validation_errors: Array[String] = []:
	get:
		_ensure_loaded()
		return validation_errors


## 节点进入场景树时载入全部静态数据，确保其他模块可立即查询。
## 首页先完成绘制，再由独立数据库副本在后台准备；首次查询会等待完整结果，避免观察到部分数据。
signal database_ready()

## 后台载入线程；运行期间只操作独立副本，主线程合并前不得读取其容器。
var _loading_thread: Thread = Thread.new()

## 后台使用的未入树数据库副本；线程结束后由主线程转交索引并释放。
var _database_copy: Node

## 内容目录的重载版本；每次完整扫描后递增，界面可据此失效旧的牌面缓存。
var content_revision: int = 0

## 完整数据是否已经提交；默认关闭，提交或同步回退完成后保持开启。
var _database_loaded: bool = false

## 是否为后台临时副本；默认关闭，副本跳过主线程等待并独立执行原有校验。
var _is_loader_copy: bool = false

## 同步加载或结果提交是否正在执行；用于避免内部索引访问重复触发初始化。
var _loading_in_main: bool = false


func _ready() -> void:
	# 等待主场景完成首帧，优先让首页得到显示和输入机会。
	await get_tree().process_frame
	await get_tree().process_frame
	if not _database_loaded:
		_start_background_load()


## 返回完整目录是否已经提交；界面用它判断是否需要展示等待提示。
func is_database_ready() -> bool:
	return _database_loaded


## 等待完整内容目录；界面入口可使用信号异步等待，不阻塞已经显示的首页。
func wait_until_ready() -> void:
	if not _database_loaded:
		await database_ready


## 开始在独立副本中加载目录；线程不可用时同步回退，保持数据正确性。
func _start_background_load() -> void:
	if _database_loaded or _loading_thread.is_started():
		return
	_database_copy = get_script().new()
	_database_copy._is_loader_copy = true
	if _loading_thread.start(Callable(_database_copy, "reload_all")) != OK:
		_database_copy.free()
		_database_copy = null
		_ensure_loaded()


## 后台任务完成后在主线程发布完整快照；无需让首页等待首次页面访问。
func _process(_delta: float) -> void:
	if _loading_thread.is_started() and not _loading_thread.is_alive():
		_ensure_loaded()


## 同步获取完整结果；仅兼容直接读取索引或同步调用的现有规则与测试入口。
func _ensure_loaded() -> void:
	if _database_loaded or _is_loader_copy or _loading_in_main:
		return
	_loading_in_main = true
	if _loading_thread.is_started():
		_loading_thread.wait_to_finish()
		for property_name: String in ["cards", "_card_definitions_by_display_name", "_resolved_card_text_cache_by_mode", "card_definitions", "card_scripts", "decks", "characters", "character_definitions", "factions", "skills", "skill_scripts", "player_effects", "player_effect_scripts", "validation_errors", "content_revision"]:
			set(property_name, _database_copy.get(property_name))
		_database_copy.free()
		_database_copy = null
	else:
		reload_all()
	_database_loaded = true
	_loading_in_main = false
	database_ready.emit()


## 应用退出时回收后台线程，避免线程仍访问项目资源。
func _exit_tree() -> void:
	if _loading_thread.is_started():
		_loading_thread.wait_to_finish()
		if _database_copy != null:
			_database_copy.free()
			_database_copy = null


## 重新扫描源码目录并校验全部配置；目录新增或删除文件后调用即可刷新索引。
func reload_all() -> bool:
	_ensure_loaded()
	validation_errors.clear()
	cards.clear()
	_card_definitions_by_display_name.clear()
	_resolved_card_text_cache_by_mode.clear()
	card_definitions.clear()
	card_scripts.clear()
	decks.clear()
	characters.clear()
	character_definitions.clear()
	factions.clear()
	skills.clear()
	skill_scripts.clear()
	player_effects.clear()
	player_effect_scripts.clear()

	_load_skills()
	_load_player_effects()
	_load_cards()
	_load_characters()
	_load_decks()
	_load_factions()
	_validate_decks()
	_validate_factions()
	_validate_characters()
	content_revision += 1
	return validation_errors.is_empty()


## 返回指定卡牌定义的深拷贝，防止调用方误改全局配置。
func get_card(card_id: String) -> Dictionary:
	if card_id.is_empty():
		return {}
	_ensure_loaded()
	return (cards.get(card_id, {}) as Dictionary).duplicate(true)


## 返回指定卡牌的源码定义对象；对象只保存静态数据，具体效果函数不得持有对局状态。
func get_card_definition(card_id: String) -> CardDefinition:
	_ensure_loaded()
	return card_definitions.get(card_id) as CardDefinition


## 为装备或其他持续区域效果创建独立卡牌实例；实例尚未绑定玩家、实体 UID 或事件总线。
func create_card_runtime(card_id: String) -> CardDefinition:
	_ensure_loaded()
	# 卡牌脚本资源；不存在时返回 null，调用方不得复用数据库中的静态定义对象保存对局状态。
	var card_script: Script = card_scripts.get(card_id) as Script
	if card_script == null:
		return null
	return card_script.new() as CardDefinition


## 返回指定武将定义的深拷贝，空结果表示 ID 未登记。
func get_character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	_ensure_loaded()
	return (characters.get(character_id, {}) as Dictionary).duplicate(true)


## 返回允许进入普通选将、随机抽取与模式换将池的武将ID；特殊武将仅在显式包含时进入结果。
func get_selectable_character_ids(include_special: bool = false) -> Array[String]:
	_ensure_loaded()
	# 可选武将结果；保留数据库扫描后的稳定键顺序，具体选将服务仍负责洗牌与候选排序。
	var result: Array[String] = []
	for character_id_variant: Variant in characters.keys():
		# 当前武将稳定ID；用于读取特殊标记并写入纯字符串结果。
		var character_id: String = str(character_id_variant)
		# 当前武将静态定义；special=true表示只能由特定规则显式生成。
		var character_definition: Dictionary = characters.get(character_id, {}) as Dictionary
		if include_special or not bool(character_definition.get("special", false)):
			result.append(character_id)
	return result


## 返回武将的本地化显示名称；界面只能使用该入口显示名称，避免稳定英文 ID 泄漏到玩家可见区域。
func resolve_character_name(character_id: String) -> String:
	if character_id.is_empty():
		return "未选武将"
	_ensure_loaded()
	# 当前武将定义；从静态索引读取以取得配置的中文 display_name。
	# 本函数只返回不可变字符串，可直接读取内部索引而无须深复制整份静态元数据。
	var character_definition: Dictionary = characters.get(character_id, {}) as Dictionary
	# 当前武将配置的显示名称；空值表示配置缺失或未填写本地化文本。
	var display_name: String = str(character_definition.get("display_name", "")).strip_edges()
	if not display_name.is_empty():
		return display_name
	return "未选武将" if character_id.is_empty() else "未知武将"


## 返回指定势力的展示元数据深拷贝；空结果表示势力 ID 未登记，调用方应使用中性视觉回退。
func get_faction(faction_id: String) -> Dictionary:
	_ensure_loaded()
	return (factions.get(faction_id, {}) as Dictionary).duplicate(true)


## 返回指定技能元数据的深拷贝，空结果表示技能 ID 未登记。
func get_skill(skill_id: String) -> Dictionary:
	_ensure_loaded()
	return (skills.get(skill_id, {}) as Dictionary).duplicate(true)


## 按当前卡牌名称模式替换文本中的【原版牌名】引用；技能说明可复用本入口保持静态原文与动态展示解耦。
## 只替换完整书名号包裹的已登记名称，普通叙述文字、稳定 ID 与规则数值均保持不变。
## 括号引用同时允许使用原版牌名或崩铁杀牌名；展示时统一解析到当前模式。
## 解析采用完整括号精确匹配，技能名、未登记术语和括号外正文保持不变。
func resolve_card_names_in_text(source_text: String) -> String:
	_ensure_loaded()
	# 当前卡牌名称模式；原版与项目名分别保存缓存，切换设置时不会复用另一模式的旧文本。
	var name_mode_key: int = int(GameSettings.card_name_mode)
	# 当前模式文本缓存；字典只保存不可变字符串，不持有界面节点或运行时规则对象。
	var mode_cache: Dictionary = _resolved_card_text_cache_by_mode.get(name_mode_key, {}) as Dictionary
	if mode_cache.has(source_text):
		return str(mode_cache.get(source_text, ""))
	# 当前解析结果；从调用方原文副本开始，仅在命中完整卡牌名称引用时更新。
	# 实现使用逐段追加而非原地替换，仍保持上述只修改完整引用的职责。
	# 当前解析结果；逐段追加可以避免某个牌名替换后又被另一张牌的名称二次命中。
	var resolved_text: String = ""
	# 当前扫描位置；范围为0至文本长度，始终从上一组完整括号之后继续。
	var cursor: int = 0
	while cursor < source_text.length():
		# 下一处左括号位置；不存在时把剩余正文原样追加并结束。
		var opening_index: int = source_text.find("【", cursor)
		if opening_index < 0:
			resolved_text += source_text.substr(cursor)
			break
		# 与当前左括号配对的首个右括号；缺失时保留剩余原文，避免破坏不完整内容。
		var closing_index: int = source_text.find("】", opening_index + 1)
		if closing_index < 0:
			resolved_text += source_text.substr(cursor)
			break
		resolved_text += source_text.substr(cursor, opening_index - cursor)
		# 当前括号文本；只有与任一卡牌原版名或崩铁杀名完全一致时才参与动态切换。
		var referenced_name: String = source_text.substr(opening_index + 1, closing_index - opening_index - 1)
		# 当前命中的卡牌定义；空字典表示括号内是技能名、术语或未登记内容，应保持原样。
		var matched_definition: Dictionary = _find_card_by_display_name(referenced_name)
		if matched_definition.is_empty():
			resolved_text += source_text.substr(opening_index, closing_index - opening_index + 1)
		else:
			resolved_text += "【%s】" % GameSettings.resolve_card_name(matched_definition)
		cursor = closing_index + 1
	if mode_cache.size() >= MAX_RESOLVED_CARD_TEXT_CACHE_ENTRIES_PER_MODE:
		# 缓存达到边界时整体清空当前模式；静态说明会按实际访问重新填充，避免维护复杂淘汰链表。
		mode_cache.clear()
	mode_cache[source_text] = resolved_text
	_resolved_card_text_cache_by_mode[name_mode_key] = mode_cache
	return resolved_text


## 按原版牌名或崩铁杀牌名精确查找卡牌定义；仅供技能说明等括号文本动态解析，不接受部分匹配。
func _find_card_by_display_name(display_name: String) -> Dictionary:
	if display_name.is_empty():
		return {}
	# 当前卡牌定义；名称解析始终读取数据库已校验的双名称元数据。
	# 当前卡牌定义；数据库加载阶段已校验稳定ID，名称字段缺失时使用空字符串跳过。
	# 当前卡牌原版名称；技能源码统一以该名称书写，空名称不会参与替换。
	# 当前原版牌名；技能描述以三国杀牌名书写时通过该字段命中。
	# 当前崩铁杀牌名；技能描述以项目牌名书写时通过该字段命中。
	# 原版名称引用标记；完整匹配可避免短牌名误改普通语句或其他牌名的一部分。
	# 当前直接比较括号内部文本，不再额外构造引用字符串，完整匹配边界由扫描器保证。
	# 当前模式名称引用；统一复用 GameSettings，保证卡牌牌面与技能说明显示一致。
	# 命中定义后由调用函数统一复用 GameSettings 生成当前模式名称。
	# 上述字段已经在数据库加载阶段建立只读名称索引，查询时无需再次遍历全部卡牌。
	return _card_definitions_by_display_name.get(display_name, {}) as Dictionary


## 判断一个牌名是否已被静态卡牌定义占用；供运行时造牌的牌名唯一性校验使用。
##
## 【为什么必须走双名索引】牌名不只在牌面上出现：技能说明、卡牌说明与信息框标题都会把文本里的【牌名】
## 再解析一次（`resolve_card_names_in_text`）。若造出的牌名与任一已登记定义的原版名或项目名相同，
## 那么它出现在信息框标题里时会被**改写**成那张牌的名字，玩家看到的牌名与实际牌名不一致。
## 因此唯一性必须按“原版名 ∪ 项目名”这一与解析器完全相同的口径判定，不能只比对其中一个。
##
## 【范围】本函数只回答“与静态定义重名”，不涉及本局已经造出的牌；后者由控制器的造牌端口另行比对
## （那些牌不写进任何 GameDatabase 容器，因此这里查不到，这是刻意的：造牌不得污染图鉴与静态卡表）。
func is_card_display_name_taken(display_name: String) -> bool:
	_ensure_loaded()
	# 去首尾空白后判定；调用方传入带空格的文本不应因为空白差异而绕过重名检查。
	var normalized_name: String = display_name.strip_edges()
	if normalized_name.is_empty():
		return false
	return _card_definitions_by_display_name.has(normalized_name)


## 返回全部已被静态卡牌定义占用的牌名（原版名 ∪ 项目名），按字典序排列。
##
## 【用途】运行时造牌的界面需要**在玩家输入过程中**即时提示重名，而 `is_card_display_name_taken` 只能回答
## 「某一个名字是否被占用」。界面若为每次按键遍历全部卡牌定义，会把静态内容层当成可变状态反复扫描；
## 因此这里一次性给出只读快照，界面只做本地集合比对，最终唯一性仍由控制器在提交时权威复核。
## 【口径】与 `is_card_display_name_taken` 完全同源（同一张索引表），不存在两套判定标准。
func get_all_card_display_names() -> Array[String]:
	_ensure_loaded()
	# 结果牌名；排序后返回，保证同一份静态内容在任何机器上得到相同顺序。
	var result: Array[String] = []
	for display_name_variant: Variant in _card_definitions_by_display_name.keys():
		result.append(str(display_name_variant))
	result.sort()
	return result


## 把卡牌的原版名与项目名写入只读名称索引；重复名称保持首个已登记定义，与原线性扫描命中顺序一致。
func _index_card_display_names(card_definition: Dictionary) -> void:
	# 当前卡牌原版名称；空名称不会参与技能说明中的完整书名号匹配。
	var original_name: String = str(card_definition.get("original_name", "")).strip_edges()
	# 当前卡牌项目名称；与原版名称相同时只写入同一个索引条目。
	var custom_name: String = str(card_definition.get("custom_name", "")).strip_edges()
	for display_name: String in [original_name, custom_name]:
		if display_name.is_empty() or _card_definitions_by_display_name.has(display_name):
			continue
		_card_definitions_by_display_name[display_name] = card_definition


## 为一名技能持有者创建独立技能实例；实例尚未绑定玩家，也不会自动订阅规则事件。
func create_skill(skill_id: String) -> SkillDefinition:
	_ensure_loaded()
	# 技能脚本资源；不存在时返回 null，让调用方以统一配置错误处理。
	var skill_script: Script = skill_scripts.get(skill_id) as Script
	if skill_script == null:
		return null
	return skill_script.new() as SkillDefinition


## 为一个承载角色创建独立效果实例；实例尚未绑定角色，也不会自动订阅规则事件。
## 与 create_skill 同构：这里只负责按 ID 造对象，生命周期与订阅完全由控制器托管。
func create_player_effect(effect_id: String) -> PlayerEffect:
	_ensure_loaded()
	# 效果脚本资源；不存在时返回 null，让调用方按统一配置错误处理。
	var effect_script: Script = player_effect_scripts.get(effect_id) as Script
	if effect_script == null:
		return null
	return effect_script.new() as PlayerEffect


## 返回指定效果的元数据深拷贝，空结果表示效果 ID 未登记。
func get_player_effect(effect_id: String) -> Dictionary:
	_ensure_loaded()
	return (player_effects.get(effect_id, {}) as Dictionary).duplicate(true)


## 返回全部已登记效果 ID；顺序继承目录扫描结果，保证读档重建按稳定顺序执行。
func get_player_effect_ids() -> Array[String]:
	_ensure_loaded()
	# 稳定结果；按目录排序后的注册顺序返回，便于测试与诊断复现同一顺序。
	var result: Array[String] = []
	for effect_id_variant: Variant in player_effects.keys():
		result.append(str(effect_id_variant))
	return result


## 返回指定牌堆中的紧凑实体牌条目；每项格式为 [花色, 点数, 卡牌ID]。
func get_deck_cards(deck_id: String) -> Array:
	_ensure_loaded()
	# 指定牌堆定义；不存在时使用空字典保证查询安全。
	var deck_definition: Dictionary = decks.get(deck_id, {}) as Dictionary
	return (deck_definition.get("cards", []) as Array).duplicate(true)


## 扫描并登记全部角色持续效果源码；效果实例挂在角色身上，因此只登记脚本与元数据，不建立持有者索引。
func _load_player_effects() -> void:
	for script_path: String in _list_gd_scripts(PLAYER_EFFECTS_DIRECTORY):
		# 当前效果脚本资源；对局开始时会由该资源为需要它的角色创建独立实例。
		var effect_script: Script = _load_content_script(script_path)
		if effect_script == null:
			validation_errors.append("角色效果脚本无法载入：%s" % script_path)
			continue
		# 先确认脚本可实例化：存在解析错误的脚本调用 new() 会在运行时中断整个载入循环，
		# 使其余效果静默消失，只留下“读档后效果不再结算”这类难以定位的表现。
		if not effect_script.can_instantiate():
			validation_errors.append("角色效果脚本存在解析错误，无法实例化：%s" % script_path)
			continue
		# 当前效果定义临时实例；只读取静态元数据，不绑定对局端口、不订阅任何时机。
		var definition: PlayerEffect = effect_script.new() as PlayerEffect
		if definition == null:
			validation_errors.append("角色效果脚本未继承 PlayerEffect：%s" % script_path)
			continue
		# 当前效果唯一 ID；空 ID 或重复 ID 会让读档重建无法确定具体脚本。
		var effect_id: String = definition.get_id()
		if effect_id.is_empty():
			validation_errors.append("角色效果脚本存在空 ID：%s" % script_path)
		elif player_effect_scripts.has(effect_id):
			validation_errors.append("角色效果 ID 重复：%s" % effect_id)
		else:
			player_effects[effect_id] = definition.get_metadata()
			player_effect_scripts[effect_id] = effect_script


## 扫描并登记全部卡牌源码；文件名只用于维护定位，稳定逻辑 ID 始终读取脚本元数据。
func _load_cards() -> void:
	for script_path: String in _list_gd_scripts(CARDS_DIRECTORY):
		# 当前卡牌脚本资源；加载失败时记录精确路径并继续检查其他文件。
		var card_script: Script = _load_content_script(script_path)
		if card_script == null:
			validation_errors.append("卡牌脚本无法载入：%s" % script_path)
			continue
		# 当前卡牌定义对象；具体文件必须继承 CardDefinition 才能参与自动注册。
		var definition: CardDefinition = card_script.new() as CardDefinition
		if definition == null:
			validation_errors.append("卡牌脚本未继承 CardDefinition：%s" % script_path)
			continue
		# 当前卡牌完整元数据；数据库只建立索引，不改写文件提供的任何字段。
		var metadata: Dictionary = definition.get_metadata()
		# 当前卡牌唯一 ID；空 ID 或重复 ID 会阻止开局，避免牌堆引用产生歧义。
		var card_id: String = definition.get_id()
		if card_id.is_empty():
			validation_errors.append("卡牌脚本存在空 ID：%s" % script_path)
		elif card_definitions.has(card_id):
			validation_errors.append("卡牌 ID 重复：%s" % card_id)
		else:
			cards[card_id] = metadata
			_index_card_display_names(metadata)
			card_definitions[card_id] = definition
			card_scripts[card_id] = card_script


## 扫描并登记全部技能源码；技能脚本先于武将载入，以便直接引用时立即完成一致性校验。
func _load_skills() -> void:
	for script_path: String in _list_gd_scripts(SKILLS_DIRECTORY):
		# 当前技能脚本资源；每名持有者会由该资源创建独立实例。
		var skill_script: Script = _load_content_script(script_path)
		if skill_script == null:
			validation_errors.append("技能脚本无法载入：%s" % script_path)
			continue
		# 当前技能定义临时实例；只读取静态元数据，不绑定对局端口。
		# 先确认脚本可实例化：存在解析错误的脚本调用 new() 会在运行时中断整个载入循环，
		# 使其后按目录顺序排列的全部技能静默消失，只留下“武将引用了未知技能”这类误导性诊断。
		if not skill_script.can_instantiate():
			validation_errors.append("技能脚本存在解析错误，无法实例化：%s" % script_path)
			continue
		var definition: SkillDefinition = skill_script.new() as SkillDefinition
		if definition == null:
			validation_errors.append("技能脚本未继承 SkillDefinition：%s" % script_path)
			continue
		# 当前技能唯一 ID；空 ID 或重复 ID 会导致武将引用无法确定具体代码。
		var skill_id: String = definition.get_id()
		if skill_id.is_empty():
			validation_errors.append("技能脚本存在空 ID：%s" % script_path)
		elif skill_scripts.has(skill_id):
			validation_errors.append("技能 ID 重复：%s" % skill_id)
		else:
			# 当前技能元数据深拷贝；标签校验与登记共用同一份数据，避免二次构造技能实例。
			var skill_metadata: Dictionary = definition.get_metadata()
			# 正文类型声明结果；只用于校验，不参与任何运行期判定。
			var declares_reincarnation_type: bool = SkillDefinition.description_declares_reincarnation_type(str(skill_metadata.get("description", "")))
			# 轮回技标签声明结果；运行期全部轮回技判定都以该标签为唯一来源。
			var declares_reincarnation_tag: bool = bool(skill_metadata.get("reincarnation", false))
			if declares_reincarnation_type and not declares_reincarnation_tag:
				validation_errors.append("技能 %s 正文声明轮回技但未设置 reincarnation 标签。" % skill_id)
			elif declares_reincarnation_tag and not declares_reincarnation_type:
				validation_errors.append("技能 %s 设置了 reincarnation 标签但正文未在类型段声明轮回技。" % skill_id)
			# 欢愉技标签声明结果；运行期全部欢愉技判定都以该标签为唯一来源。
			var declares_joy_tag: bool = bool(skill_metadata.get("joy_skill", false))
			# 正文类型声明结果；与轮回技同一口径，只看类型段是否把自身声明为欢愉技。
			var declares_joy_type: bool = SkillDefinition.description_declares_joy_type(str(skill_metadata.get("description", "")))
			if declares_joy_type and not declares_joy_tag:
				validation_errors.append("技能 %s 正文声明欢愉技但未设置 joy_skill 标签。" % skill_id)
			elif declares_joy_tag and not declares_joy_type:
				validation_errors.append("技能 %s 设置了 joy_skill 标签但正文未在类型段声明欢愉技。" % skill_id)
			elif declares_joy_tag and int(skill_metadata.get("performance_number", 0)) < 1:
				# 参演编号是阿哈时刻的唯一排序键；缺失或非正数会让该技能无法稳定排序，必须在加载期拦住。
				validation_errors.append("技能 %s 是欢愉技但未声明有效的 performance_number 参演编号。" % skill_id)
			skills[skill_id] = skill_metadata
			skill_scripts[skill_id] = skill_script


## 扫描并登记全部武将源码；武将文件直接 preload 技能脚本，不再维护集中字符串配置表。
func _load_characters() -> void:
	for script_path: String in _list_gd_scripts(CHARACTERS_DIRECTORY):
		# 当前武将脚本资源；加载失败不会影响其他武将继续接受校验。
		var character_script: Script = _load_content_script(script_path)
		if character_script == null:
			validation_errors.append("武将脚本无法载入：%s" % script_path)
			continue
		# 当前武将定义对象；必须继承 CharacterDefinition 才能提供技能脚本引用。
		# 与技能载入同一口径：解析失败或依赖技能载入失败的武将脚本无法实例化，
		# 此时必须给出准确诊断，否则会被后续的“缺少 display_name”等派生错误掩盖真实原因。
		if not character_script.can_instantiate():
			validation_errors.append("武将脚本存在解析错误，无法实例化：%s" % script_path)
			continue
		var definition: CharacterDefinition = character_script.new() as CharacterDefinition
		if definition == null:
			validation_errors.append("武将脚本未继承 CharacterDefinition：%s" % script_path)
			continue
		# 当前武将唯一 ID；选将、网络与存档始终使用该稳定值。
		var character_id: String = definition.get_id()
		if character_id.is_empty():
			validation_errors.append("武将脚本存在空 ID：%s" % script_path)
		elif character_definitions.has(character_id):
			validation_errors.append("武将 ID 重复：%s" % character_id)
		else:
			# 当前武将对外元数据；插画路径由源码文件名自动生成，武将脚本内的旧手填字段不会绕过统一命名规则。
			var character_metadata: Dictionary = definition.get_metadata()
			character_metadata.erase("art_path")
			# 当前武将自动匹配到的插画路径；空值表示 PNG 与 JPG 均不存在，界面会继续显示统一占位图。
			var automatic_art_path: String = _find_character_art_path(script_path)
			if not automatic_art_path.is_empty():
				character_metadata["art_path"] = automatic_art_path
			characters[character_id] = character_metadata
			character_definitions[character_id] = definition
		for skill_script: Script in definition.get_skill_scripts():
			if skill_script == null or not skill_script.resource_path.begins_with(SKILLS_DIRECTORY + "/"):
				validation_errors.append("武将 %s 的技能必须直接引用 %s 内的脚本。" % [character_id, SKILLS_DIRECTORY])


## 返回某一类别下的全部卡牌定义 ID，按卡牌 ID 字典序排列。
##
## 【用途】需要按类别列举卡牌的功能（例如运行时造牌的「选择一张要复制的牌」界面）不能自己去遍历
## 卡牌目录或依赖加载顺序；由数据库统一给出排序后的只读结果，界面、AI 与回放才能得到同一份顺序。
## 【参数】card_type 取卡牌定义中的 `type` 字段（basic / trick / equipment 等）；未知类别返回空数组。
func get_card_ids_by_type(card_type: String) -> Array[String]:
	_ensure_loaded()
	# 结果定义ID；按字典序排序，与文件系统枚举顺序无关。
	var result: Array[String] = []
	if card_type.is_empty():
		return result
	for card_id_variant: Variant in cards.keys():
		# 当前定义ID与元数据；类别不匹配的直接跳过。
		var card_id: String = str(card_id_variant)
		if str((cards.get(card_id, {}) as Dictionary).get("type", "")) == card_type:
			result.append(card_id)
	result.sort()
	return result


## 根据武将源码文件基础名自动查找插画；只接受 image 目录中的同名小写 PNG 或 JPG 文件。
func _find_character_art_path(character_script_path: String) -> String:
	# 当前武将源码文件基础名；例如 buluoniya.gd 会得到 buluoniya，并且不依赖武将稳定 ID。
	var character_file_base_name: String = character_script_path.get_file().get_basename()
	for image_extension: String in CHARACTER_IMAGE_EXTENSIONS:
		# 当前格式对应的候选资源路径；目录、基础名和扩展名共同组成唯一自动匹配位置。
		var candidate_path: String = "%s/%s.%s" % [CHARACTER_IMAGE_DIRECTORY, character_file_base_name, image_extension]
		if ResourceLoader.exists(candidate_path):
			return candidate_path
	return ""


## 载入牌堆配置；牌堆仍适合使用紧凑 JSON，因为同一卡牌定义会对应多张不同花色与点数的实体牌。
func _load_decks() -> void:
	# 牌堆配置根对象；其 decks 字典可登记任意数量的牌堆。
	var decks_root: Dictionary = _load_json_object(DECKS_PATH)
	decks = (decks_root.get("decks", {}) as Dictionary).duplicate(true)


## 载入势力展示配置；势力没有独立规则函数，因此保持集中纯数据避免重复脚本样板。
func _load_factions() -> void:
	# 势力配置根对象；factions 数组中的每项按唯一 ID 建立只读索引。
	var factions_root: Dictionary = _load_json_object(FACTIONS_PATH)
	for row_variant: Variant in factions_root.get("factions", []):
		# 当前势力展示定义；只保存界面名称与颜色，不影响身份局阵营或规则结算。
		var row: Dictionary = row_variant as Dictionary
		# 当前势力唯一 ID；武将通过 faction 字段引用该稳定标识。
		var faction_id: String = str(row.get("id", ""))
		if faction_id.is_empty():
			validation_errors.append("势力配置存在空 ID。")
		elif factions.has(faction_id):
			validation_errors.append("势力 ID 重复：%s" % faction_id)
		else:
			factions[faction_id] = row.duplicate(true)


## 返回目录中按文件名稳定排序的全部 GDScript 路径；新增文件会自然进入下一次扫描。
func _list_gd_scripts(directory_path: String) -> Array[String]:
	# 目录访问对象；目录缺失会形成明确配置错误，而不是静默返回空内容库。
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		validation_errors.append("数据源码目录不存在：%s" % directory_path)
		return []
	# 目录文件名数组；排序保证重复 ID 错误与加载日志在不同平台上保持一致。
	var file_names: PackedStringArray = directory.get_files()
	file_names.sort()
	# 完整脚本路径结果；`.gd.uid` 与其他导入辅助文件不会进入注册流程。
	var result: Array[String] = []
	# 已登记的规范脚本文件名；导出包同时暴露源码名与remap名时用于避免重复加载同一资源。
	var registered_script_file_names: Dictionary = {}
	for file_name: String in file_names:
		# 当前目录项对应的原始GDScript文件名；导出PCK中的remap、编译或加密形式会恢复为规范`.gd`路径。
		var script_file_name: String = _resolve_gd_script_file_name(file_name)
		if script_file_name.is_empty() or registered_script_file_names.has(script_file_name):
			continue
		registered_script_file_names[script_file_name] = true
		# 当前源码文件基础名；规范允许小写拼音、数字和下划线组合，禁止空格、横线、中文与大写字母。
		var base_name: String = script_file_name.get_basename()
		if not _is_lowercase_pinyin_filename(base_name):
			validation_errors.append("内容源码文件只能使用小写字母、数字和下划线命名：%s/%s" % [directory_path, script_file_name])
		result.append("%s/%s" % [directory_path, script_file_name])
	return result


## 把编辑器源码、remap、编译脚本或加密脚本目录项规范化为原始`.gd`文件名；其他文件返回空字符串。
func _resolve_gd_script_file_name(file_name: String) -> String:
	if file_name.get_extension() == "gd":
		return file_name
	if file_name.ends_with(".gd.remap"):
		return file_name.trim_suffix(".remap")
	if file_name.get_extension() in ["gdc", "gde"]:
		return "%s.gd" % file_name.get_basename()
	return ""


## 按原始路径、编译路径和加密路径依次加载内容脚本；用于兼容不同导出脚本模式与平台资源映射行为。
func _load_content_script(script_path: String) -> Script:
	# 原始脚本基础路径；规范输入以`.gd`结尾，用于构造导出后的`.gdc`与`.gde`候选。
	var script_base_path: String = script_path.trim_suffix(".gd")
	# 按优先级排列的资源候选；编辑器命中原始路径，导出包可在资源重映射失效时直接命中编译或加密脚本。
	var candidate_paths: Array[String] = [script_path, "%s.gdc" % script_base_path, "%s.gde" % script_base_path]
	for candidate_path: String in candidate_paths:
		if not ResourceLoader.exists(candidate_path):
			continue
		# 当前候选加载结果；只有Script资源可作为内容定义实例化，其他资源类型继续尝试后续候选。
		var script_resource: Script = load(candidate_path) as Script
		if script_resource != null:
			return script_resource
	return null


## 校验文件名是否仅由 a 至 z、0 至 9 和下划线组成；拼音语义与数字后缀用途由代码评审保证。
func _is_lowercase_pinyin_filename(base_name: String) -> bool:
	if base_name.is_empty():
		return false
	for character_index: int in range(base_name.length()):
		# 当前 Unicode 码点；ASCII 小写字母为97至122、数字为48至57、下划线为95。
		var codepoint: int = base_name.unicode_at(character_index)
		# 当前字符是否合法；三种允许范围以外的空格、横线、中文和大写字母都会失败。
		var is_allowed_character: bool = codepoint >= 97 and codepoint <= 122 or codepoint >= 48 and codepoint <= 57 or codepoint == 95
		if not is_allowed_character:
			return false
	return true


## 读取 JSON 文件并保证返回字典；文件或语法错误会写入统一错误列表。
func _load_json_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		validation_errors.append("数据文件不存在：%s" % path)
		return {}
	# 已打开的数据文件；只在本函数作用域内读取并自动释放。
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		validation_errors.append("数据文件无法读取：%s" % path)
		return {}
	# JSON 原始文本；解析器需要完整字符串以提供准确行号。
	var source: String = file.get_as_text()
	# JSON 解析器实例；用于同时取得结果与错误描述。
	var parser: JSON = JSON.new()
	# 解析错误码；OK 表示 data 可安全转换为字典。
	var error: Error = parser.parse(source)
	if error != OK:
		validation_errors.append("JSON 解析失败 %s:%d %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if not parser.data is Dictionary:
		validation_errors.append("JSON 根节点必须是对象：%s" % path)
		return {}
	return parser.data as Dictionary


## 校验牌堆引用，避免开局后才发现实体牌指向不存在的源码定义。
func _validate_decks() -> void:
	for deck_id_variant: Variant in decks.keys():
		# 当前牌堆 ID；用于生成可追溯的校验错误。
		var deck_id: String = str(deck_id_variant)
		# 当前牌堆配置；cards 必须为三元素数组集合。
		var deck_definition: Dictionary = decks[deck_id] as Dictionary
		for entry_variant: Variant in deck_definition.get("cards", []):
			# 当前实体牌紧凑条目；索引 0/1/2 分别为花色、点数、卡牌 ID。
			var entry: Array = entry_variant as Array
			if entry.size() != 3:
				validation_errors.append("牌堆 %s 存在非法条目。" % deck_id)
				continue
			# 当前实体牌引用的卡牌 ID；必须已在 game_data/cards 中自动登记。
			var card_id: String = str(entry[2])
			if not cards.has(card_id):
				validation_errors.append("牌堆 %s 引用了未知卡牌：%s" % [deck_id, card_id])


## 校验势力展示字段，保证武将牌能够稳定生成完整名称、圆徽简称和十六进制主题颜色。
func _validate_factions() -> void:
	for faction_id_variant: Variant in factions.keys():
		# 当前势力 ID；用于为展示字段错误提供可追溯的配置位置。
		var faction_id: String = str(faction_id_variant)
		# 当前势力定义；只读检查完整名称、简称和颜色字符串，不修改配置内容。
		var faction: Dictionary = factions[faction_id] as Dictionary
		if str(faction.get("display_name", "")).is_empty():
			validation_errors.append("势力 %s 缺少 display_name。" % faction_id)
		if str(faction.get("short_name", "")).is_empty():
			validation_errors.append("势力 %s 缺少 short_name。" % faction_id)
		# 势力主题颜色；当前规范要求不带井号的六位十六进制 RGB 字符串。
		var color_value: String = str(faction.get("color", ""))
		if color_value.length() != 6 or not color_value.is_valid_hex_number(false):
			validation_errors.append("势力 %s 的 color 必须是六位十六进制 RGB。" % faction_id)


## 校验卡牌必填信息以及武将对势力、技能源码的引用，避免运行时出现静默缺项。
func _validate_characters() -> void:
	for card_id_variant: Variant in cards.keys():
		# 当前卡牌 ID；所有玩家可见名称、类别与效果说明均必须由对应文件完整提供。
		var card_id: String = str(card_id_variant)
		# 当前卡牌元数据；只读检查通用规则所需的核心字段。
		var card: Dictionary = cards[card_id] as Dictionary
		for required_field: String in ["original_name", "custom_name", "type", "subtype", "effect_id", "target_mode", "description"]:
			if str(card.get(required_field, "")).is_empty():
				validation_errors.append("卡牌 %s 缺少 %s。" % [card_id, required_field])
	for character_id_variant: Variant in characters.keys():
		# 当前武将 ID；用于为所有引用错误提供可追溯的配置位置。
		var character_id: String = str(character_id_variant)
		# 当前武将定义；从只读索引读取，不向校验流程之外暴露可修改引用。
		var character: Dictionary = characters[character_id] as Dictionary
		if str(character.get("display_name", "")).is_empty():
			validation_errors.append("武将 %s 缺少 display_name。" % character_id)
		# 当前武将势力 ID；必须指向 factions 数组中的展示元数据。
		var faction_id: String = str(character.get("faction", ""))
		if not factions.has(faction_id):
			validation_errors.append("武将 %s 引用了未知势力：%s" % [character_id, faction_id])
		for skill_id_variant: Variant in character.get("skills", []):
			# 当前武将引用的技能 ID；必须由 game_data/skills 中已登记的脚本提供。
			var skill_id: String = str(skill_id_variant)
			if not skills.has(skill_id):
				validation_errors.append("武将 %s 引用了未知技能：%s" % [character_id, skill_id])
