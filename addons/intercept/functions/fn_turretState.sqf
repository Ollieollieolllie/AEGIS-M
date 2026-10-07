/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretState

Description:
    One weapon turret's runtime state: a HashMap, created on first use, kept
    in the System's "AEGISM_turrets" (turret path -> state).
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the System vehicle <OBJECT>
    _turretPath - turret path <ARRAY>

Returns:
    The turret's state <HASHMAP>

Examples:
    ([_praetorian, [0]] call aegism_intercept_fnc_turretState) get "aim_ciws";

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath"];

private _all = _system getVariable "AEGISM_turrets";
if (isNil "_all") then {
    _all = createHashMap;
    _system setVariable ["AEGISM_turrets", _all, false];
};
private _state = _all get _turretPath;
if (isNil "_state") then {
    _state = createHashMap;
    _all set [_turretPath, _state];
};
_state
