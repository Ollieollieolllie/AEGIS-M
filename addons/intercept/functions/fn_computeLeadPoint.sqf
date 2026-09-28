/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_computeLeadPoint

Description:
    Computes where to aim an unguided CIWS gun so its round and the target
    arrive at the same point: the target's projected position after the
    round's time of flight, raised by the round's gravity drop.

    Adapted from the zero-effort-miss idea (project the target forward by
    time-to-go) as a one-shot aim solution rather than ACE3's continuous
    in-flight steering law, which only applies to a steerable missile.

    All physics comes from real config:
        muzzle velocity - CfgMagazines initSpeed, overridden per engine rules
            by CfgWeapons initSpeed (> 0 replaces it, < 0 multiplies it by
            its absolute value). An earlier version read initSpeed from
            CfgAmmo, where it doesn't exist, so this function silently
            returned the raw target position for every shot (visible in the
            RPT as "lead offset from raw target=0m").
        drag - CfgAmmo airFriction (negative). Arma bullet drag decelerates
            at |k|v^2, giving v(t) = v0 / (1 + |k| v0 t) and distance
            s(t) = ln(1 + |k| v0 t) / |k|, so the time to cover distance d
            is t = (exp(|k| d) - 1) / (|k| v0). For the 35mm AA round
            (k = -0.0005, v0 = 1440) at 2km that's 2.39s, versus 1.39s if
            drag were ignored -- the difference between hitting and missing.

    Target acceleration is measured from successive velocity samples cached
    on the target per firing System (SQF has no acceleration command). A
    sample closer than AEGISM_LEAD_MIN_SAMPLE_DT to the previous one reuses
    the last estimate rather than dividing by a near-zero interval; one
    older than AEGISM_LEAD_MAX_SAMPLE_DT is discarded as stale (the target
    was out of engagement for a while).

Parameters:
    _system - the firing System vehicle (keys the acceleration sample) <OBJECT>
    _gunPos - ASL position the round is fired from <ARRAY>
    _target - the target object <OBJECT>
    _weaponClass - CfgWeapons class of the gun <STRING>
    _magazineClass - CfgMagazines class loaded <STRING>

Returns:
    PositionASL of the aim point <ARRAY>

Examples:
    [_cheetah, eyePos gunner _cheetah, _heli, "autocannon_35mm", "680Rnd_35mm_AA_shells"] call aegism_intercept_fnc_computeLeadPoint;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_LEAD_SOLVE_ITERATIONS 3
#define AEGISM_GRAVITY 9.81
#define AEGISM_LEAD_MIN_SAMPLE_DT 0.05
#define AEGISM_LEAD_MAX_SAMPLE_DT 2

params ["_system", "_gunPos", "_target", "_weaponClass", "_magazineClass"];

private _targetPos = getPosASLVisual _target;

private _muzzleVelocity = getNumber (configFile >> "CfgMagazines" >> _magazineClass >> "initSpeed");
private _weaponSpeed = getNumber (configFile >> "CfgWeapons" >> _weaponClass >> "initSpeed");
if (_weaponSpeed > 0) then { _muzzleVelocity = _weaponSpeed; };
if (_weaponSpeed < 0) then { _muzzleVelocity = _muzzleVelocity * (abs _weaponSpeed); };
if (_muzzleVelocity <= 0) exitWith { _targetPos };

private _ammoClass = getText (configFile >> "CfgMagazines" >> _magazineClass >> "ammo");
private _drag = abs ((getNumber (configFile >> "CfgAmmo" >> _ammoClass >> "airFriction")) min 0);

private _fnTimeOfFlight = {
    params ["_distance", "_v0", "_k"];
    if (_k <= 0) exitWith { _distance / _v0 };
    ((exp (_k * _distance)) - 1) / (_k * _v0)
};

private _targetVelocity = velocity _target;

private _sampleKey = format ["AEGISM_leadSample_%1", netId _system];
private _sample = _target getVariable [_sampleKey, []];
private _targetAcceleration = [0, 0, 0];
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

private _timeToGo = [_gunPos distance _targetPos, _muzzleVelocity, _drag] call _fnTimeOfFlight;
private _projectedPos = _targetPos;
for "_i" from 1 to AEGISM_LEAD_SOLVE_ITERATIONS do {
    _projectedPos = _targetPos
        vectorAdd (_targetVelocity vectorMultiply _timeToGo)
        vectorAdd (_targetAcceleration vectorMultiply (0.5 * _timeToGo * _timeToGo));
    _timeToGo = [_gunPos distance _projectedPos, _muzzleVelocity, _drag] call _fnTimeOfFlight;
};

_projectedPos vectorAdd [0, 0, 0.5 * AEGISM_GRAVITY * _timeToGo * _timeToGo]
