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
        thrust, burnSpeed, accelTime, accelDist - missile boost: CfgAmmo
            thrust (m/s^2) until maxSpeed or thrustTime
        timeToLive - CfgAmmo timeToLive (the round's lifetime; 0 = unset)
        lockCone - CfgAmmo missileLockCone (180 if unset)
        fuseDistance - CfgAmmo fuseDistance (arming distance)
        guided - CfgAmmo simulation is shotMissile
        blastRadius - CfgAmmo indirectHitRange

    Each new entry is logged once (KINEMATICS), so the values the solver
    works with are in the RPT.

Parameters:
    _weaponClass - CfgWeapons class <STRING>
    _magazineClass - CfgMagazines class <STRING>

Returns:
    [ammoClass, v0, drag, thrust, burnSpeed, accelTime, accelDist,
     timeToLive, lockCone, fuseDistance, guided, blastRadius] <ARRAY>

Examples:
    ["weapon_Cannon_Phalanx", "magazine_Cannon_Phalanx_x1550"] call aegism_intercept_fnc_weaponKinematics;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

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
private _thrust = getNumber (_ammoCfg >> "thrust");
private _maxSpeed = getNumber (_ammoCfg >> "maxSpeed");
private _burnSpeed = if (_thrust > 0) then { _v0 + _thrust * getNumber (_ammoCfg >> "thrustTime") } else { _v0 };
if (_maxSpeed > 0) then { _burnSpeed = _burnSpeed min _maxSpeed; };
private _accelTime = if (_thrust > 0) then { (_burnSpeed - _v0) / _thrust } else { 0 };
private _accelDist = _v0 * _accelTime + 0.5 * _thrust * _accelTime * _accelTime;

private _lockCone = getNumber (_ammoCfg >> "missileLockCone");
if (_lockCone <= 0) then { _lockCone = 180; };

_cached = [
    _ammoClass, _v0, _drag, _thrust, _burnSpeed, _accelTime, _accelDist,
    getNumber (_ammoCfg >> "timeToLive"),
    _lockCone,
    getNumber (_ammoCfg >> "fuseDistance"),
    (toLower getText (_ammoCfg >> "simulation")) == "shotmissile",
    getNumber (_ammoCfg >> "indirectHitRange")
];
_cache set [_key, _cached];

diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " KINEMATICS: %1 / %2 -> %3: v0 %4 m/s, airFriction %5, thrust %6 m/s2 to %7 m/s, timeToLive %8s, lockCone %9, fuseDistance %10m, guided %11, blast %12m (cached).",
    _weaponClass, _magazineClass, _ammoClass, _v0, _drag, _thrust, _burnSpeed, _cached select 7, _lockCone, _cached select 9, _cached select 10, _cached select 11];

_cached
