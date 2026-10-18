class_name PlayerState
extends RefCounted

signal changed

const MAX_HEALTH: int = 100

var health: int = MAX_HEALTH:
	set(value):
		health = clampi(value, 0, MAX_HEALTH)
		changed.emit()

var money: int = 0:
	set(value):
		money = maxi(value, 0)
		changed.emit()
