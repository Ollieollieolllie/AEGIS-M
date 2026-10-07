/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_targetBody

Description:
    A target's body as AEGIS-M knows it: its model's bounding box, in its
    own model space (x right, y forward, z up), and half its diagonal (the
    sphere that holds all of it).
    Full notes: docs/functions/intercept.md

Parameters:
    _target - the target object <OBJECT>

Returns:
    [box min, box max, half diagonal m] (model space; [[0,0,0], [0,0,0], 0]
    for a null target) <ARRAY>

Examples:
    ([_rocket] call aegism_intercept_fnc_targetBody) params ["_min", "_max", "_radius"];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

params ["_target"];

if (isNull _target) exitWith { [[0, 0, 0], [0, 0, 0], 0] };

private _type = typeOf _target;
private _cache = missionNamespace getVariable "AEGISM_cacheBody";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheBody", _cache];
};
private _cached = _cache get _type;
if (!isNil "_cached") exitWith { _cached };

// Collision layer (clipping type 2, ClipGeometry) first, visual (default) if
// the model has none.
(2 boundingBoxReal _target) params ["_geometryMin", "_geometryMax"];
(boundingBoxReal _target) params ["_visualMin", "_visualMax"];
private _useGeometry = (_geometryMin distance _geometryMax) > 0;
_cached = [[_visualMin, _visualMax], [_geometryMin, _geometryMax]] select _useGeometry;
_cached params ["_min", "_max"];
_cached pushBack ((_min distance _max) / 2);
_cache set [_type, _cached];

private _fnBox = {
    params ["_min", "_max"];
    private _size = _max vectorDiff _min;
    format ["%1 x %2 x %3 m", (_size select 0) toFixed 2, (_size select 1) toFixed 2, (_size select 2) toFixed 2]
};
if (AEGISM_RPT_VERBOSE) then {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TARGET-SIZE: %1 -- collision box %2, visual box %3: the %4 box is its body (half-diagonal %5 m).",
        _type,
        [[_geometryMin, _geometryMax] call _fnBox, "none"] select !_useGeometry,
        [_visualMin, _visualMax] call _fnBox,
        ["visual", "collision"] select _useGeometry, (_cached select 2) toFixed 2];
};
_cached
