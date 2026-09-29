/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_computeLeadPoint

Description:
    Intercept solution for one weapon against one target: where to point so
    the round/missile and the target arrive at the same place, and whether
    that is possible at all.

    The target is projected forward by the weapon's time of flight to the
    projected point (velocity plus measured acceleration, zero-effort-miss
    style), iterated to convergence. All kinematics come from real config,
    read once per weapon + magazine (aegism_intercept_fnc_weaponKinematics):

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
        missile (launcher) - CfgMagazines initSpeed at launch, then CfgAmmo
            thrust (m/s^2) until CfgAmmo maxSpeed or thrustTime, then that
            speed (e.g. MIM-145: 45 m/s, +450 m/s^2, 850 m/s). No drop: the
            missile is guided. Pointing the launcher at this point instead of
            the target's current position saves the missile a hard turn
            right off the rail.

    FEASIBLE only if the solution converges inside the weapon's own reach
    (weaponInfo maxRange, from config) and within the round's own lifetime
    (CfgAmmo timeToLive, e.g. 6s for vanilla bullets). A target receding
    faster than the round can close -- a jet flying away from a gun -- has
    no solution: the projected point runs off to infinity. The previous
    version didn't check this and iterated to NaN (RPT "Error Type Not a
    Number" in this file), and CIWS kept firing at targets it could never
    reach. An infeasible solution returns the target's current position as
    the aim point.

    Target acceleration is measured from successive velocity samples cached
    on the target per firing System (SQF has no acceleration command); pass
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

Returns:
    [aimPoint ASL <ARRAY>, feasible <BOOLEAN>, timeOfFlight s <NUMBER>
     (-1 if infeasible), interceptDistance m <NUMBER>, predicted track
     [position ASL, velocity, acceleration] the target was projected from
     <ARRAY> -- CIWS spotting replays it (aegism_intercept_fnc_ciwsSpot),
     interceptPoint ASL: where the target is met (the aim point before the
     gun's drop is added) <ARRAY>]

Examples:
    [_cheetah, eyePos gunner _cheetah, _heli, _weaponInfo, "ciws"] call aegism_intercept_fnc_computeLeadPoint;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_LEAD_SOLVE_ITERATIONS 5
#define AEGISM_GRAVITY 9.80665
#define AEGISM_LEAD_MIN_SAMPLE_DT 0.05
#define AEGISM_LEAD_MAX_SAMPLE_DT 2
// exp() argument above which a gun's drag makes the flight time absurd
// (e^30 ~ 1e13) -- treated as "can't get there" rather than overflowing.
#define AEGISM_MAX_DRAG_EXPONENT 30

params ["_system", "_origin", "_target", "_weaponInfo", "_role", ["_useAcceleration", true], ["_delay", 0], ["_ballistic", false], ["_leadBias", 0]];
_weaponInfo params ["", "_weaponClass", "_magazineClass", "", "", ["_maxRange", 0]];

private _targetPos = getPosASLVisual _target;
private _currentDistance = _origin distance _targetPos;

private _isGun = _role == "ciws";

// Kinematics, declared at this scope: the time-of-flight code below is
// called later from here, and SQF code only sees variables that still exist
// in the scope it's called from.
([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics)
    params ["", "_v0", "_k", "_thrust", "_burnSpeed", "_accelTime", "_accelDist", "_maxTime"];

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
        if (_burnSpeed <= 0) exitWith { -1 };
        if (_thrust > 0 && {_d <= _accelDist}) exitWith { ((sqrt (_v0 * _v0 + 2 * _thrust * _d)) - _v0) / _thrust };
        _accelTime + (_d - _accelDist) / _burnSpeed
    }
};

// No usable speed data in config (e.g. a mod weapon with neither initSpeed
// nor thrust): nothing to predict with, so aim at the target and don't
// block the engagement -- the old behaviour -- rather than calling every
// target unreachable.
if ((_isGun && {_v0 <= 0}) || {!_isGun && {_burnSpeed <= 0}}) exitWith { [_targetPos, true, -1, _currentDistance, [_targetPos, velocity _target, [0, 0, 0]], _targetPos] };

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
        private _dt = time - _prevTime;
        switch (true) do {
            case (_dt < AEGISM_LEAD_MIN_SAMPLE_DT): { _targetAcceleration = _prevAccel; };
            case (_dt > AEGISM_LEAD_MAX_SAMPLE_DT): { _targetAcceleration = [0, 0, 0]; };
            default { _targetAcceleration = (_targetVelocity vectorDiff _prevVelocity) vectorMultiply (1 / _dt); };
        };
        if (_dt >= AEGISM_LEAD_MIN_SAMPLE_DT) then {
            _target setVariable [_sampleKey, [_targetVelocity, time, _targetAcceleration], false];
        };
    } else {
        _target setVariable [_sampleKey, [_targetVelocity, time, [0, 0, 0]], false];
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

private _timeToGo = [_currentDistance] call _fnTimeOfFlight;
private _interceptPoint = _targetPos;
private _interceptDistance = _currentDistance;
private _aimPoint = _targetPos;
private _feasible = !([_currentDistance, _timeToGo] call _fnOutOfReach);

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

if (_feasible) then {
    for "_i" from 1 to AEGISM_LEAD_SOLVE_ITERATIONS do {
        [_timeToGo] call _fnSolveAt;
        // The round covers the distance to the aim point along its launch
        // line (for a gun that's the raised point, see header).
        _timeToGo = [_origin distance _aimPoint] call _fnTimeOfFlight;
        if ([_interceptDistance, _timeToGo] call _fnOutOfReach) exitWith { _feasible = false; };
    };
};

private _track = [_targetPos, _targetVelocity, _targetAcceleration];

if (!_feasible) exitWith { [_targetPos, false, -1, _interceptDistance, _track, _targetPos] };

[_timeToGo] call _fnSolveAt;

[_aimPoint, true, _timeToGo, _interceptDistance, _track, _interceptPoint]
