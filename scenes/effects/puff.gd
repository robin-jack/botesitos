extends AnimatedSprite2D

func _ready():
	# Play the animation immediately
	play("default")
	# When it reaches frame 5, delete itself
	animation_finished.connect(queue_free)
