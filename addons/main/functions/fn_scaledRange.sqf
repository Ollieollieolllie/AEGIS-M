/* ----------------------------------------------------------------------------
Function: aegism_fnc_scaledRange

Description:
    Applies the active AEGIS-M range scale setting (Arma Scale / Real World
    Scale / Custom Multiplier) to a real-world-sourced base range value.
    Full notes: docs/functions/main.md

Parameters:
    _baseRange - the real-world-sourced base range value (metres) <NUMBER>

Returns:
    The scaled range value (metres) <NUMBER>

Examples:
    [4000] call aegism_fnc_scaledRange;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_baseRange"];

if (_baseRange == 0) exitWith { 0 };

private _multiplier = switch (missionNamespace getVariable ["aegism_main_scaleMode", 0]) do {
    case 1: { 1 };     // Real World Scale
    case 2: { missionNamespace getVariable ["aegism_main_scaleCustomMultiplier", 1] }; // Custom Multiplier
    default { 0.5 };   // Arma Scale
};

_baseRange * _multiplier
