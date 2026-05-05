extends AnimatedSprite2D

func _ready():
	# Play the animation immediately
	play("default")
	animation_finished.connect(queue_free)
