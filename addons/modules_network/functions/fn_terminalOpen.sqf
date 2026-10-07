/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalOpen

Description:
    Opens a terminal's screen on this machine: what it reaches on the left
    (its Sites and their vehicles), and for the one picked a Status tab
    (the live status board) and, on a control terminal, a Settings tab.
    Full notes: docs/functions/modules_network.md

Parameters:
    _anchor - the Site or vehicle the terminal is synced to <OBJECT>
    _terminal - the terminal it's opened from <OBJECT>

Returns:
    Nothing

Examples:
    [_site, _laptop] call aegism_network_fnc_terminalOpen;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

params ["_anchor", "_terminal"];

if (!hasInterface || {!isNull (uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull])}) exitWith {};

private _display = (findDisplay 46) createDisplay "RscDisplayEmpty";
if (isNull _display) exitWith {};
uiNamespace setVariable ["AEGISM_terminalDisplay", _display];
// The screen's state: what it reaches ("nodes", from the server), the one
// picked, the tab shown, and the settings form built for it.
uiNamespace setVariable ["AEGISM_terminalState", createHashMapFromArray [
    ["terminal", _terminal], ["anchor", _anchor], ["access", "status"], ["nodes", []], ["node", -1],
    ["tab", "status"], ["rows", []], ["formControls", []], ["formFor", objNull]
]];
_display displayAddEventHandler ["Unload", { uiNamespace setVariable ["AEGISM_terminalState", nil]; }];

private _x0 = safeZoneX + 0.15 * safeZoneW;
private _y0 = safeZoneY + 0.1 * safeZoneH;
private _w = 0.7 * safeZoneW;
private _h = 0.8 * safeZoneH;
private _titleH = 0.045 * safeZoneH;
private _padX = 0.008 * safeZoneW;
private _padY = 0.012 * safeZoneH;
private _listW = 0.24 * _w;
private _tabH = 0.035 * safeZoneH;
private _tabW = 0.1 * _w;
private _footH = 0.04 * safeZoneH;
private _paneX = _x0 + 2 * _padX + _listW;
private _paneW = _w - _listW - 3 * _padX;
private _bodyY = _y0 + _titleH + _padY;
private _bodyH = _h - _titleH - 2 * _padY;
private _contentY = _bodyY + _tabH + _padY;
private _contentH = _bodyH - _tabH - _footH - 2 * _padY;

// A plain panel.
private _fnPanel = {
    params ["_position", "_colour"];
    private _panel = _display ctrlCreate ["RscText", -1];
    _panel ctrlSetPosition _position;
    _panel ctrlSetBackgroundColor _colour;
    _panel ctrlCommit 0;
    _panel
};

[[_x0, _y0, _w, _h], [0.04, 0.06, 0.08, 0.95]] call _fnPanel;

private _title = _display ctrlCreate ["RscStructuredText", -1];
_title ctrlSetPosition [_x0, _y0, _w, _titleH];
_title ctrlSetBackgroundColor [0.09, 0.2, 0.27, 1];
_title ctrlSetStructuredText parseText "<t font='PuristaSemibold' size='1.1' color='#4FC3F7'>AEGIS-M Site Terminal</t>";
_title ctrlCommit 0;

private _badge = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_BADGE_IDC];
_badge ctrlSetPosition [_x0 + 0.4 * _w, _y0 + 0.008 * safeZoneH, 0.6 * _w - _padX, _titleH];
_badge ctrlSetStructuredText parseText "<t align='right' size='0.8' color='#90A4AE'>Esc to close</t>";
_badge ctrlCommit 0;

// What it reaches.
[[_x0 + _padX, _bodyY, _listW, _bodyH], [1, 1, 1, 0.04]] call _fnPanel;
private _list = _display ctrlCreate ["RscListBox", AEGISM_TERMINAL_LIST_IDC];
_list ctrlSetPosition [_x0 + _padX, _bodyY, _listW, _bodyH];
_list ctrlSetBackgroundColor [0, 0, 0, 0];
_list ctrlCommit 0;
_list ctrlAddEventHandler ["LBSelChanged", {
    params ["", "_index"];
    [_index] call aegism_network_fnc_terminalSelect;
}];

// The tabs, and what's picked.
private _tabStatus = _display ctrlCreate ["RscButtonMenu", AEGISM_TERMINAL_TAB_STATUS_IDC];
_tabStatus ctrlSetPosition [_paneX, _bodyY, _tabW, _tabH];
_tabStatus ctrlSetText "STATUS";
_tabStatus ctrlCommit 0;
_tabStatus ctrlAddEventHandler ["ButtonClick", { [-1, "status"] call aegism_network_fnc_terminalSelect; }];

