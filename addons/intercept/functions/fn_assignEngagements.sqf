/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_assignEngagements

Description:
    Site-level engagement coordinator, run once per Site every 0.5s on the
    server -- at once for a munition close to impact that has just come into
    the picture (aegism_network_fnc_moduleInit).
    Full notes: docs/functions/intercept.md

Parameters:
    _logic - the Site logic <OBJECT>

Returns:
    Nothing

Examples:
    [_site] call aegism_intercept_fnc_assignEngagements;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"
#include "..\..\main\rpt.hpp"
#include "..\..\main\coordinator.hpp"
#include "..\plan.hpp"

#define AEGISM_INTERCEPTOR_SETTLE 1.5
// A launcher's salvo is away but no missile ever left it this long after its
// last fire command (a FIRE-FAILED its shot count wasn't taken back for):
// released.
#define AEGISM_NO_LAUNCH_TIMEOUT 5
#define AEGISM_CIWS_IDLE_GRACE 8
// A gun crew's reaction is capped at this (automated fire control), as its
// engagement loop applies it (aegism_intercept_fnc_engagementLoop).
#define AEGISM_CIWS_REACTION_CAP 1
#define AEGISM_NEVER_FIRED_TIMEOUT 15
#define AEGISM_CIWS_OVERRIDE_RANGE_FRACTION 0.4
#define AEGISM_SIZE_TIE_TOLERANCE 50
#define AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD 3
// _fnLauncherEta: the launcher has no missile left for this contact.
#define AEGISM_NO_ROUND 1e10
// A launcher's claim its turret is already working keeps its place on the
// queue ahead of contacts impacting up to this many seconds sooner.
#define AEGISM_WORKING_LEAD 5
// A launcher is only given a munition it can fire at in time; one it has
// is kept until it's later than this, then handed off or released.
#define AEGISM_LATE_MARGIN 0.5
// The Site's Warning Lasts After Last Shot default (aegism_intercept_fnc_
// engagementLoop's in-combat window).
#define AEGISM_LIVE_WINDOW_DEFAULT 10
// The layered reserve stops holding back for a munition the cheaper tier was
// planned to fire at this long ago and hasn't (RESERVE-MISSED).
#define AEGISM_RESERVE_GRACE 3
// A threat munition this close to impact with no weapon on it is logged
// (UNENGAGED), once. (At 20 s a high-arc rocket is still several kilometres
// up and out, out of every short-range launcher's reach, as it should be.)
#define AEGISM_UNENGAGED_TTI 10
// The layered reserve holds a longer-reach launcher back only if it could
// still fire this long after the cheaper tier's planned intercept (the
// interceptor's settle, then a reaction) and meet the munition in time.
#define AEGISM_RESERVE_RELOOK 3
#define AEGISM_GRAVITY 9.80665

params ["_logic"];

if (isNull _logic) exitWith {};

// Set again at the end if this run leaves launcher shots to be worked out
// before the next (those of the munitions whose look it put off).
_logic setVariable ["AEGISM_assignMore", false, false];

private _startedAt = diag_tickTime;
// Counts this run for the PERF line.
private _fnPerf = {
    private _ms = (diag_tickTime - _startedAt) * 1000;
    PERF_INC(PERF_COORD_RUNS);
    PERF_ADD(PERF_COORD_MS,_ms);
    AEGISM_perfCounts set [PERF_COORD_MAX_MS, (AEGISM_perfCounts select PERF_COORD_MAX_MS) max _ms];
};
// And its parts: the time since the last part ended goes to counter _this.
private _partFrom = _startedAt;
private _fnPerfPart = {
    PERF_ADD(_this,(diag_tickTime - _partFrom) * 1000);
    _partFrom = diag_tickTime;
};

private _engagementSettings = _logic getVariable "AEGISM_engagement";
if (isNil "_engagementSettings") exitWith {
    if (_logic getVariable ["AEGISM_lastAssignWarning", ""] != "no-engagement-settings") then {
        _logic setVariable ["AEGISM_lastAssignWarning", "no-engagement-settings", false];
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " WARNING: Site %1 has no AEGISM_engagement set -- cannot assign engagements.", _logic];
    };
};

[_logic] call aegism_detect_fnc_pruneStaleContacts;

// A Site linked to others coordinates the whole group's vehicles
// (aegism_network_fnc_linkSites); its pool and claims are the group's.
private _members = _logic getVariable ["AEGISM_groupMembers", _logic getVariable ["AEGISM_networkMembers", []]];
private _pool = _logic getVariable ["AEGISM_pooledContacts", createHashMap];
private _claims = _logic getVariable ["AEGISM_claims", createHashMap];

private _fnHeight = { (ASLToAGL (getPosASL _this)) select 2 };

// A member vehicle's own resolved settings (Site + its overrides).
private _fnSettings = {
    private _settings = _this getVariable "AEGISM_resolvedEngagementSettings";
    if (isNil "_settings") then { _settings = [_this] call aegism_system_fnc_resolveEngagementSettings; };
    _settings
};

// Classes the Site pool holds: the Site's allowlist plus any class a live
// member's override adds (that member alone will engage it).
private _allowlist = +(_engagementSettings getOrDefault ["targetClassAllowlist", []]);
{
    if (!isNull _x && {alive _x}) then {
        { _allowlist pushBackUnique _x; } forEach ((_x call _fnSettings) getOrDefault ["targetClassAllowlist", []]);
    };
} forEach _members;
// Every Site of a linked group: each one's sensors add to the group's pool.
{ _x setVariable ["AEGISM_contactAllowlist", _allowlist, false]; } forEach (_logic getVariable ["AEGISM_linkSites", [_logic]]);

// --- 2. Review existing assignments ---------------------------------------
// Turrets committed to contacts, indexed by turret ([system netId, turret
// path]) -> [[contactKey, role, holding, roundsNeeded, working, lastDitch],
// ...]. "holding" = still needs the turret: always for a gun; for a launcher
// only until its salvo is away (its missiles then guide themselves and the
// launcher is free for its next target). roundsNeeded = missiles the claim
// still has to fire (0 for a gun). "working" = the launcher claim its turret
// is on now (aegism_intercept_fnc_engagementLoop), kept ahead on its queue
// (AEGISM_WORKING_LEAD). "lastDitch" = a gun's shot with less than its
// Minimum Firing Window (see the last-ditch pass), which it drops for a
// contact it has its full window on. Indexed so the conflict and queue
// checks look at one turret's claims, not the whole Site's for every
// candidate: with ~30 contacts, 8 weapons and 40 claims that was ~10,000
// checks a run.
private _busy = createHashMap;
private _fnBusyAdd = {
    params ["_system", "_turretPath", "_contactKey", "_role", "_holding", "_rounds", ["_working", false], ["_lastDitch", false]];
    private _key = [netId _system, _turretPath];
    private _list = _busy get _key;
    if (isNil "_list") then { _list = []; _busy set [_key, _list]; };
    _list pushBack [_contactKey, _role, _holding, _rounds, _working, _lastDitch];
};
private _fnBusyRemove = {
    params ["_system", "_turretPath", "_contactKey"];
    private _list = _busy getOrDefault [[netId _system, _turretPath], []];
    private _index = _list findIf { (_x select 0) == _contactKey };
    if (_index != -1) then { _list deleteAt _index; };
};
// A gun drops its last-ditch shot for _newTarget, a contact it has its full
// firing window (_window s) on (see the last-ditch pass).
private _fnDropLastDitch = {
    params ["_system", "_turretPath", "_newTarget", "_window"];
    private _key = [netId _system, _turretPath];
    private _list = _busy getOrDefault [_key, []];
    private _fnIsLastDitch = { (_this select 1) == "ciws" && {_this param [5, false]} };
    {
        private _bKey = _x select 0;
        private _records = _claims getOrDefault [_bKey, []];
        private _index = _records findIf { (_x get "role") == "ciws" && {(_x get "system") == _system} && {((_x get "weaponInfo") select 0) isEqualTo _turretPath} };
        if (_index != -1) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ASSIGN-CLEAR: %1 (ciws) released %2 -- a last-ditch shot, dropped for %3, which it has %4s to fire at.",
                _system, (_records select _index) get "target", _newTarget, round (_window * 10) / 10];
            _records deleteAt _index;
            if (_records isEqualTo []) then { _claims deleteAt _bKey; };
        };
    } forEach (_list select { _x call _fnIsLastDitch });
    _busy set [_key, _list select { !(_x call _fnIsLastDitch) }];
};

