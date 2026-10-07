/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalShow

Description:
    Shows what the server sent on this machine's open terminal screen: a
    status board, sized to its text so the screen scrolls, or a line about
    the last Apply.
    Full notes: docs/functions/modules_network.md

Parameters:
    _text - the board, structured text; "" leaves it as it is <STRING>
    _note - a line for the foot of the screen, structured text; "" leaves
        it as it is <STRING, default "">

Returns:
    Nothing

Examples:
    [_text] call aegism_network_fnc_terminalShow;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

params [["_text", ""], ["_note", ""]];

private _display = uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull];
if (isNull _display) exitWith {};

if (_note != "") then { (_display displayCtrl AEGISM_TERMINAL_NOTE_IDC) ctrlSetStructuredText parseText _note; };
if (_text == "") exitWith {};

private _board = _display displayCtrl AEGISM_TERMINAL_BOARD_IDC;
_board ctrlSetStructuredText parseText _text;
_board ctrlSetPositionH ((ctrlTextHeight _board) max ((ctrlPosition (_display displayCtrl AEGISM_TERMINAL_GROUP_IDC)) select 3));
_board ctrlCommit 0;
