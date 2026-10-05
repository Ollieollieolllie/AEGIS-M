/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_assignEngagements

Description:
    Site-level engagement coordinator, run once per Site every 0.5s on the
    server. Decides, for every pooled contact, which member System's weapon
    engages it; member engagement loops only execute these assignments.
    Sites linked through a shared vehicle (aegism_network_fnc_linkSites) are
    coordinated once, by their lead, across every vehicle of the group
    ("AEGISM_groupMembers"), from the pool and ledger they share.

    1. Prune the Site pool by expiry (aegism_detect_fnc_pruneStaleContacts).
       Sensors never delete from the shared pool directly any more -- they
       used to, which deleted assignments every second and restarted the
       crew reaction timer so launchers never fired.

    2. Review existing assignments (AEGISM_claims) and keep each unless:
         - its System is dead, or the contact left the pool
         - the weapon can no longer usefully engage it (aegism_intercept_
           fnc_canEngage: envelope, and a feasible intercept -- a gun is
           released from a jet flying away that its rounds can't catch).
           Not asked of a launcher whose salvo is away: its missiles are
           flying, and another launcher shouldn't fire on top of them
         - launcher MISSED: salvo spent, AEGISM_INTERCEPTOR_SETTLE seconds
           since the last shot, and none of its interceptors are still in
           flight. This is judged from the real missiles (captured by
           aegism_intercept_fnc_onSystemFired), not a fixed timer -- the old
           8s timer called a long-range shot "failed" while its missile was
           still flying and fired a second one at the same target.
         - CIWS idle: hasn't fired for AEGISM_CIWS_IDLE_GRACE seconds
         - launcher crew failed to fire (reliability roll, flagged by
           aegism_intercept_fnc_engagementLoop): the contact is re-tasked,
           and that launcher can't take it back until its lost fire cycle
           is over (the contact's "avoid" list), so another weapon tries
         - launcher out of missiles before firing at it
         - never fired within AEGISM_NEVER_FIRED_TIMEOUT seconds of being
           assigned (turret can't bear, LOS never clears) -- frees the
           contact for a better-placed weapon instead of holding it forever

    3. Assign free roles, contacts in Target Priority order -- except a
       contact only passive radar hears (aegism_fnc_hasTrack), which only
       cues the Site's radars. For each
       contact, a launcher and a CIWS weapon are chosen independently (CIWS
       runs in parallel with a launcher unless that gun's "CIWS last
       resort" is set). A candidate weapon must:
         - have live ammo
         - engage that target class (its vehicle's own settings)
         - have the contact inside its envelope
         - not be on a TURRET already committed to a DIFFERENT contact
           (two weapons sharing a turret, e.g. the Cheetah's gun and
           missiles, used to be assigned to different targets and fight
           over the turret's aim forever)
         - for a launcher: a missile left for it once the claims ahead of
           it in that launcher's queue are served (a launcher is never
           queued past its last missile)
         - not be held in LAYERED RESERVE (below)
       Best fit: see _fnPickWeapon. A launcher is only given a munition it
       can fire at in time (LATE otherwise); a queued one that falls later
       than AEGISM_LATE_MARGIN is handed to a launcher that can make it
       (HANDOFF) or released. A launcher's queue is soonest impact first,
       except that the claim its turret is already working keeps its place
       unless one AEGISM_WORKING_LEAD s more urgent comes (_fnQueuePlace).

    Layered reserve (munitions only): every cycle the coordinator plays
    forward each launcher tier, shortest reach first -- each launcher's own
    queue, cooldown, measured shot spacing and missiles left, and the moment
    each incoming munition will enter its envelope (projected on its
    ballistic path) -- to see which munitions the cheaper tiers will kill in
    time. A longer-reach launcher (e.g. a Patriot next to RAM launchers)
    holds its missiles for those, and steps in only for the munitions the
    cheaper tiers can't take in time: when the volume saturates them. It
    stops holding for one the cheaper tier was planned to fire at
    AEGISM_RESERVE_GRACE s ago that none of its launchers has, or whose shot
    missed (RESERVE-MISSED): a plan the tier can't carry out -- a rocket
    coming down too steep for the RAMs -- held every Patriot back until it
    was too late.

    Threat re-assessment: after AEGISM_RETRY_THREAT_ASSESSMENT_THRESHOLD
    launcher attempts on a still-living contact, further launcher shots only
    go to it if no unassigned contact outranks it (aegism_intercept_fnc_
    threatValue).

    Per-vehicle settings: everything decided per WEAPON -- envelope, which
    target classes it engages, missiles per target, CIWS last resort -- uses
    that weapon's own vehicle's resolved settings ("AEGISM_resolved
    EngagementSettings": the Site's, plus any per-vehicle overrides, see
    aegism_system_fnc_applyOverrides). The Site's own doctrine decides the
    rest: engagement ORDER (Target Priority -- contacts are served
    highest-priority first, so when threats outnumber free weapons the
    priority rule decides who gets them; it used to be HashMap order, and
    the setting did nothing for a Site) and which classes the Site pool
    holds at all (the Site's allowlist plus any class a member vehicle's
    override adds, "AEGISM_contactAllowlist", read by aegism_detect_fnc_
    addContact).

    Writes AEGISM_claims: contact key (aegism_fnc_contactKey) -> array of
    assignment records (HashMap: target, system, role, weaponInfo,
    assignedAt, lastShotAt, roundsFired, interceptors), and
    AEGISM_withheldCiws (diagnostic, for debugDraw). Publishes each member's
    own records on the member itself ("AEGISM_assigned", role -> records,
    soonest impact first), so its engagement loop never scans or sorts the
    Site's claims. Consumers use the record's own "target" object.

    Cost (it runs in one frame, so it's what shows as a server spike under a
    salvo):
        - the layered-reserve plan's per-munition, per-launcher question
          (when can this launcher first make a shot that lands in time) is
          worked out step by step only as far as the first shot, each step
          cached ("AEGISM_planCache") while the munition keeps to its
          predicted path, and skipped while every munition already has a
          launcher (solving the whole path up front was the ~100 ms frame
          when a salvo came into view)
        - claims are indexed per turret, so the conflict and queue checks
          read one turret's claims (they scanned the whole Site's for every
          candidate weapon of every contact)
        - each launcher's timing is worked out once per run
        - a launcher whose salvo is away isn't re-judged (its missiles are
          flying; it's released once they're gone)
        - a launcher a contact is plainly beyond is skipped before the full
          engageability check; a gun's own check rules out far contacts on
          its flight time to its reach (aegism_intercept_fnc_canEngage)
        - so is a launcher whose queue and reaction alone run past a
          munition's impact (it can't be in time): the full check (its
          intercept solves) was most of the 18-27 ms runs under a rocket
          ripple, re-run for every launcher on every unassigned rocket
    Each run's time is counted for the PERF line (aegism_fnc_perfLog).

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

#define AEGISM_INTERCEPTOR_SETTLE 1.5
#define AEGISM_CIWS_IDLE_GRACE 8
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
// Layered-reserve plan: seconds between the projected positions checked
// while waiting for a munition to enter a launcher's envelope.
#define AEGISM_RESERVE_PLAN_STEP 1
// A cached plan scan is reused while the munition stays within this many
// metres of the path it was scanned on, for at most this many seconds.
#define AEGISM_PLAN_CACHE_TOLERANCE 25
#define AEGISM_PLAN_CACHE_MAX_AGE 10
#define AEGISM_GRAVITY 9.80665

params ["_logic"];

if (isNull _logic) exitWith {};

private _startedAt = diag_tickTime;
// Counts this run for the PERF line.
private _fnPerf = {
    private _ms = (diag_tickTime - _startedAt) * 1000;
    PERF_INC(PERF_COORD_RUNS);
    PERF_ADD(PERF_COORD_MS,_ms);
    AEGISM_perfCounts set [PERF_COORD_MAX_MS, (AEGISM_perfCounts select PERF_COORD_MAX_MS) max _ms];
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
// path]) -> [[contactKey, role, holding, roundsNeeded, working], ...].
// "holding" = still needs the turret: always for a gun; for a launcher only
// until its salvo is away (its missiles then guide themselves and the
// launcher is free for its next target). roundsNeeded = missiles the claim
// still has to fire (0 for a gun). "working" = the launcher claim its turret
// is on now (aegism_intercept_fnc_engagementLoop), kept ahead on its queue
// (AEGISM_WORKING_LEAD). Indexed so the conflict and queue checks look at one
// turret's claims, not the whole Site's for every candidate: with ~30
// contacts, 8 weapons and 40 claims that was ~10,000 checks a run.
private _busy = createHashMap;
private _fnBusyAdd = {
    params ["_system", "_turretPath", "_contactKey", "_role", "_holding", "_rounds", ["_working", false]];
    private _key = [netId _system, _turretPath];
    private _list = _busy get _key;
    if (isNil "_list") then { _list = []; _busy set [_key, _list]; };
    _list pushBack [_contactKey, _role, _holding, _rounds, _working];
};
private _fnBusyRemove = {
    params ["_system", "_turretPath", "_contactKey"];
    private _list = _busy getOrDefault [[netId _system, _turretPath], []];
    private _index = _list findIf { (_x select 0) == _contactKey };
    if (_index != -1) then { _list deleteAt _index; };
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
            private _engage = [false, ""];
            if (_alive) then {
                _engage = if (_salvoAway) then { [true, ""] } else { [_system, _role, _weaponInfo, _object, _systemSettings] call aegism_intercept_fnc_canEngage };
            };
            if (!_salvoAway) then {
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
                case (_role == "launcher" && {(_record get "roundsFired") >= (_systemSettings getOrDefault ["salvoSize", 1])} && {CBA_missionTime > _lastShotAt + AEGISM_INTERCEPTOR_SETTLE} && {((_record get "interceptors") findIf { !isNull _x && {alive _x} }) == -1}): { "missed (salvo spent, no interceptor still in flight)" };
                case (_role == "ciws" && {_lastShotAt >= 0} && {CBA_missionTime > _lastShotAt + AEGISM_CIWS_IDLE_GRACE}): { "CIWS idle" };
                case (_lastShotAt < 0 && {CBA_missionTime > (_record get "assignedAt") + AEGISM_NEVER_FIRED_TIMEOUT}): { "never fired (cannot bear or no LOS)" };
                default { "" };
            };

            if (_reason != "") then {
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ASSIGN-CLEAR: %1 (%2) released %3 -- %4.", _system, _role, _object, _reason];
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
                    !_isGun && {_record getOrDefault ["working", false]}] call _fnBusyAdd;
            } forEach _kept;
        };
    };
} forEach (keys _claims);

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