// Iterates a snapshot of the keys: entries are deleted/replaced below, which
// isn't safe while iterating the HashMap itself.
{
    private _contactKey = _x;
    private _records = _claims get _contactKey;
    private _entry = _pool getOrDefault [_contactKey, createHashMap];
    private _object = _entry getOrDefault ["object", objNull];

    if (isNull _object || {!alive _object} || {!((_entry getOrDefault ["class", ""]) in _allowlist)}) then {
        _claims deleteAt _contactKey;
    } else {
        private _kept = _records select {
            private _record = _x;
            private _system = _record get "system";
            private _role = _record get "role";
            private _weaponInfo = _record get "weaponInfo";
            private _lastShotAt = _record get "lastShotAt";
            private _alive = !isNull _system && {alive _system};
            private _systemSettings = if (_alive) then { _system call _fnSettings } else { createHashMap };
            // A launcher whose salvo is away isn't re-judged: its missiles are
            // flying, and releasing the claim then (the target crossing out of
            // the envelope) let another launcher fire at it on top of them.
            // Its claim ends when they're gone (missed, below).
            private _salvoAway = _role == "launcher" && {(_record get "roundsFired") >= (_systemSettings getOrDefault ["salvoSize", 1])};
            // Nor is a launcher's claim on a munition while it waits its turn
            // behind others on that launcher's queue ("queued", aegism_
            // intercept_fnc_engagementLoop) and is judged by its planned shot
            // ("planned", the hand-off check below): whether it could be
            // fired at NOW says nothing of its turn, and asking cost an
            // intercept solve for every queued claim on every run.
            private _waiting = _role == "launcher" && {!_salvoAway} && {_record getOrDefault ["planned", false]} && {(_record getOrDefault ["status", ""]) == "queued"};
            private _engage = [false, ""];
            if (_alive) then {
                _engage = if (_salvoAway || {_waiting}) then { [true, ""] } else { [_system, _role, _weaponInfo, _object, _systemSettings] call aegism_intercept_fnc_canEngage };
            };
            if (!_salvoAway && {!_waiting}) then {
                _record set ["flightTime", _engage param [2, 0]];
                // A gun cued onto it before it's in reach (aegism_intercept_
                // fnc_canEngage): its engagement loop holds, "cued".
                _record set ["cued", (_engage param [4, 0]) > 0];
            };

            private _unfiredLauncher = _role == "launcher" && {(_record get "roundsFired") == 0};

            private _reason = switch (true) do {
                case (!_alive): { "system dead" };
                case !((_entry get "class") in (_systemSettings getOrDefault ["targetClassAllowlist", []])): { format ["%1 not engaged by this vehicle (its settings)", _entry get "class"] };
                case !(_engage select 0): { _engage select 1 };
                case (_unfiredLauncher && {_record getOrDefault ["crewFailed", false]}): {
                    // Keep this launcher off the contact until its lost fire
                    // cycle is over, so another weapon gets the next try.
                    private _holdUntil = ([_system, _weaponInfo select 0] call aegism_intercept_fnc_turretState) getOrDefault ["holdUntil", CBA_missionTime];
                    _entry set ["avoid", ((_entry getOrDefault ["avoid", []]) select { (_x select 2) > CBA_missionTime }) + [[_system, _weaponInfo select 0, _holdUntil]]];
                    "crew failed to fire (reliability roll) -- re-tasking it to the rest of the Site"
                };
                case (_unfiredLauncher && {(_system magazineTurretAmmo [_weaponInfo select 2, _weaponInfo select 0]) <= 0}): { "launcher out of missiles" };
                // Missed only once a missile has actually left: a fire command
                // that fired nothing (aegism_intercept_fnc_fireWeapon,
                // FIRE-FAILED) isn't a miss -- a launcher firing into its
                // magazine reload had its targets released as missed.
                case (_role == "launcher" && {(_record get "roundsFired") >= (_systemSettings getOrDefault ["salvoSize", 1])} && {CBA_missionTime > _lastShotAt + AEGISM_INTERCEPTOR_SETTLE} && {(_record get "interceptors") isNotEqualTo []} && {((_record get "interceptors") findIf { !isNull _x && {alive _x} }) == -1}): { "missed (salvo spent, no interceptor still in flight)" };
                case (_role == "launcher" && {(_record get "roundsFired") >= (_systemSettings getOrDefault ["salvoSize", 1])} && {(_record get "interceptors") isEqualTo []} && {CBA_missionTime > _lastShotAt + AEGISM_NO_LAUNCH_TIMEOUT}): { "fired, but no missile ever left the launcher" };
                case (_role == "ciws" && {_lastShotAt >= 0} && {CBA_missionTime > _lastShotAt + AEGISM_CIWS_IDLE_GRACE}): { "CIWS idle" };
                // From when a launcher's claim reached the front of its queue
                // (a gun works every claim it has at once): one still waiting
                // its turn hasn't failed to fire.
                case (_lastShotAt < 0 && {CBA_missionTime > ([_record get "assignedAt", _record getOrDefault ["frontSince", 1e10]] select (_role == "launcher")) + AEGISM_NEVER_FIRED_TIMEOUT}): { "never fired (cannot bear or no LOS)" };
                default { "" };
            };

            if (_reason != "") then {
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ASSIGN-CLEAR: %1 (%2) released %3 -- %4.", _system, _role, _object, _reason];
                // A launcher gone from it: its launchers are looked at in
                // this run, whenever its next look was due (_asleep, below).
                if (_role == "launcher") then { _entry set ["launcherLookAt", 0]; _entry set ["launcherLookBy", 0]; };
            };
            _reason == ""
        };

        if (_kept isEqualTo []) then {
            _claims deleteAt _contactKey;
        } else {
            _claims set [_contactKey, _kept];
            {
                private _record = _x;
                private _isGun = (_record get "role") == "ciws";
                private _roundsNeeded = if (_isGun) then { 0 } else {
                    ((((_record get "system") call _fnSettings) getOrDefault ["salvoSize", 1]) - (_record get "roundsFired")) max 0
                };
                [_record get "system", (_record get "weaponInfo") select 0, _contactKey, _record get "role", _isGun || {_roundsNeeded > 0}, _roundsNeeded,
                    !_isGun && {_record getOrDefault ["working", false]}, _isGun && {_record getOrDefault ["lastDitch", false]}] call _fnBusyAdd;
            } forEach _kept;
        };
    };
} forEach (keys _claims);
PERF_COORD_REVIEW_MS call _fnPerfPart;

// --- Live weapons across every member ---------------------------------------
private _allWeapons = [];
{
    private _system = _x;
    if (!isNull _system && {alive _system}) then {
        private _systemData = _system getVariable "AEGISM_system";
        if (!isNil "_systemData") then {
            {
                private _role = _x;
                {
                    _x params ["_turretPath", "", "_magClass"];
                    if ((_system magazineTurretAmmo [_magClass, _turretPath]) > 0) then {
                        _allWeapons pushBack [_system, _role, _x];
                    };
                } forEach (_systemData getOrDefault [["launcherWeapons", "ciwsWeapons"] select (_role == "ciws"), []]);
            } forEach ["launcher", "ciws"];
        };
    };
} forEach _members;

if (_allWeapons isEqualTo []) exitWith {
    if (_logic getVariable ["AEGISM_lastAssignWarning", ""] != "no-weapons") then {
        _logic setVariable ["AEGISM_lastAssignWarning", "no-weapons", false];
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " WARNING: Site %1 has %2 member(s) but no live launcher/CIWS weapon (none adopted, dead, or out of ammo).", _logic, count _members];
    };
    _logic setVariable ["AEGISM_claims", _claims, false];
    { if (!isNull _x) then { _x setVariable ["AEGISM_assigned", nil, false]; }; } forEach _members;
};
_logic setVariable ["AEGISM_lastAssignWarning", "", false];

// --- 3. Assign free roles ----------------------------------------------------
private _withheldCiws = [];
// Munitions only last-ditch shots are left for: [contactKey, [[weapon (an
// _allWeapons entry), its eligibility entry], ...]] (the last-ditch pass).
private _lastDitch = [];

// Time to impact of every contact (aegism_intercept_fnc_timeToImpact), used
// for ordering, launcher queues, and in-time checks alike.
private _memberPositions = (_members select { !isNull _x && {alive _x} }) apply { getPosASL _x };
private _ttiByKey = createHashMap;
// Munitions whose launchers aren't looked at in this run. One that isn't
// urgent (further than AEGISM_URGENT_TTI from impact) is given a time for
// its next look when its launchers are (its "launcherLookAt", set where it's
// served below): shortly before the layered reserve has a launcher firing at
// it, or AEGISM_FAR_INTERVAL s on, whichever is sooner; AEGISM_FAR_INTERVAL s
// on if a launcher already has it; the next run if none has it and none is
// planned to. Until then it isn't planned again -- it keeps its place in the
// reserve plan as last worked out -- and it's left out of the launchers'
// sweep -- a rocket of a long-range salvo was in the air for 65 s
// and given to a short-range launcher 26 s from impact, and until then every
// one of them was planned against every launcher on every run (20 ms a run
// with 48 rockets and 11 launchers, 2026-10-06). Its guns are looked at as
// ever.
private _asleep = createHashMap;
// When the crew of the launcher the reserve plan has firing at a munition
// would have to start on it, s from now (this run's plan only).
private _planFire = createHashMap;
// Munitions due a look that can't be put off to a later run (the reserve
// plan puts off the rest once the run has worked out AEGISM_PLAN_STEPS new
// steps of launcher shots, below): those past the time their look had to
// come by (their "launcherLookBy", set with "launcherLookAt") -- one with no
// launcher and none planned for it, one whose planned launcher's crew has to
// start on it, one that has already waited AEGISM_FAR_INTERVAL s. A munition
// new to the coordinator can wait that long for its first look.
private _mustLook = createHashMap;
{
    private _object = _y getOrDefault ["object", objNull];
    if (!isNull _object && {alive _object}) then {
        private _tti = [_object, _y get "class", _memberPositions] call aegism_intercept_fnc_timeToImpact;
        _ttiByKey set [_x, _tti];
        if (_tti > AEGISM_URGENT_TTI && {_tti < 1e9} && {_y getOrDefault ["isMunition", false]}) then {
            if !("launcherLookAt" in _y) then {
                _y set ["launcherLookAt", CBA_missionTime];
                _y set ["launcherLookBy", CBA_missionTime + AEGISM_FAR_INTERVAL];
            };
            if (CBA_missionTime < (_y get "launcherLookAt")) then {
                _asleep set [_x, true];
            } else {
                if (CBA_missionTime >= (_y getOrDefault ["launcherLookBy", 0])) then { _mustLook set [_x, true]; };
            };
        };
        // Kept on the contact for the debug overlays (aegism_fnc_debugDraw).
        _y set ["tti", [_tti, CBA_missionTime]];
    };
} forEach _pool;

// Serve contacts in the Site's Target Priority order, so when threats
// outnumber free weapons the priority rule decides which get them. The
// default, Soonest Impact, works a salvo front to back.
private _priority = _engagementSettings getOrDefault ["targetPriority", "soonestImpact"];
private _orderedKeys = keys _ttiByKey;
if (_memberPositions isNotEqualTo [] && {count _orderedKeys > 1}) then {
    private _scored = _orderedKeys apply {
        private _entry = _pool get _x;
        private _object = _entry get "object";
        private _pos = getPosASL _object;
        private _nearest = _memberPositions select 0;
        private _nearestDist = 1e10;
        {
            private _dist = _pos distance _x;
            if (_dist < _nearestDist) then { _nearestDist = _dist; _nearest = _x; };
        } forEach _memberPositions;
        private _score = switch (_priority) do {
            case "nearest": { -_nearestDist };
            case "fastestClosing": { (velocity _object) vectorDotProduct (_pos vectorFromTo _nearest) };
            case "highestValue": { ([_entry get "class"] call aegism_intercept_fnc_threatValue) * 1e6 - _nearestDist };
            default { -(_ttiByKey get _x) };
        };
        [_score, _x]
    };
    _scored sort false;
    _orderedKeys = _scored apply { _x select 1 };
};

// One launcher turret's firing rhythm right now: [crew reaction s, cooldown
// s until it may fire again, shot spacing s, missiles left, missiles per
// target]. Reaction is none for an automated/UAV system. Cooldown is its
// shot interval since its last missile, a crew's lost fire cycle (turret
// state "holdUntil"), or its weapon's own reload, whichever ends latest.
// Shot spacing is
// the launcher's own MEASURED time per missile (turret state "spacing",
// aegism_intercept_fnc_engagementLoop), which includes lost reliability
// rolls and re-aiming between targets; before its first back-to-back shots
// it's estimated: its shot interval (aegism_intercept_fnc_launcherInterval),
// or the time its weapon really takes to ready a round if that's longer
// (measured, aegism_intercept_fnc_weaponReload), plus one interval for every
// fire cycle its crew's reliability is expected to lose per missile.
// (Planning on the bare interval queued RAM launchers ~2x deeper than they
// could fire, so the back of a salvo was left to them until too late.)
// Worked out once per launcher per run: nothing it depends on changes
// within a run.
// One vehicle's crew: [its crew modifiers (aegism_intercept_fnc_
// applyCrewModulation), whether it's in combat -- it or its Site fired within
// the Site's live window (Warning Lasts After Last Shot), when its crew's
// Reaction Once in Combat applies, as its engagement loop judges it (aegism_
// intercept_fnc_engagementLoop)]. Once per vehicle per run.
private _crewCache = createHashMap;
private _fnCrew = {
    params ["_candSystem"];
    private _cached = _crewCache get (netId _candSystem);
    if (!isNil "_cached") exitWith { _cached };
    private _mods = _candSystem getVariable "AEGISM_resolvedCrewMods";
    if (isNil "_mods") then {
        private _crew = _candSystem getVariable "AEGISM_resolvedCrew";
        if (isNil "_crew") then { _crew = [_candSystem] call aegism_system_fnc_resolveCrew; };
        _mods = [_crew, _candSystem] call aegism_intercept_fnc_applyCrewModulation;
    };
    private _candNetwork = _candSystem getVariable ["AEGISM_network", objNull];
    private _lastShotAt = (_candSystem getVariable ["AEGISM_lastShotAt", -1e9]) max (_candNetwork getVariable ["AEGISM_lastShotAt", -1e9]);
    private _liveWindow = if (isNull _candNetwork) then { AEGISM_LIVE_WINDOW_DEFAULT } else { ([_candNetwork] call aegism_fnc_siteSettingsSource) getVariable ["alarmHold", AEGISM_LIVE_WINDOW_DEFAULT] };
    _cached = [_mods, CBA_missionTime - _lastShotAt <= _liveWindow];
    _crewCache set [netId _candSystem, _cached];
    _cached
};
// A gun crew's reaction to a new target, as its engagement loop applies it:
// capped at AEGISM_CIWS_REACTION_CAP, then its Reaction Once in Combat.
private _fnGunReaction = {
    ([_this] call _fnCrew) params ["_mods", "_inCombat"];
    ((_mods get "reactionTime") min AEGISM_CIWS_REACTION_CAP) * ([1, _mods getOrDefault ["combatReactionMult", 1]] select _inCombat)
};

