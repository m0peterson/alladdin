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
@onready var interactions: InteractionController = $Interactions
@onready var interaction_hint: Label = $Interface/HUD/InteractionHint
@onready var dialogue: Control = $Interface/Dialogue
@onready var dialogue_text: Label = $Interface/Dialogue/Text
@onready var dialogue_close: Button = $Interface/Dialogue/Close


func _ready() -> void:
	new_game_button.pressed.connect(_new_game)
	$Interface/MainMenu/Exit.pressed.connect(_exit_game)
	resume_button.pressed.connect(_resume)
	$Interface/PauseMenu/MainMenu.pressed.connect(_return_to_menu)
	$Interface/PauseMenu/Exit.pressed.connect(_exit_game)
	interactions.prompt_changed.connect(_update_interaction_hint)
	interactions.interaction_completed.connect(_show_dialogue)
	dialogue_close.pressed.connect(_close_dialogue)
	new_game_button.grab_focus()


func _input(event: InputEvent) -> void:
	if world != null and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if dialogue.visible:
			_close_dialogue()
		elif get_tree().paused:
			_resume()
		else:
			get_tree().paused = true
			interaction_hint.hide()
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
	interactions.set_player(player)
	player_state.changed.connect(_update_hud)
	_update_hud()
	new_game_button.release_focus()
	main_menu.hide()
	hud.show()


func _resume() -> void:
	# GUI consumes events, but Input polling still sees held navigation keys.
	player.suppress_movement_until_release()
	interactions.suppress_until_release()
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	pause_menu.hide()
	get_tree().paused = false


func _return_to_menu() -> void:
	interactions.set_player(null)
	player_state.changed.disconnect(_update_hud)
	$WorldContainer.remove_child(world)
	world.queue_free()
	world = null
	player = null
	player_state = null
	get_tree().paused = false
	pause_menu.hide()
	hud.hide()
	dialogue.hide()
	main_menu.show()
	new_game_button.grab_focus()


func _update_interaction_hint(text: String) -> void:
	interaction_hint.text = text
	interaction_hint.visible = not text.is_empty()


func _show_dialogue(message: String) -> void:
	dialogue_text.text = message
	interaction_hint.hide()
	get_tree().paused = true
	dialogue.show()
	dialogue_close.grab_focus()


func _close_dialogue() -> void:
	dialogue.hide()
	_resume()


func _update_hud() -> void:
	health_label.text = "Здоровье: %d/%d" % [player_state.health, PlayerState.MAX_HEALTH]
	money_label.text = "Динары: %d" % player_state.money


func _exit_game() -> void:
	get_tree().quit()
