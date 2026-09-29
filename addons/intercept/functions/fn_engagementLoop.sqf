/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_engagementLoop

Description:
    One engagement tick for one role ("launcher" or "ciws") of one System,
    run on the server every 0.1s by a per-frame handler registered in
    aegism_system_fnc_moduleInit. Ammo is read live from the vehicle's real
    magazines; AEGIS-M counts nothing itself.

    NETWORKED (synced to a Site): executes the assignments the Site's
    coordinator (aegism_intercept_fnc_assignEngagements) published for this
    System and role ("AEGISM_assigned", soonest impact first). It never
    picks targets itself. Nothing assigned: returns straight away.

    STANDALONE: each of its weapon turrets picks its own target from the
    System's own pool (aegism_intercept_fnc_selectTarget) -- a target another
    of its turrets in this role is already on is left to that turret -- and
    keeps its own engagement state in its turret state ("standalone_<role>",
    aegism_intercept_fnc_turretState). A launcher turret whose salvo is away
    moves on to its next target while the missiles fly ("inFlight_launcher");
    if they all miss, the target is back on its list (MISSED). Nothing in
    the pool: returns straight away.

    Both paths run the same per-engagement sequence on an engagement state
    HashMap (a Site assignment record, or the standalone state) with keys
    assignedAt, lastShotAt, roundsFired, nextAttemptAt, interceptors:
        1. Aim -- a launcher solves here (aegism_intercept_fnc_aimWeapon); a
           CIWS gun's per-frame tracker (aegism_intercept_fnc_ciwsTrack) is
           handed the target and its current aim used. Every tick from the
           moment of assignment, so the turret is already on target when the
           crew finishes reacting.
        2. Crew reaction time since assignment (CIWS capped at
           AEGISM_CIWS_REACTION_CAP: automated fire control).
        3. Fire cadence:
             launcher - doctrine salvoSize per engagement, the launcher's
                 shot interval between shots (aegism_intercept_fnc_
                 launcherInterval; both crew-modulated)
             ciws - sustained bursts (aegism_intercept_fnc_ciwsBurst) of a
                 random doctrine ciwsBurstMin..ciwsBurstMax seconds at the
                 gun's own rate of fire, and ciwsBurstPause (crew-modulated)
                 before firing again at the SAME target. A gun whose last
                 target is gone goes straight on to the next: the pause
                 after every kill cost ~1s per shell in a salvo. A running
                 burst is cut short if the target changes or LOS is lost.
        4. LOS from this System (a Site contact may have been detected by a
           sibling with a different view), re-checked every
           AEGISM_LOS_REUSE s.
        5. Alignment from step 1.
        6. Fire (aegism_intercept_fnc_fireWeapon). A failed crew
           reliability roll costs one fire cycle (nextAttemptAt). A Site
           launcher's lost cycle holds the whole turret ("holdUntil") and
           flags the assignment "crewFailed": the coordinator re-tasks the
           contact to another weapon rather than leaving it with a crew that
           just failed to shoot.

    Every silent wait is logged once per engagement (REACTING, SLEWING
    every AEGISM_SLEW_LOG_INTERVAL s, LOS-BLOCKED on change), so an assigned
    weapon that isn't firing always says why in the RPT.

    Optional Cost/Value Judgment (standalone): the crew holds fire on a
    contact if firing would leave fewer rounds than there are pooled
    contacts of strictly higher threat value.

Parameters:
    _system - the System vehicle <OBJECT>
    _role - "launcher" or "ciws" <STRING>

Returns:
    Nothing

Examples:
    [_samSite, "launcher"] call aegism_intercept_fnc_engagementLoop;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