// Whether the contact being served (_targetPos, _speed) is too far for a gun
// to reach at all, by the gun's own bound (aegism_intercept_fnc_canEngage):
// the rounds' flight to its reach, plus its cue time and the largest lead
// correction its spotting holds, in which the contact closes at most speed x
// t + g t^2 / 2. Worked out once per gun per run, so a far contact costs a
// distance and a sum here instead of the gun's whole check, which says the
// same: every free gun was asked about every rocket in the sky on every run,
// about 0.1 ms a time.
private _gunSpans = createHashMap;
private _fnGunBeyond = {
    params ["_candSystem", "_candInfo", "_candSettings"];
    private _cacheKey = [netId _candSystem, _candInfo select 0, _candInfo select 1];
    private _cached = _gunSpans get _cacheKey;
    if (isNil "_cached") then {
        private _reach = _candInfo param [5, 0];
        ([_candInfo select 1, _candInfo select 2] call aegism_intercept_fnc_weaponKinematics) params ["", "_v0", "_k", "", "", "", "", "_lifetime"];
        private _span = -1;
        if (_reach > 0 && {_v0 > 0}) then {
            _span = if (_k > 0) then { ((exp ((_k * _reach) min 30)) - 1) / (_k * _v0) } else { _reach / _v0 };
            if (_lifetime > 0) then { _span = _span min _lifetime; };
            private _lead = 0;
            { _lead = _lead max (abs (_y param [0, 0])); } forEach (([_candSystem, _candInfo select 0] call aegism_intercept_fnc_turretState) getOrDefault ["corrections", createHashMap]);
            _span = _span + _lead + ((_candSettings getOrDefault ["ciwsCueAhead", 5]) max 0);
        };
        _cached = [eyePos _candSystem, _reach, _span];
        _gunSpans set [_cacheKey, _cached];
    };
    _cached params ["_eye", "_reach", "_span"];
    _span >= 0 && {(_eye distance _targetPos) > _reach + _speed * _span + 0.5 * AEGISM_GRAVITY * _span * _span}
};

private _timingCache = createHashMap;
private _fnLauncherTiming = {
    params ["_candSystem", "_weaponInfo"];
    _weaponInfo params ["_turretPath", "", "_magClass"];
    private _cacheKey = [netId _candSystem, _turretPath];
    private _cached = _timingCache get _cacheKey;
    if (!isNil "_cached") exitWith { _cached };
    private _settings = _candSystem call _fnSettings;
    ([_candSystem] call _fnCrew) params ["_mods", "_inCombat"];
    private _ts = [_candSystem, _turretPath] call aegism_intercept_fnc_turretState;
    private _interval = ([_candSystem, _weaponInfo, _settings] call aegism_intercept_fnc_launcherInterval) * (_mods get "shotIntervalMult");
    // Its weapon still loading its next magazine or readying its next round
    // (aegism_intercept_fnc_weaponReload): POOK's launchers reload for
    // minutes, and the engine shows the new magazine's count meanwhile.
    ([_candSystem, _turretPath, _weaponInfo select 1] call aegism_intercept_fnc_weaponReload) params ["", "_reloadWait", "", "", "_roundTime"];
    private _reliability = (_mods get "reliability") max 0.05;
    private _spacing = _ts getOrDefault ["spacing", (_interval max _roundTime) + _interval * (1 - _reliability) / _reliability];
    private _readyAt = (((_ts getOrDefault ["shotAt", -1e9]) + _interval) max (_ts getOrDefault ["holdUntil", -1e9])) max (CBA_missionTime + _reloadWait);
    // In combat, its crew's Reaction Once in Combat, as its engagement loop
    // applies it (aegism_intercept_fnc_engagementLoop): the full reaction
    // made it look slower than it was.
    private _reaction = _mods get "reactionTime";
    if (_inCombat) then { _reaction = _reaction * (_mods getOrDefault ["combatReactionMult", 1]); };
    _cached = [_reaction, (_readyAt - CBA_missionTime) max 0, _spacing, _candSystem magazineTurretAmmo [_magClass, _turretPath], (_settings getOrDefault ["salvoSize", 1]) max 1];
    _timingCache set [_cacheKey, _cached];
    _cached
};

// Seconds until one launcher turret can fire at a contact: crew reaction
// (what's left of it, for a contact it was given at _assignedAt), or its
// cooldown plus one shot spacing for every missile still to be fired on its
// queue for contacts ahead of it. AEGISM_NO_ROUND if those claims already
// use every missile it has left -- it used to be queued regardless, and a
// Patriot with 1 missile was given 3 rockets; the two it could never shoot
// at sat on it until the 15s never-fired timeout.
//
// Queue order (_fnQueuePlace): soonest impact first, but the claim the
// turret is already working (aegism_intercept_fnc_engagementLoop) counts as
// impacting AEGISM_WORKING_LEAD s sooner than it does -- it keeps its place
// unless something much more urgent comes.
private _fnQueuePlace = {
    params ["_tti", "_working"];
    _tti - ([0, AEGISM_WORKING_LEAD] select _working)
};
private _fnLauncherEta = {
    params ["_candSystem", "_weaponInfo", "_contactKey", "_tti", ["_assignedAt", CBA_missionTime]];
    ([_candSystem, _weaponInfo] call _fnLauncherTiming) params ["_reaction", "_cooldown", "_spacing", "_rounds"];
    private _queue = _busy getOrDefault [[netId _candSystem, _weaponInfo select 0], []];
    private _place = [_tti, (_queue findIf { (_x select 0) == _contactKey && {_x select 4} }) != -1] call _fnQueuePlace;
    private _roundsAhead = 0;
    {
        _x params ["_bKey", "_bRole", "_bHolding", "_bRounds", "_bWorking"];
        if (_bRole == "launcher" && {_bHolding} && {_bKey != _contactKey} && {([_ttiByKey getOrDefault [_bKey, 1e10], _bWorking] call _fnQueuePlace) < _place}) then {
            _roundsAhead = _roundsAhead + _bRounds;
        };
    } forEach _queue;
    if (_rounds <= _roundsAhead) exitWith { AEGISM_NO_ROUND };
    ((_assignedAt + _reaction - CBA_missionTime) max 0) max (_cooldown + _roundsAhead * _spacing)
};

// --- Layered reserve ---------------------------------------------------------
// Plays each launcher tier (same reach = same tier) forward over the
// incoming munitions, shortest reach first, and records for each munition
// the reach of the cheapest tier predicted to kill it in time
// (_coveredReach). A launcher with a longer reach than that holds its
// missiles for it (see the eligibility check below); a munition no cheaper
// tier can take in time -- the volume has saturated them -- is open to
// every launcher. The longest-reach tier itself isn't played: it only ever
// takes what the others can't.
//
// Per launcher the play uses its real rhythm (_fnLauncherTiming), its
// current queue (unfired claims occupy its next slots, soonest impact
// first), and, for each munition, the first moment a missile fired at it
// along its projected path meets it inside the envelope, before impact
// (_fnPlanShot). The munition goes to whichever of the tier's launchers would
// kill it soonest.

// [fireTime, interceptTime] (seconds from now) of the earliest shot from
// _start on that meets the munition before _tti, or [] if there's none
// (aegism_intercept_fnc_planShot, which keeps every answer in the Site's
// plan cache, "AEGISM_planCache").
//
// A run always gets its answer in full. What's counted is the new steps
// worked out for it (_plan select 2): past AEGISM_PLAN_STEPS of them the
// reserve plan puts off the munitions whose look can wait, and leaves their
// questions (_plan select 3) to be worked out between this run and the next
// (aegism_intercept_fnc_planAhead).
private _planCache = _logic getVariable "AEGISM_planCache";
if (isNil "_planCache") then { _planCache = createHashMap; _logic setVariable ["AEGISM_planCache", _planCache, false]; };
// This run's plan work: [cache, never cut short (-1), new steps worked out,
// questions for the frames before the next run].
private _plan = [_planCache, -1, 0, []];
private _fnPlanShot = { (_this + [_plan]) call aegism_intercept_fnc_planShot };

