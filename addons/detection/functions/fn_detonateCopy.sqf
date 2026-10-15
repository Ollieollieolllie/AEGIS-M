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

// How far behind the server's copy, and ahead of it, a copy is looked for:
// seconds of its flight (see notes).
#define AEGISM_COPY_SLACK 0.25
// The most of the message's delay counted, s.
#define AEGISM_COPY_MAX_LAG 0.5
// The farthest a copy may be off that stretch of its path, m.
#define AEGISM_COPY_TOLERANCE 40

params ["_projectile", "_ammo", "_shooter", "_at", "_velocity", "_sentAt", ["_dropPayload", false]];

// The server's own copy is already set off (a hosted game's host).
if (isServer) exitWith {};

if (isNull _projectile) then {
    // Flown by every machine for itself: this machine's own copy of that
    // ammo, from the same shooter, nearest the stretch of path where the
    // server's was -- or up to a round trip ahead of it, on the machine that
    // fired it.
    private _copies = ((missionNamespace getVariable ["AEGISM_munitionCopies", createHashMap]) getOrDefault [_ammo, []]) select { !isNull _x && {alive _x} };
    private _lag = ((CBA_missionTime - _sentAt) max 0) min AEGISM_COPY_MAX_LAG;
    private _from = _at vectorDiff (_velocity vectorMultiply AEGISM_COPY_SLACK);
    private _span = _velocity vectorMultiply (2 * (_lag + AEGISM_COPY_SLACK));
    private _spanSq = _span vectorDotProduct _span;
    private _bestMiss = AEGISM_COPY_TOLERANCE;
    {
        private _parent = (getShotParents _x) param [0, objNull];
        if (isNull _shooter || {isNull _parent} || {_parent == _shooter}) then {
            private _rel = (getPosASL _x) vectorDiff _from;
            private _along = if (_spanSq > 0) then { 0 max (1 min ((_rel vectorDotProduct _span) / _spanSq)) } else { 0 };
            private _miss = vectorMagnitude (_rel vectorDiff (_span vectorMultiply _along));
            if (_miss < _bestMiss) then {
                _bestMiss = _miss;
                _projectile = _x;
            };
        };
    } forEach _copies;
} else {
    // One the network carries: only the machine it's local to sets it off.
    if (!local _projectile) then { _projectile = objNull; };
};
if (isNull _projectile || {!alive _projectile}) exitWith {};

if (_dropPayload) then {
    _projectile setVariable ["AEGISM_intercepted", true];
    _projectile addEventHandler ["SubmunitionCreated", {
        params ["", "_submunitionProjectile"];
        deleteVehicle _submunitionProjectile;
    }];
};
triggerAmmo _projectile;
