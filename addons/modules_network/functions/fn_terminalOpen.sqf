/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalOpen

Description:
    Opens a terminal's screen on this machine: what it reaches on the left
    (its Sites and their vehicles), and for the one picked a Status tab
    (the live status board), on a control terminal a Settings tab, and on
    one with manual interception an Interception tab (map, tracks, weapons).
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
// picked, the tab shown, and the settings form built for it; for the
// Interception page, whether the terminal has it ("engage"), the server's
// last answer ("picture") and the track and weapon picked there.
private _fnMarkerIcon = { getText (configFile >> "CfgMarkers" >> _this >> "icon") };
uiNamespace setVariable ["AEGISM_terminalState", createHashMapFromArray [
    ["terminal", _terminal], ["anchor", _anchor], ["access", "status"], ["engage", false], ["nodes", []], ["node", -1],
    ["tab", "status"], ["formRows", []], ["formControls", []], ["formFor", objNull],
    ["picture", []], ["pictureAt", 0], ["pictureFor", objNull], ["trackKey", ""], ["weaponId", ""], ["filling", false],
    ["rows", []], ["rings", []], ["labelled", []], ["radarId", ""],
    ["surface", false], ["surfaceMode", false], ["strikePoint", []],
    ["icons", ["mil_triangle" call _fnMarkerIcon, "mil_arrow2" call _fnMarkerIcon, "mil_circle" call _fnMarkerIcon, "mil_box" call _fnMarkerIcon,
        "mil_arrow" call _fnMarkerIcon, "mil_objective" call _fnMarkerIcon, "mil_destroy" call _fnMarkerIcon]]
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

private _tabIntercept = _display ctrlCreate ["RscButtonMenu", AEGISM_TERMINAL_TAB_INTERCEPT_IDC];
_tabIntercept ctrlSetPosition [_paneX + 2 * (_tabW + _padX), _bodyY, 1.3 * _tabW, _tabH];
_tabIntercept ctrlSetText "INTERCEPTION";
_tabIntercept ctrlCommit 0;
_tabIntercept ctrlShow false;
_tabIntercept ctrlAddEventHandler ["ButtonClick", { [-1, "intercept"] call aegism_network_fnc_terminalSelect; }];
// (Where the tabs go: the ones a terminal has are packed to the left,
// aegism_network_fnc_terminalFill.)
(uiNamespace getVariable "AEGISM_terminalState") set ["tabRow", [_paneX, _bodyY, _tabW, _tabH, _padX]];

private _headingX = _paneX + 3.3 * _tabW + 3 * _padX;
private _heading = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_HEADING_IDC];
_heading ctrlSetPosition [_headingX, _bodyY + 0.004 * safeZoneH, _paneX + _paneW - _headingX, _tabH];
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

// Interception: the map on the left; on the right the automation switch,
// the tracks, the weapons and the radars of the Site or vehicle picked, and
// the orders standing (aegism_network_fnc_terminalIntercept fills them,
// aegism_network_fnc_terminalMapDraw draws the map). A map control can't sit in a group, so
// it's the screen's own; it's shown with the tab (aegism_network_fnc_
// terminalSelect) at "mapRect".
private _mapW = 0.58 * _paneW;
private _colX = _paneX + _mapW + _padX;
private _colW = _paneW - _mapW - _padX;
private _headH = 0.026 * safeZoneH;
private _radarRowH = 0.03 * safeZoneH;
private _listsH = _contentH - _tabH - 3 * _headH - _radarRowH - 6 * 0.5 * _padY;
(uiNamespace getVariable "AEGISM_terminalState") set ["mapRect", [_paneX, _contentY, _mapW, _contentH]];

private _map = _display ctrlCreate ["RscMapControl", AEGISM_TERMINAL_MAP_IDC];
_map ctrlSetPosition [_paneX, _contentY, 0, 0];
_map ctrlCommit 0;
_map ctrlShow false;
_map ctrlAddEventHandler ["Draw", { _this call aegism_network_fnc_terminalMapDraw; }];
_map ctrlAddEventHandler ["MouseButtonClick", {
    params ["_map", "_button", "_x", "_y"];
    if (_button == 0) then { ["mapClick", [_map, _x, _y]] call aegism_network_fnc_terminalCommand; };
}];

private _auto = _display ctrlCreate ["RscButtonMenu", AEGISM_TERMINAL_AUTO_IDC];
_auto ctrlSetPosition [_colX, _contentY, _colW, _tabH];
_auto ctrlSetText "AUTOMATION: ON";
_auto ctrlSetTooltip "Off: this Site's weapons fire on this page's orders only. On: the Site also runs them on its own.";
_auto ctrlCommit 0;
_auto ctrlAddEventHandler ["ButtonClick", { ["automation"] call aegism_network_fnc_terminalCommand; }];
// Surface Strike's switch, beside it on a terminal that has it (aegism_
// network_fnc_terminalFill makes the room): on, a click on the map away
// from any track puts the strike point there.
(uiNamespace getVariable "AEGISM_terminalState") set ["autoRect", [_colX, _contentY, _colW, _tabH]];
private _surfaceButton = _display ctrlCreate ["RscButtonMenu", AEGISM_TERMINAL_SURFACE_IDC];
_surfaceButton ctrlSetPosition [_colX + 0.6 * _colW, _contentY, 0.4 * _colW, _tabH];
_surfaceButton ctrlSetText "SURFACE: OFF";
_surfaceButton ctrlSetTooltip "On: click the map to put a strike point on the ground, pick a weapon, and Engage. A launcher lofts one missile onto it; a gun fires one burst and needs a clear line to it.";
_surfaceButton ctrlCommit 0;
_surfaceButton ctrlShow false;
_surfaceButton ctrlAddEventHandler ["ButtonClick", { ["surface"] call aegism_network_fnc_terminalCommand; }];

private _rowY = _contentY + _tabH + 0.5 * _padY;
private _tracksHead = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_TRACKS_HEAD_IDC];
_tracksHead ctrlSetPosition [_colX, _rowY, _colW, _headH];
_tracksHead ctrlCommit 0;
_rowY = _rowY + _headH;
private _tracks = _display ctrlCreate ["RscListBox", AEGISM_TERMINAL_TRACKS_IDC];
_tracks ctrlSetPosition [_colX, _rowY, _colW, 0.36 * _listsH];
_tracks ctrlSetBackgroundColor [1, 1, 1, 0.04];
_tracks ctrlCommit 0;
_tracks ctrlAddEventHandler ["LBSelChanged", {
    params ["_list", "_index"];
    if (_index >= 0) then { ["track", [_list lbData _index]] call aegism_network_fnc_terminalCommand; };
}];
_rowY = _rowY + 0.36 * _listsH + 0.5 * _padY;