// Time to impact of every contact (aegism_intercept_fnc_timeToImpact), used
// for ordering, launcher queues, and in-time checks alike.
private _memberPositions = (_members select { !isNull _x && {alive _x} }) apply { getPosASL _x };
private _ttiByKey = createHashMap;
{
    private _object = _y getOrDefault ["object", objNull];
    if (!isNull _object && {alive _object}) then {
        private _tti = [_object, _y get "class", _memberPositions] call aegism_intercept_fnc_timeToImpact;
        _ttiByKey set [_x, _tti];
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
// shot interval since its last missile, or a crew's lost fire cycle
// (turret state "holdUntil"), whichever ends later. Shot spacing is
// the launcher's own MEASURED time per missile (turret state "spacing",
// aegism_intercept_fnc_engagementLoop), which includes lost reliability
// rolls and re-aiming between targets; before its first back-to-back shots
// it's estimated as its shot interval (aegism_intercept_fnc_
// launcherInterval) / crew reliability. (Planning on the bare interval
// queued RAM launchers ~2x deeper than they could fire, so the back of a
// salvo was left to them until too late.) Worked out once per launcher per
// run: nothing it depends on changes within a run.
private _timingCache = createHashMap;
private _fnLauncherTiming = {
    params ["_candSystem", "_weaponInfo"];
    _weaponInfo params ["_turretPath", "", "_magClass"];
    private _cacheKey = [netId _candSystem, _turretPath];
    private _cached = _timingCache get _cacheKey;
    if (!isNil "_cached") exitWith { _cached };
    private _settings = _candSystem call _fnSettings;
    private _mods = _candSystem getVariable "AEGISM_resolvedCrewMods";
    if (isNil "_mods") then {
        private _crew = _candSystem getVariable "AEGISM_resolvedCrew";
        if (isNil "_crew") then { _crew = [_candSystem] call aegism_system_fnc_resolveCrew; };
        _mods = [_crew, _candSystem] call aegism_intercept_fnc_applyCrewModulation;
    };
    private _ts = [_candSystem, _turretPath] call aegism_intercept_fnc_turretState;
    private _interval = ([_candSystem, _weaponInfo, _settings] call aegism_intercept_fnc_launcherInterval) * (_mods get "shotIntervalMult");
    private _spacing = _ts getOrDefault ["spacing", _interval / ((_mods get "reliability") max 0.05)];
    private _readyAt = ((_ts getOrDefault ["shotAt", -1e9]) + _interval) max (_ts getOrDefault ["holdUntil", -1e9]);
    // In combat, its crew's Reaction Once in Combat, as its engagement loop
    // applies it (aegism_intercept_fnc_engagementLoop): the full reaction
    // made it look slower than it was.
    private _reaction = _mods get "reactionTime";
    private _candNetwork = _candSystem getVariable ["AEGISM_network", objNull];
    private _lastShotAt = (_candSystem getVariable ["AEGISM_lastShotAt", -1e9]) max (_candNetwork getVariable ["AEGISM_lastShotAt", -1e9]);
    private _liveWindow = if (isNull _candNetwork) then { AEGISM_LIVE_WINDOW_DEFAULT } else { ([_candNetwork] call aegism_fnc_siteSettingsSource) getVariable ["alarmHold", AEGISM_LIVE_WINDOW_DEFAULT] };
    if (CBA_missionTime - _lastShotAt <= _liveWindow) then { _reaction = _reaction * (_mods getOrDefault ["combatReactionMult", 1]); };
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
// _start on that meets the munition before _tti, or [] if there's none.
//
// Found by stepping along the munition's projected path every AEGISM_
// RESERVE_PLAN_STEP s from _start -- a feasible intercept, its meeting point
// inside the envelope (the munition itself may still be beyond it when the
// missile leaves, aegism_intercept_fnc_canEngage), landing before impact --
// and only as far as the first shot.
// Each step's answer is kept per munition and launcher, in game time
// ("AEGISM_planCache": [scanned at, position, velocity, step -> [fire at,
// intercept at], or [] for no shot]), so a later question from another start
// re-solves nothing already worked out. The whole path used to be solved up
// front -- an intercept solve (aegism_intercept_fnc_launchSolution) for every
// step in the envelope, for every munition and launcher -- and a salvo coming
// into view together cost ~100 ms in one frame. A ballistic path is fixed,
// and so is a parked launcher's envelope; the steps are thrown away if the
// munition strays AEGISM_PLAN_CACHE_TOLERANCE m from the path they were
// worked out on (a rocket still burning, a missile turning), or after
// AEGISM_PLAN_CACHE_MAX_AGE s.
private _planCache = _logic getVariable "AEGISM_planCache";
if (isNil "_planCache") then { _planCache = createHashMap; _logic setVariable ["AEGISM_planCache", _planCache, false]; };
private _fnPlanShot = {
    params ["_candSystem", "_weaponInfo", "_bounds", "_object", "_ballistic", "_start", "_tti", "_key"];
    private _drop = [0, 0.5 * AEGISM_GRAVITY] select _ballistic;
    private _cacheKey = [_key, netId _candSystem, _weaponInfo select 0];
    private _entry = _planCache getOrDefault [_cacheKey, []];
    private _valid = _entry isNotEqualTo [] && {
        _entry params ["_scannedAt", "_p0", "_v0"];
        private _dt = CBA_missionTime - _scannedAt;
        _dt <= AEGISM_PLAN_CACHE_MAX_AGE
            && {((_p0 vectorAdd (_v0 vectorMultiply _dt) vectorDiff [0, 0, _drop * _dt * _dt]) distance (getPosASL _object)) <= AEGISM_PLAN_CACHE_TOLERANCE}
    };
    if (_valid) then {
        PERF_INC(PERF_PLAN_HITS);
    } else {
        PERF_INC(PERF_PLAN_BUILDS);
        _entry = [CBA_missionTime, getPosASL _object, velocity _object, createHashMap];
        _planCache set [_cacheKey, _entry];
    };
    _entry params ["_scannedAt", "_p0", "_v", "_steps"];
    _bounds params ["_minRange", "_maxRange", "_minAltitude", "_maxAltitude"];
    private _origin = eyePos _candSystem;
    private _muzzle = [];
    // The missile's flight to the edge of its reach, for the "too far" bound
    // below (worked out when first needed).
    private _span = -2;
    private _impactAt = CBA_missionTime + _tti;
    private _found = [];
    for "_k" from (ceil (((CBA_missionTime + _start) - _scannedAt) / AEGISM_RESERVE_PLAN_STEP) max 0) to (floor ((_impactAt - _scannedAt) / AEGISM_RESERVE_PLAN_STEP)) do {
        private _shot = _steps get _k;
        if (isNil "_shot") then {
            _shot = [];
            // Seconds after the path was taken, and from now.
            private _sinceScan = _k * AEGISM_RESERVE_PLAN_STEP;
            private _p = (_p0 vectorAdd (_v vectorMultiply _sinceScan)) vectorDiff [0, 0, _drop * _sinceScan * _sinceScan];
            // Fired at from here, the missile meets it closer in -- and only
            // that meeting point has to be inside the envelope (aegism_
            // intercept_fnc_canEngage). Too far for even that, it isn't
            // solved: in the missile's flight to the edge of its reach, the
            // munition closes at most speed x t (+ g t^2 / 2 falling).
            if (_span < -1) then { _span = if (_maxRange > 0) then { [_weaponInfo, _maxRange] call aegism_intercept_fnc_missileFlightTime } else { -1 }; };
            private _speed = vectorMagnitude (_v vectorDiff [0, 0, 2 * _drop * _sinceScan]);
            if (_maxRange > 0 && {_span < 0 || {(_origin distance _p) <= _maxRange + _speed * _span + _drop * _span * _span}}) then {
                // Only a shot a missile can be put onto (aegism_intercept_fnc_
                // launchSolution, the turret having had time to swing): a RAM
                // planned onto rockets above its 40-degree limit held the
                // Patriots in reserve for kills it couldn't make. A vertical
                // launch cell's shots are off-bore, with the missile's turn.
                if (_muzzle isEqualTo []) then { _muzzle = ([_candSystem, _weaponInfo select 0, "launcher"] call aegism_intercept_fnc_turretPoints) select 0; };
                PERF_INC(PERF_PLAN_SOLVES);
                ([_candSystem, _weaponInfo, _object, _muzzle, false, false, false, (_scannedAt + _sinceScan) - CBA_missionTime, _ballistic] call aegism_intercept_fnc_launchSolution)
                    params ["_launchable", "", "", "", "_flightTime", "", "", "", "", "_interceptPoint", "_interceptDistance"];
                if (_launchable) then {
                    private _interceptHeight = (ASLToAGL _interceptPoint) select 2;
                    if (_interceptDistance >= _minRange && {_interceptDistance <= _maxRange} && {_interceptHeight >= _minAltitude} && {_maxAltitude <= 0 || {_interceptHeight <= _maxAltitude}}) then {
                        _shot = [_scannedAt + _sinceScan, _scannedAt + _sinceScan + (_flightTime max 0)];
                    };
                };
            };
            _steps set [_k, _shot];
        };
        if (_shot isNotEqualTo [] && {(_shot select 1) < _impactAt}) exitWith { _found = _shot; };
    };
    if (_found isEqualTo []) exitWith { [] };
    [(_found select 0) - CBA_missionTime, (_found select 1) - CBA_missionTime]
};

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
//       3. most rounds left, so deep magazines take the volume
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
        private _rounds = _candSystem magazineTurretAmmo [_magClass, _turretPath];
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
// The plan only decides which launchers may take a FREE munition: with none
// free, there's nothing to plan.
private _anyFree = (_planKeys findIf { ((_claims getOrDefault [_x, []]) findIf { (_x get "role") == "launcher" }) == -1 }) != -1;
if (count _tierReaches > 1 && {_anyFree}) then {
    _planKeys = _planKeys apply { [_ttiByKey get _x, _x] };
    _planKeys sort true;
    _planKeys = _planKeys apply { _x select 1 };

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
                // Held back only if a longer-reach launcher would still have a
                // shot should this tier's miss: one that can fire once its
                // planned intercept has had AEGISM_RESERVE_RELOOK s to show a
                // miss, and still meet the munition before it comes down. A
                // high-arc rocket coming down steeply only falls back into a
                // RAM's reach in its last seconds -- planned to the RAMs there,
                // it held every Patriot back until no second shot was left.
                if (_best isNotEqualTo []) then {
                    private _relookAt = (_best select 2) + AEGISM_RESERVE_RELOOK;
                    private _fallback = (_launcherEntries findIf {
                        _x params ["_candSystem", "", "_candInfo"];
                        (_candInfo select 5) > _tierReach
                            && {(_planEntry get "class") in ((_candSystem call _fnSettings) getOrDefault ["targetClassAllowlist", []])}
                            && {(_avoid findIf { (_x select 0) == _candSystem && {(_x select 1) isEqualTo (_candInfo select 0)} }) == -1}
                            && {([_candSystem, _candInfo, [_candSystem call _fnSettings, _candInfo, "launcher"] call aegism_intercept_fnc_envelopeBounds,
                                _object, _ballistic, _relookAt, _tti, _key] call _fnPlanShot) isNotEqualTo []}
                    }) != -1;
                    if (!_fallback) then {
                        if !(_planEntry getOrDefault ["noFallbackLogged", false]) then {
                            _planEntry set ["noFallbackLogged", true];
                            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " RESERVE-RELEASED: %1 (%2, impact in %3s) -- the %4m launcher tier could only kill it %5s before impact, leaving the longer-reach launchers no second shot if it missed: they may take it now.",
                                _object, _planEntry get "class", round _tti, round _tierReach, round ((_tti - (_best select 2)) * 10) / 10];
                        };
                        _best = [];
                    };
                };
                if (_best isNotEqualTo []) then {
                    _best params ["_index", "_fireTime"];
                    private _state = _played select _index;
                    private _salvo = (_state select 6) min (_state select 4);
                    _state set [3, _fireTime + _salvo * (_state select 5)];
                    _state set [4, (_state select 4) - _salvo];
                    _coveredReach set [_key, _tierReach];
                    // When the plan first had the tier firing at it, for the
                    // check that it does (RESERVE-MISSED, below).
                    if !("reserveFireAt" in _planEntry) then { _planEntry set ["reserveFireAt", CBA_missionTime + _fireTime]; };
                    _settled pushBack _key;
                };
            };
        } forEach _planKeys;
        _planKeys = _planKeys - _settled;
    } forEach (_tierReaches select [0, count _tierReaches - 1]);
};

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
        private _handoff = [];
        if (_isMunition && {_hasLauncher}) then {
            private _index = _existing findIf { (_x get "role") == "launcher" && {(_x get "roundsFired") == 0} };
            if (_index != -1) then {
                private _record = _existing select _index;
                (_record get "weaponInfo") params ["_turretPath"];
                private _eta = [_record get "system", _record get "weaponInfo", _contactKey, _timeToImpact, _record get "assignedAt"] call _fnLauncherEta;
                if (_eta + (_record getOrDefault ["flightTime", 0]) >= _timeToImpact + AEGISM_LATE_MARGIN) then {
                    _handoff = [_record, _eta];
                    _existing deleteAt _index;
                    [_record get "system", _turretPath, _contactKey] call _fnBusyRemove;
                    _hasLauncher = false;
                };
            };
        };

        {
            private _role = _x;
            private _covered = [_hasLauncher, _hasCiws] select (_role == "ciws");

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
                        private _conflict = ((_busy getOrDefault [[netId _candSystem, _candInfo select 0], []]) findIf {
                            _x params ["_bKey", "_bRole", "_bHolding"];
                            _bKey != _contactKey && {_bHolding} && {_role == "ciws" || {_bRole == "ciws"} || {!_isMunition}}
                        }) != -1;
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
                        private _beyond = _role == "launcher" && {
                            private _reach = _candInfo select 5;
                            private _span = ([_candInfo, _reach] call aegism_intercept_fnc_missileFlightTime) max 0;
                            ((getPosASL _candSystem) distance _targetPos) > _reach + 50 + _speed * _span + 0.5 * AEGISM_GRAVITY * _span * _span
                        };
                        // A launcher whose own queue and reaction alone run
                        // past the munition's impact can't fire at it in
                        // time, whatever its missile's flight: skipped before
                        // the full check (_fnPickWeapon would turn it down).
                        // A salvo's unreachable rockets were otherwise
                        // re-solved against every launcher on every run:
                        // 18-27 ms runs in a jet's rocket attack.
                        private _queueReady = 0;
                        if (_role == "launcher" && {_isMunition} && {!_conflict} && {!_avoided} && {!_reserved} && {!_beyond}) then {
                            _queueReady = [_candSystem, _candInfo, _contactKey, _timeToImpact] call _fnLauncherEta;
                            if (_queueReady >= _timeToImpact) then { _tooLate pushBack [_queueReady, _candSystem]; };
                        };
                        if (!_conflict && {!_avoided} && {!_reserved} && {!_beyond} && {_queueReady < _timeToImpact} && {_class in (_candSettings getOrDefault ["targetClassAllowlist", []])}) then {
                            private _engage = [_candSystem, _role, _candInfo, _object, _candSettings] call aegism_intercept_fnc_canEngage;
                            if (_engage select 0) then { _eligible pushBack [_forEachIndex, _engage param [2, 0], _engage param [4, 0]]; };
                        };
                    };
                } forEach _allWeapons;

                if (_role == "launcher" && {_eligible isEqualTo []} && {_tooLate isNotEqualTo []} && {_handoff isEqualTo []} && {!(_entry getOrDefault ["lateLogged", false])}) then {
                    _entry set ["lateLogged", true];
                    _tooLate sort true;
                    (_tooLate select 0) params ["_soonestReady", "_soonestSystem"];
                    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " LATE: no launcher can fire at %1 in time (impact in %2s) -- the soonest, %3, %4. Left to the guns.",
                        _object, round (_timeToImpact * 10) / 10, _soonestSystem,
                        ["has no missile left for it", format ["is ready in ~%1s, before its missile's flight", round (_soonestReady * 10) / 10]] select (_soonestReady < AEGISM_NO_ROUND)];
                };

                if (_held isNotEqualTo [] && {!(_entry getOrDefault ["reserveLogged", false])}) then {
                    _entry set ["reserveLogged", true];
                    if (AEGISM_RPT_VERBOSE) then {
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " RESERVE: %1 (%2, impact in %3s) -- the %4m launcher tier is predicted to kill it in time, holding %5.",
                            _object, _class, round _timeToImpact, round _reserveReach, _held];
                    };
                };

                // CIWS last resort (each gun's own setting): while a launcher
                // covers the contact, a last-resort gun holds unless the
                // contact is already deep inside its own reach.
                if (_role == "ciws" && {_hasLauncher} && {_eligible isNotEqualTo []}) then {
                    private _free = _eligible select {
                        (_allWeapons select (_x select 0)) params ["_candSystem", "", "_candInfo"];
                        !((_candSystem call _fnSettings) getOrDefault ["ciwsLastResort", false])
                            || {((getPosASL _candSystem) distance _targetPos) <= (_candInfo select 5) * AEGISM_CIWS_OVERRIDE_RANGE_FRACTION}
                    };
                    if (_free isEqualTo []) then { _withheldCiws pushBack [_contactKey, (_allWeapons select ((_eligible select 0) select 0)) select 0]; };
                    _eligible = _free;
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
                        (_eligible select (_eligible findIf { (_x select 0) == _weaponIndex })) params ["", "_flightTime", ["_cueIn", 0]];

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
                                private _oldEta = _handoff select 1;
                                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " HANDOFF: %1 can't fire at %2 in time (%3) -- %4 (%5) takes it, fires in ~%6s.",
                                    (_handoff select 0) get "system", _object,
                                    [format ["ready in ~%1s + %2s flight vs impact in %3s", round (_oldEta * 10) / 10, round (((_handoff select 0) getOrDefault ["flightTime", 0]) * 10) / 10, round (_timeToImpact * 10) / 10], "no missile left for it"] select (_oldEta >= AEGISM_NO_ROUND),
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
                _handoff params ["_old", "_oldEta"];
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " ASSIGN-CLEAR: %1 (launcher) released %2 -- %3, and no other launcher can take it in time.", _old get "system", _object,
                    if (_oldEta >= AEGISM_NO_ROUND) then { "no missile left for it (its queue is deeper than its magazine)" } else {
                        format ["can't fire at it in time (ready in ~%1s + %2s flight vs impact in %3s)", round (_oldEta * 10) / 10, round ((_old getOrDefault ["flightTime", 0]) * 10) / 10, round (_timeToImpact * 10) / 10]
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
                    case (_candRole == "launcher" && {_cover > 0} && {(_candInfo select 5) > _cover}): { format ["held in reserve for the %1m tier", round _cover] };
                    default {
                        private _engage = [_candSystem, _candRole, _candInfo, _object, _candSettings] call aegism_intercept_fnc_canEngage;
                        if (_engage select 0) then { "could engage it, but is busy or would be too late" } else { _engage select 1 }
                    };
                }]
            };
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " UNENGAGED: %1 (%2) impact in %3s, %4m from the nearest Site vehicle, and no weapon is on it -- %5.",
                _object, _class, round _timeToImpact, round (selectMin (_memberPositions apply { _x distance _targetPos })), _why joinString "; "];
        };

        if (_existing isNotEqualTo []) then { _claims set [_contactKey, _existing]; };
    };
} forEach _orderedKeys;

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

call _fnPerf;
