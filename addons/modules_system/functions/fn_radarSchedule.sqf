/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_radarSchedule

Description:
    Points a narrow radar that turns on a turret no AEGIS-M weapon uses (the
    vanilla radar truck's 120 degrees), whatever its Radar Emission: called
    once a second by aegism_system_fnc_emconUpdate. It's never left idle
    facing wherever its crew last looked.

    The Site's turning radars -- its whole linked group's (aegism_network_
    fnc_linkSites) -- divide the sky between them: 360 degrees in equal home
    sectors, one each, measured from the middle of them, in a fixed order
    (by netId), the first centred on north. A sector decides which radar
    looks after which contacts:

        fire control - while a Site launcher's missiles fly at a target in
            its sector, it holds as many of them as it can, and doesn't
            search.
        track - on the contacts in its sector, centred to hold the most
            important at once: a threat under engagement, then munitions by
            time to impact, a contact only passive radar hears (a radar look
            makes it a track), aircraft. A contact another Site sensor saw in
            the last AEGISM_HELD_FOR s counts for a quarter: the radar is for
            what nobody holds. It stays centred where it is while that scores
            AEGISM_TRACK_KEEP of the best centre, rather than hopping between
            near-equal ones. Every AEGISM_SEARCH_REVISIT s it takes a look at
            its search position, if its track doesn't already hold that, and
            comes back.
        search - nothing worth tracking: the Site's turning radars rotate
            round together, evenly spaced -- each starts on its own sector
            and turns on one step (three quarters of the narrowest arc among
            them) every period (the slowest turret's swing for a step, then
            AEGISM_SEARCH_DWELL s), by the mission clock, so all of them are
            always at the same step. Every radar looks all the way round --
            radars far apart see past different hills -- and at any moment
            their beams are spread evenly round the sky (three 120-degree
            radars keep all round covered as they turn). Silent ones turn too,
            so each is in its place when it lights. With the Site's Turning
            Radars Hold Their Sector on, a radar whose arc covers its sector
            stays on it instead. (Searching on their own, two radars each
            swung across their own half and never turned round; three ended
            up facing north, east and south with the west uncovered; four
            drifted until two pointed the same way.) Pitched up a quarter of
            its vertical arc (within its elevation limits), covering the
            horizon and well above it.

    A contact belongs to the radar whose sector it's in. Another of the
    Site's radars tracks it only if that one can't reach it -- and then only
    one: each radar posts what it's tracking ("AEGISM_radarTracks": contact
    key -> [radar netId, until]), and a contact another is tracking counts
    for a tenth.

    Every dwell starts once the turret has had time to swing there, from its
    traverse rate (aegism_intercept_fnc_turretConfig). Logged as RADAR-TASK
    at RPT Detail Verbose when it starts tracking, holds fire control, starts
    searching, or the rotation changes (a turning radar joins or leaves).

    Records on the vehicle ("AEGISM_radarBeam", for the debug overlays):
    task, taskUntil, lastSearchAt, bearing (where it points), search (its
    search position), dwellFrom, fenceCount, text.

Parameters:
    _vehicle - the radar vehicle <OBJECT>
    _radar - its pointable radar: its sensors entry (aegism_system_fnc_
        discoverCapabilities) <ARRAY>

Returns:
    Nothing

Examples:
    [_radarTruck, _sensor] call aegism_system_fnc_radarSchedule;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

#define AEGISM_TRACK_DWELL 2
#define AEGISM_SEARCH_DWELL 2
#define AEGISM_SEARCH_REVISIT 6
#define AEGISM_HELD_FOR 1.5
// The rotation's smallest step, degrees.
#define AEGISM_ROTATION_MIN_STEP 10
// Tracking, it stays put while where it points scores this share of the best.
#define AEGISM_TRACK_KEEP 0.85
// Contacts worth at least this much together make it track rather than search.
#define AEGISM_TRACK_MIN 2
// Its tracks stand this long after it last said so.
#define AEGISM_CLAIM_FOR 2
// How far out the point a radar turret is aimed at lies, metres.
#define AEGISM_LOOK_DISTANCE 2000
// Contact weights (see the header).
#define AEGISM_W_GUIDED 100
#define AEGISM_W_ENGAGED 10
#define AEGISM_W_CUE 6
#define AEGISM_W_MUNITION 5
#define AEGISM_W_AIRCRAFT 3

