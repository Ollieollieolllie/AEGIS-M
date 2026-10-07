/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_destroyMunition

Description:
    Destroys an incoming munition where it is (triggerAmmo: it detonates in
    the air).
    Full notes: docs/functions/detection.md

Parameters:
    _munition - the munition <OBJECT>

Returns:
    Nothing

Examples:
    [_shell] call aegism_detect_fnc_destroyMunition;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_munition"];

if (isNull _munition || {!alive _munition}) exitWith {};

if ((toLower getText (configOf _munition >> "simulation")) == "shotsubmunitions") then {
    _munition setVariable ["AEGISM_intercepted", true];
    _munition addEventHandler ["SubmunitionCreated", {
        params ["", "_submunitionProjectile"];
        deleteVehicle _submunitionProjectile;
    }];
};
triggerAmmo _munition;
