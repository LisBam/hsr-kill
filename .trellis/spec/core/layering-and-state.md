# 分层与状态权威

> 权威来源：`docs/架构说明.md`「总体原则」「模块职责」「数据结构」「状态可见性」「设计边界」。

---

## 一、单向依赖（架构宪法）

项目采用**单向依赖的五层结构**，任何反向依赖都是 bug：

| 层 | 代表 | 职责 |
|---|---|---|
| 静态数据层 | `game_data/*`、`data/decks.json` | 声明内容 |
| 状态与规则层 | `scripts/data/*`、`scripts/core/match_controller.gd` | 权威结算 |
| 事件运行时 | `scripts/core/event_scheduler.gd`、`trigger_manager.gd` | 嵌套、暂停与恢复 |
| 动作协议层 | `scripts/data/player_action.gd`、`choice_request.gd`、`choice_response.gd` | 统一外部输入 |
| AI / 网络适配层 | `scripts/ai/*`、`scripts/network/network_gateway.gd` | 提供不同操作来源 |
| UI 层 | `scripts/ui/*`、`scenes/*` | 只渲染快照并提交动作 |

**铁律**：UI、AI、网络模块**都不得直接改写 `GameState`**。离线玩家、LAN 客户端与内置 AI 统一通过 `PlayerAction` 下发操作；LAN 由房主权威结算，并按观察者裁剪私有快照。

---

## 二、状态结构（改动前务必确认可见性）

| 类型 | 文件 | 关键点 |
|---|---|---|
| `CardInstance` | `scripts/data/card_instance.gd` | 实体牌 UID、配置 ID、花色、点数、区域、所有者；手牌临时牌名与 `hand_mark_tags` **互相独立** |
| `PlayerState` | `scripts/data/player_state.gd` | 身份、武将、体力、护盾、手牌、装备区、判定区、连环与翻面、公开标记、角标文本、木牛「粮」等 |
| `GameState` | `scripts/data/game_state.gd` | 玩家数组、摸牌堆/弃牌堆/处理区、当前阶段、回合数、动作序号、胜负、根事件与各类历史 |
| `PlayerAction` | `scripts/data/player_action.gd` | 统一操作结构；装备主动动作名由**卡牌文件动态声明**，控制器不维护白名单 |
| `ChoiceRequest` / `ChoiceResponse` | `scripts/data/choice_request.gd`、`choice_response.gd` | 统一 `use/respond/card/target/target_control/card_target/button/control/discard/arrange` 选择协议；响应只含可序列化 ID |
| `VirtualCard` | `scripts/data/virtual_card.gd` | 逻辑牌与实体材料 UID 的分离描述 |
| `CardMoveEvent` / `CardPresentationEvent` | `scripts/core/card_move_event.gd` 等 | 移牌与表现事件记录 |

### 必须遵守的状态约定

- `PlayerState.face_down` 明确区分正面与背面；**横置只由 `PlayerStateOverlay` 绘制，不写节点旋转/缩放**。
- 护盾是**公开非负整数**，初始为 0，**不并入体力或体力上限**。
- `public_marks` 只保存可序列化字段，由 `PlayerMarkService` 修改；`source_player_id` 是**死亡清理的唯一来源归属**，跨角色标记不得省略。
- `acquired_skills` 保存局内获得技能及其次数与来源；`hand_limit_bonus` 可累加，最终手牌上限为 `max(hp + hand_limit_bonus, 0)`。
- 限定技运行时对象仍由控制器持有；广播前只向快照补充公开的 `used_limited_skill_ids` 稳定 ID 数组——**UI 与 AI 不得取得技能对象或用历史猜测复原额度**。
- 技能实例表同样只以**派生字段**进入快照：广播前补充 `installed_skill_ids`（当前实际安装的技能 ID），它是「某个技能现在是否还在这名角色身上」的唯一公开依据——**不要为“已失去的技能”另建名单或标记字段**。失去技能就是卸载实例，界面按该字段裁剪即可自动同时满足“失去后立即消失”和“新获得后立即显示”。
- 失去技能的通用入口是 `remove_skill()` / `remove_all_skills()`：卸载实例、清理获得与临时记录、清理轮回公开状态，**不写任何持久名单**，因此装配路径不得按技能 ID 拦截。若需要“失去后的状态不被读档抹掉”，存档记录的是**当前实际持有集合**（`installed_skill_ids`），读档只装配集合内的技能；缺该字段的旧存档按武将完整装配。
- 手牌临时牌名与 `hand_mark_tags` 只能由**统一移牌边界**清除，技能**不得直接改写牌区数组**。

