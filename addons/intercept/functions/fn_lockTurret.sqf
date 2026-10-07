/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_lockTurret

Description:
    Points one turret of a vehicle at an ASL position with lockCameraTo, or
    hands it back to its crew.
    Full notes: docs/functions/intercept.md

Parameters:
    _vehicle - the vehicle <OBJECT>
    _turretPath - turret path, e.g. [0] <ARRAY>
    _target - ASL position to point at, or objNull to release <ARRAY, OBJECT>

Returns:
    Nothing

Examples:
    [_cheetah, [0], _leadPointASL] call aegism_intercept_fnc_lockTurret;
    [_cheetah, [0], objNull] call aegism_intercept_fnc_lockTurret;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle", "_turretPath", "_target"];

if (isNull _vehicle) exitWith {};

if (_vehicle turretLocal _turretPath) then {
    _vehicle lockCameraTo [_target, _turretPath, false];
} else {
    [_vehicle, [_target, _turretPath, false]] remoteExecCall ["lockCameraTo", _vehicle turretOwner _turretPath];
};