// Picks one weapon from the eligible list ([index in _allWeapons, flight
// time] pairs) for a contact. Returns [index in _allWeapons, seconds until it
// can fire, in time], index -1 if no launcher has a missile left for it.
//
//   gun - closest warhead size to the threat's (within AEGISM_SIZE_TIE_
//       TOLERANCE of the best), then nearest.
//   launcher - layered-defence doctrine, from each launcher's real values:
//       0. a missile left for it (_fnLauncherEta not AEGISM_NO_ROUND)
//       1. can fire IN TIME: _fnLauncherEta plus the missile's flight time
//          must beat the contact's time to impact
//       2. shortest reach first (weaponInfo maxRange, i.e. the missile's
//          own lock range): long-range interceptors are kept for threats
//          only they can reach. (If NO launcher is in time, the one that
//          would intercept soonest comes first -- and isn't given a
//          munition: LATE, below.)
//       3. most missiles left once its queue is served, so deep magazines
//          take the volume and like launchers share it
//       4. soonest ready, then closest warhead size, then nearest
//   Config "cost" is deliberately NOT used: it's an AI value weight, not a
//   price, and it's inverted for this (vanilla long-range SAM base 500,
//   short-range 1000). The old rule was warhead size alone, which sent
//   Patriots (30m blast) at MLRS rockets while a 21-round, 1-second RAM
//   launcher sat idle.
private _fnPickWeapon = {
    params ["_eligible", "_role", "_contactKey", "_contactSize", "_targetPos", "_timeToImpact"];

    if (_role == "ciws") exitWith {
        private _sizeDiffs = _eligible apply { abs ((((_allWeapons select (_x select 0)) select 2) select 3) - _contactSize) };
        private _minSizeDiff = selectMin _sizeDiffs;
        private _best = -1;
        private _bestDist = 1e10;
        {
            private _dist = (getPosASL ((_allWeapons select ((_eligible select _forEachIndex) select 0)) select 0)) distance _targetPos;
            if (_x <= _minSizeDiff + AEGISM_SIZE_TIE_TOLERANCE && {_dist < _bestDist}) then { _best = _forEachIndex; _bestDist = _dist; };
        } forEach _sizeDiffs;
        [(_eligible select _best) select 0, 0, true]
    };

    private _scored = _eligible apply {
        _x params ["_weaponIndex", "_flightTime"];
        (_allWeapons select _weaponIndex) params ["_candSystem", "", "_candInfo"];
        _candInfo params ["_turretPath", "", "_magClass", ["_size", 0], "", ["_reach", 0]];
        private _readyIn = [_candSystem, _candInfo, _contactKey, _timeToImpact] call _fnLauncherEta;
        private _inTime = (_readyIn + _flightTime) < _timeToImpact;
        // Missiles left once the claims on its queue are served. By its
        // magazine alone, of two RAM launchers side by side the one a single
        // missile ahead was given four rockets in a second -- the last fired
        // at 10 s later, 16 s from impact -- while the other had nothing to
        // fire at for 11 s (2026-10-06).
        private _committed = 0;
        {
            _x params ["_bKey", "_bRole", "_bHolding", "_bRounds"];
            if (_bRole == "launcher" && {_bHolding} && {_bKey != _contactKey}) then { _committed = _committed + _bRounds; };
        } forEach (_busy getOrDefault [[netId _candSystem, _turretPath], []]);
        private _rounds = (_candSystem magazineTurretAmmo [_magClass, _turretPath]) - _committed;
        [[1, 0] select _inTime, [_readyIn + _flightTime, _reach] select _inTime, -_rounds, _readyIn, abs (_size - _contactSize), (getPosASL _candSystem) distance _targetPos, _weaponIndex, _inTime]
    };
    _scored = _scored select { (_x select 3) < AEGISM_NO_ROUND };
    if (_scored isEqualTo []) exitWith { [-1, AEGISM_NO_ROUND, false] };
    _scored sort true;
    (_scored select 0) params ["", "", "", "_readyIn", "", "", "_weaponIndex", "_inTime"];
    [_weaponIndex, _readyIn, _inTime]
};

// Layered reserve plan (see above), munition key -> reach of the cheapest
// launcher tier predicted to kill it in time.
private _coveredReach = createHashMap;
private _launcherEntries = _allWeapons select { (_x select 1) == "launcher" };
private _tierReaches = [];
{ _tierReaches pushBackUnique ((_x select 2) select 5); } forEach _launcherEntries;
_tierReaches sort true;
// Plan scans for munitions that are gone.
{ if !((_x select 0) in _ttiByKey) then { _planCache deleteAt _x; }; } forEach (keys _planCache);
private _planKeys = (keys _ttiByKey) select {
    private _planEntry = _pool get _x;
    (_planEntry getOrDefault ["isMunition", false]) && {(_ttiByKey get _x) < 1e9} && {(_planEntry get "class") in _allowlist}
};
// --- Guns with munitions of their own -----------------------------------------
// A gun whose Engagement Mode is "planned" is the cheapest layer of all: the
// munitions it's planned for are left to it by every launcher, and it takes
// none a launcher has. Played forward like a launcher tier, soonest impact
// first: a munition is a gun's when the gun is free for it as it comes into
// reach (within a plan step) -- so it has the whole of its pass to fire at
// it -- and is then counted as busy with it for its Minimum Firing Window,
// and no less than one longest burst and its pause (my figure for a gun's
// time on one target: nothing measures it yet). The munitions between go to
// the launchers. A gun still on one when the next it was planned for comes
// into reach loses that one: it's the launchers' again (GUN-PLAN-RELEASED).
// Only reach and time are planned: a munition it then can't bear on is a
// leaker.
//
// Munition key -> the gun it's planned for.
private _gunPlanned = createHashMap;
// [system, weaponInfo, settings, free at (game time), eye, reach m, its
// rounds' flight to that s, time on one munition s]
private _plannedGuns = [];
{
    _x params ["_candSystem", "_candRole", "_candInfo"];
    if (_candRole == "ciws") then {
        private _candSettings = _candSystem call _fnSettings;
        if ((_candSettings getOrDefault ["ciwsMode", "overlap"]) == "planned") then {
            private _reach = ([_candSettings, _candInfo, "ciws"] call aegism_intercept_fnc_envelopeBounds) select 1;
            ([_candInfo select 1, _candInfo select 2] call aegism_intercept_fnc_weaponKinematics) params ["", "_v0", "_k", "", "", "", "", "_lifetime"];
            if (_reach > 0 && {_v0 > 0}) then {
                private _flight = if (_k > 0) then { ((exp ((_k * _reach) min 30)) - 1) / (_k * _v0) } else { _reach / _v0 };
                if (_lifetime > 0) then { _flight = _flight min _lifetime; };
                private _need = (_candSettings getOrDefault ["ciwsMinWindow", 3]) max ((_candSettings getOrDefault ["ciwsBurstMax", 5]) + (_candSettings getOrDefault ["ciwsBurstPause", 1]));
                _plannedGuns pushBack [_candSystem, _candInfo, _candSettings, CBA_missionTime, eyePos _candSystem, _reach, _flight, _need];
            };
        };
    };
} forEach _allWeapons;
if (_plannedGuns isNotEqualTo []) then {
    // When a gun's rounds can first meet a munition inside its reach (game
    // time; 1e12: not before it comes down): its projected path stepped
    // until it's inside, less the rounds' flight there. Kept on the contact
    // for AEGISM_PLAN_CACHE_MAX_AGE s.
    private _fnGunOpens = {
        params ["_gun", "_entry", "_tti"];
        _gun params ["_candSystem", "_candInfo", "", "", "_eye", "_reach", "_flight"];
        private _opens = _entry get "gunOpens";
        if (isNil "_opens") then { _opens = createHashMap; _entry set ["gunOpens", _opens]; };
        private _gunKey = [netId _candSystem, _candInfo select 0, _candInfo select 1];
        (_opens getOrDefault [_gunKey, [-1e9, 0]]) params ["_workedAt", "_opensAt"];
        if (CBA_missionTime - _workedAt <= AEGISM_PLAN_CACHE_MAX_AGE) exitWith { _opensAt };
        private _object = _entry get "object";
        private _p0 = getPosASL _object;
        private _v = velocity _object;
        private _drop = [0, 0.5 * AEGISM_GRAVITY] select ((_entry get "class") in ["artilleryShell", "rocket", "bomb"]);
        _opensAt = 1e12;
        private _t = 0;
        while {_t <= _tti} do {
            if ((_eye distance ((_p0 vectorAdd (_v vectorMultiply _t)) vectorDiff [0, 0, _drop * _t * _t])) <= _reach) exitWith {
                _opensAt = CBA_missionTime + ((_t - _flight) max 0);
            };
            _t = _t + AEGISM_RESERVE_PLAN_STEP;
        };
        _opens set [_gunKey, [CBA_missionTime, _opensAt]];
        _opensAt
    };
    private _gunKeys = _planKeys apply { [_ttiByKey get _x, _x] };
    _gunKeys sort true;
    {
        _x params ["_tti", "_key"];
        private _planEntry = _pool get _key;
        private _records = _claims getOrDefault [_key, []];
        // A launcher's already: never a planned gun's.
        if ((_records findIf { (_x get "role") == "launcher" }) == -1) then {
            // A planned gun on it already: it's that gun's, which is busy
            // with it for its time from when it could first fire at it.
            private _mine = -1;
            private _since = 0;
            {
                private _record = _x;
                if ((_record get "role") == "ciws") then {
                    private _index = _plannedGuns findIf { (_x select 0) == (_record get "system") && {((_x select 1) select 0) isEqualTo ((_record get "weaponInfo") select 0)} };
                    if (_index != -1) then { _mine = _index; _since = _record get "assignedAt"; };
                };
            } forEach _records;
            if (_mine != -1) then {
                private _gun = _plannedGuns select _mine;
                private _opensAt = ([_gun, _planEntry, _tti] call _fnGunOpens) min (CBA_missionTime + _tti);
                _gun set [3, (_gun select 3) max ((_since max _opensAt) + (_gun select 7))];
                _gunPlanned set [_key, _gun select 0];
            } else {
                private _class = _planEntry get "class";
                private _best = -1;
                private _bestOpens = 1e12;
                {
                    _x params ["", "", "_candSettings", "_freeAt", "", "", "", "_need"];
                    if (_class in (_candSettings getOrDefault ["targetClassAllowlist", []])) then {
                        private _opensAt = [_x, _planEntry, _tti] call _fnGunOpens;
                        if (_freeAt <= _opensAt + AEGISM_RESERVE_PLAN_STEP && {(CBA_missionTime + _tti) - (_opensAt max _freeAt) >= _need} && {_opensAt < _bestOpens}) then {
                            _best = _forEachIndex;
                            _bestOpens = _opensAt;
                        };
                    };
                } forEach _plannedGuns;
                if (_best != -1) then {
                    private _gun = _plannedGuns select _best;
                    _gun set [3, (_bestOpens max (_gun select 3)) + (_gun select 7)];
                    _gunPlanned set [_key, _gun select 0];
                };
            };
        };
        if (_key in _gunPlanned) then {
            // No launcher's: its place in the launchers' plan goes.
            _planEntry deleteAt "reserveSlot";
            _planEntry deleteAt "reserveFireAt";
            if ((_planEntry getOrDefault ["gunPlannedFor", objNull]) != (_gunPlanned get _key)) then {
                _planEntry set ["gunPlannedFor", _gunPlanned get _key];
                if (AEGISM_RPT_VERBOSE) then {
                    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " GUN-PLAN: %1 (%2, impact in %3s) -- planned for %4's gun (Engagement Mode: Planned); the launchers leave it to it.",
                        _planEntry get "object", _planEntry get "class", round _tti, _gunPlanned get _key];
                };
            };
        } else {
            if ("gunPlannedFor" in _planEntry) then {
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " GUN-PLAN-RELEASED: %1 (%2, impact in %3s) -- %4's gun isn't free for it as planned; open to the launchers.",
                    _planEntry get "object", _planEntry get "class", round _tti, _planEntry get "gunPlannedFor"];
                _planEntry deleteAt "gunPlannedFor";
                // Its launchers are looked at in this run.
                _planEntry set ["launcherLookAt", 0];
                _planEntry set ["launcherLookBy", 0];
                _asleep deleteAt _key;
                _mustLook set [_key, true];
            };
        };
    } forEach _gunKeys;
    _planKeys = _planKeys select { !(_x in _gunPlanned) };
};

