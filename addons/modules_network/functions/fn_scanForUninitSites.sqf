/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_scanForUninitSites

Description:
    One tick of a periodic fallback scan (registered in XEH_postInit.sqf)
    that manually runs aegism_network_fnc_moduleInit on any placed
    AEGISM_Module_Site object whose own module activation never fired --
    working around an observed Eden Preview limitation where a Module_F-
    derived module's own "function"/isTriggerActivated=0 auto-run does not
    reliably invoke in Preview mode, even though the exact same setup runs
    correctly once the mission is exported and launched as a real scenario.

    Finds every placed Site with `entities` (indexed by type) -- it used to
    be allMissionObjects every 2s on every machine, which walks every object
    in the mission. The first pass checks the two agree and logs which one
    this scan uses; if `entities` ever misses a Site that allMissionObjects
    finds, the scan keeps using allMissionObjects.

    A Site is considered already initialized if it has "AEGISM_network
    Members" set (written by aegism_network_fnc_moduleInit itself), so a Site
    whose real activation DID fire is left alone. Synced units are recovered
    via synchronizedObjects -- the same sync-line data the module's own
    activation would have passed.

    Runs on every machine, matching the module's own isGlobal=1 activation
    -- aegism_network_fnc_moduleInit gates its own loop registrations to the
    server.

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
    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " SITE-SCAN: entities finds %1 Site(s), allMissionObjects %2 -- the fallback Site scan uses %3.",
        _byEntities, _byMission, ["allMissionObjects (entities missed some)", "entities"] select _useEntities];
};

{
    private _site = _x;
    if (isNil { _site getVariable "AEGISM_networkMembers" }) then {
        private _units = synchronizedObjects _site;
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " FALLBACK-INIT: %1 never received its own Eden/Preview module activation (a known Preview-mode limitation, not an AEGIS-M bug) -- manually running aegism_network_fnc_moduleInit with %2 synced unit(s) found via synchronizedObjects.", _site, count _units];
        [_site, _units, true] call aegism_network_fnc_moduleInit;
    };
} forEach (if (_useEntities) then { entities "AEGISM_Module_Site" } else { allMissionObjects "AEGISM_Module_Site" });
