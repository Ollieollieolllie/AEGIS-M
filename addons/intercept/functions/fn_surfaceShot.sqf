/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_surfaceShot

Description:
    Whether a weapon has a shot at a point on the ground, and where its
    turret has to point for it: a launcher's missile is lofted onto the
    point, a gun's rounds are sent on their own ballistic path to it.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the firing vehicle <OBJECT>
    _role - "launcher" or "ciws" <STRING>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _aimPos - the point, ASL <ARRAY>

Returns:
    [it has a shot <BOOLEAN>, why not <STRING>, where to point the turret
     ASL <ARRAY>, flight time s <NUMBER>, distance m <NUMBER>]

Examples:
    [_patriot, "launcher", _weaponInfo, AGLToASL _position] call aegism_intercept_fnc_surfaceShot;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\strike.hpp"

params ["_system", "_role", "_weaponInfo", "_aimPos"];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass", "", "", ["_weaponMax", 0]];

if (isNull _system || {!alive _system}) exitWith { [false, "the vehicle is lost", [], 0, 0] };
if ((_system magazineTurretAmmo [_magazineClass, _turretPath]) <= 0) exitWith { [false, "nothing left to fire", [], 0, 0] };

private _settings = _system getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_settings") then { _settings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
private _origin = ([_system, _turretPath, _role] call aegism_intercept_fnc_turretPoints) select 0;
private _distance = _origin distance _aimPos;

if (_role == "launcher") exitWith {
    // Guided only: an unguided rocket can't be brought down onto a point.
    // And not the small ones (strike.hpp): a Stinger's warhead is for an
    // aircraft, and the user doesn't want it offered against the ground.
    private _kinematics = [_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics;
    if !(_kinematics param [10, false]) exitWith { [false, "its missile isn't guided", [], 0, _distance] };
    private _blast = _kinematics param [11, 0];
    if (_blast < AEGISM_STRIKE_MIN_BLAST) exitWith {
        [false, format ["its warhead is too small for the ground (%1m blast, under %2m)", _blast, AEGISM_STRIKE_MIN_BLAST], [], 0, _distance]
    };
    // Nor one fired to lock on after launch that ACE's guidance doesn't
    // fly (the MIM-145 without ACE): the game doesn't send it to a point
    // (aegism_intercept_fnc_lockAfterLaunch).
    if (([_weaponClass, _magazineClass] call aegism_intercept_fnc_lockAfterLaunch) select 0) exitWith {
        [false, "its missile locks on after launch: only a guidance mod (ACE) can send it to a point", [], 0, _distance]
    };
    ([_settings, _weaponInfo, "launcher"] call aegism_intercept_fnc_envelopeBounds) params ["_minRange", "_maxRange"];
    if (_maxRange > 0 && {_distance > _maxRange}) exitWith { [false, format ["beyond reach (%1m of %2m)", round _distance, round _maxRange], [], 0, _distance] };
    private _closest = _minRange max AEGISM_STRIKE_MIN_RANGE;
    if (_distance < _closest) exitWith { [false, format ["too close (%1m, under %2m)", round _distance, round _closest], [], 0, _distance] };

    // It leaves toward the point it's first sent for (aegism_intercept_fnc_
    // strikeMissile): above the aim point by the loft. A turret that can't
    // point there launches as close as it gets, and the missile turns.
    private _first = _aimPos vectorAdd [0, 0, AEGISM_STRIKE_LOFT_AT(_origin distance2D _aimPos)];
    private _direction = _origin vectorFromTo _first;
    ([_system, _turretPath, _direction] call aegism_intercept_fnc_turretCanPoint) params ["_canPoint", "", "", "", ["_reachable", []]];
    if (!_canPoint && {_reachable isEqualType []} && {count _reachable == 3}) then { _direction = _reachable; };
    // (Its path is longer than the straight line by about the loft.)
    private _flight = [_weaponInfo, _distance * (1 + 0.5 * AEGISM_STRIKE_LOFT * AEGISM_STRIKE_LOFT)] call aegism_intercept_fnc_missileFlightTime;
    [true, "", _origin vectorAdd (_direction vectorMultiply 2000), _flight max 0, _distance]
};

// --- A gun ----------------------------------------------------------------------
if (_weaponMax > 0 && {_distance > _weaponMax}) exitWith { [false, format ["beyond reach (%1m of %2m)", round _distance, round _weaponMax], [], 0, _distance] };

// Its own aim, as against anything else (aegism_intercept_fnc_computeLead
// Point: the round's flight with its drag, and the drop over it), on an
// object standing at the point: one of the server's own, moved there.
private _probe = missionNamespace getVariable ["AEGISM_surfaceProbe", objNull];
if (isNull _probe) then {
    _probe = "Land_HelipadEmpty_F" createVehicleLocal [0, 0, 0];
    missionNamespace setVariable ["AEGISM_surfaceProbe", _probe];
};
_probe setPosASL _aimPos;
([_system, _origin, _probe, _weaponInfo, "ciws", false, 0, false, 0] call aegism_intercept_fnc_computeLeadPoint) params ["_aimPoint", "_feasible", "_flightTime"];
if (!_feasible) exitWith { [false, format ["no ballistic solution (%1m)", round _distance], [], 0, _distance] };

([_system, _turretPath, _origin vectorFromTo _aimPoint] call aegism_intercept_fnc_turretCanPoint) params ["_canPoint", "_aimElevation", "_minElevation", "_maxElevation"];
if (!_canPoint) exitWith {
    [false, format ["beyond the turret's limits (aim %1 deg elevation; turret %2 to %3 deg)", round _aimElevation, _minElevation, _maxElevation], [], 0, _distance]
};

// A line to it clear of the ground: its rounds fly nearly flat. Only the
// ground counts -- trees and buildings are shot through or into, as the
// user wants it -- and ground within AEGISM_STRIKE_LOS_SLACK of the point
// is the point itself.
private _ground = terrainIntersectAtASL [_origin, _aimPos vectorAdd [0, 0, 1]];
if (_ground isNotEqualTo [0, 0, 0] && {(_ground distance _aimPos) > AEGISM_STRIKE_LOS_SLACK}) exitWith {
    [false, format ["no line of fire (the ground is in the way %1m short of it)", round (_ground distance _aimPos)], [], 0, _distance]
};

[true, "", _aimPoint, _flightTime max 0, _distance]
