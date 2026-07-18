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

## 牌堆配置文件路径；牌堆条目只保存花色、点数与稳定卡牌 ID，不重复保存卡牌规则。
const DECKS_PATH: String = "res://data/decks.json"

## 势力展示配置文件路径；势力只提供名称、简称与颜色，不承载武将或技能逻辑。
const FACTIONS_PATH: String = "res://game_data/factions.json"

## 以卡牌 ID 为键的卡牌元数据索引；界面、AI、网络与规则查询只读取深拷贝。
var cards: Dictionary = {}

## 以卡牌 ID 为键的卡牌源码定义对象；效果解析器通过该索引调用对应卡牌文件的函数。
var card_definitions: Dictionary = {}

## 以卡牌 ID 为键的卡牌脚本资源索引；装备等持续区域效果会由该脚本创建独立运行时实例。
var card_scripts: Dictionary = {}

## 以牌堆 ID 为键的牌堆配置索引；牌堆条目只引用卡牌 ID，逻辑不重复存储。
var decks: Dictionary = {}

## 以武将 ID 为键的武将元数据索引；技能数组由武将源码直接引用的技能脚本自动生成。
var characters: Dictionary = {}

## 以武将 ID 为键的武将源码定义对象；用于校验技能脚本引用并为工具链提供源码入口。
var character_definitions: Dictionary = {}

## 以势力 ID 为键的势力展示元数据索引；不参与身份、距离、伤害或胜负规则。
var factions: Dictionary = {}

## 以技能 ID 为键的技能元数据索引；技能栏、网络与回放只读取该字典的深拷贝。
var skills: Dictionary = {}

## 以技能 ID 为键的技能脚本资源索引；每局会通过 create_skill 创建互不共享状态的运行时实例。
var skill_scripts: Dictionary = {}

## 最近一次载入产生的错误列表；为空表示全部源码定义、牌堆和势力引用均可安全使用。
var validation_errors: Array[String] = []


## 节点进入场景树时载入全部静态数据，确保其他模块可立即查询。
func _ready() -> void:
	reload_all()


## 重新扫描源码目录并校验全部配置；目录新增或删除文件后调用即可刷新索引。
func reload_all() -> bool:
	validation_errors.clear()
	cards.clear()
	card_definitions.clear()
	card_scripts.clear()
	decks.clear()
	characters.clear()
	character_definitions.clear()
	factions.clear()
	skills.clear()
	skill_scripts.clear()

	_load_skills()
	_load_cards()
	_load_characters()
	_load_decks()
	_load_factions()
	_validate_decks()
	_validate_factions()
	_validate_characters()
	return validation_errors.is_empty()


## 返回指定卡牌定义的深拷贝，防止调用方误改全局配置。
func get_card(card_id: String) -> Dictionary:
	return (cards.get(card_id, {}) as Dictionary).duplicate(true)


## 返回指定卡牌的源码定义对象；对象只保存静态数据，具体效果函数不得持有对局状态。
func get_card_definition(card_id: String) -> CardDefinition:
	return card_definitions.get(card_id) as CardDefinition


## 为装备或其他持续区域效果创建独立卡牌实例；实例尚未绑定玩家、实体 UID 或事件总线。
func create_card_runtime(card_id: String) -> CardDefinition:
	# 卡牌脚本资源；不存在时返回 null，调用方不得复用数据库中的静态定义对象保存对局状态。
	var card_script: Script = card_scripts.get(card_id) as Script
	if card_script == null:
		return null
	return card_script.new() as CardDefinition


## 返回指定武将定义的深拷贝，空结果表示 ID 未登记。
func get_character(character_id: String) -> Dictionary:
	return (characters.get(character_id, {}) as Dictionary).duplicate(true)


## 返回武将的本地化显示名称；界面只能使用该入口显示名称，避免稳定英文 ID 泄漏到玩家可见区域。
func resolve_character_name(character_id: String) -> String:
	# 当前武将定义；从静态索引读取以取得配置的中文 display_name。
	var character_definition: Dictionary = get_character(character_id)
	# 当前武将配置的显示名称；空值表示配置缺失或未填写本地化文本。
	var display_name: String = str(character_definition.get("display_name", "")).strip_edges()
	if not display_name.is_empty():
		return display_name
	return "未选武将" if character_id.is_empty() else "未知武将"


## 返回指定势力的展示元数据深拷贝；空结果表示势力 ID 未登记，调用方应使用中性视觉回退。
func get_faction(faction_id: String) -> Dictionary:
	return (factions.get(faction_id, {}) as Dictionary).duplicate(true)


