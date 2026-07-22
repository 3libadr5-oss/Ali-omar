# MapData.gd
class_name MapData
extends Resource

@export var name: String = "مرحلة جديدة"
@export var scene: PackedScene   # اسحب مشهد المرحلة هنا
@export var icon: Texture2D      # اسحب الصورة هنا
@export var preview_image: Texture2D = null
