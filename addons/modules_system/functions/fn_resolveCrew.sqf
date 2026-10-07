/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveCrew

Description:
    Resolves which Personality data applies to a System vehicle.
    Full notes: docs/functions/modules_system.md

Parameters:
    _systemObject - the vehicle to resolve Personality data for <OBJECT>
    _changes - optional; applied overrides are appended as "key=value"
        (by reference, for logging) <ARRAY>

Returns:
    The resolved crew data <HASHMAP>

Examples:
    [_tigris] call aegism_system_fnc_resolveCrew;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_systemObject", ["_changes", []]];

// Its Site linked with others under a Shared Site Coordinator: that Site's
// personality (aegism_fnc_siteSettingsSource).
private _network = _systemObject getVariable ["AEGISM_network", objNull];
private _source = [_network] call aegism_fnc_siteSettingsSource;
private _base = if (_source != _network) then { _source getVariable "AEGISM_crew" } else { _systemObject getVariable "AEGISM_crew" };
if (isNil "_base" && {!isNull _network}) then { _base = _network getVariable "AEGISM_crew"; };
if (isNil "_base") then { _base = [] call aegism_system_fnc_defaultCrew; };

[_systemObject, _base, "crew", _changes] call aegism_system_fnc_applyOverrides