// The plan only decides which launchers may take a FREE munition: with none
// free that's looked at in this run (_asleep), there's nothing to plan.
private _anyFree = (_planKeys findIf { !(_x in _asleep) && {((_claims getOrDefault [_x, []]) findIf { (_x get "role") == "launcher" }) == -1} }) != -1;
if (count _tierReaches > 1 && {_anyFree}) then {
    _planKeys = _planKeys apply { [_ttiByKey get _x, _x] };
    _planKeys sort true;
    _planKeys = _planKeys apply { _x select 1 };
    // Munitions the plan has looked at in this run (one isn't put off part
    // way through the tiers).
    private _looked = createHashMap;

    {
        private _tierReach = _x;
        // Played launcher: [system, weaponInfo, settings, next free s, missiles
        // left, shot spacing s, missiles per target, reaction s, envelope
        // bounds].
        private _played = (_launcherEntries select { ((_x select 2) select 5) == _tierReach }) apply {
            _x params ["_candSystem", "", "_candInfo"];
            private _candSettings = _candSystem call _fnSettings;
            ([_candSystem, _candInfo] call _fnLauncherTiming) params ["_reaction", "_cooldown", "_spacing", "_rounds", "_salvo"];
            [_candSystem, _candInfo, _candSettings, _cooldown, _rounds, _spacing, _salvo, _reaction, [_candSettings, _candInfo, "launcher"] call aegism_intercept_fnc_envelopeBounds]
        };
        private _settled = [];
        {
            private _key = _x;
            private _tti = _ttiByKey get _key;
            private _planEntry = _pool get _key;
            private _launcherClaim = (_claims getOrDefault [_key, []]) select { (_x get "role") == "launcher" };
            if (_launcherClaim isNotEqualTo []) then {
                // Already claimed. By one of this tier's launchers: it takes
                // that launcher's next slot(s). By a longer-reach tier's: left
                // for that tier's own pass. Never planned as a free munition.
                private _record = _launcherClaim select 0;
                if (((_record get "weaponInfo") select 5) <= _tierReach) then {
                    private _index = _played findIf { (_x select 0) == (_record get "system") && {((_x select 1) select 0) isEqualTo ((_record get "weaponInfo") select 0)} };
                    if (_index != -1) then {
                        private _state = _played select _index;
                        private _need = ((_state select 6) - (_record get "roundsFired")) max 0;
                        _state set [3, (_state select 3) + _need * (_state select 5)];
                        _state set [4, (_state select 4) - _need];
                    };
                    _settled pushBack _key;
                };
            } else {
                // Put off: the run has worked out AEGISM_PLAN_STEPS new steps
                // already, and this one's look can wait (it isn't in
                // _mustLook). It isn't looked at in this run -- as one asleep,
                // here and in the launchers' sweep -- and stays due. Its
                // questions of this tier's launchers are kept as they'd be
                // asked now, to be worked out before the next run (aegism_
                // intercept_fnc_planAhead), which then has them ready.
                if (!(_key in _asleep) && {!(_key in _mustLook)} && {!(_key in _looked)} && {_tti > AEGISM_URGENT_TTI} && {(_plan select 2) >= AEGISM_PLAN_STEPS}) then {
                    _asleep set [_key, true];
                    PERF_INC(PERF_COORD_PUT_OFF);
                    private _class = _planEntry get "class";
                    private _object = _planEntry get "object";
                    private _ballistic = _class in ["artilleryShell", "rocket", "bomb"];
                    {
                        _x params ["_candSystem", "_candInfo", "_candSettings", "_nextFree", "_rounds", "", "", "_reaction", "_bounds"];
                        if (_rounds > 0 && {_class in (_candSettings getOrDefault ["targetClassAllowlist", []])}) then {
                            (_plan select 3) pushBack [_candSystem, _candInfo, _bounds, _object, _ballistic, CBA_missionTime + (_nextFree max _reaction), CBA_missionTime + _tti, _key];
                        };
                    } forEach _played;
                };
                // One not looked at in this run (_asleep) isn't planned again,
                // but keeps the launcher slot its last plan gave it
                // ("reserveSlot": [tier, launcher, turret, firing at]), so the
                // munitions planned after it find that launcher taken. Left
                // out of the play altogether, every munition that was planned
                // found the tier free: the reserve never saw it saturated,
                // four Patriots fired 3 missiles instead of 12 -- from 27 s
                // out, not 50 -- and two RAM launchers fired 41 of their 42
                // (2026-10-06).
                if (_key in _asleep) exitWith {
                    (_planEntry getOrDefault ["reserveSlot", []]) params [["_slotReach", -1], ["_slotSystem", objNull], ["_slotTurret", []], ["_slotFireAt", 0]];
                    if (_slotReach == _tierReach) then {
                        private _index = _played findIf { (_x select 0) == _slotSystem && {((_x select 1) select 0) isEqualTo _slotTurret} };
                        if (_index != -1) then {
                            private _state = _played select _index;
                            private _salvo = (_state select 6) min (_state select 4);
                            _state set [3, ((_slotFireAt - CBA_missionTime) max (_state select 3)) + _salvo * (_state select 5)];
                            _state set [4, (_state select 4) - _salvo];
                            _coveredReach set [_key, _tierReach];
                            _settled pushBack _key;
                        };
                    };
                };
                _looked set [_key, true];
                _planEntry deleteAt "reserveSlot";
                private _object = _planEntry get "object";
                private _ballistic = (_planEntry get "class") in ["artilleryShell", "rocket", "bomb"];
                private _avoid = (_planEntry getOrDefault ["avoid", []]) select { (_x select 2) > CBA_missionTime };
                private _best = [];
                {
                    _x params ["_candSystem", "_candInfo", "_candSettings", "_nextFree", "_rounds", "", "", "_reaction", "_bounds"];
                    if (_rounds > 0
                        && {(_planEntry get "class") in (_candSettings getOrDefault ["targetClassAllowlist", []])}
                        && {(_avoid findIf { (_x select 0) == _candSystem && {(_x select 1) isEqualTo (_candInfo select 0)} }) == -1}) then {
                        private _shot = [_candSystem, _candInfo, _bounds, _object, _ballistic, _nextFree max _reaction, _tti, _key] call _fnPlanShot;
                        if (_shot isNotEqualTo [] && {_best isEqualTo [] || {(_shot select 1) < (_best select 1)}}) then {
                            _best = [_forEachIndex, _shot select 0, _shot select 1];
                        };
                    };
                } forEach _played;
                // Whether a longer-reach launcher would still have a shot at it
                // should this tier's miss: one that can fire once the tier's
                // intercept (_this s from now) has had AEGISM_RESERVE_RELOOK s
                // to show a miss, and still meet the munition before it comes
                // down.
                private _fnSecondShot = {
                    private _relookAt = _this + AEGISM_RESERVE_RELOOK;
                    (_launcherEntries findIf {
                        _x params ["_candSystem", "", "_candInfo"];
                        (_candInfo select 5) > _tierReach
                            && {(_planEntry get "class") in ((_candSystem call _fnSettings) getOrDefault ["targetClassAllowlist", []])}
                            && {(_avoid findIf { (_x select 0) == _candSystem && {(_x select 1) isEqualTo (_candInfo select 0)} }) == -1}
                            && {([_candSystem, _candInfo, [_candSystem call _fnSettings, _candInfo, "launcher"] call aegism_intercept_fnc_envelopeBounds,
                                _object, _ballistic, _relookAt, _tti, _key] call _fnPlanShot) isNotEqualTo []}
                    }) != -1
                };
                // A kill that leaves no such second shot is still this tier's
                // when that's only its queue: one of its launchers, with
                // nothing ahead of it, would kill the munition early enough.
                // The longer-reach launchers then step in only for what this
                // tier has no missile or no time left for. (At the 3.3 s a
                // missile they were measured at, two RAM launchers with 42
                // missiles had the time for 41 of the 44 rockets of a salvo
                // left to them; four Patriots fired 11 at it for the second
                // shot alone, 2026-10-06.)
                // If even a free launcher of this tier could only kill it that
                // late, the longer-reach launchers may take it now: a high-arc
                // rocket coming down steeply only falls back into a RAM's
                // reach in its last seconds -- planned to the RAMs there, it
                // held every Patriot back until no second shot was left.
                if (_best isNotEqualTo [] && {!((_best select 2) call _fnSecondShot)}) then {
                    private _queueOnly = (_played findIf {
                        _x params ["_candSystem", "_candInfo", "_candSettings", "_nextFree", "_rounds", "", "", "_reaction", "_bounds"];
                        _rounds > 0
                            && {_nextFree > _reaction}
                            && {(_planEntry get "class") in (_candSettings getOrDefault ["targetClassAllowlist", []])}
                            && {(_avoid findIf { (_x select 0) == _candSystem && {(_x select 1) isEqualTo (_candInfo select 0)} }) == -1}
                            && {
                                private _free = [_candSystem, _candInfo, _bounds, _object, _ballistic, _reaction, _tti, _key] call _fnPlanShot;
                                _free isNotEqualTo [] && {(_free select 1) call _fnSecondShot}
                            }
                    }) != -1;
                    if (!_queueOnly) then {
                        if !(_planEntry getOrDefault ["noFallbackLogged", false]) then {
                            _planEntry set ["noFallbackLogged", true];
                            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " RESERVE-RELEASED: %1 (%2, impact in %3s) -- the %4m launcher tier could only kill it %5s before impact, even with nothing ahead of it on a launcher, leaving the longer-reach launchers no second shot if it missed: they may take it now.",
                                _object, _planEntry get "class", round _tti, round _tierReach, round ((_tti - (_best select 2)) * 10) / 10];
                        };
                        _best = [];
                    };
                };
                if (_best isNotEqualTo []) then {
                    _best params ["_index", "_fireTime"];
                    private _state = _played select _index;
                    // The plan has this launcher firing at it at its first
                    // chance: nothing ahead of it, and the munition in reach as
                    // soon as its crew has reacted.
                    private _atOnce = (_state select 3) <= (_state select 7) && {_fireTime <= (_state select 7) + AEGISM_RESERVE_PLAN_STEP};
                    private _salvo = (_state select 6) min (_state select 4);
                    _state set [3, _fireTime + _salvo * (_state select 5)];
                    _state set [4, (_state select 4) - _salvo];
                    _coveredReach set [_key, _tierReach];
                    _planFire set [_key, _fireTime - (_state select 7)];
                    _planEntry set ["reserveSlot", [_tierReach, _state select 0, (_state select 1) select 0, CBA_missionTime + _fireTime]];
                    // When the plan has the tier firing at it, for the check
                    // that it does (RESERVE-MISSED, below): its latest
                    // estimate, until it has a launcher firing at its first
                    // chance -- from then that stands, or a plan that said
                    // "as soon as its crew has reacted" on every run would
                    // never be seen to fail. It used to be the plan's first
                    // estimate, made as the munition came into view a minute
                    // out, and that one is early: about 4 s for a RAM
                    // launcher and an MLRS rocket, and more with the game run
                    // at 2-4x, where the rockets' predicted impact slid 6 s
                    // during their flight -- the check then gave twelve
                    // rockets to the Patriots 25-32 s from impact, before a
                    // RAM launcher could reach them, and the Patriots ran dry
                    // (2026-10-06).
                    if (!_atOnce || {!("reserveFireAt" in _planEntry)}) then { _planEntry set ["reserveFireAt", CBA_missionTime + _fireTime]; };
                    _settled pushBack _key;
                };
            };
        } forEach _planKeys;
        _planKeys = _planKeys - _settled;
    } forEach (_tierReaches select [0, count _tierReaches - 1]);
};
PERF_COORD_RESERVE_MS call _fnPerfPart;

