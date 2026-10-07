/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_threatValue

Description:
    Maps a contact class to a threat-value score.
    Full notes: docs/functions/intercept.md

Parameters:
    _class - a classified contact class, from aegism_detect_fnc_
        classifyTarget <STRING>

Returns:
    Threat value, higher = higher priority to spend interceptors on
    (0 if the class is unrecognized) <NUMBER>

Examples:
    ["missile"] call aegism_intercept_fnc_threatValue;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_class"];

switch (_class) do {
    case "missile": { 5 };
    case "bomb": { 4 };
    case "fixedWing": { 3 };
    case "helicopter": { 3 };
    case "drone": { 2 };
    case "rocket": { 2 };
    case "artilleryShell": { 1 };
    default { 0 };
};
