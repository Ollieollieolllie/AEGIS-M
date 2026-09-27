/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_moduleInit

Description:
    Entry point run when an AEGISM_Module_Network is placed and synced in
    Eden or Zeus. Establishes the battery membership link: writes
    "AEGISM_network" (pointing at this Network's logic object) onto every
    synced AEGISM_Module_System vehicle, and initializes this Network's own
    pooled-contact list ("AEGISM_pooledContacts", populated later by the
    detection loop from member Systems' Radar-role sensors) and member
    registry ("AEGISM_networkMembers").

    Must run before aegism_system_fnc_moduleInit / aegism_engagement_fnc_
    moduleInit / aegism_crew_fnc_moduleInit resolve their object -> network
    -> default chain, since that resolution reads "AEGISM_network" off the
    System vehicle. Enforced via a lower functionPriority (0) than System's
    (1) and EngagementSettings/Crew's (2) in their respective CfgVehicles
    entries -- Arma runs placed modules' functions in ascending
    functionPriority order.

Parameters:
    _logic - the module logic object (this Network) <OBJECT>
    _units - synced AEGISM_Module_System vehicles <ARRAY of OBJECT>
    _activated - module activation state (unused, modules run on init) <BOOLEAN>

Returns:
    Nothing

Examples:
    [_logic, _units, _activated] call aegism_network_fnc_moduleInit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_logic", "_units", "_activated"];

_logic setVariable ["AEGISM_pooledContacts", [], false];
_logic setVariable ["AEGISM_networkMembers", _units, false];

{
    _x setVariable ["AEGISM_network", _logic, false];
} forEach _units;

diag_log text format ["[AEGIS-M] Network %1 established with %2 member System(s).", _logic, count _units];
