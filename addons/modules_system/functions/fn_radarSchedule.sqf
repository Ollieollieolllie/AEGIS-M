/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_radarSchedule

Description:
    Points a narrow radar that turns on a turret no AEGIS-M weapon uses (the
    vanilla radar truck's 120 degrees), whatever its Radar Emission: called
    once a second by aegism_system_fnc_emconUpdate. Its beam is time-shared
    between tracking and searching, so it's never left idle facing wherever
    its crew last looked:

        fire control - while a Site launcher's missiles fly at a target it
            can bring into its arc, it stays on them (the targets the most
            of them it can hold at once), and doesn't search.
        track - on the contacts in the Site's picture it can bring into its
            arc, centred to hold the most important at once: a threat under
            engagement, then munitions by time to impact, a contact only
            passive radar hears (a radar look makes it a track), aircraft.
            A contact another Site sensor saw in the last AEGISM_HELD_FOR s
            counts for a quarter: this radar is for what nobody holds. It
            stays centred where it is while that scores AEGISM_TRACK_KEEP of
            the best centre, rather than hopping between near-equal ones.
            Every AEGISM_SEARCH_REVISIT s it looks at the arc either side of
            its track that was searched longer ago -- a short swing, and back
            before the track is lost.
        search - nothing worth tracking: a steady sweep round, one step of
            three quarters of its arc at a time, skipping an arc another of
            the Site's radars searched in the last AEGISM_SECTOR_FRESH s
            ("AEGISM_radarSectors": when each AEGISM_SECTOR_WIDTH-degree
            bearing was last in an emitting narrow radar's beam) -- so
            several radars spread out round the sky -- and one its turret
            can't reach. It dwells AEGISM_SEARCH_DWELL s once it's there,
            twice as long on bearings contacts have been on in the last
            AEGISM_THREAT_MEMORY s ("AEGISM_threatAxes"). Pitched up a
            quarter of its vertical arc (within its elevation limits),
            covering the horizon and well above it.

    The Site's narrow radars (its whole linked group's) share where each is
    looking and what each is tracking ("AEGISM_radarBeams", "AEGISM_
    radarTracks"): a search arc overlapping another's beam -- even one
    still swinging there -- is skipped, and a contact another is tracking
    counts for a tenth (a target missiles are flying at excepted), so the
    second radar searches instead. Two radars of linked Sites used to sweep
    the same arc at the same time.

    Every dwell starts once the turret has had time to swing there, from
    its traverse rate (aegism_intercept_fnc_turretConfig): a dwell that ran
    out mid-swing left a slow turret never settling. Each new task and
    search dwell is logged as RADAR-TASK at RPT Detail Verbose.

    Bearings are measured from each radar itself; a Site's radars share the
    sector times (on the linked group's lead, aegism_network_fnc_linkSites),
    which assumes they're near each other. A silent radar (not emitting)
    keeps pointing -- at what it would track, or the sector it would search
    next -- but searches nothing, so it's on it the moment it lights.

    Records on the vehicle ("AEGISM_radarBeam", for the debug overlays):
    task, taskUntil, lastSearchAt, bearing, text.

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
#define AEGISM_SECTOR_WIDTH 10
// A sector another radar of the Site searched this recently is skipped.
#define AEGISM_SECTOR_FRESH 4
#define AEGISM_THREAT_MEMORY 300
// Tracking, it stays put while where it points scores this share of the best.
#define AEGISM_TRACK_KEEP 0.85
// Contacts worth at least this much together make it track rather than search.
#define AEGISM_TRACK_MIN 2
// A search arc whose centre is nearer another radar's beam than this share
// of their two half arcs together overlaps it.
#define AEGISM_BEAM_SEPARATION 0.75
// Its beam and tracks stand this long after it last said so.
#define AEGISM_CLAIM_FOR 2
// How far out the point a radar turret is aimed at lies, metres.
#define AEGISM_LOOK_DISTANCE 2000
// Contact weights (see the header).
#define AEGISM_W_GUIDED 100
#define AEGISM_W_ENGAGED 10
#define AEGISM_W_CUE 6
#define AEGISM_W_MUNITION 5
#define AEGISM_W_AIRCRAFT 3

params ["_vehicle", "_radar"];
_radar params ["", "", "_arc", "_turretPath", "", "", "", ["_verticalArc", 360]];

private _beam = _vehicle getVariable "AEGISM_radarBeam";
if (isNil "_beam") then {
    _beam = createHashMapFromArray [["task", ""], ["taskUntil", -1], ["lastSearchAt", -1e9], ["bearing", getDir _vehicle], ["sweep", getDir _vehicle], ["kind", ""], ["dwellFrom", -1], ["text", ""]];
    _vehicle setVariable ["AEGISM_radarBeam", _beam, false];
};

private _network = _vehicle getVariable ["AEGISM_network", objNull];
private _members = if (isNull _network) then { [_vehicle] } else {
    (_network getVariable ["AEGISM_groupMembers", _network getVariable ["AEGISM_networkMembers", []]]) select { !isNull _x && {alive _x} }
};
private _pool = ([_network, _vehicle] select (isNull _network)) getVariable ["AEGISM_pooledContacts", createHashMap];
private _claims = if (isNull _network) then { createHashMap } else { _network getVariable ["AEGISM_claims", createHashMap] };
// The Site's shared search record: its link group's lead's, or this radar's own.
private _holder = if (isNull _network) then { _vehicle } else { _network getVariable ["AEGISM_linkLead", _network] };
private _bins = round (360 / AEGISM_SECTOR_WIDTH);
private _sectors = _holder getVariable "AEGISM_radarSectors";
if (isNil "_sectors") then { _sectors = []; _sectors resize [_bins, -1e9]; _holder setVariable ["AEGISM_radarSectors", _sectors, false]; };
private _axes = _holder getVariable "AEGISM_threatAxes";
if (isNil "_axes") then { _axes = []; _axes resize [_bins, -1e9]; _holder setVariable ["AEGISM_threatAxes", _axes, false]; };
// Where the Site's narrow radars are looking ("AEGISM_radarBeams": radar
// netId -> [radar, bearing, half arc, until]) and which contacts each is
// tracking ("AEGISM_radarTracks": contact key -> [radar netId, until]); each
// writes its own at the end. Another's beam isn't searched again, nor
// another's track tracked: two radars of linked Sites used to sweep the same
// arc at the same time -- a sector only counted as searched once a radar got
// there, so the other picked it too while it was still swinging.
private _beams = _holder getVariable "AEGISM_radarBeams";
if (isNil "_beams") then { _beams = createHashMap; _holder setVariable ["AEGISM_radarBeams", _beams, false]; };
private _tracks = _holder getVariable "AEGISM_radarTracks";
if (isNil "_tracks") then { _tracks = createHashMap; _holder setVariable ["AEGISM_radarTracks", _tracks, false]; };
private _myId = netId _vehicle;
private _otherBeams = [];
{
    _y params ["_radarVehicle", "_otherBearing", "_otherHalf", "_until"];
    if (_x != _myId && {!isNull _radarVehicle} && {alive _radarVehicle} && {time <= _until}) then { _otherBeams pushBack [_otherBearing, _otherHalf]; };
} forEach _beams;

private _eye = eyePos _vehicle;
private _emitting = isVehicleRadarOn _vehicle;
private _half = _arc / 2;
// Signed difference between two bearings, -180 to 180.
private _fnDiff = { params ["_a", "_b"]; ((_a - _b + 540) mod 360) - 180 };
private _fnBin = { (floor ((_this mod 360) / AEGISM_SECTOR_WIDTH)) mod _bins };

// --- Who holds what: contacts another Site sensor saw just now ---
private _held = createHashMap;
{
    private _other = _x;
    if (_other != _vehicle && {((_other getVariable ["AEGISM_system", createHashMap]) getOrDefault ["hasSensor", false])}) then {
        {
            private _key = _x;
            if ((keys (_y getOrDefault ["sources", createHashMap])) findIf { _x != "passiveradar" && {time - ((_y get "sources") get _x) <= AEGISM_HELD_FOR} } != -1) then { _held set [_key, true]; };
        } forEach (_other getVariable ["AEGISM_pooledContacts", createHashMap]);
        (_other getVariable ["AEGISM_seenMunitions", [-1e9, createHashMap]]) params ["_readAt", "_munitions"];
        if (time - _readAt <= AEGISM_HELD_FOR) then { { _held set [_x, true]; } forEach _munitions; };
    };
} forEach _members;

// --- What it could look at: [bearing, elevation, weight, guided, object] ---
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
        // Where contacts have been (search weighting), whether or not it can look there.
        private _bearing = _eye getDir _pos;
        _axes set [_bearing call _fnBin, time];
        if (([_vehicle, _pos] call aegism_system_fnc_radarCovers) select 0) then {
            private _guided = _object in _guidedTargets;
            (_y getOrDefault ["tti", [1e10, time]]) params ["_tti", "_ttiAt"];
            private _weight = switch (true) do {
                case _guided: { AEGISM_W_GUIDED };
                case (_key in _claims): { AEGISM_W_ENGAGED };
                case !([_y] call aegism_fnc_hasTrack): { AEGISM_W_CUE };
                case (_y getOrDefault ["isMunition", false]): { AEGISM_W_MUNITION + 10 / (1 + ((_tti - (time - _ttiAt)) max 0)) };
                default { AEGISM_W_AIRCRAFT };
            };
            if (!_guided && {_key in _held}) then { _weight = _weight / 4; };
            // Another of the Site's radars is tracking it: left to that one
            // (not a target missiles are flying at -- fire control).
            (_tracks getOrDefault [_key, ["", -1]]) params ["_trackedBy", "_trackedUntil"];
            if (!_guided && {_trackedBy != ""} && {_trackedBy != _myId} && {time <= _trackedUntil}) then { _weight = _weight / 10; };
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
    private _count = 0;
    private _guidedCount = 0;
    private _heaviest = [-1, 0];
    {
        _x params ["_bearing", "_elevation", "_weight", "_guided"];
        if (abs ([_bearing, _centre] call _fnDiff) <= _hold) then {
            _score = _score + _weight;
            _count = _count + 1;
            if (_guided) then { _guidedCount = _guidedCount + 1; };
            if (_weight > (_heaviest select 0)) then { _heaviest = [_weight, _elevation]; };
        };
    } forEach _contacts;
    [_score, _count, _guidedCount, _heaviest select 1]
};
// [score, bearing, contacts held, guided held, elevation].
private _window = [0, _beam get "bearing", 0, 0, 0];
if (_contacts isNotEqualTo []) then {
    private _centres = [];
    { _centres append [_x select 0, (_x select 0) + _hold, (_x select 0) - _hold]; } forEach _contacts;
    {
        private _centre = (_x + 360) mod 360;
        (_centre call _fnWindow) params ["_score", "_count", "_guidedCount", "_elevation"];
        if (_score > (_window select 0)) then { _window = [_score, _centre, _count, _guidedCount, _elevation]; };
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

// --- Where to search ---
([_vehicle, _turretPath] call aegism_intercept_fnc_turretConfig) params ["", "", "", "_minElev", "_maxElev", "", "_traverseRate"];
private _pitch = (((_verticalArc min 180) / 4) max _minElev) min _maxElev;
private _span = floor (_half / AEGISM_SECTOR_WIDTH);
private _step = (_arc * 0.75) max AEGISM_SECTOR_WIDTH;
// Seconds its turret takes to swing from where it points to a bearing.
private _fnSlew = { (abs ([_this, _beam get "bearing"] call _fnDiff)) / (_traverseRate max 1) };
private _fnReachable = {
    ([_vehicle, _eye vectorAdd ([sin _this * cos _pitch, cos _this * cos _pitch, sin _pitch] vectorMultiply AEGISM_LOOK_DISTANCE)] call aegism_system_fnc_radarCovers) select 0
};
// How long since the arc centred on a bearing was searched, on average.
private _fnAge = {
    private _centreBin = _this call _fnBin;
    private _sum = 0;
    for "_j" from (_centreBin - _span) to (_centreBin + _span) do { _sum = _sum + ((time - (_sectors select ((_j + _bins) mod _bins))) min AEGISM_THREAT_MEMORY); };
    _sum / (2 * _span + 1)
};
private _fnThreatAxis = {
    private _centreBin = _this call _fnBin;
    private _found = false;
    for "_j" from (_centreBin - _span) to (_centreBin + _span) do { if (time - (_axes select ((_j + _bins) mod _bins)) <= AEGISM_THREAT_MEMORY) exitWith { _found = true; }; };
    _found
};
// Clear of where the Site's other narrow radars are looking (their beams,
// swinging there or already there), so two don't search one arc together.
private _fnClear = {
    private _centre = _this;
    (_otherBeams findIf { abs ([_centre, _x select 0] call _fnDiff) < AEGISM_BEAM_SEPARATION * (_half + (_x select 1)) }) == -1
};
// The sweep's next sector: one step on round, past any another radar of the
// Site is looking at or has just searched, and any its turret can't reach.
// (If every one is taken, the next one clear of the others' beams; failing
// that, simply the next step.)
private _fnNextSweep = {
    private _found = -1;
    {
        private _test = _x;
        private _next = _beam get "sweep";
        for "_i" from 1 to (ceil (360 / _step)) do {
            _next = (_next + _step) mod 360;
            if ((_next call _fnReachable) && {_next call _test}) exitWith { _found = _next; };
        };
        if (_found >= 0) exitWith {};
    } forEach [{ (_this call _fnClear) && {(_this call _fnAge) >= AEGISM_SECTOR_FRESH} }, { _this call _fnClear }];
    [_found, ((_beam get "sweep") + _step) mod 360] select (_found < 0)
};

// --- Choose its task ---
private _task = _beam get "task";
private _until = _beam get "taskUntil";
private _searchBearing = -1;
private _why = "";
switch (true) do {
    case (_guidedCount > 0): { _task = "fire control"; _until = time; };
    // Something worth tracking: track, with a look either side of it every
    // so often (only while emitting: a silent radar searches nothing).
    case (_trackScore >= AEGISM_TRACK_MIN): {
        if (_task == "search" && {time < _until}) exitWith {};
        if (_emitting && {_task == "track"} && {time >= _until} && {time - (_beam get "lastSearchAt") >= AEGISM_SEARCH_REVISIT}) exitWith {
            // The older of the two arcs beside its track (one clear of the
            // other radars' beams first): a short swing, and back before the
            // track is lost.
            private _sides = [_trackBearing + _step, _trackBearing - _step] apply { (_x + 360) mod 360 } select { _x call _fnReachable };
            if (_sides isEqualTo []) exitWith {};
            _sides = _sides apply { [parseNumber (_x call _fnClear), _x call _fnAge, _x] };
            _sides sort false;
            _task = "search";
            _searchBearing = (_sides select 0) select 2;
            _why = "beside its track";
        };
        if (_task != "track") then { _until = time + (_trackBearing call _fnSlew) + AEGISM_TRACK_DWELL; };
        _task = "track";
    };
    default {
        if (_task != "search" || {_emitting && {time >= _until}}) then {
            // Back to the sweep from wherever it is.
            if ((_beam getOrDefault ["kind", ""]) != "sweep") then { _beam set ["sweep", _beam get "bearing"]; };
            _searchBearing = call _fnNextSweep;
            _beam set ["sweep", _searchBearing];
            _why = "sweep";
        };
        _task = "search";
    };
};
if (_searchBearing >= 0) then {
    // Dwells once it's there; twice as long towards bearings threats came from.
    private _slew = _searchBearing call _fnSlew;
    private _dwell = AEGISM_SEARCH_DWELL * ([1, 2] select (_searchBearing call _fnThreatAxis));
    _until = time + _slew + _dwell;
    _beam set ["dwellFrom", time + _slew];
    _beam set ["bearing", _searchBearing];
    _beam set ["kind", _why];
    _beam set ["lastSearchAt", time];
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " RADAR-TASK: %1 searches %2 deg (%3) -- %4s swing, then %5s; %6.", _vehicle, round _searchBearing, _why,
            (round (_slew * 10)) / 10, _dwell, ["silent, pointing only", "emitting"] select _emitting];
    };
};
if (_task != (_beam get "task") && {_task != "search"}) then {
    _beam set ["kind", _task];
    _beam set ["dwellFrom", time + (_trackBearing call _fnSlew)];
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " RADAR-TASK: %1 %2 %3 contact(s) at %4 deg (%5).", _vehicle, ["tracks", "holds for fire control"] select (_task == "fire control"),
            _trackCount, round _trackBearing, (_contacts select { abs ([_x select 0, _trackBearing] call _fnDiff) <= _hold }) apply { typeOf (_x select 4) }];
    };
};
_beam set ["task", _task];
_beam set ["taskUntil", _until];

// --- Point it ---
private _aimAt = [];
if (_task in ["track", "fire control"]) then {
    _beam set ["bearing", _trackBearing];
    _aimAt = _eye vectorAdd ([sin _trackBearing * cos _trackElevation, cos _trackBearing * cos _trackElevation, sin _trackElevation] vectorMultiply AEGISM_LOOK_DISTANCE);
    _beam set ["text", format ["%1 %2 (%3 deg)", ["TRACK", "FIRE CONTROL"] select (_task == "fire control"), _trackCount, round _trackBearing]];
} else {
    private _bearing = _beam get "bearing";
    _aimAt = _eye vectorAdd ([sin _bearing * cos _pitch, cos _bearing * cos _pitch, sin _pitch] vectorMultiply AEGISM_LOOK_DISTANCE);
    _beam set ["text", format ["SEARCH %1 deg%2", round _bearing, ["", " (swinging)"] select (time < (_beam getOrDefault ["dwellFrom", -1]))]];
};
[_vehicle, _turretPath, _aimAt] call aegism_intercept_fnc_lockTurret;

// --- What the Site's narrow radars have searched: this one's beam while it
// emits, once it's there. (Not a 360-degree radar's: everything would always
// be fresh, and a narrow radar -- usually the longer-reaching -- would stop
// moving.) ---
if (_emitting && {time >= (_beam getOrDefault ["dwellFrom", -1])}) then {
    private _centreBin = (_beam get "bearing") call _fnBin;
    for "_j" from (_centreBin - _span) to (_centreBin + _span) do { _sectors set [(_j + _bins) mod _bins, time]; };
};

// --- Its beam and tracks, for the Site's other radars (see above) ---
_beams set [_myId, [_vehicle, _beam get "bearing", _half, time + AEGISM_CLAIM_FOR]];
{ if (time > ((_y select 1) + AEGISM_CLAIM_FOR)) then { _tracks deleteAt _x; }; } forEach +_tracks;
if (_task in ["track", "fire control"]) then {
    {
        _x params ["_bearing", "", "", "", "", "_key"];
        (_tracks getOrDefault [_key, ["", -1]]) params ["_trackedBy", "_trackedUntil"];
        if (abs ([_bearing, _trackBearing] call _fnDiff) <= _hold && {_trackedBy in ["", _myId] || {time > _trackedUntil}}) then {
            _tracks set [_key, [_myId, time + AEGISM_CLAIM_FOR]];
        };
    } forEach _contacts;
};

