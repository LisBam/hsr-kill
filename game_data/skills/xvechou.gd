extends SkillDefinition

## 【血仇】技能源码。持有者进入濒死时按当前轮回节执行回复或减上限摸牌，并以轮回数X作为效果值。

## 回复效果所在的①轮回节零基索引；固定0对应玩家可见的①。
const RECOVER_SECTION_INDEX: int = 0

## 减少体力上限效果所在的②轮回节零基索引；固定1对应玩家可见的②。
const MAX_HP_DRAW_SECTION_INDEX: int = 1

## ②轮回节固定减少的体力上限；数值1来自技能原文，修改时必须同步玩法文档。
const MAX_HP_LOSS: int = 1


## 写入轮回锁定技静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"xvechou",
		"name":"血仇",
		"trigger":"dyingBegin",
		"ui_enabled":false,
		"lock":true,
		"reincarnation":true,
		"reincarnation_section_count":2,
		"reincarnation_has_explicit_sections":true,
		"description":"轮回技，锁定技，当你进入濒死状态时，①你回复X点体力；②你减少1点体力上限。（X为本技能的轮回数）",
	})


## 订阅持有者进入濒死的开始时机；锁定技满足条件后直接执行当前轮回节。
func install() -> void:
	subscribe_timing("dyingBegin", _on_owner_dying_begin, "player")


## 按当前轮回节与轮回数执行血仇；每次实际执行完成后统一推进轮回状态。
func _on_owner_dying_begin(_event: RuleEvent) -> void:
	# 技能持有者；必须仍存活、在场且处于濒死体力范围。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or owner.hp > 0 or not begin_reincarnation_activation():
		return
	# 本次效果使用的轮回数X；在效果与日志完成前保持同一快照。
	var round_count: int = get_reincarnation_round_count()
	# 本次效果所在轮回节；服务使用零基索引，分别对应正文①与②。
	var section_index: int = get_reincarnation_section_index()
	if section_index == RECOVER_SECTION_INDEX:
		announce_activation({"round_count":round_count, "section_number":section_index + 1, "recover":round_count})
		host.call("recover", owner_player_id, owner_player_id, round_count, get_id())
	elif section_index == MAX_HP_DRAW_SECTION_INDEX:
		announce_activation({"round_count":round_count, "section_number":section_index + 1, "max_hp_loss":MAX_HP_LOSS, "draw_count":round_count})
		# 当前已经位于dyingBegin；关闭体力上限端口的重复濒死入口，让外层流程在本技能完成后继续统一求救。
		host.call("change_max_hp", owner_player_id, -MAX_HP_LOSS, owner_player_id, get_id(), false, false)
	complete_reincarnation_activation()


## 修正AI对持有者预计致命来牌的估值；①可回复X点时按回复后的生存结果而非直接死亡评估。
func modify_ai_incoming_card_effect(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, _definition: Dictionary, ai_profile: Dictionary, _target_result: float, expected_damage_amount: int, current_score: float, evaluator: Object) -> float:
	if target_id != owner_player_id or not bool(ai_profile.get("damage", false)) or get_reincarnation_section_index() != RECOVER_SECTION_INDEX:
		return current_score
	# 血仇持有者快照；只有预计伤害会令其进入濒死时才替换普通致死估值。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or int(target.get("hp", 0)) + int(target.get("shield", 0)) > expected_damage_amount:
		return current_score
	# 回复后的预期体力；X至少为1，结果用于统一资源变化评分并保留双方阵营关系。
	var recovered_hp: int = mini(maxi(int(target.get("hp", 0)) - expected_damage_amount + get_reincarnation_round_count(), 1), int(target.get("max_hp", 1)))
	# 相对受伤前体力变化；按实际伤害与随后回复的合并结果估值。
	var net_hp_change: int = recovered_hp - int(target.get("hp", 0))
	return evaluator.score_resource_change(authoritative_snapshot, actor_id, target_id, 0, net_hp_change)
