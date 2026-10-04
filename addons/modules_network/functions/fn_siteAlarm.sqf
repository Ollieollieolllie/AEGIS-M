/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_siteAlarm

Description:
    A Site's alarm, one of three states, updated with the Site's
    coordinator (every 0.5s, server only):
        incoming - a munition threatening the Site was seen within the last
            AEGISM_INCOMING_HOLD s ("AEGISM_incomingAt", written by aegism_
            detect_fnc_munitionCheck)
        warning - the Site has a weapon assigned to a target (going live:
            before its first shot), or fired within the last "alarmHold" s
            ("AEGISM_lastShotAt", written by aegism_intercept_fnc_
            onSystemFired)
        off - neither
    Incoming replaces warning; a state whose tone is "off" falls through to
    the next.

    Each state's tone is a looping sound source (this addon's CfgVehicles
    AEGISM_Alarm_*, or the Site's custom class) created at every speaker --
    each non-vehicle object synced to the Site, or the Site logic itself if
    there is none. The engine loops it, and deleting it stops it at once, so
    the network only carries a change of state, never the repeats. (A laptop
    synced to the Site is its status terminal, aegism_network_fnc_
    isTerminal, not a speaker.) Nothing
    happens between changes but a few variable reads.

    Logged as ALARM on each change.

Parameters:
    _logic - the Site logic <OBJECT>
    _alarm - this Site's alarm state, [state, sound class, sound sources],
        updated in place <ARRAY>

Returns:
    Nothing

Examples:
    [_logic, _alarm] call aegism_network_fnc_siteAlarm;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// The pools' own contact expiry (aegism_detect_fnc_pruneStaleContacts): an
// inbound round not seen for this long has dropped out of the Site's pool.
#define AEGISM_INCOMING_HOLD 3

params ["_logic", "_alarm"];

// A tone setting -> its sound source class ("" = off).
private _fnClass = {
    params ["_logic", "_tone", "_custom"];
    if (_custom != "" && {isClass (configFile >> "CfgVehicles" >> _custom)}) exitWith { _custom };
    if (_tone == "auto") then {
        // The Site's side: its first crewed member's.
        private _members = _logic getVariable ["AEGISM_networkMembers", []];
        private _index = _members findIf { alive _x && {side _x in [west, east, independent]} };
        private _side = civilian;
        if (_index != -1) then { _side = side (_members select _index); };
        _tone = switch (_side) do {
            case west: { "heliNato" };
            case east: { "heliCsat" };
            default { "klaxon" };
        };
    };
    if (_tone == "off") exitWith { "" };
    private _class = "AEGISM_Alarm_" + (toUpper (_tone select [0, 1])) + (_tone select [1]);
    ["", _class] select (isClass (configFile >> "CfgVehicles" >> _class))
};

// Its alarm settings: its own, or, linked under a Shared Site Coordinator,
// that Site's (aegism_fnc_siteSettingsSource).
private _settings = [_logic] call aegism_fnc_siteSettingsSource;
private _state = "";
private _class = "";
if (time - (_logic getVariable ["AEGISM_incomingAt", -1e9]) <= AEGISM_INCOMING_HOLD) then {
    _class = [_logic, _settings getVariable ["alarmIncoming", "auto"], _settings getVariable ["alarmIncomingCustom", ""]] call _fnClass;
    if (_class != "") then { _state = "incoming"; };
};
if (_state == "" && {count (_logic getVariable ["AEGISM_claims", createHashMap]) > 0 || {time - (_logic getVariable ["AEGISM_lastShotAt", -1e9]) <= (_settings getVariable ["alarmHold", 10])}}) then {
    _class = [_logic, _settings getVariable ["alarmWarning", "base"], _settings getVariable ["alarmWarningCustom", ""]] call _fnClass;
    if (_class != "") then { _state = "warning"; };
};

// Same sound (off -> off, or two states set to the same tone): nothing to do.
if (_class == (_alarm select 1)) exitWith { _alarm set [0, _state]; };

{ deleteVehicle _x; } forEach (_alarm select 2);
private _sources = [];
private _speakers = [];
if (_class != "") then {
    // Not another Site synced to this one (that links them, aegism_network_
    // fnc_linkSites), nor a laptop (a status terminal).
    _speakers = (synchronizedObjects _logic) select { !(_x isKindOf "AllVehicles") && {!(_x isKindOf "AEGISM_Module_Site")} && {!([_x] call aegism_network_fnc_isTerminal)} };
    if (_speakers isEqualTo []) then { _speakers = [_logic]; };
    { _sources pushBack (createSoundSource [_class, getPosATL _x, [], 0]); } forEach _speakers;
};
diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " ALARM: Site %1 %2 -> %3%4", _logic, ["off", _alarm select 0] select ((_alarm select 0) != ""), ["off", _state] select (_state != ""),
    ["", format [" (%1 from %2 speaker(s): %3)", _class, count _speakers, _speakers apply { typeOf _x }]] select (_class != "")];
_alarm set [0, _state];
_alarm set [1, _class];
_alarm set [2, _sources];