#define AEGISM_CIWS_REACTION_CAP 1
#define AEGISM_SLEW_LOG_INTERVAL 5
#define AEGISM_INTERCEPTOR_SETTLE 1.5
#define AEGISM_TURRET_RELEASE 1.5
// Weight of each new sample in a launcher's measured shot spacing.
#define AEGISM_SPACING_SMOOTHING 0.3
// A line-of-sight check stays good this long.
#define AEGISM_LOS_REUSE 0.2
// Standalone: a launcher's target pick is reused this long; an empty pick
// (nothing engageable) is retried after this long.
#define AEGISM_SELECT_REUSE 0.5
#define AEGISM_SELECT_EMPTY_RETRY 0.25

params ["_system", "_role"];

if (isNull _system || {!alive _system}) exitWith {};

private _isCiws = _role == "ciws";
private _systemData = _system getVariable "AEGISM_system";
if (isNil "_systemData") exitWith {};
private _weaponPool = _systemData getOrDefault [["launcherWeapons", "ciwsWeapons"] select _isCiws, []];
private _network = _system getVariable ["AEGISM_network", objNull];
private _stateKey = "standalone_" + _role;

// Hand a turret back to its crew once nothing has aimed it for
// AEGISM_TURRET_RELEASE s.
{
    private _ts = [_system, _x select 0] call aegism_intercept_fnc_turretState;
    private _lockedAt = _ts getOrDefault ["lockAt", -1];
    if (_lockedAt >= 0 && {time - _lockedAt > AEGISM_TURRET_RELEASE}) then {
        _ts set ["lockAt", -1];
        [_system, _x select 0, objNull] call aegism_intercept_fnc_lockTurret;
    };
} forEach _weaponPool;

// --- Nothing to do: return before any real work --------------------------------
private _assigned = [];
if (!isNull _network) then {
    private _byRole = _system getVariable "AEGISM_assigned";
    if (!isNil "_byRole") then { _assigned = _byRole getOrDefault [_role, []]; };
};
if (!isNull _network && {_assigned isEqualTo []}) exitWith {};

private _pool = _system getVariable "AEGISM_pooledContacts";
if (isNull _network && {isNil "_pool" || {count _pool == 0}}) exitWith {
    // Clear what each turret was on (the debug overlays show it).
    {
        private _state = ([_system, _x select 0] call aegism_intercept_fnc_turretState) get _stateKey;
        if (!isNil "_state" && {!isNull (_state getOrDefault ["target", objNull])}) then {
            ([_system, _x select 0] call aegism_intercept_fnc_turretState) set [_stateKey, createHashMap];
        };
    } forEach _weaponPool;
};

PERF_INC(PERF_ENGAGE_TICKS);

private _engagementSettings = _system getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_engagementSettings") then { _engagementSettings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
// Crew modifiers are resolved with the crew (aegism_system_fnc_moduleInit's
// 5s refresh) rather than rebuilt every tick.
private _crewMods = _system getVariable "AEGISM_resolvedCrewMods";
if (isNil "_crewMods") then {
    private _crew = _system getVariable "AEGISM_resolvedCrew";
    if (isNil "_crew") then { _crew = [_system] call aegism_system_fnc_resolveCrew; };
    _crewMods = [_crew, _system] call aegism_intercept_fnc_applyCrewModulation;
};

// eyePos is already ASL.
private _weaponPos = eyePos _system;

private _reactionTime = _crewMods get "reactionTime";
if (_isCiws) then { _reactionTime = _reactionTime min AEGISM_CIWS_REACTION_CAP; };
private _salvoSize = _engagementSettings getOrDefault ["salvoSize", 1];

