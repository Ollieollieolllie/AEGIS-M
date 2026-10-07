/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalIntercept

Description:
    Shows the server's answer on this machine's open terminal screen, on its
    Interception page: the track and weapon lists, the automation switch,
    and the orders standing. The page's map draws from the same answer
    (aegism_network_fnc_terminalMapDraw).
    Full notes: docs/functions/modules_network.md

Parameters:
    _picture - [node, what's wrong, automation on, Site name, tracks,
        weapons, orders, last lines, missiles in flight, radars]
        (aegism_network_fnc_terminalPicture) <ARRAY>

Returns:
    Nothing

Examples:
    [_picture] remoteExecCall ["aegism_network_fnc_terminalIntercept", _owner];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

params [["_picture", []]];

private _display = uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull];
private _state = uiNamespace getVariable "AEGISM_terminalState";
if (isNull _display || {isNil "_state"}) exitWith {};

_picture params [["_node", objNull], ["_error", ""], ["_automation", true], ["_siteName", ""], ["_tracks", []], ["_weapons", []], ["_orders", []], ["_log", []], ["_missiles", []], ["_radars", []]];
// An answer for what was shown a moment ago: dropped.
private _shown = ((_state get "nodes") param [_state get "node", []]) param [0, objNull];
if ((_state get "tab") != "intercept" || {_shown isNotEqualTo _node}) exitWith {};

_state set ["picture", _picture];
_state set ["pictureAt", CBA_missionTime];

private _fnRange = {
    if (_this >= 1000) then { format ["%1 km", (round (_this / 100)) / 10] } else { format ["%1 m", round _this] }
};
private _fnShort = {
    private _name = getText (configOf _this >> "displayName");
    if (_name == "") then { _name = typeOf _this; };
    _name
};

private _auto = _display displayCtrl AEGISM_TERMINAL_AUTO_IDC;
_auto ctrlSetText (["AUTOMATION: OFF  (orders only)", "AUTOMATION: ON"] select _automation);
_auto ctrlSetTextColor ([[1, 0.65, 0.15, 1], AEGISM_TERMINAL_ACCENT] select _automation);
_auto ctrlEnable (_error == "");

// --- Tracks: soonest impact first, then nearest -------------------------------
private _from = getPosASL _node;
private _order = [];
{ _order pushBack [_x select 6, _from distance (_x select 3), _forEachIndex]; } forEach _tracks;
_order sort true;

private _trackKey = _state getOrDefault ["trackKey", ""];
private _trackList = _display displayCtrl AEGISM_TERMINAL_TRACKS_IDC;
// (Filled again every second: the list's own event is told so, and doesn't
// take the selection being put back for a pick.)
_state set ["filling", true];
lbClear _trackList;
private _selectedRow = -1;
// (Surface Strike's point, first: picked like a track.)
private _strikePoint = _state getOrDefault ["strikePoint", []];
if (_strikePoint isNotEqualTo []) then {
    private _row = _trackList lbAdd format ["STRIKE POINT  grid %1  %2", mapGridPosition _strikePoint, (_from distance _strikePoint) call _fnRange];
    _trackList lbSetData [_row, "@strike"];
    _trackList lbSetColor [_row, [1, 0.65, 0.15, 1]];
    if (_trackKey == "@strike") then { _selectedRow = _row; };
};
{
    (_tracks select (_x select 2)) params ["_key", "_class", "_kind", "", "", "_name", "_tti", "_on"];
    private _text = format ["%1  %2  %3", toUpper _class, _name, (_x select 1) call _fnRange];
    if (_tti < 1e9) then { _text = _text + format ["  %1 s", round _tti]; };
    if (_kind in ["friendly", "neutral"]) then { _text = _text + format ["  [%1]", toUpper _kind]; };
    if (_kind == "hostile") then { _text = _text + "  [NOT ENGAGED]"; };
    if (_on isNotEqualTo []) then { _text = _text + format ["  <%1>", count _on]; };
    private _row = _trackList lbAdd _text;
    _trackList lbSetData [_row, _key];
    _trackList lbSetColor [_row, switch (_kind) do {
        case "threat": { AEGISM_TERMINAL_TRACK_THREAT };
        case "ordered": { AEGISM_TERMINAL_TRACK_ORDERED };
        case "hostile": { AEGISM_TERMINAL_TRACK_HOSTILE };
        case "friendly": { AEGISM_TERMINAL_TRACK_FRIENDLY };
        default { AEGISM_TERMINAL_TRACK_NEUTRAL };
    }];
    if (_key == _trackKey) then { _selectedRow = _row; };
} forEach _order;
if (_selectedRow == -1) then { _state set ["trackKey", ""]; } else { _trackList lbSetCurSel _selectedRow; };
(_display displayCtrl AEGISM_TERMINAL_TRACKS_HEAD_IDC) ctrlSetStructuredText parseText format [
    "<t size='0.8' font='PuristaSemibold' color='%1'>TRACKS</t><t size='0.75' color='%2'>   %3 held or seen by %4</t>",
    AEGISM_TERMINAL_ACCENT_HEX, AEGISM_TERMINAL_DIM_HEX, count _tracks, _siteName];

