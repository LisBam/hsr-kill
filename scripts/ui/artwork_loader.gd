class_name ArtworkLoader
extends RefCounted

## UI 插画安全加载器。卡牌与武将组件通过可选资源路径加载插画，空路径或资源缺失时统一返回 null。

## 卡牌插画配置字段名；数据文件填写 res:// 路径即可启用，运行时无需修改。
const CARD_ART_FIELD: String = "art_path"

## 武将插画配置字段名；与卡牌共用字段名称，便于数据扩展工具统一处理。
const CHARACTER_ART_FIELD: String = "art_path"

## 图鉴共享的最大后台插画任务数；2 个任务限制解码竞争与快速切页时的临时内存，运行时无需修改。
const MAX_BACKGROUND_REQUESTS: int = 2

## 无头渲染器的后台纹理并发上限；1个任务避免dummy纹理存储与场景纹理装配交错，图形客户端仍使用正常并发。
const MAX_HEADLESS_BACKGROUND_REQUESTS: int = 1

## 后台完成纹理的短期强引用上限；8 张足以覆盖单帧创建，正式牌面随后自行持有纹理。
const MAX_PREPARED_TEXTURES: int = 8

## 已提交但尚未领取的插画路径；两个图鉴共享任务，避免同一路径重复请求或提前阻塞领取。
static var _background_paths: Dictionary = {}

## 已完成的短期纹理缓存；按插入顺序淘汰，防止滚动浏览让加载器无限持有原画。
static var _prepared_textures: Dictionary = {}


## 非阻塞准备图鉴插画；返回 true 后正式组件可沿用同步接口直接取得已缓存纹理。
## 空路径、缺失资源和错误类型沿用 null 降级；只有确认完成的后台任务才允许调用 threaded_get。
static func prepare_from_definition(definition: Dictionary) -> bool:
	# 需要准备的插画路径；机缘等无插画条目无需启动后台任务。
	var artwork_path: String = str(definition.get(CHARACTER_ART_FIELD, "")).strip_edges()
	# 后台路径快照；领取完成任务时会修改字典，遍历快照避免迭代失效。
	for pending_path: String in _background_paths.keys():
		# 当前任务状态；轮询不会等待解码线程，完成后领取释放引擎任务引用。
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(pending_path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		# 完成或失败的纹理；失败时缓存 null，避免同一坏资源每帧重复发起请求。
		var resource: Resource = ResourceLoader.load_threaded_get(pending_path) if status == ResourceLoader.THREAD_LOAD_LOADED else null
		_background_paths.erase(pending_path)
		_cache_prepared(pending_path, resource as Texture2D)
	# 无头环境不让正式场景的梯度纹理装配与后台纹理创建同时进行；仍以轮询等待，不阻塞主线程。
	var headless: bool = DisplayServer.get_name() == "headless"
	if headless and not _background_paths.is_empty():
		return false
	if artwork_path.is_empty() or _prepared_textures.has(artwork_path):
		return true
	if _background_paths.has(artwork_path):
		return false
	if ResourceLoader.has_cached(artwork_path) or not ResourceLoader.exists(artwork_path):
		return true
	if _background_paths.size() >= (MAX_HEADLESS_BACKGROUND_REQUESTS if headless else MAX_BACKGROUND_REQUESTS):
		return false
	if ResourceLoader.load_threaded_request(artwork_path, "Texture2D") != OK:
		_cache_prepared(artwork_path, null)
		return true
	_background_paths[artwork_path] = true
	return false


## 统一保存完成或失败结果；所有写入都执行容量限制，异常素材也不会突破短期缓存上限。
static func _cache_prepared(artwork_path: String, texture: Texture2D) -> void:
	_prepared_textures[artwork_path] = texture
	while _prepared_textures.size() > MAX_PREPARED_TEXTURES:
		_prepared_textures.erase(_prepared_textures.keys()[0])


## 根据配置字典读取插画路径并安全加载 Texture2D；无效路径不会产生运行时类型转换错误。
static func load_from_definition(definition: Dictionary, field_name: String = "art_path") -> Texture2D:
	# 配置中的资源路径；空字符串表示该内容暂未配置插画。
	var artwork_path: String = str(definition.get(field_name, "")).strip_edges()
	if _prepared_textures.has(artwork_path):
		return _prepared_textures[artwork_path] as Texture2D
	if artwork_path.is_empty() or not ResourceLoader.exists(artwork_path):
		return null
	# 已加载的通用资源；只有 Texture2D 才能交给界面组件展示。
	var resource: Resource = load(artwork_path)
	if resource is Texture2D:
		return resource as Texture2D
	return null
