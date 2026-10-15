/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugDraw

Description:
    Per-frame 3D debug overlay of AEGIS-M's live detection and engagement
    state, drawn from what the server works out (aegism_fnc_debugModel):
    here on the server, sent to a client that asks (aegism_fnc_debugRequest).
    Full notes: docs/functions/main.md

Parameters:
    None

Returns:
    Nothing (run every frame from aegism's XEH_postInit)

Examples:
    [] call aegism_fnc_debugDraw;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

if !("aegism_main_debugDraw" call CBA_settings_fnc_get) exitWith {};

#define AEGISM_DEBUG_CIRCLE_SEGMENTS 36
// A stacked label's spacing, as a fraction of its distance from the camera:
// about one text line on screen at any range.
#define AEGISM_LINE_SPACING 0.022
// On the server: worked out again at most this often, s.
#define AEGISM_MODEL_REFRESH 0.1
// On a client: drawn while the server's last is no older than this, s (it
// sends one every half second, aegism_fnc_debugPublish).
#define AEGISM_MODEL_STALE 3
// The farthest a position is moved on by its velocity, s.
#define AEGISM_MOVE_ON_MAX 1.5

private _model = if (isServer) then {
    private _built = missionNamespace getVariable ["AEGISM_debugModel", []];
    if (_built isEqualTo [] || {CBA_missionTime - (_built select 0) >= AEGISM_MODEL_REFRESH} || {CBA_missionTime < (_built select 0)}) then {
        _built = [] call aegism_fnc_debugModel;
        missionNamespace setVariable ["AEGISM_debugModel", _built];
    };
    _built
} else {
    missionNamespace getVariable ["AEGISM_debugModel", []]
};
if (_model isEqualTo []) exitWith {};
_model params ["_builtAt", "_rings", "_lines", "_icons", "_texts"];
if (!isServer && {abs (CBA_missionTime - _builtAt) > AEGISM_MODEL_STALE}) exitWith {};

private _camera = positionCameraToWorld [0, 0, 0];
private _age = ((CBA_missionTime - _builtAt) max 0) min AEGISM_MOVE_ON_MAX;
// An anchor's position ASL (aegism_fnc_debugModel): its object's where this
// machine has it, else where the server had it, moved on by its velocity.
private _fnAt = {
    params ["_object", "_position", "_velocity", "_lift", "_eye"];
    private _at = if (isNull _object) then {
        _position vectorAdd (_velocity vectorMultiply _age)
    } else {
        if (_eye) then { eyePos _object } else { getPosASLVisual _object }
    };
    _at vectorAdd [0, 0, _lift]
};

// --- Rings: round their anchor, level with it ---
{
    _x params ["_anchor", "_radius", "_color"];
    private _center = _anchor call _fnAt;
    private _previous = [];
    for "_i" from 0 to AEGISM_DEBUG_CIRCLE_SEGMENTS do {
        private _angle = (_i % AEGISM_DEBUG_CIRCLE_SEGMENTS) * (360 / AEGISM_DEBUG_CIRCLE_SEGMENTS);
        private _point = ASLToAGL (_center vectorAdd [_radius * sin _angle, _radius * cos _angle, 0]);
        if (_i > 0) then { drawLine3D [_previous, _point, _color]; };
        _previous = _point;
    };
} forEach _rings;

// --- Lines: solid, or in dashes ---
{
    _x params ["_fromAnchor", "_toAnchor", "_color", "_dashes"];
    private _from = ASLToAGL (_fromAnchor call _fnAt);
    private _to = ASLToAGL (_toAnchor call _fnAt);
    if (_dashes <= 0) then {
        drawLine3D [_from, _to, _color];
    } else {
        private _span = _to vectorDiff _from;
        for "_i" from 0 to (2 * _dashes - 1) step 2 do {
            drawLine3D [_from vectorAdd (_span vectorMultiply (_i / (2 * _dashes))), _from vectorAdd (_span vectorMultiply ((_i + 1) / (2 * _dashes))), _color];
        };
    };
} forEach _lines;

// --- Icons ---
{
    _x params ["_anchor", "_icon", "_color", "_size"];
    drawIcon3D [_icon, _color, ASLToAGL (_anchor call _fnAt), _size, _size, 0, "", 2];
} forEach _icons;

// --- Labels: stacked that many text lines above their anchor; seconds to
// impact counted down here ---
{
    _x params ["_anchor", "_stack", "_text", "_color", "_size", "_impactAt"];
    private _position = ASLToAGL (_anchor call _fnAt);
    if (_impactAt >= 0) then { _text = format [_text, (round ((_impactAt - CBA_missionTime) * 10) / 10) max 0]; };
    drawIcon3D ["", _color, _position vectorAdd [0, 0, (_camera distance _position) * AEGISM_LINE_SPACING * _stack], 0, 0, 0, _text, 2, _size, "RobotoCondensedBold", "center"];
} forEach _texts;
