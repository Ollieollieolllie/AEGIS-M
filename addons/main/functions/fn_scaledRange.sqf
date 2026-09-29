/* ----------------------------------------------------------------------------
Function: aegism_fnc_scaledRange

Description:
    Applies the active AEGIS-M range scale setting (Arma Scale / Real World
    Scale / Custom Multiplier) to a real-world-sourced base range value.
    Every range-consuming module (System, EngagementSettings, detection loop)
    must resolve its ranges through this function rather than reading its
    configured base value directly, so the scale setting stays a single
    global multiplier applied in one place.

    Reads the settings' own global variables (CBA keeps every setting's
    value in the missionNamespace variable of the same name) rather than
    CBA_settings_fnc_get: this runs inside every envelope check.

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
