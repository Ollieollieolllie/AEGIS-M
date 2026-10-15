/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_projectileCopy

Description:
    Every machine but the server: its "ProjectileCreated" mission event.
    Keeps a list of its own copies of the munitions the server may set off,
    and bursts an AEGIS-M gun's rounds on the server's fuze time.
    Full notes: docs/functions/detection.md

Parameters:
    _projectile - the new projectile <OBJECT>

Returns:
    Nothing

Examples:
    addMissionEventHandler ["ProjectileCreated", { _this call aegism_detect_fnc_projectileCopy; }];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// A class's list is cleared of the gone at this many.
#define AEGISM_COPIES_PRUNE_AT 24

params ["_projectile"];

if (isNull _projectile) exitWith {};
private _ammo = typeOf _projectile;
([_ammo] call aegism_detect_fnc_ammoThreatInfo) params ["_class", "_isCarrier"];

// Not a munition AEGIS-M tracks: a round of an AEGIS-M gun with Self-
// Destruct Rounds bursts at the same age as the server's copy (aegism_
// intercept_fnc_ciwsSelfDestruct publishes the fuze per vehicle and ammo).
if (_class == "" && {!_isCarrier}) exitWith {
    if !(missionNamespace getVariable ["AEGISM_selfDestructOn", false]) exitWith {};
    private _fuzes = ((getShotParents _projectile) param [0, objNull]) getVariable ["AEGISM_selfDestructFuzes", []];
    if (_fuzes isEqualTo []) exitWith {};
    private _index = _fuzes findIf { (_x select 0) == _ammo };
    if (_index == -1) exitWith {};
    [{
        if (!isNull _this && {alive _this}) then { triggerAmmo _this; };
    }, _projectile, (_fuzes select _index) select 1] call CBA_fnc_waitAndExecute;
};

private _all = missionNamespace getVariable "AEGISM_munitionCopies";
if (isNil "_all") then {
    _all = createHashMap;
    missionNamespace setVariable ["AEGISM_munitionCopies", _all];
};
private _copies = _all getOrDefault [_ammo, []];
if (count _copies >= AEGISM_COPIES_PRUNE_AT) then { _copies = _copies select { !isNull _x && {alive _x} }; };
_copies pushBackUnique _projectile;
_all set [_ammo, _copies];

// What a carrier releases, in case this machine's mission event doesn't
// report it (one set off by the server has its own deleted, aegism_detect_
// fnc_detonateCopy).
if (_isCarrier) then {
    _projectile addEventHandler ["SubmunitionCreated", {
        params ["_projectile", "_submunitionProjectile"];
        if (_projectile getVariable ["AEGISM_intercepted", false]) exitWith {};
        [_submunitionProjectile] call aegism_detect_fnc_projectileCopy;
    }];
};
