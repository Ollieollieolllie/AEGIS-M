/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_destroyMunition

Description:
    Destroys an incoming munition where it is (triggerAmmo: it detonates in
    the air), on every machine (aegism_detect_fnc_detonate).
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

private _isCarrier = (toLower getText (configOf _munition >> "simulation")) == "shotsubmunitions";
if (_isCarrier) then { _munition setVariable ["AEGISM_intercepted", true]; };
[_munition, _isCarrier] call aegism_detect_fnc_detonate;
