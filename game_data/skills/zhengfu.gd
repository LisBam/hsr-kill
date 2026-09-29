extends SkillDefinition

## 【征服】技能源码。刻律德菈击杀其他角色后固定回复1点体力，然后按被击杀者势力二选一结算：
## 非翁法罗斯角色阵亡时，所有翁法罗斯势力的角色的轮回技进入下一个轮回节；
## 翁法罗斯角色阵亡时，刻律德菈本次的击杀奖惩被整体改写为摸四张牌。
## 本技能是锁定技，满足条件即自动结算，不创建任何确认或选择请求。

## 翁法罗斯势力稳定ID；同时用于判断被击杀者势力与需要推进轮回节的角色范围。
const FACTION_ID: String = "wengfaluosi"

## 每次击杀固定回复的体力值；数值1来自原文“回复1点体力”，修改会直接改变该领袖的续航强度。
const RECOVER_AMOUNT: int = 1

## 击杀奖惩改写类型；与死亡结算组件声明的“摸四张牌”类型保持同一稳定字符串。
const KILL_REWARD_DRAW_FOUR: String = DeathResolutionService.KILL_REWARD_DRAW_FOUR_TYPE

## AI认定“可牺牲队友”的体力上限；目标体力不高于该值时才有资格被用于换取四张牌。
const AI_SACRIFICIAL_HP_LIMIT: int = 1

## AI认定“可牺牲队友”的手牌上限；手握资源的队友仍有后续价值，不纳入牺牲评估。
const AI_SACRIFICIAL_HAND_LIMIT: int = 0

## AI认定“行动靠后”的最少座次距离；达到该距离说明目标短期内轮不到行动，牺牲代价最低。
const AI_LATE_TURN_DISTANCE: int = 3


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id":"zhengfu",
		"name":"征服",
		"trigger":"die",
		"ui_enabled":false,
		"leader_skill":true,
		"lock":true,
		"description":"领袖技，锁定技，当你击杀其他角色时，你回复1点体力，然后若其势力不为“翁法罗斯”，所有“翁法罗斯”势力的角色的轮回技进入下一个轮回节；否则，你的击杀奖惩改为摸四张牌。",
	})


## 订阅死亡时机；使用source角色关系，只有本技能持有者确实是伤害来源时才进入结算。
func install() -> void:
	subscribe_timing("die", _on_kill, "source")


## 持有者击杀其他角色后结算回复体力与势力分支；击杀奖惩改写由modify_death_reward在同一次死亡流程中完成。
func _on_kill(event: RuleEvent) -> void:
	# 被击杀角色ID；无来源伤害、自杀与失去体力造成的阵亡都不满足“击杀其他角色”。
	var victim_id: int = event.target_id if event != null else -1
	if victim_id < 0 or victim_id == owner_player_id:
		return
	# 技能持有者；死亡或离场的领袖不再回复体力，也不再推进其他角色的轮回技。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 被击杀角色；复活、车轮战换将与过关斩将换将都不是真实阵亡，一律不结算本技能。
	var victim: PlayerState = host.state.get_player(victim_id) as PlayerState
	if victim == null or victim.alive or not victim.death_confirmed:
		return
	# 本次被击杀者势力；同一取值同时决定下面走“推进轮回节”还是“保留奖惩改写分支”。
	var victim_faction_id: String = _get_player_faction_id(victim)
	announce_activation({"victim_id":victim_id, "victim_faction":victim_faction_id})
	_recover_owner(owner)
	if victim_faction_id == FACTION_ID:
		return
	_advance_all_faction_reincarnation_sections()


## 令持有者回复固定1点体力；已经满体力时没有可回复缺口，直接跳过。
func _recover_owner(owner: PlayerState) -> void:
	if owner.hp >= owner.max_hp:
		return
	host.call("recover", owner_player_id, owner_player_id, RECOVER_AMOUNT, get_id())


