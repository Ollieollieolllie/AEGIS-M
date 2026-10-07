/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileFlightTime

Description:
    Seconds a launcher's missile flies toward a point a given distance away,
    on its learned or simulated speed curve.
    Full notes: docs/functions/intercept.md

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
private _lifetime = ([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 7;
if (_lifetime > 0) then { _time = _time min _lifetime; };
_time
