/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_scanForRoles

Description:
    One tick of the periodic discovery scan (registered in XEH_postInit.sqf)
    that calls aegism_system_fnc_moduleInit on any vehicle not yet
    processed. There is no role checkbox to read anymore -- every vehicle
    in the mission gets exactly one discovery pass (aegism_system_fnc_
    moduleInit itself decides whether it actually has any AEGIS-M-relevant
    capability -- real radar, guided missiles, or a high-rate-of-fire gun --
    and marks it processed either way so it's never re-scanned), which is
    what makes "just take an existing radar/launcher/CIWS vehicle, no setup
    needed" actually work.

    Runs on every machine (not isServer-gated) so every client also gets
    the non-server parts of aegism_system_fnc_moduleInit (AEGISM_system,
    resolved caches) -- that function's own internal isServer gates still
    correctly limit the actual detection/engagement loop registrations to
    the server.

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_system_fnc_scanForRoles;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

{
    if (!(_x getVariable ["AEGISM_systemInitialized", false])) then {
        [_x] call aegism_system_fnc_moduleInit;
    };
} forEach vehicles;
