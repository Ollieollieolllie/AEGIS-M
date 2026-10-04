/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalShow

Description:
    Shows a Site's status board, as sent by the server (aegism_network_fnc_
    terminalRequest), on this machine's open terminal screen (aegism_
    network_fnc_terminalOpen), sized to its text so the screen scrolls. Does
    nothing once the screen is closed.

Parameters:
    _text - the board, structured text <STRING>

Returns:
    Nothing

Examples:
    [_text] call aegism_network_fnc_terminalShow;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_TERMINAL_BOARD_IDC 77802
#define AEGISM_TERMINAL_GROUP_IDC 77801

params ["_text"];

private _display = uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull];
if (isNull _display) exitWith {};

private _board = _display displayCtrl AEGISM_TERMINAL_BOARD_IDC;
_board ctrlSetStructuredText parseText _text;
_board ctrlSetPositionH ((ctrlTextHeight _board) max ((ctrlPosition (_display displayCtrl AEGISM_TERMINAL_GROUP_IDC)) select 3));
_board ctrlCommit 0;
