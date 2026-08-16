extends Node
## Єдина точка навігації між екранами. Жодна інша сцена не викликає
## change_scene_to_file напряму — інакше перемикання екранів розсипається
## по кодовій базі й перестає бути єдиним місцем для гейту передачі ходу.

const BATTLE_SCENE: String = "res://game/battle/battle_screen.tscn"
const MAIN_MENU_SCENE: String = "res://game/ui/main_menu.tscn"
const MATCH_SETUP_SCENE: String = "res://game/ui/match_setup.tscn"
const SETTINGS_SCENE: String = "res://game/ui/settings_screen.tscn"
const RESULTS_SCENE: String = "res://game/ui/results_screen.tscn"

func goto(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func goto_battle() -> void:
	goto(BATTLE_SCENE)

func goto_main_menu() -> void:
	goto(MAIN_MENU_SCENE)

func goto_match_setup() -> void:
	goto(MATCH_SETUP_SCENE)

func goto_settings() -> void:
	goto(SETTINGS_SCENE)

func goto_results() -> void:
	goto(RESULTS_SCENE)
