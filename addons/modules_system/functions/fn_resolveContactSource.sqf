/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveContactSource

Description:
    Resolves where a Launcher/CIWS-role System draws tracked contacts from:
    its own same-instance Radar role (self-contained case, e.g. a Tigris/
    ZSU-style vehicle), its Network's pooled contact list (networked case),
    both together, or neither -- logging a diag_log warning for the latter
    since that System would otherwise silently never engage anything, per
    the AEGIS-M architecture plan (section 1) link validation requirement.

    Role bitmask (matches aegism_system_fnc_moduleInit): Radar = 1,
    Launcher = 2, CIWS = 4. Reads "AEGISM_system" (HashMap, key "roleMask")
    and "AEGISM_network" (Object or objNull) from the system object.

Parameters:
    _systemObject - the vehicle carrying an AEGISM_Module_System <OBJECT>

Returns:
    Contact source list, any combination of "ownRadar" / "network" (empty
    array if neither is available) <ARRAY of STRING>

Examples:
    [_tigris] call aegism_system_fnc_resolveContactSource;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_systemObject"];

private _sources = [];

private _system = _systemObject getVariable ["AEGISM_system", createHashMap];
private _roleMask = _system getOrDefault ["roleMask", 0];
private _roleRadar = 1;
if ((_roleMask mod (_roleRadar * 2)) >= _roleRadar) then {
    _sources pushBack "ownRadar";
};

private _network = _systemObject getVariable ["AEGISM_network", objNull];
if (!isNull _network) then {
    _sources pushBack "network";
};

if (_sources isEqualTo []) then {
    diag_log text format ["[AEGIS-M] WARNING: System on %1 has no contact source (no own Radar role, no Network) -- it will never detect a target. Sync a Network or enable the Radar role.", _systemObject];
};

_sources
