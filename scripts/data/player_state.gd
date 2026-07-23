class_name PlayerState
extends RefCounted

## 单名玩家的权威对局状态。该结构不依赖 UI、AI 或网络节点，可独立序列化与测试。

## 玩家在本局中的稳定座次 ID；范围从0开始，死亡后也不复用。
var player_id: int = -1

## 玩家显示名称；可由本地设置或联机房间资料提供。
var display_name: String = "玩家"

## 当前武将配置 ID；通过数据仓库查询名称、性别、势力与技能。
var character_id: String = ""

## 当前武将入场代次；每次正式应用或交换武将牌时递增，0表示尚未选择武将，用于阻止异步事件跨武将生效。
var character_generation: int = 0

## 当前武将是否已经向所有玩家亮出；选将阶段领袖先公开，其他玩家完成后同时公开。
var character_revealed: bool = false

## 当前身份；身份局取leader/loyalist/rebel/renegade，斗地主取landlord/peasant，2v2与车轮战取blue/red。
var identity: String = "rebel"

## 身份是否对公共信息可见；领袖开局明置，其他身份通常在死亡时公开。
var identity_revealed: bool = false

## 当前体力值；可降至0以下以完整表达濒死所需回复量。
var hp: int = 4

## 当前体力上限；默认4，样例武将配置可覆盖为3或其他正整数。
var max_hp: int = 4

## 当前护盾值；默认0且没有上限，受到伤害时优先扣减，失去体力与回复不会修改该值。
var shield: int = 0

## 当前是否存活；死亡结算完成后设为 false，之后不再参与行动顺序。
var alive: bool = true

## 当前是否处于濒死流程；体力不大于0时先设为 true，救援成功或死亡确认后恢复 false。
var dying: bool = false

## 当前是否已经完成死亡确认；与 alive 分开保存，允许濒死和死亡触发在确认前插入。
var death_confirmed: bool = false

## 当前是否离开游戏但未死亡；离场角色保留稳定座次和历史，但默认不参与距离与选择。
var out_of_game: bool = false

## 机缘等规则要求角色仅离场至指定轮结束时保存的轮数；-1表示普通离场，不由轮次流程自动返回。
var out_of_game_until_round: int = -1

## 当前是否处于连环状态；属性伤害结算后会触发横置角色间的伤害传导。
var chained: bool = false

## 当前是否处于翻面状态；为后续武将技能与完整回合规则预留。
var face_down: bool = false

## 武将牌左上角通用公开文本；空字符串隐藏组件，技能或模式只能写入面向所有观察者一致的展示内容。
var character_corner_text: String = ""

## 武将牌左上角公开文本条目；键为稳定来源ID，值保存文本与排序值，由控制器合成为character_corner_text以允许多个技能同时显示。
var character_corner_text_entries: Dictionary = {}

## 当前角色持有的公开标记；键为稳定标记ID，值包含单字图标、名称、说明、数量与来源角色，全部观察者均可见。
var public_marks: Dictionary = {}

## 当前是否由基础 AI 代替真人执行操作；默认 false，仅在真人主动托管或联机掉线后由权威控制器写入，并会同步到所有观察者。
var auto_managed: bool = false

## 当前托管是否由联机掉线触发；默认 false，true 时界面显示“已离线，托管中”且不允许远端玩家自行关闭。
var auto_managed_offline: bool = false

## 当前手牌数组；仅本人和权威对局核心可读取完整实体牌信息。
var hand: Array[CardInstance] = []

## 当前装备区；键为 weapon、armor、offensive_mount、defensive_mount、treasure。
var equipment: Dictionary = {}

## 当前判定区中的延时锦囊；按进入顺序在判定阶段依次处理。
var judgment_area: Array[CardInstance] = []

## 当前回合已使用【杀】次数；进入新回合时重置为0。
var slash_count: int = 0

## 当前回合是否已使用【酒】；进入新回合时重置为 false。
var wine_used: bool = false

## 【酒】提供的下一张【杀】伤害加值；声明使用下一张【杀】时消耗。
var wine_bonus: int = 0

## 本回合需要跳过的阶段集合；延时锦囊判定后写入 draw 或 play。
var skipped_phases: Dictionary = {}

## 木牛流马下扣置的“粮”；装备离开且未转移给他人时应置入弃牌堆。
var wooden_ox_storage: Array[CardInstance] = []

## 当前出牌阶段是否已发动木牛流马存粮；每个回合开始时重置为 false。
var wooden_ox_used: bool = false

## 当前临时技能与失效时机；键为技能 ID，值为 turn_end、phase_end 等稳定持续标识。
var temporary_skills: Dictionary = {}

## 当前通过机缘等局内永久来源获得的技能；键为技能 ID，值保存来源、每回合次数、总次数与已用次数，死亡前持续有效。
var acquired_skills: Dictionary = {}

