/*
    Limits on what AEGIS-M learns while a mission runs: each weapon's own
    measurements of itself and its targets (README, "Learning in play").
    A measurement outside them is taken as a problem with the measuring --
    a frame hitch, a position or velocity that jumped, a round fired off its
    gate, a missile that changed target -- not as something the weapon or
    target really did. It's thrown away, and logged.
*/

// --- Target acceleration -----------------------------------------------------
// The most a target can accelerate, m/s^2: aircraft 15 g; munitions 100 g (a
// missile manoeuvring, a rocket's boost). A lead-solver sample above it
// (aegism_intercept_fnc_computeLeadPoint) is dropped, and the last good one
// stands. A CIWS round's report of how far the real target strayed from its
// predicted track (aegism_intercept_fnc_ciwsSpot) is only believed up to
// what that acceleration could do in the round's flight.
#define AEGISM_MAX_ACCEL_AIRCRAFT 147
#define AEGISM_MAX_ACCEL_MUNITION 981
#define AEGISM_MAX_ACCEL(CLASS) ([AEGISM_MAX_ACCEL_AIRCRAFT, AEGISM_MAX_ACCEL_MUNITION] select ((CLASS) in ["missile", "rocket", "bomb", "artilleryShell"]))

// --- Missile speed (aegism_intercept_fnc_recordMissileSpeed) -----------------
// One flight's real time over its simulated flight's time (aegism_intercept_
// fnc_missileProfile) for the distance it covered. A flight outside these is
// thrown away.
#define AEGISM_SPEED_FACTOR_MIN 0.5
#define AEGISM_SPEED_FACTOR_MAX 2
// A flight shorter than this says little: one frame is a large part of it, s.
#define AEGISM_SPEED_MIN_FLIGHT 1
// The factor used is the median of the last AEGISM_SPEED_SAMPLES flights,
// once there are AEGISM_SPEED_MIN_SAMPLES: one odd flight can't move it.
#define AEGISM_SPEED_SAMPLES 15
#define AEGISM_SPEED_MIN_SAMPLES 3

// --- Missile turn rate (aegism_intercept_fnc_recordMissileTurn) --------------
// A flight's fastest sustained turn above this is a tumble or a glitch, deg/s.
#define AEGISM_TURN_RATE_MAX 180

// --- CIWS spotting (aegism_intercept_fnc_ciwsSpot) ---------------------------
// A round that says the gun needs more lead (s) or elevation (rad) than these
// is thrown away; the gun's correction, an average of the rest, stays inside
// them.
#define AEGISM_SPOT_MAX_LEAD 0.5
#define AEGISM_SPOT_MAX_ELEVATION 0.01
// A round that misses where the gun now aims by more than AEGISM_SPOT_OUTLIER
// times the median miss of its last AEGISM_SPOT_SCALE_ROUNDS measured rounds
// (once it has AEGISM_SPOT_SCALE_MIN) is an outlier: left out of the
// correction and of the gun's measured scatter. The median follows the gun's
// real accuracy, so a real change isn't locked out the way a fixed limit
// would.
#define AEGISM_SPOT_OUTLIER 4
#define AEGISM_SPOT_SCALE_ROUNDS 30
#define AEGISM_SPOT_SCALE_MIN 10

// --- Firing rates --------------------------------------------------------------
// A CIWS burst measured faster than this many times its config rate of fire
// was miscounted, and is left out of its measured rate
// (aegism_intercept_fnc_ciwsBurst). A launcher's time between two missiles
// shorter than this fraction of its own shot interval was miscounted, and is
// left out of its measured shot spacing (aegism_intercept_fnc_engagementLoop).
#define AEGISM_RATE_MAX_RATIO 1.25
#define AEGISM_SPACING_MIN_RATIO 0.9
