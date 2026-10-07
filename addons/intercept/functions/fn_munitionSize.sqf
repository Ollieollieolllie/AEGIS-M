/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_munitionSize

Description:
    A CfgAmmo entry's indirectHitRange (blast radius, m), used as a
    munition's size class.
    Full notes: docs/functions/intercept.md

Parameters:
    _ammoClassName - a CfgAmmo classname <STRING>

Returns:
    indirectHitRange in metres, or 0 if the ammo doesn't define one (plain
    kinetic ammo, or an invalid classname) <NUMBER>

Examples:
    ["M_Titan_AA"] call aegism_intercept_fnc_munitionSize;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_ammoClassName"];

private _cache = missionNamespace getVariable "AEGISM_cacheMunitionSize";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheMunitionSize", _cache];
};
private _cached = _cache get _ammoClassName;
if (!isNil "_cached") exitWith { _cached };

private _ammoConfig = configFile >> "CfgAmmo" >> _ammoClassName;
_cached = if (isClass _ammoConfig) then { getNumber (_ammoConfig >> "indirectHitRange") } else { 0 };
_cache set [_ammoClassName, _cached];
_cached
