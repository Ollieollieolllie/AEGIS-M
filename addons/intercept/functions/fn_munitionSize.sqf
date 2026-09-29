/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_munitionSize

Description:
    Reads a CfgAmmo entry's indirectHitRange (blast radius, metres) as a
    real-config proxy for a munition's physical size/destructive class --
    used both to size an incoming contact's own munition (how big is the
    missile bearing down on us) and an interceptor's loaded ammo (how big
    a warhead does this launcher's weapon carry), so aegism_intercept_fnc_
    assignEngagements can match one against the other without a mission
    designer hand-tuning a "small/medium/large" tier per class.

    indirectHitRange is what the engine uses for splash damage, so it's set
    consistently across vanilla and modded explosive ammo, and scales with
    warhead size. hit (direct-hit damage) is NOT used here -- it's noisy
    across ammo roles. Plain (non-explosive) gun ammo returns 0.

    Cached per ammo class ("AEGISM_cacheMunitionSize"): the coordinator
    sizes every contact every cycle.

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
