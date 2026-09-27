/* ----------------------------------------------------------------------------
Function: aegism_fnc_scaledRange

Description:
    Applies the active AEGIS-M range scale setting (Arma Scale / Real World
    Scale / Custom Multiplier) to a real-world-sourced base range value.
    Every range-consuming module (System, EngagementSettings, detection loop)
    must resolve its ranges through this function rather than reading its
    configured base value directly, so the scale setting stays a single
    global multiplier applied in one place.

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

private _mode = "aegism_main_scaleMode" call CBA_settings_fnc_get;
private _multiplier = switch (_mode) do {
    case 0: { 0.5 };   // Arma Scale
    case 1: { 1 };     // Real World Scale
    case 2: { "aegism_main_scaleCustomMultiplier" call CBA_settings_fnc_get }; // Custom Multiplier
    default { 0.5 };
};

_baseRange * _multiplier
