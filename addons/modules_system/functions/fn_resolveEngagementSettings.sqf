/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveEngagementSettings

Description:
    Resolves which Doctrine data applies to a System vehicle: its Site's (or
    the defaults), with its own overrides.
    Full notes: docs/functions/modules_system.md

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

// Its Site linked with others under a Shared Site Coordinator: that Site's
// settings (aegism_fnc_siteSettingsSource).
private _network = _systemObject getVariable ["AEGISM_network", objNull];
private _source = [_network] call aegism_fnc_siteSettingsSource;
private _base = if (_source != _network) then { _source getVariable "AEGISM_engagement" } else { _systemObject getVariable "AEGISM_engagement" };
if (isNil "_base" && {!isNull _network}) then { _base = _network getVariable "AEGISM_engagement"; };
if (isNil "_base") then { _base = [] call aegism_system_fnc_defaultEngagementSettings; };

[_systemObject, _base, "engagement", _changes] call aegism_system_fnc_applyOverrides
