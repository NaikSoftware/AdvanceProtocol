class_name ResultsScreen
extends Control
## Task 3.5 (скелет): екран результату. Переможець, підсумок по гравцях
## (втрати, завдана шкода, утримані цілі, рівні досвіду), кнопки «Реванш»
## (той самий матч, новий сід) і «В меню».
##
## Скелет: статичні числа-заглушки. Привʼязка до Events.MatchEnded і реальний
## реванш (новий сід того самого матчу) — крок логіки Task 3.5.


func _ready() -> void:
	%RematchButton.pressed.connect(SceneRouter.goto_battle)
	%ToMenuButton.pressed.connect(SceneRouter.goto_main_menu)
