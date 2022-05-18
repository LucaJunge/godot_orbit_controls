extends Node

# SIGNALS #
signal start
signal change
signal end

# CAMERA #

# Path to the camera to control with the orbit controls
export(NodePath) var _camera
var camera = null
#onready var viewport = get_tree().get_root()

# PROPERTIES
export var target: Vector3 = Vector3(0, 0, 0)
export var auto_rotate: bool = false
export var enable_zoom: bool = true
export var enable_damping: bool = true
export var rotate_speed: float = 1.0
export var damping_factor: float = 0.05
export var radius: float = 1.0
export var max_zoom_distance: float = 5.0
export var min_zoom_distance: float = 0.2
export(float, -6.28318 , 6.28318) var min_azimuth_angle = 0.1
export(float, -6.28318 , 6.28318) var max_azimuth_angle = 0
export(float, 0.0000001, 3.14159) var min_polar_angle = 0.0000001
export(float, 0.0000001, 3.14159) var max_polar_angle = PI - 0.0000001

# HELPERS
var spherical = Spherical.new()
var spherical_delta = Spherical.new()

var is_pressed: bool = false
var last_difference_in_x: float = 0.0
var start_point: Vector3 = Vector3(0, 0, 0)
var polar_angle: float = deg2rad(90.0) # also called inclination
var azimuth_angle: float = deg2rad(90.0)

# on movement
var azimuth_start: float = 0.0
var event_start: Vector2 = Vector2(0.0, 0.0)
var prev_position: Vector2 = Vector2(0, 0)

# On Updates
var offset = Vector3(0, 0, 0)

# Called when the node enters the scene tree for the first time.
func _ready():
	check_camera()
	check_constraints()
	camera.translation = get_polar_coordinates()

func _process(delta):
	var position = camera.translation
	offset = position - target
	spherical.set_from_vector(offset)
#
#	# Dampen the actual spherical with the delta
	if enable_damping:
		spherical.theta += spherical_delta.theta * damping_factor
		spherical.phi += spherical_delta.phi * damping_factor
	else:
		spherical.theta += spherical_delta.theta
		spherical.phi += spherical_delta.phi 
#
#	camera.look_at(target, Vector3(0, 1, 0))
#
#	# Dampen the delta spherical by the damping factor
	if enable_damping:
		spherical_delta.theta *= (1 - damping_factor)
		spherical_delta.phi *= (1 - damping_factor)
	else:
		spherical_delta.set(0, 0, 0)
#
	pass
	
func _unhandled_input(event):
	
	if event is InputEventMouseButton:
		if event.pressed:

			if event.button_index == BUTTON_WHEEL_UP:
				radius += 0.1
				if(radius > max_zoom_distance):
					radius  = max_zoom_distance
				camera.translation = get_polar_coordinates()
			elif event.button_index == BUTTON_WHEEL_DOWN:
				radius -= 0.1
				if(radius < min_zoom_distance):
					radius = min_zoom_distance
				camera.translation = get_polar_coordinates()

			is_pressed = true
			azimuth_start = azimuth_angle
			event_start = event.position
		else:
			is_pressed = false

	if event is InputEventMouseMotion and is_pressed:
		var difference_in_x = event_start.x - event.position.x
		var difference_in_y = event_start.y - event.position.y

		event_start = event.position

		if enable_damping:
			azimuth_angle -= deg2rad((difference_in_x * rotate_speed) * (1 - damping_factor))
			polar_angle += deg2rad((difference_in_y * rotate_speed) * (1 - damping_factor))
		else:
			azimuth_angle -= deg2rad(difference_in_x * rotate_speed)
			polar_angle += deg2rad(difference_in_y * rotate_speed)

		if(polar_angle < min_polar_angle):
			polar_angle = min_polar_angle
		elif(polar_angle > max_polar_angle - 0.01):
			polar_angle = max_polar_angle - 0.01

		camera.translation = get_polar_coordinates()
		camera.look_at(target, Vector3(0, 1, 0))
		
# input radians only
func get_polar_coordinates():
	var x = radius * sin(polar_angle) * cos(azimuth_angle)
	var y = radius * cos(polar_angle)
	var z = radius * sin(polar_angle) * sin(azimuth_angle)
	return Vector3(x, y, z)


func check_constraints():
	# check azimuth constraints
	var azimuth_difference = max_azimuth_angle - min_azimuth_angle
	if not azimuth_difference < 2 * PI:
		printerr("Azimuth angles are wrong: max angle minus min angle must be smaller than 6.28318 (2 * PI). Angle is currently ", azimuth_difference)
		
	# check polar constraints
	
	# check other constraints
	pass

func check_camera():
	# Check if camera variable is actually a camera
	if _camera:
		camera = get_node(_camera)
		
		if not camera.is_class("Camera"):
			printerr("Selected Camera is not a camera.")
			return
	else:
		printerr("No camera provided")
