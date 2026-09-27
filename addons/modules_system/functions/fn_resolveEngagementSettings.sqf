/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveEngagementSettings

Description:
    Resolves which Doctrine data applies to a given System vehicle, per the
    object -> network -> default fallback order defined in the AEGIS-M
    architecture plan (section 1): doctrine set directly on the vehicle
    (possible via scripting; there's no separate per-vehicle Doctrine
    module anymore) overrides one inherited from its synced AEGISM_Module_
    Site, and if neither is present a hardcoded default is used so a
    role-checked vehicle still functions standalone with no Site at all.

    Reads the object-namespaced variables set by aegism_system_fnc_
    moduleInit and AEGISM_Module_Site's own moduleInit: "AEGISM_engagement"
    (HashMap or nil) and "AEGISM_network" (Object or objNull).

Parameters:
    _systemObject - the vehicle to resolve Doctrine data for <OBJECT>

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
