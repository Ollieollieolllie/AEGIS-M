/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_scanForUninitSites

Description:
    One tick of a periodic fallback scan (registered in XEH_postInit.sqf)
    that manually runs aegism_network_fnc_moduleInit on any placed
    AEGISM_Module_Site object whose own module activation never fired --
    working around a real, observed Eden Preview limitation where a
    Module_F-derived module's own "function"/isTriggerActivated=0 auto-run
    does not reliably invoke in Preview mode, even though the exact same
    placement/sync setup runs correctly once the mission is actually
    exported and launched as a real scenario. Confirmed directly against an
    RPT where every launcher logged contactSource=[] (never synced to
    anything) despite the Site module being genuinely placed and synced in
    Eden, with zero trace anywhere in the RPT of aegism_network_fnc_
    moduleInit, or any error, ever running at all -- config.cpp's own
    function/isGlobal/isTriggerActivated setup is entirely standard and
    correct, so there was nothing for AEGIS-M's own code to have caught;
    this scan exists purely to route around the engine's own Preview-mode
    gap rather than to fix a bug in this codebase.

    Finds every placed instance via allMissionObjects "AEGISM_Module_Site"
    (the CfgVehicles classname itself, not a scan of `vehicles` -- a module
    logic object is not a vehicle and would never appear there). A Site is
    considered already initialized if it has "AEGISM_networkMembers" set
    (written by aegism_network_fnc_moduleInit itself, see that function's
    own doc comment) -- so a Site whose real Eden activation DID fire
    (Preview working correctly, or an exported mission) is left alone and
    never double-initialized by this fallback; only a Site that's been
    sitting uninitialized is picked up.

    Synced units are recovered via synchronizedObjects _site directly --
    this is the same real sync-line data Eden's own module activation would
    have passed as moduleInit's own "_units" parameter, read straight off
    the object rather than depending on the module's own activation
    pipeline having run at all, so this works identically regardless of
    WHY the real activation didn't fire.

    Runs on every machine (not isServer-gated), matching aegism_system_fnc_
    scanForRoles' own reasoning -- aegism_network_fnc_moduleInit itself
    internally gates its own loop registrations to isServer, so calling it
    unconditionally here is exactly as safe as the module's own real
    isGlobal=1 activation would have been.

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_network_fnc_scanForUninitSites;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

{
    private _site = _x;
    if (isNil { _site getVariable "AEGISM_networkMembers" }) then {
        private _units = synchronizedObjects _site;
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " FALLBACK-INIT: %1 never received its own Eden/Preview module activation (a known Preview-mode limitation, not an AEGIS-M bug) -- manually running aegism_network_fnc_moduleInit with %2 synced unit(s) found via synchronizedObjects.", _site, count _units];
        [_site, _units, true] call aegism_network_fnc_moduleInit;
    };
} forEach (allMissionObjects "AEGISM_Module_Site");
