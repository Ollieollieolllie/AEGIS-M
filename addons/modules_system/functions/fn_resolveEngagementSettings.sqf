/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveEngagementSettings

Description:
    Resolves which Doctrine data applies to a given System vehicle:
        1. the base -- the Site's doctrine (AEGISM_Module_Site's moduleInit
           copies it onto every member as "AEGISM_engagement", and it is
           also read from the Site logic via "AEGISM_network"), or the
           hardcoded defaults for a standalone vehicle;
        2. then the vehicle's own per-vehicle overrides on top, if it has
           any enabled (aegism_system_fnc_applyOverrides) -- each setting
           left on "Site setting" keeps the base value.

Parameters:
    _systemObject - the vehicle to resolve Doctrine data for <OBJECT>
    _changes - optional; applied overrides are appended as "key=value"
        (by reference, for logging) <ARRAY>

Returns:
    The resolved engagement settings data <HASHMAP>

Examples:
    [_tigris] call aegism_system_fnc_resolveEngagementSettings;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_systemObject", ["_changes", []]];

private _base = _systemObject getVariable "AEGISM_engagement";
if (isNil "_base") then {
    private _network = _systemObject getVariable ["AEGISM_network", objNull];
    if (!isNull _network) then { _base = _network getVariable "AEGISM_engagement"; };
};
if (isNil "_base") then { _base = [] call aegism_system_fnc_defaultEngagementSettings; };

[_systemObject, _base, "engagement", _changes] call aegism_system_fnc_applyOverrides
