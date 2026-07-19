class_name AndroidDisplayStability
extends Node

## Android显示稳定组件。组件只负责移动端帧率与垂直同步策略，不读取牌桌、菜单或规则状态。

## Android目标帧率；默认60帧用于避免高刷新率设备在60/90/120Hz之间反复切换，运行时通常无需动态修改。
@export_range(30, 120, 1) var target_fps: int = 60

## 是否强制开启垂直同步；默认开启以避免高通Adreno设备出现撕裂、交换链节奏抖动或整屏闪烁，运行时通常无需动态修改。
@export var force_vsync: bool = true

## 是否只在Android平台应用显示策略；默认开启，保证桌面端继续使用原有窗口和帧率设置，运行时通常无需动态修改。
@export var android_only: bool = true


## 场景进入树后延迟应用显示策略；等待Android窗口与图形交换链完成创建后再写入帧率状态。
func _ready() -> void:
	call_deferred("_apply_display_stability")


## 应用从后台恢复时重新写入显示策略；部分Android系统会在切换前后台后重置刷新率或交换链节奏。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		call_deferred("_apply_display_stability")


## 锁定Android最大帧率并启用垂直同步；重复调用保持幂等，不创建每帧计时器或持续轮询。
func _apply_display_stability() -> void:
	if android_only and OS.get_name() != "Android":
		return
	Engine.max_fps = target_fps
	if force_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