### 濒死不变量

「存活角色体力不大于 0 时必须处于濒死或进入死亡确认」是权威不变量。`dyingBefore/dyingBegin` 的取消或中立化**只有**在处理器已恢复正体力、确认死亡或令角色离场时才能终止；单独设置事件标志不行。

### 死亡与胜负

- `IdentityRules.evaluate_winner()` **只把 `alive=false` 视为死亡**。
- `out_of_game=true`（离场）的角色仍计入身份局、斗地主与 2v2 阵营生存，只是从行动、距离、目标和响应集合排除。
- `GameState.game_over` 一旦成立，即成为规则操作与 `CardEffectResolver` 的统一终止条件。

---

## 三、快照可见性（信息泄漏防线）

- 快照按 `to_dict(viewer_id, ...)` 为每个观察者**单独裁剪**：非响应者的私有选择候选必须裁掉。
- 机缘 `choosing` 阶段只保留该观察者自己的三张候选，并移除已选卡正文；全部收齐进入 `revealing` 后才公开 `revealed_votes` 与 `winner_card_id`。
- 选将期间：只有本人收到 `local_identity`、候选、锁定/可换 ID 与剩余换将卡；**不泄漏其他玩家身份或张数**。
- 私有展示牌只能放入该响应者的 `context.display_candidates`，**不得写回公共快照、实体 `shown` 或 `known_to`**。
- 公开序列化尽量复用只读数组（在机缘历史长度或首尾哨兵变化时才生成新数组）；**已经发出的旧快照不会被原地改写**。

> 新增任何"可见但不应被所有人看到"的字段时，必须同时确认裁剪逻辑，并补网络侧测试。

---

## 四、服务组件的单一职责（新增功能的正确落点）

`MatchController` 负责**编排**，而不是承载所有逻辑。既有先例：

| 组件 | 职责（不做什么） |
|---|---|
| `PlayerMarkService` | 公开标记规范化、数量限制、全场唯一转移、死亡清理；不读 UI/AI/具体技能 ID |
| `PlayerEffectService` | 角色持续效果实例托管（创建/复用、按角色持久状态重建、移除与整局清空）；**不读具体技能或效果 ID、不决定何时施加效果** |
| `ReincarnationSkillService` | 轮回数、轮回节、永劫与次数；**不执行具体技能效果、不持有技能实例** |
| `PlayerZoneAbolitionService` | 装备栏与判定区废除；**不读卡牌定义、技能 ID、AI 或界面节点** |
| `GameplayPauseService` | 对局级令牌暂停；首个申请者暂停，最后一个释放者恢复 |
| `GameFlowPacer` | 按业务键管理可取消计时器；**不读 `GameState`、不决定阶段** |
| `CardMovementService` | 唯一移牌边界与牌面知识、移动历史、弃牌顺序索引 |
| `MatchReplayRecorder` / `Store` / `PlaybackDriver` | 回放录制 / 持久化 / 重演；**不读 `GameState`** |
| `CharacterSelectionService` | 纯数据选将状态机；不加载界面、不注册 AI、不修改牌区 |
| `StallWatchdogService` | 停滞检测与软/硬两级修复 |

**新增玩法逻辑时先问：这是不是一个可以独立成组件的能力？** 若是，新建服务并让 `MatchController` 只暴露转发端口。

---