// Runs the aim/gate/fire sequence for one engagement (see header).
private _fnExecute = {
    params ["_target", "_weaponInfo", "_state"];
    _weaponInfo params ["_turretPath", "_weaponClass", "_magClass"];

    // Each exit below records where this engagement stands ("status", for the
    // debug overlays, aegism_fnc_statusStyle).
    if ((_system magazineTurretAmmo [_magClass, _turretPath]) <= 0) exitWith { _state set ["status", "noAmmo"]; };

    // A launcher whose salvo is away has nothing left to do for this target
    // (its missiles guide themselves): it no longer aims at it, so the
    // turret is free for its next assignment while they fly.
    if (!_isCiws && {(_state get "roundsFired") >= _salvoSize}) exitWith { _state set ["status", "inFlight"]; };

    private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;

    // A gun's per-frame tracker keeps the turret on this target between
    // ticks, bursts or not; a running burst stops once the turret's "tickAt"
    // goes stale (the assignment is no longer being worked).
    private _aim = if (_isCiws) then {
        _ts set ["tickAt", time];
        _ts set ["trackTarget", [_target, _weaponInfo, time]];
        [_system, _turretPath] call aegism_intercept_fnc_ciwsTrack
    } else {
        [_system, _target, _weaponInfo, _role] call aegism_intercept_fnc_aimWeapon
    };
    _aim params ["_aligned", "_angle", "_tolerance", "_aimPoint", "_feasible", ["_inRange", true]];

    if (time < (_state get "assignedAt") + _reactionTime) exitWith {
        _state set ["status", "reacting"];
        if !(_state getOrDefault ["reactionLogged", false]) then {
            _state set ["reactionLogged", true];
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " REACTING: %1 (%2) on %3 -- crew reaction %4s, turret slewing meanwhile.", _system, _role, _target, _reactionTime];
        };
    };

    if (time - (_state getOrDefault ["losAt", -1e9]) >= AEGISM_LOS_REUSE) then {
        _state set ["losAt", time];
        _state set ["losClear", (lineIntersectsSurfaces [_weaponPos, getPosASL _target, _system, _target, true, 1]) isEqualTo []];
    };
    private _losClear = _state get "losClear";

    // CIWS burst in progress: aegism_intercept_fnc_ciwsBurst fires it; cut
    // it short if it's on another target (re-assigned) or LOS is lost.
    (_ts getOrDefault ["burst", [-1, objNull, 0]]) params ["_burstEndsAt", "_burstTarget", "_burstId"];
    if (_isCiws && {time < _burstEndsAt}) exitWith {
        if (_burstTarget != _target || {!_losClear}) then {
            _ts set ["burst", [time, _burstTarget, _burstId]];
            _state set ["status", ["slewing", "losBlocked"] select !_losClear];
        } else {
            _state set ["lastShotAt", time];
            _state set ["status", "firing"];
        };
    };

    // Launcher: its shot interval (aegism_intercept_fnc_launcherInterval --
    // the setting, or Auto: the launcher's own config fire rate) since this
    // LAUNCHER's last missile, whatever it was fired at (turret "shotAt").
    // CIWS: the burst pause, counted from when the last burst ENDED
    // (aegism_intercept_fnc_ciwsBurst rewrites endsAt to the actual end
    // time) -- only between bursts at the SAME target.
    private _baseInterval = if (_isCiws) then {
        _engagementSettings getOrDefault ["ciwsBurstPause", 1]
    } else {
        [_system, _weaponInfo, _engagementSettings] call aegism_intercept_fnc_launcherInterval
    };
    private _interval = _baseInterval * (_crewMods get "shotIntervalMult");
    private _intervalFrom = if (_isCiws) then { [-1, _burstEndsAt] select (_burstTarget == _target) } else { _ts getOrDefault ["shotAt", -1] };

    if (_intervalFrom >= 0 && {time < _intervalFrom + _interval}) exitWith { _state set ["status", "reloading"]; };
    if (time < (_state getOrDefault ["nextAttemptAt", -1])) exitWith { _state set ["status", "reloading"]; };
    if (!_isCiws && {time < (_ts getOrDefault ["holdUntil", -1])}) exitWith { _state set ["status", "reloading"]; };

    if (!_losClear) exitWith {
        _state set ["status", "losBlocked"];
        if !(_state getOrDefault ["losBlocked", false]) then {
            _state set ["losBlocked", true];
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " LOS-BLOCKED: %1 (%2) cannot see %3 -- holding, re-checking every tick.", _system, _role, _target];
        };
    };
    _state set ["losBlocked", false];

    if (!_feasible) exitWith {
        _state set ["status", "noSolution"];
        if (time > (_state getOrDefault ["lastSlewLog", -1e9]) + AEGISM_SLEW_LOG_INTERVAL) then {
            _state set ["lastSlewLog", time];
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " NO-SOLUTION: %1 (%2) holding on %3 -- no intercept inside the weapon's reach (target receding faster than the round can close, or meeting point beyond range).", _system, _role, _target];
        };
    };

    // A gun tracking a target still beyond its open-fire range (aegism_
    // intercept_fnc_openFireRange): on it, holding fire until it's closer.
    if (!_inRange) exitWith {
        _state set ["status", "rangeHold"];
        if !(_state getOrDefault ["rangeHoldLogged", false]) then {
            _state set ["rangeHoldLogged", true];
            (_ts getOrDefault ["solve", []]) params ["", "", "", "", "", "", "", ["_interceptDistance", 0], "", "", ["_openFireRange", 0], ["_minRange", 0]];
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " RANGE-HOLD: %1 (%2) tracking %3 -- intercept at %4m, %5: holding fire (see OPEN-FIRE-RANGE).",
                _system, _role, _target, round _interceptDistance,
                if (_interceptDistance < _minRange) then {
                    format ["inside the round's %1m arming distance", round _minRange]
                } else {
                    format ["beyond its %1m open-fire range, where one burst is less than %2 percent likely to hit", round _openFireRange, _engagementSettings getOrDefault ["ciwsOpenFireChance", 40]]
                }];
        };
    };

    if (!_aligned) exitWith {
        _state set ["status", "slewing"];
        if (time > (_state getOrDefault ["lastSlewLog", -1e9]) + AEGISM_SLEW_LOG_INTERVAL) then {
            _state set ["lastSlewLog", time];
            // Why a turret can't get there: its aim point past the turret's own
            // elevation limits (aegism_intercept_fnc_turretCanPoint).
            ([_system, _turretPath, _weaponPos vectorFromTo _aimPoint] call aegism_intercept_fnc_turretCanPoint) params ["_canPoint", "_aimElevation", "_minElevation", "_maxElevation"];
            private _limitNote = if (_canPoint) then { "" } else {
                format [" -- aim point at %1 deg elevation, beyond the turret's %2 to %3 deg", round _aimElevation, _minElevation, _maxElevation]
            };
            diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " SLEWING: %1 (%2) on %3 -- barrel %4 deg off aim point, need <= %5%6%7.", _system, _role, _target, round (_angle * 10) / 10, round (_tolerance * 100) / 100,
                ["", " (or the turret settled inside the missile's lock cone)"] select !_isCiws, _limitNote];
        };
    };

    private _burstDuration = 0;
    if (_isCiws) then {
        private _burstMin = _engagementSettings getOrDefault ["ciwsBurstMin", 3];
        private _burstMax = (_engagementSettings getOrDefault ["ciwsBurstMax", 5]) max _burstMin;
        _burstDuration = _burstMin + random (_burstMax - _burstMin);
    };

    private _result = [_system, _target, _weaponInfo, _crewMods get "reliability", _role, _state get "interceptors", _burstDuration] call aegism_intercept_fnc_fireWeapon;
    switch (_result) do {
        case 1: {
            _state set ["lastShotAt", time];
            _state set ["roundsFired", (_state get "roundsFired") + 1];
            _state set ["status", ["firing", "inFlight"] select (!_isCiws && {(_state get "roundsFired") >= _salvoSize})];
            if (!_isCiws) then {
                // Measured time per missile when firing back to back (it
                // includes lost reliability rolls and re-aiming between
                // targets, which the configured interval alone doesn't) --
                // the Site coordinator plans each launcher's queue with it.
                // A gap longer than twice the estimate was idle time, not
                // firing rate, and is ignored.
                private _spacing = _ts getOrDefault ["spacing", _interval / ((_crewMods get "reliability") max 0.05)];
                private _gap = time - (_ts getOrDefault ["shotAt", -1e9]);
                if (_gap <= 2 * _spacing) then {
                    _ts set ["spacing", (1 - AEGISM_SPACING_SMOOTHING) * _spacing + AEGISM_SPACING_SMOOTHING * _gap];
                };
            };
            _ts set ["shotAt", time];
        };
        case 0: {
            _state set ["status", "crewFailed"];
            _state set ["nextAttemptAt", time + _interval];
            // Site launcher, nothing fired at this contact yet: the crew's
            // lost cycle holds the turret, and the coordinator hands the
            // contact to another weapon (aegism_intercept_fnc_assign
            // Engagements, "crew failed to fire").
            if (!_isCiws && {!isNull _network} && {(_state get "roundsFired") == 0}) then {
                _ts set ["holdUntil", time + _interval];
                _state set ["crewFailed", true];
            };
        };
        default { _state set ["status", "held"]; };
    };
};

