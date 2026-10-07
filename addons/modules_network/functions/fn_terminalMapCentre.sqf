/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalMapCentre

Description:
    Brings the Interception page's map onto a point, showing a given width
    of ground: moves it, measures what it then really shows, and corrects,
    a few frames apart. Run every frame while a move is asked for.
    Full notes: docs/functions/modules_network.md

Parameters:
    _args - unused <ARRAY>
    _handle - this per-frame handler <NUMBER>

Returns:
    Nothing

Examples:
    [{ _this call aegism_network_fnc_terminalMapCentre; }, 0, []] call CBA_fnc_addPerFrameHandler;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

// Frames left between a move and measuring what it did.
#define AEGISM_TERMINAL_CENTRE_WAIT 3
// Moves at most.
#define AEGISM_TERMINAL_CENTRE_TRIES 6
// Close enough: the width shown within this fraction of the one asked for,
// and the middle within this fraction of that width of the point.
#define AEGISM_TERMINAL_CENTRE_SPAN_SLACK 0.05
#define AEGISM_TERMINAL_CENTRE_SLACK 0.01

params ["", "_handle"];

private _display = uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull];
private _state = uiNamespace getVariable "AEGISM_terminalState";
private _centre = if (isNil "_state") then { [] } else { _state getOrDefault ["mapCentre", []] };
if (isNull _display || {_centre isEqualTo []}) exitWith {
    if (!isNil "_state") then { _state set ["mapCentreHandle", -1]; };
    [_handle] call CBA_fnc_removePerFrameHandler;
};
// (Only while the page shows: the map has no size otherwise.)
if ((_state get "tab") != "intercept") exitWith {};

// [point, width of ground to show m, moves made, where the last move aimed,
// frames to wait, what the first move left: [width shown, m off]]
_centre params ["_position", "_span", "_moves", "_aim", "_wait", "_first"];
private _map = _display displayCtrl AEGISM_TERMINAL_MAP_IDC;
(ctrlPosition _map) params ["_mapX", "_mapY", "_mapW", "_mapH"];
if (_mapW <= 0) exitWith {};
if (_wait > 0) exitWith { _centre set [4, _wait - 1]; };
if !(ctrlMapAnimDone _map) exitWith {};

// What it shows now: the ground across its middle row, and at its middle.
private _left = _map ctrlMapScreenToWorld [_mapX, _mapY + _mapH / 2];
private _right = _map ctrlMapScreenToWorld [_mapX + _mapW, _mapY + _mapH / 2];
private _middle = _map ctrlMapScreenToWorld [_mapX + _mapW / 2, _mapY + _mapH / 2];
private _shown = abs ((_right select 0) - (_left select 0));
private _off = [(_position select 0) - (_middle select 0), (_position select 1) - (_middle select 1), 0];
private _scale = ctrlMapScale _map;

private _good = _moves > 0 && {abs (_shown - _span) <= AEGISM_TERMINAL_CENTRE_SPAN_SLACK * _span} && {(vectorMagnitude _off) <= AEGISM_TERMINAL_CENTRE_SLACK * _span};
if (_moves == 1) then { _centre set [5, [_shown, vectorMagnitude _off]]; };
if (_good || {_moves >= AEGISM_TERMINAL_CENTRE_TRIES}) exitWith {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL-MAP: %1 on %2 after %3 move(s): shows %4m across (asked %5m), its middle %6m off, scale %7; the first move left it showing %8m, %9m off. Control at %10.",
        ["NOT centred", "centred"] select _good, _position select [0, 2], _moves, round _shown, round _span, round (vectorMagnitude _off), _scale,
        round (_first param [0, -1]), round (_first param [1, -1]), [_mapX, _mapY, _mapW, _mapH]];
    _state set ["mapCentre", []];
};

// The next move: the scale that shows the width asked for (what's shown is
// in proportion to it), and aimed off by as much as the last move landed
// off -- wherever the game puts the point it's given, that brings it to the
// middle of the control.
private _zoom = if (_shown > 0) then { ((_scale * _span / _shown) max 0.001) min 1 } else { _scale };
// (What's off was measured at the old scale; at the new one it's that much
// smaller or larger.)
private _nextAim = if (_moves == 0) then { _position select [0, 2] } else {
    private _ratio = if (_scale > 0) then { _zoom / _scale } else { 1 };
    [(_aim select 0) + (_off select 0) * _ratio, (_aim select 1) + (_off select 1) * _ratio]
};
_map ctrlMapAnimAdd [0, _zoom, _nextAim];
ctrlMapAnimCommit _map;
_centre set [2, _moves + 1];
_centre set [3, _nextAim];
_centre set [4, AEGISM_TERMINAL_CENTRE_WAIT];
