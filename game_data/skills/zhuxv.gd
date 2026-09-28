extends SkillDefinition

## 【逐虚】技能源码。两节轮回技：①弃置随机一名有牌的角色随机一张牌；②对随机一名角色造成1点伤害。
## 两节共用同一个“出牌阶段限两次”额度，恰好等于走完一个完整轮回所需的发动次数。

## 轮回节总数；与描述中的①②一一对应，走完最后一节即回到第一节。
const SECTION_COUNT: int = 2

## 轮回节序号：随机弃置一名有牌角色的一张牌。
const SECTION_DISCARD: int = 0

## 轮回节序号：对随机一名角色造成伤害。
const SECTION_DAMAGE: int = 1

## 整个技能每个出牌阶段的发动上限；数值2来自技能原文“出牌阶段限两次”。
const PLAY_PHASE_LIMIT: int = 2

## 随机伤害节造成的伤害值；数值1来自技能原文“造成1点伤害”。
const DAMAGE_AMOUNT: int = 1

## 第一层随机的历史类别：①被选中的目标角色。
const HISTORY_DISCARD_TARGET: String = "zhuxv_random_discard_target"

## 第二层随机的历史类别：①在该角色区域内选中的牌。
const HISTORY_DISCARD_CARD: String = "zhuxv_random_discard_card"

## ②的随机历史类别：被选中的伤害目标角色。
const HISTORY_DAMAGE_TARGET: String = "zhuxv_random_damage_target"

## 最近一次结算的共享记录键；写入持有者的武将私有数据供【揭质】复核“同一目标、同一效果”。
const LAST_RESOLVED_KEY: String = "zhuxv_last_resolved"

## 可选装备栏稳定顺序；随机取牌需要遍历全部装备槽，顺序与玩家状态定义保持一致。
const EQUIPMENT_SLOTS: Array[String] = ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]

## 友方被②误伤时的追加惩罚系数；系数越高，AI越避免在自己或队友体力偏低时发动伤害节。
const FRIENDLY_FIRE_PENALTY: float = 2.0

## 当前出牌阶段已发动次数；进入每个出牌阶段复原，与轮回服务自带的每轮回节限次并存复核。
var _used_this_play_phase: int = 0


## 写入两轮回节主动技能静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"zhuxv",
		"name":"逐虚",
		"trigger":"active/phaseUse",
		"enable":"phaseUse",
		"ui_enabled":true,
		"reincarnation":true,
		"reincarnation_section_count":2,
		"reincarnation_has_explicit_sections":true,
		"description":"轮回技，出牌阶段限两次，你可①弃置随机一名有牌的角色随机一张牌；②对随机一名角色造成1点伤害。",
	})


## 订阅出牌阶段开始以复原阶段额度。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")


## 每个出牌阶段复原“限两次”额度；普通与额外出牌阶段一视同仁。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = 0


## 检查出牌阶段归属、阶段额度、轮回额度与本节是否存在合法随机候选。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或非自身出牌阶段均不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 阶段额度；整个技能每阶段最多发动两次。
	if _used_this_play_phase >= PLAY_PHASE_LIMIT:
		return false
	# 轮回额度；与阶段额度是两套独立机制，任一耗尽都不开放入口。
	if not can_activate_reincarnation():
		return false
	# 本节候选；没有合法目标时不开放入口，避免产生空效果并浪费额度。
	if get_reincarnation_section_index() == SECTION_DISCARD:
		return not _get_discard_target_ids().is_empty()
	return not _get_damage_target_ids().is_empty()


