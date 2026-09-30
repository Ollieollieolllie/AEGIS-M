/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretCanPoint

Description:
    Whether a turret can physically point along a world direction, and the
    closest direction it CAN point along: the direction taken into the
    vehicle's own model space (so a vehicle on a slope is handled) and
    checked against the turret config's own limits (cached, aegism_
    intercept_fnc_turretConfig):
        elevation - minElev / maxElev
        traverse - minTurn / maxTurn, degrees from the vehicle's forward,
            positive to the LEFT (verified on the Ghost Hawk's door guns:
            left 15 to 160, right -160 to -15); a span of 360 or more turns
            all the way round
    The closest reachable direction clamps each axis to its nearest limit --
    where a fixed-bearing or fixed launcher actually sends its missile
    (aegism_intercept_fnc_launchSolution).

    Why: a CIWS whose aim point was beyond its travel could never get its
    barrel within tolerance, so it held fire on that target until the target
    landed. The Praetorian 1C (B_AAA_System_01_F, maxElev 85) sat with its
    barrel pinned 1.5-4 degrees short of shells coming down steeply beside
    it for over 5s each, while other shells it could have reached got
    through.

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>
    _direction - world-space direction to point along <ARRAY>

Returns:
    [can point <BOOLEAN>, elevation deg, min elevation deg, max elevation
     deg -- elevation of the direction in the vehicle's own frame,
     closest reachable world direction <ARRAY>, the direction's traverse
     angle deg (left positive), min traverse deg, max traverse deg] <ARRAY>

Examples:
    [_praetorian, [0], _origin vectorFromTo _aimPoint] call aegism_intercept_fnc_turretCanPoint;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath", "_direction"];

([_system, _turretPath] call aegism_intercept_fnc_turretConfig) params ["", "", "", "_minElevation", "_maxElevation", "", "", "", "_minTurn", "_maxTurn"];
private _local = vectorNormalized (_system vectorWorldToModelVisual _direction);
private _elevation = asin (((_local select 2) max -1) min 1);
// Model +x is right, +y forward; the turret's own angle is positive left.
private _turn = -((_local select 0) atan2 (_local select 1));

private _reachElevation = (_elevation max _minElevation) min _maxElevation;
private _reachTurn = _turn;
private _traverseOk = true;
if (_maxTurn - _minTurn < 360) then {
    // The angle taken into [minTurn, minTurn + 360): inside the limits if it
    // isn't past maxTurn; otherwise the nearer limit, going either way round.
    private _wrapped = _turn;
    while { _wrapped < _minTurn } do { _wrapped = _wrapped + 360; };
    while { _wrapped >= _minTurn + 360 } do { _wrapped = _wrapped - 360; };
    _traverseOk = _wrapped <= _maxTurn;
    if (!_traverseOk) then {
        _reachTurn = [_minTurn, _maxTurn] select ((_wrapped - _maxTurn) <= (_minTurn + 360 - _wrapped));
    };
};
private _canPoint = _traverseOk && {_elevation >= _minElevation} && {_elevation <= _maxElevation};

private _reachDirection = if (_canPoint) then { vectorNormalized _direction } else {
    _system vectorModelToWorldVisual [-(sin _reachTurn) * (cos _reachElevation), (cos _reachTurn) * (cos _reachElevation), sin _reachElevation]
};

[_canPoint, _elevation, _minElevation, _maxElevation, _reachDirection, _turn, _minTurn, _maxTurn]
