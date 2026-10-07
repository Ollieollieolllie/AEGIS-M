/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_zeusApplySite

Description:
    Applies a Site's settings as edited in Zeus, on every machine.
    Full notes: docs/functions/modules_network.md

Parameters:
    _logic - the Site logic <OBJECT>
    _pairs - [property, value] pairs from the dialog <ARRAY>

Returns:
    Nothing

Examples:
    [_site, [["maxRange", 8000]]] remoteExecCall ["aegism_network_fnc_zeusApplySite", 0];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_logic", "_pairs"];

if (isNull _logic) exitWith {};

[_logic, configOf _logic >> "Attributes", _pairs] call aegism_fnc_applyAttributeValues;

if (!isServer) exitWith {};

([_logic] call aegism_network_fnc_readSiteSettings) params ["_engagementData", "_crewData"];
_logic setVariable ["AEGISM_engagement", _engagementData, false];
_logic setVariable ["AEGISM_crew", _crewData, false];

// Shared Site Coordinator: one per linked group. Ticked here, it's unticked
// on every other Site linked, synced or sharing a vehicle with this one --
// on every machine, so their Zeus dialogs show it.
private _members = _logic getVariable ["AEGISM_networkMembers", []];
if (_logic getVariable ["sharedCoordinator", false]) then {
    private _connected = (_logic getVariable ["AEGISM_linkSites", [_logic]]) + ((synchronizedObjects _logic) select { _x isKindOf "AEGISM_Module_Site" });
    {
        if (((_x getVariable ["AEGISM_networkMembers", []]) findIf { _x in _members }) != -1 || {_logic in synchronizedObjects _x}) then { _connected pushBack _x; };
    } forEach ((missionNamespace getVariable ["AEGISM_allPoolOwners", []]) select { !isNull _x && {_x isKindOf "AEGISM_Module_Site"} });
    _connected = (_connected arrayIntersect _connected) - [_logic];
    private _unticked = _connected select { _x getVariable ["sharedCoordinator", false] };
    { _x setVariable ["sharedCoordinator", false, true]; } forEach _unticked;
    if (_unticked isNotEqualTo []) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SITE-SETTINGS: %1 is now the Shared Site Coordinator of its linked Sites -- unticked on %2.", _logic, _unticked];
    };
};

{
    _x setVariable ["AEGISM_engagement", _engagementData, false];
    _x setVariable ["AEGISM_crew", _crewData, false];
} forEach _members;
// Every vehicle these settings now reach: its own, and, linked under it as
// Shared Site Coordinator, the whole group's (aegism_fnc_siteSettingsSource).
// A change of coordinator re-resolves its group itself (aegism_network_fnc_
// linkSites).
{
    if (!isNil {_x getVariable "AEGISM_system"}) then { [_x] call aegism_system_fnc_resolveSettings; };
} forEach ((_logic getVariable ["AEGISM_groupMembers", []]) + _members);

// Threat rings: redrawn for the Site's group (aegism_network_fnc_
// drawThreatRings) when Threat Rings on Map, Shared Site Coordinator or
// Protected Area Radius is changed -- turned on, drawn; turned off, gone (or
// the group's drawn without this Site's). Otherwise left as drawn.
private _ringsKey = [_logic getVariable ["threatRings", false], _logic getVariable ["sharedCoordinator", false], _logic getVariable ["protectRadius", 750]];
if (_ringsKey isNotEqualTo (_logic getVariable ["AEGISM_ringsApplied", [false, false, 750]])) then {
    [_logic] call aegism_network_fnc_drawThreatRings;
};
_logic setVariable ["AEGISM_ringsApplied", _ringsKey, false];

diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SITE-SETTINGS: %1 edited in Zeus, applied to %2 member(s) -- engagement %3 | crew %4", _logic, count _members, _engagementData, _crewData];
