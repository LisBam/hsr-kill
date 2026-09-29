# 内容命名与目录结构

> 权威来源：`docs/内容制作指南.md`「通用制作规范 → 命名规范」「GameDatabase 完整源码索引」。

---

## 一、目录职责表

| 内容 | 存放目录 | 基类 |
|---|---|---|
| 卡牌 | `game_data/cards` | `CardDefinition` |
| 技能 | `game_data/skills` | `SkillDefinition` |
| 武将 | `game_data/characters` | `CharacterDefinition` |
| 武将插画 | `game_data/characters/image` | 与武将源码**同名**的 PNG 或 JPG |
| 势力 | `game_data/factions.json` | JSON 展示数据 |
| 实体牌堆 | `data/decks.json` | JSON 实体牌数据 |

三个基类分别位于 `game_data/card_definition.gd`、`game_data/skill_definition.gd`、`game_data/character_definition.gd`。

补充基类：`game_data/sequential_virtual_skill_definition.gd`（`SequentialVirtualSkillDefinition`，需要连续使用多张无材料虚拟牌的技能）、`game_data/skill_player.gd`（`SkillPlayer`，技能的 `who/source` 角色操作对象）。

---

## 二、命名规范（强制）

文件名与稳定 `id` 统一使用对应**中文名称的完整小写拼音**：

- 不标声调
- 不使用中文、英文翻译、大写字母、空格或横线
- 仅允许字符 `a`~`z`；命名冲突时允许末尾追加「下划线 + 递增数字」
- **同名角色的不同命途版本**使用「下划线 + 命途拼音」区分（既有先例：`xing` / `xing_cunhu` / `xing_huanyv`，`qiong` / `qiong_cunhu` / `qiong_huanyv`）。这类后缀表达的是**内容语义**而不是冲突序号，因此不适用 `_2` 递增规则；**纯重名**（内容语义相同）仍必须使用 `_2`、`_3`。

示例：

| 内容 | 文件名 / `id` |
|---|---|
| 武将【布洛妮娅】 | `buluoniya` |
| 技能【行军】 | `xingjun` |
| 卡牌【杀】 | `sha` |
| 卡牌【顺手牵羊】 | `shunshouqianyang.gd` |
| 同名冲突第 2 个 | `shunshouqianyang_2.gd`，依此类推 `_3`、`_4` |

### 四条硬约束

1. 文件名使用完整小写拼音，仅允许 `a`~`z` 与冲突序号。
2. 文件内部的稳定 `id` **非空且全项目唯一**，与文件名采用相同拼音主体和冲突序号。
3. 文件名用于开发者定位源码；稳定 `id` 用于**规则、牌堆、网络、回放与存档**。重命名文件时**不得随意修改已经投入使用的稳定 ID**。
4. 所有变量必须有独占注释（见 [`../project/collaboration-rules.md`](../project/collaboration-rules.md)）。

> 命名冲突处理原则：保留第一个内容的原始拼音名称，后续同名内容从 `_2` 起递增。

---

## 三、GameDatabase 扫描与校验

`GameDatabase` 是自动加载的静态内容仓库，`_ready()` 时调用 `reload_all()`：清空全部索引，按**技能 → 卡牌 → 武将 → 牌堆 → 势力**顺序重载并校验。

### 目录扫描会检查

- 脚本可载入、继承类型正确
- `id` 非空且不重复
- 武将技能引用、势力引用、牌堆卡牌引用有效

任一错误写入 `GameDatabase.validation_errors`，**非空时 `start_match()` 拒绝开局**。

### 导出环境的路径规范化

编辑器目录中是 `.gd`；导出 PCK 后可能暴露 `.gd.remap`、`.gdc`、`.gde`。数据库会把这些规范化为原始 `.gd` 资源路径加载，因此 Android 导出后仍能登记完整卡牌、技能与武将。**新增内容不需要为此做特殊处理。**

### 查询返回值的拷贝语义

- `get_card()` / `get_character()` / `get_skill()` / `get_deck_cards()` 返回**深拷贝**或静态定义。
- **持续装备和运行时技能必须使用创建函数**（`create_card_runtime()` / `create_skill()`）获得独立实例。
- **禁止把数据库定义对象当作对局状态容器**。
- 缓存只保存不可变字符串，**不保存技能节点、对局快照或运行时对象**。

### 插画自动发现

- 卡牌可直接提供 `art_path`（推荐 `res://assets/art/cards/<卡牌ID>.webp`）。
- 武将定义**不维护** `art_path`；`GameDatabase._load_characters()` 按武将源码文件完整基础名，在 `res://game_data/characters/image/` 按 **PNG → JPG** 顺序自动发现同名资源。
- 同名 PNG 与 JPG 并存时选 PNG；两者都缺失**不产生校验错误**，只显示占位图。

---

## 常见错误

| 错误 | 说明 |
|---|---|
| 用中文名或英文翻译做文件名 | 扫描会记录非法命名错误 |
| 改了文件名却保留旧 `id`（或反之） | 源码名与逻辑标识无法对应；且稳定 ID 一旦投入使用不可随意改 |
| 冲突时自行起新名字而不加 `_2` 序号 | 破坏「拼音主体一致」约定 |
| 直接修改 `GameDatabase.cards` 等索引字典 | 内容代码必须走查询函数拿深拷贝 |
| 把 `get_card_definition()` 的静态定义绑成运行时实例 | 静态定义绑定运行时会导致状态污染，运行时必须用 `create_card_runtime()` |
