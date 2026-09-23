# 网络层

> 权威来源：`docs/网络通信.md`、`docs/架构说明.md` 外部适配层、`README.md` 联机部分。

---

## 一、三种模式与统一门面

`scripts/network/network_gateway.gd` 封装**离线 / 局域网（LAN）/ 远程（REMOTE）**三种模式：

- `OFFLINE`：本地回环。
- `LAN`：直接管理 `ENetMultiplayerPeer` 建房/加入。
- `REMOTE`：保留外部适配器信号。

`is_lan_client()` 用于统一隐藏非房主无法生效的局内权威控件。

**释放会话顺序（有实际约束）**：先以 `OfflineMultiplayerPeer` 脱离 `SceneMultiplayer`，**再**关闭旧 ENet peer，使同端口可**立即复用**。

---

## 二、房主权威模型（核心不变量）

- **房主运行权威 `MatchController`**，客户端**无状态**。
- 客户端**不能上传状态、取得密码明文或伪造其他玩家操作**。
- 客户端只上行 `PlayerAction`，下行只读的**观察者裁剪快照**与表现事件。
- 真人玩家 ID 按**大厅位置顺序**分配；客户端只绑定房主分配的本地玩家 ID 并渲染远端快照。

### 防伪与抗重放

| 机制 | 说明 |
|---|---|
| 包序号去重 | 按**每个发送端**维护封包序号 |
| actor 防伪 | 校验真实发送者，拒绝伪造 actor |
| 定向私有快照 | 按观察者单独下发 |
| 密码隐私 | 房主内存保存密码，公共快照只暴露 `has_password` |

---

## 三、断线重连（会话令牌）

- 房主开局时为每名远端真人签发 **32 字符会话令牌**。
- 掉线时按令牌**登记座位预约**。
- 客户端断线后以 **2 秒间隔自动重拨，最多 15 次**，并携令牌重新登记。
- 令牌命中即重绑 peer 映射，并以 `lan_match_peer_reconnected` 通知控制器**解除离线托管**。
- 令牌还能直接接管房主尚未察觉掉线的旧连接。
- **对局结束或重开新局时，预约整体失效。**
- 按远端地址计时的**重新加入冷却为 5000 毫秒**。

---

## 四、局内聊天

`NetworkGateway` 集中承载聊天，**不让 UI 直接处理规则外的网络细节**：

- `send_match_chat_message()`：离线模式本地回环；LAN 客户端上行 `match_chat` 封包；房主按**连接绑定的稳定玩家 ID 反查署名**后逐客户端中继并本地登记。
- 历史**上限 100 条**；在大厅开局与会话结束边界清空（**断线重连与同房重开保留**）。
- 统一经 `match_chat_received` 信号交给牌桌。
- 条目只含**序号、发送者稳定玩家 ID、署名与正文**（不含时间字段）。
- 正文单条最长 **200 字符**。
- **聊天不进入规则协议。**

---

## 五、大厅与身份映射

- 房间级「自选身份」开关经 `IdentityRules.supports_lobby_custom_identity()` 权威规范化，并随公共快照广播。
- 静态 `get_lobby_display_slot_count_for()` 统一提供大厅视觉位置数（车轮战固定 2 位、自选身份等于规则人数、其余 2~3 人 3 位）；**房主换位校验与大厅界面共用**。
- 自选身份开启时，开局映射按成员大厅位置经 `IdentityRules.get_lobby_slot_match_seats()` 直接绑定规则座次。
- 控制器把 `lan_custom_identity_enabled` 锁入 `match_options` 后按固定身份表分配，**不再洗牌或做 2v2 蓝红互换**。

---

## 六、相关测试

| 场景 | 说明 |
|---|---|
| `tests/lan_network_test.tscn` | 真实双进程 ENet 密码房、形象与位置同步、密码隐私、定向私有快照、actor 防伪 |
| `tests/lan_match_flow_test.tscn` | 房主权威控制器、客户端无状态选将、他人手牌与随机种子防泄漏 |
| `tests/lan_reconnect_test.tscn` | 断线后离线托管、令牌重连恢复原稳定玩家 ID |
| `tests/lan_custom_identity_test.tscn` | 自选身份位置表与 2v2 座次映射 |
| `tests/lan_kick_rejoin_test.tscn` | 踢出与重新加入冷却 |
| `tests/match_chat_test.tscn` | 聊天规范化、历史上限、气泡 |

> 部分用例会**派生第二个 Godot 进程**，需要允许本机 **UDP 回环**。

---

## Quality Check

- [ ] 客户端未上传状态；所有上行都经房主权威复核。
- [ ] 新增快照字段已评估裁剪，未泄露身份/手牌/随机种子/密码。
- [ ] 新增上行封包保留了 actor 防伪与序号去重。
- [ ] 会话释放仍遵循「先脱离 SceneMultiplayer，再关闭 peer」顺序。
- [ ] 新增聊天类数据未混入规则协议。
- [ ] 已跑对应 `lan_*` 测试；涉双进程用例时确认本机 UDP 回环可用。
- [ ] `docs/网络通信.md` 已同步。
