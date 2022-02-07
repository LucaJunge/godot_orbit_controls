extends Node

# emit signals?
# signal change
# signal starts
# signal end

export(NodePath) var _camera
onready var camera = get_node(_camera)
onready var viewport = get_tree().get_root()

var spherical = Spherical.new()
var spherical_delta = Spherical.new()

# exported variables
export var target: Vector3 = Vector3(0, 0, 0)
export var radius: float = 1.0

#rotation properties
export var auto_rotate: bool = false
export var rotate_speed: float = 1.0
export var enable_damping: bool = false
export var damping_factor: float = 0.05
export(float, -6.28318 , 6.28318) var min_azimuth_angle = 0.1
export(float, -6.28318 , 6.28318) var max_azimuth_angle = 0
export(float, 0.0000001, 3.14159) var min_polar_angle = 0.0000001
export(float, 0.0000001, 3.14159) var max_polar_angle = PI - 0.0000001

# zoom properties
export var enable_zoom: bool = true
export var max_zoom_distance: float = 3.0
export var min_zoom_distance: float = 0.2
# don't forget dolly

var is_pressed: bool = false
var last_difference_in_x: float = 0.0
var start_point: Vector3 = Vector3(0, 0, 0)
var polar_angle: float = deg2rad(90.0) # also called inclination
var azimuth_angle: float = deg2rad(90.0)

# on movement
var azimuth_start: float = 0.0
var event_start: Vector2 = Vector2(0.0, 0.0)
var prev_position: Vector2 = Vector2(0, 0)

# for debug output
onready var debug_list = get_node("../Debug/")

# Called when the node enters the scene tree for the first time.
func _ready():
	# Check if camera variable is actually a camera
	if not camera.is_class("Camera"):
		printerr("Selected Camera is not a camera.")
		return
	
	check_constraints()
	
	# connect debug signal
	debug_list.connect("azimuth_slider_changed", self, "on_azimuth_changed")
	debug_list.connect("polar_slider_changed", self, "on_polar_changed")

func _process(delta):
	pass
	
func _unhandled_input(event):
	
	if event is InputEventMouseButton:
		if event.pressed:
			
			if event.button_index == BUTTON_WHEEL_UP:
				radius += 0.1
				if(radius > max_zoom_distance):
					radius  = max_zoom_distance
				camera.translation = get_polar_coordinates()
				$"../Sphere".mesh.radius = radius
				$"../Sphere".mesh.height = radius * 2
			elif event.button_index == BUTTON_WHEEL_DOWN:
				radius -= 0.1
				if(radius < min_zoom_distance):
					radius = min_zoom_distance
				camera.translation = get_polar_coordinates()
				$"../Sphere".mesh.radius = radius
				$"../Sphere".mesh.height = radius * 2
								
			is_pressed = true
			azimuth_start = azimuth_angle
			event_start = event.position
			
			debug_list.set_key("press_position", str(event.position))
			debug_list.set_toggle("pressed", event.pressed)
		else:
			is_pressed = false
			debug_list.set_key("release_position", str(event.position))
			debug_list.set_toggle("pressed", event.pressed)
	
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

func on_azimuth_changed(value):
	azimuth_angle = deg2rad(-value)

func on_polar_changed(value):
	polar_angle = deg2rad(-value)

func check_constraints():
	# check azimuth constraints
	var azimuth_difference = max_azimuth_angle - min_azimuth_angle
	if not azimuth_difference < 2 * PI:
		printerr("Azimuth angles are wrong: max angle minus min angle must be smaller than 6.28318 (2 * PI). Angle is currently ", azimuth_difference)
		
	# check polar constraints
	
	# check other constraints
	pass
