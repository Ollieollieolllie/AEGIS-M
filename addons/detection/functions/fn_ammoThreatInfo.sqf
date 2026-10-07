/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_ammoThreatInfo

Description:
    What a fired ammo class means to AEGIS-M, cached per class: its threat
    class, whether it's a carrier whose submunitions must be followed, and
    how many it releases.
    Full notes: docs/functions/detection.md

Parameters:
    _ammoClass - CfgAmmo class <STRING>

Returns:
    [threat class ("" if none), carrier <BOOLEAN>, submunitions released]
    <ARRAY>

Examples:
    ["R_230mm_HE"] call aegism_detect_fnc_ammoThreatInfo;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_ammoClass"];

private _cache = missionNamespace getVariable "AEGISM_cacheAmmoThreat";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheAmmoThreat", _cache];
};
private _cached = _cache get _ammoClass;
if (!isNil "_cached") exitWith { _cached };

private _ammoCfg = configFile >> "CfgAmmo" >> _ammoClass;
private _submunitions = 1;
if (isArray (_ammoCfg >> "submunitionConeType")) then {
    _submunitions = (getArray (_ammoCfg >> "submunitionConeType")) param [1, 1];
} else {
    if (isNumber (_ammoCfg >> "submunitionCount")) then { _submunitions = getNumber (_ammoCfg >> "submunitionCount"); };
};
_cached = [
    [_ammoClass] call aegism_detect_fnc_classifyAmmoClass,
    (toLower getText (_ammoCfg >> "simulation")) == "shotsubmunitions",
    _submunitions
];
_cache set [_ammoClass, _cached];
_cached