if (!isNull _network) exitWith {
    // --- NETWORKED: execute this System's Site assignments ---
    // Soonest impact first (the coordinator's order): per launcher turret,
    // only the first assignment whose salvo isn't away yet is worked this
    // tick -- front to back through a salvo -- while the rest wait their
    // turn instead of fighting over the turret's aim.
    private _workingTurrets = [];
    {
        private _target = _x getOrDefault ["target", objNull];
        if (!isNull _target && {alive _target}) then {
            (_x get "weaponInfo") params ["_turretPath"];
            private _salvoAway = !_isCiws && {(_x get "roundsFired") >= _salvoSize};
            if (_isCiws || _salvoAway || {!(_turretPath in _workingTurrets)}) then {
                if (!_isCiws && {!_salvoAway}) then { _workingTurrets pushBack _turretPath; };
                [_target, _x get "weaponInfo", _x] call _fnExecute;
            } else {
                // Behind another on this launcher's queue.
                _x set ["status", "queued"];
            };
        };
    } forEach _assigned;
};

// --- STANDALONE: each turret on its own target ---------------------------------
private _readyWeapons = _weaponPool select {
    _x params ["_turretPath", "", "_magClass"];
    (_system magazineTurretAmmo [_magClass, _turretPath]) > 0
};
if (_readyWeapons isEqualTo []) exitWith {};

