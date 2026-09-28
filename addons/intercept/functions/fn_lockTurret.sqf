/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_lockTurret

Description:
    Points one specific turret of a vehicle at an ASL position, or hands it
    back to its crew, with lockCameraTo -- the same command ACE's Hunter-
    Killer uses to slew a gunner's turret (ace_hunterkiller_fnc_slew:
    "_vehicle lockCameraTo [_posASL, _turret, true]"; released with objNull,
    as ace_aircraft does).

    Replaces lookAt, which is an order to a UNIT: given the vehicle it goes
    to the effective commander, so on a crewed vehicle like the Cheetah only
    the commander's optic traversed and the main gun never moved.
    lockCameraTo addresses the turret by its path, whoever crews it.

    The lock is PERSISTENT (temporary = false) and released explicitly
    (objNull, by aegism_intercept_fnc_engagementLoop). ACE passes temporary
    = true because its gunner is usually a player who should be able to take
    the turret back; here the gunner is AI, and with temporary = true SAM
    turrets sat 30-60 degrees off their assigned target for 15s at a time --
    apparently the crew's own aiming reclaiming the turret.

    lockCameraTo must run where the turret is local (ACE routes it with
    CBA_fnc_turretEvent). The engagement loops run on the server, where AI
    crews normally are; a turret owned elsewhere (headless client, player
    gunner) gets the command sent to its owner.

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
