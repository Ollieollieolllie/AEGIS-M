/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveContactSource

Description:
    Resolves where a launcher/CIWS System draws tracked contacts from: its
    own sensors, or its Site's pool.
    Full notes: docs/functions/modules_system.md

Parameters:
    _systemObject - the vehicle to resolve a contact source for <OBJECT>

Returns:
    Contact source list, any combination of "ownSensor" / "network" (empty
    array if neither is available) <ARRAY of STRING>

Examples:
    [_tigris] call aegism_system_fnc_resolveContactSource;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_systemObject"];

private _sources = [];

private _system = _systemObject getVariable ["AEGISM_system", createHashMap];
if (_system getOrDefault ["hasSensor", false]) then {
    _sources pushBack "ownSensor";
};

private _network = _systemObject getVariable ["AEGISM_network", objNull];
private _warning = "";

if (!isNull _network) then {
    // A Site linked to others gets the whole group's contacts (aegism_
    // network_fnc_linkSites).
    private _members = _network getVariable ["AEGISM_groupMembers", _network getVariable ["AEGISM_networkMembers", []]];
    private _networkHasSensor = (_members findIf {
        private _memberSystem = _x getVariable ["AEGISM_system", createHashMap];
        _memberSystem getOrDefault ["hasSensor", false]
    }) != -1;

    if (_networkHasSensor) then {
        _sources pushBack "network";
    } else {
        _warning = format ["System on %1 is synced to Network %2, but no current member of that Network has a sensor of its own (radar, IR or visual) -- it will never receive any contacts from it.", _systemObject, _network];
    };
};

if (_sources isEqualTo []) then {
    _warning = format ["System on %1 has no contact source (no sensor of its own, no Network with a sensor-equipped member) -- it will never detect a target.", _systemObject];
};

private _lastWarning = _systemObject getVariable ["AEGISM_lastContactSourceWarning", ""];
if (_warning != _lastWarning) then {
    _systemObject setVariable ["AEGISM_lastContactSourceWarning", _warning, false];
    if (_warning != "") then {
        diag_log text ("[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " WARNING: " + _warning);
    } else {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " System on %1 now has a contact source: %2 (earlier warning resolved).", _systemObject, _sources];
    };
};

_sources
