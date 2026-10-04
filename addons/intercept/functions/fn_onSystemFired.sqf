/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_onSystemFired

Description:
    Body of the single persistent "Fired" event handler every AEGIS-M System
    vehicle gets (added lazily by aegism_intercept_fnc_fireWeapon). It must
    live on the VEHICLE: a unit's own "Fired" event never triggers for a
    vehicle-mounted weapon.

    aegism_intercept_fnc_fireWeapon writes a capture context on the firing
    TURRET ("capture" in aegism_intercept_fnc_turretState: [target, role,
    interceptors, expiresAt, targetIsMunition, turretPath, weapon, launch
    plan [off-bore deg, predicted flight s, fired at]]) and this
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
            (aegism_intercept_fnc_interceptorPFH), with its launch plan for
            the turn measurement. Context cleared after.
        ciws - every round of the burst, until the context expires, goes to
            the gun's round tracker (aegism_intercept_fnc_ciwsRounds): fuzed
            against a MUNITION target, and every AEGISM_SPOT_EVERY-th round
            measured for spotting against the track it was aimed with. A
            round against an aircraft that isn't spotted isn't tracked at all
            (the engine's own collision handles the hit). With Self-Destruct
            Rounds on, every round also goes to its gun's self-destruct
            queue (aegism_intercept_fnc_ciwsSelfDestruct).

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
// No fire command from AEGIS-M for this weapon: the crew fired by itself
// (its gunner ordered to lock an aircraft, aegism_intercept_fnc_gunnerLock,
// mustn't make it shoot). Logged once per vehicle and weapon.
if (_context isEqualTo []) exitWith {
    private _logKey = "AEGISM_uncommandedLogged_" + _weapon;
    if !(_vehicle getVariable [_logKey, false]) then {
        _vehicle setVariable [_logKey, true];
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " UNCOMMANDED-FIRE: %1 fired %2 (%3) with no AEGIS-M fire command -- its crew's own AI fired.", _vehicle, _weapon, typeOf _projectile];
    };
};
_context params ["_target", "_role", "_interceptors", "_expiresAt", "_targetIsMunition", "_turretPath", "", ["_launch", []]];

if (time > _expiresAt) exitWith { _ts deleteAt "capture"; };

// The Site's going-live alarm lasts a while after its last shot (aegism_
// network_fnc_siteAlarm), and its crews are in combat meanwhile (aegism_
// intercept_fnc_engagementLoop) -- a vehicle with no Site by its own. Every
// Site of a linked group (aegism_network_fnc_linkSites) goes live together.
_vehicle setVariable ["AEGISM_lastShotAt", time];
private _site = _vehicle getVariable ["AEGISM_network", objNull];
if (!isNull _site) then {
    { _x setVariable ["AEGISM_lastShotAt", time]; } forEach (_site getVariable ["AEGISM_linkSites", [_site]]);
};

if (_role == "launcher") exitWith {
    _ts deleteAt "capture";
    // Forced: set even if the target is outside the missile's own seeker
    // cone as it leaves (an off-bore launch turns onto it).
    if (!isNull _target && {alive _target}) then {
        _projectile setMissileTarget [_target, true];
    };
    _interceptors pushBack _projectile;
    [_projectile, _target, _launch] call aegism_intercept_fnc_interceptorPFH;
};

// Every round of the burst, whatever it's aimed at (Self-Destruct Rounds).
if ((_vehicle getVariable ["AEGISM_resolvedEngagementSettings", createHashMap]) getOrDefault ["ciwsSelfDestruct", false]) then {
    [_vehicle, _turretPath, _ts, _projectile, _weapon] call aegism_intercept_fnc_ciwsSelfDestruct;
};

if (isNull _target || {!alive _target}) exitWith {};
private _seq = (_ts getOrDefault ["spotSeq", 0]) + 1;
_ts set ["spotSeq", _seq];
private _spot = _seq % AEGISM_SPOT_EVERY == 0;
if (!_targetIsMunition && {!_spot}) exitWith {};
[_vehicle, _turretPath, _ts, _projectile, _target, _targetIsMunition, _spot] call aegism_intercept_fnc_ciwsRounds;
