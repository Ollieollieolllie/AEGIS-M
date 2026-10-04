/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalOpen

Description:
    Opens a Site's status terminal screen on this machine: its live status
    board (aegism_fnc_statusBoard -- every member vehicle's roles, status,
    target and ammo, and every contact it tracks, with the sensors that see
    it and the weapons on it), scrollable, refreshed once a second until
    it's closed (Esc) or the terminal is gone.

    The board's data lives where the engagement pipeline runs, the server:
    each second this asks it for the board (aegism_network_fnc_
    terminalRequest), which sends it back (aegism_network_fnc_terminalShow)
    -- so it works for a client of a dedicated server, which the Site Status
    Hint (aegism_fnc_debugHint) can't.

Parameters:
    _site - the Site <OBJECT>
    _terminal - the terminal it's opened from <OBJECT>

Returns:
    Nothing

Examples:
    [_site, _laptop] call aegism_network_fnc_terminalOpen;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_TERMINAL_BOARD_IDC 77802
#define AEGISM_TERMINAL_GROUP_IDC 77801

params ["_site", "_terminal"];

if (!hasInterface || {!isNull (uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull])}) exitWith {};

private _display = (findDisplay 46) createDisplay "RscDisplayEmpty";
if (isNull _display) exitWith {};
uiNamespace setVariable ["AEGISM_terminalDisplay", _display];

private _x0 = safeZoneX + 0.25 * safeZoneW;
private _w = 0.5 * safeZoneW;
private _y0 = safeZoneY + 0.1 * safeZoneH;
private _h = 0.8 * safeZoneH;
private _titleH = 0.05 * safeZoneH;
private _pad = 0.01 * safeZoneW;

private _background = _display ctrlCreate ["RscText", -1];
_background ctrlSetPosition [_x0, _y0, _w, _h];
_background ctrlSetBackgroundColor [0.04, 0.06, 0.08, 0.93];
_background ctrlCommit 0;

private _title = _display ctrlCreate ["RscStructuredText", -1];
_title ctrlSetPosition [_x0, _y0, _w, _titleH];
_title ctrlSetBackgroundColor [0.09, 0.2, 0.27, 1];
_title ctrlSetStructuredText parseText "<t font='PuristaSemibold' size='1.1' color='#4FC3F7'>AEGIS-M Site Terminal</t><t align='right' size='0.8' color='#90A4AE'>Esc to close</t>";
_title ctrlCommit 0;

private _group = _display ctrlCreate ["RscControlsGroupNoHScrollbars", AEGISM_TERMINAL_GROUP_IDC];
_group ctrlSetPosition [_x0 + _pad, _y0 + _titleH + _pad, _w - 2 * _pad, _h - _titleH - 2 * _pad];
_group ctrlCommit 0;

private _board = _display ctrlCreate ["RscStructuredText", AEGISM_TERMINAL_BOARD_IDC, _group];
_board ctrlSetPosition [0, 0, _w - 2 * _pad - 0.02 * safeZoneW, _h - _titleH - 2 * _pad];
_board ctrlSetStructuredText parseText "<t color='#90A4AE'>Connecting to the Site...</t>";
_board ctrlCommit 0;

// Once a second while it's open: ask the server for the board.
[{
    params ["_args", "_pfhHandle"];
    _args params ["_site", "_terminal", "_display"];
    if (isNull _display) exitWith { [_pfhHandle] call CBA_fnc_removePerFrameHandler; };
    if (isNull _terminal) exitWith {
        _display closeDisplay 2;
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };
    [_site] remoteExecCall ["aegism_network_fnc_terminalRequest", 2];
}, 1, [_site, _terminal, _display]] call CBA_fnc_addPerFrameHandler;
[_site] remoteExecCall ["aegism_network_fnc_terminalRequest", 2];