{
    private _contactKey = _x;
    private _entry = _pool get _contactKey;
    private _object = _entry get "object";
    private _class = _entry get "class";

    // A contact only passive radar hears is a bearing, not a track: it cues
    // the Site's radars (aegism_system_fnc_emconUpdate) but isn't assigned.
    if (!isNull _object && {alive _object} && {_class in _allowlist} && {[_entry] call aegism_fnc_hasTrack}) then {
        private _targetPos = getPosASL _object;
        private _speed = vectorMagnitude velocity _object;
        private _height = _object call _fnHeight;
        private _contactSize = [typeOf _object] call aegism_intercept_fnc_munitionSize;
        private _existing = _claims getOrDefault [_contactKey, []];
        private _hasLauncher = (_existing findIf { (_x get "role") == "launcher" }) != -1;
        private _hasCiws = (_existing findIf { (_x get "role") == "ciws" }) != -1;

        // A munition may be queued on a launcher still working an earlier
        // one; its time to impact bounds how long it can wait. Aircraft
        // aren't queued.
        private _isMunition = _entry getOrDefault ["isMunition", false];
        private _timeToImpact = _ttiByKey getOrDefault [_contactKey, 1e10];

        // HAND-OFF: a queued launcher claim (nothing fired yet) that can no
        // longer fire in time -- later than AEGISM_LATE_MARGIN: more urgent
        // contacts were queued ahead of it, or the launcher fires slower than
        // planned -- is offered to the other launchers. If one can make it, it
        // takes over (HANDOFF); otherwise it's released (LATE), so the turret
        // isn't swung onto a shot it can't make. Without this a claim sat on a
        // saturated launcher until its 15s never-fired timeout, and a Patriot
        // only got the back of the salvo when it was too late. The margin
        // keeps one at the edge from changing hands on every estimate.
        // Also runs when the launcher has no missile left for it (its ETA is
        // AEGISM_NO_ROUND): newer, more urgent contacts took its last ones.
        //
        // "In time" for a launcher that isn't ready yet is judged from when it
        // will be (_fnPlanShot): whether any shot from then on meets the
        // munition inside the envelope before impact. It used to be its wait
        // plus the flight of a shot fired NOW -- at a rocket still 11 km out,
        // 16 s, though by the time the launcher was free the rocket would be
        // close and the flight a few seconds: a Tor's queue lost 52 claims
        // that way in one salvo (2026-10-06), and each was a munition it could
        // have killed.
        private _ballistic = _class in ["artilleryShell", "rocket", "bomb"];
        private _handoff = [];
        // Its launchers aren't looked at in this run (_asleep, above): neither
        // its claim's hand-off nor a launcher for it.
        private _asleepNow = _contactKey in _asleep;
        if (_isMunition && {_hasLauncher} && {!_asleepNow}) then {
            private _index = _existing findIf { (_x get "role") == "launcher" && {(_x get "roundsFired") == 0} };
            if (_index != -1) then {
                private _record = _existing select _index;
                (_record get "weaponInfo") params ["_turretPath"];
                private _eta = [_record get "system", _record get "weaponInfo", _contactKey, _timeToImpact, _record get "assignedAt"] call _fnLauncherEta;
                // (The plan needs the launcher's reach: one with none known
                // keeps the old test.)
                private _bounds = [(_record get "system") call _fnSettings, _record get "weaponInfo", "launcher"] call aegism_intercept_fnc_envelopeBounds;
                // (Nor is there a plan for one that isn't coming down on the
                // Site, time to impact 1e10: no impact to land a shot before.)
                private _planned = _eta > AEGISM_RESERVE_PLAN_STEP && {_eta < AEGISM_NO_ROUND} && {(_bounds select 1) > 0} && {_timeToImpact < 1e9};
                // (For the review of this claim on the next run, above.)
                _record set ["planned", _planned];
                private _late = if (_planned) then {
                    ([_record get "system", _record get "weaponInfo", _bounds, _object, _ballistic, _eta, _timeToImpact + AEGISM_LATE_MARGIN, _contactKey] call _fnPlanShot) isEqualTo []
                } else {
                    _eta + (_record getOrDefault ["flightTime", 0]) >= _timeToImpact + AEGISM_LATE_MARGIN
                };
                if (_late) then {
                    _handoff = [_record, _eta, _planned];
                    _existing deleteAt _index;
                    [_record get "system", _turretPath, _contactKey] call _fnBusyRemove;
                    _hasLauncher = false;
                };
            };
        };

        {
            private _role = _x;
            private _covered = [_hasLauncher, _hasCiws] select (_role == "ciws");
            // A munition whose launchers aren't looked at in this run
            // (_asleep -- not due, or its look put off by the reserve plan):
            // no launcher is decided for it in this one. Its guns are.
            if (_role == "launcher" && {_asleepNow}) then { _covered = true; };
            // Nor for one planned for a gun (_gunPlanned): it's the gun's.
            if (_role == "launcher" && {_contactKey in _gunPlanned}) then { _covered = true; };

            if (!_covered) then {
                // [index in _allWeapons, flight time] of every weapon that can
                // take this contact. Recomputed per role: a winner may be
                // removed from _allWeapons before the next role is scored.
                //
                // Launchers skip it while (a) it's on their "avoid" list --
                // their crew just failed to fire at it, so another weapon gets
                // the next try -- or (b) they're held in layered reserve: a
                // cheaper tier is predicted to kill it in time.
                private _avoid = (_entry getOrDefault ["avoid", []]) select { (_x select 2) > CBA_missionTime };
                private _reserveReach = _coveredReach getOrDefault [_contactKey, -1];
                // The plan had a cheaper tier firing at it by now, and no
                // launcher has it: the plan was wrong -- a shot it judged
                // possible that no launcher of the tier could actually make (a
                // rocket coming down too steep for the RAMs held every Patriot
                // back until it was too late). The reserve doesn't hold for it
                // again (RESERVE-MISSED).
                if (_role == "launcher" && {_reserveReach > 0} && {!_hasLauncher}
                    && {CBA_missionTime > (_entry getOrDefault ["reserveFireAt", 1e10]) + AEGISM_RESERVE_GRACE}
                    && {!(_entry getOrDefault ["reserveMissed", false])}) then {
                    _entry set ["reserveMissed", true];
                    // Why each of the tier's launchers can't take it now -- where
                    // the plan and the launchers' own check disagree.
                    private _why = [];
                    {
                        _x params ["_candSystem", "_candRole", "_candInfo"];
                        if (_candRole == "launcher" && {(_candInfo select 5) == _reserveReach}) then {
                            private _engage = [_candSystem, "launcher", _candInfo, _object, _candSystem call _fnSettings] call aegism_intercept_fnc_canEngage;
                            _why pushBack format ["%1: %2", _candSystem, ["can engage it", _engage select 1] select !(_engage select 0)];
                        };
                    } forEach _allWeapons;
                    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " RESERVE-MISSED: %1 (%2, impact in %3s) -- %4: the reserve may take it. The tier's launchers now: %5.",
                        _object, _class, round _timeToImpact,
                        if ((_entry getOrDefault ["launcherAttempts", 0]) > 0) then {
                            format ["the %1m launcher tier's shot at it missed", round _reserveReach]
                        } else {
                            format ["the %1m launcher tier was to fire at it %2s ago and none of its launchers has it", round _reserveReach, round (CBA_missionTime - (_entry get "reserveFireAt"))]
                        }, _why joinString "; "];
                };
                if (_entry getOrDefault ["reserveMissed", false]) then { _reserveReach = -1; };
                private _held = [];
                private _eligible = [];
                // Launchers too late for this munition before the full check:
                // [seconds until it could fire, system].
                private _tooLate = [];
                {
                    _x params ["_candSystem", "_candRole", "_candInfo"];
                    if (_candRole == _role) then {
                        private _candSettings = _candSystem call _fnSettings;
                        // A gun needs its turret to itself. A launcher only
                        // conflicts with a gun on the same turret, or with
                        // its own claims when this contact can't be queued
                        // (an aircraft).
                        private _conflicts = (_busy getOrDefault [[netId _candSystem, _candInfo select 0], []]) select {
                            _x params ["_bKey", "_bRole", "_bHolding"];
                            _bKey != _contactKey && {_bHolding} && {_role == "ciws" || {_bRole == "ciws"} || {!_isMunition}}
                        };
                        private _conflict = _conflicts isNotEqualTo [];
                        // A gun on nothing but a last-ditch shot (the last-
                        // ditch pass, below) is free for a contact it has its
                        // full firing window on: it drops that shot for it.
                        private _preempts = _role == "ciws" && {_conflict} && {(_conflicts findIf { !(_x param [5, false]) }) == -1};
                        if (_preempts) then { _conflict = false; };
                        private _avoided = _role == "launcher" && {(_avoid findIf { (_x select 0) == _candSystem && {(_x select 1) isEqualTo (_candInfo select 0)} }) != -1};
                        private _reserved = _role == "launcher" && {_reserveReach > 0} && {(_candInfo select 5) > _reserveReach};
                        if (_reserved) then { _held pushBackUnique _candSystem; };
                        // A launcher the contact is plainly beyond is skipped
                        // before the full check: too far out for its missile
                        // to meet it inside its own reach (doctrine can only
                        // shorten it) -- in the missile's flight to the edge
                        // of it (aegism_intercept_fnc_missileFlightTime) the
                        // contact closes at most speed x t + g t^2 / 2. Only
                        // the meeting point has to be inside (aegism_
                        // intercept_fnc_canEngage): this used to be the
                        // contact's distance now against the reach alone, and
                        // RAM launchers that could meet a rocket at 5 km
                        // weren't offered it until it was there. The margin
                        // covers eyePos vs vehicle position.
                        // A free gun the same way, by the gun's own bound
                        // (_fnGunBeyond).
                        private _beyond = if (_role == "launcher") then {
                            private _reach = _candInfo select 5;
                            private _span = ([_candInfo, _reach] call aegism_intercept_fnc_missileFlightTime) max 0;
                            ((getPosASL _candSystem) distance _targetPos) > _reach + 50 + _speed * _span + 0.5 * AEGISM_GRAVITY * _span * _span
                        } else {
                            !_conflict && {[_candSystem, _candInfo, _candSettings] call _fnGunBeyond}
                        };
                        // A launcher whose own queue and reaction alone run
                        // past the munition's impact can't fire at it in
                        // time, whatever its missile's flight: skipped before
                        // the full check (_fnPickWeapon would turn it down).
                        // A salvo's unreachable rockets were otherwise
                        // re-solved against every launcher on every run:
                        // 18-27 ms runs in a jet's rocket attack.
                        private _queueReady = 0;
                        // Not ready yet: its shot at it from when it is
                        // ([fire in, intercept in] s, _fnPlanShot). None that
                        // lands in time inside its envelope -- the munition
                        // inside its minimum range by then, or too steep --
                        // and it isn't given it: its place goes to one it can
                        // kill. An S-300 with 30 s between missiles kept
                        // being handed the next rocket due, 26 of them out of
                        // its envelope by the time it could fire.
                        private _planShot = [];
                        private _noShot = false;
                        if (_role == "launcher" && {_isMunition} && {!_conflict} && {!_avoided} && {!_reserved} && {!_beyond}) then {
                            _queueReady = [_candSystem, _candInfo, _contactKey, _timeToImpact] call _fnLauncherEta;
                            if (_queueReady >= _timeToImpact) then {
                                _tooLate pushBack [_queueReady, _candSystem, false];
                            } else {
                                // (The plan needs the launcher's reach, and an
                                // impact to land before: without either it
                                // keeps the shot-fired-now test.)
                                private _bounds = [_candSettings, _candInfo, "launcher"] call aegism_intercept_fnc_envelopeBounds;
                                if (_queueReady > AEGISM_RESERVE_PLAN_STEP && {(_bounds select 1) > 0} && {_timeToImpact < 1e9} && {_class in (_candSettings getOrDefault ["targetClassAllowlist", []])}) then {
                                    _planShot = [_candSystem, _candInfo, _bounds, _object, _ballistic, _queueReady, _timeToImpact, _contactKey] call _fnPlanShot;
                                    if (_planShot isEqualTo []) then {
                                        _noShot = true;
                                        _tooLate pushBack [_queueReady, _candSystem, true];
                                    };
                                };
                            };
                        };
                        if (!_conflict && {!_avoided} && {!_reserved} && {!_beyond} && {!_noShot} && {_queueReady < _timeToImpact} && {_class in (_candSettings getOrDefault ["targetClassAllowlist", []])}) then {
                            // A gun: judged with its crew's reaction to a new
                            // target, for its firing window.
                            private _engage = [_candSystem, _role, _candInfo, _object, _candSettings, [0, _candSystem call _fnGunReaction] select (_role == "ciws")] call aegism_intercept_fnc_canEngage;
                            // [index in _allWeapons, flight time, cue time, full
                            // firing window, firing window s, why it's short,
                            // drops a last-ditch shot for it] -- one dropping a
                            // shot only for its full window.
                            private _full = (_engage param [6, ""]) == "";
                            if ((_engage select 0) && {!_preempts || _full}) then {
                                // Its flight: of a shot fired now, or, for a
                                // launcher not ready yet, from when it's ready
                                // to its planned intercept.
                                private _flight = if (_planShot isEqualTo []) then { _engage param [2, 0] } else { (_planShot select 1) - _queueReady };
                                _eligible pushBack [_forEachIndex, _flight, _engage param [4, 0], _full, _engage param [5, 1e10], _engage param [6, ""], _preempts];
                            };
                        };
                    };
                } forEach _allWeapons;

                if (_role == "launcher" && {_eligible isEqualTo []} && {_tooLate isNotEqualTo []} && {_handoff isEqualTo []} && {!(_entry getOrDefault ["lateLogged", false])}) then {
                    _entry set ["lateLogged", true];
                    // The soonest ready of them.
                    private _soonest = 0;
                    { if ((_x select 0) < ((_tooLate select _soonest) select 0)) then { _soonest = _forEachIndex; }; } forEach _tooLate;
                    (_tooLate select _soonest) params ["_soonestReady", "_soonestSystem", ["_noShotFrom", false]];
                    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " LATE: no launcher can fire at %1 in time (impact in %2s) -- the soonest, %3, %4. Left to the guns.",
                        _object, round (_timeToImpact * 10) / 10, _soonestSystem,
                        switch (true) do {
                            case (_soonestReady >= AEGISM_NO_ROUND): { "has no missile left for it" };
                            case _noShotFrom: { format ["is ready in ~%1s, and has no shot at it from then that lands in time inside its envelope", round (_soonestReady * 10) / 10] };
                            default { format ["is ready in ~%1s, before its missile's flight", round (_soonestReady * 10) / 10] };
                        }];
                };

                if (_held isNotEqualTo [] && {!(_entry getOrDefault ["reserveLogged", false])}) then {
                    _entry set ["reserveLogged", true];
                    if (AEGISM_RPT_VERBOSE) then {
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " RESERVE: %1 (%2, impact in %3s) -- the %4m launcher tier is predicted to kill it in time, holding %5.",
                            _object, _class, round _timeToImpact, round _reserveReach, _held];
                    };
                };

                // A gun beside the launchers (each gun's own Engagement
                // Mode): while a launcher has the contact, a last-resort gun
                // holds unless the contact is already deep inside its own
                // reach, and a planned gun holds whatever -- it has munitions
                // of its own (_gunPlanned).
                if (_role == "ciws" && {_hasLauncher} && {_eligible isNotEqualTo []}) then {
                    private _free = _eligible select {
                        (_allWeapons select (_x select 0)) params ["_candSystem", "", "_candInfo"];
                        switch ((_candSystem call _fnSettings) getOrDefault ["ciwsMode", "overlap"]) do {
                            case "planned": { false };
                            case "lastResort": { ((getPosASL _candSystem) distance _targetPos) <= (_candInfo select 5) * AEGISM_CIWS_OVERRIDE_RANGE_FRACTION };
                            default { true };
                        }
                    };
                    if (_free isEqualTo []) then { _withheldCiws pushBack [_contactKey, (_allWeapons select ((_eligible select 0) select 0)) select 0]; };
                    _eligible = _free;
                };

                // Guns with less than their Minimum Firing Window on it
                // (aegism_intercept_fnc_canEngage): a last-ditch shot. Left
                // for the last-ditch pass after every contact is served, so a
                // gun only spends its time on one with nothing better to do --
                // given rockets 2-5 s from impact one after another, a Cheetah
                // hit 2 of 21 and swung away from the rest of the volley.
                if (_role == "ciws" && {_eligible isNotEqualTo []}) then {
                    private _full = _eligible select { _x select 3 };
                    if (_full isEqualTo []) then {
                        private _candidates = (_eligible select { !(_x select 6) }) apply { [_allWeapons select (_x select 0), _x] };
                        if (_candidates isNotEqualTo []) then { _lastDitch pushBack [_contactKey, _candidates]; };
                    };
                    _eligible = _full;
                };

                if (_eligible isNotEqualTo []) then {
                    private _allowed = true;

                    if (_role == "launcher") then {
                        private _attempts = _entry getOrDefault ["launcherAttempts", 0];
                        if (_attempts >= AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD) then {
                            private _thisValue = [_class] call aegism_intercept_fnc_threatValue;
                            private _outranking = (keys _pool) select {
                                private _otherEntry = _pool get _x;
                                private _otherObject = _otherEntry get "object";
                                _x != _contactKey && {!isNull _otherObject} && {alive _otherObject}
                                    && {(_otherEntry get "class") in _allowlist}
                                    && {((_claims getOrDefault [_x, []]) findIf { (_x get "role") == "launcher" }) == -1}
                                    && {([_otherEntry get "class"] call aegism_intercept_fnc_threatValue) > _thisValue}
                            };
                            _allowed = _outranking isEqualTo [];
                            if (!_allowed) then {
                                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " RETRY-DECLINE: %1 (%2) has taken %3 launcher attempts -- %4 higher-value contact(s) unassigned.", _object, _class, _attempts, count _outranking];
                            };
                        };
                    };

                    ([_eligible, _role, _contactKey, _contactSize, _targetPos, _timeToImpact] call _fnPickWeapon) params ["_weaponIndex", "_readyIn", "_inTime"];
                    if (_allowed && {_weaponIndex >= 0}) then {
                        (_allWeapons select _weaponIndex) params ["_bestSystem", "_bestRole", "_bestInfo"];
                        (_eligible select (_eligible findIf { (_x select 0) == _weaponIndex })) params ["", "_flightTime", ["_cueIn", 0], "", ["_window", 1e10], "", ["_preempting", false]];

                        // A launcher only takes a munition it can fire at in
                        // time: given one it can't, it swung onto it while the
                        // shots it could make waited -- under a jet's rocket
                        // ripple a Patriot was given rockets it would fire at
                        // 8-12 s after their impact. Left to the guns (LATE).
                        // A hand-off only goes ahead if the new launcher is
                        // also actually a different one.
                        private _late = _role == "launcher" && {_isMunition} && {!_inTime};
                        private _isHandoff = _role == "launcher" && {_handoff isNotEqualTo []};
                        private _handoffUseful = _isHandoff && {!_late} && {
                            private _old = _handoff select 0;
                            (_old get "system") != _bestSystem || {((_old get "weaponInfo") select 0) isNotEqualTo (_bestInfo select 0)}
                        };
                        if (_late && {!_isHandoff} && {!(_entry getOrDefault ["lateLogged", false])}) then {
                            _entry set ["lateLogged", true];
                            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " LATE: no launcher can fire at %1 in time (impact in %2s) -- the soonest, %3, is ready in ~%4s + %5s flight. Left to the guns.",
                                _object, round (_timeToImpact * 10) / 10, _bestSystem, round (_readyIn * 10) / 10, round (_flightTime * 10) / 10];
                        };

                        if (!_late && {!_isHandoff || _handoffUseful}) then {
                            if (_role == "launcher") then {
                                if (!_isHandoff) then { _entry set ["launcherAttempts", (_entry getOrDefault ["launcherAttempts", 0]) + 1]; };
                                _hasLauncher = true;
                            } else {
                                _hasCiws = true;
                            };

                            if (_preempting) then { [_bestSystem, _bestInfo select 0, _object, _window] call _fnDropLastDitch; };
                            _existing pushBack createHashMapFromArray [
                                ["target", _object],
                                ["class", _class],
                                ["system", _bestSystem],
                                ["role", _bestRole],
                                ["weaponInfo", _bestInfo],
                                ["assignedAt", CBA_missionTime],
                                ["lastShotAt", -1],
                                ["roundsFired", 0],
                                ["interceptors", []],
                                ["flightTime", _flightTime],
                                ["cued", _cueIn > 0]
                            ];
                            [_bestSystem, _bestInfo select 0, _contactKey, _bestRole, true,
                                [0, ((_bestSystem call _fnSettings) getOrDefault ["salvoSize", 1]) max 1] select (_role == "launcher")] call _fnBusyAdd;
                            // A launcher taking munitions stays available for
                            // more this cycle -- it queues them (bounded by each
                            // one's time to impact, see _fnLauncherEta).
                            if (_role == "ciws" || {!_isMunition}) then { _allWeapons deleteAt _weaponIndex; };

                            if (_isHandoff) then {
                                _handoff params ["_old", "_oldEta", ["_oldPlanned", false]];
                                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " HANDOFF: %1 can't fire at %2 in time (%3) -- %4 (%5) takes it, fires in ~%6s.",
                                    _old get "system", _object,
                                    switch (true) do {
                                        case (_oldEta >= AEGISM_NO_ROUND): { "no missile left for it" };
                                        case _oldPlanned: { format ["ready in ~%1s, with no shot from then that lands inside its envelope before impact in %2s", round (_oldEta * 10) / 10, round (_timeToImpact * 10) / 10] };
                                        default { format ["ready in ~%1s + %2s flight vs impact in %3s", round (_oldEta * 10) / 10, round ((_old getOrDefault ["flightTime", 0]) * 10) / 10, round (_timeToImpact * 10) / 10] };
                                    },
                                    _bestSystem, _bestInfo select 1, round (_readyIn * 10) / 10];
                            } else {
                                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ASSIGN: %1 (%2, %3 %4) -> %5 (%6, %7m, %8m AGL)%9%10", _bestSystem, typeOf _bestSystem, _bestRole, _bestInfo select 1, _object, _class, round ((getPosASL _bestSystem) distance _targetPos), round _height,
                                    [["", format [", impact in %1s", round _timeToImpact]] select (_timeToImpact < 1e9), format [", fires in ~%1s, impact in %2s", round (_readyIn * 10) / 10, round _timeToImpact]] select (_role == "launcher" && {_readyIn > 0} && {_timeToImpact < 1e9}),
                                    ["", format [" -- cued: in reach within %1s, the crew reacts and the barrel comes onto it meanwhile", _cueIn]] select (_cueIn > 0)];
                                // A longer-reach launcher on a munition no cheaper
                                // tier can take in time: the reserve steps in.
                                if (_role == "launcher" && {_reserveReach < 0} && {count _tierReaches > 1} && {_isMunition} && {_timeToImpact < 1e9}
                                    && {(_bestInfo select 5) > (_tierReaches select 0)}) then {
                                    if (AEGISM_RPT_VERBOSE) then {
                                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SATURATION: %1 %2 (impact in %3s) -- %4 steps in from the reserve.",
                                            ["no shorter-range launcher can kill", "no shorter-range launcher's shot leaves a second chance at"] select (_entry getOrDefault ["noFallbackLogged", false]),
                                            _object, round _timeToImpact, _bestSystem];
                                    };
                                };
                            };
                        };
                    };
                };
            };

            // Hand-off found no launcher that can make it: released, so its
            // launcher's turret goes on to the shots it can make (it used to
            // be restored, and the turret swung onto a rocket it couldn't
            // fire at before impact, then back). Open to any weapon that
            // frees up in time.
            if (_role == "launcher" && {_handoff isNotEqualTo []} && {!_hasLauncher}) then {
                _handoff params ["_old", "_oldEta", ["_oldPlanned", false]];
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ASSIGN-CLEAR: %1 (launcher) released %2 -- %3, and no other launcher can take it in time.", _old get "system", _object,
                    switch (true) do {
                        case (_oldEta >= AEGISM_NO_ROUND): { "no missile left for it (its queue is deeper than its magazine)" };
                        case _oldPlanned: { format ["can't kill it in time (ready in ~%1s, with no shot from then that lands inside its envelope before impact in %2s)", round (_oldEta * 10) / 10, round (_timeToImpact * 10) / 10] };
                        default { format ["can't fire at it in time (ready in ~%1s + %2s flight vs impact in %3s)", round (_oldEta * 10) / 10, round ((_old getOrDefault ["flightTime", 0]) * 10) / 10, round (_timeToImpact * 10) / 10] };
                    }];
            };
        } forEach ["launcher", "ciws"];

        // A threat coming down with no weapon on it at all: why each weapon
        // isn't, once (UNENGAGED) -- held in reserve, out of its reach, too
        // late, or whatever its own check says.
        if (_isMunition && {_existing isEqualTo []} && {_timeToImpact <= AEGISM_UNENGAGED_TTI} && {!(_entry getOrDefault ["unengagedLogged", false])}) then {
            _entry set ["unengagedLogged", true];
            private _cover = [_coveredReach getOrDefault [_contactKey, -1], -1] select (_entry getOrDefault ["reserveMissed", false]);
            private _why = _allWeapons apply {
                _x params ["_candSystem", "_candRole", "_candInfo"];
                private _candSettings = _candSystem call _fnSettings;
                format ["%1 %2: %3", _candSystem, ["missile", "gun"] select (_candRole == "ciws"), switch (true) do {
                    case !(_class in (_candSettings getOrDefault ["targetClassAllowlist", []])): { "not a class it engages" };
                    case (_candRole == "launcher" && {_contactKey in _gunPlanned}): { format ["left to %1's gun (planned for it)", _gunPlanned get _contactKey] };
                    case (_candRole == "launcher" && {_cover > 0} && {(_candInfo select 5) > _cover}): { format ["held in reserve for the %1m tier", round _cover] };
                    default {
                        private _engage = [_candSystem, _candRole, _candInfo, _object, _candSettings] call aegism_intercept_fnc_canEngage;
                        switch (true) do {
                            case !(_engage select 0): { _engage select 1 };
                            case ((_engage param [6, ""]) != ""): { format ["only a last-ditch shot (%1), and busy", _engage select 6] };
                            default { "could engage it, but is busy or would be too late" };
                        }
                    };
                }]
            };
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " UNENGAGED: %1 (%2) impact in %3s, %4m from the nearest Site vehicle, and no weapon is on it -- %5.",
                _object, _class, round _timeToImpact, round (selectMin (_memberPositions apply { _x distance _targetPos })), _why joinString "; "];
        };

        // When its launchers are looked at next, for a munition that isn't
        // urgent (_asleep, above). With a launcher on it: AEGISM_FAR_INTERVAL
        // s on, for its claim's hand-off check. With none, and the reserve
        // plan holding it for a launcher to fire at later: a turn and a plan
        // step before that launcher's crew would have to start on it (the
        // plan has its reaction counted from now, and its fire time is only
        // as fine as its steps -- woken a turn before the fire time alone,
        // RAM launchers were given their rockets 0.9 s later than when every
        // run looked), or AEGISM_FAR_INTERVAL s on if that's sooner.
        // Otherwise: the next run.
        //
        // And the time that look has to come by ("launcherLookBy"): a run
        // that has done enough new work may put it off (the reserve plan,
        // _mustLook), but not past when that crew would have to start, nor
        // more than AEGISM_FAR_INTERVAL s. One with no launcher and none
        // planned for it is never put off.
        if (_isMunition && {!_asleepNow} && {_timeToImpact > AEGISM_URGENT_TTI} && {_timeToImpact < 1e9}) then {
            private _lookIn = 0;
            private _lookBy = 0;
            if (_hasLauncher) then {
                _lookIn = AEGISM_FAR_INTERVAL;
                _lookBy = AEGISM_FAR_INTERVAL;
            } else {
                if (_contactKey in _planFire) then {
                    private _startIn = ((_planFire get _contactKey) - AEGISM_RESERVE_PLAN_STEP - AEGISM_COORDINATOR_INTERVAL) max 0;
                    _lookIn = AEGISM_FAR_INTERVAL min _startIn;
                    _lookBy = (2 * AEGISM_FAR_INTERVAL) min _startIn;
                };
            };
            _entry set ["launcherLookAt", CBA_missionTime + _lookIn];
            _entry set ["launcherLookBy", CBA_missionTime + _lookBy];
        };

        if (_existing isNotEqualTo []) then { _claims set [_contactKey, _existing]; };
    };
} forEach _orderedKeys;

