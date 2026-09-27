/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveCrew

Description:
    Resolves which Personality data applies to a given System vehicle, per
    the object -> network -> default fallback order defined in the AEGIS-M
    architecture plan (section 1) -- identical resolution order to aegism_
    system_fnc_resolveEngagementSettings, applied to crew personality data
    instead of doctrine data. "Object" here means directly set on the
    vehicle itself (possible via scripting; there's no separate per-vehicle
    Personality module anymore), "network" means inherited from a synced
    AEGISM_Module_Site's own Personality Attributes.

    Reads the object-namespaced variables "AEGISM_crew" (HashMap or nil) and
    "AEGISM_network" (Object or objNull).

Parameters:
    _systemObject - the vehicle to resolve Personality data for <OBJECT>

Returns:
    The resolved crew data <HASHMAP>

Examples:
    [_tigris] call aegism_system_fnc_resolveCrew;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_systemObject"];

private _ownCrew = _systemObject getVariable "AEGISM_crew";
if (!isNil "_ownCrew") exitWith {
    _ownCrew
};

private _network = _systemObject getVariable ["AEGISM_network", objNull];
if (!isNull _network) then {
    private _networkCrew = _network getVariable "AEGISM_crew";
    if (!isNil "_networkCrew") exitWith {
        _networkCrew
    };
};

[] call aegism_system_fnc_defaultCrew
