/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_detonateCopy

Description:
    Sets off this machine's copy of a projectile the server has just set
    off (aegism_detect_fnc_detonate).
    Full notes: docs/functions/detection.md

Parameters:
    _projectile - the projectile, if it reached this machine (objNull for
        one each machine flies its own copy of) <OBJECT>
    _ammo - its ammo class <STRING>
    _shooter - the vehicle that fired it, or objNull <OBJECT>
    _at - where the server's copy was, ASL <ARRAY>
    _velocity - its velocity there <ARRAY>
    _sentAt - when, CBA_missionTime <NUMBER>
    _dropPayload - also delete what it releases <BOOLEAN, default false>

Returns:
    Nothing

Examples:
    [_rocket, "R_230mm_HE", _sandstorm, _at, _velocity, CBA_missionTime, true] remoteExecCall ["aegism_detect_fnc_detonateCopy", -2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// The most of the message's delay counted, s.
#define AEGISM_COPY_MAX_LAG 0.5
// How near where it should be a copy is taken at once: this many metres,
// plus this many seconds of its flight (see notes).
#define AEGISM_COPY_NEAR 30
#define AEGISM_COPY_NEAR_TIME 0.1
// Failing that, the nearest anywhere on the wider stretch of its path:
// seconds of its flight behind and ahead, and metres off it.
#define AEGISM_COPY_SLACK 0.25
#define AEGISM_COPY_TOLERANCE 40

params ["_projectile", "_ammo", "_shooter", "_at", "_velocity", "_sentAt", ["_dropPayload", false]];

// The server's own copy is already set off (a hosted game's host).
if (isServer) exitWith {};

if (isNull _projectile) then {
    // Flown by every machine for itself: this machine's own copy of that
    // ammo, from the same shooter, not already set off by an earlier
    // message.
    private _copies = ((missionNamespace getVariable ["AEGISM_munitionCopies", createHashMap]) getOrDefault [_ammo, []]) select {
        !isNull _x && {alive _x} && {!(_x getVariable ["AEGISM_detonated", false])} && {
            private _parent = (getShotParents _x) param [0, objNull];
            isNull _shooter || {isNull _parent} || {_parent == _shooter}
        }
    };
    private _lag = ((CBA_missionTime - _sentAt) max 0) min AEGISM_COPY_MAX_LAG;
    // Where it should be here: where the server's was -- the shot reached
    // this machine as late as the message did -- or, on the machine that
    // fired it, a round trip further on, since its copy left first.
    private _expected = if (!isNull _shooter && {local _shooter}) then { _at vectorAdd (_velocity vectorMultiply (2 * _lag)) } else { _at };
    // The nearest to that, if near enough: of a salvo's rounds along one
    // path, the one the server set off.
    private _best = AEGISM_COPY_NEAR + AEGISM_COPY_NEAR_TIME * (vectorMagnitude _velocity);
    {
        private _miss = (getPosASL _x) vectorDistance _expected;
        if (_miss < _best) then { _best = _miss; _projectile = _x; };
    } forEach _copies;
    // Else, so that none flies on: the nearest to it anywhere on the wider
    // stretch of its path.
    if (isNull _projectile) then {
        private _from = _at vectorDiff (_velocity vectorMultiply AEGISM_COPY_SLACK);
        private _span = _velocity vectorMultiply (2 * (_lag + AEGISM_COPY_SLACK));
        private _spanSq = _span vectorDotProduct _span;
        _best = 1e10;
        {
            private _rel = (getPosASL _x) vectorDiff _from;
            private _along = if (_spanSq > 0) then { 0 max (1 min ((_rel vectorDotProduct _span) / _spanSq)) } else { 0 };
            if ((vectorMagnitude (_rel vectorDiff (_span vectorMultiply _along))) <= AEGISM_COPY_TOLERANCE) then {
                private _miss = (getPosASL _x) vectorDistance _expected;
                if (_miss < _best) then { _best = _miss; _projectile = _x; };
            };
        } forEach _copies;
    };
} else {
    // One the network carries: only the machine it's local to sets it off.
    if (!local _projectile) then { _projectile = objNull; };
};
if (isNull _projectile || {!alive _projectile}) exitWith {};
_projectile setVariable ["AEGISM_detonated", true];

if (_dropPayload) then {
    _projectile setVariable ["AEGISM_intercepted", true];
    _projectile addEventHandler ["SubmunitionCreated", {
        params ["", "_submunitionProjectile"];
        deleteVehicle _submunitionProjectile;
    }];
};
triggerAmmo _projectile;