// --- Weapons: of the Site or vehicle picked ---------------------------------
// One row a weapon -- and one row for every launcher of a type standing
// together (within AEGISM_TERMINAL_BATTERY_RADIUS of another of the row,
// same vehicle type, turret, weapon and magazine): a battery of four is
// one row with its missiles added up, and an order to it goes to whichever
// of them is best placed (aegism_network_fnc_terminalOrder).
// [kind, indices into _weapons]
private _rows = [];
{
    _x params ["_vehicle", "_role", "_turretPath", "_weaponClass", "_magClass"];
    private _kind = [typeOf _vehicle, _role, _turretPath, _weaponClass, _magClass];
    private _index = _rows findIf {
        (_x select 0) isEqualTo _kind && {((_x select 1) findIf { (((_weapons select _x) select 0) distance _vehicle) <= AEGISM_TERMINAL_BATTERY_RADIUS }) != -1}
    };
    if (_index == -1) then { _rows pushBack [_kind, [_forEachIndex]]; } else { ((_rows select _index) select 1) pushBack _forEachIndex; };
} forEach _weapons;

private _weaponId = _state getOrDefault ["weaponId", ""];
private _weaponList = _display displayCtrl AEGISM_TERMINAL_WEAPONS_IDC;
lbClear _weaponList;
_selectedRow = -1;
// What the screen keeps of each row, for its orders and its map: [id,
// [vehicle, ...], turret, weapon, [reach m, ...], one of them has a shot]
private _kept = [];
private _labelled = [];
{
    _x params ["_kind", "_members"];
    _kind params ["", "_role", "_turretPath", "_weaponClass", "_magClass"];
    private _entries = _members apply { _weapons select _x };
    private _vehicles = _entries apply { _x select 0 };
    private _first = _vehicles select 0;
    private _rounds = 0;
    { _rounds = _rounds + ((_x select 5) max 0); } forEach _entries;
    private _picked = (_entries select 0) select 7;
    private _able = { _x select 8 } count _entries;

    private _munition = getText (configFile >> "CfgMagazines" >> _magClass >> "displayName");
    if (_munition == "") then { _munition = getText (configFile >> "CfgWeapons" >> _weaponClass >> "displayName"); };
    if (_munition == "") then { _munition = _weaponClass; };
    // (One on its own carries its callsign: a Site can have several of the
    // same launcher apart from each other.)
    private _text = if (count _entries > 1) then {
        format ["%1  x%2  --  %3  x%4", _first call _fnShort, count _entries, _munition, _rounds]
    } else {
        format ["%1 (%2)  --  %3  x%4", _first call _fnShort, _first, _munition, _rounds]
    };
    if (_picked) then {
        _text = _text + (switch (true) do {
            case (_able == 0): { "  --  " + ((_entries select 0) select 9) };
            case (count _entries > 1): { format ["  --  %1 OF %2 HAVE A SHOT", _able, count _entries] };
            default { "  --  HAS A SHOT" };
        });
    };
    private _row = _weaponList lbAdd _text;
    private _id = format ["%1|%2|%3", netId _first, _turretPath, _weaponClass];
    _weaponList lbSetData [_row, _id];
    _weaponList lbSetTooltip [_row, format ["%1 -- %2, %3", _vehicles, ["launcher", "gun"] select (_role == "ciws"), _weaponClass]];
    _weaponList lbSetColor [_row, switch (true) do {
        case (_rounds <= 0): { AEGISM_TERMINAL_TRACK_NEUTRAL };
        case (_picked && {_able > 0}): { [0.4, 0.73, 0.42, 1] };
        case _picked: { AEGISM_TERMINAL_DIM };
        default { [0.85, 0.88, 0.9, 1] };
    }];
    if (_id == _weaponId) then { _selectedRow = _row; };
    _kept pushBack [_id, _vehicles, _turretPath, _weaponClass, _entries apply { _x select 6 }, _able > 0];
    _labelled pushBackUnique _first;
} forEach _rows;
if (_selectedRow == -1) then { _state set ["weaponId", ""]; } else { _weaponList lbSetCurSel _selectedRow; };
_state set ["rows", _kept];
// For the map: the vehicles named on it (one of each row), and the reach
// of each launcher of the row picked.
_state set ["labelled", _labelled];
private _pickedRow = _kept param [_kept findIf { (_x select 0) == (_state get "weaponId") }, []];
private _rings = [];
{ _rings pushBack [_x, (_pickedRow select 4) select _forEachIndex]; } forEach (_pickedRow param [1, []]);
_state set ["rings", _rings];
(_display displayCtrl AEGISM_TERMINAL_WEAPONS_HEAD_IDC) ctrlSetStructuredText parseText format [
    "<t size='0.8' font='PuristaSemibold' color='%1'>WEAPONS</t><t size='0.75' color='%2'>   %3</t>",
    AEGISM_TERMINAL_ACCENT_HEX, AEGISM_TERMINAL_DIM_HEX,
    ["pick a track to see which has a shot at it", "against the track picked"] select ((_state get "trackKey") != "")];

