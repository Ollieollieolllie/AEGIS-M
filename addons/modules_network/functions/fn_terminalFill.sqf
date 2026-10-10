/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalFill

Description:
    Fills this machine's open terminal screen with what the terminal
    reaches, as the server worked it out (aegism_network_fnc_terminalScope),
    and picks the first -- or, when its reach has changed since, lists it
    again and keeps what was picked if that's still within it.
    Full notes: docs/functions/modules_network.md

Parameters:
    _nodes - [object, label, "site" or "vehicle"] each <ARRAY>
    _access - "status" or "control" <STRING>
    _engage - the terminal has the Interception page <BOOLEAN, default false>
    _surface - and Surface Strike on it <BOOLEAN, default false>

Returns:
    Nothing

Examples:
    [_nodes, "control"] remoteExecCall ["aegism_network_fnc_terminalFill", _owner];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

params [["_nodes", []], ["_access", "status"], ["_engage", false], ["_surface", false]];

private _display = uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull];
private _state = uiNamespace getVariable "AEGISM_terminalState";
if (isNull _display || {isNil "_state"}) exitWith {};
_state set ["access", _access];
_state set ["engage", _engage];
// Surface Strike: its switch beside the automation switch, on that page.
_state set ["surface", _surface];
if (!_surface) then {
    _state set ["surfaceMode", false];
    _state set ["strikePoint", []];
};
(_state get "autoRect") params ["_autoX", "_autoY", "_autoW", "_autoH"];
(_display displayCtrl AEGISM_TERMINAL_AUTO_IDC) ctrlSetPosition [_autoX, _autoY, [_autoW, 0.58 * _autoW] select _surface, _autoH];
(_display displayCtrl AEGISM_TERMINAL_AUTO_IDC) ctrlCommit 0;
(_display displayCtrl AEGISM_TERMINAL_SURFACE_IDC) ctrlShow (_surface && {(_state get "tab") == "intercept"});
(_display displayCtrl AEGISM_TERMINAL_BADGE_IDC) ctrlSetStructuredText parseText format [
    "<t align='right' size='0.8'><t color='%1'>%2%4</t><t color='%3'>   |   Esc to close</t></t>",
    [AEGISM_TERMINAL_DIM_HEX, AEGISM_TERMINAL_WARN_HEX] select (_access == "control" || {_engage}),
    ["STATUS ONLY", "FULL CONTROL"] select (_access == "control"),
    AEGISM_TERMINAL_DIM_HEX,
    ["", "  +  MANUAL INTERCEPTION"] select _engage];
// The tabs it has, packed to the left.
(_state get "tabRow") params ["_tabX", "_tabY", "_tabW", "_tabH", "_tabGap"];
private _slotX = _tabX + _tabW + _tabGap;
{
    _x params ["_idc", "_has", "_width"];
    private _tab = _display displayCtrl _idc;
    _tab ctrlShow _has;
    if (_has) then {
        _tab ctrlSetPosition [_slotX, _tabY, _width, _tabH];
        _tab ctrlCommit 0;
        _slotX = _slotX + _width + _tabGap;
    };
} forEach [[AEGISM_TERMINAL_TAB_SETTINGS_IDC, _access == "control", _tabW], [AEGISM_TERMINAL_TAB_INTERCEPT_IDC, _engage, 1.3 * _tabW]];

// The same reach as it shows (the request is repeated every few seconds: a
// Site handed the Shared Site Coordinator's place, a vehicle lost, a new
// sync all change it): only its access may have changed.
private _shown = _state get "nodes";
if (_shown isNotEqualTo [] && {_nodes isEqualTo _shown}) exitWith {
    if ((_access != "control" && {(_state get "tab") == "settings"}) || {!_engage && {(_state get "tab") == "intercept"}}) then {
        [-1, "status"] call aegism_network_fnc_terminalSelect;
    };
};

private _list = _display displayCtrl AEGISM_TERMINAL_LIST_IDC;
if (_nodes isEqualTo []) exitWith {
    _state set ["nodes", []];
    _state set ["node", -1];
    lbClear _list;
    (_display displayCtrl AEGISM_TERMINAL_GROUP_IDC) ctrlShow true;
    { (_display displayCtrl _x) ctrlShow false; } forEach ([AEGISM_TERMINAL_FORM_IDC, AEGISM_TERMINAL_APPLY_IDC, AEGISM_TERMINAL_REVERT_IDC, AEGISM_TERMINAL_SURFACE_IDC] + AEGISM_TERMINAL_INTERCEPT_IDCS);
    _state set ["tab", "status"];
    (_display displayCtrl AEGISM_TERMINAL_BOARD_IDC) ctrlSetStructuredText parseText "<t color='#90A4AE'>This terminal isn't synced to a Site or to an AEGIS-M vehicle.</t>";
};

// What was picked, if it's still within reach; else the first.
private _node = _state get "node";
private _picked = if (_node >= 0) then { (_shown param [_node, []]) param [0, objNull] } else { objNull };
private _index = (_nodes findIf { (_x select 0) isEqualTo _picked }) max 0;
_state set ["nodes", _nodes];
_state set ["node", -1];
lbClear _list;
// Grouped: linked Sites under one heading, each other Site and the
// vehicles in no Site apart, a gap between groups. A row's value is its
// node; a heading's or a gap's is -1.
private _lastGroup = "";
private _pickRow = 0;
{
    _x params ["", "_label", "_kind", ["_group", ""]];
    if (_group != _lastGroup) then {
        if (_lastGroup != "") then { _list lbSetValue [_list lbAdd "", -1]; };
        private _heading = switch (true) do {
            case ((_group find "linked:") == 0): { "LINKED SITES" };
            case (_group == "vehicles"): { "VEHICLES IN NO SITE" };
            default { "" };
        };
        if (_heading != "") then {
            private _headRow = _list lbAdd _heading;
            _list lbSetValue [_headRow, -1];
            _list lbSetColor [_headRow, [0.56, 0.64, 0.68, 1]];
        };
        _lastGroup = _group;
    };
    private _row = _list lbAdd ([format ["    %1", _label], _label] select (_kind == "site"));
    _list lbSetValue [_row, _forEachIndex];
    _list lbSetColor [_row, [[0.85, 0.88, 0.9, 1], AEGISM_TERMINAL_ACCENT] select (_kind == "site")];
    if (_forEachIndex == _index) then { _pickRow = _row; };
} forEach _nodes;
// (Selecting a row picks its node: the list's own event.)
_list lbSetCurSel _pickRow;
if ((_state get "node") != _index) then { [_index] call aegism_network_fnc_terminalSelect; };
