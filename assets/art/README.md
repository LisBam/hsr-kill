# 插画资源目录

该目录用于集中保存后续加入的卡牌与武将插画。推荐结构：

```text
assets/art/
├── cards/          # 卡牌插画
└── characters/     # 武将头像或立绘
```

建议卡牌插画使用接近 3:2 的横向主体构图，武将插画使用竖向半身或全身构图，主体尽量位于中央；武将牌左侧会覆盖势力与竖排名称，右侧会覆盖体力圆点，中下部可能覆盖最多 5 条装备信息。PNG、WebP、JPG 和可被 Godot 导入为 `Texture2D` 的 SVG 均可使用。

添加资源后，在对应数据定义中填写项目资源路径：

```json
{"id":"sha", "art_path":"res://assets/art/cards/sha.webp"}
```

```json
{"id":"trailblazer", "art_path":"res://assets/art/characters/trailblazer.webp"}
```

`art_path` 为空、缺失或指向无效资源时，界面会继续显示统一占位图，不影响开局、规则结算、网络快照或存档结构。