## 发动当前轮回节；效果完全由权威随机结果决定，动作不携带任何参数。
func activate(_context: Dictionary = {}) -> String:
	if not can_activate():
		return "【逐虚】当前不满足发动条件。"
	# 当前轮回节；在推进前锁定快照，防止后续步骤改变索引导致效果错配。
	var section_index: int = get_reincarnation_section_index()
	if not begin_reincarnation_activation():
		return "【逐虚】当前轮回节的发动额度已用尽。"
	_used_this_play_phase += 1
	if section_index == SECTION_DISCARD:
		_execute_random_discard()
	else:
		_execute_random_damage()
	# 轮回推进必须在效果落地后完成；②完成后轮回数加一并回到①。
	complete_reincarnation_activation()
	return ""


## 为AI枚举本技能在本出牌阶段的候选动作；随机效果无参数，因此只提交一个空负载动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})


## 执行①随机弃牌：先在有牌角色中等概率取一名，再在该角色区域内等概率取一张弃置。
func _execute_random_discard() -> void:
	# 有牌的角色（含自己）；区域内至少有一张牌才参与本次随机。
	var target_ids: Array[int] = _get_discard_target_ids()
	if target_ids.is_empty():
		return
	# 第一层随机：目标角色；索引由权威随机流产生并写入随机历史。
	var target_index: int = int(host.call("pick_random_candidate_index", target_ids.size(), HISTORY_DISCARD_TARGET, {"skill_id":get_id(), "section_index":SECTION_DISCARD}))
	if target_index < 0:
		return
	# 已锁定的目标角色；其后所有随机与效果都只作用于该角色。
	var target_id: int = target_ids[target_index]
	# 第二层随机：该角色区域内的一张牌；目标确定后重新取区域快照，避免使用过期候选。
	var card_uids: Array[int] = _get_zone_card_uids(target_id)
	if card_uids.is_empty():
		return
	var card_index: int = int(host.call("pick_random_candidate_index", card_uids.size(), HISTORY_DISCARD_CARD, {"skill_id":get_id(), "target_id":target_id}))
	if card_index < 0:
		return
	# 最终被弃置的实体牌；权威入口按牌所在区域选择正确路径并派发弃置时机。
	var card_uid: int = card_uids[card_index]
	announce_activation({"section_number":SECTION_DISCARD + 1, "round_count":get_reincarnation_round_count(), "target_id":target_id, "card_uid":card_uid})
	host.call("discard_selected_player_cards", target_id, [card_uid] as Array[int], owner_player_id)
	_record_section_resolved(SECTION_DISCARD, target_id)


## 执行②随机伤害：在全部存活角色中等概率取一名（含自己），对其造成1点伤害。
func _execute_random_damage() -> void:
	# 全部存活角色；原文未要求目标有牌，因此不施加任何区域限制，自己同样是合法目标。
	var target_ids: Array[int] = _get_damage_target_ids()
	if target_ids.is_empty():
		return
	var target_index: int = int(host.call("pick_random_candidate_index", target_ids.size(), HISTORY_DAMAGE_TARGET, {"skill_id":get_id(), "section_index":SECTION_DAMAGE}))
	if target_index < 0:
		return
	# 已锁定的伤害目标；伤害来源统一记为技能持有者以保留击杀归属。
	var target_id: int = target_ids[target_index]
	announce_activation({"section_number":SECTION_DAMAGE + 1, "round_count":get_reincarnation_round_count(), "target_id":target_id, "amount":DAMAGE_AMOUNT})
	host.call("damage", owner_player_id, target_id, DAMAGE_AMOUNT)
	_record_section_resolved(SECTION_DAMAGE, target_id)


## 记录最近一次结算的节编号与目标；【揭质】据此复核“同一目标、同一效果”。
func _record_section_resolved(section_index: int, target_id: int) -> void:
	# 技能持有者；结算完成时角色必然有效，判空仅为防御异步期间的极端情况。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return
	# 共享记录写入武将私有数据容器：该容器既参与存档，也不属于任何单一技能实例的私有效率字段。
	owner.character_form_state[LAST_RESOLVED_KEY] = {
		"section_index":section_index,
		"target_id":target_id,
		"resolved_turn_number":host.state.turn_number,
		"character_generation":owner.character_generation,
	}


