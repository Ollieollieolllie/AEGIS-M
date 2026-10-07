/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_classifyAmmoClass

Description:
    Classifies an ammo class name into an AEGIS-M target class from its
    CfgAmmo inheritance chain.
    Full notes: docs/functions/detection.md

Parameters:
    _ammoClassName - a CfgAmmo classname <STRING>

Returns:
    One of "missile" | "rocket" | "bomb" | "artilleryShell", or "" if it
    doesn't classify as any of these (e.g. plain cannon/gun ammo) <STRING>

Examples:
    ["M_Titan_AA"] call aegism_detect_fnc_classifyAmmoClass;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_ammoClassName"];

private _cache = missionNamespace getVariable "AEGISM_cacheAmmoClass";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheAmmoClass", _cache];
};
private _cached = _cache get _ammoClassName;
if (!isNil "_cached") exitWith { _cached };

private _cfgAmmo = configFile >> "CfgAmmo";
private _ammoConfig = _cfgAmmo >> _ammoClassName;

private _class = if (!isClass _ammoConfig) then { "" } else {
    // ShellCore covers tank/IFV main-gun rounds too (e.g. Sh_120mm_HE), which
    // are direct-fire and not an air-defence threat. Only ammo the engine
    // itself flags as indirect artillery (CfgAmmo artilleryLock = 1, set on
    // Sh_155mm_AMOS/Sh_82mm_AMOS and inherited by their variants) counts.
    private _isArtillery = (getNumber (_ammoConfig >> "artilleryLock")) == 1;
    // Fallback: simulation-string match for ammo that doesn't chain through
    // the vanilla *Core classes (some mod ammo reparents directly off Default).
    private _simulation = toLower getText (_ammoConfig >> "simulation");
    switch (true) do {
        case (_ammoClassName isKindOf ["MissileCore", _cfgAmmo]): { "missile" };
        case (_ammoClassName isKindOf ["BombCore", _cfgAmmo]): { "bomb" };
        case (_ammoClassName isKindOf ["ShellCore", _cfgAmmo]): { ["", "artilleryShell"] select _isArtillery };
        case (_ammoClassName isKindOf ["RocketCore", _cfgAmmo]): { "rocket" };
        case (_simulation == "shotmissile"): { "missile" };
        case (_simulation == "shotrocket"): { "rocket" };
        case (_simulation in ["shotshell", "shotsubmunitions"] && _isArtillery): { "artilleryShell" };
        default { "" };
    }
};

_cache set [_ammoClassName, _class];
_class
