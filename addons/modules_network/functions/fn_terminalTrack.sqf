/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalTrack

Description:
    Server, once a second: a terminal laptop's connection follows the item
    -- off the ground onto whoever picked it up, into a crate, back onto the
    ground where it's a terminal again. One fixed in place is put back.
    Full notes: docs/functions/modules_network.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_network_fnc_terminalTrack;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

// A connection whose laptop can't be found is looked for this long, then
// given up, s (my figure).
#define AEGISM_TERMINAL_LOOSE_FOR 10

if (!isServer) exitWith {};

// Laptops on the ground: [object, item class, its class, position (world),
// direction, up, record]. A record: [item class, connected to, access,
// manual interception, surface strike, fixed in place].
private _bodies = missionNamespace getVariable ["AEGISM_terminalBodies", []];
// Whatever else holds a record ("AEGISM_terminalCarried"): units, crates.
private _carriers = (missionNamespace getVariable ["AEGISM_terminalCarriers", []]) select { !isNull _x };
// Records nothing holds yet: [record, where it was, since, where it lay if
// it was on the ground].
private _loose = missionNamespace getVariable ["AEGISM_terminalLoose", []];
if (_bodies isEqualTo [] && {_carriers isEqualTo []} && {_loose isEqualTo []}) exitWith {};

// How many of an item something has: a unit on it, anything else in it.
private _fnCount = {
    params ["_object", "_item"];
    if (isNull _object) exitWith { 0 };
    private _list = [];
    if (_object isKindOf "CAManBase") then {
        // (The game's own laptop item is a magazine, config-wise: it's
        // among a unit's magazines, not its items.)
        _list = (items _object) + (magazines _object);
    } else {
        {
            private _part = _object call _x;
            if (!isNil "_part") then { _list append _part; };
        } forEach [{ itemCargo _this }, { magazineCargo _this }, { weaponCargo _this }, { backpackCargo _this }];
    };
    { (toLower _x) == _item } count _list
};
// How many of them it's known to hold a connection for: its records, and
// its own if it's a laptop on the ground.
private _fnHeld = {
    params ["_object", "_item"];
    ({ (_x select 0) == _item } count (_object getVariable ["AEGISM_terminalCarried", []]))
        + (parseNumber ((toLower (_object getVariable ["AEGISM_terminalItem", ""])) == _item))
};
// Makes a holder on the ground a terminal.
private _fnGround = {
    params ["_holder", "_record"];
    _record params ["_item", ["_link", []], ["_access", "status"], ["_engage", false], ["_surface", false], ["_fixed", false]];
    _holder setVariable ["AEGISM_terminalAccess", _access, true];
    _holder setVariable ["AEGISM_terminalEngage", _engage, true];
    _holder setVariable ["AEGISM_terminalSurface", _surface, true];
    _holder setVariable ["AEGISM_terminalFixed", _fixed, true];
    _holder setVariable ["AEGISM_terminalItem", _item, true];
    _holder setVariable ["AEGISM_terminalLink", _link select { !isNull _x }, true];
    [_holder, objNull] call aegism_network_fnc_terminalLink;
};
// Gives something a record to carry.
private _fnCarry = {
    params ["_holder", "_record"];
    private _records = +(_holder getVariable ["AEGISM_terminalCarried", []]);
    _records pushBack _record;
    _holder setVariable ["AEGISM_terminalCarried", _records, true];
    _carriers pushBackUnique _holder;
};

// --- Laptops on the ground: still there, or gone from where they lay ---------
private _kept = [];
{
    private _body = _x;
    _body params ["_object", "_item", "_class", "_position", "_direction", "_up", "_record"];
    if (isNull _object || {([_object, _item] call _fnCount) == 0}) then {
        _loose pushBack [_record, _position, CBA_missionTime, [_class, _position, _direction, _up]];
        if (!isNull _object) then {
            _object setVariable ["AEGISM_terminalItem", "", true];
            _object setVariable ["AEGISM_terminalLink", [], true];
            [_object, objNull] remoteExec ["aegism_network_fnc_terminalAction", 0, _object];
        };
    } else {
        // (What it may do can be changed in Zeus, and it can be moved: read
        // again each time, for when it's gone.)
        _body set [2, typeOf _object];
        _body set [3, getPosWorld _object];
        _body set [4, vectorDir _object];
        _body set [5, vectorUp _object];
        _body set [6, [_item, (_object getVariable ["AEGISM_terminalLink", []]) select { !isNull _x },
            _object getVariable ["AEGISM_terminalAccess", "status"], _object getVariable ["AEGISM_terminalEngage", false],
            _object getVariable ["AEGISM_terminalSurface", false], _object getVariable ["AEGISM_terminalFixed", false]]];
        _kept pushBack _body;
    };
} forEach _bodies;
// (Kept before anything is put down again below: aegism_network_fnc_
// terminalLink adds to it.)
missionNamespace setVariable ["AEGISM_terminalBodies", _kept];

