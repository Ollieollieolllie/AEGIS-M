/* ----------------------------------------------------------------------------
Function: aegism_fnc_statusStyle

Description:
    How the debug overlays (aegism_fnc_debugDraw, aegism_fnc_debugHint) show
    one engagement's state -- the "status" aegism_intercept_fnc_
    engagementLoop records on it every tick -- so each munition queued on a
    launcher shows where it actually is, not one colour for the lot:

        queued - waiting its turn: the launcher is on another first (blue)
        assigned - just assigned, not worked yet (green)
        reacting - crew reaction time (amber)
        slewing - turret swinging onto it (amber)
        reloading - shot interval / burst pause / lost fire cycle (orange)
        rangeHold - a gun tracking it, beyond its open-fire range (teal)
        firing - a gun's burst on it, or a missile just launched (red)
        inFlight - salvo away, missiles guiding (gold)
        losBlocked / noSolution - can't see it / can't reach it (purple)
        crewFailed / held / noAmmo - crew missed its cycle, fire held, empty
            (grey)

Parameters:
    _status - the engagement's status <STRING>

Returns:
    [label <STRING>, colour RGBA <ARRAY>, colour hex <STRING>, urgency
     (higher = shown first) <NUMBER>]

Examples:
    ["queued"] call aegism_fnc_statusStyle;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_status", ""]];

switch (_status) do {
    case "queued": { ["queued", [0.45, 0.7, 1, 1], "#73B3FF", 1] };
    case "reacting": { ["reacting", [1, 0.79, 0.16, 1], "#FFCA28", 3] };
    case "slewing": { ["slewing", [1, 0.79, 0.16, 1], "#FFCA28", 3] };
    case "reloading": { ["reloading", [1, 0.65, 0.15, 1], "#FFA726", 4] };
    case "rangeHold": { ["range hold", [0.3, 0.85, 0.8, 1], "#4DD9CC", 2] };
    case "firing": { ["firing", [0.94, 0.33, 0.31, 1], "#EF5350", 7] };
    case "inFlight": { ["in flight", [1, 0.84, 0.31, 1], "#FFD54F", 5] };
    case "losBlocked": { ["no LOS", [0.81, 0.58, 0.85, 1], "#CE93D8", 6] };
    case "noSolution": { ["no solution", [0.81, 0.58, 0.85, 1], "#CE93D8", 6] };
    case "crewFailed": { ["crew failed", [0.62, 0.62, 0.62, 1], "#9E9E9E", 0] };
    case "held": { ["fire held", [0.62, 0.62, 0.62, 1], "#9E9E9E", 0] };
    case "noAmmo": { ["no ammo", [0.62, 0.62, 0.62, 1], "#9E9E9E", 0] };
    default { ["assigned", [0.4, 0.73, 0.42, 1], "#66BB6A", 1] };
}
