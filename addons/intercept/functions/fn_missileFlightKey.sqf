/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileFlightKey
Description:
    The key a missile's learned speed curve is kept under: its flight
    config.
    Full notes: docs/functions/intercept.md

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