## 令所有存活在场的翁法罗斯势力角色的全部轮回技进入下一个轮回节；最后一节会自动进入下一轮回。
func _advance_all_faction_reincarnation_sections() -> void:
	for player: PlayerState in host.state.players:
		if player == null or not player.alive or player.out_of_game or not _is_faction_player(player, FACTION_ID):
			continue
		# 当前角色全部轮回技；经控制器公开端口读取，技能不自行遍历PlayerState内部字典。
		var reincarnation_skill_ids: Array[String] = []
		reincarnation_skill_ids.assign(host.call("list_reincarnation_skill_ids", player.player_id))
		for skill_id: String in reincarnation_skill_ids:
			host.call("enter_next_reincarnation_section", player.player_id, skill_id)


## 被击杀者属于翁法罗斯时，把持有者本次击杀奖惩整体改写为摸四张牌；其余势力保留身份规则基础奖惩。
func modify_death_reward(victim_snapshot: Dictionary, _base_reward: String) -> String:
	# 势力判定只使用稳定武将定义；未亮将或未知势力一律视为不满足条件。
	if _get_snapshot_faction_id(victim_snapshot) != FACTION_ID:
		return ""
	return KILL_REWARD_DRAW_FOUR


## 判断权威玩家当前武将是否属于指定势力；势力元数据只筛选技能作用范围，不替代身份模式阵营。
func _is_faction_player(player: PlayerState, faction_id: String) -> bool:
	return _get_player_faction_id(player) == faction_id


## 返回权威玩家的势力ID；未知武将、空武将或空定义统一返回空字符串。
func _get_player_faction_id(player: PlayerState) -> String:
	if player == null:
		return ""
	return str((GameDatabase.get_character(player.character_id) as Dictionary).get("faction", ""))


## 从公开快照中取出指定玩家的字典；技能AI钩子只读取快照，不访问评估器内部状态。
func _get_snapshot_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前快照玩家；按稳定player_id匹配，座次顺序不影响结果。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}


## 从公开快照读取势力ID；未亮将时character_id为空，因此按未知势力处理，不推测隐藏信息。
func _get_snapshot_faction_id(player_snapshot: Dictionary) -> String:
	# 目标武将ID；空值表示该武将尚未公开。
	var character_id: String = str(player_snapshot.get("character_id", ""))
	if character_id.is_empty():
		return ""
	return str((GameDatabase.get_character(character_id) as Dictionary).get("faction", ""))


## 修正“即将击杀翁法罗斯势力角色”的身份局后果评分；本技能把误杀奖惩换成四张牌，因此必须重估。
func modify_ai_lethal_damage_consequence(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, current_score: float, evaluator: Object) -> float:
	# 只有本技能持有者自己的击杀会被改写奖惩；其他角色的估值不受影响。
	if actor_id != owner_player_id:
		return current_score
	# 目标公开快照；不存在、已死亡或离场的目标不进入改写链。
	var target: Dictionary = _get_snapshot_player(authoritative_snapshot, target_id)
	if target.is_empty() or not bool(target.get("alive", false)):
		return current_score
	# 目标势力；非翁法罗斯角色走“推进轮回节”分支，不会改写击杀者的击杀奖惩。
	if _get_snapshot_faction_id(target) != FACTION_ID:
		return current_score
	# 改写后的评分；先撤销通用层已经计入的“领袖误杀忠臣”弃牌惩罚，再计入四张牌的规则收益。
	var result: float = current_score + _get_overridden_leader_penalty(authoritative_snapshot, actor_id, target_id, evaluator)
	result += float(DeathResolutionService.KILL_REWARD_DRAW_FOUR_COUNT) * NonameAIEvaluator.CARD_RESOURCE_VALUE
	# 同阵营减员补偿；只对击杀者视角下的己方角色生效，避免为敌方目标重复加值。
	if _is_perceived_ally(authoritative_snapshot, actor_id, target_id, evaluator):
		result += _get_sacrificial_ally_recovery(authoritative_snapshot, target, evaluator)
	return result


