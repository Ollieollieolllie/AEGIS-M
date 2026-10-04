/* ----------------------------------------------------------------------------
Function: aegism_fnc_statusBoard

Description:
    The AEGIS-M status board, as structured text:

        - one Site in detail: every member vehicle with its roles ([R]adar
          [I]R [V]isual sensor, [L]auncher [C]IWS), a colour-coded status,
          its current target and ammo. A Site linked with others (aegism_
          network_fnc_linkSites) is shown with its whole group: which Site
          coordinates it and whose settings apply, what links them, and each
          Site's vehicles under its own heading (the coordinator first, the
          one asked about marked "this terminal" or "nearest"; a vehicle
          linking them shown once, LINK)
        - with _everything, other Sites one line each, a linked one with
          what it's linked with and who coordinates
        - with _everything: every other Site as a one-line summary,
          standalone (unsynced) Systems one line each, and the vehicles
          AEGIS-M found capable but hasn't activated (deferred until synced
          to a Site), with why -- e.g. a launcher with no sensor of its own
          placed without a Site
        - last, the detailed Site's tracked contacts, the sensor kinds that
          saw each ([RDR IR], aegism_fnc_sensorTags) and the weapons on each
          (the longest section, so it's the one a hint box cuts)

    Each engagement shows in its own state's colour (aegism_fnc_statusStyle
    -- the state the engagement loop records on it every tick): blue QUEUED
    behind another on its launcher, amber REACTING/SLEWING/LOCKING, orange
    RELOADING, teal RANGE HOLD, red FIRING, gold IN FLIGHT, purple NO LOS /
    NO SOLUTION, grey CREW FAILED / FIRE HELD / NO AMMO. A vehicle with
    nothing assigned: green READY, yellow TRACKING (sensor with contacts),
    grey NO AMMO, dark grey DESTROYED.

    Shown by the Site Status Hint (aegism_fnc_debugHint: the Site nearest
    the camera, and everything else) and by a Site's status terminal
    (aegism_network_fnc_terminalRequest: that Site alone).

    Reads the same server-side variables the engagement pipeline runs on,
    so it only has data where that pipeline runs: singleplayer, Eden
    Preview, or the server (a terminal's board is built there and sent to
    the player using it).

Parameters:
    _focus - the Site shown in detail, or objNull for none <OBJECT>
    _everything - also the other Sites, standalone Systems and inactive
        vehicles <BOOLEAN, default true>
    _maxContacts - most contacts listed, nearest first <NUMBER, default 6>

Returns:
    Structured text, for parseText <STRING>

Examples:
    hintSilent parseText ([_site] call aegism_fnc_statusBoard);
    [_site, false, 50] call aegism_fnc_statusBoard;

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

params [["_focus", objNull], ["_everything", true], ["_maxContacts", 6]];

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

    // A networked sensor feeds its Site's pool (it keeps no munitions of its own).
    private _network = _system getVariable ["AEGISM_network", objNull];
    private _contacts = count (([_network, _system] select (isNull _network)) getVariable ["AEGISM_pooledContacts", createHashMap]);
    if ((_systemData getOrDefault ["hasSensor", false]) && {_contacts > 0}) exitWith { [format ["TRACKING %1 contact(s)", _contacts], COL_TRACK] };

    ["READY", COL_READY]
};

// "[R I L C]" role tags and "L 3 | C 540" ammo for one System.
private _fnRolesAndAmmo = {
    params ["_system"];
    private _systemData = _system getVariable ["AEGISM_system", createHashMap];
    private _tags = [];
    {
        _x params ["_type", "_tag"];
        if (((_systemData getOrDefault ["sensors", []]) findIf { (_x select 0) == _type }) != -1) then { _tags pushBack _tag; };
    } forEach [["radar", "R"], ["ir", "I"], ["visual", "V"]];
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
// The detailed Site's contacts go last: the vehicle-level sections come
// first, so they aren't the ones pushed off the bottom of a hint box.
private _contactLines = [];
private _focusIndex = _sites find _focus;

if (_everything && {_sites isEqualTo []} && {_standalone isEqualTo []} && {_deferred isEqualTo []}) then {
    _lines pushBack format ["<t size='0.85' color='%1'>No Site or System active.</t>", COL_DIM];
};
if (!_everything && {_focusIndex < 0}) then {
    _lines pushBack format ["<t size='0.85' color='%1'>This Site isn't running (deleted, or not set up yet).</t>", COL_DIM];
};

// The focus Site's linked group (aegism_network_fnc_linkSites), its
// coordinator first: just the focus Site when it isn't linked.
private _focusGroup = [];
if (_focusIndex >= 0) then {
    private _lead = _focus getVariable ["AEGISM_linkLead", _focus];
    _focusGroup = (_focus getVariable ["AEGISM_linkSites", [_focus]]) select { !isNull _x && {_x in _sites} };
    _focusGroup pushBackUnique _focus;
    if (_lead in _focusGroup) then { _focusGroup = [_lead] + (_focusGroup - [_lead]); };
};

// --- The focus Site, in detail: with every Site it's linked with ---
if (_focusIndex >= 0) then {
    private _claims = _focus getVariable ["AEGISM_claims", createHashMap];
    private _pool = _focus getVariable ["AEGISM_pooledContacts", createHashMap];
    private _allRecords = [];
    { _allRecords append _y; } forEach _claims;
    private _lead = _focusGroup select 0;
    private _linked = count _focusGroup > 1;
    // Every vehicle of the group, once; the ones linking its Sites.
    private _members = [];
    { { _members pushBackUnique _x; } forEach ((_x getVariable ["AEGISM_networkMembers", []]) select { !isNull _x }); } forEach _focusGroup;
    private _linkedBy = _focus getVariable ["AEGISM_linkShared", []];
    private _sharedVehicles = _linkedBy select { _x in _members };

    if (_linked) then {
        _lines pushBack format ["<t size='0.95' font='PuristaSemibold' color='%1'>Linked Sites: %2</t><br/>", COL_HEAD, (_focusGroup apply { [_x, _sites find _x] call _fnSiteName }) joinString " + "];
        _lines pushBack format ["<t size='0.75' color='%1'>%2 vehicle(s), %3 contact(s), %4 engagement(s) -- contacts and engagements shared</t><br/>", COL_DIM, count _members, count _pool, count _allRecords];
        _lines pushBack format ["<t size='0.75' color='%1'>Coordinated by %2 -- %3</t><br/>", COL_TRACK, [_lead, _sites find _lead] call _fnSiteName,
            ["first set up; each vehicle keeps its own Site's settings", "Shared Site Coordinator: its settings apply to every vehicle"] select (_lead getVariable ["sharedCoordinator", false])];
        private _byWhat = _sharedVehicles apply { [_x] call _fnShortName };
        if ((_linkedBy findIf { _x isKindOf "AEGISM_Module_Site" }) != -1) then { _byWhat pushBack "Site modules synced to each other"; };
        _lines pushBack format ["<t size='0.75' color='%1'>Linked by %2</t><br/>", COL_DIM, _byWhat joinString ", "];
    } else {
        _lines pushBack format ["<t size='0.95' font='PuristaSemibold' color='%1'>%2</t><br/>", COL_HEAD, [_focus, _focusIndex] call _fnSiteName];
        _lines pushBack format ["<t size='0.75' color='%1'>%2 vehicle(s), %3 contact(s), %4 engagement(s)</t><br/>", COL_DIM, count _members, count _pool, count _allRecords];
    };

    // Each Site's vehicles; a vehicle linking Sites under the first that
    // lists it (LINK).
    private _shown = [];
    {
        private _site = _x;
        if (_linked) then {
            private _siteTags = [];
            if (_site == _lead) then { _siteTags pushBack "coordinator"; };
            if (_site == _focus) then { _siteTags pushBack (["this terminal", "nearest"] select _everything); };
            _lines pushBack format ["<br/><t align='left' size='0.85' font='PuristaSemibold' color='%1'>%2</t><t align='left' size='0.75' color='%3'>%4</t><br/>",
                COL_HEAD, [_site, _sites find _site] call _fnSiteName, COL_DIM, ["", format ["  (%1)", _siteTags joinString ", "]] select (_siteTags isNotEqualTo [])];
        } else {
            _lines pushBack "<br/>";
        };
        {
            private _member = _x;
            if !(_member in _shown) then {
                _shown pushBack _member;
                ([_member] call _fnRolesAndAmmo) params ["_tags", "_ammoText"];
                ([_member, _allRecords select { (_x get "system") == _member }] call _fnSystemStatus) params ["_statusText", "_colour"];
                _lines pushBack format ["<t align='left' size='0.85'>%1 %2 <t color='%3'>%4</t>%5</t><br/>",
                    [_colour, "●"] call _fnColour, [_member] call _fnShortName, COL_DIM, _tags,
                    ["", format [" <t color='%1'>LINK</t>", COL_TRACK]] select (_member in _sharedVehicles)];
                _lines pushBack format ["<t align='left' size='0.75'>    %1%2</t><br/>",
                    [_colour, _statusText] call _fnColour, ["", format [" <t color='%1'>(%2)</t>", COL_DIM, _ammoText]] select (_ammoText != "")];
            };
        } forEach ((_site getVariable ["AEGISM_networkMembers", []]) select { !isNull _x });
    } forEach _focusGroup;

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
            if (_forEachIndex < _maxContacts) then {
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
                private _sensorTags = [_entry getOrDefault ["sources", createHashMap]] call aegism_fnc_sensorTags;
                _contactLines pushBack format ["<t align='left' size='0.75'>  %1 %2 <t color='%3'>%4 %5%7</t>%6</t><br/>",
                    [_urgent select 1, "●"] call _fnColour,
                    [_object] call _fnShortName, COL_DIM, _entry get "class", [_nearest] call _fnRange,
                    ["", format [" <t color='%1'>&lt;-</t> %2", COL_DIM, _onIt joinString ", "]] select (_onIt isNotEqualTo []),
                    ["", format [" [%1]", _sensorTags]] select (_sensorTags != "")];
            };
        } forEach _sorted;
        if (count _sorted > _maxContacts) then {
            _contactLines pushBack format ["<t align='left' size='0.7' color='%1'>  +%2 more</t><br/>", COL_DIM, count _sorted - _maxContacts];
        };
    };
};

if (_everything) then {
    // --- Other Sites (not linked with the focus Site), one line each ---
    private _otherSites = _sites - _focusGroup - [_focus];
    if (_otherSites isNotEqualTo []) then {
        _lines pushBack format ["<br/><t align='left' size='0.8' font='PuristaSemibold' color='%1'>Other Sites</t><br/>", COL_HEAD];
        {
            private _claimCount = 0;
            { _claimCount = _claimCount + count _y; } forEach (_x getVariable ["AEGISM_claims", createHashMap]);
            private _linkedWith = (_x getVariable ["AEGISM_linkSites", [_x]]) - [_x];
            private _otherLead = _x getVariable ["AEGISM_linkLead", _x];
            _lines pushBack format ["<t align='left' size='0.75'>  %1 <t color='%2'>%3 veh, %4 contacts, %5 engaging</t>%6</t><br/>",
                [_x, _sites find _x] call _fnSiteName, COL_DIM,
                count (_x getVariable ["AEGISM_networkMembers", []]), count (_x getVariable ["AEGISM_pooledContacts", createHashMap]), _claimCount,
                ["", format [" <t color='%1'>linked with %2, coordinated by %3</t>", COL_TRACK, (_linkedWith apply { [_x, _sites find _x] call _fnSiteName }) joinString ", ", [_otherLead, _sites find _otherLead] call _fnSiteName]] select (_linkedWith isNotEqualTo [])];
        } forEach _otherSites;
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
};

_lines append _contactLines;
_lines joinString ""
