extends Node
## Єдина точка навігації між екранами. Жодна інша сцена не викликає
## change_scene_to_file напряму — інакше перемикання екранів розсипається
## по кодовій базі й перестає бути єдиним місцем для гейту передачі ходу.

const BATTLE_SCENE: String = "res://game/battle/battle_screen.tscn"
const MAIN_MENU_SCENE: String = "res://game/ui/main_menu.tscn"

func goto(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func goto_battle() -> void:
	goto(BATTLE_SCENE)

func goto_main_menu() -> void:
	goto(MAIN_MENU_SCENE)
