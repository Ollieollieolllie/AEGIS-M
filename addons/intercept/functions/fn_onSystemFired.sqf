/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_onSystemFired

Description:
    Body of the single persistent "Fired" event handler every AEGIS-M System
    vehicle gets (added lazily by aegism_intercept_fnc_fireWeapon). It must
    live on the VEHICLE: a unit's own "Fired" event never triggers for a
    vehicle-mounted weapon, which is why the old per-gunner capture handler
    never fired at all -- no interceptor was ever tracked or proximity-fuzed.

    aegism_intercept_fnc_fireWeapon writes a capture context for the weapon
    it is about to fire ("AEGISM_capture_<weapon>" = [target, role,
    interceptors, expiresAt, targetIsMunition, turretPath]) and this handler
    consumes it for the rounds
    that weapon actually produces:
        launcher - exactly one round per fire command: the missile is given
            its target (setMissileTarget -- without it a vanilla missile
            fired by script has no lock and flies unguided or seeks whatever
            its seeker finds), recorded in the assignment's interceptors
            list (so aegism_intercept_fnc_assignEngagements can tell "still
            in flight" from "missed"), and handed to the proximity fuse
            (aegism_intercept_fnc_interceptorPFH). Context cleared after.
        ciws - every round of the burst, until the context expires, gets the
            tracker: fuzed only against a MUNITION target (projectile-vs-
            projectile hits don't exist in the engine, while an aircraft is
            hit by normal collision), and spotted against any target -- its
            miss from the target's PREDICTED track (the one it was aimed
            with) feeds the gun's aim correction (aegism_intercept_fnc_
            ciwsSpot), with the burst it belongs to and the correction it
            was aimed with.

    Rounds from other weapons, or after the context expired, are ignored.

Parameters:
    _vehicle - the firing System vehicle <OBJECT>
    _weapon - fired weapon class <STRING>
    _projectile - the fired projectile <OBJECT>

Returns:
    Nothing

Examples:
    [_vehicle, _weapon, _projectile] call aegism_intercept_fnc_onSystemFired;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle", "_weapon", "_projectile"];

private _key = format ["AEGISM_capture_%1", _weapon];
private _context = _vehicle getVariable _key;
if (isNil "_context") exitWith {};
_context params ["_target", "_role", "_interceptors", "_expiresAt", "_targetIsMunition", ["_turretPath", []]];

if (time > _expiresAt) exitWith {
    _vehicle setVariable [_key, nil, false];
};
if (isNull _projectile) exitWith {};

if (_role == "launcher") exitWith {
    _vehicle setVariable [_key, nil, false];
    if (!isNull _target && {alive _target}) then {
        _projectile setMissileTarget _target;
    };
    _interceptors pushBack _projectile;
    [_projectile, _target] call aegism_intercept_fnc_interceptorPFH;
};

if (isNull _target || {!alive _target}) exitWith {};
private _burstId = (_vehicle getVariable [format ["AEGISM_ciwsBurst_%1", _turretPath], [0, objNull, 0]]) select 2;
private _correction = +(_vehicle getVariable [format ["AEGISM_ciwsCorrection_%1", _turretPath], [0, 0]]);
// The track the aim predicted the target would fly (aegism_intercept_fnc_
// aimWeapon, refreshed every frame of the burst): the round is spotted
// against it, not against the target itself.
private _track = _vehicle getVariable [format ["AEGISM_ciwsTrack_%1", _turretPath], []];
if (_track isEqualTo []) exitWith {
    if (_targetIsMunition) then { [_projectile, _target] call aegism_intercept_fnc_interceptorPFH; };
};
[_projectile, _target, [_vehicle, _turretPath, _burstId, _correction, _track, typeOf _projectile]] call aegism_intercept_fnc_interceptorPFH;
