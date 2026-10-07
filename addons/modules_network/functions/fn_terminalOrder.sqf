/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalOrder

Description:
    Takes an order from a terminal's Interception page, on the server: a
    weapon onto a track, cease fire, automation switched on or off, or a
    radar ordered on or silent. Checks the terminal's access, the player's
    distance and its reach.
    Full notes: docs/functions/modules_network.md

Parameters:
    _terminal - the terminal <OBJECT>
    _anchor - the Site or vehicle its action was made for <OBJECT>
    _node - the Site or vehicle picked on its screen <OBJECT>
    _command - "engage", "strike", "cease", "automation" or "radar" <STRING>
    _args - "engage": [contact key, vehicle or the vehicles of one row of
        launchers (the best placed fires), turret path, weapon class];
        "strike": [point ASL, vehicle or vehicles, turret path, weapon
        class] (a terminal with Surface Strike only);
        "cease": [contact key, "" for every order]; "automation": [on];
        "radar": [radar vehicles ([] for every radar picked), "on", "off"
        or "" for its own emission control] <ARRAY>

Returns:
    Nothing

Examples:
    [_laptop, _site, _site, "automation", [false]] remoteExecCall ["aegism_network_fnc_terminalOrder", 2];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

// Lines kept for the page (as aegism_intercept_fnc_assignEngagements keeps them).
#define AEGISM_MANUAL_LOG_LINES 8

params [["_terminal", objNull], ["_anchor", objNull], ["_node", objNull], ["_command", ""], ["_args", []]];

if (!isServer) exitWith {};

private _owner = remoteExecutedOwner;
private _local = !isMultiplayer || {_owner in [0, clientOwner]};
// A line for the screen it came from.
private _fnAnswer = {
    params ["_note", ["_good", true]];
    _note = format ["<t size='0.85' color='%1'>%2</t>", [AEGISM_TERMINAL_WARN_HEX, AEGISM_TERMINAL_ACCENT_HEX] select _good, _note];
    if (_local) then { ["", _note] call aegism_network_fnc_terminalShow; } else { ["", _note] remoteExecCall ["aegism_network_fnc_terminalShow", _owner]; };
};
private _user = if (_local) then { player } else { (allPlayers select { owner _x == _owner }) param [0, objNull] };
private _userName = if (isNull _user) then { "an unknown player" } else { name _user };

private _isSite = !isNull _node && {_node isKindOf "AEGISM_Module_Site"};
private _site = if (_isSite) then { _node } else { _node getVariable ["AEGISM_network", objNull] };
private _refusal = switch (true) do {
    case (isNull _terminal || {isNull _node}): { "the terminal or what it controls is gone" };
    case !(_terminal getVariable ["AEGISM_terminalEngage", false]): { "this terminal has no manual interception" };
    case (!isNull _user && {(_user distance _terminal) > AEGISM_TERMINAL_REACH}): { "you're not at the terminal" };
    case ((([_terminal, _anchor] call aegism_network_fnc_terminalScope) findIf { (_x select 0) == _node }) == -1): { "that isn't within this terminal's reach" };
    case (isNull _site): { "manual interception works through a Site, and this vehicle isn't in one" };
    default { "" };
};
private _fnRefuse = {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MANUAL: %1 (%2) from terminal %3 by %4 refused -- %5.", _command, _node, _terminal, _userName, _this];
    [format ["Refused: %1.", _this], false] call _fnAnswer;
};
if (_refusal != "") exitWith { _refusal call _fnRefuse; };

// The Site that coordinates it holds the picture and the orders.
private _lead = _site getVariable ["AEGISM_linkLead", _site];
// The Shared Site Coordinator of linked Sites stands for all of them (as
// its terminal's reach does, aegism_network_fnc_terminalScope): every
// vehicle of the group. Another Site: its own. A vehicle: itself.
private _linked = (_site getVariable ["AEGISM_linkSites", [_site]]) select { !isNull _x };
private _coordinates = _isSite && {_lead == _site} && {count _linked > 1} && {_site getVariable ["sharedCoordinator", false]};
private _vehicles = switch (true) do {
    case _coordinates: { (_lead getVariable ["AEGISM_groupMembers", _lead getVariable ["AEGISM_networkMembers", []]]) select { !isNull _x && {alive _x} } };
    case _isSite: { (_site getVariable ["AEGISM_networkMembers", []]) select { !isNull _x && {alive _x} } };
    default { [_node] select { alive _x } };
};
// A line for every terminal's page, and the RPT.
private _fnNote = {
    private _log = _lead getVariable ["AEGISM_manualLog", []];
    _log pushBack [CBA_missionTime, _this];
    if (count _log > AEGISM_MANUAL_LOG_LINES) then { _log deleteAt 0; };
    _lead setVariable ["AEGISM_manualLog", _log, false];
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MANUAL: %1 (terminal %2)", _this, _terminal];
};

