/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveCrew

Description:
    Resolves which Personality data applies to a given System vehicle --
    same order as aegism_system_fnc_resolveEngagementSettings: the Site's
    personality ("AEGISM_crew" on the vehicle or its Site logic) or the
    defaults when standalone, then the vehicle's own per-vehicle overrides
    on top (aegism_system_fnc_applyOverrides).

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

private _base = _systemObject getVariable "AEGISM_crew";
if (isNil "_base") then {
    private _network = _systemObject getVariable ["AEGISM_network", objNull];
    if (!isNull _network) then { _base = _network getVariable "AEGISM_crew"; };
};
if (isNil "_base") then { _base = [] call aegism_system_fnc_defaultCrew; };

[_systemObject, _base, "crew", _changes] call aegism_system_fnc_applyOverrides
