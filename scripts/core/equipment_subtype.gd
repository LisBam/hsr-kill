class_name EquipmentSubtype
extends RefCounted

## 装备牌子类别规则表。装备筛选、牌面文本与装备入场效果通过稳定子类别和槽位映射协作，避免各模块重复硬编码字符串。

## 武器子类别；对应武器装备槽，提供攻击范围及武器专属效果。
const WEAPON: String = "weapon"

## 防具子类别；对应防具装备槽，通常用于修正受到的伤害或来牌效果。
const ARMOR: String = "armor"

## 进攻坐骑子类别；对应进攻坐骑装备槽，默认提供距离-1修正。
const OFFENSIVE_MOUNT: String = "offensive_mount"

## 防御坐骑子类别；对应防御坐骑装备槽，默认提供距离+1修正。
const DEFENSIVE_MOUNT: String = "defensive_mount"

## 宝物子类别；对应宝物装备槽，用于木牛流马等独立持续装备效果。
const TREASURE: String = "treasure"

## 全部合法装备子类别；顺序用于稳定遍历和从不同类别中随机选择装备。
const ALL: Array[String] = [WEAPON, ARMOR, OFFENSIVE_MOUNT, DEFENSIVE_MOUNT, TREASURE]

## 装备子类别到唯一装备槽的映射；当前五种子类别与槽位一一对应。
const SLOT_BY_SUBTYPE: Dictionary = {
	WEAPON: WEAPON,
	ARMOR: ARMOR,
	OFFENSIVE_MOUNT: OFFENSIVE_MOUNT,
	DEFENSIVE_MOUNT: DEFENSIVE_MOUNT,
	TREASURE: TREASURE,
}


## 判断给定稳定值是否为项目支持的装备子类别；未知值不能参与按子类别抽取或直接装入装备区。
static func is_valid(subtype: String) -> bool:
	return ALL.has(subtype)


## 返回装备子类别对应的装备槽；未知子类别返回空字符串，调用方应拒绝继续安装。
static func get_slot(subtype: String) -> String:
	return str(SLOT_BY_SUBTYPE.get(subtype, ""))
