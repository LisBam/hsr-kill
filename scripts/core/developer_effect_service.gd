class_name DeveloperEffectService
extends RefCounted

## 开发者调试效果队列。只保存稳定效果键、目标座次与可序列化载荷，
## 由统一结算管线在优先级链末端逐条消费，自身不持有 Callable、节点或任何规则状态。
##
## 设计意图：单机调试需要在「当前结算完全空闲」的那一刻精确注入一次数值效果。
## 直接调用规则端口会把效果插进正在进行的结算中间，破坏时机顺序与因果链；
## 因此本服务只负责排队，真正的执行仍全部经 MatchController 的公开规则端口完成，
## 不复制任何数值公式，也不直接改写 GameState / PlayerState 字段。
##
## 使用方式：MatchController 持有唯一实例；界面调用 enqueue() 入队，
## 统一结算管线在空闲边界调用 resume_next() 消费一条，重开局 / 终局 / 拆除运行时时调用 reset()。

## 效果键：摸牌。让目标走权威摸牌流程摸指定张数。
const EFFECT_DRAW: String = "draw"

## 效果键：弃牌。让目标从其普通手牌中自行选择并弃置指定张数。
const EFFECT_DISCARD: String = "discard"

## 效果键：回复体力。走权威回复流程，受体力上限截断，满体力时不产生任何变化。
const EFFECT_RECOVER: String = "recover"

## 效果键：失去体力。绕过护盾、防具与伤害事件，与「受到伤害」语义不同。
const EFFECT_LOSE_HP: String = "lose_hp"

## 效果键：受到伤害。固定为无来源普通伤害，仍走完整防具修正、濒死与属性连环流程。
const EFFECT_DAMAGE: String = "damage"

## 效果键：增加体力上限。
const EFFECT_GAIN_MAX_HP: String = "gain_max_hp"

## 效果键：减少体力上限。权威端保证至少保留 1 点上限。
const EFFECT_LOSE_MAX_HP: String = "lose_max_hp"

## 效果键：获得护盾。
const EFFECT_GAIN_SHIELD: String = "gain_shield"

## 效果键：失去护盾。护盾不足时按实际值扣减，最低为 0。
const EFFECT_LOSE_SHIELD: String = "lose_shield"

## 效果键：从摸牌堆获得指定实体牌；载荷字段 uids 为实体牌 UID 数组。
const EFFECT_GAIN_DRAW_PILE_CARD: String = "gain_draw_pile_card"

## 效果键：更换目标武将；载荷字段 character_id 为新武将 ID。
const EFFECT_REPLACE_CHARACTER: String = "replace_character"

## 需要正数 amount 的效果键；其余效果键通过 payload 传参，amount 必须为 0。
const AMOUNT_EFFECT_KINDS: Array[String] = [
	EFFECT_DRAW,
	EFFECT_DISCARD,
	EFFECT_RECOVER,
	EFFECT_LOSE_HP,
	EFFECT_DAMAGE,
	EFFECT_GAIN_MAX_HP,
	EFFECT_LOSE_MAX_HP,
	EFFECT_GAIN_SHIELD,
	EFFECT_LOSE_SHIELD,
]

## 全部合法效果键；enqueue() 据此拒绝未知键，避免界面拼写错误被静默接受。
const ALL_EFFECT_KINDS: Array[String] = [
	EFFECT_DRAW,
	EFFECT_DISCARD,
	EFFECT_RECOVER,
	EFFECT_LOSE_HP,
	EFFECT_DAMAGE,
	EFFECT_GAIN_MAX_HP,
	EFFECT_LOSE_MAX_HP,
	EFFECT_GAIN_SHIELD,
	EFFECT_LOSE_SHIELD,
	EFFECT_GAIN_DRAW_PILE_CARD,
	EFFECT_REPLACE_CHARACTER,
]

## 效果载荷与权威日志共用的原因字符串；让时机窗口与战斗记录能识别本次变化来自离线调试表面。
const REASON: String = "developer_console"

