/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugCheckSite

Description:
    On-demand sync/capability sanity check, meant to be run from the Arma
    debug console (or any script) while testing a mission, rather than
    reading RPT log output after the fact -- answers "is my radar/launcher
    actually linked to this Site, and did AEGIS-M even recognize it as
    something it can use" directly and immediately.

    With no argument, reports on every Site currently registered
    (AEGISM_allPoolOwners' Network-type entries, i.e. every placed and
    activated AEGISM_Module_Site). With a specific Site logic object, reports
    on just that one.

    For each Site: member count, and per member -- its class, whether
    AEGISM_network actually points back at this Site (catches a vehicle that
    LOOKS synced in Eden's sync-line view but whose module init never ran or
    targeted a different Site, e.g. from a stale isGlobal netId issue), and
    its discovered capability (hasRadar/radarRange, launcher weapon count,
    CIWS weapon count) -- or "NOT AN AEGIS-M SYSTEM" if aegism_system_fnc_
    moduleInit never found it to have any qualifying capability at all (the
    single most common reason "nothing happens": a vehicle synced to the
    Site that AEGIS-M itself never recognized, e.g. wrong vehicle, no real
    radar/missile/CIWS loadout).

    Prints to hint (visible in-game immediately) AND diag_log (so it's also
    captured in the RPT for later reference) -- deliberately not gated
    behind the "aegism_main_debugDraw" CBA setting, since this is a one-shot
    manual check a mission tester runs on demand, not a continuous overlay.

Parameters:
    _site - a specific Site logic object to check, or nothing/objNull to
        check every currently-registered Site <OBJECT, optional>

Returns:
    Nothing

Examples:
    [] call aegism_fnc_debugCheckSite;
    [aegism_site_1] call aegism_fnc_debugCheckSite;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_site", objNull]];

private _allOwners = missionNamespace getVariable ["AEGISM_allPoolOwners", []];
// A Site is any pool owner with NO "AEGISM_system" variable of its own --
// that's exactly how the rest of the codebase (e.g. aegism_fnc_debugDraw)
// already tells a Network/Site logic apart from a System vehicle, since
// only a System ever gets AEGISM_system set (see aegism_system_fnc_
// moduleInit).
private _sites = if (isNull _site) then {
    _allOwners select { isNil { _x getVariable "AEGISM_system" } }
} else {
    [_site]
};

if (_sites isEqualTo []) exitWith {
    private _msg = "[AEGIS-M] DEBUG CHECK: no Site found -- either none is placed/activated yet, or AEGISM_allPoolOwners is empty (nothing has registered at all, which itself would mean no AEGISM_Module_Site has run its init).";
    hint _msg;
    diag_log text _msg;
};

{
    private _thisSite = _x;
    private _members = _thisSite getVariable ["AEGISM_networkMembers", []];
    private _lines = [format ["=== AEGIS-M Site Check: %1 ===", _thisSite], format ["Members synced: %1", count _members]];

    if (_members isEqualTo []) then {
        _lines pushBack "  (no vehicles synced to this Site at all -- check the sync lines in Eden/Zeus)";
    };

    {
        private _member = _x;
        private _networkOk = (_member getVariable ["AEGISM_network", objNull]) == _thisSite;
        private _system = _member getVariable "AEGISM_system";

        private _line = format ["  - %1 (%2): AEGISM_network points to this Site = %3", _member, typeOf _member, _networkOk];
        _lines pushBack _line;

        if (isNil "_system") then {
            _lines pushBack "      NOT AN AEGIS-M SYSTEM -- aegism_system_fnc_discoverCapabilities found no real radar sensor, no missile/rocket magazine, and no high-rate-of-fire gun magazine on this vehicle's current loadout. Check the RPT for a matching '[AEGIS-M] DISCOVERY:' line, or that this is really the vehicle you intended to sync.";
        } else {
            _lines pushBack format ["      hasRadar=%1 (range=%2m) launcherWeapons=%3 ciwsWeapons=%4", _system get "hasRadar", round (_system get "radarRange"), count (_system get "launcherWeapons"), count (_system get "ciwsWeapons")];
        };
    } forEach _members;

    private _pool = _thisSite getVariable ["AEGISM_pooledContacts", createHashMap];
    private _claims = _thisSite getVariable ["AEGISM_claims", createHashMap];
    _lines pushBack format ["Pooled contacts: %1 -- Active assignments: %2", count _pool, count _claims];

    private _fullMsg = _lines joinString "\n";
    hint _fullMsg;
    diag_log text _fullMsg;
} forEach _sites;
