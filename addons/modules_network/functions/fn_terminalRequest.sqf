/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalRequest

Description:
    Server side of a terminal's Status tab: builds the status board of a
    Site, or of a vehicle's Site, and sends it back to the machine that
    asked.
    Full notes: docs/functions/modules_network.md

Parameters:
    _node - the Site, or one of its vehicles <OBJECT>

Returns:
    Nothing

Examples:
    [_site] remoteExecCall ["aegism_network_fnc_terminalRequest", 2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_node", objNull]];

if (!isServer) exitWith {};

private _site = if (_node isKindOf "AEGISM_Module_Site") then { _node } else { _node getVariable ["AEGISM_network", objNull] };
// A vehicle with no Site: the whole board, which lists standalone vehicles.
private _text = if (isNull _site) then { [objNull, true, 1e6] call aegism_fnc_statusBoard } else { [_site, false, 1e6] call aegism_fnc_statusBoard };

// Asked from this machine (singleplayer, or a hosted game's host): shown
// here.
private _owner = remoteExecutedOwner;
if (!isMultiplayer || {_owner in [0, clientOwner]}) exitWith { [_text] call aegism_network_fnc_terminalShow; };
[_text] remoteExecCall ["aegism_network_fnc_terminalShow", _owner];
