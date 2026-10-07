/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalCommand

Description:
    One thing done on this machine's open terminal screen, on its
    Interception page: a track or weapon picked (in a list, or on the map),
    or an order sent to the server.
    Full notes: docs/functions/modules_network.md

Parameters:
    _command - "request" (ask for the picture), "track" [contact key],
        "weapon" [weapon row id], "radar" [radar id], "mapClick" [map
        control, x, y], "engage", "cease", "automation", "radarOrder"
        ["on", "off" or ""], "surface" (Surface Strike's switch) <STRING>
    _args - as its command needs <ARRAY, default []>

Returns:
    Nothing

Examples:
    ["engage"] call aegism_network_fnc_terminalCommand;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

params [["_command", ""], ["_args", []]];

private _display = uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull];
private _state = uiNamespace getVariable "AEGISM_terminalState";
if (isNull _display || {isNil "_state"}) exitWith {};
if ((_state get "tab") != "intercept") exitWith {};

private _node = ((_state get "nodes") param [_state get "node", []]) param [0, objNull];
if (isNull _node) exitWith {};
private _terminal = _state get "terminal";
private _anchor = _state get "anchor";
(_state getOrDefault ["picture", []]) params ["", "", ["_automation", true], "", ["_tracks", []], ["_weapons", []]];

// (What's picked goes with it, for the weapons' "has a shot": a track's
// key, or the strike point itself -- "@strike" in the track list.)
private _fnRequest = {
    private _picked = _state getOrDefault ["trackKey", ""];
    if (_picked == "@strike") then { _picked = _state getOrDefault ["strikePoint", []]; };
    [_terminal, _anchor, _node, _picked] remoteExecCall ["aegism_network_fnc_terminalPicture", 2];
};
private _fnNote = {
    (_display displayCtrl AEGISM_TERMINAL_NOTE_IDC) ctrlSetStructuredText parseText format ["<t size='0.85' color='%1'>%2</t>", AEGISM_TERMINAL_DIM_HEX, _this];
};

switch (_command) do {
    case "request": { call _fnRequest; };

    // A pick only: the lists are filled again every second, and putting
    // their selection back isn't one.
    case "track": {
        _args params [["_key", ""]];
        if (!(_state getOrDefault ["filling", false]) && {_key != (_state getOrDefault ["trackKey", ""])}) then {
            _state set ["trackKey", _key];
            call _fnRequest;
        };
    };
    case "weapon": {
        _args params [["_id", ""]];
        if (!(_state getOrDefault ["filling", false]) && {_id != (_state getOrDefault ["weaponId", ""])}) then {
            _state set ["weaponId", _id];
            call _fnRequest;
        };
    };

    case "radar": {
        _args params [["_id", ""]];
        if !(_state getOrDefault ["filling", false]) then { _state set ["radarId", _id]; };
    };

    // The radar picked -- or, with the list's first row picked, every one.
    case "radarOrder": {
        _args params [["_order", ""]];
        private _id = _state getOrDefault ["radarId", ""];
        private _radars = (((_state getOrDefault ["picture", []]) param [9, []]) apply { _x select 0 }) select { _id == "" || {netId _x == _id} };
        if (_radars isEqualTo []) exitWith { "There's no radar there to order." call _fnNote; };
        "Sending..." call _fnNote;
        [_terminal, _anchor, _node, "radar", [[_radars, []] select (_id == ""), _order]] remoteExecCall ["aegism_network_fnc_terminalOrder", 2];
        call _fnRequest;
    };

    // The track nearest the click, if one is near.
    case "mapClick": {
        _args params ["_map", "_clickX", "_clickY"];
        private _age = (CBA_missionTime - (_state getOrDefault ["pictureAt", CBA_missionTime])) min 3;
        private _best = "";
        private _bestDistance = AEGISM_TERMINAL_PICK_RADIUS;
        {
            _x params ["_key", "", "", "_position", "_velocity"];
            private _screen = _map ctrlMapWorldToScreen (_position vectorAdd (_velocity vectorMultiply _age));
            private _distance = _screen distance2D [_clickX, _clickY];
            if (_distance < _bestDistance) then {
                _bestDistance = _distance;
                _best = _key;
            };
        } forEach _tracks;
        if (_best != "" && {_best != (_state getOrDefault ["trackKey", ""])}) then {
            _state set ["trackKey", _best];
            call _fnRequest;
        };
        // No track there, and Surface Strike switched on: the strike point.
        if (_best == "" && {_state getOrDefault ["surfaceMode", false]}) then {
            private _world = _map ctrlMapScreenToWorld [_clickX, _clickY];
            _state set ["strikePoint", [_world select 0, _world select 1, (getTerrainHeightASL _world) max 0]];
            _state set ["trackKey", "@strike"];
            call _fnRequest;
        };
    };

    case "engage": {
        // (A row of several launchers: the server has the best placed of
        // them fire.)
        private _key = _state getOrDefault ["trackKey", ""];
        private _id = _state getOrDefault ["weaponId", ""];
        private _rows = _state getOrDefault ["rows", []];
        private _index = _rows findIf { (_x select 0) == _id };
        if (_key == "" || {_index == -1}) exitWith { "Pick a track and a weapon first." call _fnNote; };
        (_rows select _index) params ["", "_vehicles", "_turretPath", "_weaponClass"];
        "Sending..." call _fnNote;
        if (_key == "@strike") then {
            [_terminal, _anchor, _node, "strike", [_state getOrDefault ["strikePoint", []], _vehicles, _turretPath, _weaponClass]] remoteExecCall ["aegism_network_fnc_terminalOrder", 2];
        } else {
            [_terminal, _anchor, _node, "engage", [_key, _vehicles, _turretPath, _weaponClass]] remoteExecCall ["aegism_network_fnc_terminalOrder", 2];
        };
        call _fnRequest;
    };

    // The orders on the track picked; with none picked, every one.
    case "cease": {
        "Sending..." call _fnNote;
        [_terminal, _anchor, _node, "cease", [_state getOrDefault ["trackKey", ""]]] remoteExecCall ["aegism_network_fnc_terminalOrder", 2];
        call _fnRequest;
    };

    // Surface Strike's switch: off takes the strike point away.
    case "surface": {
        if !(_state getOrDefault ["surface", false]) exitWith {};
        private _on = !(_state getOrDefault ["surfaceMode", false]);
        _state set ["surfaceMode", _on];
        (_display displayCtrl AEGISM_TERMINAL_SURFACE_IDC) ctrlSetText (["SURFACE: OFF", "SURFACE: ON"] select _on);
        if (_on) then {
            "Surface strike: click the map where no track is to put the strike point." call _fnNote;
        } else {
            _state set ["strikePoint", []];
            if ((_state getOrDefault ["trackKey", ""]) == "@strike") then { _state set ["trackKey", ""]; };
            "" call _fnNote;
            call _fnRequest;
        };
    };

    case "automation": {
        "Sending..." call _fnNote;
        // (Shown at once; the server's next answer says how it stands.)
        (_display displayCtrl AEGISM_TERMINAL_AUTO_IDC) ctrlSetText (["AUTOMATION: ON", "AUTOMATION: OFF  (orders only)"] select _automation);
        [_terminal, _anchor, _node, "automation", [!_automation]] remoteExecCall ["aegism_network_fnc_terminalOrder", 2];
        call _fnRequest;
    };
};
