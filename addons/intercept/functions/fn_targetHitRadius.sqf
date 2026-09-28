/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_targetHitRadius

Description:
    Reads a munition target's real physical half-size from its own model
    bounding box (boundingBoxReal), for aegism_intercept_fnc_interceptorPFH
    to widen its effective hit radius beyond a plain point-to-center-point
    check -- a real missile/rocket/bomb has actual model geometry, not a
    single point, so an interceptor that geometrically clips its body should
    count as a hit even if that point lies outside the interceptor's own
    (possibly small or zero) blast radius measured from the target's bare
    center.

    boundingBoxReal returns [[minX,minY,minZ],[maxX,maxY,maxZ]] in the
    object's own model space -- half the length of the diagonal between
    those two corners is used as a single representative "radius" (a sphere
    that fully contains the model's own bounding box), simpler and more
    conservative than trying to reason about which axis the interceptor
    actually approached from.

    Deliberately NOT called for a platform target (helicopter/plane/drone)
    -- see aegism_intercept_fnc_interceptorPFH's own doc comment for why:
    those already have real hitpoints/collision, so widening their
    effective radius here would credit a near-miss the engine itself never
    registered as a hit.

Parameters:
    _target - the munition target object to measure <OBJECT>

Returns:
    Half-diagonal of the target's own real bounding box, metres <NUMBER>

Examples:
    [_incomingMissile] call aegism_intercept_fnc_targetHitRadius;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_target"];

if (isNull _target) exitWith { 0 };

(boundingBoxReal _target) params ["_min", "_max"];
(_min distance _max) / 2
