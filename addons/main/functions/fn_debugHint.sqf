/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugHint

Description:
    Live status board in the hint box, refreshed once a second while the
    CBA setting "AEGIS-M > Debug > Site Status Hint" is on:

        - the Site nearest the camera, in detail: every member vehicle with
          its roles ([R]adar [L]auncher [C]IWS), a colour-coded status, its
          current target and ammo
        - every other Site as a one-line summary
        - standalone (unsynced) Systems, one line each
        - not active: vehicles AEGIS-M found capable but hasn't activated
          (deferred until synced to a Site), with why -- e.g. a launcher
          with no radar of its own placed without a Site
        - last, the nearest Site's tracked contacts and the weapons on
          each (the longest section, so it's the one the hint box cuts)

    Each engagement shows in its own state's colour (aegism_fnc_statusStyle
    -- the state the engagement loop records on it every tick): blue QUEUED
    behind another on its launcher, amber REACTING/SLEWING, orange
    RELOADING, teal RANGE HOLD, red FIRING, gold IN FLIGHT, purple NO LOS /
    NO SOLUTION, grey CREW FAILED / FIRE HELD / NO AMMO. A vehicle with
    nothing assigned: green READY, yellow TRACKING (radar with contacts),
    grey NO AMMO, dark grey DESTROYED.

    Reads the same server-side variables the engagement pipeline runs on,
    so it only has data where that pipeline runs: singleplayer, Eden
    Preview, or the host of a hosted game (not a client of a dedicated
    server).

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_fnc_debugHint;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define COL_READY "#66BB6A"
#define COL_TRACK "#FFEE58"
#define COL_ENGAGE "#FFA726"
#define COL_EMPTY "#9E9E9E"
#define COL_DEAD "#616161"
#define COL_DIM "#90A4AE"
#define COL_HEAD "#4FC3F7"
#define AEGISM_HINT_MAX_CONTACTS 6

if !("aegism_main_debugHint" call CBA_settings_fnc_get) exitWith {
    if (missionNamespace getVariable ["AEGISM_debugHintShown", false]) then {
        missionNamespace setVariable ["AEGISM_debugHintShown", false];
        hintSilent "";
    };
};
missionNamespace setVariable ["AEGISM_debugHintShown", true];

private _fnShortName = {
    params ["_object"];
    if (isNull _object) exitWith { "-" };
    private _name = getText (configOf _object >> "displayName");
    if (_name == "") then { _name = typeOf _object; };
    _name
};

private _fnRange = {
    params ["_metres"];
    if (_metres >= 1000) then { format ["%1km", (round (_metres / 100)) / 10] } else { format ["%1m", round _metres] }
};

private _fnColour = {
    params ["_colour", "_text"];
    format ["<t color='%1'>%2</t>", _colour, _text]
};

// [status text, colour] for one System, from its engagements' own states
// (the "status" the engagement loop records, aegism_fnc_statusStyle): each
// engagement it's working, in its state's colour, and how many wait queued
// behind them; the System takes the colour of the most urgent.
private _fnSystemStatus = {
    params ["_system", "_records"];
    if (!alive _system) exitWith { ["DESTROYED", COL_DEAD] };

    private _systemData = _system getVariable ["AEGISM_system", createHashMap];
    private _lines = [];
    private _queued = 0;
    private _urgent = [-1, COL_ENGAGE];
    {
        private _record = _x;
        ([_record getOrDefault ["status", ""]] call aegism_fnc_statusStyle) params ["_label", "", "_hex", "_urgency"];
        if ((_record getOrDefault ["status", ""]) == "queued") then {
            _queued = _queued + 1;
        } else {
            private _target = _record getOrDefault ["target", objNull];
            _lines pushBack ([_hex, format ["%1: %2 %3 %4", ["L", "C"] select ((_record get "role") == "ciws"), toUpper _label, [_target] call _fnShortName, [_system distance _target] call _fnRange]] call _fnColour);
        };
        if (_urgency > (_urgent select 0)) then { _urgent = [_urgency, _hex]; };
    } forEach _records;

    if (_records isNotEqualTo []) exitWith {
        if (_queued > 0) then {
            _lines pushBack ([(["queued"] call aegism_fnc_statusStyle) select 2, format ["+%1 queued", _queued]] call _fnColour);
        };
        [_lines joinString " | ", _urgent select 1]
    };

    private _weapons = (_systemData getOrDefault ["launcherWeapons", []]) + (_systemData getOrDefault ["ciwsWeapons", []]);
    private _anyAmmo = (_weapons findIf { _x params ["_turretPath", "", "_magClass"]; (_system magazineTurretAmmo [_magClass, _turretPath]) > 0 }) != -1;
    if (_weapons isNotEqualTo [] && {!_anyAmmo}) exitWith { ["NO AMMO", COL_EMPTY] };

    // A networked radar feeds its Site's pool (it keeps no munitions of its own).
    private _network = _system getVariable ["AEGISM_network", objNull];
    private _contacts = count (([_network, _system] select (isNull _network)) getVariable ["AEGISM_pooledContacts", createHashMap]);
    if ((_systemData getOrDefault ["hasRadar", false]) && {_contacts > 0}) exitWith { [format ["TRACKING %1 contact(s)", _contacts], COL_TRACK] };

    ["READY", COL_READY]
};