// --- Last-ditch: guns with nothing better -------------------------------------
// A munition every gun that could take it has less than its Minimum Firing
// Window on was left out above. A gun still free now that every contact has
// been served takes the one it has the longest window on: little chance, but
// nothing better for it to do. It drops it the moment a contact it has its
// full window on comes (_fnDropLastDitch).
if (_lastDitch isNotEqualTo []) then {
    // [window, index] pairs, so sort only ever compares numbers.
    private _options = [];
    private _order = [];
    {
        _x params ["_contactKey", "_candidates"];
        {
            _order pushBack [(_x select 1) param [4, 0], count _options];
            _options pushBack [_contactKey, _x select 0, _x select 1];
        } forEach _candidates;
    } forEach _lastDitch;
    _order sort false;
    {
        (_options select (_x select 1)) params ["_contactKey", "_weapon", "_eligibleEntry"];
        _eligibleEntry params ["", "_flightTime", ["_cueIn", 0], "", "", ["_short", ""]];
        _weapon params ["_candSystem", "_candRole", "_candInfo"];
        private _weaponIndex = _allWeapons find _weapon;
        private _existing = _claims getOrDefault [_contactKey, []];
        private _entry = _pool getOrDefault [_contactKey, createHashMap];
        private _object = _entry getOrDefault ["object", objNull];
        private _busyNow = ((_busy getOrDefault [[netId _candSystem, _candInfo select 0], []]) findIf { (_x select 0) != _contactKey && {_x select 2} }) != -1;
        if (_weaponIndex != -1 && {!_busyNow} && {!isNull _object} && {alive _object} && {(_existing findIf { (_x get "role") == "ciws" }) == -1}) then {
            _existing pushBack createHashMapFromArray [
                ["target", _object],
                ["class", _entry get "class"],
                ["system", _candSystem],
                ["role", _candRole],
                ["weaponInfo", _candInfo],
                ["assignedAt", CBA_missionTime],
                ["lastShotAt", -1],
                ["roundsFired", 0],
                ["interceptors", []],
                ["flightTime", _flightTime],
                ["cued", _cueIn > 0],
                ["lastDitch", true]
            ];
            _claims set [_contactKey, _existing];
            [_candSystem, _candInfo select 0, _contactKey, _candRole, true, 0, false, true] call _fnBusyAdd;
            _allWeapons deleteAt _weaponIndex;
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ASSIGN: %1 (%2, ciws %3) -> %4 (%5, %6m, %7m AGL), impact in %8s -- last-ditch: %9; nothing better for it now.",
                _candSystem, typeOf _candSystem, _candInfo select 1, _object, _entry get "class", round (_candSystem distance _object), round (_object call _fnHeight),
                round (_ttiByKey getOrDefault [_contactKey, 0]), _short];
        };
    } forEach _order;
};

