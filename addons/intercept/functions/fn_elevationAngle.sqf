/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_elevationAngle

Description:
    Elevation of one ASL position as seen from another, in degrees above
    (positive) or below (negative) the horizontal.

Parameters:
    _from - observer position, ASL <ARRAY>
    _to - observed position, ASL <ARRAY>

Returns:
    Elevation angle, degrees <NUMBER>

Examples:
    [eyePos _cheetah, getPosASL _rocket] call aegism_intercept_fnc_elevationAngle;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_from", "_to"];

// Clamped: float error can push the ratio fractionally past +-1.
asin (((((_to select 2) - (_from select 2)) / ((_from distance _to) max 0.001)) max -1) min 1)
