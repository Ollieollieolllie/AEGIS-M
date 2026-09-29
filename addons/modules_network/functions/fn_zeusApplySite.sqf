/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_zeusApplySite

Description:
    Applies a Site's settings as edited in Zeus (aegism_fnc_
    zeusAttributeDialog), on every machine: each attribute's own Eden
    expression runs (aegism_fnc_applyAttributeValues), so the Site logic
    gets the same variables its Eden attributes would set.

    On the server the Site's doctrine and personality are then rebuilt
    (aegism_network_fnc_readSiteSettings), handed to every member vehicle,
    and each member System re-resolved at once rather than at its next
    5-second poll. Logged as SITE-SETTINGS.

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

private _members = _logic getVariable ["AEGISM_networkMembers", []];
{
    _x setVariable ["AEGISM_engagement", _engagementData, false];
    _x setVariable ["AEGISM_crew", _crewData, false];
    if (!isNil {_x getVariable "AEGISM_system"}) then { [_x] call aegism_system_fnc_resolveSettings; };
} forEach _members;

diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " SITE-SETTINGS: %1 edited in Zeus, applied to %2 member(s) -- engagement %3 | crew %4", _logic, count _members, _engagementData, _crewData];
