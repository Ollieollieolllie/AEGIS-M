/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_fireModeStats

Description:
    The config numbers of the fire mode a turret's weapon is in right now:
    its CfgWeapons dispersion and reloadTime.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>
    _weaponClass - CfgWeapons class <STRING>

Returns:
    [mode config name, dispersion rad, reloadTime s] <ARRAY>

Examples:
    [_praetorian, [0], "weapon_Cannon_Phalanx"] call aegism_intercept_fnc_fireModeStats;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath", "_weaponClass"];

private _mode = (weaponState [_system, _turretPath, _weaponClass]) param [2, ""];

private _cache = missionNamespace getVariable "AEGISM_cacheModes";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheModes", _cache];
};
private _key = _weaponClass + "|" + _mode;
private _cached = _cache get _key;
if (!isNil "_cached") exitWith { _cached };

private _weaponCfg = configFile >> "CfgWeapons" >> _weaponClass;
private _modeCfg = _weaponCfg >> _mode;
if (_mode == "" || {!isClass _modeCfg}) then { _modeCfg = _weaponCfg; };

_cached = [configName _modeCfg, getNumber (_modeCfg >> "dispersion"), (getNumber (_modeCfg >> "reloadTime")) max 0];
_cache set [_key, _cached];
_cached