private _weaponsHead = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_WEAPONS_HEAD_IDC];
_weaponsHead ctrlSetPosition [_colX, _rowY, _colW, _headH];
_weaponsHead ctrlCommit 0;
_rowY = _rowY + _headH;
private _weapons = _display ctrlCreate ["RscListBox", AEGISM_TERMINAL_WEAPONS_IDC];
_weapons ctrlSetPosition [_colX, _rowY, _colW, 0.26 * _listsH];
_weapons ctrlSetBackgroundColor [1, 1, 1, 0.04];
_weapons ctrlCommit 0;
_weapons ctrlAddEventHandler ["LBSelChanged", {
    params ["_list", "_index"];
    if (_index >= 0) then { ["weapon", [_list lbData _index]] call aegism_network_fnc_terminalCommand; };
}];
_rowY = _rowY + 0.26 * _listsH + 0.5 * _padY;

// The radars, and what the one picked (or all of them, the first row) is
// ordered to do.
private _radarsHead = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_RADARS_HEAD_IDC];
_radarsHead ctrlSetPosition [_colX, _rowY, _colW, _headH];
_radarsHead ctrlCommit 0;
_rowY = _rowY + _headH;
private _radars = _display ctrlCreate ["RscListBox", AEGISM_TERMINAL_RADARS_IDC];
_radars ctrlSetPosition [_colX, _rowY, _colW, 0.18 * _listsH];
_radars ctrlSetBackgroundColor [1, 1, 1, 0.04];
_radars ctrlCommit 0;
_radars ctrlAddEventHandler ["LBSelChanged", {
    params ["_list", "_index"];
    if (_index >= 0) then { ["radar", [_list lbData _index]] call aegism_network_fnc_terminalCommand; };
}];
_rowY = _rowY + 0.18 * _listsH + 0.25 * _padY;
{
    _x params ["_idc", "_text", "_order", "_tooltip"];
    private _button = _display ctrlCreate ["RscButtonMenu", _idc];
    _button ctrlSetPosition [_colX + _forEachIndex * (_colW / 3), _rowY, _colW / 3 - 0.25 * _padX, _radarRowH];
    _button ctrlSetText _text;
    _button ctrlSetTooltip _tooltip;
    _button ctrlCommit 0;
    _button setVariable ["AEGISM_radarOrder", _order];
    _button ctrlAddEventHandler ["ButtonClick", { ["radarOrder", [(_this select 0) getVariable ["AEGISM_radarOrder", ""]]] call aegism_network_fnc_terminalCommand; }];
} forEach [
    [AEGISM_TERMINAL_RADAR_AUTO_IDC, "RADAR: AUTO", "", "The radar picked (or every radar, with the first row picked) goes back to its own emission control."],
    [AEGISM_TERMINAL_RADAR_ON_IDC, "EMIT", "on", "Orders the radar picked (or every radar) on, until taken back. It still shuts down for an anti-radiation missile inbound on it, if it's set to."],
    [AEGISM_TERMINAL_RADAR_OFF_IDC, "SILENT", "off", "Orders the radar picked (or every radar) silent, until taken back."]
];
_rowY = _rowY + _radarRowH + 0.5 * _padY;

