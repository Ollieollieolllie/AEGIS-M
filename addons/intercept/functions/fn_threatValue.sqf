/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_threatValue

Description:
    Pure lookup: maps a classified contact class to a threat-value score
    used both by aegism_intercept_fnc_selectTarget's "highestValue" target-
    priority rule and by aegism_intercept_fnc_engagementLoop's cost/value
    judgment gate (AEGISM_Module_Site's "Enable Cost/Value Judgment"
    Personality option) -- kept as a single shared table so the two can
    never drift apart from each other.

    Missiles outrank platforms since a missed missile is an immediate kill
    risk to the defended asset, while a missed aircraft can be re-engaged
    on a later pass.

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
