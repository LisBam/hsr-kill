class_name ArtworkLoader
extends RefCounted

## UI 插画安全加载器。卡牌与武将组件通过可选资源路径加载插画，空路径或资源缺失时统一返回 null。

## 卡牌插画配置字段名；数据文件填写 res:// 路径即可启用，运行时无需修改。
const CARD_ART_FIELD: String = "art_path"

## 武将插画配置字段名；与卡牌共用字段名称，便于数据扩展工具统一处理。
const CHARACTER_ART_FIELD: String = "art_path"


## 根据配置字典读取插画路径并安全加载 Texture2D；无效路径不会产生运行时类型转换错误。
static func load_from_definition(definition: Dictionary, field_name: String = "art_path") -> Texture2D:
	# 配置中的资源路径；空字符串表示该内容暂未配置插画。
	var artwork_path: String = str(definition.get(field_name, "")).strip_edges()
	if artwork_path.is_empty() or not ResourceLoader.exists(artwork_path):
		return null
	# 已加载的通用资源；只有 Texture2D 才能交给界面组件展示。
	var resource: Resource = load(artwork_path)
	if resource is Texture2D:
		return resource as Texture2D
	return null
