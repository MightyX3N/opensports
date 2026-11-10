## Every number that shapes how bowling plays. Units: metres, kilograms, seconds, radians.
class_name BowlingTuning

const BASE := {
	# ball
	ball_radius = 0.108, ball_mass = 6.5,
	min_speed = 3.0, max_speed = 9.5,  # m/s down the lane for power 0 and 1
	release_height = 0.12,
	max_hook = 10.0,                   # rad/s of side rotation at full twist
	aim_from_swing = 0.0,
	max_swing_aim = 0.02792527,        # 1.6 degrees
	# lane friction: oiled front, dry back end
	oil_length = 12.0, oil_mu = 0.012, dry_mu = 0.20,
	ball_lin_damp = 0.02,
	# pins
	pin_mass = 1.53, pin_mu = 0.25, pin_e = 0.45, ball_pin_e = 0.55,
	settle_after = 1.0, settle_ramp = 1.2, max_turn_time = 8.0,
	down_tilt = 0.43633231,            # 25 degrees
	# player
	move_range = 0.45, move_speed = 0.55,
	turn_range = 0.10471976, turn_speed = 0.10471976, # 6 degrees
}
const PROFILES := {
	arcade = {pin_mass = 1.1, pin_mu = 0.12}, # lighter, slippier pins: more pin action, like the original
	realistic = {},
}

static func get_profile(profile := "arcade") -> Dictionary:
	var t := BASE.duplicate()
	t.merge(PROFILES.get(profile, {}), true)
	return t
