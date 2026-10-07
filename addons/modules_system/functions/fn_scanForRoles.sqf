/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_scanForRoles

Description:
    One tick of the periodic discovery scan (registered in XEH_postInit.sqf)
    that calls aegism_system_fnc_moduleInit on any vehicle not yet
    processed.
    Full notes: docs/functions/modules_system.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_system_fnc_scanForRoles;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Deferred vehicles (capable but not synced, see aegism_system_fnc_
// moduleInit) are skipped here -- discovery is config-heavy, and they're
// re-evaluated directly by aegism_network_fnc_moduleInit when synced.
private _newlyScanned = 0;
private _server = isServer;
{
    if ((_server || {local _x}) && {!(_x getVariable ["AEGISM_systemInitialized", false])} && {!(_x getVariable ["AEGISM_systemDeferred", false])}) then {
        _newlyScanned = _newlyScanned + 1;
        [_x] call aegism_system_fnc_moduleInit;
    };
} forEach vehicles;

// Logged only on the very first pass (missionNamespace flag, not per-tick)
// so it's easy to confirm the scan is actually running at all without
// spamming the RPT every 2 seconds for the rest of the mission.
if (isNil "AEGISM_scanForRolesFirstPassLogged") then {
    missionNamespace setVariable ["AEGISM_scanForRolesFirstPassLogged", true];
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DISCOVERY: first scan pass ran, %1 vehicle(s) in mission at this point, %2 newly checked.", count vehicles, _newlyScanned];
};