private _candidates = [];
{
    private _object = _y getOrDefault ["object", objNull];
    if (!isNull _object && {alive _object}) then { _candidates pushBack [_object, _y get "class"]; };
} forEach _pool;

private _byTurret = createHashMap;
{
    private _list = _byTurret get (_x select 0);
    if (isNil "_list") then { _list = []; _byTurret set [_x select 0, _list]; };
    _list pushBack _x;
} forEach _readyWeapons;

private _crew = _system getVariable "AEGISM_resolvedCrew";
if (isNil "_crew") then { _crew = [_system] call aegism_system_fnc_resolveCrew; };
private _selectKey = "select_" + _role;
private _taken = [];

{
    private _turretPath = _x;
    private _weapons = _y;
    private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;
    private _state = _ts getOrDefault [_stateKey, createHashMap];

    // Launcher salvos still flying: those targets wait. All missiles gone
    // and the target alive: it missed, and the target is back on the list.
    private _exclude = +_taken;
    if (!_isCiws) then {
        private _inFlight = (_ts getOrDefault ["inFlight_launcher", []]) select {
            _x params ["_flightTarget", "_interceptors", "_lastShotAt"];
            private _alive = !isNull _flightTarget && {alive _flightTarget};
            private _flying = time <= _lastShotAt + AEGISM_INTERCEPTOR_SETTLE || {(_interceptors findIf { !isNull _x && {alive _x} }) != -1};
            if (_alive && {!_flying}) then {
                diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " MISSED: %1 (%2) salvo at %3 failed -- re-engaging.", _system, _role, _flightTarget];
            };
            _alive && _flying
        };
        _ts set ["inFlight_launcher", _inFlight];
        { _exclude pushBack (_x select 0); } forEach _inFlight;
    };
    private _turretCandidates = _candidates select { !((_x select 0) in _exclude) };

    // Target pick: a launcher reuses its pick for AEGISM_SELECT_REUSE s; an
    // empty pick is retried after AEGISM_SELECT_EMPTY_RETRY s; a gun checks
    // its current target first (aegism_intercept_fnc_selectTarget) -- and
    // while that target is still beyond its open-fire range (so every tick
    // would be a full re-pick, looking for one in range), re-picks at most
    // every AEGISM_SELECT_REUSE s.
    private _current = _state getOrDefault ["target", objNull];
    (_ts getOrDefault [_selectKey, [-1e9, objNull, []]]) params ["_selectedAt", "_selectedTarget", "_selectedWeapon"];
    private _currentAim = _ts getOrDefault ["aim_ciws", []];
    private _selection = switch (true) do {
        case (!_isCiws && {time - _selectedAt < AEGISM_SELECT_REUSE} && {!isNull _selectedTarget} && {alive _selectedTarget}
            && {!(_selectedTarget in _exclude)} && {_selectedWeapon in _weapons}): { [_selectedTarget, _selectedWeapon] };
        case (_isCiws && {time - _selectedAt < AEGISM_SELECT_REUSE} && {!isNull _current} && {alive _current} && {_selectedTarget == _current}
            && {!(_current in _exclude)} && {_selectedWeapon in _weapons}
            && {(_currentAim param [3, objNull]) == _current} && {!(_currentAim param [7, true])}): { [_current, _selectedWeapon] };
        case (isNull _selectedTarget && {isNull _current} && {time - _selectedAt < AEGISM_SELECT_EMPTY_RETRY}): { [objNull, []] };
        default {
            private _picked = [_weaponPos, _turretCandidates, _engagementSettings, _weapons, _role, _system, _current, _turretPath] call aegism_intercept_fnc_selectTarget;
            _ts set [_selectKey, [time, _picked select 0, _picked select 1]];
            _picked
        };
    };
    _selection params ["_target", "_weaponInfo"];

    if (isNull _target) then {
        if (!isNull _current) then { _ts set [_stateKey, createHashMap]; };
    } else {
        _taken pushBack _target;
        private _targetKey = [_target] call aegism_fnc_contactKey;
        if (_targetKey != (_state getOrDefault ["targetKey", ""])) then {
            _state = createHashMapFromArray [
                ["targetKey", _targetKey],
                ["target", _target],
                ["assignedAt", time],
                ["lastShotAt", -1],
                ["roundsFired", 0],
                ["interceptors", []]
            ];
        };
        _ts set [_stateKey, _state];

        if (_crew getOrDefault ["costValueJudgment", false]) then {
            private _targetValue = [[_target] call aegism_detect_fnc_classifyTarget] call aegism_intercept_fnc_threatValue;
            private _moreValuable = { ([_x select 1] call aegism_intercept_fnc_threatValue) > _targetValue } count _candidates;
            private _totalAmmo = 0;
            { _x params ["_weaponTurret", "", "_magClass"]; _totalAmmo = _totalAmmo + (_system magazineTurretAmmo [_magClass, _weaponTurret]); } forEach _readyWeapons;
            if (_moreValuable >= _totalAmmo) then { _state set ["nextAttemptAt", time + 1]; };
        };

        [_target, _weaponInfo, _state] call _fnExecute;

        // Salvo away: the missiles guide themselves and this launcher moves
        // on to its next target (re-picked next tick).
        if (!_isCiws && {(_state get "roundsFired") >= _salvoSize}) then {
            (_ts get "inFlight_launcher") pushBack [_target, _state get "interceptors", _state get "lastShotAt"];
            _ts set [_stateKey, createHashMap];
            _ts set [_selectKey, [-1e9, objNull, []]];
        };
    };
} forEach _byTurret;