// --- Units and crates: fewer of the item than connections held ---------------
{
    private _holder = _x;
    private _records = +(_holder getVariable ["AEGISM_terminalCarried", []]);
    private _classes = _records apply { _x select 0 };
    private _changed = false;
    {
        private _item = _x;
        // (Its own, if it's also a laptop on the ground, isn't one of these.)
        private _have = ([_holder, _item] call _fnCount) - (parseNumber ((toLower (_holder getVariable ["AEGISM_terminalItem", ""])) == _item));
        private _held = { (_x select 0) == _item } count _records;
        while { _held > _have } do {
            // The last one it took up is the one that went.
            private _index = -1;
            { if ((_x select 0) == _item) then { _index = _forEachIndex; }; } forEach _records;
            if (_index == -1) then {
                _held = _have;
            } else {
                _loose pushBack [_records deleteAt _index, getPosWorld _holder, CBA_missionTime, []];
                _held = _held - 1;
                _changed = true;
            };
        };
    } forEach (_classes arrayIntersect _classes);
    if (_changed) then { _holder setVariable ["AEGISM_terminalCarried", _records, true]; };
} forEach _carriers;
_carriers = _carriers select { (_x getVariable ["AEGISM_terminalCarried", []]) isNotEqualTo [] };

// --- Connections nothing holds: who, or what, has the laptop now --------------
private _left = [];
{
    _x params ["_record", "_position", "_since", "_home"];
    private _item = _record select 0;
    private _near = ASLToAGL _position;
    private _placed = false;

    // A unit, alive or not, with one more on it than it's known to carry:
    // the nearest.
    private _units = ((_near nearEntities ["CAManBase", AEGISM_TERMINAL_REACH]) + (allDeadMen select { (_x distance _near) <= AEGISM_TERMINAL_REACH }))
        select { ([_x, _item] call _fnCount) > ([_x, _item] call _fnHeld) };
    private _taker = objNull;
    { if (isNull _taker || {(_x distance _near) < (_taker distance _near)}) then { _taker = _x; }; } forEach _units;

    if (!isNull _taker) then {
        _placed = true;
        if ((_record param [5, false]) && {_home isNotEqualTo []}) then {
            // Fixed in place: off whoever took it, and back where it lay.
            _home params ["_class", "_at", "_direction", "_up"];
            private _isMagazine = isClass (configFile >> "CfgMagazines" >> _item);
            [_taker, _item] remoteExecCall [["removeItem", "removeMagazine"] select _isMagazine, _taker];
            private _holder = createVehicle [_class, [0, 0, 0], [], 0, "CAN_COLLIDE"];
            _holder setPosWorld _at;
            _holder setVectorDirAndUp [_direction, _up];
            if (([_holder, _item] call _fnCount) == 0) then {
                if (_isMagazine) then { _holder addMagazineCargoGlobal [_item, 1]; } else { _holder addItemCargoGlobal [_item, 1]; };
            };
            [_holder, _record] call _fnGround;
            ["AEGIS-M: this terminal is fixed in place."] remoteExecCall ["hintSilent", _taker];
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL: %1 took up a terminal that is fixed in place -- taken off it and put back as %2.", name _taker, _holder];
        } else {
            [_taker, _record] call _fnCarry;
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL: %1 has a terminal (%2) on it, connected to %3 -- %4.", name _taker, _item, _record select 1,
                ["it keeps its connection there", "it's on its action menu while it carries it"] select (alive _taker)];
        };
    };

    // On the ground, in a crate or in a vehicle: the nearest thing with one
    // more in it than it's known to hold. A plain holder on the ground is a
    // terminal again where it lies; anything else keeps it until it's taken
    // out.
    if (!_placed) then {
        private _things = (nearestObjects [_near, ["WeaponHolder", "WeaponHolderSimulated", "ReammoBox_F", "LandVehicle", "Air", "Ship"], AEGISM_TERMINAL_REACH])
            select { ([_x, _item] call _fnCount) > ([_x, _item] call _fnHeld) };
        private _thing = _things param [0, objNull];
        if (!isNull _thing) then {
            _placed = true;
            if ((_thing isKindOf "WeaponHolder" || {_thing isKindOf "WeaponHolderSimulated"}) && {(_thing getVariable ["AEGISM_terminalItem", ""]) == ""}) then {
                [_thing, _record] call _fnGround;
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL: a terminal (%1) lies at grid %2 (%3), connected to %4 -- a terminal again there.", _item, mapGridPosition _thing, _thing, _record select 1];
            } else {
                [_thing, _record] call _fnCarry;
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL: a terminal (%1) is in %2 (%3) -- it keeps its connection there.", _item, _thing, typeOf _thing];
            };
        };
    };

    if (!_placed) then {
        if (CBA_missionTime - _since > AEGISM_TERMINAL_LOOSE_FOR) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " TERMINAL: a terminal (%1) left where it was near grid %2 and wasn't found on anyone or in anything within %3m for %4s -- its connection to %5 is dropped.",
                _item, mapGridPosition _near, AEGISM_TERMINAL_REACH, AEGISM_TERMINAL_LOOSE_FOR, _record select 1];
        } else {
            _left pushBack _x;
        };
    };
} forEach _loose;

missionNamespace setVariable ["AEGISM_terminalCarriers", _carriers];
missionNamespace setVariable ["AEGISM_terminalLoose", _left];
