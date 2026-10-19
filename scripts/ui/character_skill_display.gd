class_name CharacterSkillDisplay
extends RefCounted

## 武将技能「查看」的统一视图模型。悬停武将牌、右键武将详情与主视角技能栏共用本类，
## 避免同一件「这名角色此刻有哪些技能、每条技能显示什么文本」的事在界面里被写第二遍。
##
## 【为什么需要本类】这三个查看入口曾经各自实现技能枚举与文本拼装，于是同一条规则在两处得出不同答案：
## 失去技能后悬停资料已经正确收敛，右键详情却仍按武将静态定义继续列出该技能。
## 把枚举与文本收敛到本类之后，两个入口只负责把同一份条目画成自己需要的形状，不会再各自漂移。
##
## 【拥有口径的唯一来源】某个技能是否算在这名角色身上，由
## `SkillDefinition.collect_snapshot_skill_ids` / `SkillDefinition.snapshot_has_skill` 判定；
## 本类**不复制** `installed_skill_ids` 裁剪规则，只消费统一入口的结果，并在其之上叠加展示专属语义：
## ① 展示顺序（固有按武将定义顺序 → 模式 → 临时 → 局内获得）；
## ② 缺失技能定义的固有技能继续占位（配置错误必须能被发现）；
## ③ 被查看角色的固有技能来源由调用方传入的定义副本决定（选将候选与手工构造的快照没有 character_id）。
##
## 【纯静态且只读】不创建节点、不创建技能实例、不改写任何对局状态，因此内容测试可以直接调用。

## 技能静态定义缺失时的占位说明；与信息框既有文案保持一致，避免技能条目静默消失。
const SKILL_DESCRIPTION_FALLBACK: String = "技能元数据尚未登记。"


## 返回一名角色此刻应当被「查看」到的技能ID顺序。
##
## `player_snapshot` 是观察者裁剪快照中的玩家条目（只读）；`character_definition` 是**被查看角色**的
## 武将静态定义副本，其 `skills` 字段是固有技能的声明顺序与来源。
## 快照缺少 `installed_skill_ids` 时（旧回放、选将候选、手工构造的测试快照）不做裁剪，
## 与技能栏的既有回退口径逐字节一致。
static func collect_visible_skill_ids(player_snapshot: Dictionary, character_definition: Dictionary = {}) -> Array[String]:
	# 被查看角色的固有技能声明数组；顺序即展示顺序。
	var native_skill_ids: Array = character_definition.get("skills", []) as Array
	# 可见技能结果；空快照与空定义同时成立时返回空数组，调用方按“无技能”处理。
	var visible_skill_ids: Array[String] = []
	if native_skill_ids.is_empty() and player_snapshot.is_empty():
		return visible_skill_ids
	# 拥有口径结果；唯一来源是统一入口，本类只消费它。
	# 传入被查看角色的固有技能表，使没有 character_id 的展示快照也能在同一套裁剪规则下求值。
	var owned_skill_ids: Array[String] = SkillDefinition.collect_snapshot_skill_ids(player_snapshot, native_skill_ids)
	# 拥有集合；把列表转成成员判定，避免在固有技能循环里反复线性查找。
	var owned_lookup: Dictionary = {}
	for owned_skill_id: String in owned_skill_ids:
		owned_lookup[owned_skill_id] = true
	# 固有技能；严格保持武将定义的声明顺序。
	for native_skill_id_variant: Variant in native_skill_ids:
		# 当前固有技能ID；空值不进入展示。
		var native_skill_id: String = str(native_skill_id_variant)
		if native_skill_id.is_empty():
			continue
		# 缺失技能定义属于配置错误，保留占位以便被发现，因此不参与“已安装”裁剪（展示专属行为）。
		var is_configuration_error: bool = GameDatabase.get_skill(native_skill_id).is_empty()
		if owned_lookup.has(native_skill_id) or is_configuration_error:
			visible_skill_ids.append(native_skill_id)
	# 模式、临时与局内获得技能；按统一入口给出的顺序追加，与固有技能重名时只保留首次出现的一项。
	for owned_skill_id: String in owned_skill_ids:
		if not visible_skill_ids.has(owned_skill_id):
			visible_skill_ids.append(owned_skill_id)
	return visible_skill_ids


