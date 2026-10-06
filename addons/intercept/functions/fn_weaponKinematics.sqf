/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_weaponKinematics

Description:
    Everything AEGIS-M reads from config about what a weapon fires, read once
    per weapon + magazine and cached ("AEGISM_cacheKinematics"): the lead
    solver, aim, fuse and burst all used to re-read these on every call --
    ten or more config lookups per aim, every frame.

        v0 - launch speed: CfgMagazines initSpeed, overridden per engine
            rules by CfgWeapons initSpeed (> 0 replaces, < 0 multiplies)
        drag - |CfgAmmo airFriction| (guns; the lead solver's drag model)
        thrust, thrustTime, initTime - a missile's motor: CfgAmmo thrust
            (m/s^2), how long it burns, and how long after launch it lights
        missileFriction - a missile's CfgAmmo airFriction, which is positive
            (a bullet's is negative); 0 with artilleryLock, which the engine
            says ignores it
        timeToLive - how long the round flies (0 = unset): CfgAmmo
            timeToLive, or, for a round that turns into an airburst or
            another round first, until then (aegism_intercept_fnc_ammoBurst)
        lockCone - CfgAmmo missileLockCone (180 if unset)
        fuseDistance - CfgAmmo fuseDistance (arming distance)
        guided - CfgAmmo simulation is shotMissile
        blastRadius - CfgAmmo indirectHitRange
        maxSpeed - CfgAmmo maxSpeed (logged; aegism_intercept_fnc_
            missileProfile doesn't apply it)
        proximity - CfgAmmo proximityExplosionDistance: the round's own
            proximity fuse, m (0 = none)
        burstAt, burstRadius - an airburst round: when it bursts, s, and its
            blast, m (0 = none; aegism_intercept_fnc_ammoBurst)

    A missile's flight is simulated from these by aegism_intercept_fnc_
    missileProfile.

    Each new entry is logged once (KINEMATICS), so the values the solver
    works with are in the RPT.

Parameters:
    _weaponClass - CfgWeapons class <STRING>
    _magazineClass - CfgMagazines class <STRING>

Returns:
    [ammoClass, v0, drag, thrust, thrustTime, initTime, missileFriction,
     timeToLive, lockCone, fuseDistance, guided, blastRadius, maxSpeed,
     proximity, burstAt, burstRadius] <ARRAY>

Examples:
    ["weapon_Cannon_Phalanx", "magazine_Cannon_Phalanx_x1550"] call aegism_intercept_fnc_weaponKinematics;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

params ["_weaponClass", "_magazineClass"];

private _cache = missionNamespace getVariable "AEGISM_cacheKinematics";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheKinematics", _cache];
};
private _key = _weaponClass + "|" + _magazineClass;
private _cached = _cache get _key;
if (!isNil "_cached") exitWith { _cached };

private _ammoClass = getText (configFile >> "CfgMagazines" >> _magazineClass >> "ammo");
private _ammoCfg = configFile >> "CfgAmmo" >> _ammoClass;

private _v0 = getNumber (configFile >> "CfgMagazines" >> _magazineClass >> "initSpeed");
private _weaponSpeed = getNumber (configFile >> "CfgWeapons" >> _weaponClass >> "initSpeed");
if (_weaponSpeed > 0) then { _v0 = _weaponSpeed; };
if (_weaponSpeed < 0) then { _v0 = _v0 * (abs _weaponSpeed); };

private _drag = abs ((getNumber (_ammoCfg >> "airFriction")) min 0);
private _missileFriction = if ((getNumber (_ammoCfg >> "artilleryLock")) == 1) then { 0 } else { (getNumber (_ammoCfg >> "airFriction")) max 0 };

private _lockCone = getNumber (_ammoCfg >> "missileLockCone");
if (_lockCone <= 0) then { _lockCone = 180; };

([_ammoClass] call aegism_intercept_fnc_ammoBurst) params ["_lifetime", "_burstAt", "_burstRadius"];

_cached = [
    _ammoClass, _v0, _drag,
    getNumber (_ammoCfg >> "thrust"),
    getNumber (_ammoCfg >> "thrustTime"),
    getNumber (_ammoCfg >> "initTime"),
    _missileFriction,
    _lifetime,
    _lockCone,
    getNumber (_ammoCfg >> "fuseDistance"),
    (toLower getText (_ammoCfg >> "simulation")) == "shotmissile",
    getNumber (_ammoCfg >> "indirectHitRange"),
    getNumber (_ammoCfg >> "maxSpeed"),
    getNumber (_ammoCfg >> "proximityExplosionDistance"),
    _burstAt,
    _burstRadius
];
_cache set [_key, _cached];

// The motor only for a missile: every CfgAmmo inherits thrust values from the
// defaults, which a bullet or shell never uses.
if (AEGISM_RPT_VERBOSE) then {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " KINEMATICS: %1 / %2 -> %3: v0 %4 m/s, airFriction %5%6, flies %7s%12, lockCone %8, fuseDistance %9m, guided %10, blast %11m%13 (cached).",
        _weaponClass, _magazineClass, _ammoClass, _v0, _drag,
        ["", format [" (its own %1), thrust %2 m/s2 for %3s from %4s after launch, maxSpeed %5", _missileFriction, _cached select 3, _cached select 4, _cached select 5, _cached select 12]] select (_cached select 10),
        _lifetime, _lockCone, _cached select 9, _cached select 10, _cached select 11,
        ["", format [" (bursts then, %1m; its timeToLive is %2s)", _burstRadius, getNumber (_ammoCfg >> "timeToLive")]] select (_burstAt > 0),
        ["", format [", proximity fuse %1m", _cached select 13]] select ((_cached select 13) > 0)];
};

_cached
