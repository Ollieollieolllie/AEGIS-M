/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ammoBurst

Description:
    How long a gun round really flies, and how it ends, from its config --
    for any mod's ammo:

    A round that is a submunition carrier (CfgAmmo simulation
    "shotSubmunitions", like vanilla's SubmunitionBullet) turns into its
    submunition triggerTime s after it's fired. If that submunition explodes
    at once (CfgAmmo explosionTime set), the round is an airburst: its
    flight ends there, in a blast of the submunition's radius (its
    indirectHitRange -- the smallest, when it's one of several). POOK's
    20, 23 and 30 mm AA rounds become 8-12 m airbursts 1 s after firing, so
    their guns reached ~1 km while AEGIS-M took their timeToLive (4-11 s)
    as their flight. If the submunition flies on instead (vanilla's minigun
    rounds swap to another bullet after 0.1 s), the round's flight goes on
    for the submunition's own lifetime.

    The round's own timeToLive still ends it first if it's shorter.

    Cached per ammo class ("AEGISM_cacheAmmoBurst").

Parameters:
    _ammoClass - a CfgAmmo class <STRING>

Returns:
    [lifetime s (0 = unset), burst at s (0 = none), burst radius m] <ARRAY>

Examples:
    (["pook_SA22_30mm_AA"] call aegism_intercept_fnc_ammoBurst) params ["_lifetime", "_burstAt", "_burstRadius"];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_ammoClass"];

private _cache = missionNamespace getVariable "AEGISM_cacheAmmoBurst";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheAmmoBurst", _cache];
};
private _cached = _cache get _ammoClass;
if (!isNil "_cached") exitWith { _cached };

private _cfg = configFile >> "CfgAmmo" >> _ammoClass;
private _lifetime = getNumber (_cfg >> "timeToLive");
private _trigger = getNumber (_cfg >> "triggerTime");
_cached = [_lifetime, 0, 0];
if ((toLower getText (_cfg >> "simulation")) == "shotsubmunitions" && {_trigger > 0} && {_lifetime <= 0 || {_trigger < _lifetime}}) then {
    // Its submunition: a class, or a list of [class, weight, ...].
    private _children = if (isArray (_cfg >> "submunitionAmmo")) then {
        (getArray (_cfg >> "submunitionAmmo")) select { _x isEqualType "" }
    } else {
        [getText (_cfg >> "submunitionAmmo")]
    };
    _children = (_children select { isClass (configFile >> "CfgAmmo" >> _x) }) apply { configFile >> "CfgAmmo" >> _x };
    if (_children isEqualTo []) exitWith {};
    private _bursting = _children select { (getNumber (_x >> "explosionTime")) > 0 };
    if (count _bursting == count _children) then {
        // An airburst: the flight ends at the burst.
        private _end = _trigger + selectMax (_bursting apply { getNumber (_x >> "explosionTime") });
        _cached = [_end, _end, selectMin (_bursting apply { getNumber (_x >> "indirectHitRange") })];
    } else {
        // Flies on as its submunition.
        private _childLife = selectMax (_children apply { getNumber (_x >> "timeToLive") });
        if (_childLife > 0) then { _cached = [_trigger + _childLife, 0, 0]; };
    };
};
_cache set [_ammoClass, _cached];
_cached
