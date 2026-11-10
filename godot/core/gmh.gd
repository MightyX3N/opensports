## A port of GamepadMotionHelpers by Julian "Jibb" Smart (MIT), the sensor fusion used by
## JoyShockMapper and many emulators: orientation + gravity tracking, automatic gyro
## calibration while the controller is still, and player-space gyro for aiming.
## https://github.com/JibbSmart/GamepadMotionHelpers — see THIRD_PARTY.md.
## Units as in the original: gyro in degrees/s, accel in g. Frame: x right, y up, z towards
## the player. Gravity points down (-y at rest).
class_name GMH
extends RefCounted

const S := {
	MinStillnessSamples = 10, MinStillnessCollectionTime = 0.5, MinStillnessCorrectionTime = 2.0,
	MaxStillnessError = 2.0, StillnessSampleDeteriorationRate = 0.2, StillnessErrorClimbRate = 0.1,
	StillnessErrorDropOnRecalibrate = 0.1, StillnessCalibrationEaseInTime = 3.0,
	StillnessCalibrationHalfTime = 0.1, StillnessConfidenceRate = 1.0,
	GravityCorrectionShakinessMaxThreshold = 0.4, GravityCorrectionShakinessMinThreshold = 0.01,
	GravityCorrectionStillSpeed = 1.0, GravityCorrectionShakySpeed = 0.1,
	GravityCorrectionGyroFactor = 0.1, GravityCorrectionGyroMinThreshold = 0.05,
	GravityCorrectionGyroMaxThreshold = 0.25, GravityCorrectionMinimumSpeed = 0.01,
	ShortSteadinessHalfTime = 0.25,
}

var q := Quaternion.IDENTITY
var grav := Vector3(0, -1, 0)
var accel := Vector3.ZERO
var smooth_accel := Vector3.ZERO
var shakiness := 0.0
var gyro := Vector3.ZERO
var bias := Vector3.ZERO
var confidence := 0.0
var steady := false
var min_delta_gyro := Vector3.ONE
var min_delta_accel := Vector3(0.25, 0.25, 0.25)
var recal_threshold := 1.0
var time_steady := 0.0
# stillness window
var _wn := 0
var _wt := 0.0
var _max_g: Vector3; var _min_g: Vector3; var _mean_g: Vector3
var _max_a: Vector3; var _min_a: Vector3; var _mean_a: Vector3; var _start_a: Vector3

static func _rot_inv(r: Quaternion, v: Vector3) -> Vector3:
	return r.inverse() * v

func _win_reset() -> void:
	_wn = 0
	_wt = 0.0

func _win_add(g: Vector3, a: Vector3, dt: float) -> void:
	if _wn == 0:
		_max_g = g; _min_g = g; _mean_g = g
		_max_a = a; _min_a = a; _mean_a = a; _start_a = a
		_wn = 1
		_wt += dt
		return
	_max_g = _max_g.max(g); _min_g = _min_g.min(g)
	_max_a = _max_a.max(a); _min_a = _min_a.min(a)
	_wn += 1
	_wt += dt
	_mean_g += (g - _mean_g) / _wn
	_mean_a += (a - _mean_a) / _wn