_logic setVariable ["AEGISM_claims", _claims, false];
_logic setVariable ["AEGISM_withheldCiws", _withheldCiws, false];

// Each member's own records, per role, soonest impact first -- a launcher's
// in its queue order (_fnQueuePlace: the claim its turret is working kept
// ahead), the order its engagement loop works them in. Sorted as [place,
// index into _records] pairs, so sort only ever compares numbers.
private _records = [];
private _buckets = _members apply { [[], []] };
{
    private _tti = _ttiByKey getOrDefault [_x, 1e10];
    {
        private _index = _members find (_x get "system");
        if (_index != -1) then {
            private _isGun = (_x get "role") == "ciws";
            ((_buckets select _index) select (parseNumber _isGun)) pushBack [[_tti, !_isGun && {_x getOrDefault ["working", false]}] call _fnQueuePlace, count _records];
            _records pushBack _x;
        };
    } forEach _y;
} forEach _claims;
{
    if (!isNull _x) then {
        (_buckets select _forEachIndex) params ["_launcherOrder", "_ciwsOrder"];
        _launcherOrder sort true;
        _ciwsOrder sort true;
        _x setVariable ["AEGISM_assigned", createHashMapFromArray [
            ["launcher", _launcherOrder apply { _records select (_x select 1) }],
            ["ciws", _ciwsOrder apply { _records select (_x select 1) }]
        ], false];
    };
} forEach _members;

// The launcher shots of the munitions whose look this run put off: their
// questions are kept on the Site, and its loop works them out in the frames
// before the next run (aegism_intercept_fnc_planAhead, from aegism_network_
// fnc_moduleInit).
_logic setVariable ["AEGISM_planLeft", _plan select 3, false];
_logic setVariable ["AEGISM_assignMore", (_plan select 3) isNotEqualTo [], false];

PERF_COORD_ASSIGN_MS call _fnPerfPart;
call _fnPerf;
