/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveSettings

Description:
    Resolves and caches a System's settings from its Site (or the defaults),
    with its own overrides applied.
    Full notes: docs/functions/modules_system.md

Parameters:
    _vehicle - the System vehicle <OBJECT>

Returns:
    The overrides applied, as "key=value" strings <ARRAY>

Examples:
    [_patriot] call aegism_system_fnc_resolveSettings;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle"];

private _overrides = [];
private _engagementSettings = [_vehicle, _overrides] call aegism_system_fnc_resolveEngagementSettings;
private _crew = [_vehicle, _overrides] call aegism_system_fnc_resolveCrew;
_vehicle setVariable ["AEGISM_resolvedContactSource", [_vehicle] call aegism_system_fnc_resolveContactSource, false];
_vehicle setVariable ["AEGISM_resolvedEngagementSettings", _engagementSettings, false];
_vehicle setVariable ["AEGISM_resolvedCrew", _crew, false];
_vehicle setVariable ["AEGISM_resolvedCrewMods", [_crew, _vehicle] call aegism_intercept_fnc_applyCrewModulation, false];

_overrides
