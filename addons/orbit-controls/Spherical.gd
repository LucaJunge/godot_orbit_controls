extends Node
class_name Spherical
	
var radius: float
var phi: float
var theta: float

func _init(_radius: float = 1, _phi: float = 0, _theta: float = 0):
	radius = _radius
	phi = _phi
	theta = _theta

func set_to(_radius: float, _phi: float, _theta: float):
	radius = _radius
	phi = _phi
	theta = _theta

func copy(_other_spherical: Spherical):
	radius = _other_spherical._radius
	phi = _other_spherical._phi
	theta = _other_spherical._theta

func make_safe() -> void:
	var precision: float = 0.0000000000001
	phi = max(precision, min(PI - precision, phi))

func set_from_vector(v: Vector3):
	self.set_from_cartesian_coords(v.x, v.y, v.z)
	
func dampen(damping_factor:float) ->bool:
	theta *= (1 - damping_factor)
	phi *= (1 - damping_factor)
	if abs(theta) < 0.001:
		theta = 0.0
	if abs(phi) < 0.001:
		phi = 0.0
	if theta == 0 and phi == 0:
		radius = 0
	return abs(theta) > 0 or abs(phi) > 0
		
func set_from_cartesian_coords(x: float, y: float, z: float):
	radius = sqrt(x * x + y * y + z * z)
	if radius == 0:
		theta = 0
		phi = 0
	else:
		theta = atan2(x, z)
		phi = acos(clamp(y / radius, -1, 1))

func apply_to_vector(vector: Vector3) -> Vector3:
	var sin_phi_radius = sin(phi) * radius
	
	vector.x = sin_phi_radius * sin(theta)
	vector.y = cos(phi) * radius
	vector.z = sin_phi_radius * cos(theta)
	return vector