## 返回一名角色此刻应当被「查看」到的技能**实例键**顺序；同名技能的多份实例各占一项。
##
## 与 collect_visible_skill_ids 的关系是「实例粒度」与「技能粒度」：前者保留“zhuru”与“zhuru#2”两项，
## 后者把两者合并为“zhuru”一项。展示顺序规则完全一致，并在固有技能处把该技能的序号实例紧跟其后，
## 使玩家看到「技能A（第一份）→ 技能A（第二份）→ 技能B」而不是把所有实例堆在列表末尾。
static func collect_visible_skill_keys(player_snapshot: Dictionary, character_definition: Dictionary = {}) -> Array[String]:
	# 被查看角色的固有技能声明数组；顺序即展示顺序。
	var native_skill_ids: Array = character_definition.get("skills", []) as Array
	# 可见实例键结果；空快照与空定义同时成立时返回空数组，调用方按“无技能”处理。
	var visible_skill_keys: Array[String] = []
	if native_skill_ids.is_empty() and player_snapshot.is_empty():
		return visible_skill_keys
	# 拥有口径结果；唯一来源是统一入口的实例粒度版本，本类只消费它。
	var owned_skill_keys: Array[String] = SkillDefinition.collect_snapshot_skill_keys(player_snapshot, native_skill_ids)
	# 拥有集合；把列表转成成员判定，避免在固有技能循环里反复线性查找。
	var owned_lookup: Dictionary = {}
	for owned_skill_key: String in owned_skill_keys:
		owned_lookup[owned_skill_key] = true
	# 固有技能；严格保持武将定义的声明顺序，并把该技能的序号实例紧随首实例之后。
	for native_skill_id_variant: Variant in native_skill_ids:
		# 当前固有技能ID；空值不进入展示。
		var native_skill_id: String = str(native_skill_id_variant)
		if native_skill_id.is_empty():
			continue
		# 缺失技能定义属于配置错误，保留占位以便被发现，因此不参与“已安装”裁剪（展示专属行为）。
		var is_configuration_error: bool = GameDatabase.get_skill(native_skill_id).is_empty()
		if owned_lookup.has(native_skill_id) or is_configuration_error:
			visible_skill_keys.append(native_skill_id)
		# 该固有技能的序号实例；统一入口已按键序收集，这里只需按同一顺序追加，天然保持“首实例优先”。
		for owned_skill_key: String in owned_skill_keys:
			if owned_skill_key == native_skill_id or not owned_lookup.has(owned_skill_key):
				continue
			if SkillDefinition.base_skill_id_of(owned_skill_key) != native_skill_id:
				continue
			if not visible_skill_keys.has(owned_skill_key):
				visible_skill_keys.append(owned_skill_key)
	# 模式、临时与局内获得技能；按统一入口给出的顺序追加，已出现过的实例键不会重复进入结果。
	for owned_skill_key: String in owned_skill_keys:
		if not visible_skill_keys.has(owned_skill_key):
			visible_skill_keys.append(owned_skill_key)
	return visible_skill_keys


## 构建一名角色的技能查看条目列表；两个查看入口都只消费它，不再各自枚举技能或拼装文本。
##
## 每个条目的字段固定为：
## - `instance_key`：技能实例键，界面按此唯一标识这一份技能（同名技能的多份实例键互不相同）；
## - `skill_id`：技能稳定ID（由实例键还原），供入口按需查询自身需要的附加信息；
## - `title`：与技能名同一行的标题（轮回数与次数文案都附在这里）；
## - `description`：技能完整描述（动态覆盖优先，书名号已按当前名称模式解析）；
## - `reincarnation`：是否轮回技，决定描述是否按轮回节拆段高亮；
## - `reincarnation_section_index`：当前轮回节索引，从0起，非轮回技恒为0；
## - `intrinsic_use_consumed`：固有发动额度是否已消耗，界面据此把整个技能条目显示为变淡。
static func build_skill_entries(player_snapshot: Dictionary, character_definition: Dictionary = {}) -> Array[Dictionary]:
	# 技能查看条目；顺序与 collect_visible_skill_keys 完全一致。
	var entries: Array[Dictionary] = []
	# 已经释放固有额度的限定技与觉醒技**实例键**集合；界面不自行推断释放状态，只读公开快照。
	# 该字段在 used_limited_skill_ids 基础上额外包含觉醒技，因此觉醒技释放后同样进入变淡表现。
	# 键为实例键，比较统一走 instance_key_list_has_skill，同名技能的多份实例才能各自正确变淡。
	var intrinsic_use_consumed_ids: Array = player_snapshot.get("used_intrinsic_use_skill_ids", []) as Array
	for skill_key_variant: Variant in collect_visible_skill_keys(player_snapshot, character_definition):
		# 当前技能实例键；同名技能的多份实例在这里各自成为一个条目。
		var instance_key: String = str(skill_key_variant)
		# 当前技能稳定ID；由实例键还原，查库、轮回高亮与名称显示都按技能ID求值。
		var skill_id: String = SkillDefinition.base_skill_id_of(instance_key)
		# 当前技能静态定义；缺失时保留稳定ID与明确占位说明。
		var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)
		# 当前技能完整名称；查看入口不截取技能按钮使用的前两个字。
		var skill_name: String = str(skill_definition.get("name", skill_id))
		# 当前技能轮回状态；公开快照是局内轮回节高亮的唯一数据来源，静态牌面缺失时回退①。
		var reincarnation_state: Dictionary = _resolve_reincarnation_state(player_snapshot, instance_key, skill_id)
		entries.append({
			"instance_key":instance_key,
			"skill_id":skill_id,
			"title":build_skill_title(player_snapshot, instance_key, skill_name),
			"description":GameDatabase.resolve_card_names_in_text(resolve_skill_description(player_snapshot, instance_key, skill_definition)),
			"reincarnation":bool(skill_definition.get("reincarnation", false)),
			"reincarnation_section_index":maxi(int(reincarnation_state.get("section_index", 0)), 0),
			"intrinsic_use_consumed":SkillDefinition.instance_key_list_has_skill(intrinsic_use_consumed_ids, instance_key),
		})
	return entries


