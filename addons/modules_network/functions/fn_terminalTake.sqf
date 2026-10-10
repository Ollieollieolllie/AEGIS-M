/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalTake

Description:
    Server: a player takes up an AEGIS-M Laptop. It becomes a numbered
    AEGIS-M laptop item on the player,
    which keeps its connection (aegism_network_fnc_terminalTrack).
    Full notes: docs/functions/modules_network.md

Parameters:
    _terminal - the laptop prop <OBJECT>
    _unit - who takes it <OBJECT>

Returns:
    Nothing

Examples:
    [_laptop, player] remoteExecCall ["aegism_network_fnc_terminalTake", 2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

params [["_terminal", objNull], ["_unit", objNull]];

if (!isServer || {isNull _terminal} || {isNull _unit} || {!alive _unit}) exitWith {};

private _fnTell = { [_this] remoteExecCall ["hintSilent", _unit]; };
private _link = (_terminal getVariable ["AEGISM_terminalLink", []]) select { !isNull _x };
if (!(_terminal isKindOf "AEGISM_Laptop") || {_link isEqualTo []}) exitWith {};
if (_terminal getVariable ["AEGISM_terminalFixed", false]) exitWith { "AEGIS-M: this terminal is fixed in place." call _fnTell; };
if ((_unit distance _terminal) > AEGISM_TERMINAL_REACH) exitWith {};

// The first numbered laptop no connection is kept under yet.
private _used = [];
{ _used pushBack ((_x select 6) select 0); } forEach (missionNamespace getVariable ["AEGISM_terminalBodies", []]);
{ { _used pushBack (_x select 0); } forEach (_x getVariable ["AEGISM_terminalCarried", []]); } forEach (missionNamespace getVariable ["AEGISM_terminalCarriers", []]);
{ _used pushBack ((_x select 0) select 0); } forEach (missionNamespace getVariable ["AEGISM_terminalLoose", []]);
private _item = "";
for "_number" from 1 to AEGISM_LAPTOP_ITEMS do {
    private _class = format ["aegism_laptop_%1", _number];
    if (_item == "" && {!(_class in _used)}) then { _item = _class; };
};
if (_item == "") exitWith { "AEGIS-M: no more laptops can be carried at once." call _fnTell; };
if !(_unit canAdd _item) exitWith { "AEGIS-M: no room to carry this laptop." call _fnTell; };

// Its connection is left loose where the player stands: the server's own
// pass finds the item on the player and gives it to them.
private _record = [_item, _link, _terminal getVariable ["AEGISM_terminalAccess", "status"], _terminal getVariable ["AEGISM_terminalEngage", false],
    _terminal getVariable ["AEGISM_terminalSurface", false], false];
private _loose = missionNamespace getVariable ["AEGISM_terminalLoose", []];
_loose pushBack [_record, getPosWorld _unit, CBA_missionTime, []];
missionNamespace setVariable ["AEGISM_terminalLoose", _loose];

diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL: %1 took up the laptop %2 (%3), connected to %4 -- it's the item %5 now.", name _unit, _terminal, typeOf _terminal, _link, _item];
deleteVehicle _terminal;
[_unit, _item] remoteExecCall ["addItem", _unit];
