/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalRequest

Description:
    Server side of a Site's status terminal (aegism_network_fnc_
    terminalOpen): builds the Site's status board -- that Site alone, every
    contact it tracks (aegism_fnc_statusBoard) -- and sends it back to the
    machine that asked (aegism_network_fnc_terminalShow). Run once a second
    per open terminal screen.

Parameters:
    _site - the Site <OBJECT>

Returns:
    Nothing

Examples:
    [_site] remoteExecCall ["aegism_network_fnc_terminalRequest", 2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_site", objNull]];

if (!isServer) exitWith {};

private _text = [_site, false, 1e6] call aegism_fnc_statusBoard;
// Asked from this machine (singleplayer, or a hosted game's host): shown
// here.
private _owner = remoteExecutedOwner;
if (!isMultiplayer || {_owner in [0, clientOwner]}) exitWith { [_text] call aegism_network_fnc_terminalShow; };
[_text] remoteExecCall ["aegism_network_fnc_terminalShow", _owner];
