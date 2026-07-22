class_name MiniGameData
extends Resource

@export var name: String = "New Game"
@export var description: String = ""
@export var icon: Texture2D
@export var scene: PackedScene
@export var min_players: int = 2
@export var max_players: int = 4
@export var duration: float = 60.0  # مدة اللعبة بالثواني
@export var max_points: int = 10  # أقصى نقاط ممكنة