## 五、唯一移牌边界（高频踩坑点）

`CardMovementService` 统一维护实体牌区域与牌面知识，并：

- 追加 `CardMoveEvent` 历史
- 在权威移动完成后发出**唯一** `card_moved` 增量
- 同一实体在同一区域且持有者未变时**拒绝重复移动**
- 按「全局回合号 + 行动角色」维护进入弃牌堆的 UID 顺序索引

**规则调用点不得重复发信号**；只有进入手牌和弃牌堆的有效增量才转为客户端表现。

---

## 六、只读查询边界

- `RuleQuery` 是**只读合法性门面**：不创建选择、不移动牌、不消耗次数。
- `RuleModifierPipeline` 是独立于触发器的**纯查询修正链**，供 card/target enabled、usable、respondable、in-range 查询使用。
- `MatchController.get_card_use_preview()` 是 UI 使用的只读查询边界，返回可提交性、合法候选、规范化目标、目标模式、修正后的目标数与说明文本——**不返回 `GameState`/`PlayerState`/`CardInstance` 对象引用**。
- `MatchController.get_match_start_validation_error()` 是开局前**不修改任何状态**的只读校验边界。
- **用牌禁令（`validate_card_action_permission`）属于这条纯查询链**：内容层声明“这张实体牌此刻能不能使用/打出”（返回空串即允许），核心层只在**三个必经之路**咨询——①`CardRuleService.validate_use()`（早于目标校验）②`CardRuleService.list_legal_targets()`（目标枚举：整张牌被否决时直接返回空数组，否则界面会先给出可点击的目标、选完才发现无法确认，表现为“不可使用却仍能指定目标”）③响应窗口候选构造（被禁的手牌不进任何响应窗口）。区域限制（例如“手牌中的”）由内容层自己按 `card.zone` 判断，**核心层不维护牌名或区域白名单**；技能提供者缺失（脱离对局的纯规则构造）时视为没有任何禁令。虚拟牌路径（`list_legal_virtual_targets()`）**刻意不咨询**该钩子：禁令语义是“手牌中的牌不能使用”，虚拟牌是否受限由技能自己的钩子按区域判断，核心层不维护区域白名单。

---

## 七、可插拔组件的生命周期：`configure()` 是唯一装配入口

`OpportunitySystem`、`AhhaMomentSystem` 一类可插拔组件都遵守同一套契约：

- 装配只有一个入口：`configure(controller, state, rng, ...)`；它内部**先调用自身 `shutdown()`** 再重新绑定，因此重复调用是幂等的、安全的。
- `shutdown()` 会把内部开关置回关闭（例如 `_enabled = false`）并解绑旧对局状态，是**拆解**动作。
- 因此**任何“拆掉旧运行时再重建对局”的路径都必须把全部组件重新 `configure()` 一遍**，恢复存档（`resume_conquest_match()`）与新开局（`start_match()`）都算。`_teardown_previous_match_runtime()` 会对组件调用 `shutdown()`，漏配的组件在**本局剩余全程**静默失效，而且**不会有任何报错**——典型症状是“新开局一切正常、点了『继续上次游戏』之后某项全局机制整局都不触发”。


## 八、记账时刻与结构性重置

涉及「每回合/每阶段限一次」这类**额度记账**的规则，出错几乎从不是规则算错，而是**记账时刻、记账来源、记账入口**这三者选错。三条硬约定：

