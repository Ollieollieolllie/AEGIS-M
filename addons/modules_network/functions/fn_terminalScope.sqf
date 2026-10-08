/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalScope

Description:
    What a terminal reaches, worked out on the server from what it's synced
    to: a vehicle, that vehicle; a Site, that Site and its vehicles; the
    Shared Site Coordinator of linked Sites, every one of them.
    Full notes: docs/functions/modules_network.md

Parameters:
    _terminal - the terminal <OBJECT>
    _anchor - the Site or vehicle its action was made for (counted with
        what the terminal itself lists as synced) <OBJECT>
    _reply - send the answer to the machine that asked (aegism_network_fnc_
        terminalFill) <BOOLEAN, default false>

Returns:
    Its nodes, in the order shown: [object, label, "site" or "vehicle"]
    each <ARRAY>

Examples:
    [_laptop, _site, true] remoteExecCall ["aegism_network_fnc_terminalScope", 2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_terminal", objNull], ["_anchor", objNull], ["_reply", false]];

if (!isServer) exitWith { [] };

// What it's synced to, and what it's connected to wherever it has been
// carried since (aegism_network_fnc_terminalData). A unit carrying one: only
// that -- what the unit itself is synced to is nothing of the laptop's.
([_terminal] call aegism_network_fnc_terminalData) params ["_access", "_engage", "_surface", "_link"];
private _synced = if (isNull _terminal || {_terminal isKindOf "CAManBase"}) then { [] } else { +(synchronizedObjects _terminal) };
if (!isNull _terminal && {!isNull _anchor} && {_terminal in (synchronizedObjects _anchor)}) then { _synced pushBackUnique _anchor; };
{ _synced pushBackUnique _x; } forEach _link;
// (One carried is its carrier's alone.)
if (isMultiplayer && {_reply} && {_terminal isKindOf "CAManBase"} && {!(remoteExecutedOwner in [0, owner _terminal])}) then { _synced = []; };

private _sites = [];
private _vehicles = [];
{
    if (_x isKindOf "AEGISM_Module_Site") then {
        private _linked = (_x getVariable ["AEGISM_linkSites", [_x]]) select { !isNull _x };
        if (count _linked > 1 && {_x getVariable ["sharedCoordinator", false]} && {(_x getVariable ["AEGISM_linkLead", _x]) == _x}) then {
            _sites pushBackUnique _x;
            { _sites pushBackUnique _x; } forEach _linked;
        } else {
            _sites pushBackUnique _x;
        };
    } else {
        private _vehicle = vehicle _x;
        if (!isNil { _vehicle getVariable "AEGISM_system" } || {_vehicle getVariable ["AEGISM_systemDeferred", false]}) then { _vehicles pushBackUnique _vehicle; };
    };
} forEach _synced;

private _fnVehicleLabel = {
    private _name = getText (configOf _this >> "displayName");
    if (_name == "") then { _name = typeOf _this; };
    format ["%1  (%2)", _name, _this]
};

private _nodes = [];
private _listed = [];
{
    private _site = _x;
    private _name = [_site] call aegism_fnc_siteName;
    if (count _sites > 1 && {_site getVariable ["sharedCoordinator", false]}) then { _name = _name + "  (coordinator)"; };
    _nodes pushBack [_site, _name, "site"];
    {
        _nodes pushBack [_x, _x call _fnVehicleLabel, "vehicle"];
        _listed pushBack _x;
    } forEach ((_site getVariable ["AEGISM_networkMembers", []]) select { !isNull _x && {alive _x} });
} forEach _sites;
{
    if !(_x in _listed) then { _nodes pushBack [_x, _x call _fnVehicleLabel, "vehicle"]; };
} forEach _vehicles;

if (_reply) then {
    private _owner = remoteExecutedOwner;
    // (Surface Strike goes with the Interception page.)
    _surface = _engage && {_surface};
    if (!isMultiplayer || {_owner in [0, clientOwner]}) then {
        [_nodes, _access, _engage, _surface] call aegism_network_fnc_terminalFill;
    } else {
        [_nodes, _access, _engage, _surface] remoteExecCall ["aegism_network_fnc_terminalFill", _owner];
    };
};

_nodes
