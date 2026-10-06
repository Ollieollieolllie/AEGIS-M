/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_targetHitRadius

Description:
    A target's physical half-size: half the diagonal of its model's bounding
    box (aegism_intercept_fnc_targetBody), a sphere that holds the whole body.

    Optionally, as seen along a line of fire: the radius of a disc with the
    box's area as seen from that direction (its projected area: each pair of
    faces' area times how squarely the line meets them). A munition's body
    is its box (aegism_intercept_fnc_bodyPass), and a round has to come
    within its own radius of that, not of the sphere -- so this is what a
    gun's fire gate (aegism_intercept_fnc_aimWeapon) and open-fire range
    (aegism_intercept_fnc_openFireRange) work with against a munition. Side
    on, vanilla's 230 mm rocket (2.29 x 11.96 x 2.29 m) is a 2.95 m disc; nose
    on, 1.29 m; its sphere is 6.19 m.

    The sphere still sizes an aircraft (the engine's own collision decides
    hits on those) and CIWS spotting's sense of "through the target"
    (aegism_intercept_fnc_ciwsSpot).

Parameters:
    _target - the target object <OBJECT>
    _lineOfFire - optional: the direction the rounds come from (any length;
        [] = the sphere) <ARRAY>

Returns:
    Radius, metres <NUMBER>

Examples:
    [_incomingMissile] call aegism_intercept_fnc_targetHitRadius;
    [_rocket, (getPosASL _rocket) vectorDiff (getPosASL _gun)] call aegism_intercept_fnc_targetHitRadius;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_target", ["_lineOfFire", []]];

if (isNull _target) exitWith { 0 };

([_target] call aegism_intercept_fnc_targetBody) params ["_min", "_max", "_halfDiagonal"];
if (_lineOfFire isEqualTo [] || {(vectorMagnitude _lineOfFire) <= 0}) exitWith { _halfDiagonal };

// The line of fire in the target's own axes: x right, y forward, z up.
private _line = vectorNormalized _lineOfFire;
private _dir = vectorDirVisual _target;
private _up = vectorUpVisual _target;
private _right = _dir vectorCrossProduct _up;
(_max vectorDiff _min) params ["_sx", "_sy", "_sz"];
private _area = (abs (_line vectorDotProduct _right)) * _sy * _sz
    + (abs (_line vectorDotProduct _dir)) * _sx * _sz
    + (abs (_line vectorDotProduct _up)) * _sx * _sy;
sqrt (_area / pi)
