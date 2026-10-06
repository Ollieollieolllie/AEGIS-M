/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_computeLeadPoint

Description:
    Intercept solution for one weapon against one target: where to point so
    the round/missile and the target arrive at the same place, and whether
    that is possible at all.

    The target is projected forward by the weapon's time of flight to the
    projected point (velocity plus measured acceleration, zero-effort-miss
    style), solved for the moment the two agree (see "Solving" below). All
    kinematics come from real config, read once per weapon + magazine
    (aegism_intercept_fnc_weaponKinematics):

        gun (ciws) - muzzle velocity v0 from CfgMagazines initSpeed
            (overridden per engine rules by CfgWeapons initSpeed: > 0
            replaces, < 0 multiplies), drag k from CfgAmmo airFriction (the
            engine's a = -k |v| v), and gravity. With a = k v0, the round's
            speed falls as v0/(1 + a t), and its velocity solves
            dv/dt = -k v0/(1 + a t) v + g exactly:
                position(t) = muzzle + aim direction x ln(1 + a t)/k
                              + g x (t + a t^2/2 - ln(1 + a t)/a) / (2a)
            So the round falls (g/2a)(t + a t^2/2 - ln(1 + a t)/a) below its
            launch line -- LESS than the vacuum g t^2/2, because the same
            drag slows its fall -- and it covers the distance to the RAISED
            point along that line: exp(k d) - 1 = a t. The aim point is the
            intercept raised by that fall. (It used to be raised by the
            vacuum drop, with the flight time measured to the un-raised
            point: at 2s of flight that aimed ~4m high, and a round climbing
            to a shell overhead arrived late -- behind it.)
            The one approximation: drag is taken at the round's speed along
            its line; gravity's own small change to that speed is second
            order.
        missile (launcher) - its speed curve learned from its own flights
            this mission, or simulated from config until then (aegism_
            intercept_fnc_missileProfile: launch speed, the motor's thrust
            and fade, drag). No drop: the missile is guided. Pointing
            the launcher at this point instead of the target's current
            position saves the missile a hard turn right off the rail.
        missile launched OFF-BORE (_launchDir given, with the missile's turn
            rate, aegism_intercept_fnc_missileAgility) - a vertical launch
            cell, a turret at its limit, or one fired before it's round: the
            missile first turns from _launchDir onto the intercept at its
            turn rate, then flies straight at it. The turn is an arc in the
            plane of the launch direction and the intercept, through the
            angle between the launch direction and the line from the turn's
            END to the intercept (iterated: the turn carries it sideways),
            covering what the missile flies in that time on its own speed
            profile. Its flight time is the arc plus the straight run. A
            target inside the turn -- the arc carries the missile past it --
            has no solution: an off-bore shot's minimum range, which grows
            with the angle and the missile's speed.

    FEASIBLE only if the solution converges inside the weapon's own reach
    (weaponInfo maxRange, from config) and within the round's own lifetime
    (CfgAmmo timeToLive, e.g. 6s for vanilla bullets, or until an airburst
    round bursts: aegism_intercept_fnc_ammoBurst) -- judged at the
    meeting point it ends on, not where the target is now: a round or
    missile can be fired at a target still beyond its reach and meet it
    inside. A target receding
    faster than the round can close -- a jet flying away from a gun -- has
    no solution: the meeting never settles. The previous version didn't
    check this and iterated to NaN (RPT "Error Type Not a Number" in this
    file), and CIWS kept firing at targets it could never reach. An
    infeasible solution returns the target's current position as the aim
    point.

    Solving: the meeting time t is where the flight time to the target's
    position at t is t itself. Before t is passed, the flight is longer
    than t; after, shorter. Until the search has seen a time past the
    meeting, it steps on to the flight time (which only moves later); then
    by secant steps inside the bracket it has, halving it when a step would
    leave it, until the two agree within AEGISM_LEAD_SOLVE_TOLERANCE.
    Simply setting t to the flight time over and over (five times, as this
    used to) only settles while the target closes slower than the round or
    missile flies. A missile coasting late in its flight doesn't: a Stinger
    at ~300 m/s on a rocket closing at ~240 swung 17.5, 3.8, 13.2, 5.8,
    11.1, 7.1 s about a meeting at 8.7 s, and was fired on the last swing
    (predicted 5.5 s; its flights took 9.1 s). Not settled within AEGISM_
    LEAD_SOLVE_ITERATIONS, or past the round's lifetime without a time past
    the meeting seen: no meeting.

    Target acceleration is measured from successive velocity samples cached
    on the target per firing System (SQF has no acceleration command) -- a
    sample beyond what the target can do (calibration.hpp: a position or
    velocity that jumped) is dropped, LEAD-SAMPLE-REJECT; pass
    _useAcceleration false for a side-effect-free, velocity-only estimate
    (the Site coordinator's envelope check).

    Planning ahead (the Site coordinator's layered reserve, aegism_intercept_
    fnc_assignEngagements): _delay solves for a shot fired that many seconds
    from now, from the target's state projected to that moment, and
    _ballistic projects it on gravity alone -- exact for an unguided
    artillery round or rocket (CfgAmmo airFriction 0).

Parameters:
    _system - the firing System vehicle (keys the acceleration sample) <OBJECT>
    _origin - ASL position the round/missile leaves from <ARRAY>
    _target - the target object <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _role - "ciws" (gun) or "launcher" (missile) <STRING>
    _useAcceleration - optional, default true <BOOLEAN>
    _delay - optional, seconds from now the shot leaves, default 0 <NUMBER>
    _ballistic - optional, project the target on gravity alone, default
        false <BOOLEAN>
    _leadBias - optional, seconds added to the time the target is projected
        forward (not to the round's flight time): a CIWS gun's spotting
        correction, aegism_intercept_fnc_ciwsSpot. Default 0 <NUMBER>
    _launchDir - optional, missile only: world direction it leaves along,
        for an off-bore launch (see header). Default [] = straight at the
        intercept <ARRAY>
    _turnRate - optional, with _launchDir: the missile's turn rate, deg/s.
        0 = unknown: flown as if launched straight <NUMBER>

Returns:
    [aimPoint ASL <ARRAY>, feasible <BOOLEAN>, timeOfFlight s <NUMBER>
     (-1 if infeasible), interceptDistance m <NUMBER>, predicted track
     [position ASL, velocity, acceleration] the target was projected from
     <ARRAY> -- CIWS spotting replays it (aegism_intercept_fnc_ciwsSpot),
     interceptPoint ASL: where the target is met (the aim point before the
     gun's drop is added) <ARRAY>, off-bore turn [angle deg, time s, ASL
     position where it ends] ([0, 0, origin] if none) <ARRAY>]

Examples:
    [_cheetah, eyePos gunner _cheetah, _heli, _weaponInfo, "ciws"] call aegism_intercept_fnc_computeLeadPoint;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"
#include "..\calibration.hpp"

// The meeting-time search (see header): at most this many flight times
// worked out, settled once the flight time to where the target will be
// agrees with the time within this, s (0.3 m on a 300 m/s target).
#define AEGISM_LEAD_SOLVE_ITERATIONS 15
#define AEGISM_LEAD_SOLVE_TOLERANCE 0.001
#define AEGISM_GRAVITY 9.80665
#define AEGISM_LEAD_MIN_SAMPLE_DT 0.05
#define AEGISM_LEAD_MAX_SAMPLE_DT 2
// exp() argument above which a gun's drag makes the flight time absurd
// (e^30 ~ 1e13) -- treated as "can't get there" rather than overflowing.
#define AEGISM_MAX_DRAG_EXPONENT 30
// Off-bore turn solve: iterations, and the change in the turn angle (deg)
// between two iterations that counts as converged. Below the minimum angle
// the launch is straight.
#define AEGISM_TURN_SOLVE_ITERATIONS 8
#define AEGISM_TURN_SOLVE_TOLERANCE 0.25
#define AEGISM_TURN_MIN_ANGLE 0.01

params ["_system", "_origin", "_target", "_weaponInfo", "_role", ["_useAcceleration", true], ["_delay", 0], ["_ballistic", false], ["_leadBias", 0], ["_launchDir", []], ["_turnRate", 0]];
_weaponInfo params ["", "_weaponClass", "_magazineClass", "", "", ["_maxRange", 0]];

private _targetPos = getPosASLVisual _target;
private _currentDistance = _origin distance _targetPos;

private _isGun = _role == "ciws";

// Kinematics, declared at this scope: the time-of-flight code below is
// called later from here, and SQF code only sees variables that still exist
// in the scope it's called from.
([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics)
    params ["", "_v0", "_k", "", "", "", "", "_maxTime"];
// A missile's flight: learned from its own flights, or its config simulation
// until then (aegism_intercept_fnc_missileProfile).
private _profile = if (_isGun) then { [] } else { [_weaponClass, _magazineClass] call aegism_intercept_fnc_missileProfile };

// Time for the round/missile to cover a distance; -1 = it can't.
private _fnTimeOfFlight = if (_isGun) then {
    {
        params ["_d"];
        if (_v0 <= 0) exitWith { -1 };
        if (_k <= 0) exitWith { _d / _v0 };
        if (_k * _d > AEGISM_MAX_DRAG_EXPONENT) exitWith { -1 };
        ((exp (_k * _d)) - 1) / (_k * _v0)
    }
} else {
    {
        params ["_d"];
        [_profile, "time", _d] call aegism_intercept_fnc_missileProfileAt
    }
};

// No usable speed data in config (e.g. a mod weapon with neither initSpeed
// nor thrust): nothing to predict with, so aim at the target and don't
// block the engagement -- the old behaviour -- rather than calling every
// target unreachable.
if ((_isGun && {_v0 <= 0}) || {!_isGun && {_profile isEqualTo []}}) exitWith { [_targetPos, true, -1, _currentDistance, [_targetPos, velocity _target, [0, 0, 0]], _targetPos, [0, 0, _origin]] };

// Off-bore launch (see header): the turn onto a point, recorded as
// [angle deg, time s, where it ends] by the flight time below.
private _turning = !_isGun && {_launchDir isNotEqualTo []} && {_turnRate > 0};
private _turn = [0, 0, _origin];

// Distance a missile covers in its first _t s: the inverse of its flight time.
private _fnDistanceAt = {
    params ["_t"];
    [_profile, "distance", _t] call aegism_intercept_fnc_missileProfileAt
};

// Flight time to a point: straight, or turning onto it first; -1 = it can't.
private _fnPathTime = {
    params ["_point"];
    private _toPoint = _point vectorDiff _origin;
    private _distance = vectorMagnitude _toPoint;
    if (!_turning) exitWith { [_distance] call _fnTimeOfFlight };
    private _theta = acos (((_launchDir vectorCos _toPoint) min 1) max -1);
    if (_theta < AEGISM_TURN_MIN_ANGLE) exitWith { _turn = [0, 0, _origin]; [_distance] call _fnTimeOfFlight };
    // The turn's plane: the launch direction and the point. Dead astern has
    // none.
    private _perp = _toPoint vectorDiff (_launchDir vectorMultiply (_toPoint vectorDotProduct _launchDir));
    if ((vectorMagnitude _perp) < 0.001) exitWith { -1 };
    private _side = vectorNormalized _perp;
    private _fnTurnEnd = {
        params ["_angle"];
        if (_angle < AEGISM_TURN_MIN_ANGLE) exitWith { [0, _origin] };
        private _arc = [_angle / _turnRate] call _fnDistanceAt;
        private _radius = _arc / (rad _angle);
        [_arc, _origin vectorAdd (_launchDir vectorMultiply (_radius * sin _angle)) vectorAdd (_side vectorMultiply (_radius * (1 - cos _angle)))]
    };
    private _converged = false;
    for "_i" from 1 to AEGISM_TURN_SOLVE_ITERATIONS do {
        private _rest = _point vectorDiff (([_theta] call _fnTurnEnd) select 1);
        // Carried past it sideways: it's inside the turn.
        if ((_rest vectorDotProduct _side) < 0) exitWith {};
        private _next = acos (((_launchDir vectorCos _rest) min 1) max -1);
        if (abs (_next - _theta) <= AEGISM_TURN_SOLVE_TOLERANCE) exitWith { _theta = _next; _converged = true; };
        _theta = _next;
    };
    if (!_converged || {_theta >= 180}) exitWith { -1 };
    ([_theta] call _fnTurnEnd) params ["_arc", "_turnEnd"];
    _turn = [_theta, _theta / _turnRate, _turnEnd];
    [_arc + (_point vectorDistance _turnEnd)] call _fnTimeOfFlight
};

private _targetVelocity = velocity _target;
private _targetAcceleration = [0, 0, 0];
if (_useAcceleration) then {
    private _sampleKey = _system getVariable "AEGISM_leadSampleKey";
    if (isNil "_sampleKey") then {
        _sampleKey = format ["AEGISM_leadSample_%1", netId _system];
        _system setVariable ["AEGISM_leadSampleKey", _sampleKey, false];
    };
    private _sample = _target getVariable [_sampleKey, []];
    if (_sample isNotEqualTo []) then {
        _sample params ["_prevVelocity", "_prevTime", "_prevAccel"];
        private _dt = CBA_missionTime - _prevTime;
        // More than the target could do (calibration.hpp): its position or
        // velocity jumped -- a frame hitch, a network correction -- it didn't
        // manoeuvre. The last good acceleration stands, and the next sample
        // is taken against the same good one.
        private _glitch = false;
        switch (true) do {
            case (_dt < AEGISM_LEAD_MIN_SAMPLE_DT): { _targetAcceleration = _prevAccel; };
            case (_dt > AEGISM_LEAD_MAX_SAMPLE_DT): { _targetAcceleration = [0, 0, 0]; };
            default {
                private _sampled = (_targetVelocity vectorDiff _prevVelocity) vectorMultiply (1 / _dt);
                private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;
                if (vectorMagnitude _sampled > AEGISM_MAX_ACCEL(_targetClass)) then {
                    _glitch = true;
                    _targetAcceleration = _prevAccel;
                    if (AEGISM_RPT_VERBOSE && {!(_target getVariable ["AEGISM_accelGlitchLogged", false])}) then {
                        _target setVariable ["AEGISM_accelGlitchLogged", true];
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " LEAD-SAMPLE-REJECT: %1 (%2) measured accelerating %3 m/s2 over %4s, beyond the %5 m/s2 a %6 can -- a glitch in its position or velocity, not a manoeuvre; the last good acceleration stands (logged once per target).",
                            _target, typeOf _target, round vectorMagnitude _sampled, round (_dt * 100) / 100, AEGISM_MAX_ACCEL(_targetClass), _targetClass];
                    };
                } else {
                    _targetAcceleration = _sampled;
                };
            };
        };
        if (_dt >= AEGISM_LEAD_MIN_SAMPLE_DT && {!_glitch}) then {
            _target setVariable [_sampleKey, [_targetVelocity, CBA_missionTime, _targetAcceleration], false];
        };
    } else {
        _target setVariable [_sampleKey, [_targetVelocity, CBA_missionTime, [0, 0, 0]], false];
    };
};
if (_ballistic) then { _targetAcceleration = [0, 0, -AEGISM_GRAVITY]; };
if (_delay > 0) then {
    _targetPos = _targetPos vectorAdd (_targetVelocity vectorMultiply _delay) vectorAdd (_targetAcceleration vectorMultiply (0.5 * _delay * _delay));
    _targetVelocity = _targetVelocity vectorAdd (_targetAcceleration vectorMultiply _delay);
    _currentDistance = _origin distance _targetPos;
};

private _fnOutOfReach = {
    params ["_distance", "_time"];
    _time < 0 || {_maxRange > 0 && {_distance > _maxRange}} || {_maxTime > 0 && {_time > _maxTime}}
};

// A gun round's fall below its launch line after _t s: gravity, damped by
// the same drag that slows the round (see header). Near-zero drag: the
// series of the same expression (it cancels badly in 32-bit floats there).
private _fnDrop = {
    params ["_t"];
    if (!_isGun) exitWith { 0 };
    private _a = _k * _v0;
    private _at = _a * _t;
    if (_at < 0.001) exitWith { 0.5 * AEGISM_GRAVITY * _t * _t * (1 - _at / 3) };
    (AEGISM_GRAVITY / (2 * _a)) * (_t + 0.5 * _at * _t - (ln (1 + _at)) / _a)
};

private _timeToGo = [_targetPos] call _fnPathTime;
private _interceptPoint = _targetPos;
private _interceptDistance = _currentDistance;
private _aimPoint = _targetPos;
// Judged only where the round or missile meets the target, once solved:
// fired at a target still beyond its reach, it meets it inside (aegism_
// intercept_fnc_canEngage) -- a gun opens fire so its rounds arrive just
// as the target comes into reach, rather than once the target is there.
// Midway the search tries times either side of the answer, and one just
// past the edge would throw out a meeting just inside it; a step only stops
// it when the round can't get there at all (a gun's drag past AEGISM_MAX_
// DRAG_EXPONENT: a target receding faster than the rounds close).
private _feasible = _timeToGo >= 0;

// For a flight time _t: where the target is met, and the point to aim at
// for it (raised by a gun round's fall).
private _fnSolveAt = {
    params ["_t"];
    private _leadTime = (_t + _leadBias) max 0;
    _interceptPoint = _targetPos
        vectorAdd (_targetVelocity vectorMultiply _leadTime)
        vectorAdd (_targetAcceleration vectorMultiply (0.5 * _leadTime * _leadTime));
    _interceptDistance = _origin distance _interceptPoint;
    _aimPoint = _interceptPoint vectorAdd [0, 0, [_t] call _fnDrop];
};

// The meeting time (see header, "Solving"): t where the flight time to the
// aim point for t, less t, is nought. _lo is the latest t seen with the
// flight still longer; _hi the earliest seen with it shorter, -1 until one is.
if (_feasible) then {
    private _t = _timeToGo;
    private _lo = 0;
    private _hi = -1;
    private _prev = 0;
    private _prevGap = _timeToGo;
    private _settled = false;
    for "_i" from 1 to AEGISM_LEAD_SOLVE_ITERATIONS do {
        [_t] call _fnSolveAt;
        // The round covers the distance to the aim point along its launch
        // line (for a gun that's the raised point, see header); an off-bore
        // missile turns onto it first.
        private _flight = [_aimPoint] call _fnPathTime;
        if (_flight < 0) exitWith {};
        private _gap = _flight - _t;
        if (abs _gap <= AEGISM_LEAD_SOLVE_TOLERANCE) exitWith { _settled = true; };
        if (_gap > 0) then { _lo = _t; } else { _hi = _t; };
        if (_hi >= 0 && {_hi - _lo <= 2 * AEGISM_LEAD_SOLVE_TOLERANCE}) exitWith { _t = (_lo + _hi) / 2; _settled = true; };
        // Still before the meeting, and already past the round's lifetime:
        // it can't meet it in time.
        if (_hi < 0 && {_maxTime > 0} && {_t > _maxTime}) exitWith {};
        private _next = _flight;
        if (_hi >= 0) then {
            if (abs (_gap - _prevGap) > 1e-9) then { _next = _t - _gap * (_t - _prev) / (_gap - _prevGap); };
            if (_next <= _lo || {_next >= _hi}) then { _next = (_lo + _hi) / 2; };
        };
        _prev = _t;
        _prevGap = _gap;
        _t = _next;
    };
    _feasible = _settled;
    _timeToGo = _t;
};

private _track = [_targetPos, _targetVelocity, _targetAcceleration];

if (_feasible) then {
    [_timeToGo] call _fnSolveAt;
    if ([_interceptDistance, _timeToGo] call _fnOutOfReach) then { _feasible = false; };
};
if (!_feasible) exitWith { [_targetPos, false, -1, _interceptDistance, _track, _targetPos, [0, 0, _origin]] };

[_aimPoint, true, _timeToGo, _interceptDistance, _track, _interceptPoint, _turn]
