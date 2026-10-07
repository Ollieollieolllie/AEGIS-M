/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_siteAlarm

Description:
    A Site's alarm, one of three states, updated with the Site's coordinator
    (every 0.5 s, server only).
    Full notes: docs/functions/modules_network.md

Parameters:
    _logic - the Site logic <OBJECT>
    _alarm - this Site's alarm state, [state, sound class, publish count],
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
    // Heard to the Site's Alarm Range: each range is its own class
    // (AEGISM_Alarm_<Tone>_<range>, this addon's config), 400 m the plain one.
    private _ranged = _class + "_" + str _range;
    if (isClass (configFile >> "CfgVehicles" >> _ranged)) exitWith { _ranged };
    ["", _class] select (isClass (configFile >> "CfgVehicles" >> _class))
};

// Its alarm settings: its own, or, linked under a Shared Site Coordinator,
// that Site's (aegism_fnc_siteSettingsSource).
private _settings = [_logic] call aegism_fnc_siteSettingsSource;
private _range = round (_settings getVariable ["alarmRange", 400]);
private _state = "";
private _class = "";
if (CBA_missionTime - (_logic getVariable ["AEGISM_incomingAt", -1e9]) <= AEGISM_INCOMING_HOLD) then {
    _class = [_logic, _settings getVariable ["alarmIncoming", "auto"], _settings getVariable ["alarmIncomingCustom", ""]] call _fnClass;
    if (_class != "") then { _state = "incoming"; };
};
if (_state == "" && {count (_logic getVariable ["AEGISM_claims", createHashMap]) > 0 || {CBA_missionTime - (_logic getVariable ["AEGISM_lastShotAt", -1e9]) <= (_settings getVariable ["alarmHold", 10])}}) then {
    _class = [_logic, _settings getVariable ["alarmWarning", "base"], _settings getVariable ["alarmWarningCustom", ""]] call _fnClass;
    if (_class != "") then { _state = "warning"; };
};

// Same sound (off -> off, or two states set to the same tone): nothing to do.
if (_class == (_alarm select 1)) exitWith { _alarm set [0, _state]; };

// Gone quiet: the All Clear tone, once.
private _once = false;
if (_class == "") then {
    _class = [_logic, _settings getVariable ["alarmClear", "off"], _settings getVariable ["alarmClearCustom", ""]] call _fnClass;
    _once = _class != "";
};

private _speakers = [];
if (_class != "") then {
    // Not another Site synced to this one (that links them, aegism_network_
    // fnc_linkSites), nor a laptop (a status terminal).
    _speakers = (synchronizedObjects _logic) select { !(_x isKindOf "AllVehicles") && {!(_x isKindOf "AEGISM_Module_Site")} && {!([_x] call aegism_network_fnc_isTerminal)} };
    if (_speakers isEqualTo []) then { _speakers = [_logic]; };
};
// Every player's machine plays it (aegism_network_fnc_alarmPlayer): the
// count tells them it's a new state even when the sound is the same as
// before (the All Clear twice).
private _count = (_alarm select 2) + 1;
_logic setVariable ["AEGISM_alarmNow", [_state, _class, _speakers, _count, _once], true];
private _sites = missionNamespace getVariable ["AEGISM_alarmSites", []];
if !(_logic in _sites) then {
    _sites pushBack _logic;
    missionNamespace setVariable ["AEGISM_alarmSites", _sites, true];
};

diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ALARM: Site %1 %2 -> %3%4", _logic, ["off", _alarm select 0] select ((_alarm select 0) != ""),
    if (_once) then { "off, all clear" } else { ["off", _state] select (_state != "") },
    ["", format [" (%1 from %2 speaker(s): %3%4)", _class, count _speakers, _speakers apply { typeOf _x }, ["", ", once"] select _once]] select (_class != "")];
_alarm set [0, _state];
_alarm set [1, ["", _class] select !_once];
_alarm set [2, _count];