// "[R L C]" role tags and "L 3 | C 540" ammo for one System.
private _fnRolesAndAmmo = {
    params ["_system"];
    private _systemData = _system getVariable ["AEGISM_system", createHashMap];
    private _tags = [];
    if (_systemData getOrDefault ["hasRadar", false]) then { _tags pushBack "R"; };
    private _ammo = [];
    {
        _x params ["_key", "_tag"];
        private _weapons = _systemData getOrDefault [_key, []];
        if (_weapons isNotEqualTo []) then {
            _tags pushBack _tag;
            private _rounds = 0;
            { _x params ["_turretPath", "", "_magClass"]; _rounds = _rounds + (_system magazineTurretAmmo [_magClass, _turretPath]); } forEach _weapons;
            _ammo pushBack format ["%1 %2", _tag, _rounds];
        };
    } forEach [["launcherWeapons", "L"], ["ciwsWeapons", "C"]];
    [format ["[%1]", _tags joinString " "], _ammo joinString " | "]
};

private _sites = (missionNamespace getVariable ["AEGISM_allPoolOwners", []]) select { !isNull _x && {!isNil {_x getVariable "AEGISM_networkMembers"}} };
private _allSystems = (missionNamespace getVariable ["AEGISM_allSystems", []]) select { !isNull _x && {alive _x} };
missionNamespace setVariable ["AEGISM_allSystems", _allSystems, false];
private _standalone = _allSystems select { isNull (_x getVariable ["AEGISM_network", objNull]) };
private _camera = positionCameraToWorld [0, 0, 0];

private _fnSiteName = {
    params ["_site", "_index"];
    private _name = vehicleVarName _site;
    if (_name == "") then { _name = format ["Site %1", _index + 1]; };
    format ["%1 (grid %2)", _name, mapGridPosition _site]
};

// Found capable but not activated: deferred until synced to a Site
// (aegism_system_fnc_moduleInit's adoption policy).
private _deferred = (missionNamespace getVariable ["AEGISM_deferredSystems", []]) select { !isNull _x && {alive _x} && {_x getVariable ["AEGISM_systemDeferred", false]} };

private _lines = [format ["<t size='1.2' font='PuristaBold' color='%1'>AEGIS-M</t><br/>", COL_HEAD]];
// The nearest Site's contacts go last: the vehicle-level sections come
// first, so they aren't the ones pushed off the bottom of the hint box.
private _contactLines = [];

if (_sites isEqualTo [] && {_standalone isEqualTo []} && {_deferred isEqualTo []}) then {
    _lines pushBack format ["<t size='0.85' color='%1'>No Site or System active.</t>", COL_DIM];
};

