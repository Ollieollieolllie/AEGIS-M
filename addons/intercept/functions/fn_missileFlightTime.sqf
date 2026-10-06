/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileFlightTime

Description:
    Seconds a launcher's missile flies toward a point a given distance away,
    on its flight simulated from config (aegism_intercept_fnc_
    missileProfile), scaled by how fast it has really flown this mission
    (aegism_intercept_fnc_recordMissileSpeed) -- until it gets there, or
    until its lifetime (CfgAmmo timeToLive) runs out if that's sooner. The
    same flight aegism_intercept_fnc_computeLeadPoint solves with.

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
_weaponInfo params ["", "_weaponClass", "_magazineClass"];

private _time = [[_weaponClass, _magazineClass] call aegism_intercept_fnc_missileProfile, "time", _distance] call aegism_intercept_fnc_missileProfileAt;
if (_time < 0) exitWith { -1 };
// How fast it has really flown this mission (aegism_intercept_fnc_
// recordMissileSpeed): 1 until measured.
_time = _time * (((missionNamespace getVariable ["AEGISM_missileSpeed", createHashMap]) getOrDefault [_weaponClass + "|" + _magazineClass, [[], 1]]) select 1);
private _lifetime = ([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 7;
if (_lifetime > 0) then { _time = _time min _lifetime; };
_time
