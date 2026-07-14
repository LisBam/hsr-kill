extends Node

## 统一数据仓库。所有卡牌、牌堆、武将与技能均从配置文件载入，扩展内容无需修改对局核心。
## 势力展示元数据与武将配置共用数据文件，并通过独立索引提供给统一武将牌组件。

## 卡牌配置文件路径；修改数据源位置时只需调整此常量。
const CARDS_PATH: String = "res://data/cards.json"

## 牌堆配置文件路径；一个文件可同时登记多套可选牌堆。
const DECKS_PATH: String = "res://data/decks.json"

## 武将配置文件路径；武将与技能表共享同一版本号，便于批量扩展。
const CHARACTERS_PATH: String = "res://data/characters.json"

## 以卡牌 ID 为键的卡牌定义索引；运行时只读，重新载入数据时整体替换。
var cards: Dictionary = {}

## 以牌堆 ID 为键的牌堆配置索引；牌堆条目只引用卡牌 ID，逻辑不重复存储。
var decks: Dictionary = {}

## 以武将 ID 为键的武将定义索引；用于创建玩家状态与后续选将界面。
var characters: Dictionary = {}

## 以势力 ID 为键的势力展示元数据索引；包含完整名称、牌面简称与主题颜色，不参与身份或胜负规则。
var factions: Dictionary = {}

## 以技能 ID 为键的技能元数据索引；具体技能组件可按 ID 注册执行器。
var skills: Dictionary = {}

## 最近一次载入产生的错误列表；为空表示三份数据均通过基础校验。
var validation_errors: Array[String] = []


## 节点进入场景树时载入全部静态数据，确保其他模块可立即查询。
func _ready() -> void:
	reload_all()


## 重新载入并校验全部配置，适合编辑器工具或热更新流程调用。
func reload_all() -> bool:
	validation_errors.clear()
	cards.clear()
	decks.clear()
	characters.clear()
	factions.clear()
	skills.clear()

	# 卡牌配置根对象；必须含 cards 数组。
	var cards_root: Dictionary = _load_json_object(CARDS_PATH)
	# 卡牌配置数组；每项会按唯一 ID 建立索引。
	var card_rows: Array = cards_root.get("cards", [])
	for row_variant: Variant in card_rows:
		# 当前卡牌定义；非字典条目会被记录为配置错误。
		var row: Dictionary = row_variant as Dictionary
		# 当前卡牌唯一 ID；为空或重复都会阻止数据通过校验。
		var card_id: String = str(row.get("id", ""))
		if card_id.is_empty():
			validation_errors.append("卡牌配置存在空 ID。")
		elif cards.has(card_id):
			validation_errors.append("卡牌 ID 重复：%s" % card_id)
		else:
			cards[card_id] = row.duplicate(true)

	# 牌堆配置根对象；其 decks 字典可登记任意数量的牌堆。
	var decks_root: Dictionary = _load_json_object(DECKS_PATH)
	decks = (decks_root.get("decks", {}) as Dictionary).duplicate(true)

	# 武将配置根对象；同时建立武将与技能两套索引。
	# 势力展示元数据与武将、技能共用该根对象，并在武将索引建立前优先载入以供引用校验。
	var characters_root: Dictionary = _load_json_object(CHARACTERS_PATH)
	for row_variant: Variant in characters_root.get("factions", []):
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
	for row_variant: Variant in characters_root.get("characters", []):
		# 当前武将定义；复制后存入运行时只读索引。
		var row: Dictionary = row_variant as Dictionary
		# 当前武将唯一 ID；扩展包必须保证全项目唯一。
		var character_id: String = str(row.get("id", ""))
		if character_id.is_empty():
			validation_errors.append("武将配置存在空 ID。")
		elif characters.has(character_id):
			validation_errors.append("武将 ID 重复：%s" % character_id)
		else:
			characters[character_id] = row.duplicate(true)
	for row_variant: Variant in characters_root.get("skills", []):
		# 当前技能元数据；实际触发逻辑由独立技能组件按 ID 绑定。
		var row: Dictionary = row_variant as Dictionary
		# 当前技能唯一 ID；空 ID 不加入索引。
		var skill_id: String = str(row.get("id", ""))
		if not skill_id.is_empty():
			skills[skill_id] = row.duplicate(true)

	_validate_decks()
	_validate_factions()
	_validate_characters()
	return validation_errors.is_empty()


## 返回指定卡牌定义的深拷贝，防止调用方误改全局配置。
func get_card(card_id: String) -> Dictionary:
	return (cards.get(card_id, {}) as Dictionary).duplicate(true)


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


## 返回指定技能元数据的深拷贝，空结果表示技能 ID 未登记；具体技能执行器不由数据仓库持有。
func get_skill(skill_id: String) -> Dictionary:
	return (skills.get(skill_id, {}) as Dictionary).duplicate(true)


## 返回指定牌堆中的紧凑实体牌条目；每项格式为 [花色, 点数, 卡牌ID]。
func get_deck_cards(deck_id: String) -> Array:
	# 指定牌堆定义；不存在时使用空字典保证查询安全。
	var deck_definition: Dictionary = decks.get(deck_id, {}) as Dictionary
	return (deck_definition.get("cards", []) as Array).duplicate(true)


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


## 校验牌堆引用，避免开局后才发现实体牌指向不存在的定义。
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
			# 当前实体牌引用的卡牌 ID；必须已在 cards.json 中登记。
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


## 校验武将对势力与技能元数据的引用，避免牌面渲染或技能栏在运行时出现静默缺项。
func _validate_characters() -> void:
	for character_id_variant: Variant in characters.keys():
		# 当前武将 ID；用于为所有引用错误提供可追溯的配置位置。
		var character_id: String = str(character_id_variant)
		# 当前武将定义；从只读索引读取，不向校验流程之外暴露可修改引用。
		var character: Dictionary = characters[character_id] as Dictionary
		# 当前武将势力 ID；必须指向 factions 数组中的展示元数据。
		var faction_id: String = str(character.get("faction", ""))
		if not factions.has(faction_id):
			validation_errors.append("武将 %s 引用了未知势力：%s" % [character_id, faction_id])
		for skill_id_variant: Variant in character.get("skills", []):
			# 当前武将引用的技能 ID；必须已登记，避免技能栏生成无法解析的占位项。
			var skill_id: String = str(skill_id_variant)
			if not skills.has(skill_id):
				validation_errors.append("武将 %s 引用了未知技能：%s" % [character_id, skill_id])
