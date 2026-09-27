/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveCrew

Description:
    Resolves which AEGISM_Module_Crew data applies to a given System object,
    per the object -> network -> default fallback order defined in the
    AEGIS-M architecture plan (section 1) -- identical resolution order to
    aegism_system_fnc_resolveEngagementSettings, applied to crew personality
    data instead of doctrine data.

    Reads the object-namespaced variables "AEGISM_crew" (HashMap or nil) and
    "AEGISM_network" (Object or objNull).

Parameters:
    _systemObject - the vehicle carrying an AEGISM_Module_System <OBJECT>

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