## 本局已经获得过的机缘卡稳定ID历史；按获得顺序保存并允许重复，用于机缘模式武将详情长期展示。
var acquired_opportunity_ids: Array[String] = []

## 最近一次公开快照使用的只读机缘历史数组；源历史未变化时由不同观察者共享，避免每次状态广播重复复制长数组。
var _acquired_opportunity_ids_snapshot_cache: Array[String] = []

## 快照缓存对应的源历史长度；默认-1强制首次序列化构建，正式追加会通过长度变化自动失效。
var _acquired_opportunity_snapshot_source_size: int = -1

## 快照缓存对应的源历史首项；默认空字符串，与长度和尾项共同识别常见的直接清空或整体替换。
var _acquired_opportunity_snapshot_source_first_id: String = ""

## 快照缓存对应的源历史尾项；默认空字符串，正式只追加路径可用常量时间判断缓存是否仍然有效。
var _acquired_opportunity_snapshot_source_last_id: String = ""

## 本对象生命周期内机缘公开快照的实际重建次数；默认0，只供性能诊断与回归测试，不进入公开状态。
var _acquired_opportunity_snapshot_rebuild_count: int = 0

## 已按效果类型汇总的机缘数值缓存；键为机缘effect稳定ID，值为截至已处理历史位置的count累计值，只供权威规则查询且不进入公开快照。
var opportunity_effect_totals_cache: Dictionary = {}

## 已写入机缘数值缓存的历史条目数量；默认0表示尚未处理任何记录，历史只追加时可增量汇总，检测到历史替换时由查询端自动重建。
var opportunity_effect_cache_processed_count: int = 0

## 最近一次汇总时已处理前缀的首个机缘ID；默认空字符串，与尾部哨兵共同识别测试或回放工具直接替换历史的情况。
var opportunity_effect_cache_first_processed_id: String = ""

## 最近一次汇总时已处理前缀的末个机缘ID；默认空字符串，正式只追加路径仅在消费新增尾项后更新且不进入公开快照。
var opportunity_effect_cache_last_processed_id: String = ""

## 当前额外手牌上限；默认0，机缘等永久效果可累加修改，最终手牌上限仍不会低于0。
var hand_limit_bonus: int = 0

## 当前模式授予的额外手牌上限；默认0，过关斩将等模式独立写入，避免与机缘和技能的永久加成相互覆盖。
var mode_hand_limit_bonus: int = 0

## 玩家回合历史；每个回合保存阶段跳过、使用牌、响应、伤害和发动技能摘要。
var turn_history: Array[Dictionary] = []

## 当前回合使用牌统计；键为逻辑牌名，值为已经确认使用的次数。
var card_use_history: Dictionary = {}

## 当前出牌阶段使用牌统计；键为逻辑牌名，值为本阶段已经确认使用的次数，进入每个普通或额外出牌阶段时清空。
var play_phase_card_use_history: Dictionary = {}

## 当前回合响应记录；每项保存响应事件 ID、逻辑牌和实体材料 UID。
var response_history: Array[Dictionary] = []

## 当前回合受到或造成的伤害记录；每项保存来源、目标、数值、属性和事件 ID。
var damage_history: Array[Dictionary] = []

## 本局累计造成的有效伤害值；按伤害最终数值累计，护盾吸收的伤害同样属于已经造成的伤害。
var total_damage_dealt: int = 0

## 本局累计受到的有效伤害值；按伤害最终数值累计，护盾吸收的伤害同样属于已经受到的伤害。
var total_damage_received: int = 0

## 本局累计使角色实际回复的体力值；包含对自身和其他角色的回复，但不计入超出体力上限的溢出量。
var total_healing_done: int = 0

## 本局累计实际摸到的牌数；牌堆不足导致未实际获得的牌不会计入。
var total_cards_drawn: int = 0

## 本局累计击杀数；仅统计由其他有效角色造成的真实死亡或模式中的武将击败，不把自杀记为击杀。
var total_kill_count: int = 0

## 本局累计受到有效伤害的次数；正数伤害即使被护盾完全吸收也会增加，用于客户端播放不依赖体力变化的受伤反馈。
var damage_taken_count: int = 0

## 当前回合发动技能记录；每项保存技能 ID、时机、目标和事件 ID。
var skill_history: Array[Dictionary] = []

## 当前回合内未能对指定目标产生预期效果的牌；键为卡牌定义ID，值为目标ID数组，供AI避免重复无效尝试。
var ai_failed_card_target_ids: Dictionary = {}

## 1v1车轮战中已经锁定的三名出场武将；仅本人、权威端与回放可读取完整顺序，对手始终只能看到当前已亮出的武将。
var wheel_duel_lineup: Array[String] = []