- **会在效果执行期间被外部改写的状态，必须在效果执行前捕获。** 例：轮回节的阶段额度若在效果跑完后才读实时 `section_index`，而效果内部的 `damage()` 会经【征服】同步推进轮回节，就会把**推进后的节**登记为「本次发动」——真正发动过的那一节从未登记（可无限重复），被推进到的那一节反而被误封锁。做法：`begin_activation` 捕获归属节（哨兵 `-1` 表示无待完成发动，不与合法的 `0`/① 混淆），`complete_activation` 只消费捕获值，并在**所有分支**上复位（否则陈旧归属会被下一次无关的 `complete` 误登记）。捕获必须早于任何会派发时机的调用（如「节开始时」）。
- **「每个入口都要记得调用」必须改造成「结构上不可能不调用」。** 清空额度若只挂在若干阶段入口上，漏掉任何一条（尤其是**读档恢复**分支）就会把上一阶段的额度泄漏到新阶段。做法：收敛到控制器**唯一重置入口**（如 `_note_play_phase_entered(player_id)`，覆盖普通出牌阶段、主要阶段转换、排队额外阶段、独立额外阶段、读档恢复全部路径），再加上一个**单调递增的出牌阶段实例号**——读取额度时实例号不一致即按空额度处理并惰性清空，形成第二道防线。新增防线要能覆盖**未来还没写出来的入口**。
- **「是不是我的阶段」不能用公开阶段字符串判断。** 嵌套选择会临时把公开阶段写成 `choice`，裸比较会让整条记账被**静默跳过**（等同于免费多发动一次）。应经控制器端口读取**选择窗口背后的真实规则阶段**（`_get_effective_rule_phase()` 一类），并保留无端口时的回退以保证无头单测语义不变。

> 新增此类状态字段时，哨兵值必须与合法取值不相交（`-1` vs 非负索引、`0` = 未设置 vs `>= 1` = 真实实例号），且所有读取都写成 `get(key, 哨兵)`，这样旧存档缺字段时自动落到「不做校验」的旧语义，无需提升存档版本。


---

## 常见错误

| 错误 | 后果 |
|---|---|
| UI/AI/网络直接改 `PlayerState.hp` / 牌区数组 | 破坏单一权威，状态与快照不一致 |
| 新增私有信息却没加快照裁剪 | 泄露隐藏身份/手牌，破坏防作弊 |
| 把玩法逻辑继续塞进 `MatchController` | 胖控制器，违反组件模式 |
| 绕过 `CardMovementService` 直接搬牌 | `card_moved` 增量缺失，表现层漏牌/重牌 |
| 把"存活"与"在场"混为一谈 | 离场角色被错误判死或错误计入胜负 |
| 技能直接改写牌区数组清除临时牌名 | 破坏 UID/花色/区域历史，回放与网络异常 |
| 把“不能用/不能打某张牌”写进界面或技能自己的牌名白名单 | 界面拦住了但 AI、联机校验、响应窗口漏过；应走 `validate_card_action_permission()` 纯查询钩子，由核心层在三个消费点统一咨询 |
| 用牌禁令只拦 `validate_use()` 与响应候选、不拦 `list_legal_targets()` | 牌在规则上不可使用，界面却仍高亮并允许点击目标；玩家能选目标、无法确认，需逐个消费点核对 |
| 恢复存档/重开局后只重建 `GameState`，忘记重新 `configure()` 可插拔组件 | `shutdown()` 已把组件关掉且不报错，该机制在整局里静默失效（换局开局正常，只有恢复路径出问题），极难从症状反推 |

| 核心层为某条规则维护牌名/区域白名单 | 内容层无法独立扩展，新增一张牌就要改核心；内容判定应由内容层声明事实 |
| 在效果执行**之后**读取「会被该效果改写的状态」来记账 | 登记到被改写后的值：真正生效的那一项漏登记（可重复触发），被推进到的那一项被误封锁 |
| 「限一次」额度的清空散落在多个阶段入口，依赖每个入口自觉调用 | 漏掉任一条（尤其读档恢复）即跨阶段泄漏；应收敛到唯一重置入口 + 单调阶段实例号做惰性失效 |
| 用公开的 `current_phase == "play"` 判断「是不是我的出牌阶段」 | 嵌套选择期间该字段临时为 `choice`，整条记账被静默跳过，等同免费多发动一次 |
| 新增状态字段但不给哨兵默认值 / 直接读 `state[key]` | 旧存档缺字段时崩溃或误判；应写成 `get(key, 哨兵)`，并保证哨兵与合法取值不相交 |