params ["_vehicle", "_radar", ["_relay", []]];
_radar params ["", "", "_arc", "_turretPath", "", "", "", ["_verticalArc", 360]];

private _beam = _vehicle getVariable "AEGISM_radarBeam";
if (isNil "_beam") then {
    _beam = createHashMapFromArray [["task", ""], ["taskUntil", -1], ["lastSearchAt", -1e9], ["bearing", getDir _vehicle], ["search", getDir _vehicle], ["dwellFrom", -1], ["fenceCount", 0], ["text", ""]];
    _vehicle setVariable ["AEGISM_radarBeam", _beam, false];
};

private _network = _vehicle getVariable ["AEGISM_network", objNull];
private _members = if (isNull _network) then { [_vehicle] } else {
    (_network getVariable ["AEGISM_groupMembers", _network getVariable ["AEGISM_networkMembers", []]]) select { !isNull _x && {alive _x} }
};
private _pool = ([_network, _vehicle] select (isNull _network)) getVariable ["AEGISM_pooledContacts", createHashMap];
private _claims = if (isNull _network) then { createHashMap } else { _network getVariable ["AEGISM_claims", createHashMap] };
// The Site's shared records: its link group's lead's, or this radar's own.
private _holder = if (isNull _network) then { _vehicle } else { _network getVariable ["AEGISM_linkLead", _network] };
private _tracks = _holder getVariable "AEGISM_radarTracks";
if (isNil "_tracks") then { _tracks = createHashMap; _holder setVariable ["AEGISM_radarTracks", _tracks, false]; };
private _myId = netId _vehicle;

private _eye = eyePos _vehicle;
private _emitting = isVehicleRadarOn _vehicle;
private _half = _arc / 2;
// Signed difference between two bearings, -180 to 180.
private _fnDiff = { params ["_a", "_b"]; ((_a - _b + 540) mod 360) - 180 };

// --- The Site's turning radars, and this one's home sector ---
private _fence = (_members select { (_x call aegism_system_fnc_turningRadar) isNotEqualTo [] }) apply { [netId _x, _x] };
_fence sort true;
_fence = _fence apply { _x select 1 };
if !(_vehicle in _fence) then { _fence = [_vehicle]; };
private _count = count _fence;
private _width = 360 / _count;
private _sectorCentre = (_fence find _vehicle) * _width;
// Sectors are bearings from the middle of the Site's turning radars: from
// each radar's own position they'd disagree for Sites far apart.
private _middle = [0, 0, 0];
{ _middle = _middle vectorAdd (eyePos _x); } forEach _fence;
_middle = _middle vectorMultiply (1 / _count);
private _fnOwner = { _fence select ((floor ((((_middle getDir _this) + _width / 2) mod 360) / _width)) min (_count - 1)) };