## 待办队列上限；超过时拒绝新请求。取值 64 足够覆盖人工连点，同时防止脚本误循环把队列撑成无界内存。
const MAX_PENDING_EFFECTS: int = 64

## 绑定宿主控制器；服务不持有规则状态，一切读写都经宿主公开端口完成。
## 允许为空，便于单元测试只验证纯队列行为而不启动对局。
var _host: Object = null

## 下一条待办效果的稳定编号；从 1 递增，0 与负数始终表示无效记录，reset() 恢复默认值。
var _next_effect_id: int = 1

## 尚未执行的待办效果；数组头部是最早提交的一项，按提交顺序（先进先出）消费以保持点击顺序。
## 每项为 {effect_id, effect_kind, target_player_id, amount, match_id, payload}，全部是可序列化的基础类型。
var _effects: Array[Dictionary] = []


func _init(host_controller: Node = null) -> void:
	_host = host_controller


## 登记一条开发者效果；只接受纯数据载荷，登记时校验对局有效性与目标存在性。
## 返回 false 表示未受理（无对局 / 已终局 / 队列已满 / 效果键非法 / 目标不存在或不可用 / 数值非法）。
func enqueue(effect_kind: String, target_player_id: int, amount: int, match_id: String, payload: Dictionary = {}) -> bool:
	if not ALL_EFFECT_KINDS.has(effect_kind):
		return false
	if _effects.size() >= MAX_PENDING_EFFECTS:
		return false
	# 数值类效果必须有正数；载荷类效果必须不带数值，避免界面把两种语义混用后无法诊断。
	if AMOUNT_EFFECT_KINDS.has(effect_kind) != (amount > 0):
		return false
	if not _is_target_usable(target_player_id):
		return false
	# 当前待办稳定编号；resume_next() 与诊断日志据此定位单条效果。
	var effect_id: int = _next_effect_id
	_next_effect_id += 1
	_effects.append({
		"effect_id":effect_id,
		"effect_kind":effect_kind,
		"target_player_id":target_player_id,
		"amount":amount,
		"match_id":match_id,
		"payload":payload.duplicate(true),
	})
	return true


## 是否有待执行的开发者效果；供控制器管线活跃性判据与界面计数使用。
func has_pending() -> bool:
	return not _effects.is_empty()


## 待执行数量；供界面显示「已排队 N 项」，不暴露队列本体。
func pending_count() -> int:
	return _effects.size()


## 消费一条待办效果；返回 true 表示本轮消费了一条（调用方应 continue 重跑管线）。
## 对局已重开、已终局或目标已失效的条目在此丢弃，并写一条可诊断的开发者日志，绝不静默丢失。
func resume_next() -> bool:
	if _effects.is_empty():
		return false
	# 最早提交的一项；先进先出保证界面点击顺序就是结算顺序。
	var effect: Dictionary = _effects.pop_front() as Dictionary
	if _host == null or _host.state == null:
		return true
	if _host.state.game_over:
		_report({"effect_kind":str(effect.get("effect_kind", "")), "target_player_id":int(effect.get("target_player_id", -1)), "ok":false, "text":"开发者效果未执行：对局已结束。"})
		return true
	# 对局标识不一致说明这是上一局遗留的待办；直接作废，不能落到新一局的角色身上。
	if str(effect.get("match_id", "")) != str(_host.state.match_id):
		_report({"effect_kind":str(effect.get("effect_kind", "")), "target_player_id":int(effect.get("target_player_id", -1)), "ok":false, "text":"开发者效果已作废：对局已重新开始。"})
		return true
	# 目标座次在等待期间可能已经阵亡或离场；此时不执行，避免把效果落到无效角色上。
	var target_player_id: int = int(effect.get("target_player_id", -1))
	if not _is_target_usable(target_player_id):
		_report({"effect_kind":str(effect.get("effect_kind", "")), "target_player_id":target_player_id, "ok":false, "text":"开发者效果已作废：目标已不在场。"})
		return true
	_execute(effect, target_player_id)
	return true


## 丢弃全部待办；重新开局、放弃对局、节点离场共用。
func reset() -> void:
	_effects.clear()
	_next_effect_id = 1