## 返回指定技能元数据的深拷贝，空结果表示技能 ID 未登记。
func get_skill(skill_id: String) -> Dictionary:
	return (skills.get(skill_id, {}) as Dictionary).duplicate(true)


## 按当前卡牌名称模式替换文本中的【原版牌名】引用；技能说明可复用本入口保持静态原文与动态展示解耦。
## 只替换完整书名号包裹的已登记名称，普通叙述文字、稳定 ID 与规则数值均保持不变。
func resolve_card_names_in_text(source_text: String) -> String:
	# 当前解析结果；从调用方原文副本开始，仅在命中完整卡牌名称引用时更新。
	var resolved_text: String = source_text
	for card_variant: Variant in cards.values():
		# 当前卡牌定义；名称解析始终读取数据库已校验的双名称元数据。
		var card_definition: Dictionary = card_variant as Dictionary
		# 当前卡牌原版名称；技能源码统一以该名称书写，空名称不会参与替换。
		var original_name: String = str(card_definition.get("original_name", "")).strip_edges()
		if original_name.is_empty():
			continue
		# 原版名称引用标记；完整匹配可避免短牌名误改普通语句或其他牌名的一部分。
		var original_reference: String = "【%s】" % original_name
		if not resolved_text.contains(original_reference):
			continue
		# 当前模式名称引用；统一复用 GameSettings，保证卡牌牌面与技能说明显示一致。
		var resolved_reference: String = "【%s】" % GameSettings.resolve_card_name(card_definition)
		resolved_text = resolved_text.replace(original_reference, resolved_reference)
	return resolved_text


## 为一名技能持有者创建独立技能实例；实例尚未绑定玩家，也不会自动订阅规则事件。
func create_skill(skill_id: String) -> SkillDefinition:
	# 技能脚本资源；不存在时返回 null，让调用方以统一配置错误处理。
	var skill_script: Script = skill_scripts.get(skill_id) as Script
	if skill_script == null:
		return null
	return skill_script.new() as SkillDefinition


## 返回指定牌堆中的紧凑实体牌条目；每项格式为 [花色, 点数, 卡牌ID]。
func get_deck_cards(deck_id: String) -> Array:
	# 指定牌堆定义；不存在时使用空字典保证查询安全。
	var deck_definition: Dictionary = decks.get(deck_id, {}) as Dictionary
	return (deck_definition.get("cards", []) as Array).duplicate(true)


## 扫描并登记全部卡牌源码；文件名只用于维护定位，稳定逻辑 ID 始终读取脚本元数据。
func _load_cards() -> void:
	for script_path: String in _list_gd_scripts(CARDS_DIRECTORY):
		# 当前卡牌脚本资源；加载失败时记录精确路径并继续检查其他文件。
		var card_script: Script = load(script_path) as Script
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
			card_definitions[card_id] = definition
			card_scripts[card_id] = card_script


## 扫描并登记全部技能源码；技能脚本先于武将载入，以便直接引用时立即完成一致性校验。
func _load_skills() -> void:
	for script_path: String in _list_gd_scripts(SKILLS_DIRECTORY):
		# 当前技能脚本资源；每名持有者会由该资源创建独立实例。
		var skill_script: Script = load(script_path) as Script
		if skill_script == null:
			validation_errors.append("技能脚本无法载入：%s" % script_path)
			continue
		# 当前技能定义临时实例；只读取静态元数据，不绑定对局端口。
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
			skills[skill_id] = definition.get_metadata()
			skill_scripts[skill_id] = skill_script


## 扫描并登记全部武将源码；武将文件直接 preload 技能脚本，不再维护集中字符串配置表。
func _load_characters() -> void:
	for script_path: String in _list_gd_scripts(CHARACTERS_DIRECTORY):
		# 当前武将脚本资源；加载失败不会影响其他武将继续接受校验。
		var character_script: Script = load(script_path) as Script
		if character_script == null:
			validation_errors.append("武将脚本无法载入：%s" % script_path)
			continue
		# 当前武将定义对象；必须继承 CharacterDefinition 才能提供技能脚本引用。
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
	for file_name: String in file_names:
		if file_name.get_extension() == "gd":
			# 当前源码文件基础名；规范允许小写拼音、数字和下划线组合，禁止空格、横线、中文与大写字母。
			var base_name: String = file_name.get_basename()
			if not _is_lowercase_pinyin_filename(base_name):
				validation_errors.append("内容源码文件只能使用小写字母、数字和下划线命名：%s/%s" % [directory_path, file_name])
			result.append("%s/%s" % [directory_path, file_name])
	return result


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
