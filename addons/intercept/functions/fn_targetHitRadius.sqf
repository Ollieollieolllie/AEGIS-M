/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_targetHitRadius

Description:
    A target's physical half-size from its own model: half the diagonal of
    its bounding box, i.e. a sphere that contains the whole body.

    The box is taken from the model's collision (Geometry) layer where it
    has one -- the body itself. The visual layer's box can be much bigger
    than the body: an MLRS rocket (R_230mm_HE, about 4m long) measured a
    6.2m radius from it, so a CIWS was credited with kills 5-6m wide of the
    rocket, and against that "size" even the gun's physics-based open-fire
    range stretched to its full 6km reach. A projectile with no collision
    layer uses the visual box.

    For a MUNITION target it widens an interceptor's effective hit radius
    (aegism_intercept_fnc_ciwsRounds, aegism_intercept_fnc_interceptorPFH) --
    a round that clips the missile's body is a hit even if its blast radius
    measured from the target's centre wouldn't reach. Never used to widen
    the hit radius for an aircraft (the engine's own collision decides
    those). For every target it sizes the CIWS fire gate (aegism_intercept_
    fnc_aimWeapon) and tells CIWS spotting (aegism_intercept_fnc_ciwsSpot) a
    round that passed through the target from one that missed.

    Cached per type ("AEGISM_cacheHitRadius"): it's read every frame. Each
    type's boxes (collision and visual) and the radius used are logged once
    (TARGET-SIZE).

Parameters:
    _target - the target object to measure <OBJECT>

Returns:
    Half-diagonal of the target's own real bounding box, metres <NUMBER>

Examples:
    [_incomingMissile] call aegism_intercept_fnc_targetHitRadius;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

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

// Collision layer (clipping type 2, ClipGeometry) first, visual (default) if
// the model has none.
(2 boundingBoxReal _target) params ["_geometryMin", "_geometryMax"];
(boundingBoxReal _target) params ["_visualMin", "_visualMax"];
private _geometryRadius = (_geometryMin distance _geometryMax) / 2;
private _visualRadius = (_visualMin distance _visualMax) / 2;
private _useGeometry = _geometryRadius > 0;
_cached = [_visualRadius, _geometryRadius] select _useGeometry;
_cache set [_type, _cached];

private _fnBox = {
    params ["_min", "_max"];
    private _size = _max vectorDiff _min;
    format ["%1 x %2 x %3 m", (_size select 0) toFixed 2, (_size select 1) toFixed 2, (_size select 2) toFixed 2]
};
if (AEGISM_RPT_VERBOSE) then {
    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " TARGET-SIZE: %1 -- collision box %2, visual box %3: hit radius %4m (half the %5 box's diagonal).",
        _type,
        [[_geometryMin, _geometryMax] call _fnBox, "none"] select !_useGeometry,
        [_visualMin, _visualMax] call _fnBox,
        _cached toFixed 2, ["visual", "collision"] select _useGeometry];
};
_cached