// --- Nearest Site, in detail ---
if (_sites isNotEqualTo []) then {
    private _nearestIndex = 0;
    {
        if ((_camera distance2D _x) < (_camera distance2D (_sites select _nearestIndex))) then { _nearestIndex = _forEachIndex; };
    } forEach _sites;
    private _site = _sites select _nearestIndex;
    private _members = (_site getVariable ["AEGISM_networkMembers", []]) select { !isNull _x };
    private _claims = _site getVariable ["AEGISM_claims", createHashMap];
    private _pool = _site getVariable ["AEGISM_pooledContacts", createHashMap];
    private _allRecords = [];
    { _allRecords append _y; } forEach _claims;

    _lines pushBack format ["<t size='0.95' font='PuristaSemibold' color='%1'>%2</t><br/>", COL_HEAD, [_site, _nearestIndex] call _fnSiteName];
    _lines pushBack format ["<t size='0.75' color='%1'>%2 vehicle(s), %3 contact(s), %4 engagement(s)</t><br/><br/>", COL_DIM, count _members, count _pool, count _allRecords];

    {
        private _member = _x;
        ([_member] call _fnRolesAndAmmo) params ["_tags", "_ammoText"];
        ([_member, _allRecords select { (_x get "system") == _member }] call _fnSystemStatus) params ["_statusText", "_colour"];
        _lines pushBack format ["<t align='left' size='0.85'>%1 %2 <t color='%3'>%4</t></t><br/>",
            [_colour, "●"] call _fnColour, [_member] call _fnShortName, COL_DIM, _tags];
        _lines pushBack format ["<t align='left' size='0.75'>    %1%2</t><br/>",
            [_colour, _statusText] call _fnColour, ["", format [" <t color='%1'>(%2)</t>", COL_DIM, _ammoText]] select (_ammoText != "")];
    } forEach _members;

    // Contacts, nearest first, with the weapons on each.
    if (count _pool > 0) then {
        _contactLines pushBack format ["<br/><t align='left' size='0.8' font='PuristaSemibold' color='%1'>Contacts</t><br/>", COL_HEAD];
        // [key, entry] of every live contact.
        private _entries = [];
        { if (!isNull (_y getOrDefault ["object", objNull])) then { _entries pushBack [_x, _y]; }; } forEach _pool;
        private _sorted = [_entries, [], {
            private _object = (_x select 1) get "object";
            private _nearest = 1e10;
            { _nearest = _nearest min (_x distance _object); } forEach _members;
            _nearest
        }, "ASCEND"] call BIS_fnc_sortBy;
        {
            if (_forEachIndex < AEGISM_HINT_MAX_CONTACTS) then {
                _x params ["_key", "_entry"];
                private _object = _entry get "object";
                private _nearest = 1e10;
                { _nearest = _nearest min (_x distance _object); } forEach _members;
                // Every weapon on it, each in its own engagement state's
                // colour, and the contact's dot in the most urgent of them.
                private _urgent = [-1, COL_TRACK];
                private _onIt = (_claims getOrDefault [_key, []]) apply {
                    ([_x getOrDefault ["status", ""]] call aegism_fnc_statusStyle) params ["_label", "", "_hex", "_urgency"];
                    if (_urgency > (_urgent select 0)) then { _urgent = [_urgency, _hex]; };
                    [_hex, format ["%1 %2 %3", ["L", "C"] select ((_x get "role") == "ciws"), [_x get "system"] call _fnShortName, _label]] call _fnColour
                };
                _contactLines pushBack format ["<t align='left' size='0.75'>  %1 %2 <t color='%3'>%4 %5</t>%6</t><br/>",
                    [_urgent select 1, "●"] call _fnColour,
                    [_object] call _fnShortName, COL_DIM, _entry get "class", [_nearest] call _fnRange,
                    ["", format [" <t color='%1'>&lt;-</t> %2", COL_DIM, _onIt joinString ", "]] select (_onIt isNotEqualTo [])];
            };
        } forEach _sorted;
        if (count _sorted > AEGISM_HINT_MAX_CONTACTS) then {
            _contactLines pushBack format ["<t align='left' size='0.7' color='%1'>  +%2 more</t><br/>", COL_DIM, count _sorted - AEGISM_HINT_MAX_CONTACTS];
        };
    };

    // --- Other Sites, one line each ---
    if (count _sites > 1) then {
        _lines pushBack format ["<br/><t align='left' size='0.8' font='PuristaSemibold' color='%1'>Other Sites</t><br/>", COL_HEAD];
        {
            if (_forEachIndex != _nearestIndex) then {
                private _claimCount = 0;
                { _claimCount = _claimCount + count _y; } forEach (_x getVariable ["AEGISM_claims", createHashMap]);
                _lines pushBack format ["<t align='left' size='0.75'>  %1 <t color='%2'>%3 veh, %4 contacts, %5 engaging</t></t><br/>",
                    [_x, _forEachIndex] call _fnSiteName, COL_DIM,
                    count (_x getVariable ["AEGISM_networkMembers", []]), count (_x getVariable ["AEGISM_pooledContacts", createHashMap]), _claimCount];
            };
        } forEach _sites;
    };
};

// --- Standalone Systems ---
if (_standalone isNotEqualTo []) then {
    _lines pushBack format ["<br/><t align='left' size='0.8' font='PuristaSemibold' color='%1'>Standalone</t><br/>", COL_HEAD];
    {
        private _system = _x;
        // Each weapon turret's own engagement, in the shape of a Site record.
        private _records = [];
        {
            private _turretPath = _x;
            private _turretState = _y;
            {
                private _state = _turretState getOrDefault ["standalone_" + _x, createHashMap];
                if (!isNull (_state getOrDefault ["target", objNull])) then {
                    private _record = +_state;
                    _record set ["role", _x];
                    _record set ["weaponInfo", [_turretPath]];
                    _records pushBack _record;
                };
            } forEach ["launcher", "ciws"];
        } forEach (_system getVariable ["AEGISM_turrets", createHashMap]);
        ([_system] call _fnRolesAndAmmo) params ["_tags", "_ammoText"];
        ([_system, _records] call _fnSystemStatus) params ["_statusText", "_colour"];
        _lines pushBack format ["<t align='left' size='0.8'>%1 %2 <t color='%3'>%4</t></t><br/><t align='left' size='0.75'>    %5 <t color='%3'>(%6)</t></t><br/>",
            [_colour, "●"] call _fnColour, [_system] call _fnShortName, COL_DIM, _tags, [_colour, _statusText] call _fnColour, _ammoText];
    } forEach _standalone;
};

// --- Not active: why, and what to do ---
if (_deferred isNotEqualTo []) then {
    _lines pushBack format ["<br/><t align='left' size='0.8' font='PuristaSemibold' color='%1'>Not active</t><br/>", COL_HEAD];
    {
        _lines pushBack format ["<t align='left' size='0.8'>%1 %2</t><br/><t align='left' size='0.75'>    <t color='%3'>%4</t></t><br/>",
            [COL_EMPTY, "●"] call _fnColour, [_x] call _fnShortName, COL_ENGAGE, _x getVariable ["AEGISM_deferReason", "deferred until synced to a Site"]];
    } forEach _deferred;
};

_lines append _contactLines;
hintSilent parseText (_lines joinString "");
