/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalMapDraw

Description:
    Draws a terminal's Interception page on its map, every frame, from the
    server's last answer: the weapons' vehicles and the radars, the tracks
    and the Site's own missiles in flight (moved on by their own speed
    since), which weapon is on which track, and the reach of the weapon
    picked.
    Full notes: docs/functions/modules_network.md

Parameters:
    _map - the page's map control <CONTROL>

Returns:
    Nothing

Examples:
    _map ctrlAddEventHandler ["Draw", { _this call aegism_network_fnc_terminalMapDraw; }];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

// A track's leader shows where it will be this many seconds on.
#define AEGISM_TERMINAL_LEADER 5
// One of the Site's own missiles trails where it was this long ago, s.
#define AEGISM_TERMINAL_TAIL 1

params ["_map"];

private _state = uiNamespace getVariable "AEGISM_terminalState";
if (isNil "_state" || {(_state get "tab") != "intercept"}) exitWith {};

(_state getOrDefault ["picture", []]) params ["", "", "", "", ["_tracks", []], ["_weapons", []], "", "", ["_missiles", []], ["_radars", []]];
(_state getOrDefault ["icons", []]) params [["_iconTrack", ""], ["_iconAir", ""], ["_iconPick", ""], ["_iconVehicle", ""], ["_iconMissile", ""], ["_iconRadar", ""]];
private _age = (CBA_missionTime - (_state getOrDefault ["pictureAt", CBA_missionTime])) min 3;
private _trackKey = _state getOrDefault ["trackKey", ""];

// --- The weapons' vehicles, the reach of the weapon picked, the radars --------
// (Launchers standing together are one row of the list, and one name here.)
private _labelled = _state getOrDefault ["labelled", []];
private _drawn = [];
{
    _x params ["_vehicle", "_reach"];
    if (!isNull _vehicle && {_reach > 0}) then { _map drawEllipse [getPosASL _vehicle, _reach, _reach, 0, AEGISM_TERMINAL_ACCENT, ""]; };
} forEach (_state getOrDefault ["rings", []]);
{
    _x params ["_vehicle", "", "", "", "", "_rounds"];
    if (!isNull _vehicle && {!(_vehicle in _drawn)}) then {
        _drawn pushBack _vehicle;
        private _name = if (_vehicle in _labelled) then { getText (configOf _vehicle >> "displayName") } else { "" };
        _map drawIcon [_iconVehicle, [AEGISM_TERMINAL_TRACK_NEUTRAL, AEGISM_TERMINAL_ACCENT] select (_rounds > 0), getPosASL _vehicle, 22, 22, 0, _name, 1, 0.032, "RobotoCondensed", "right"];
    };
} forEach _weapons;
private _radarId = _state getOrDefault ["radarId", ""];
{
    _x params ["_vehicle", "_on", "_order"];
    if (!isNull _vehicle) then {
        private _position = getPosASL _vehicle;
        if (netId _vehicle == _radarId) then { _map drawIcon [_iconPick, [1, 1, 1, 1], _position, 34, 34, 0, "", 0, 0.03, "RobotoCondensed", "right"]; };
        _map drawIcon [_iconRadar, [AEGISM_TERMINAL_RADAR_OFF, AEGISM_TERMINAL_RADAR_ON] select _on, _position, 24, 24, 0,
            format ["%1%2%3", ["", getText (configOf _vehicle >> "displayName") + "  "] select !(_vehicle in _drawn), ["SILENT", "EMITTING"] select _on, ["", " (ordered)"] select (_order != "")],
            1, 0.03, "RobotoCondensed", "left"];
    };
} forEach _radars;

// --- The Site's own missiles in flight ------------------------------------------
{
    _x params ["_position", "_velocity", "_manual"];
    private _now = _position vectorAdd (_velocity vectorMultiply _age);
    private _colour = [AEGISM_TERMINAL_MISSILE, AEGISM_TERMINAL_TRACK_ORDERED] select _manual;
    // (Where it has just been: a short tail.)
    _map drawLine [_now vectorDiff (_velocity vectorMultiply AEGISM_TERMINAL_TAIL), _now, _colour];
    _map drawIcon [_iconMissile, _colour, _now, 16, 16, (_velocity select 0) atan2 (_velocity select 1), "", 1, 0.03, "RobotoCondensed", "right"];
} forEach _missiles;

// --- The tracks -------------------------------------------------------------------
{
    _x params ["_key", "_class", "_kind", "_position", "_velocity", "_name", "_tti", "_on"];
    private _now = _position vectorAdd (_velocity vectorMultiply _age);
    private _colour = switch (_kind) do {
        case "threat": { AEGISM_TERMINAL_TRACK_THREAT };
        case "ordered": { AEGISM_TERMINAL_TRACK_ORDERED };
        case "hostile": { AEGISM_TERMINAL_TRACK_HOSTILE };
        case "friendly": { AEGISM_TERMINAL_TRACK_FRIENDLY };
        default { AEGISM_TERMINAL_TRACK_NEUTRAL };
    };
    private _picked = _key == _trackKey;

    // Which weapon is on it, in its engagement's own colour (aegism_fnc_
    // statusStyle); an order's line is the order colour.
    {
        _x params ["_vehicle", "", "_status", "_manual"];
        if (!isNull _vehicle) then {
            _map drawLine [getPosASL _vehicle, _now, [([_status] call aegism_fnc_statusStyle) select 1, AEGISM_TERMINAL_TRACK_ORDERED] select _manual];
        };
    } forEach _on;

    if ((vectorMagnitude _velocity) > 1) then {
        _map drawLine [_now, _now vectorAdd (_velocity vectorMultiply AEGISM_TERMINAL_LEADER), _colour];
    };
    if (_picked) then { _map drawIcon [_iconPick, [1, 1, 1, 1], _now, 34, 34, 0, "", 0, 0.03, "RobotoCondensed", "right"]; };
    private _isMunition = _class in ["missile", "rocket", "bomb", "artilleryShell"];
    // (Every track has its name in the list; on the map only the one
    // picked, aircraft, and what's about to land, so a salvo stays readable.)
    private _label = if (_picked || {!_isMunition} || {_tti < 15}) then {
        [_name, format ["%1  %2 s", _name, round _tti]] select (_tti < 1e9)
    } else { "" };
    _map drawIcon [[_iconAir, _iconTrack] select _isMunition, _colour, _now, [20, 14] select _isMunition, [20, 14] select _isMunition,
        (_velocity select 0) atan2 (_velocity select 1), _label, 1, 0.03, "RobotoCondensed", "right"];
} forEach _tracks;
