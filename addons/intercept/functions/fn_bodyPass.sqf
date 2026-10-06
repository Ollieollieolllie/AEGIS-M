/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_bodyPass

Description:
    How close a round came to a munition's body over one frame: the least
    distance between the round's path and the munition's box (aegism_
    intercept_fnc_targetBody) -- 0 if it went through it. The fuses compare
    it with the round's own radius (its blast, CfgAmmo indirectHitRange, or
    its proximity fuse, proximityExplosionDistance): aegism_intercept_fnc_
    ciwsRounds, aegism_intercept_fnc_interceptorPFH.

    The path is relative: both move (at a 1500 m/s closing speed that's
    ~25 m a frame), so it's the round's position from the munition's model
    origin, last frame and this, turned into the munition's own axes as it
    points now.

    A path that doesn't come within the box's sphere plus the radius is
    turned away at once (most rounds, most frames); otherwise the distance
    to the box along it -- a convex function of how far along -- is found by
    ternary search.

Parameters:
    _target - the munition <OBJECT>
    _rel0 - the round from the target's model origin last frame (world axes) <ARRAY>
    _rel1 - the same this frame <ARRAY>
    _radius - the round's own radius, m (for the quick rejection) <NUMBER>

Returns:
    Least distance from the path to the box, m (beyond _radius, a lower
    bound) <NUMBER>

Examples:
    private _miss = [_rocket, _rel0, _rel1, 3] call aegism_intercept_fnc_bodyPass;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Ternary search steps: each keeps two thirds, so 20 resolve a 25 m path to
// about a millimetre.
#define AEGISM_BODY_PASS_STEPS 20

params ["_target", "_rel0", "_rel1", "_radius"];

([_target] call aegism_intercept_fnc_targetBody) params ["_min", "_max", "_halfDiagonal"];

// Into the target's own axes: x right, y forward, z up.
private _dir = vectorDirVisual _target;
private _up = vectorUpVisual _target;
private _right = _dir vectorCrossProduct _up;
private _a = [_rel0 vectorDotProduct _right, _rel0 vectorDotProduct _dir, _rel0 vectorDotProduct _up];
private _b = [_rel1 vectorDotProduct _right, _rel1 vectorDotProduct _dir, _rel1 vectorDotProduct _up];
private _seg = _b vectorDiff _a;
private _lengthSq = _seg vectorDotProduct _seg;

// Quick rejection: the path's closest approach to the box's centre.
private _centre = (_min vectorAdd _max) vectorMultiply 0.5;
private _at = if (_lengthSq > 0) then { 0 max (1 min (((_centre vectorDiff _a) vectorDotProduct _seg) / _lengthSq)) } else { 0 };
private _toCentre = (_a vectorAdd (_seg vectorMultiply _at)) distance _centre;
if (_toCentre > _halfDiagonal + _radius) exitWith { _toCentre - _halfDiagonal };

// A point's distance to the box.
private _fnDistance = {
    params ["_t"];
    private _p = _a vectorAdd (_seg vectorMultiply _t);
    _p distance [
        ((_p select 0) max (_min select 0)) min (_max select 0),
        ((_p select 1) max (_min select 1)) min (_max select 1),
        ((_p select 2) max (_min select 2)) min (_max select 2)
    ]
};
private _lo = 0;
private _hi = 1;
for "_i" from 1 to AEGISM_BODY_PASS_STEPS do {
    private _m1 = _lo + (_hi - _lo) / 3;
    private _m2 = _hi - (_hi - _lo) / 3;
    if (([_m1] call _fnDistance) <= ([_m2] call _fnDistance)) then { _hi = _m2; } else { _lo = _m1; };
};
[(_lo + _hi) / 2] call _fnDistance
