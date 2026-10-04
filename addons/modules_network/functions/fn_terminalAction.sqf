/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalAction

Description:
    Makes an object a Site's status terminal, on this machine: the action
    "AEGIS-M: Site Status" (within 3 m), which opens that Site's live status
    board (aegism_network_fnc_terminalOpen). An objNull Site takes the
    action away.

    A Site's terminals are the laptops synced to it (any object whose class
    name has "laptop" in it -- they're not alarm speakers). The server sends
    this to every machine, and to anyone joining later (one JIP entry per
    terminal, gone with it): from the Site's own setup (aegism_network_fnc_
    moduleInit) and its live-resync poll, for one synced or unsynced
    afterwards (in Zeus).

Parameters:
    _terminal - the laptop <OBJECT>
    _site - its Site, or objNull to take the action away <OBJECT>

Returns:
    Nothing

Examples:
    [_laptop, _site] remoteExec ["aegism_network_fnc_terminalAction", 0, _laptop];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_terminal", "_site"];

if (!hasInterface || {isNull _terminal}) exitWith {};

private _previous = _terminal getVariable ["AEGISM_terminalAction", -1];
if (_previous >= 0) then {
    _terminal removeAction _previous;
    _terminal setVariable ["AEGISM_terminalAction", nil];
};
if (isNull _site) exitWith {};

_terminal setVariable ["AEGISM_terminalAction", _terminal addAction [
    "<t color='#4FC3F7'>AEGIS-M: Site Status</t>",
    {
        params ["_terminal", "", "", "_site"];
        [_site, _terminal] call aegism_network_fnc_terminalOpen;
    },
    _site, 1.5, true, true, "", "true", 3
]];
