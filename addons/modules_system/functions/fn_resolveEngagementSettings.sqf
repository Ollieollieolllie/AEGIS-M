/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveEngagementSettings

Description:
    Resolves which AEGISM_Module_EngagementSettings data applies to a given
    System object, per the object -> network -> default fallback order
    defined in the AEGIS-M architecture plan (section 1): a doctrine synced
    directly to the System overrides one inherited from its Network, and if
    neither is present a hardcoded default is used so the System still
    functions standalone.

    Reads/writes the object-namespaced variables set by aegism_system_fnc_
    moduleInit and the (future) EngagementSettings/Network module init
    functions: "AEGISM_engagement" (HashMap or nil) and "AEGISM_network"
    (Object or objNull).

Parameters:
    _systemObject - the vehicle carrying an AEGISM_Module_System <OBJECT>

Returns:
    The resolved engagement settings data <HASHMAP>

Examples:
    [_tigris] call aegism_system_fnc_resolveEngagementSettings;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_systemObject"];

private _ownEngagement = _systemObject getVariable "AEGISM_engagement";
if (!isNil "_ownEngagement") exitWith {
    _ownEngagement
};

private _network = _systemObject getVariable ["AEGISM_network", objNull];
if (!isNull _network) then {
    private _networkEngagement = _network getVariable "AEGISM_engagement";
    if (!isNil "_networkEngagement") exitWith {
        _networkEngagement
    };
};

[] call aegism_system_fnc_defaultEngagementSettings
