/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretSlewTime

Description:
    Seconds a turret needs to swing its barrel from where it points now to a
    world direction.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>
    _weaponClass - the turret's weapon (for its barrel direction) <STRING>
    _direction - world-space direction to point along <ARRAY>

Returns:
    Seconds; an axis whose rate isn't set counts as not moving (0 if
    neither is) <NUMBER>

Examples:
    [_cheetah, [0], "autocannon_35mm", _origin vectorFromTo _aimPoint] call aegism_intercept_fnc_turretSlewTime;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath", "_weaponClass", "_direction"];

([_system, _turretPath] call aegism_intercept_fnc_turretConfig) params ["", "", "", "_minElevation", "_maxElevation", "", "_traverseRate", "_elevateRate", "_minTurn", "_maxTurn"];
// An axis without a rate doesn't move (a fixed-bearing launcher): nothing to
// wait for on it.
if (_traverseRate <= 0 && {_elevateRate <= 0}) exitWith { 0 };

private _barrel = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection;
if (_barrel isEqualTo [0, 0, 0]) exitWith { 0 };

// Azimuth and elevation of a direction in the vehicle's own frame.
private _fnAngles = {
    private _local = vectorNormalized (_system vectorWorldToModelVisual _this);
    [(_local select 0) atan2 (_local select 1), asin (((_local select 2) max -1) min 1)]
};
(_barrel call _fnAngles) params ["_barrelAzimuth", "_barrelElevation"];
(_direction call _fnAngles) params ["_aimAzimuth", "_aimElevation"];

private _traverse = abs (_aimAzimuth - _barrelAzimuth);
if (_traverse > 180) then { _traverse = 360 - _traverse; };
if (_maxTurn - _minTurn < 360) then {
    // In the turret's own angle (positive left, aegism_intercept_fnc_
    // turretConfig), taken into its limits: no wrapping across the gap.
    private _fnTurretAngle = {
        private _angle = -_this;
        while { _angle < _minTurn } do { _angle = _angle + 360; };
        while { _angle >= _minTurn + 360 } do { _angle = _angle - 360; };
        _angle min _maxTurn
    };
    _traverse = abs ((_aimAzimuth call _fnTurretAngle) - (_barrelAzimuth call _fnTurretAngle));
};
private _elevate = abs (((_aimElevation max _minElevation) min _maxElevation) - _barrelElevation);

private _traverseTime = if (_traverseRate > 0) then { _traverse / _traverseRate } else { 0 };
private _elevateTime = if (_elevateRate > 0) then { _elevate / _elevateRate } else { 0 };
_traverseTime max _elevateTime
