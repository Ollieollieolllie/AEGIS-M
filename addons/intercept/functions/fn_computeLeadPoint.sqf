/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_computeLeadPoint

Description:
    Intercept solution for one weapon against one target: where to point so
    the round/missile and the target arrive at the same place, and whether
    that is possible at all.

    The target is projected forward by the weapon's time of flight to the
    projected point (velocity plus measured acceleration, zero-effort-miss
    style), iterated to convergence. All kinematics come from real config:

        gun (ciws) - muzzle velocity from CfgMagazines initSpeed (overridden
            per engine rules by CfgWeapons initSpeed: > 0 replaces, < 0
            multiplies) and drag from CfgAmmo airFriction: v(t) = v0/(1 +
            |k| v0 t), so covering distance d takes (exp(|k| d) - 1)/(|k| v0).
            The aim point is raised by the round's gravity drop.
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

Parameters:
    _system - the firing System vehicle (keys the acceleration sample) <OBJECT>
    _origin - ASL position the round/missile leaves from <ARRAY>
    _target - the target object <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _role - "ciws" (gun) or "launcher" (missile) <STRING>
    _useAcceleration - optional, default true <BOOLEAN>

Returns:
    [aimPoint ASL <ARRAY>, feasible <BOOLEAN>, timeOfFlight s <NUMBER>
     (-1 if infeasible), interceptDistance m <NUMBER>]

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

params ["_system", "_origin", "_target", "_weaponInfo", "_role", ["_useAcceleration", true]];
_weaponInfo params ["", "_weaponClass", "_magazineClass", "", "", ["_maxRange", 0]];

private _targetPos = getPosASLVisual _target;
private _currentDistance = _origin distance _targetPos;

private _ammoCfg = configFile >> "CfgAmmo" >> getText (configFile >> "CfgMagazines" >> _magazineClass >> "ammo");
private _maxTime = getNumber (_ammoCfg >> "timeToLive");

private _v0 = getNumber (configFile >> "CfgMagazines" >> _magazineClass >> "initSpeed");
private _weaponSpeed = getNumber (configFile >> "CfgWeapons" >> _weaponClass >> "initSpeed");
if (_weaponSpeed > 0) then { _v0 = _weaponSpeed; };
if (_weaponSpeed < 0) then { _v0 = _v0 * (abs _weaponSpeed); };

private _isGun = _role == "ciws";

// Kinematics, declared at this scope: the time-of-flight code below is
// called later from here, and SQF code only sees variables that still exist
// in the scope it's called from.
private _k = abs ((getNumber (_ammoCfg >> "airFriction")) min 0);
private _thrust = getNumber (_ammoCfg >> "thrust");
private _maxSpeed = getNumber (_ammoCfg >> "maxSpeed");
private _burnSpeed = if (_thrust > 0) then { _v0 + _thrust * getNumber (_ammoCfg >> "thrustTime") } else { _v0 };
if (_maxSpeed > 0) then { _burnSpeed = _burnSpeed min _maxSpeed; };
private _accelTime = if (_thrust > 0) then { (_burnSpeed - _v0) / _thrust } else { 0 };
private _accelDist = _v0 * _accelTime + 0.5 * _thrust * _accelTime * _accelTime;

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
if ((_isGun && {_v0 <= 0}) || {!_isGun && {_burnSpeed <= 0}}) exitWith { [_targetPos, true, -1, _currentDistance] };

private _targetVelocity = velocity _target;
private _targetAcceleration = [0, 0, 0];
if (_useAcceleration) then {
    private _sampleKey = format ["AEGISM_leadSample_%1", netId _system];
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

private _fnOutOfReach = {
    params ["_distance", "_time"];
    _time < 0 || {_maxRange > 0 && {_distance > _maxRange}} || {_maxTime > 0 && {_time > _maxTime}}
};

private _timeToGo = [_currentDistance] call _fnTimeOfFlight;
private _interceptDistance = _currentDistance;
private _aimPoint = _targetPos;
private _feasible = !([_currentDistance, _timeToGo] call _fnOutOfReach);

if (_feasible) then {
    for "_i" from 1 to AEGISM_LEAD_SOLVE_ITERATIONS do {
        _aimPoint = _targetPos
            vectorAdd (_targetVelocity vectorMultiply _timeToGo)
            vectorAdd (_targetAcceleration vectorMultiply (0.5 * _timeToGo * _timeToGo));
        _interceptDistance = _origin distance _aimPoint;
        _timeToGo = [_interceptDistance] call _fnTimeOfFlight;
        if ([_interceptDistance, _timeToGo] call _fnOutOfReach) exitWith { _feasible = false; };
    };
};

if (!_feasible) exitWith { [_targetPos, false, -1, _interceptDistance] };

if (_isGun) then {
    _aimPoint = _aimPoint vectorAdd [0, 0, 0.5 * AEGISM_GRAVITY * _timeToGo * _timeToGo];
};

[_aimPoint, true, _timeToGo, _interceptDistance]
