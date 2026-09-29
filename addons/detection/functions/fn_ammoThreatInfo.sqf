/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_ammoThreatInfo

Description:
    What a fired ammo class means to AEGIS-M, cached per class
    ("AEGISM_cacheAmmoThreat"): its threat class (aegism_detect_fnc_
    classifyAmmoClass) and whether it's a carrier (CfgAmmo simulation
    "shotSubmunitions") whose released projectiles must be followed. The
    server's Fired handler runs this for every round fired in the mission;
    for a bullet it's one lookup.

Parameters:
    _ammoClass - CfgAmmo class <STRING>

Returns:
    [threat class ("" if none), carrier <BOOLEAN>] <ARRAY>

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

_cached = [
    [_ammoClass] call aegism_detect_fnc_classifyAmmoClass,
    (toLower getText (configFile >> "CfgAmmo" >> _ammoClass >> "simulation")) == "shotsubmunitions"
];
_cache set [_ammoClass, _cached];
_cached