## AutoCalibration::AddSampleStillness with sensor fusion
func _stillness(g: Vector3, a: Vector3, dt: float) -> void:
	_win_add(g, a, dt)
	var gd := _max_g - _min_g
	var ad := _max_a - _min_a
	var climb: float = S.StillnessSampleDeteriorationRate * dt
	if confidence < 1:
		min_delta_gyro += Vector3.ONE * climb
		min_delta_accel += Vector3.ONE * climb
	if _wn >= S.MinStillnessSamples and _wt >= S.MinStillnessCollectionTime:
		min_delta_gyro = min_delta_gyro.min(gd)
		min_delta_accel = min_delta_accel.min(ad)
	else:
		recal_threshold = minf(recal_threshold + S.StillnessErrorClimbRate * dt, S.MaxStillnessError)
		return
	var th := recal_threshold
	var still := true
	for i in 3:
		if gd[i] > min_delta_gyro[i] * th or ad[i] > min_delta_accel[i] * th:
			still = false
	steady = false
	if still:
		if _wt >= S.MinStillnessCorrectionTime:
			time_steady = minf(time_steady + dt, S.StillnessCalibrationEaseInTime)
			var ease_in: float = time_steady / S.StillnessCalibrationEaseInTime
			var calibrated := _mean_g
			var half: float = S.StillnessCalibrationHalfTime * confidence
			var lerp_f := 0.0 if half <= 0 else pow(2.0, -ease_in * dt / half)
			var new_bias := calibrated.lerp(bias, lerp_f)
			confidence = minf(confidence + dt * S.StillnessConfidenceRate, 1)
			steady = true
			# remove the part of the "still" reading explained by gravity turning
			var pn := _start_a.normalized()
			var tn := a.normalized()
			var av := tn.cross(pn)
			var cl := av.length()
			if cl > 0:
				var ang := rad_to_deg(acos(clampf(tn.dot(pn), -1, 1)))
				av = av * ((ang / _wt) / cl)
			var sf := (calibrated - av).lerp(bias, lerp_f)
			for i in 3:
				if absf(tn[i]) <= 0.7:
					new_bias[i] = sf[i]
			bias = new_bias
		else:
			recal_threshold = minf(recal_threshold + S.StillnessErrorClimbRate * dt, S.MaxStillnessError)
	elif time_steady > 0:
		recal_threshold = maxf(1, recal_threshold - S.StillnessErrorDropOnRecalibrate)
		time_steady = 0.0
		_win_reset()
	else:
		recal_threshold = minf(recal_threshold + S.StillnessErrorClimbRate * dt, S.MaxStillnessError)
		_win_reset()

## Motion::Update. gyro deg/s (bias-corrected), accel g.
func _motion(g: Vector3, acc: Vector3, gravity_length: float, dt: float) -> void:
	var angle_speed := deg_to_rad(g.length())
	var rotation := Quaternion.IDENTITY
	if angle_speed * dt >= 1e-12:
		rotation = Quaternion(g.normalized(), angle_speed * dt)
	q = q * rotation
	var amag := acc.length()
	if amag > 0:
		var an := acc / amag
		smooth_accel = _rot_inv(rotation, smooth_accel)
		var sf: float = 0.0 if S.ShortSteadinessHalfTime <= 0 else pow(2.0, -dt / S.ShortSteadinessHalfTime)
		shakiness = maxf(shakiness * sf, (acc - smooth_accel).length())
		smooth_accel = acc.lerp(smooth_accel, sf)
		grav = _rot_inv(rotation, grav)
		var grav_to_accel := an * -gravity_length - grav
		var dir := grav_to_accel.normalized()
		var speed: float = S.GravityCorrectionStillSpeed + (S.GravityCorrectionShakySpeed - S.GravityCorrectionStillSpeed) * \
			clampf((shakiness - S.GravityCorrectionShakinessMinThreshold) / (S.GravityCorrectionShakinessMaxThreshold - S.GravityCorrectionShakinessMinThreshold), 0, 1)
		var limit := maxf(angle_speed * S.GravityCorrectionGyroFactor, S.GravityCorrectionMinimumSpeed)
		if speed > limit:
			var close := clampf((grav_to_accel.length() - S.GravityCorrectionGyroMinThreshold) / (S.GravityCorrectionGyroMaxThreshold - S.GravityCorrectionGyroMinThreshold), 0, 1)
			speed = limit + (speed - limit) * close
		var delta := dir * speed * dt
		if delta.length_squared() < grav_to_accel.length_squared():
			grav += delta
		else:
			grav = an * -gravity_length
		# pull the orientation so its gravity matches the tracked gravity
		var grav_world := q * grav.normalized()
		var down := Vector3(0, -1, 0)
		var err := acos(clampf(down.dot(grav_world), -1, 1))
		var flat := grav_world.cross(down)
		if flat.length() > 1e-9 and err > 1e-9:
			q = Quaternion(flat.normalized(), err) * q
		accel = acc + grav
	else:
		grav = _rot_inv(rotation, grav)
		accel = grav
	q = q.normalized()

## GamepadMotion::ProcessMotion. gyro deg/s raw, accel g raw.
func process(g: Vector3, a: Vector3, dt: float) -> void:
	if g == Vector3.ZERO and a == Vector3.ZERO:
		return
	_stillness(g, a, dt)
	gyro = g - bias
	_motion(gyro, a, a.length(), dt)
