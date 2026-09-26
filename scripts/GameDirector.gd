extends "res://scripts/GameManager.gd"
class_name GameDirector

## GDD-named domain facade. The current project keeps the proven GameManager
## autoload for compatibility, while new integrations can depend on the
## GameDirector contract without coupling to UI scenes.
