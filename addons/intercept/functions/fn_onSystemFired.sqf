/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_onSystemFired

Description:
    Body of the single persistent "Fired" event handler every AEGIS-M System
    vehicle gets (added lazily by aegism_intercept_fnc_fireWeapon). It must
    live on the VEHICLE: a unit's own "Fired" event never triggers for a
    vehicle-mounted weapon.

    aegism_intercept_fnc_fireWeapon writes a capture context on the firing
    TURRET ("capture" in aegism_intercept_fnc_turretState: [target, role,
    interceptors, expiresAt, targetIsMunition, turretPath, weapon]) and this
    handler consumes it for the rounds that turret actually produces. The
    turret is found from the Fired event's gunner; if that doesn't lead to a
    context for this weapon, the turret whose context names this weapon.
    (Contexts used to be keyed by weapon class alone, so two turrets with
    the same weapon took each other's rounds.)
        launcher - exactly one round per fire command: the missile is given
            its target (setMissileTarget -- without it a missile fired by
            script has no lock and flies unguided or seeks whatever its
            seeker finds), recorded in the assignment's interceptors list
            (so aegism_intercept_fnc_assignEngagements can tell "still in
            flight" from "missed"), and handed to its proximity fuse
            (aegism_intercept_fnc_interceptorPFH). Context cleared after.
        ciws - every round of the burst, until the context expires, goes to
            the gun's round tracker (aegism_intercept_fnc_ciwsRounds): fuzed
            against a MUNITION target, and every AEGISM_SPOT_EVERY-th round
            measured for spotting against the track it was aimed with. A
            round against an aircraft that isn't spotted isn't tracked at all
            (the engine's own collision handles the hit).

    Rounds from other weapons, or after the context expired, are ignored.

Parameters:
    _vehicle - the firing System vehicle <OBJECT>
    _weapon - fired weapon class <STRING>
    _projectile - the fired projectile <OBJECT>
    _gunner - the Fired event's gunner <OBJECT>

Returns:
    Nothing

Examples:
    [_vehicle, _weapon, _projectile, _gunner] call aegism_intercept_fnc_onSystemFired;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Rounds measured for spotting: one in this many. A burst still gives the
// estimator dozens of samples.
#define AEGISM_SPOT_EVERY 3

params ["_vehicle", "_weapon", "_projectile", ["_gunner", objNull]];

if (isNull _projectile) exitWith {};
private _turrets = _vehicle getVariable "AEGISM_turrets";
if (isNil "_turrets") exitWith {};

private _ts = createHashMap;
private _context = [];
if (!isNull _gunner) then {
    private _gunnerTurret = _turrets getOrDefault [_vehicle unitTurret _gunner, createHashMap];
    private _candidate = _gunnerTurret getOrDefault ["capture", []];
    if ((_candidate param [6, ""]) == _weapon) then { _ts = _gunnerTurret; _context = _candidate; };
};
if (_context isEqualTo []) then {
    {
        private _candidate = _y getOrDefault ["capture", []];
        if ((_candidate param [6, ""]) == _weapon) exitWith { _ts = _y; _context = _candidate; };
    } forEach _turrets;
};
if (_context isEqualTo []) exitWith {};
_context params ["_target", "_role", "_interceptors", "_expiresAt", "_targetIsMunition", "_turretPath"];

if (time > _expiresAt) exitWith { _ts deleteAt "capture"; };

// The Site's going-live alarm lasts a while after its last shot (aegism_
// network_fnc_siteAlarm).
private _site = _vehicle getVariable ["AEGISM_network", objNull];
if (!isNull _site) then { _site setVariable ["AEGISM_lastShotAt", time]; };

if (_role == "launcher") exitWith {
    _ts deleteAt "capture";
    if (!isNull _target && {alive _target}) then {
        _projectile setMissileTarget _target;
    };
    _interceptors pushBack _projectile;
    [_projectile, _target] call aegism_intercept_fnc_interceptorPFH;
};

if (isNull _target || {!alive _target}) exitWith {};
private _seq = (_ts getOrDefault ["spotSeq", 0]) + 1;
_ts set ["spotSeq", _seq];
private _spot = _seq % AEGISM_SPOT_EVERY == 0;
if (!_targetIsMunition && {!_spot}) exitWith {};
[_vehicle, _turretPath, _ts, _projectile, _target, _targetIsMunition, _spot] call aegism_intercept_fnc_ciwsRounds;