// --- Who holds what: contacts another Site sensor saw just now ---
private _held = createHashMap;
{
    private _other = _x;
    if (_other != _vehicle && {((_other getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasSensor", false])}) then {
        {
            private _key = _x;
            if ((keys (_y getOrDefault ["sources", createHashMap])) findIf { _x != "passiveradar" && {CBA_missionTime - ((_y get "sources") get _x) <= AEGISM_HELD_FOR} } != -1) then { _held set [_key, true]; };
        } forEach (_other getVariable ["AEGISM_pooledContacts", createHashMap]);
        (_other getVariable ["AEGISM_seenMunitions", [-1e9, createHashMap]]) params ["_readAt", "_munitions"];
        if (CBA_missionTime - _readAt <= AEGISM_HELD_FOR) then { { _held set [_x, true]; } forEach _munitions; };
    };
} forEach _members;

// --- What it looks after: [bearing, elevation, weight, guided, object, key] ---
private _guidedTargets = [];
{
    {
        private _target = _x getOrDefault ["target", objNull];
        if ((_x get "role") == "launcher" && {!isNull _target} && {((_x getOrDefault ["interceptors", []]) findIf { !isNull _x && {alive _x} }) != -1}) then { _guidedTargets pushBackUnique _target; };
    } forEach _y;
} forEach _claims;
private _contacts = [];
{
    private _key = _x;
    private _object = _y getOrDefault ["object", objNull];
    if (!isNull _object && {alive _object}) then {
        private _pos = getPosASL _object;
        private _bearing = _eye getDir _pos;
        // In its sector, or in another's that can't reach it.
        private _owner = _pos call _fnOwner;
        if ((_owner == _vehicle || {!(([_owner, _pos] call aegism_system_fnc_radarCovers) select 0)})
            && {([_vehicle, _pos] call aegism_system_fnc_radarCovers) select 0}) then {
            private _guided = _object in _guidedTargets;
            (_y getOrDefault ["tti", [1e10, CBA_missionTime]]) params ["_tti", "_ttiAt"];
            private _weight = switch (true) do {
                case _guided: { AEGISM_W_GUIDED };
                case (_key in _claims): { AEGISM_W_ENGAGED };
                case !([_y] call aegism_fnc_hasTrack): { AEGISM_W_CUE };
                case (_y getOrDefault ["isMunition", false]): { AEGISM_W_MUNITION + 10 / (1 + ((_tti - (CBA_missionTime - _ttiAt)) max 0)) };
                default { AEGISM_W_AIRCRAFT };
            };
            if (!_guided && {_key in _held}) then { _weight = _weight / 4; };
            // Another of the Site's radars is already tracking it (one that
            // isn't its owner either): left to that one.
            (_tracks getOrDefault [_key, ["", -1]]) params ["_trackedBy", "_trackedUntil"];
            if (_trackedBy != "" && {_trackedBy != _myId} && {CBA_missionTime <= _trackedUntil}) then { _guided = false; _weight = _weight / 10; };
            private _distance = _eye distance _pos;
            _contacts pushBack [_bearing, if (_distance > 0) then { asin ((((_pos select 2) - (_eye select 2)) / _distance) max -1 min 1) } else { 0 }, _weight, _guided, _object, _key];
        };
    };
} forEach _pool;

// --- Where to track: the beam centre holding the most weight at once ---
// A little inside its arc, so a contact near the edge stays in it.
private _hold = _half * 0.85;
// [score, contacts held, guided held, elevation of its heaviest] at a centre.
private _fnWindow = {
    private _centre = _this;
    private _score = 0;
    private _inside = 0;
    private _guidedCount = 0;
    private _heaviest = [-1, 0];
    {
        _x params ["_bearing", "_elevation", "_weight", "_guided"];
        if (abs ([_bearing, _centre] call _fnDiff) <= _hold) then {
            _score = _score + _weight;
            _inside = _inside + 1;
            if (_guided) then { _guidedCount = _guidedCount + 1; };
            if (_weight > (_heaviest select 0)) then { _heaviest = [_weight, _elevation]; };
        };
    } forEach _contacts;
    [_score, _inside, _guidedCount, _heaviest select 1]
};
// [score, bearing, contacts held, guided held, elevation].
private _window = [0, _beam get "bearing", 0, 0, 0];
if (_contacts isNotEqualTo []) then {
    private _centres = [];
    { _centres append [_x select 0, (_x select 0) + _hold, (_x select 0) - _hold]; } forEach _contacts;
    {
        private _centre = (_x + 360) mod 360;
        (_centre call _fnWindow) params ["_score", "_inside", "_guidedCount", "_elevation"];
        if (_score > (_window select 0)) then { _window = [_score, _centre, _inside, _guidedCount, _elevation]; };
    } forEach _centres;
    // Already tracking: it stays where it is unless somewhere else is clearly
    // better, rather than hopping between near-equal centres every second.
    if ((_beam get "task") in ["track", "fire control"]) then {
        private _here = (_beam get "bearing") call _fnWindow;
        if ((_here select 0) >= AEGISM_TRACK_KEEP * (_window select 0) && {(_here select 2) >= (_window select 3)}) then {
            _window = [_here select 0, _beam get "bearing", _here select 1, _here select 2, _here select 3];
        };
    };
};
_window params ["_trackScore", "_trackBearing", "_trackCount", "_guidedCount", "_trackElevation"];

// --- Where to search: the Site's turning radars rotate together ---
([_vehicle, _turretPath] call aegism_intercept_fnc_turretConfig) params ["", "", "", "_minElev", "_maxElev", "", "_traverseRate"];
private _pitch = (((_verticalArc min 180) / 4) max _minElev) min _maxElev;
// Seconds its turret takes to swing from where it points to a bearing.
private _fnSlew = { (abs ([_this, _beam get "bearing"] call _fnDiff)) / (_traverseRate max 1) };
// One step of the rotation -- three quarters of the narrowest arc among them
// -- every period: the slowest turret's swing for a step, then a dwell. The
// same for all, so they keep their places.
private _turning = _fence apply {
    private _sensor = _x call aegism_system_fnc_turningRadar;
    [_sensor select 2, ([_x, _sensor select 3] call aegism_intercept_fnc_turretConfig) select 6]
};
private _rotationStep = ((selectMin (_turning apply { _x select 0 })) * 0.75) max AEGISM_ROTATION_MIN_STEP;
private _period = (selectMax (_turning apply { _rotationStep / ((_x select 1) max 1) })) + AEGISM_SEARCH_DWELL;
// Holding its sector still: its arc covers it, and the Site's Turning Radars
// Hold Their Sector is on.
private _holds = _arc >= _width && {(_vehicle getVariable ["AEGISM_resolvedEngagementSettings", createHashMap]) getOrDefault ["radarHoldSector", false]};
// Where it searches now: its sector's centre if it holds it; otherwise its
// place in the rotation -- its sector's centre turned on one step every
// period, by the mission clock, so every one of them is at the same step.
private _fnNextSearch = {
    if (_holds) exitWith { _sectorCentre };
    (_sectorCentre + (floor (CBA_missionTime / _period)) * _rotationStep) mod 360
};
private _sectorText = if (_count == 1) then { "" } else {
    format [", sector %1-%2", ((round (_sectorCentre - _width / 2)) + 360) mod 360, (round (_sectorCentre + _width / 2)) mod 360]
};
private _searchText = switch (true) do {
    case (_relay isNotEqualTo []): {
        switch (true) do {
            case ((_relay select 0) >= 0): { ", relay scan: lit" };
            case ((_relay select 1) >= 0): { ", relay scan: next" };
            default { ", relay scan: standing by" };
        }
    };
    case (_holds): { format [", holding sector %1-%2", ((round (_sectorCentre - _width / 2)) + 360) mod 360, (round (_sectorCentre + _width / 2)) mod 360] };
    case (_count == 1): { ", rotating" };
    default { format [", rotating %1 of %2", (_fence find _vehicle) + 1, _count] };
};

// --- Choose its task ---
private _task = _beam get "task";
private _until = _beam get "taskUntil";
private _searchBearing = -1;
private _why = "";
switch (true) do {
    case (_guidedCount > 0): { _task = "fire control"; _until = CBA_missionTime; };
    // Something worth tracking: track, with a look at its sector's search
    // position every so often (only while emitting: a silent radar searches
    // nothing) if its track doesn't already hold that.
    case (_trackScore >= AEGISM_TRACK_MIN): {
        if (_task == "search" && {CBA_missionTime < _until}) exitWith {};
        if (_emitting && {_task == "track"} && {CBA_missionTime >= _until} && {CBA_missionTime - (_beam get "lastSearchAt") >= AEGISM_SEARCH_REVISIT}) exitWith {
            private _look = call _fnNextSearch;
            _beam set ["lastSearchAt", CBA_missionTime];
            // Its track's beam already takes in most of that arc.
            if (abs ([_look, _trackBearing] call _fnDiff) <= _half / 2) exitWith {};
            _task = "search";
            _searchBearing = _look;
            _why = "a look at its search position while tracking";
        };
        if (_task != "track") then { _until = CBA_missionTime + (_trackBearing call _fnSlew) + AEGISM_TRACK_DWELL; };
        _task = "track";
    };
    // Searching: where the rotation (or its held sector) has it now, emitting
    // or not -- a silent one keeps its place, and is there when it lights.
    // In the relay scan (aegism_system_fnc_radarRelay), the arc it's lit on
    // or lights on next; with neither, it holds where it is.
    default {
        private _next = if (_relay isEqualTo []) then { call _fnNextSearch } else { _relay select 1 };
        if (_next >= 0 && {_task != "search" || {abs ([_next, _beam get "search"] call _fnDiff) > 1}}) then {
            _searchBearing = _next;
            _why = switch (true) do {
                case (_relay isNotEqualTo []): { ["relay scan, next arc", "relay scan, lit"] select ((_relay select 0) >= 0) };
                case (_holds): { "holding its sector" };
                default { "rotating" };
            };
        };
        _task = "search";
    };
};
if (_searchBearing >= 0) then {
    private _slew = _searchBearing call _fnSlew;
    _until = CBA_missionTime + _slew + AEGISM_SEARCH_DWELL;
    _beam set ["dwellFrom", CBA_missionTime + _slew];
    _beam set ["bearing", _searchBearing];
    _beam set ["search", _searchBearing];
    _beam set ["lastSearchAt", CBA_missionTime];
    // Logged when it starts searching, the rotation changes (a turning radar
    // joins or leaves), or it takes an arc of the relay scan -- not every
    // step of the rotation.
    if (AEGISM_RPT_VERBOSE && {(_beam get "task") != "search" || {(_beam get "fenceCount") != _count} || {_relay isNotEqualTo []}}) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " RADAR-TASK: %1 searches %2 deg (%3%4) -- %5; the rotation steps %6 deg every %7s; %8.", _vehicle, round _searchBearing, _why, _sectorText,
            if (_count == 1) then { "the Site's only turning radar" } else { format ["with %1 other turning radar(s), %2 deg apart", _count - 1, round _width] },
            round _rotationStep, (round (_period * 10)) / 10, ["silent, pointing only", "emitting"] select _emitting];
    };
};
_beam set ["fenceCount", _count];
if (_task != (_beam get "task") && {_task != "search"}) then {
    _beam set ["dwellFrom", CBA_missionTime + (_trackBearing call _fnSlew)];
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " RADAR-TASK: %1 %2 %3 contact(s) at %4 deg%5 (%6).", _vehicle, ["tracks", "holds for fire control"] select (_task == "fire control"),
            _trackCount, round _trackBearing, _sectorText, (_contacts select { abs ([_x select 0, _trackBearing] call _fnDiff) <= _hold }) apply { typeOf (_x select 4) }];
    };
};
_beam set ["task", _task];
_beam set ["taskUntil", _until];