private _ordersText = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_ORDERS_IDC];
_ordersText ctrlSetPosition [_colX, _rowY, _colW, 0.2 * _listsH];
_ordersText ctrlSetBackgroundColor [1, 1, 1, 0.04];
_ordersText ctrlCommit 0;
{ (_display displayCtrl _x) ctrlShow false; } forEach AEGISM_TERMINAL_INTERCEPT_IDCS;

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

// (Interception's own two, where Settings has Apply and Revert.)
private _engage = _display ctrlCreate ["RscButtonMenu", AEGISM_TERMINAL_ENGAGE_IDC];
_engage ctrlSetPosition [_paneX, _footY, _tabW, _footH];
_engage ctrlSetText "ENGAGE";
_engage ctrlSetTooltip "Orders the weapon picked onto the track picked: one missile, or a gun's fire until it's down. Again for another missile.";
_engage ctrlCommit 0;
_engage ctrlShow false;
_engage ctrlAddEventHandler ["ButtonClick", { ["engage"] call aegism_network_fnc_terminalCommand; }];

private _cease = _display ctrlCreate ["RscButtonMenu", AEGISM_TERMINAL_CEASE_IDC];
_cease ctrlSetPosition [_paneX + _tabW + _padX, _footY, _tabW, _footH];
_cease ctrlSetText "CEASE FIRE";
_cease ctrlSetTooltip "Ends the orders on the track picked -- with none picked, every order. A missile already in flight flies on.";
_cease ctrlCommit 0;
_cease ctrlShow false;
_cease ctrlAddEventHandler ["ButtonClick", { ["cease"] call aegism_network_fnc_terminalCommand; }];

private _note = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_NOTE_IDC];
_note ctrlSetPosition [_paneX + 2 * (_tabW + _padX), _footY + 0.006 * safeZoneH, _paneW - 2 * (_tabW + _padX), _footH];
_note ctrlCommit 0;

// Twice a second while it's open. What it reaches: until the server has
// answered, and every fifth second after (its reach changes with the Sites'
// links and coordinator). Every second, the board of the one picked while
// Status is shown, or its picture while Interception is -- and that twice a
// second while the Site has a missile in flight, so it moves on the map.
[{
    params ["_args", "_pfhHandle"];
    _args params ["_anchor", "_terminal", "_display", "_count"];
    _args set [3, _count + 1];
    if (isNull _display) exitWith { [_pfhHandle] call CBA_fnc_removePerFrameHandler; };
    // Its laptop gone -- or, one it carries, no longer on it.
    if (isNull _terminal || {_terminal isKindOf "CAManBase" && {!alive _terminal || {(_terminal getVariable ["AEGISM_terminalCarried", []]) isEqualTo []}}}) exitWith {
        _display closeDisplay 2;
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };
    private _state = uiNamespace getVariable ["AEGISM_terminalState", createHashMap];
    private _nodes = _state getOrDefault ["nodes", []];
    private _second = _count mod 2 == 0;
    if ((_nodes isEqualTo [] && {_second}) || {_count mod 10 == 8}) then {
        [_terminal, _anchor, true] remoteExecCall ["aegism_network_fnc_terminalScope", 2];
    };
    private _tab = _state getOrDefault ["tab", "status"];
    if (_tab == "status" && {_second}) then {
        private _node = _nodes param [_state getOrDefault ["node", -1], []];
        if (_node isNotEqualTo []) then { [_node select 0] remoteExecCall ["aegism_network_fnc_terminalRequest", 2]; };
    };
    if (_tab == "intercept" && {_second || {((_state getOrDefault ["picture", []]) param [8, []]) isNotEqualTo []}}) then {
        ["request"] call aegism_network_fnc_terminalCommand;
    };
}, 0.5, [_anchor, _terminal, _display, 0]] call CBA_fnc_addPerFrameHandler;

[_terminal, _anchor, true] remoteExecCall ["aegism_network_fnc_terminalScope", 2];
