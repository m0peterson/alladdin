class_name DefeatRecovery
extends Node

signal recovered(money_lost: int)

var player: Node2D
var state: PlayerState
var spawn_position: Vector2 = Vector2(136, 368)
var bandit: BazaarBandit
var _pending: bool = false


# Attach under the pausable world. Inventory is deliberately not a dependency.
func configure(actor: Node2D, player_state: PlayerState, start: Vector2 = Vector2(136, 368), enemy: BazaarBandit = null) -> void:
	if is_instance_valid(player) and player.defeated.is_connected(_on_defeated):
		player.defeated.disconnect(_on_defeated)
	player = actor
	state = player_state
	spawn_position = start
	bandit = enemy
	player.defeated.connect(_on_defeated)


func _on_defeated() -> void:
	if _pending:
		return
	_pending = true
	call_deferred("_recover")


func _recover() -> void:
	if not _pending:
		return
	_pending = false
	if not is_instance_valid(player) or state == null:
		return
	var lost: int = floori(float(state.money) * 0.1)
	state.money -= lost
	state.health = PlayerState.MAX_HEALTH
	player.global_position = spawn_position
	player.reset_combat()
	player.suppress_movement_until_release()
	if is_instance_valid(bandit):
		bandit.reset_duel()
	recovered.emit(lost)