// --- Point it ---
private _aimAt = [];
if (_task in ["track", "fire control"]) then {
    _beam set ["bearing", _trackBearing];
    _aimAt = _eye vectorAdd ([sin _trackBearing * cos _trackElevation, cos _trackBearing * cos _trackElevation, sin _trackElevation] vectorMultiply AEGISM_LOOK_DISTANCE);
    _beam set ["text", format ["%1 %2 (%3 deg%4)", ["TRACK", "FIRE CONTROL"] select (_task == "fire control"), _trackCount, round _trackBearing, _sectorText]];
} else {
    private _bearing = _beam get "bearing";
    _aimAt = _eye vectorAdd ([sin _bearing * cos _pitch, cos _bearing * cos _pitch, sin _pitch] vectorMultiply AEGISM_LOOK_DISTANCE);
    _beam set ["text", format ["SEARCH %1 deg%2%3", round _bearing, _searchText, ["", " (swinging)"] select (CBA_missionTime < (_beam getOrDefault ["dwellFrom", -1]))]];
};
[_vehicle, _turretPath, _aimAt] call aegism_intercept_fnc_lockTurret;

// --- What it's tracking, for the Site's other radars (see above) ---
{ if (CBA_missionTime > ((_y select 1) + AEGISM_CLAIM_FOR)) then { _tracks deleteAt _x; }; } forEach +_tracks;
if (_task in ["track", "fire control"]) then {
    {
        _x params ["_bearing", "", "", "", "", "_key"];
        (_tracks getOrDefault [_key, ["", -1]]) params ["_trackedBy", "_trackedUntil"];
        if (abs ([_bearing, _trackBearing] call _fnDiff) <= _hold && {_trackedBy in ["", _myId] || {CBA_missionTime > _trackedUntil}}) then {
            _tracks set [_key, [_myId, CBA_missionTime + AEGISM_CLAIM_FOR]];
        };
    } forEach _contacts;
};
