/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_debugProbeMunitions

Description:
    In-game probe, run from the debug console while testing (on the server:
    in single player or as host the local console is fine).
    Full notes: docs/functions/intercept.md

Parameters:
    _on - start (true) or stop (false) <BOOLEAN, default true>

Returns:
    Nothing

Examples:
    [] call aegism_intercept_fnc_debugProbeMunitions;
    [false] call aegism_intercept_fnc_debugProbeMunitions;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Lines per axis when measuring: the box's size over this many steps.
#define AEGISM_PROBE_STEPS 200
// How far into its flight a munition is probed, s.
#define AEGISM_PROBE_AFTER 0.5

params [["_on", true]];

private _fnSay = {
    params ["_text"];
    diag_log text ("[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " " + _text);
    systemChat ("[AEGIS-M] " + _text);
};

if (!isServer) exitWith { ["PROBE: run it on the server (the local debug console in single player or as host; Server Exec on a dedicated server) -- that's where AEGIS-M tracks munitions."] call _fnSay; };

private _handle = missionNamespace getVariable ["AEGISM_probeHandle", -1];
if (_handle >= 0) then {
    [_handle] call CBA_fnc_removePerFrameHandler;
    missionNamespace setVariable ["AEGISM_probeHandle", -1];
};
if (!_on) exitWith { ["PROBE: stopped."] call _fnSay; };

// Measures one munition (see notes).
private _fnProbe = {
    params ["_projectile", "_fnSay"];
    private _started = diag_tickTime;
    (boundingBoxReal _projectile) params ["_min", "_max"];
    private _size = _max vectorDiff _min;
    private _mid = (_min vectorAdd _max) vectorMultiply 0.5;
    // Its model space in the world this frame: x right, y forward, z up.
    private _origin = getPosWorld _projectile;
    private _dir = vectorDir _projectile;
    private _up = vectorUp _projectile;
    private _right = _dir vectorCrossProduct _up;
    private _fnWorld = {
        params ["_m"];
        _origin vectorAdd (_right vectorMultiply (_m select 0)) vectorAdd (_dir vectorMultiply (_m select 1)) vectorAdd (_up vectorMultiply (_m select 2))
    };
    // A line between two model points touches the projectile in that LOD.
    private _fnTouches = {
        params ["_a", "_b", "_lod"];
        ((lineIntersectsSurfaces [[_a] call _fnWorld, [_b] call _fnWorld, objNull, objNull, true, -1, _lod, "NONE", false]) findIf {
            (_x select 2) == _projectile || {(_x select 3) == _projectile}
        }) != -1
    };
    // Where along one axis lines across the box touch it: [from, to], or [].
    // _axis: the axis stepped along (0 x, 1 y, 2 z); _across: the axis each
    // line runs along; _at: the line's position on the remaining axis.
    private _fnScan = {
        params ["_lod", "_axis", "_across", "_at"];
        private _other = ([0, 1, 2] - [_axis, _across]) select 0;
        private _step = ((_size select _axis) / AEGISM_PROBE_STEPS) max 0.001;
        private _from = 1e10;
        private _to = -1e10;
        for "_v" from ((_min select _axis) - _step) to ((_max select _axis) + _step) step _step do {
            private _a = [0, 0, 0];
            _a set [_axis, _v];
            _a set [_other, _at];
            private _b = +_a;
            _a set [_across, (_min select _across) - 1];
            _b set [_across, (_max select _across) + 1];
            if ([_a, _b, _lod] call _fnTouches) then {
                _from = _from min _v;
                _to = _to max _v;
            };
        };
        [[], [_from, _to]] select (_to >= _from)
    };

    // Which LODs can hit it at all: lines side-on along its length.
    private _lods = ["GEOM", "FIRE", "VIEW", "IFIRE", "PHYSX"];
    private _lengths = _lods apply { [_x, 1, 0, _mid select 2] call _fnScan };
    private _found = _lengths findIf { _x isNotEqualTo [] };
    private _hitBy = [];
    { if ((_lengths select _forEachIndex) isNotEqualTo []) then { _hitBy pushBack _x; }; } forEach _lods;
    private _body = "";
    if (_found != -1) then {
        private _lod = _lods select _found;
        (_lengths select _found) params ["_y0", "_y1"];
        private _yMid = (_y0 + _y1) / 2;
        // Across the body at the middle of its length: width (lines along
        // z, stepping x) and height (lines along x, stepping z).
        private _width = [_lod, 0, 2, _yMid] call _fnScan;
        private _height = [_lod, 2, 0, _yMid] call _fnScan;
        private _fnSpan = { params ["_range"]; if (_range isEqualTo []) then { "?" } else { ((_range select 1) - (_range select 0)) toFixed 2 } };
        _body = format ["Body in %1: %2 m long (model y %3 to %4 m), %5 m wide, %6 m high.",
            _lod, (_y1 - _y0) toFixed 2, _y0 toFixed 2, _y1 toFixed 2, [_width] call _fnSpan, [_height] call _fnSpan];
    } else {
        _body = "No LOD hit it: lineIntersectsSurfaces can't see this projectile, so its box is all AEGIS-M has to go on.";
    };
    [format ["PROBE: %1 (model %2) -- box %3 x %4 x %5 m (half-diagonal %6 m). LODs that hit it: %7. %8 (%9 ms)",
        typeOf _projectile, getText (configOf _projectile >> "model"),
        (_size select 0) toFixed 2, (_size select 1) toFixed 2, (_size select 2) toFixed 2,
        ([_projectile] call aegism_intercept_fnc_targetHitRadius) toFixed 2,
        [_hitBy joinString ", ", "none"] select (_hitBy isEqualTo []),
        _body, ((diag_tickTime - _started) * 1000) toFixed 1]] call _fnSay;
};

missionNamespace setVariable ["AEGISM_probeDone", createHashMap];
_handle = [{
    params ["_args"];
    _args params ["_fnProbe", "_fnSay"];
    private _done = missionNamespace getVariable ["AEGISM_probeDone", createHashMap];
    {
        _x params ["_projectile", "", "", "", "", "", "", "_flags"];
        private _ammo = _flags getOrDefault ["ammo", ""];
        if (!(_ammo in _done) && {!isNull _projectile} && {alive _projectile} && {CBA_missionTime - (_flags getOrDefault ["firedAt", CBA_missionTime]) >= AEGISM_PROBE_AFTER}) then {
            _done set [_ammo, true];
            [_projectile, _fnSay] call _fnProbe;
        };
    } forEach (missionNamespace getVariable ["AEGISM_trackedMunitions", []]);
}, 0, [_fnProbe, _fnSay]] call CBA_fnc_addPerFrameHandler;
missionNamespace setVariable ["AEGISM_probeHandle", _handle];

["PROBE: on -- each new ammo type AEGIS-M tracks is probed once in flight. [false] call aegism_intercept_fnc_debugProbeMunitions stops it."] call _fnSay;
