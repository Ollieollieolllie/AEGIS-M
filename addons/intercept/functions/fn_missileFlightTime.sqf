/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileFlightTime

Description:
    Seconds a launcher's missile flies toward a point a given distance away,
    on its real speed profile (aegism_intercept_fnc_weaponKinematics: launch
    speed, then thrust until its top speed, then that speed) -- until it gets
    there, or until its lifetime (CfgAmmo timeToLive) runs out if that's
    sooner. The same profile aegism_intercept_fnc_computeLeadPoint solves
    with.

    Used to rule out, without solving anything, a target too far out for a
    missile to meet inside its reach: in the time the missile takes to fly to
    the edge of its reach, the target can close at most speed x t + g t^2 / 2
    (aegism_intercept_fnc_canEngage, and the Site coordinator's reserve
    plan).

Parameters:
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _distance - metres <NUMBER>

Returns:
    Seconds <NUMBER>, or -1 with no speed data in config

Examples:
    [_weaponInfo, 5000] call aegism_intercept_fnc_missileFlightTime;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_weaponInfo", "_distance"];

([_weaponInfo select 1, _weaponInfo select 2] call aegism_intercept_fnc_weaponKinematics)
    params ["", "_v0", "", "_thrust", "_burnSpeed", "_accelTime", "_accelDist", "_lifetime"];
if (_burnSpeed <= 0) exitWith { -1 };
private _time = if (_thrust > 0 && {_distance <= _accelDist}) then {
    ((sqrt (_v0 * _v0 + 2 * _thrust * _distance)) - _v0) / _thrust
} else {
    _accelTime + (_distance - _accelDist) / _burnSpeed
};
if (_lifetime > 0) then { _time = _time min _lifetime; };
_time