## 1v1车轮战当前出场武将在阵容中的索引；范围0至2，普通模式保持0且不参与规则。
var wheel_duel_lineup_index: int = 0

## 1v1车轮战本局已经阵亡的武将数量；范围0至3，达到3时该玩家真正出局并触发胜负结算。
var wheel_duel_defeated_count: int = 0


## 使用稳定 ID 与显示名创建玩家状态，其他字段由开局流程填充。
func _init(id: int = -1, name: String = "玩家") -> void:
	player_id = id
	display_name = name


## 返回当前武器实体牌；未装备武器时返回 null。
func get_weapon() -> CardInstance:
	return equipment.get("weapon") as CardInstance


## 返回当前防具实体牌；未装备防具时返回 null。
func get_armor() -> CardInstance:
	return equipment.get("armor") as CardInstance


## 返回手牌上限。基础规则等于当前体力值，再叠加局内永久加成，最终最低为0。
func get_hand_limit() -> int:
	return maxi(hp + hand_limit_bonus + mode_hand_limit_bonus, 0)


## 按实体牌 UID 查找手牌；未找到时返回 null。
func find_hand_card(card_uid: int) -> CardInstance:
	for card: CardInstance in hand:
		if card.uid == card_uid:
			return card
	return null


## 按实体牌 UID 查找可使用或打出的牌，包括手牌与当前木牛流马下的“粮”。
func find_playable_card(card_uid: int) -> CardInstance:
	# 手牌查询结果；优先返回普通手牌。
	var hand_card: CardInstance = find_hand_card(card_uid)
	if hand_card != null:
		return hand_card
	for stored_card: CardInstance in wooden_ox_storage:
		if stored_card.uid == card_uid:
			return stored_card
	return null


## 移除并返回指定 UID 的手牌；该函数不决定卡牌后续目标区域。
func take_hand_card(card_uid: int) -> CardInstance:
	for index: int in range(hand.size()):
		if hand[index].uid == card_uid:
			return hand.pop_at(index)
	return null


## 移除并返回可使用或打出的牌；先查手牌，再查木牛流马下的“粮”。
func take_playable_card(card_uid: int) -> CardInstance:
	# 从手牌移出的结果；不为空时无需继续查询“粮”。
	var hand_card: CardInstance = take_hand_card(card_uid)
	if hand_card != null:
		return hand_card
	for index: int in range(wooden_ox_storage.size()):
		if wooden_ox_storage[index].uid == card_uid:
			return wooden_ox_storage.pop_at(index)
	return null


## 返回手牌与“粮”组成的可使用牌数组副本；调用方不得据此直接修改玩家区域。
func get_playable_cards() -> Array[CardInstance]:
	# 合并后的可用牌数组；手牌保持在前，“粮”追加在后。
	var result: Array[CardInstance] = hand.duplicate()
	result.append_array(wooden_ox_storage)
	return result


## 返回公开快照使用的只读机缘历史；正式追加会自动重建，整体替换必须调用失效接口以覆盖首尾相同的中段变化。
func get_acquired_opportunity_ids_snapshot() -> Array[String]:
	# 当前源历史长度；与首尾哨兵共同提供常量时间失效检查，不在每次广播重新遍历完整历史。
	var current_source_size: int = acquired_opportunity_ids.size()
	# 当前源历史首项；空历史使用空字符串，正常机缘ID均为非空稳定标识。
	var current_source_first_id: String = "" if acquired_opportunity_ids.is_empty() else acquired_opportunity_ids[0]
	# 当前源历史尾项；只追加后该值变化，重复追加相同ID时仍由长度变化触发重建。
	var current_source_last_id: String = "" if acquired_opportunity_ids.is_empty() else acquired_opportunity_ids.back()
	if current_source_size != _acquired_opportunity_snapshot_source_size \
			or current_source_first_id != _acquired_opportunity_snapshot_source_first_id \
			or current_source_last_id != _acquired_opportunity_snapshot_source_last_id:
		# 新的不可变快照数组；替换引用而不原地修改旧缓存，保证已经发出的状态快照保持发送瞬间的数据。
		var refreshed_snapshot: Array[String] = acquired_opportunity_ids.duplicate()
		refreshed_snapshot.make_read_only()
		_acquired_opportunity_ids_snapshot_cache = refreshed_snapshot
		_acquired_opportunity_snapshot_source_size = current_source_size
		_acquired_opportunity_snapshot_source_first_id = current_source_first_id
		_acquired_opportunity_snapshot_source_last_id = current_source_last_id
		_acquired_opportunity_snapshot_rebuild_count += 1
	return _acquired_opportunity_ids_snapshot_cache


