/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalLink

Description:
    Server: connects a laptop to a Site or vehicle (or takes that connection
    away), keeps the connection on the laptop itself so it can travel with
    it, and gives every machine its action.
    Full notes: docs/functions/modules_network.md

Parameters:
    _terminal - the laptop <OBJECT>
    _anchor - the Site or vehicle; objNull to only publish it again <OBJECT>
    _add - connect (true) or disconnect (false) <BOOLEAN, default true>

Returns:
    Nothing

Examples:
    [_laptop, _site] call aegism_network_fnc_terminalLink;
    [_laptop, objNull] remoteExecCall ["aegism_network_fnc_terminalLink", 2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_terminal", objNull], ["_anchor", objNull], ["_add", true]];

if (!isServer || {isNull _terminal}) exitWith {};

private _link = (_terminal getVariable ["AEGISM_terminalLink", []]) select { !isNull _x };
if (!isNull _anchor) then {
    if (_add) then { _link pushBackUnique _anchor; } else { _link = _link - [_anchor]; };
};
_terminal setVariable ["AEGISM_terminalLink", _link, true];

// The inventory item it is, if it's one that can be picked up: what it's
// followed by when it is (aegism_network_fnc_terminalTrack). A prop has none.
if (isNil { _terminal getVariable "AEGISM_terminalItem" }) then {
    private _cargo = [];
    {
        private _part = _terminal call _x;
        if (!isNil "_part") then { _cargo append _part; };
    } forEach [{ itemCargo _this }, { magazineCargo _this }, { weaponCargo _this }, { backpackCargo _this }];
    _terminal setVariable ["AEGISM_terminalItem", _cargo param [0, ""], true];
};
private _item = toLower (_terminal getVariable ["AEGISM_terminalItem", ""]);
if (_item != "") then {
    private _bodies = missionNamespace getVariable ["AEGISM_terminalBodies", []];
    if ((_bodies findIf { (_x select 0) isEqualTo _terminal }) == -1) then {
        _bodies pushBack [_terminal, _item, typeOf _terminal, getPosWorld _terminal, vectorDir _terminal, vectorUp _terminal,
            [_item, _link, _terminal getVariable ["AEGISM_terminalAccess", "status"], _terminal getVariable ["AEGISM_terminalEngage", false],
                _terminal getVariable ["AEGISM_terminalSurface", false], _terminal getVariable ["AEGISM_terminalFixed", false]]];
        missionNamespace setVariable ["AEGISM_terminalBodies", _bodies];
    };
};

if !(_terminal getVariable ["AEGISM_terminalLogged", false]) then {
    _terminal setVariable ["AEGISM_terminalLogged", true];
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL: %1 (%2) is a terminal, connected to %3 -- %4.", _terminal, typeOf _terminal, _link,
        if (_item == "") then { "a prop: it can't be picked up" } else {
            format ["the inventory item %1: %2", _item,
                ["picked up, it keeps its connection", "fixed in place"] select (_terminal getVariable ["AEGISM_terminalFixed", false])]
        }];
};

[_terminal, _link param [0, objNull]] remoteExec ["aegism_network_fnc_terminalAction", 0, _terminal];
