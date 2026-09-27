/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_resolveContactSource

Description:
    Resolves where a Launcher/CIWS-capable System draws tracked contacts
    from: its own native radar (self-contained case, e.g. a Tigris/ZSU-
    style vehicle with both missiles and its own sensor), its Network's
    pooled contact list (networked case), both together, or neither --
    logging a diag_log warning for either dead end, since that System would
    otherwise silently never engage anything, per the AEGIS-M architecture
    plan (section 1) link validation requirement. A synced Network only
    counts as a real contact source if at least one of its current members
    (per the live "AEGISM_networkMembers" list, see aegism_network_fnc_
    moduleInit) actually has radar capability -- a Network with no radar
    anywhere in it can never populate its own pool, so a Launcher relying
    solely on it would otherwise pass this check yet still never see a
    single contact.

    Called periodically (not just once at init, see aegism_system_fnc_
    moduleInit's re-resolution poll) so a Network gaining or losing its
    only radar-equipped member is reflected without a mission restart; the
    warning message is only re-logged when it actually changes, so a
    persisting problem doesn't spam the RPT log every poll.

    Reads "AEGISM_system" (HashMap, key "hasRadar") and "AEGISM_network"
    (Object or objNull) from the system object.

Parameters:
    _systemObject - the vehicle to resolve a contact source for <OBJECT>

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
if (_system getOrDefault ["hasRadar", false]) then {
    _sources pushBack "ownRadar";
};

private _network = _systemObject getVariable ["AEGISM_network", objNull];
private _warning = "";

if (!isNull _network) then {
    private _members = _network getVariable ["AEGISM_networkMembers", []];
    private _networkHasRadar = (_members findIf {
        private _memberSystem = _x getVariable ["AEGISM_system", createHashMap];
        _memberSystem getOrDefault ["hasRadar", false]
    }) != -1;

    if (_networkHasRadar) then {
        _sources pushBack "network";
    } else {
        _warning = format ["System on %1 is synced to Network %2, but no current member of that Network has radar capability -- it will never receive any contacts from it.", _systemObject, _network];
    };
};

if (_sources isEqualTo []) then {
    _warning = format ["System on %1 has no contact source (no radar of its own, no Network with a radar-capable member) -- it will never detect a target.", _systemObject];
};

if (_warning != "" && {_systemObject getVariable ["AEGISM_lastContactSourceWarning", ""] != _warning}) then {
    diag_log text ("[AEGIS-M] WARNING: " + _warning);
    _systemObject setVariable ["AEGISM_lastContactSourceWarning", _warning, false];
};

_sources