## 清空队列并返回被丢弃的条数；用于界面在重开局后提示，不参与规则。
func drain_discarded() -> int:
	var discarded_count: int = _effects.size()
	reset()
	return discarded_count


## 返回全部待办的深拷贝；只供测试与诊断断言顺序，调用方修改不会影响真实队列。
func to_array() -> Array[Dictionary]:
	# 对外快照数组；逐项深拷贝，不与内部存储共享容器。
	var result: Array[Dictionary] = []
	for effect: Dictionary in _effects:
		result.append(effect.duplicate(true))
	return result


## 判断目标座次当前是否可用；只读宿主公开状态，不修改任何字段。
func _is_target_usable(target_player_id: int) -> bool:
	if _host == null or _host.state == null:
		return false
	# 目标玩家状态；死亡或已离场的角色不接受任何开发者效果。
	var target: PlayerState = _host.state.get_player(target_player_id)
	return target != null and target.alive and not target.out_of_game


## 按效果键分派到宿主公开规则端口；所有数值结算都在权威端完成，本服务只汇总可读结果。
func _execute(effect: Dictionary, target_player_id: int) -> void:
	# 效果键；已由 enqueue() 校验，这里不再重复拒绝，保证 match 覆盖全部合法值。
	var effect_kind: String = str(effect.get("effect_kind", ""))
	# 数值参数；载荷类效果恒为 0。
	var amount: int = int(effect.get("amount", 0))
	# 载荷字典；换将与摸牌堆取牌使用。
	var payload: Dictionary = effect.get("payload", {}) as Dictionary
	# 目标展示名；日志与状态行统一使用权威格式化结果。
	var target_text: String = _host.format_player_state_log_name(_host.state.get_player(target_player_id))
	match effect_kind:
		EFFECT_DRAW:
			# draw() 只登记规则序列，实体在后续时机窗口才移动，因此此处只能确认「已提交」。
			_host.draw(target_player_id, amount)
			_report(_result(effect_kind, target_player_id, true, "%s摸%d张牌（已提交）。" % [target_text, amount]))
		EFFECT_DISCARD:
			# 权威端只提供「调整到目标手牌数」的自选弃牌端口；换算成目标张数后由玩家自行选择。
			var discard_player: PlayerState = _host.state.get_player(target_player_id)
			var hand_size: int = discard_player.hand.size()
			# 期望弃置数；手牌不足时按实际手牌数上限收敛，并在结果中如实说明。
			var actual_discard: int = mini(amount, hand_size)
			if actual_discard <= 0:
				_report(_result(effect_kind, target_player_id, false, "%s没有手牌可弃置。" % target_text))
			else:
				var accepted: bool = _host.adjust_hand_size(target_player_id, hand_size - actual_discard)
				if not accepted:
					_report(_result(effect_kind, target_player_id, false, "%s弃牌请求未被受理。" % target_text))
				else:
					_report(_result(effect_kind, target_player_id, true, "%s等待选择弃置%d张牌（已提交）。" % [target_text, actual_discard]))
		EFFECT_RECOVER:
			# recover() 同样只登记规则序列；满体力时权威端会静默早退，因此先给出可读提示。
			var recover_target: PlayerState = _host.state.get_player(target_player_id)
			if recover_target.hp >= recover_target.max_hp:
				_report(_result(effect_kind, target_player_id, false, "%s体力已满，回复未生效。" % target_text))
			else:
				_host.recover(-1, target_player_id, amount, REASON)
				_report(_result(effect_kind, target_player_id, true, "%s回复%d点体力（已提交）。" % [target_text, amount]))
		EFFECT_LOSE_HP:
			# 失去体力返回实际扣减量；0 表示权威端拒绝了本次请求。
			var lost_hp: int = _host.lose_hp(-1, target_player_id, amount, REASON)
			if lost_hp > 0:
				_report(_result(effect_kind, target_player_id, true, "%s失去%d点体力。" % [target_text, lost_hp]))
			else:
				_report(_result(effect_kind, target_player_id, false, "%s失去体力未生效。" % target_text))
		EFFECT_DAMAGE:
			# damage() 依次派发多级时机窗口，扣血发生在窗口之后，因此只能确认「已提交」。
			_host.damage(-1, target_player_id, amount, "normal", "", false, false, {})
			_report(_result(effect_kind, target_player_id, true, "%s受到%d点无来源伤害（已提交）。" % [target_text, amount]))
		EFFECT_GAIN_MAX_HP:
			var gained_max_hp: int = _host.change_max_hp(target_player_id, amount, -1, REASON)
			if gained_max_hp > 0:
				_report(_result(effect_kind, target_player_id, true, "%s体力上限+%d。" % [target_text, gained_max_hp]))
			else:
				_report(_result(effect_kind, target_player_id, false, "%s体力上限未变化。" % target_text))
		EFFECT_LOSE_MAX_HP:
			# 权威端把减少量钳制为「至少保留 1 点上限」，返回值已反映真实变化量。
			var lost_max_hp: int = _host.change_max_hp(target_player_id, -amount, -1, REASON)
			if lost_max_hp < 0:
				_report(_result(effect_kind, target_player_id, true, "%s体力上限%d。" % [target_text, lost_max_hp]))
			else:
				_report(_result(effect_kind, target_player_id, false, "%s体力上限未变化。" % target_text))
		EFFECT_GAIN_SHIELD:
			var gained_shield: int = _host.shield(target_player_id, amount, -1, REASON)
			if gained_shield > 0:
				_report(_result(effect_kind, target_player_id, true, "%s获得%d点护盾。" % [target_text, gained_shield]))
			else:
				_report(_result(effect_kind, target_player_id, false, "%s获得护盾未生效。" % target_text))
		EFFECT_LOSE_SHIELD:
			# change_hujia() 的负向分支返回负数；取绝对值用于展示。
			var shield_delta: int = _host.change_hujia(target_player_id, -amount, -1, REASON)
			if shield_delta < 0:
				_report(_result(effect_kind, target_player_id, true, "%s失去%d点护盾。" % [target_text, absi(shield_delta)]))
			else:
				_report(_result(effect_kind, target_player_id, false, "%s失去护盾未生效。" % target_text))
		EFFECT_GAIN_DRAW_PILE_CARD:
			# 请求获得的实体牌 UID 列表；纯数据载荷，界面提交什么就尝试获得什么。
			var requested_uids: Array = payload.get("uids", []) as Array
			# 实际获得张数；逐张经权威移牌边界获得，返回空值表示该实体已不在摸牌堆中。
			var gained_count: int = 0
			for card_uid_variant: Variant in requested_uids:
				if _host.gain_draw_pile_card_by_uid(target_player_id, int(card_uid_variant)) != null:
					gained_count += 1
			if gained_count > 0:
				_report(_result(effect_kind, target_player_id, true, "%s从摸牌堆获得%d张牌。" % [target_text, gained_count]))
			else:
				_report(_result(effect_kind, target_player_id, false, "%s未获得任何牌。" % target_text))
		EFFECT_REPLACE_CHARACTER:
			var new_character_id: String = str(payload.get("character_id", ""))
			var replaced: bool = _host.replace_player_character_card(target_player_id, new_character_id, REASON)
			if replaced:
				_report(_result(effect_kind, target_player_id, true, "%s已更换武将。" % target_text))
			else:
				_report(_result(effect_kind, target_player_id, false, "%s更换武将失败。" % target_text))
		_:
			_report(_result(effect_kind, target_player_id, false, "未知的开发者效果键：%s。" % effect_kind))


## 组装一条可序列化的执行结果；界面状态行只读取本结构，不解析日志文本。
func _result(effect_kind: String, target_player_id: int, ok: bool, text: String) -> Dictionary:
	return {"effect_kind":effect_kind, "target_player_id":target_player_id, "ok":ok, "text":text}


## 把结果交回宿主；日志与信号由控制器发布，本服务不直接持有任何界面或信号。
func _report(result_data: Dictionary) -> void:
	if _host != null and _host.has_method("report_developer_effect_result"):
		_host.report_developer_effect_result(result_data)
