/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugCheckSite

Description:
    On-demand sync and capability check of a Site or vehicle, run from the
    debug console.
    Full notes: docs/functions/main.md

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
            _lines pushBack "      NOT AN AEGIS-M SYSTEM -- aegism_system_fnc_discoverCapabilities found no radar, IR or visual sensor, no missile/rocket magazine, and no high-rate-of-fire gun magazine on this vehicle's current loadout. Check the RPT for a matching '[AEGIS-M] DISCOVERY:' line, or that this is really the vehicle you intended to sync.";
        } else {
            private _sensorText = ((_system getOrDefault ["sensors", []]) apply { format ["%1 %2m %3deg", _x select 0, round (_x select 1), round (_x select 2)] }) joinString ", ";
            _lines pushBack format ["      sensors: %1; launcherWeapons=%2 ciwsWeapons=%3", [_sensorText, "none"] select (_sensorText == ""), count (_system get "launcherWeapons"), count (_system get "ciwsWeapons")];
        };
    } forEach _members;

    private _pool = _thisSite getVariable ["AEGISM_pooledContacts", createHashMap];
    private _claims = _thisSite getVariable ["AEGISM_claims", createHashMap];
    _lines pushBack format ["Pooled contacts: %1 -- Active assignments: %2", count _pool, count _claims];

    private _fullMsg = _lines joinString "\n";
    hint _fullMsg;
    diag_log text _fullMsg;
} forEach _sites;
