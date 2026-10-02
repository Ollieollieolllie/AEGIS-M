/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveContactSource

Description:
    Resolves where a Launcher/CIWS-capable System draws tracked contacts
    from: its own sensors (self-contained case: a radar, IR or visual
    sensor of its own -- a Tigris/ZSU-style vehicle, or a Spartan with its
    launcher-mounted IR), its Network's pooled contact list (networked
    case), both together, or neither -- logging a diag_log warning for
    either dead end, since that System would otherwise silently never
    engage anything. A synced Network only counts as a real contact source
    if at least one of its current members (per the live
    "AEGISM_networkMembers" list, see aegism_network_fnc_moduleInit) has a
    sensor of its own -- a Network with none anywhere in it can never
    populate its own pool, so a Launcher relying solely on it would
    otherwise pass this check yet still never see a single contact.

    Called periodically (not just once at init, see aegism_system_fnc_
    moduleInit's re-resolution poll) so a Network gaining or losing its
    only sensor-equipped member is reflected without a mission restart; the
    warning message is only re-logged when it actually changes, so a
    persisting problem doesn't spam the RPT log every poll.

    Reads "AEGISM_system" (HashMap, key "hasSensor", aegism_system_fnc_
    discoverCapabilities) and "AEGISM_network" (Object or objNull) from the
    system object.

Parameters:
    _systemObject - the vehicle to resolve a contact source for <OBJECT>

Returns:
    Contact source list, any combination of "ownSensor" / "network" (empty
    array if neither is available) <ARRAY of STRING>

Examples:
    [_tigris] call aegism_system_fnc_resolveContactSource;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_systemObject"];

private _sources = [];

private _system = _systemObject getVariable ["AEGISM_system", createHashMap];
if (_system getOrDefault ["hasSensor", false]) then {
    _sources pushBack "ownSensor";
};

private _network = _systemObject getVariable ["AEGISM_network", objNull];
private _warning = "";

if (!isNull _network) then {
    private _members = _network getVariable ["AEGISM_networkMembers", []];
    private _networkHasSensor = (_members findIf {
        private _memberSystem = _x getVariable ["AEGISM_system", createHashMap];
        _memberSystem getOrDefault ["hasSensor", false]
    }) != -1;

    if (_networkHasSensor) then {
        _sources pushBack "network";
    } else {
        _warning = format ["System on %1 is synced to Network %2, but no current member of that Network has a sensor of its own (radar, IR or visual) -- it will never receive any contacts from it.", _systemObject, _network];
    };
};

if (_sources isEqualTo []) then {
    _warning = format ["System on %1 has no contact source (no sensor of its own, no Network with a sensor-equipped member) -- it will never detect a target.", _systemObject];
};

private _lastWarning = _systemObject getVariable ["AEGISM_lastContactSourceWarning", ""];
if (_warning != _lastWarning) then {
    _systemObject setVariable ["AEGISM_lastContactSourceWarning", _warning, false];
    if (_warning != "") then {
        diag_log text ("[AEGIS-M] t=" + (time toFixed 1) + " WARNING: " + _warning);
    } else {
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " System on %1 now has a contact source: %2 (earlier warning resolved).", _systemObject, _sources];
    };
};

_sources