switch (_command) do {
    case "automation": {
        // Of what's picked, and of everything under it: the coordinator's
        // switch is every linked Site's and their vehicles', a Site's is its
        // own vehicles' too, a vehicle's is that vehicle's alone. (The
        // coordinator's used to be its own Site's vehicles only: switched
        // off, the launchers of the Sites linked to it went on firing on
        // their own, 2026-10-07.)
        _args params [["_on", true]];
        { _x setVariable ["AEGISM_automation", _on, false]; } forEach ([[_node], _linked] select _coordinates);
        if (_isSite) then { { _x setVariable ["AEGISM_automation", _on, false]; } forEach _vehicles; };
        _lead setVariable ["AEGISM_assignNow", true, false];
        private _what = switch (true) do {
            case _coordinates: { format ["%1 and the %2 Site(s) linked to it", [_site] call aegism_fnc_siteName, (count _linked) - 1] };
            case _isSite: { [_site] call aegism_fnc_siteName };
            default { str _node };
        };
        (format ["%1 switched the automation of %2 %3.", _userName, _what, ["OFF: its weapons fire on orders only", "ON"] select _on]) call _fnNote;
        [switch (true) do {
            case (!_on): { format ["Automation off for %1: its weapons fire on orders only.", _what] };
            case (!_isSite && {!(_site getVariable ["AEGISM_automation", true])}): { "Automation on for this vehicle -- but its Site's is off, so it still fires on orders only." };
            default { format ["Automation on for %1.", _what] };
        }] call _fnAnswer;
    };

    case "engage": {
        _args params [["_key", ""], ["_candidates", objNull], ["_turretPath", []], ["_weaponClass", ""]];
        if !(_candidates isEqualType []) then { _candidates = [_candidates]; };

        // The track: one the Site holds, or one its sensors see besides.
        private _target = ((_lead getVariable ["AEGISM_pooledContacts", createHashMap]) getOrDefault [_key, createHashMap]) getOrDefault ["object", objNull];
        if (isNull _target) then {
            {
                (_x getVariable ["AEGISM_otherTracks", [-1e9, []]]) params ["_readAt", "_list"];
                if (isNull _target && {CBA_missionTime - _readAt <= AEGISM_TERMINAL_TRACK_FRESH}) then {
                    private _index = _list findIf { !isNull (_x select 0) && {([_x select 0] call aegism_fnc_contactKey) == _key} };
                    if (_index != -1) then { _target = (_list select _index) select 0; };
                };
            } forEach ((_lead getVariable ["AEGISM_groupMembers", _lead getVariable ["AEGISM_networkMembers", []]]) select { !isNull _x && {alive _x} });
        };
        if (isNull _target || {!alive _target}) exitWith { "the Site no longer holds that track" call _fnRefuse; };

        // Each vehicle it may be (one row of the page stands for every
        // launcher of a type standing together): why it can't, or how well
        // placed it is -- [already on this track, claims it's working, rounds
        // short of the fullest]. The best placed takes the order, so another
        // missile at a track comes from the next launcher of the battery
        // rather than waiting on the first's reload.
        private _claims = _lead getVariable ["AEGISM_claims", createHashMap];
        private _onTrack = (_claims getOrDefault [[_target] call aegism_fnc_contactKey, []]) apply { _x get "system" };
        private _why = "that weapon isn't within this terminal's reach";
        private _able = [];
        {
            private _vehicle = _x;
            if (!isNull _vehicle && {_vehicle in _vehicles}) then {
                private _data = _vehicle getVariable ["AEGISM_system", createHashMap];
                private _fnWeapon = { (_data getOrDefault [_this, []]) select { (_x select 0) isEqualTo _turretPath && {(_x select 1) == _weaponClass} } };
                private _role = "launcher";
                private _found = "launcherWeapons" call _fnWeapon;
                if (_found isEqualTo []) then {
                    _role = "ciws";
                    _found = "ciwsWeapons" call _fnWeapon;
                };
                private _weaponInfo = _found param [0, []];
                private _rounds = if (_weaponInfo isEqualTo []) then { 0 } else { _vehicle magazineTurretAmmo [_weaponInfo select 2, _turretPath] };
                _why = switch (true) do {
                    case (_weaponInfo isEqualTo []): { "that isn't a weapon AEGIS-M runs" };
                    case (_rounds <= 0): { "it has nothing left to fire" };
                    default {
                        private _settings = _vehicle getVariable "AEGISM_resolvedEngagementSettings";
                        if (isNil "_settings") then { _settings = [_vehicle] call aegism_system_fnc_resolveEngagementSettings; };
                        private _engage = [_vehicle, _role, _weaponInfo, _target, _settings] call aegism_intercept_fnc_canEngage;
                        ["", format ["it has no shot at it (%1)", _engage param [1, "no solution"]]] select !(_engage select 0)
                    };
                };
                if (_why == "") then {
                    private _working = { (_x getOrDefault ["status", ""]) != "inFlight" } count (((_vehicle getVariable ["AEGISM_assigned", createHashMap]) getOrDefault [_role, []]));
                    _able pushBack [parseNumber (_vehicle in _onTrack), _working, -_rounds, count _able, _vehicle, _role, _weaponInfo];
                };
            };
        } forEach _candidates;
        if (_able isEqualTo []) exitWith { _why call _fnRefuse; };
        _able sort true;
        (_able select 0) params ["", "", "", "", "_vehicle", "_role", "_weaponInfo"];

        private _name = getText (configOf _target >> "displayName");
        if (_name == "") then { _name = typeOf _target; };
        private _orders = _lead getVariable ["AEGISM_manualOrders", []];
        _orders pushBack createHashMapFromArray [
            ["target", _target], ["key", [_target] call aegism_fnc_contactKey], ["name", _name], ["system", _vehicle], ["weaponInfo", _weaponInfo],
            ["role", _role], ["by", _userName], ["at", CBA_missionTime], ["placed", false]
        ];
        _lead setVariable ["AEGISM_manualOrders", _orders, false];
        _lead setVariable ["AEGISM_assignNow", true, false];
        (format ["%1 ordered %2 (%3) onto %4.", _userName, _vehicle, _weaponClass, _name]) call _fnNote;
        [format ["Ordered: %1 onto %2.", getText (configOf _vehicle >> "displayName"), _name]] call _fnAnswer;
    };

    // A point on the ground (aegism_intercept_fnc_surfaceStrike): one missile
    // lofted onto it, or one burst of a gun. Of a row of launchers, one
    // that has the shot and isn't on a strike already; then the least busy,
    // then the fullest.
    case "strike": {
        _args params [["_point", []], ["_candidates", objNull], ["_turretPath", []], ["_weaponClass", ""]];
        if !(_candidates isEqualType []) then { _candidates = [_candidates]; };
        if !(_terminal getVariable ["AEGISM_terminalSurface", false]) exitWith { "this terminal has no surface strike" call _fnRefuse; };
        if !(_point isEqualType [] && {count _point == 3}) exitWith { "there's no strike point" call _fnRefuse; };

        private _why = "that weapon isn't within this terminal's reach";
        private _able = [];
        {
            private _vehicle = _x;
            if (!isNull _vehicle && {_vehicle in _vehicles}) then {
                private _data = _vehicle getVariable ["AEGISM_system", createHashMap];
                private _fnWeapon = { (_data getOrDefault [_this, []]) select { (_x select 0) isEqualTo _turretPath && {(_x select 1) == _weaponClass} } };
                private _role = "launcher";
                private _found = "launcherWeapons" call _fnWeapon;
                if (_found isEqualTo []) then {
                    _role = "ciws";
                    _found = "ciwsWeapons" call _fnWeapon;
                };
                private _weaponInfo = _found param [0, []];
                _why = switch (true) do {
                    case (_weaponInfo isEqualTo []): { "that isn't a weapon AEGIS-M runs" };
                    case (CBA_missionTime < (([_vehicle, _turretPath] call aegism_intercept_fnc_turretState) getOrDefault ["strikeUntil", -1])): { "it's on another strike" };
                    default {
                        private _shot = [_vehicle, _role, _weaponInfo, _point] call aegism_intercept_fnc_surfaceShot;
                        ["", format ["it has no shot at it (%1)", _shot select 1]] select !(_shot select 0)
                    };
                };
                if (_why == "") then {
                    private _working = { (_x getOrDefault ["status", ""]) != "inFlight" } count ((_vehicle getVariable ["AEGISM_assigned", createHashMap]) getOrDefault [_role, []]);
                    _able pushBack [_working, -(_vehicle magazineTurretAmmo [_weaponInfo select 2, _turretPath]), count _able, _vehicle, _role, _weaponInfo];
                };
            };
        } forEach _candidates;
        if (_able isEqualTo []) exitWith { _why call _fnRefuse; };
        _able sort true;
        (_able select 0) params ["", "", "", "_vehicle", "_role", "_weaponInfo"];

        ([_vehicle, _role, _weaponInfo, _point, _lead] call aegism_intercept_fnc_surfaceStrike) params ["_started", "_reason"];
        if (!_started) exitWith { _reason call _fnRefuse; };
        (format ["%1 ordered %2 (%3) to strike grid %4.", _userName, _vehicle, _weaponClass, mapGridPosition _point]) call _fnNote;
        [format ["Strike ordered: %1 onto grid %2.", getText (configOf _vehicle >> "displayName"), mapGridPosition _point]] call _fnAnswer;
    };

    case "cease": {
        _args params [["_key", ""]];
        // (A surface strike still coming onto its point, or a gun's burst
        // at one: called off. aegism_intercept_fnc_surfaceStrike.)
        private _calledOff = 0;
        if (_key in ["", "@strike"]) then {
            {
                {
                    if (CBA_missionTime < (_y getOrDefault ["strikeUntil", -1])) then {
                        _y set ["strikeAbort", CBA_missionTime];
                        _calledOff = _calledOff + 1;
                    };
                } forEach (_x getVariable ["AEGISM_turrets", createHashMap]);
            } forEach _vehicles;
        };
        private _claims = _lead getVariable ["AEGISM_claims", createHashMap];
        private _kept = [];
        private _ended = 0;
        {
            private _order = _x;
            if ((_order get "system") in _vehicles && {_key == "" || {(_order get "key") == _key}}) then {
                _ended = _ended + 1;
                // Its claim: gone if nothing has been fired for it (or it's a
                // gun's); with a missile in flight, no more are fired.
                private _records = _claims getOrDefault [_order get "key", []];
                private _index = _records findIf {
                    (_x get "system") isEqualTo (_order get "system") && {(_x get "role") == (_order get "role")} && {((_x get "weaponInfo") select 0) isEqualTo ((_order get "weaponInfo") select 0)}
                };
                if (_index != -1) then {
                    private _record = _records select _index;
                    if ((_order get "role") == "ciws" || {(_record get "roundsFired") == 0}) then {
                        // (Until the coordinator's next run takes it off the
                        // vehicle: nothing more to fire.)
                        _record set ["salvo", 0];
                        _records deleteAt _index;
                        if (_records isEqualTo []) then { _claims deleteAt (_order get "key"); };
                    } else {
                        _record set ["salvo", _record get "roundsFired"];
                    };
                };
            } else {
                _kept pushBack _order;
            };
        } forEach (_lead getVariable ["AEGISM_manualOrders", []]);
        _lead setVariable ["AEGISM_manualOrders", _kept, false];
        _lead setVariable ["AEGISM_assignNow", true, false];
        if (_ended + _calledOff > 0) then { (format ["%1 ended %2 order(s) and called off %3 strike(s): cease fire.", _userName, _ended, _calledOff]) call _fnNote; };
        [format ["Cease fire: %1 order(s) ended, %2 strike(s) called off.", _ended, _calledOff]] call _fnAnswer;
    };

    // A radar ordered on, silent, or back to its own emission control
    // (aegism_system_fnc_emconUpdate reads "AEGISM_radarOrder", and is run
    // at once so it shows).
    case "radar": {
        _args params [["_radars", []], ["_order", ""]];
        if !(_order in ["on", "off", ""]) exitWith { "it isn't a radar order this version knows" call _fnRefuse; };
        private _mine = _vehicles select { (_x getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasRadar", false] };
        if (_radars isNotEqualTo []) then { _mine = _mine select { _x in _radars }; };
        if (_mine isEqualTo []) exitWith { "there's no radar there within this terminal's reach" call _fnRefuse; };
        {
            _x setVariable ["AEGISM_radarOrder", _order, false];
            [_x] call aegism_system_fnc_emconUpdate;
        } forEach _mine;
        private _text = switch (_order) do { case "on": { "ON" }; case "off": { "SILENT" }; default { "back to their own emission control" }; };
        (format ["%1 ordered %2 radar(s) %3: %4.", _userName, count _mine, _text, _mine]) call _fnNote;
        [format ["%1 radar(s) %2.", count _mine, _text]] call _fnAnswer;
    };

    default { "it isn't an order this version knows" call _fnRefuse; };
};