## 收集①的合法目标：区域内（手牌/装备区/判定区）至少有一张牌的角色，含自己。
func _get_discard_target_ids() -> Array[int]:
	# 结果按座次顺序追加；顺序本身不影响等概率语义，但保证同种子结果可复现。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player == null or not player.alive or player.out_of_game:
			continue
		if not _get_zone_card_uids(player.player_id).is_empty():
			result.append(player.player_id)
	return result


## 收集②的合法目标：全部存活角色，含自己，不要求有牌。
func _get_damage_target_ids() -> Array[int]:
	# 结果按座次顺序追加；死亡与离场角色不参与随机。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player == null or not player.alive or player.out_of_game:
			continue
		result.append(player.player_id)
	return result


## 收集指定角色当前可被随机弃置的区域牌UID；覆盖手牌、装备区与判定区。
func _get_zone_card_uids(target_id: int) -> Array[int]:
	var player: PlayerState = host.state.get_player(target_id)
	if player == null:
		return []
	# 结果按“手牌→装备→判定”的固定顺序构建，保证同种子下两层随机结果稳定可复现。
	var result: Array[int] = []
	for hand_card: CardInstance in player.hand:
		result.append(hand_card.uid)
	for slot: String in EQUIPMENT_SLOTS:
		if player.equipment.has(slot):
			result.append((player.equipment[slot] as CardInstance).uid)
	for judgment_card: CardInstance in player.judgment_area:
		result.append(judgment_card.uid)
	return result


## AI按“等概率命中每一名存活角色”估算逐虚的期望收益；伤害节在命中自己或队友时追加惩罚。
## AI钩子没有host，只能读取权威快照与估值器，因此轮回节从快照的轮回状态中读取。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	# 持有者快照；缺失时不给分，避免无效动作进入AI候选。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty():
		return 0.0
	# 存活角色列表；与权威目标收集使用同一套存活判定。
	var alive_ids: Array[int] = []
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；死亡或离场角色不参与随机。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)):
			alive_ids.append(int(player.get("player_id", -1)))
	if alive_ids.is_empty():
		return 0.0
	# 当前轮回节索引；读取权威轮回状态，缺失时按第一节估算。
	var reincarnation_state: Dictionary = (owner.get("reincarnation_skills", {}) as Dictionary).get(get_id(), {}) as Dictionary
	# 轮回节零基索引；服务使用与技能常量相同的编号口径。
	var section_index: int = int(reincarnation_state.get("section_index", SECTION_DISCARD))
	# 每名存活角色的命中概率；两层随机的第一层与②的单层随机都是等概率，因此期望值可直接加权求和。
	var hit_chance: float = 1.0 / float(alive_ids.size())
	var score: float = 0.0
	for target_id: int in alive_ids:
		# 目标敌我态度；正值表示友方，用于判断效果方向。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		if section_index == SECTION_DISCARD:
			# ① 命中敌方视为削弱收益，命中友方视为损失；统一按“目标失去一张牌”换算。
			var discard_gain: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, -1, 0)
			score += hit_chance * discard_gain
		else:
			# ② 伤害的期望收益；对敌方为正、对友方为负，方向由估值器按态度给出。
			var damage_gain: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 0, -DAMAGE_AMOUNT)
			score += hit_chance * damage_gain
			# 额外惩罚：目标是自己或队友时，体力越低损失越大，体现“队友或自己体力值低时降低收益”。
			if attitude > 0.0:
				var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
				# 目标已损失的体力值；0表示满体力，此时只承受基础惩罚。
				var hp_deficit: float = maxf(float(target.get("max_hp", 0)) - float(target.get("hp", 0)), 0.0)
				score -= hit_chance * (1.0 + hp_deficit) * FRIENDLY_FIRE_PENALTY
	# 随机削弱与随机伤害都存在下限收益；至少给出一个正分，避免AI完全不使用本技能。
	return maxf(score, 0.5)
