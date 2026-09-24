class_name PauseRegistry
extends RefCounted

## 多通道暂停注册表。选择、网络、动画延迟和对局终止使用独立 token，释放一个通道不会误恢复其他等待。

## 下一个暂停 token ID；从 1 递增，0 永远表示无效 token。
var _next_token_id: int = 1

## 以 token ID 为键的暂停记录；已解决记录保留到运行时重置，供回放和调试查询。
var _tokens: Dictionary = {}


## 创建一个新的暂停 token 并返回稳定 ID；owner_event_id 为 -1 时表示阻塞整个事件栈。
func acquire(channel: String, owner_event_id: int, reason: String) -> int:
	# 当前新 token 的稳定 ID；先保存后递增，确保第一条记录为 1。
	var token_id: int = _next_token_id
	_next_token_id += 1
	_tokens[token_id] = {
		"token_id": token_id,
		"channel": channel,
		"owner_event_id": owner_event_id,
		"reason": reason,
		"resolved": false,
		"resolution": "",
	}
	return token_id


## 解决指定暂停 token；重复解决或未知 token 返回 false，不会影响其他暂停通道。
func resolve(token_id: int, resolution: String = "completed") -> bool:
	if not _tokens.has(token_id):
		return false
	# 当前 token 记录副本；Dictionary 为引用类型，修改字段会直接写回注册表。
	var token: Dictionary = _tokens[token_id] as Dictionary
	if bool(token.get("resolved", false)):
		return false
	token["resolved"] = true
	token["resolution"] = resolution
	return true


## 返回指定事件栈是否受到未解决 token 阻塞；全局 token 或栈中任一事件拥有的 token 都会阻塞。
func has_active_for_stack(event_stack: Array[int]) -> bool:
	# 当前令牌记录；仅匹配指定事件所有者，其他通道保持原状态。
	for token_variant: Variant in _tokens.values():
		# 当前暂停记录；只读取未解决 token 的所有者归属。
		var token: Dictionary = token_variant as Dictionary
		if bool(token.get("resolved", false)):
			continue
		# token 所属事件；-1 表示全局，其他值只阻塞包含该事件的当前调用链。
		var owner_event_id: int = int(token.get("owner_event_id", -1))
		if owner_event_id < 0 or event_stack.has(owner_event_id):
			return true
	return false


## 返回指定事件是否仍有未解决 token；用于事件摘要和选择响应权威校验。
func has_active_for_event(event_id: int) -> bool:
	# 当前令牌记录；仅匹配指定事件所有者，其他通道保持原状态。
	for token_variant: Variant in _tokens.values():
		# 当前暂停记录；事件 ID 和解决状态同时匹配才视为活跃。
		var token: Dictionary = token_variant as Dictionary
		if int(token.get("owner_event_id", -2)) == event_id and not bool(token.get("resolved", false)):
			return true
	return false


## 返回是否存在任意未解决暂停；UI、断线处理和调试器可用该别名快速判断全局是否仍在等待。
func has_active() -> bool:
	return not get_active_tokens().is_empty()


## 仅释放已终止事件拥有的暂停；其他事件及全局通道不受影响，返回实际释放数量。
func resolve_owner(owner_event_id: int, resolution: String) -> int:
	# 本次释放数量；重复清理返回0，保证取消与终局收尾幂等。
	var resolved_count: int = 0
	# 当前令牌记录；仅匹配指定事件所有者，其他通道保持原状态。
	for token_variant: Variant in _tokens.values():
		# 当前所有权记录；只改变同一事件仍活跃的令牌。
		var token: Dictionary = token_variant as Dictionary
		if int(token.get("owner_event_id", -1)) == owner_event_id and not bool(token.get("resolved", false)):
			token["resolved"] = true
			token["resolution"] = resolution
			resolved_count += 1
	return resolved_count


## 解决全部未完成 token；对局结束和运行时重置使用稳定原因，旧请求随后无法恢复事件。
func resolve_all(resolution: String) -> void:
	# 当前令牌记录；仅匹配指定事件所有者，其他通道保持原状态。
	for token_variant: Variant in _tokens.values():
		# 当前暂停记录；已解决 token 保留原始结果，不覆盖其历史语义。
		var token: Dictionary = token_variant as Dictionary
		if not bool(token.get("resolved", false)):
			token["resolved"] = true
			token["resolution"] = resolution


## 返回当前未解决 token 的深拷贝；外部只能观察，不能直接释放或篡改注册表。
func get_active_tokens() -> Array[Dictionary]:
	# 活跃 token 快照；按 token ID 排序，保证固定输入得到稳定回放顺序。
	var result: Array[Dictionary] = []
	# 当前令牌记录；仅匹配指定事件所有者，其他通道保持原状态。
	for token_variant: Variant in _tokens.values():
		# 当前 token；只导出未解决项。
		var token: Dictionary = token_variant as Dictionary
		if not bool(token.get("resolved", false)):
			result.append(token.duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left.get("token_id", 0)) < int(right.get("token_id", 0)))
	return result


## 返回全部 token 历史深拷贝；回放系统可据此验证多个暂停通道的获取和释放顺序。
func get_history() -> Array[Dictionary]:
	# 全部 token 快照；包含已解决项并按稳定 ID 排序。
	var result: Array[Dictionary] = []
	# 当前令牌记录；仅匹配指定事件所有者，其他通道保持原状态。
	for token_variant: Variant in _tokens.values():
		result.append((token_variant as Dictionary).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left.get("token_id", 0)) < int(right.get("token_id", 0)))
	return result


## 清空所有 token 并重置序号；只能在创建新对局且旧事件全部失效时调用。
## 身份约束：重置清空记录但保留分配序号单调递增，不能重新使用旧回调可能携带的token ID。
func reset() -> void:
	# 序号跨重开保持单调；旧网络/表现回调不能释放新局恰好同号的暂停。
	_tokens.clear()
