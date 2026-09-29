/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_targetHitRadius

Description:
    A target's physical half-size from its own model bounding box
    (boundingBoxReal): half the diagonal, i.e. a sphere that contains the
    whole model.

    For a MUNITION target it widens an interceptor's effective hit radius
    (aegism_intercept_fnc_ciwsRounds, aegism_intercept_fnc_interceptorPFH) --
    a round that clips the missile's body is a hit even if its blast radius
    measured from the target's centre wouldn't reach. Never used to widen
    the hit radius for an aircraft (the engine's own collision decides
    those). For every target it sizes the CIWS fire gate (aegism_intercept_
    fnc_aimWeapon) and tells CIWS spotting (aegism_intercept_fnc_ciwsSpot) a
    round that passed through the target from one that missed.

    Cached per type ("AEGISM_cacheHitRadius"): it's read every frame.

Parameters:
    _target - the target object to measure <OBJECT>

Returns:
    Half-diagonal of the target's own real bounding box, metres <NUMBER>

Examples:
    [_incomingMissile] call aegism_intercept_fnc_targetHitRadius;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_target"];

if (isNull _target) exitWith { 0 };

private _type = typeOf _target;
private _cache = missionNamespace getVariable "AEGISM_cacheHitRadius";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheHitRadius", _cache];
};
private _cached = _cache get _type;
if (!isNil "_cached") exitWith { _cached };

(boundingBoxReal _target) params ["_min", "_max"];
_cached = (_min distance _max) / 2;
_cache set [_type, _cached];
_cached
