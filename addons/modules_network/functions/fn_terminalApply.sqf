/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalApply

Description:
    Server side of a control terminal's Apply: checks the terminal is one
    with full control, that what's changed is within its reach and that the
    player is at it, then applies the settings on every machine exactly as
    a Zeus edit does.
    Full notes: docs/functions/modules_network.md

Parameters:
    _terminal - the terminal <OBJECT>
    _anchor - the Site or vehicle its action was made for <OBJECT>
    _target - the Site or vehicle whose settings are changed <OBJECT>
    _pairs - [property, value] pairs from its settings form <ARRAY>

Returns:
    Nothing

Examples:
    [_laptop, _site, _spartan, _pairs] remoteExecCall ["aegism_network_fnc_terminalApply", 2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

params [["_terminal", objNull], ["_anchor", objNull], ["_target", objNull], ["_pairs", []]];

if (!isServer) exitWith {};

private _owner = remoteExecutedOwner;
private _local = !isMultiplayer || {_owner in [0, clientOwner]};
// A line for the screen it came from.
private _fnAnswer = {
    params ["_note"];
    if (_local) then { ["", _note] call aegism_network_fnc_terminalShow; } else { ["", _note] remoteExecCall ["aegism_network_fnc_terminalShow", _owner]; };
};
private _user = if (_local) then { player } else { (allPlayers select { owner _x == _owner }) param [0, objNull] };
private _userName = if (isNull _user) then { "an unknown player" } else { name _user };

private _refusal = switch (true) do {
    case (isNull _terminal || {isNull _target}): { "the terminal or what it changes is gone" };
    case ((([_terminal, _target] call aegism_network_fnc_terminalData) select 0) != "control"): { "this terminal is status only here" };
    case (!isNull _user && {_terminal isKindOf "CAManBase"} && {_terminal != _user}): { "that terminal is someone else's to use" };
    case (!isNull _user && {(_user distance _terminal) > AEGISM_TERMINAL_REACH}): { "you're not at the terminal" };
    case ((([_terminal, _anchor] call aegism_network_fnc_terminalScope) findIf { (_x select 0) == _target }) == -1): { "that isn't within this terminal's reach" };
    default { "" };
};
if (_refusal != "") exitWith {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL: change to %1 from terminal %2 by %3 refused -- %4.", _target, _terminal, _userName, _refusal];
    [format ["<t size='0.85' color='%1'>Refused: %2.</t>", AEGISM_TERMINAL_WARN_HEX, _refusal]] call _fnAnswer;
};

private _isSite = _target isKindOf "AEGISM_Module_Site";
private _applyFunction = ["aegism_system_fnc_zeusApplyOverrides", "aegism_network_fnc_zeusApplySite"] select _isSite;
// The same JIP entry a Zeus edit of it uses: the last edit of either kind
// is what a player joining later gets.
[_target, _pairs] remoteExecCall [_applyFunction, 0, format ["AEGISM_zeus_%1_%2", _applyFunction, netId _target]];

diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL: %1 changed %2 of %3 from terminal %4.", _userName, ["its overrides", "the settings"] select _isSite, _target, _terminal];
[format ["<t size='0.85' color='%1'>Applied (mission time %2).</t>", AEGISM_TERMINAL_ACCENT_HEX, [CBA_missionTime, "MM:SS"] call BIS_fnc_secondsToString]] call _fnAnswer;
