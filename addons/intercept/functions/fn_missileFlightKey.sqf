/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileFlightKey
Description:
    The key a missile's learned speed curve is kept under (aegism_intercept_
    fnc_recordMissileSpeed, aegism_intercept_fnc_missileProfile): its flight
    config -- launch speed, thrust, burn time, motor delay, airFriction,
    lifetime and maxSpeed (aegism_intercept_fnc_weaponKinematics) -- not its
    weapon. Missiles that fly alike learn together: POOK's SA-8 has six
    one-missile launchers, each its own weapon, magazine and ammo class.

Parameters:
    _weaponClass - CfgWeapons class <STRING>
    _magazineClass - CfgMagazines class <STRING>

Returns:
    <STRING>

Examples:
    ["pook_SA8Launcher2", "pook_SA8_9K33_mag2"] call aegism_intercept_fnc_missileFlightKey;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_weaponClass", "_magazineClass"];

([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics)
    params ["", "_v0", "", "_thrust", "_thrustTime", "_initTime", "_friction", "_lifetime", "", "", "", "", "_maxSpeed"];
str [_v0, _thrust, _thrustTime, _initTime, _friction, _lifetime, _maxSpeed]
