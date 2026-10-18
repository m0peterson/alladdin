extends SceneTree

const Game = preload("res://scripts/game.gd")
const KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_ESCAPE, KEY_TAB]
const CAPTURE_DIR: String = "res://.godot/t04-review"

var game: Game
var failures: int = 0
var capture: bool = false


func _initialize() -> void:
	capture = "--capture-ui" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		push_error("BLOCKED: UI capture needs a real renderer")
		quit(1)
		return
	if capture and DirAccess.make_dir_recursive_absolute(CAPTURE_DIR) != OK:
		push_error("FAIL: cannot create UI capture directory")
		quit(1)
		return
	if change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) != OK:
		quit(1)
		return
	await scene_changed
	game = current_scene as Game
	await _frames(2)
	_expect(game.main_menu.visible and not game.hud.visible, "startup shows main menu")
	_expect(game.world == null and not paused, "no world runs behind main menu")
	var continue_button: Button = game.get_node("Interface/MainMenu/Continue") as Button
	_expect(continue_button.disabled, "Continue disabled before save support")
	_expect(not (game.get_node("Interface/MainMenu/SaveHint") as Label).text.is_empty(), "unavailable save explained without hover")
	_check_cyrillic()
	await _save("main-menu")
	await _tap(KEY_DOWN)
	_expect(game.get_viewport().gui_get_focus_owner() == game.get_node("Interface/MainMenu/Exit"), "keyboard skips disabled Continue")
	await _tap(KEY_UP)
	_expect(game.new_game_button.has_focus(), "keyboard returns to New Game")
	# Hold navigation and movement across keyboard activation of New Game.
	_key(KEY_UP, true)
	_key(KEY_W, true)
	await _tap(KEY_ENTER)
	_expect(game.world != null and game.world.scene_file_path == "res://scenes/start.tscn", "New Game opens existing bazaar")
	_expect(game.player.state == game.player_state, "player and HUD share one state")
	_expect(game.hud.visible and not game.main_menu.visible, "gameplay HUD replaces main menu")
	var start: Vector2 = game.player.position
	await _frames(8)
	_expect(game.player.position == start, "held menu keys do not move new game")
	_release()
	await _frames(2)
	await _save("hud")
	_key(KEY_D, true)
	await _frames(8)
	_expect(game.player.position.x > start.x + 5.0, "fresh gameplay input moves player")
	await _tap(KEY_ESCAPE)
	_expect(paused and game.pause_menu.visible, "Esc pauses and opens menu")
	var stopped: Vector2 = game.player.position
	var frame: int = game.player.sprite.frame
	var progress: float = game.player.sprite.frame_progress
	var timer: Timer = Timer.new()
	timer.wait_time = 0.02
	game.world.add_child(timer)
	timer.start()
	var time_left: float = timer.time_left
	await _frames(8)
	_expect(game.player.position == stopped, "held movement cannot move paused world")
	_expect(game.player.sprite.frame == frame and game.player.sprite.frame_progress == progress, "animation pauses with world")
	_expect(timer.time_left == time_left, "world timer pauses with simulation")
	await _save("pause")
	# Echo must not repeatedly toggle pause while Esc is held.
	_key(KEY_ESCAPE, true, true)
	await _frames(2)
	_expect(paused, "Esc echo does not toggle pause")
	_key(KEY_ESCAPE, false)
	await _tap(KEY_ESCAPE)
	_expect(not paused and not game.pause_menu.visible, "Esc resumes")
	await _frames(8)
	_expect(game.player.position == stopped, "held key blocked after Esc resume")
	_release()
	await _frames(2)
	_key(KEY_D, true)
	await _frames(6)
	_expect(game.player.position.x > stopped.x + 4.0, "movement rearmed after release")
	_release()
	await _tap(KEY_ESCAPE)
	_key(KEY_W, true)
	await _click(game.resume_button)
	_expect(not paused, "mouse resume works during pause")
	stopped = game.player.position
	await _frames(6)
	_expect(game.player.position == stopped, "mouse resume also blocks held movement")
	_release()
	await _frames(2)
	game.player.state.health = 37
	game.player.state.money = 1234567890
	_expect(game.health_label.text == "Здоровье: 37/100", "HUD follows shared health change")
	_expect(game.money_label.text == "Динары: 1234567890", "HUD follows shared money change")
	await _save("hud-changed")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_DOWN)
	_expect(game.get_viewport().gui_get_focus_owner() == game.get_node("Interface/PauseMenu/MainMenu"), "pause keyboard navigation works")
	var old_state: PlayerState = game.player_state
	var old_world: WeakRef = weakref(game.world)
	await _tap(KEY_ENTER)
	_expect(not paused and game.main_menu.visible and not game.hud.visible, "return to menu clears pause")
	_expect(game.world == null and old_world.get_ref() == null, "old world removed and freed")
	_expect(game.get_node("WorldContainer").get_child_count() == 0, "no hidden world after return")
	_expect(old_state.changed.get_connections().is_empty(), "old HUD subscription removed")
	await _click(game.new_game_button)
	_expect(game.player_state != old_state, "new game owns fresh state")
	_expect(game.player_state.health == 100 and game.player_state.money == 0, "new game resets health and money")
	old_state.money = 999
	_expect(game.money_label.text == "Динары: 0", "discarded state cannot change HUD")
	for cycle: int in range(3):
		await _tap(KEY_ESCAPE)
		_expect(paused and game.pause_menu.visible, "repeated pause opens")
		await _tap(KEY_ENTER)
		_expect(not paused and not game.pause_menu.visible, "keyboard resume works repeatedly")
	_release()
	if failures:
		push_error("FAIL: T04 UI (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T04 menus, shared HUD state, pause and input isolation")
		print("INFO: actual UI captures in .godot/t04-review" if capture else "NOT RUN: rendered Cyrillic readability; check separately")
		quit(0)


func _check_cyrillic() -> void:
	var title: Label = game.get_node("Interface/MainMenu/Title") as Label
	var font: Font = title.get_theme_font("font")
	for character: String in "АладдинТениАграбыНоваяиграПродолжитьВыходЗдоровьеДинарыПаузаСохранениянедоступныВернуться":
		_expect(font.has_char(character.unicode_at(0)), "font covers Cyrillic: " + character)


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(1)


func _tap(key: Key) -> void:
	_key(key, true)
	await _frames(1)
	_key(key, false)
	await _frames(1)


func _key(key: Key, pressed: bool, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


func _release() -> void:
	for key: Key in KEYS:
		_key(key, false)


func _frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		await process_frame


func _save(label: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(CAPTURE_DIR + "/" + label + ".png") != OK:
		_expect(false, "save UI capture: " + label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