## 使机缘公开快照在下一次序列化时重建；整体替换、回放校准或编辑器工具修改中段条目前必须调用。
func invalidate_acquired_opportunity_snapshot_cache() -> void:
	_acquired_opportunity_snapshot_source_size = -1
	_acquired_opportunity_snapshot_source_first_id = ""
	_acquired_opportunity_snapshot_source_last_id = ""


## 返回机缘公开快照累计重建次数；用于验证重复状态广播没有反复复制长历史，玩法逻辑不得依赖该计数。
func get_acquired_opportunity_snapshot_rebuild_count() -> int:
	return _acquired_opportunity_snapshot_rebuild_count


## 返回适合指定观察者的状态快照；他人只能看到手牌数量，不能看到牌面。
func to_dict(viewer_id: int = -1, reveal_private: bool = false) -> Dictionary:
	# 序列化后的装备区；装备属于公共信息，始终包含完整实体牌数据。
	var equipment_data: Dictionary = {}
	for slot_variant: Variant in equipment.keys():
		# 当前装备槽名称；用于保持网络结构与规则层一致。
		var slot: String = str(slot_variant)
		# 当前装备实体牌；空槽不会出现在字典中。
		var card: CardInstance = equipment[slot] as CardInstance
		equipment_data[slot] = card.to_dict()

	# 序列化后的手牌；只有本人、回放或服务器调试快照包含牌面。
	var hand_data: Array = []
	if reveal_private or viewer_id == player_id:
		for card: CardInstance in hand:
			hand_data.append(card.to_dict())

	# 序列化后的判定区；延时锦囊属于公共信息。
	var judgment_data: Array = []
	for card: CardInstance in judgment_area:
		judgment_data.append(card.to_dict())

	# 序列化后的“粮”；仅所有者或权威调试快照可看到牌面，其他玩家只看到数量。
	var wooden_ox_data: Array = []
	if reveal_private or viewer_id == player_id:
		for card: CardInstance in wooden_ox_storage:
			wooden_ox_data.append(card.to_dict())

	return {
		"player_id": player_id,
		"display_name": display_name,
		"character_id": character_id if character_revealed or viewer_id == player_id or reveal_private else "",
		"character_generation": character_generation,
		"character_revealed": character_revealed,
		"identity": identity if identity_revealed or viewer_id == player_id or reveal_private else "hidden",
		"identity_revealed": identity_revealed,
		"hp": hp,
		"max_hp": max_hp,
		"shield": shield,
		"alive": alive,
		"dying": dying,
		"death_confirmed": death_confirmed,
		"out_of_game": out_of_game,
		"out_of_game_until_round": out_of_game_until_round,
		"chained": chained,
		"face_down": face_down,
		"character_corner_text": character_corner_text,
		"character_corner_text_entries": character_corner_text_entries.duplicate(true),
		"public_marks": public_marks.duplicate(true),
		"auto_managed": auto_managed,
		"auto_managed_offline": auto_managed_offline,
		"wine_used": wine_used,
		"wine_bonus": wine_bonus,
		"hand_count": hand.size(),
		"hand": hand_data,
		"equipment": equipment_data,
		"judgment_area": judgment_data,
		"wooden_ox_storage_count": wooden_ox_storage.size(),
		"wooden_ox_storage": wooden_ox_data,
		"temporary_skills": temporary_skills.duplicate(true),
		"acquired_skills": acquired_skills.duplicate(true),
		"acquired_opportunity_ids": get_acquired_opportunity_ids_snapshot(),
		"hand_limit_bonus": hand_limit_bonus,
		"mode_hand_limit_bonus": mode_hand_limit_bonus,
		"turn_history_count": turn_history.size(),
		"card_use_history": card_use_history.duplicate(true),
		"play_phase_card_use_history": play_phase_card_use_history.duplicate(true),
		"response_history_count": response_history.size(),
		"damage_history_count": damage_history.size(),
		"total_damage_dealt": total_damage_dealt,
		"total_damage_received": total_damage_received,
		"total_healing_done": total_healing_done,
		"total_cards_drawn": total_cards_drawn,
		"total_kill_count": total_kill_count,
		"damage_taken_count": damage_taken_count,
		"ai_failed_card_target_ids": ai_failed_card_target_ids.duplicate(true),
		"wheel_duel_lineup": wheel_duel_lineup.duplicate() if reveal_private or viewer_id == player_id else [],
		"wheel_duel_lineup_index": wheel_duel_lineup_index if reveal_private or viewer_id == player_id else -1,
		"wheel_duel_defeated_count": wheel_duel_defeated_count,
		# 技能发动历史是公开事实；AI用稳定回合号与目标上下文判断“每回合每名角色限一次”。
		"skill_history": skill_history.duplicate(true),
		"skill_history_count": skill_history.size(),
	}
