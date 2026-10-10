/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalPicture

Description:
    Answers a terminal's Interception page, on the server: the tracks its
    Site holds or sees, the weapons and radars of the Site or vehicle
    picked (with whether each weapon has a shot at the track picked), the
    Site's missiles in flight, and the orders standing.
    Full notes: docs/functions/modules_network.md

Parameters:
    _terminal - the terminal <OBJECT>
    _anchor - the Site or vehicle its action was made for <OBJECT>
    _node - the Site or vehicle picked on its screen <OBJECT>
    _selected - the contact key of the track picked there, "" for none --
        or Surface Strike's point, ASL <STRING or ARRAY, default "">

Returns:
    Nothing

Examples:
    [_laptop, _site, _site, ""] remoteExecCall ["aegism_network_fnc_terminalPicture", 2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

params [["_terminal", objNull], ["_anchor", objNull], ["_node", objNull], ["_selected", ""]];

if (!isServer) exitWith {};
if (isNull _terminal || {isNull _node} || {!(([_terminal, _node] call aegism_network_fnc_terminalData) select 1)}) exitWith {};

private _owner = remoteExecutedOwner;
private _local = !isMultiplayer || {_owner in [0, clientOwner]};
// [node, what's wrong ("" = nothing), automation on, Site name, tracks,
// weapons, orders, last lines, missiles in flight, radars]
private _fnReply = {
    if (_local) then { [_this] call aegism_network_fnc_terminalIntercept; } else { [_this] remoteExecCall ["aegism_network_fnc_terminalIntercept", _owner]; };
};

private _isSite = _node isKindOf "AEGISM_Module_Site";
private _site = if (_isSite) then { _node } else { _node getVariable ["AEGISM_network", objNull] };
if (isNull _site) exitWith {
    [_node, "Manual interception works through a Site: this vehicle isn't in one.", true, "", [], [], [], [], [], []] call _fnReply;
};

// The Site that coordinates it holds the picture and the orders.
private _lead = _site getVariable ["AEGISM_linkLead", _site];
private _pool = _lead getVariable ["AEGISM_pooledContacts", createHashMap];
private _claims = _lead getVariable ["AEGISM_claims", createHashMap];
private _groupMembers = (_lead getVariable ["AEGISM_groupMembers", _lead getVariable ["AEGISM_networkMembers", []]]) select { !isNull _x && {alive _x} };
// The Shared Site Coordinator of linked Sites stands for all of them (as
// its terminal's reach does, aegism_network_fnc_terminalScope): every
// vehicle of the group. Another Site: its own. A vehicle: itself.
private _linked = (_site getVariable ["AEGISM_linkSites", [_site]]) select { !isNull _x };
private _coordinates = _isSite && {_lead == _site} && {count _linked > 1} && {_site getVariable ["sharedCoordinator", false]};
private _vehicles = switch (true) do {
    case _coordinates: { _groupMembers };
    case _isSite: { (_site getVariable ["AEGISM_networkMembers", []]) select { !isNull _x && {alive _x} } };
    default { [_node] select { alive _x } };
};

private _fnName = {
    private _name = getText (configOf _this >> "displayName");
    if (_name == "") then { _name = typeOf _this; };
    _name
};

// --- Tracks ---------------------------------------------------------------------
// [key, class, kind, position ASL, velocity, name, s to impact (1e10 = none),
// what's on it: [vehicle, role, status, ordered, missiles fired] each]. Kind:
// "threat" (the Site's own contact), "ordered" (in its pool for an order
// alone), and of what its sensors see besides: "hostile" (of a class it
// doesn't engage), "friendly", "neutral".
private _tracks = [];
private _objects = createHashMap;
{
    private _object = _y getOrDefault ["object", objNull];
    if (!isNull _object && {alive _object}) then {
        _objects set [_x, _object];
        (_y getOrDefault ["tti", [1e10, CBA_missionTime]]) params ["_tti", "_ttiAt"];
        if (_tti < 1e9) then { _tti = (_tti - (CBA_missionTime - _ttiAt)) max 0; };
        private _on = (_claims getOrDefault [_x, []]) apply {
            [_x get "system", _x get "role", _x getOrDefault ["status", ""], _x getOrDefault ["manual", false], _x get "roundsFired"]
        };
        _tracks pushBack [_x, _y get "class", ["threat", "ordered"] select (_y getOrDefault ["manualOnly", false]), getPosASL _object, velocity _object, _object call _fnName, _tti, _on];
    };
} forEach _pool;

private _ownSide = if (_groupMembers isEqualTo []) then { sideUnknown } else { side (_groupMembers select 0) };
{
    (_x getVariable ["AEGISM_otherTracks", [-1e9, []]]) params ["_readAt", "_list"];
    if (CBA_missionTime - _readAt <= AEGISM_TERMINAL_TRACK_FRESH) then {
        {
            _x params ["_object", "_class"];
            if (!isNull _object && {alive _object}) then {
                private _key = [_object] call aegism_fnc_contactKey;
                if !(_key in _objects) then {
                    _objects set [_key, _object];
                    private _side = side _object;
                    private _kind = switch (true) do {
                        case ([_ownSide, _side] call aegism_detect_fnc_isHostile): { "hostile" };
                        case (_side in [west, east, independent]): { "friendly" };
                        default { "neutral" };
                    };
                    _tracks pushBack [_key, _class, _kind, getPosASL _object, velocity _object, _object call _fnName, 1e10, []];
                };
            };
        } forEach _list;
    };
} forEach _groupMembers;

// --- Weapons ---------------------------------------------------------------------
// [vehicle, role, turret, weapon, magazine, rounds, reach m (0 = none known),
// a track is picked, it has a shot at it, why not]
// (Against the track picked -- or the strike point, on a terminal that
// has Surface Strike: aegism_intercept_fnc_surfaceShot.)
private _strikePoint = if (_selected isEqualType [] && {count _selected == 3} && {([_terminal, _node] call aegism_network_fnc_terminalData) select 2}) then { _selected } else { [] };
private _target = if (_selected isEqualType "") then { _objects getOrDefault [_selected, objNull] } else { objNull };
private _weapons = [];
{
    private _vehicle = _x;
    private _data = _vehicle getVariable ["AEGISM_system", createHashMap];
    private _settings = _vehicle getVariable "AEGISM_resolvedEngagementSettings";
    if (isNil "_settings") then { _settings = [_vehicle] call aegism_system_fnc_resolveEngagementSettings; };
    {
        private _role = _x;
        {
            _x params ["_turretPath", "_weaponClass", "_magClass", "", "", ["_modeMax", 0]];
            private _rounds = _vehicle magazineTurretAmmo [_magClass, _turretPath];
            private _reach = if (_role == "launcher") then { ([_settings, _x, _role] call aegism_intercept_fnc_envelopeBounds) param [1, 0] } else { _modeMax };
            private _can = false;
            private _why = "";
            if (_strikePoint isNotEqualTo []) then {
                private _shot = [_vehicle, _role, _x, _strikePoint] call aegism_intercept_fnc_surfaceShot;
                _can = _shot select 0;
                _why = _shot select 1;
            };
            if (!isNull _target) then {
                if (_rounds <= 0) then {
                    _why = "nothing left to fire";
                } else {
                    private _engage = [_vehicle, _role, _x, _target, _settings] call aegism_intercept_fnc_canEngage;
                    _can = _engage select 0;
                    _why = _engage param [1, ""];
                };
            };
            _weapons pushBack [_vehicle, _role, _turretPath, _weaponClass, _magClass, _rounds, _reach max 0, !isNull _target || {_strikePoint isNotEqualTo []}, _can, _why];
        } forEach (_data getOrDefault [["launcherWeapons", "ciwsWeapons"] select (_role == "ciws"), []]);
    } forEach ["launcher", "ciws"];
} forEach _vehicles;

// --- The Site's own missiles in flight -------------------------------------------
// [position ASL, velocity, fired on an order] each: every interceptor of
// every claim that's still flying. (A missile is the server's own object,
// not one a client could be handed: where it is and how it moves is sent.)
private _missiles = [];
{
    {
        private _manual = _x getOrDefault ["manual", false];
        {
            if (!isNull _x && {alive _x}) then { _missiles pushBack [getPosASL _x, velocity _x, _manual]; };
        } forEach (_x getOrDefault ["interceptors", []]);
    } forEach _y;
} forEach _claims;

// (And a surface strike's: aegism_intercept_fnc_strikeMissile.)
{
    if (!isNull _x && {alive _x}) then { _missiles pushBack [getPosASL _x, velocity _x, true]; };
} forEach (missionNamespace getVariable ["AEGISM_strikeMissiles", []]);

// --- Radars: of the Site or vehicle picked ------------------------------------
// [vehicle, emitting, ordered ("on", "off", "" = its own emission control),
// its state, and why (aegism_fnc_emconText)]
private _radars = [];
{
    if ((_x getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasRadar", false]) then {
        ([_x] call aegism_fnc_emconText) params ["_label", "_detail"];
        _radars pushBack [_x, isVehicleRadarOn _x, _x getVariable ["AEGISM_radarOrder", ""], _label, _detail];
    };
} forEach _vehicles;

// --- Orders, and what became of the last ones --------------------------------
private _orders = (_lead getVariable ["AEGISM_manualOrders", []]) apply { [_x get "system", _x get "name", _x get "role", _x getOrDefault ["placed", false], _x get "by"] };
private _log = (_lead getVariable ["AEGISM_manualLog", []]) apply { [CBA_missionTime - (_x select 0), _x select 1] };

// (Automation: of what's picked -- every Site the coordinator stands for,
// a Site's own, or a vehicle's own and its Site's.)
private _automation = if (_coordinates) then {
    (_linked findIf { !(_x getVariable ["AEGISM_automation", true]) }) == -1
} else {
    (_node getVariable ["AEGISM_automation", true]) && {_site getVariable ["AEGISM_automation", true]}
};
private _siteName = [_site] call aegism_fnc_siteName;
if (_coordinates) then { _siteName = format ["%1 and the %2 Site(s) linked to it", _siteName, (count _linked) - 1]; };
[_node, "", _automation, _siteName, _tracks, _weapons, _orders, _log, _missiles, _radars] call _fnReply;