## 从公开快照取出某个技能实例的轮回状态；先按实例键精确命中，未命中时回落到该技能的首实例。
## 快照的 reincarnation_skills 键为实例键，因此同名轮回技的多份实例各自高亮自己的轮回节。
static func _resolve_reincarnation_state(player_snapshot: Dictionary, instance_key: String, skill_id: String) -> Dictionary:
	# 轮回状态映射；缺失该可选字段时返回空字典，界面回退①节。
	var reincarnation_map: Dictionary = player_snapshot.get("reincarnation_skills", {}) as Dictionary
	if reincarnation_map.has(instance_key):
		return reincarnation_map.get(instance_key, {}) as Dictionary
	return reincarnation_map.get(skill_id, {}) as Dictionary


## 返回技能在当前对局中的显示描述；公开快照的 dynamic_skill_descriptions 是唯一动态来源。
## 该字段只包含“当前进度与静态原文不同”的技能（例如【断界】已被删除的选项需要划掉），
## 因此普通技能依旧逐字显示静态元数据描述；技能自身不得改写 GameDatabase 的静态原文。
## 传入的可能是实例键（同名技能的多份实例各自显示不同正文）：先按实例键精确命中，未命中时按技能ID找首实例的覆盖。
static func resolve_skill_description(player_snapshot: Dictionary, skill_id: String, skill_definition: Dictionary = {}) -> String:
	# 快照下发的动态描述覆盖；缺失该可选字段时自然回退静态原文。
	var dynamic_descriptions: Dictionary = player_snapshot.get("dynamic_skill_descriptions", {}) as Dictionary
	if dynamic_descriptions.has(skill_id):
		return str(dynamic_descriptions.get(skill_id, ""))
	# 技能ID回退：容器里可能只登记了首实例（键即技能ID）的覆盖，或调用方传的是序号实例键。
	var base_skill_id: String = SkillDefinition.base_skill_id_of(skill_id)
	for key_variant: Variant in dynamic_descriptions.keys():
		if SkillDefinition.base_skill_id_of(str(key_variant)) == base_skill_id:
			return str(dynamic_descriptions.get(key_variant, ""))
	return str(skill_definition.get("description", SKILL_DESCRIPTION_FALLBACK))


## 返回技能查看标题；轮回技先标注轮回数，局内获得的受限技能再显示完整次数文案，避免改写技能原文。
## 片段顺序固定为「轮回数 → 次数文案」，与技能按钮悬停标题保持完全一致。
## 传入的可能是实例键：查库与轮回状态读取都先还原成技能ID，标题里不会出现“#序号”。
static func build_skill_title(player_snapshot: Dictionary, skill_id: String, skill_name: String = "") -> String:
	# 技能ID；调用方可能传入实例键，先还原再查库，避免标题退化成内部键。
	var base_skill_id: String = SkillDefinition.base_skill_id_of(skill_id)
	# 当前技能显示名；调用方未给出时按稳定ID查库，数据库缺失则回退稳定ID本身。
	var resolved_skill_name: String = skill_name if not skill_name.is_empty() else str(GameDatabase.get_skill(base_skill_id).get("name", base_skill_id))
	# 默认技能标题；所有查看入口统一使用书名号样式。
	var skill_title: String = "【%s】" % resolved_skill_name
	# 技能名后的补充说明片段；全部为空时不追加括号。
	var title_suffix_parts: Array[String] = []
	# 技能静态定义；只用于判断该技能是否为轮回技，不读取技能的运行时实例。
	var skill_definition: Dictionary = GameDatabase.get_skill(base_skill_id)
	if bool(skill_definition.get("reincarnation", false)):
		# 当前技能轮回状态；与轮回节高亮共用同一公开快照字段，不新增数据来源。
		var reincarnation_state: Dictionary = _resolve_reincarnation_state(player_snapshot, skill_id, base_skill_id)
		# 当前轮回数；下限1保证未登记的轮回技仍显示稳定文本。
		var reincarnation_round_count: int = maxi(int(reincarnation_state.get("round_count", 1)), 1)
		title_suffix_parts.append("轮回%d" % reincarnation_round_count)
	# 当前快照内的受限技能次数映射；该字段由权威获得技能记录生成，视图不自行计算或扣减次数。
	# 键为实例键：先按实例键精确命中，未命中时按技能ID找首实例的次数文案。
	var remaining_uses_by_skill: Dictionary = player_snapshot.get("acquired_skill_remaining_uses", {}) as Dictionary
	# 当前技能完整次数文案；没有限制或不是局内获得技能时保持空字符串。
	var remaining_uses_description: String = str(remaining_uses_by_skill.get(skill_id, remaining_uses_by_skill.get(base_skill_id, "")))
	if not remaining_uses_description.is_empty():
		title_suffix_parts.append(remaining_uses_description)
	if not title_suffix_parts.is_empty():
		skill_title += "（%s）" % "；".join(title_suffix_parts)
	return skill_title
