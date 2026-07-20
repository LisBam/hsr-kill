class_name AICharacterAdjustmentService
extends RefCounted

## 开局前 AI 武将调整服务。该组件只维护可调整 AI、当前目标和重新随机的候选，不安装技能、不修改玩家状态。

## 当前是否仍处于房主调整阶段；false表示房主已确认结束，控制器可以继续发放起始手牌。
var active: bool = false

## 本局拥有调整权限的房主玩家 ID；离线模式为本地真人，局域网模式为房主绑定玩家。
var host_player_id: int = -1

## 每次点击 AI 后重新随机发放的候选数量；最少1张且不超过武将库大小。
var candidate_count: int = 5

## 是否允许调整 AI 时打开“所有武将”；来源为本局已经锁定的房主权威设置。
var allow_all_characters: bool = false

## 当前被房主选中的 AI 玩家 ID；-1表示正在等待房主点击场上 AI 武将牌。
var selected_ai_player_id: int = -1

## 本局允许被调整的 AI 玩家 ID；按当前最终座次保存，界面只使用稳定 ID。
var _ai_player_ids: Array[int] = []

## 全部已登记武将 ID 副本；候选生成与“所有武将”都不修改全局数据库索引。
var _character_ids: Array[String] = []

## 当前目标本次重新随机得到的武将候选；切换目标时整体替换。
var _current_candidates: Array[String] = []

## 对局控制器注入的随机数生成器；与身份、牌堆和初次选将共享同一可复现随机源。
var _rng: RandomNumberGenerator


## 创建一次房主调整阶段；没有 AI 时保持 inactive，调用方可直接继续开局。
func begin(ai_player_ids: Array[int], character_ids: Array[String], requested_candidate_count: int, can_show_all_characters: bool, authority_player_id: int, rng: RandomNumberGenerator) -> void:
	_ai_player_ids = ai_player_ids.duplicate()
	_character_ids = character_ids.duplicate()
	candidate_count = clampi(requested_candidate_count, 1, maxi(_character_ids.size(), 1))
	allow_all_characters = can_show_all_characters
	host_player_id = authority_player_id
	selected_ai_player_id = -1
	_current_candidates.clear()
	_rng = rng
	active = not _ai_player_ids.is_empty() and not _character_ids.is_empty() and host_player_id >= 0


## 为房主点击的 AI 重新随机候选；返回空字符串表示目标合法且选将框可以打开。
func select_ai_target(actor_id: int, target_player_id: int) -> String:
	if not active:
		return "当前没有可调整的 AI 武将。"
	if actor_id != host_player_id:
		return "只有房主可以调整 AI 武将。"
	if not _ai_player_ids.has(target_player_id):
		return "所选角色不是可调整的 AI。"
	selected_ai_player_id = target_player_id
	_current_candidates = _make_candidates()
	return ""


## 校验房主为当前目标提交的武将；成功后关闭选将框并返回场上目标选择状态。
func select_character(actor_id: int, target_player_id: int, character_id: String) -> String:
	if not active or actor_id != host_player_id:
		return "只有房主可以调整 AI 武将。"
	if target_player_id != selected_ai_player_id or not _ai_player_ids.has(target_player_id):
		return "当前 AI 调整目标已经失效。"
	# 合法武将集合；开启全部武将时可提交数据库中的任意武将，否则必须来自本次随机候选。
	var valid_character_ids: Array[String] = _character_ids if allow_all_characters else _current_candidates
	if not valid_character_ids.has(character_id):
		return "所选武将不在当前 AI 候选列表中。"
	selected_ai_player_id = -1
	_current_candidates.clear()
	return ""


## 结束房主调整阶段；任何尚未确认的当前目标都会直接放弃，不改变其现有武将。
func finish(actor_id: int) -> String:
	if not active:
		return "当前没有进行中的 AI 武将调整。"
	if actor_id != host_player_id:
		return "只有房主可以结束 AI 武将调整。"
	active = false
	selected_ai_player_id = -1
	_current_candidates.clear()
	return ""


## 返回公共可点击 AI 玩家 ID 副本；所有客户端可用它绘制合法目标，但只有房主能提交动作。
func get_ai_player_ids() -> Array[int]:
	return _ai_player_ids.duplicate()


## 返回面向指定观察者的选将框快照；只有房主选中 AI 后才能取得私有候选。
func to_selection_dict(viewer_id: int) -> Dictionary:
	if not active or viewer_id != host_player_id or selected_ai_player_id < 0:
		return {}
	return {
		"phase":"ai_character_adjustment_selecting",
		"selection_kind":"ai_adjustment",
		"local_player_id":viewer_id,
		"target_player_id":selected_ai_player_id,
		"local_candidates":_current_candidates.duplicate(),
		"all_character_ids":_character_ids.duplicate() if allow_all_characters else [],
		"allow_all_characters":allow_all_characters,
		"allow_custom_assignment":false,
		"can_select":true,
	}


## 使用本局随机源生成一组不重复候选；每次重新点击 AI 都会重新洗牌。
func _make_candidates() -> Array[String]:
	# 可写候选池；全局武将数组只读保留。
	var pool: Array[String] = _character_ids.duplicate()
	for index: int in range(pool.size() - 1, 0, -1):
		# 当前交换索引；共享随机源保证固定种子下候选可复现。
		var swap_index: int = _rng.randi_range(0, index)
		# 当前临时武将 ID；完成标准 Fisher-Yates 交换。
		var temporary: String = pool[index]
		pool[index] = pool[swap_index]
		pool[swap_index] = temporary
	# 本次候选结果；数量不会超过武将库。
	var result: Array[String] = []
	for candidate_index: int in range(mini(candidate_count, pool.size())):
		result.append(pool[candidate_index])
	return result
