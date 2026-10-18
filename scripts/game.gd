extends Control

const BAZAAR: PackedScene = preload("res://scenes/start.tscn")
const Player = preload("res://scripts/player.gd")

var world: Control
var player_state: PlayerState
var player: Player

@onready var main_menu: Control = $Interface/MainMenu
@onready var pause_menu: Control = $Interface/PauseMenu
@onready var hud: Control = $Interface/HUD
@onready var health_label: Label = $Interface/HUD/Health
@onready var money_label: Label = $Interface/HUD/Money
@onready var new_game_button: Button = $Interface/MainMenu/NewGame
@onready var resume_button: Button = $Interface/PauseMenu/Resume


func _ready() -> void:
	new_game_button.pressed.connect(_new_game)
	$Interface/MainMenu/Exit.pressed.connect(_exit_game)
	resume_button.pressed.connect(_resume)
	$Interface/PauseMenu/MainMenu.pressed.connect(_return_to_menu)
	$Interface/PauseMenu/Exit.pressed.connect(_exit_game)
	new_game_button.grab_focus()


func _input(event: InputEvent) -> void:
	if world != null and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if get_tree().paused:
			_resume()
		else:
			get_tree().paused = true
			pause_menu.show()
			resume_button.grab_focus()


func _new_game() -> void:
	if world != null:
		return
	player_state = PlayerState.new()
	world = BAZAAR.instantiate() as Control
	# The controller and its menus keep running; all world descendants pause.
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	player = world.get_node("World/Player") as Player
	player.state = player_state
	player.suppress_movement_until_release()
	$WorldContainer.add_child(world)
	player_state.changed.connect(_update_hud)
	_update_hud()
	new_game_button.release_focus()
	main_menu.hide()
	hud.show()


func _resume() -> void:
	# GUI consumes events, but Input polling still sees held navigation keys.
	player.suppress_movement_until_release()
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	pause_menu.hide()
	get_tree().paused = false


func _return_to_menu() -> void:
	player_state.changed.disconnect(_update_hud)
	$WorldContainer.remove_child(world)
	world.queue_free()
	world = null
	player = null
	player_state = null
	get_tree().paused = false
	pause_menu.hide()
	hud.hide()
	main_menu.show()
	new_game_button.grab_focus()


func _update_hud() -> void:
	health_label.text = "Здоровье: %d/%d" % [player_state.health, PlayerState.MAX_HEALTH]
	money_label.text = "Динары: %d" % player_state.money


func _exit_game() -> void:
	get_tree().quit()
