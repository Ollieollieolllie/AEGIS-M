/* ----------------------------------------------------------------------------
Function: aegism_fnc_debugHint

Description:
    Live status board in the hint box, refreshed once a second while the
    CBA setting "AEGIS-M > Debug > Site Status Hint" is on:

        - the Site nearest the camera, in detail: every member vehicle with
          its roles ([R]adar [L]auncher [C]IWS), a colour-coded status, its
          current target and ammo; then that Site's tracked contacts and
          which weapons are on each
        - every other Site as a one-line summary
        - standalone (unsynced) Systems, one line each

    Status colours: green READY, yellow TRACKING (radar with contacts), amber
    REACTING/SLEWING, orange ENGAGING, red FIRING, purple NO SOLUTION /
    LOS BLOCKED, grey NO AMMO, dark grey DESTROYED.

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
#define COL_SLEW "#FFCA28"
#define COL_ENGAGE "#FFA726"
#define COL_FIRE "#EF5350"
#define COL_BLOCKED "#CE93D8"
#define COL_EMPTY "#9E9E9E"
#define COL_DEAD "#616161"
#define COL_DIM "#90A4AE"
#define COL_HEAD "#4FC3F7"
#define AEGISM_HINT_MAX_CONTACTS 6
#define AEGISM_HINT_RECENT_SHOT 2

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

// [status text, colour] for one System, from its live engagement state.
private _fnSystemStatus = {
    params ["_system", "_records"];
    if (!alive _system) exitWith { ["DESTROYED", COL_DEAD] };

    private _systemData = _system getVariable ["AEGISM_system", createHashMap];
    private _status = [];
    {
        private _record = _x;
        private _role = _record get "role";
        private _target = _record getOrDefault ["target", objNull];
        (_record get "weaponInfo") params ["_turretPath"];
        private _turretState = (_system getVariable ["AEGISM_turrets", createHashMap]) getOrDefault [_turretPath, createHashMap];
        private _burstEnds = (_turretState getOrDefault ["burst", [-1]]) select 0;
        (_turretState getOrDefault ["aim_" + _role, []]) params [["_angle", 0], ["_tolerance", 180], ["_aimAt", -1e9], ["_aimTarget", objNull], ["_feasible", true]];
        private _aimFresh = time - _aimAt < 1 && {_aimTarget == _target};
        private _targetText = format ["%1 %2", [_target] call _fnShortName, [_system distance _target] call _fnRange];
        private _roleTag = ["L", "C"] select (_role == "ciws");

        private _line = switch (true) do {
            case (time < _burstEnds || {time - (_record get "lastShotAt") < AEGISM_HINT_RECENT_SHOT && {(_record get "lastShotAt") >= 0}}): { [format ["FIRING %1", _targetText], COL_FIRE] };
            case (_aimFresh && {!_feasible}): { [format ["NO SOLUTION %1", _targetText], COL_BLOCKED] };
            case (_record getOrDefault ["losBlocked", false]): { [format ["LOS BLOCKED %1", _targetText], COL_BLOCKED] };
            case (_aimFresh && {_angle > _tolerance}): { [format ["SLEWING %1deg %2", round _angle, _targetText], COL_SLEW] };
            case (time - (_record get "assignedAt") < 1): { [format ["REACTING %1", _targetText], COL_SLEW] };
            default { [format ["ENGAGING %1", _targetText], COL_ENGAGE] };
        };
        _status pushBack [format ["%1: %2", _roleTag, _line select 0], _line select 1];
    } forEach _records;

    if (_status isNotEqualTo []) exitWith {
        // Most urgent colour first (FIRING > ...), all lines shown.
        private _order = [COL_FIRE, COL_BLOCKED, COL_SLEW, COL_ENGAGE];
        private _worst = _status select 0;
        { if ((_order find (_x select 1)) < (_order find (_worst select 1))) then { _worst = _x; }; } forEach _status;
        [(_status apply { _x select 0 }) joinString " | ", _worst select 1]
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

private _lines = [format ["<t size='1.2' font='PuristaBold' color='%1'>AEGIS-M</t><br/>", COL_HEAD]];

if (_sites isEqualTo [] && {_standalone isEqualTo []}) then {
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
        _lines pushBack format ["<br/><t align='left' size='0.8' font='PuristaSemibold' color='%1'>Contacts</t><br/>", COL_HEAD];
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
                private _onIt = (_claims getOrDefault [_key, []]) apply { format ["%1 %2", ["L", "C"] select ((_x get "role") == "ciws"), [_x get "system"] call _fnShortName] };
                _lines pushBack format ["<t align='left' size='0.75'>  %1 %2 <t color='%3'>%4 %5</t>%6</t><br/>",
                    [[COL_TRACK, COL_ENGAGE] select (_onIt isNotEqualTo []), "●"] call _fnColour,
                    [_object] call _fnShortName, COL_DIM, _entry get "class", [_nearest] call _fnRange,
                    ["", format [" <t color='%1'>&lt;- %2</t>", COL_ENGAGE, _onIt joinString ", "]] select (_onIt isNotEqualTo [])];
            };
        } forEach _sorted;
        if (count _sorted > AEGISM_HINT_MAX_CONTACTS) then {
            _lines pushBack format ["<t align='left' size='0.7' color='%1'>  +%2 more</t><br/>", COL_DIM, count _sorted - AEGISM_HINT_MAX_CONTACTS];
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

hintSilent parseText (_lines joinString "");
