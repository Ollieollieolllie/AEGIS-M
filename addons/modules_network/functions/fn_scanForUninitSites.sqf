/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_scanForUninitSites

Description:
    One tick of the fallback scan that runs aegism_network_fnc_moduleInit on
    any placed Site whose module activation never fired.
    Full notes: docs/functions/modules_network.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_network_fnc_scanForUninitSites;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

private _useEntities = missionNamespace getVariable "AEGISM_siteScanUsesEntities";
if (isNil "_useEntities") then {
    private _byEntities = count (entities "AEGISM_Module_Site");
    private _byMission = count (allMissionObjects "AEGISM_Module_Site");
    _useEntities = _byEntities >= _byMission;
    missionNamespace setVariable ["AEGISM_siteScanUsesEntities", _useEntities];
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SITE-SCAN: entities finds %1 Site(s), allMissionObjects %2 -- the fallback Site scan uses %3.",
        _byEntities, _byMission, ["allMissionObjects (entities missed some)", "entities"] select _useEntities];
};

{
    private _site = _x;
    if (isNil { _site getVariable "AEGISM_networkMembers" }) then {
        private _units = synchronizedObjects _site;
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " FALLBACK-INIT: %1 never received its own Eden/Preview module activation (a known Preview-mode limitation, not an AEGIS-M bug) -- manually running aegism_network_fnc_moduleInit with %2 synced unit(s) found via synchronizedObjects.", _site, count _units];
        [_site, _units, true] call aegism_network_fnc_moduleInit;
    };
} forEach (if (_useEntities) then { entities "AEGISM_Module_Site" } else { allMissionObjects "AEGISM_Module_Site" });