private _tabSettings = _display ctrlCreate ["RscButtonMenu", AEGISM_TERMINAL_TAB_SETTINGS_IDC];
_tabSettings ctrlSetPosition [_paneX + _tabW + _padX, _bodyY, _tabW, _tabH];
_tabSettings ctrlSetText "SETTINGS";
_tabSettings ctrlCommit 0;
_tabSettings ctrlShow false;
_tabSettings ctrlAddEventHandler ["ButtonClick", { [-1, "settings"] call aegism_network_fnc_terminalSelect; }];

private _heading = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_HEADING_IDC];
_heading ctrlSetPosition [_paneX + 2 * (_tabW + _padX), _bodyY + 0.004 * safeZoneH, _paneW - 2 * (_tabW + _padX), _tabH];
_heading ctrlCommit 0;

[[_paneX, _contentY, _paneW, _contentH], [1, 1, 1, 0.04]] call _fnPanel;

// Status: the board, scrolling.
private _group = _display ctrlCreate ["RscControlsGroupNoHScrollbars", AEGISM_TERMINAL_GROUP_IDC];
_group ctrlSetPosition [_paneX + _padX, _contentY + _padY, _paneW - 2 * _padX, _contentH - 2 * _padY];
_group ctrlCommit 0;
private _board = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_BOARD_IDC, _group];
_board ctrlSetPosition [0, 0, _paneW - 2 * _padX - 0.02 * safeZoneW, _contentH - 2 * _padY];
_board ctrlSetStructuredText parseText "<t color='#90A4AE'>Connecting...</t>";
_board ctrlCommit 0;

// Settings: the form (aegism_network_fnc_terminalSelect builds it).
private _form = _display ctrlCreate ["RscControlsGroupNoHScrollbars", AEGISM_TERMINAL_FORM_IDC];
_form ctrlSetPosition [_paneX + _padX, _contentY + _padY, _paneW - 2 * _padX, _contentH - 2 * _padY];
_form ctrlCommit 0;
_form ctrlShow false;

private _footY = _contentY + _contentH + _padY;
private _apply = _display ctrlCreate ["RscButtonMenu", AEGISM_TERMINAL_APPLY_IDC];
_apply ctrlSetPosition [_paneX, _footY, _tabW, _footH];
_apply ctrlSetText "APPLY";
_apply ctrlCommit 0;
_apply ctrlShow false;
_apply ctrlAddEventHandler ["ButtonClick", { [] call aegism_network_fnc_terminalSend; }];

private _revert = _display ctrlCreate ["RscButtonMenu", AEGISM_TERMINAL_REVERT_IDC];
_revert ctrlSetPosition [_paneX + _tabW + _padX, _footY, _tabW, _footH];
_revert ctrlSetText "REVERT";
_revert ctrlCommit 0;
_revert ctrlShow false;
_revert ctrlAddEventHandler ["ButtonClick", { [-1, "", true] call aegism_network_fnc_terminalSelect; }];

private _note = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_NOTE_IDC];
_note ctrlSetPosition [_paneX + 2 * (_tabW + _padX), _footY + 0.006 * safeZoneH, _paneW - 2 * (_tabW + _padX), _footH];
_note ctrlCommit 0;

// Once a second while it's open: what it reaches, until the server has
// answered and every fifth second after (its reach changes with the Sites'
// links and coordinator); and the board of the one picked, while Status is
// shown.
[{
    params ["_args", "_pfhHandle"];
    _args params ["_anchor", "_terminal", "_display", "_count"];
    _args set [3, _count + 1];
    if (isNull _display) exitWith { [_pfhHandle] call CBA_fnc_removePerFrameHandler; };
    if (isNull _terminal) exitWith {
        _display closeDisplay 2;
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };
    private _state = uiNamespace getVariable ["AEGISM_terminalState", createHashMap];
    private _nodes = _state getOrDefault ["nodes", []];
    if (_nodes isEqualTo [] || {_count mod 5 == 4}) then {
        [_terminal, _anchor, true] remoteExecCall ["aegism_network_fnc_terminalScope", 2];
    };
    if ((_state getOrDefault ["tab", "status"]) == "status") then {
        private _node = _nodes param [_state getOrDefault ["node", -1], []];
        if (_node isNotEqualTo []) then { [_node select 0] remoteExecCall ["aegism_network_fnc_terminalRequest", 2]; };
    };
}, 1, [_anchor, _terminal, _display, 0]] call CBA_fnc_addPerFrameHandler;

[_terminal, _anchor, true] remoteExecCall ["aegism_network_fnc_terminalScope", 2];