// --- Radars: of the Site or vehicle picked -----------------------------------
// The first row stands for all of them (what the three buttons under the
// list order, with it picked).
private _radarId = _state getOrDefault ["radarId", ""];
private _radarList = _display displayCtrl AEGISM_TERMINAL_RADARS_IDC;
lbClear _radarList;
private _emitting = { _x select 1 } count _radars;
private _all = _radarList lbAdd format ["ALL RADARS  --  %1 of %2 emitting", _emitting, count _radars];
_radarList lbSetData [_all, ""];
_radarList lbSetColor [_all, [0.85, 0.88, 0.9, 1]];
_selectedRow = _all;
{
    _x params ["_vehicle", "_on", "_order", "_label", "_detail"];
    private _text = format ["%1 (%2)  --  %3", _vehicle call _fnShort, _vehicle, _label];
    if (_order != "") then { _text = _text + "  [ORDERED]"; };
    private _row = _radarList lbAdd _text;
    private _id = netId _vehicle;
    _radarList lbSetData [_row, _id];
    _radarList lbSetTooltip [_row, _detail];
    _radarList lbSetColor [_row, [AEGISM_TERMINAL_RADAR_OFF, AEGISM_TERMINAL_RADAR_ON] select _on];
    if (_id == _radarId) then { _selectedRow = _row; };
} forEach _radars;
if (_selectedRow == _all) then { _state set ["radarId", ""]; };
_radarList lbSetCurSel _selectedRow;
_state set ["filling", false];
(_display displayCtrl AEGISM_TERMINAL_RADARS_HEAD_IDC) ctrlSetStructuredText parseText format [
    "<t size='0.8' font='PuristaSemibold' color='%1'>RADARS</t><t size='0.75' color='%2'>   hover a row for what it's doing</t>",
    AEGISM_TERMINAL_ACCENT_HEX, AEGISM_TERMINAL_DIM_HEX];
{ (_display displayCtrl _x) ctrlEnable (_radars isNotEqualTo []); } forEach [AEGISM_TERMINAL_RADAR_AUTO_IDC, AEGISM_TERMINAL_RADAR_ON_IDC, AEGISM_TERMINAL_RADAR_OFF_IDC];

// --- Orders standing, and what became of the last -----------------------------
private _lines = [];
if (_error != "") then { _lines pushBack format ["<t color='%1'>%2</t>", AEGISM_TERMINAL_WARN_HEX, _error]; };
{
    _x params ["_vehicle", "_name", "_role", "_placed", "_by"];
    _lines pushBack format ["<t color='%1'>ORDER</t>  %2 on %3  <t color='%4'>(%5, by %6)</t>",
        AEGISM_TERMINAL_WARN_HEX, _vehicle call _fnShort, _name, AEGISM_TERMINAL_DIM_HEX, ["being placed", "standing"] select _placed, _by];
} forEach _orders;
// (Newest first.)
private _last = +_log;
reverse _last;
{
    _x params ["_age", "_text"];
    _lines pushBack format ["<t color='%1'>%2 s ago  %3</t>", AEGISM_TERMINAL_DIM_HEX, round _age, _text];
} forEach (_last select [0, 4]);
if (_lines isEqualTo []) then { _lines pushBack format ["<t color='%1'>No orders standing.</t>", AEGISM_TERMINAL_DIM_HEX]; };
(_display displayCtrl AEGISM_TERMINAL_ORDERS_IDC) ctrlSetStructuredText parseText format ["<t size='0.75'>%1</t>", _lines joinString "<br/>"];

// The buttons follow what's picked.
(_display displayCtrl AEGISM_TERMINAL_ENGAGE_IDC) ctrlEnable ((_state get "trackKey") != "" && {_pickedRow param [5, false]});
// (Cease Fire always: a surface strike isn't among the orders listed.)
(_display displayCtrl AEGISM_TERMINAL_CEASE_IDC) ctrlEnable true;
