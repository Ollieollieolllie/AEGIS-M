/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_radarCovers

Description:
    Whether one of a vehicle's active radars can see a position: within its
    reach and inside its arc.
    Full notes: docs/functions/modules_system.md

Parameters:
    _vehicle - the vehicle <OBJECT>
    _position - ASL position <ARRAY>

Returns:
    [covers <BOOLEAN>, turret path of the radar that covers it, [] for one
    fixed to the hull or if none does <ARRAY>]

Examples:
    [_radarTruck, getPosASL _jet] call aegism_system_fnc_radarCovers;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle", "_position"];

private _system = _vehicle getVariable ["AEGISM_system", createHashMap];
private _eye = eyePos _vehicle;
private _distance = _eye distance _position;
private _elevation = if (_distance > 0) then { asin (((((_position select 2) - (_eye select 2)) / _distance) max -1) min 1) } else { 0 };
// Bearing from the vehicle's forward, -180 to 180, clockwise positive.
private _relative = _vehicle getRelDir _position;
if (_relative > 180) then { _relative = _relative - 360; };

private _index = (_system getOrDefault ["sensors", []]) findIf {
    _x params ["_type", "_range", "_arc", "_aim", "", "", "", ["_verticalArc", 360], ["_aimDown", 0]];
    _type == "radar" && {_distance <= _range} && {
        if (_aim isEqualTo []) then {
            (_arc >= 360 || {abs _relative <= _arc / 2}) && {_verticalArc >= 360 || {abs (_elevation + _aimDown) <= _verticalArc / 2}}
        } else {
            // Turret limits are degrees from forward, positive to the left.
            ([_vehicle, _aim] call aegism_intercept_fnc_turretConfig) params ["", "", "", "_minElev", "_maxElev", "", "", "", "_minTurn", "_maxTurn"];
            ((_maxTurn - _minTurn) >= 360 || {-_relative >= _minTurn - _arc / 2 && {-_relative <= _maxTurn + _arc / 2}})
                && {_verticalArc >= 360 || {_elevation >= _minElev - _verticalArc / 2 && {_elevation <= _maxElev + _verticalArc / 2}}}
        }
    }
};
if (_index < 0) exitWith { [false, []] };
[true, ((_system get "sensors") select _index) select 3]