## 返回通用估值已经计入、但被本技能改写掉的规则奖惩分值；不存在该项惩罚时返回0。
func _get_overridden_leader_penalty(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, evaluator: Object) -> float:
	# 击杀者快照；非领袖不存在“误杀忠臣后弃置全部手牌和装备”的规则惩罚。
	var actor: Dictionary = _get_snapshot_player(authoritative_snapshot, actor_id)
	if str(actor.get("identity", "")) != "leader":
		return 0.0
	# 目标感知身份；未暴露为忠臣时通用层不会追加该惩罚，也就没有需要撤销的部分。
	if evaluator.get_perceived_identity(authoritative_snapshot, target_id) != "loyalist":
		return 0.0
	# 通用惩罚的可弃资源部分；与身份战略评估器保持同一对手牌与装备的计数口径。
	var discarded_resource_count: int = maxi(int(actor.get("hand_count", 0)), 0) + _get_snapshot_equipment_count(actor)
	return IdentityStrategyEvaluator.LEADER_KILL_LOYALIST_BASE_PENALTY + float(discarded_resource_count) * IdentityStrategyEvaluator.LEADER_KILL_LOYALIST_RESOURCE_PENALTY


## 判断目标在击杀者视角是否属于同阵营；只读取自身身份与目标感知身份，不窥视隐藏身份。
func _is_perceived_ally(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, evaluator: Object) -> bool:
	# 击杀者自身身份；身份局中AI始终知道自己的阵营。
	var actor_identity: String = str(_get_snapshot_player(authoritative_snapshot, actor_id).get("identity", ""))
	# 目标感知身份；未公开身份时不会形成同阵营结论。
	var target_identity: String = evaluator.get_perceived_identity(authoritative_snapshot, target_id)
	if actor_identity in ["leader", "loyalist"]:
		return target_identity in ["leader", "loyalist"]
	if actor_identity == "rebel":
		return target_identity == "rebel"
	return false


## 返回“用低价值己方角色换取四张牌”时补回的同阵营减员损失；只对没有短期行动价值的队友生效。
func _get_sacrificial_ally_recovery(authoritative_snapshot: Dictionary, target: Dictionary, evaluator: Object) -> float:
	# 牺牲前提：目标体力与手牌都已低到无法继续提供行动价值。
	if int(target.get("hp", 0)) > AI_SACRIFICIAL_HP_LIMIT or int(target.get("hand_count", 0)) > AI_SACRIFICIAL_HAND_LIMIT:
		return 0.0
	# 目标距离下次行动的座次距离；越靠后说明其被保留的价值越低。
	var turn_distance: int = evaluator.get_turn_distance(authoritative_snapshot, int(target.get("player_id", -1)))
	# 行动位置折算比例；距离达到认定阈值时视为完全没有短期行动价值。
	var sacrifice_ratio: float = clampf(float(turn_distance) / float(maxi(AI_LATE_TURN_DISTANCE, 1)), 0.0, 1.0)
	return IdentityStrategyEvaluator.ALLY_LETHAL_DAMAGE_PENALTY * sacrifice_ratio


## 统计公开快照中实际装备件数；空槽位占位字典不计入，与身份战略评估器保持同一口径。
func _get_snapshot_equipment_count(player_snapshot: Dictionary) -> int:
	# 玩家装备槽位快照；缺失时按空字典处理，保证裁剪快照也能安全使用。
	var equipment: Dictionary = player_snapshot.get("equipment", {}) as Dictionary
	# 已装备件数；遍历固定槽位值而非字典长度，避免空槽占位字典被误计入。
	var equipment_count: int = 0
	for equipment_variant: Variant in equipment.values():
		# 当前槽位装备；非空字典才代表一件会被奖惩弃置的装备。
		var equipment_card: Dictionary = equipment_variant as Dictionary
		if not equipment_card.is_empty():
			equipment_count += 1
	return equipment_count
