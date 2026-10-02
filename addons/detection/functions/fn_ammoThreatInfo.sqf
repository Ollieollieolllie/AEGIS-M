/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_ammoThreatInfo

Description:
    What a fired ammo class means to AEGIS-M, cached per class
    ("AEGISM_cacheAmmoThreat"): its threat class (aegism_detect_fnc_
    classifyAmmoClass), whether it's a carrier (CfgAmmo simulation
    "shotSubmunitions") whose released projectiles must be followed, and for
    a carrier how many it releases: the count in its submunitionConeType
    (R_230mm_Cluster {"randomcenter", 50}, Cluster_155mm_AMOS 35), else its
    submunitionCount, else 1 (R_230mm_HE releases its one R_230mm_fly). The
    server's Fired handler runs this for every round fired in the mission;
    for a bullet it's one lookup.

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
