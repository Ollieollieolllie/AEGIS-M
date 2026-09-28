/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_engagementLoop

Description:
    One engagement tick for one role ("launcher" or "ciws") of one System,
    run on the server by a per-frame handler registered in aegism_system_
    fnc_moduleInit (every 0.5s for launchers, 0.1s for CIWS). Ammo is read
    live from the vehicle's real magazines; AEGIS-M counts nothing itself.

    NETWORKED (synced to a Site): executes every assignment the Site's
    coordinator (aegism_intercept_fnc_assignEngagements) currently holds for
    this System+role. It never picks targets itself.

    STANDALONE: picks its own target and weapon from its own pool
    (aegism_intercept_fnc_selectTarget) and keeps its own engagement state
    in "AEGISM_engagementState_<role>".

    Both paths run the same per-engagement sequence on an engagement state
    HashMap (a Site assignment record, or the standalone state) with keys
    assignedAt, lastShotAt, roundsFired, nextAttemptAt, interceptors:
        1. Aim (aegism_intercept_fnc_aimWeapon) -- every tick from the
           moment of assignment, so the turret is already on target when
           the crew finishes reacting.
        2. Crew reaction time since assignment (CIWS capped at
           AEGISM_CIWS_REACTION_CAP: automated fire control).
        3. Fire cadence:
             launcher - doctrine salvoSize per engagement, minShotInterval
                 between shots (both crew-modulated)
             ciws - sustained bursts (aegism_intercept_fnc_ciwsBurst) of a
                 random doctrine ciwsBurstMin..ciwsBurstMax seconds at the
                 gun's own rate of fire, ciwsBurstPause (crew-modulated)
                 between them, no salvo cap: point defence keeps firing
                 while it has a target. A running burst is cut short if the
                 target changes or LOS is lost. (It used to be one
                 BIS_fnc_fire per tick -- a 2-round pull in the gun's
                 "manual" mode -- about once a second.)
        4. LOS from this System (a Site contact may have been detected by a
           sibling with a different view).
        5. Alignment from step 1.
        6. Fire (aegism_intercept_fnc_fireWeapon). A failed crew
           reliability roll costs one fire cycle (nextAttemptAt).

    Every silent wait is logged once per engagement (REACTING, SLEWING
    every AEGISM_SLEW_LOG_INTERVAL s, LOS-BLOCKED on change), so an assigned
    weapon that isn't firing always says why in the RPT.

    Standalone re-engagement: once a launcher salvo is spent and every
    interceptor from it is gone while the target lives, the salvo is reset
    (the Site coordinator does the equivalent by re-assigning).

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

#define AEGISM_CIWS_REACTION_CAP 1
#define AEGISM_SLEW_LOG_INTERVAL 5
#define AEGISM_INTERCEPTOR_SETTLE 1.5
#define AEGISM_TURRET_RELEASE 1.5
// Weight of each new sample in a launcher's measured shot spacing.
#define AEGISM_SPACING_SMOOTHING 0.3

params ["_system", "_role"];

if (isNull _system || {!alive _system}) exitWith {};

private _isCiws = _role == "ciws";
private _systemData = _system getVariable ["AEGISM_system", createHashMap];
private _engagementSettings = _system getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_engagementSettings") then { _engagementSettings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
private _crew = _system getVariable "AEGISM_resolvedCrew";
if (isNil "_crew") then { _crew = [_system] call aegism_system_fnc_resolveCrew; };
private _crewMods = [_crew, _system] call aegism_intercept_fnc_applyCrewModulation;

private _weaponPool = _systemData getOrDefault [["launcherWeapons", "ciwsWeapons"] select _isCiws, []];
// eyePos is already ASL (it used to be wrapped in AGLToASL, which raised the
// LOS origin by the ground height under the vehicle).
private _weaponPos = eyePos _system;
private _network = _system getVariable ["AEGISM_network", objNull];

private _reactionTime = _crewMods get "reactionTime";
if (_isCiws) then { _reactionTime = _reactionTime min AEGISM_CIWS_REACTION_CAP; };
private _salvoSize = _engagementSettings getOrDefault ["salvoSize", 1];

// Hand a turret back to its crew once nothing has aimed it for
// AEGISM_TURRET_RELEASE s. While engaged, aegism_intercept_fnc_aimWeapon
// re-locks it every tick (0.5s at the slowest, the launcher interval).
{
    private _turretPath = _x select 0;
    private _lockKey = format ["AEGISM_turretLockAt_%1", _turretPath];
    private _lockedAt = _system getVariable [_lockKey, -1];
    if (_lockedAt >= 0 && {time - _lockedAt > AEGISM_TURRET_RELEASE}) then {
        _system setVariable [_lockKey, -1, false];
        [_system, _turretPath, objNull] call aegism_intercept_fnc_lockTurret;
    };
} forEach _weaponPool;

// Runs the aim/gate/fire sequence for one engagement (see header).
private _fnExecute = {
    params ["_target", "_weaponInfo", "_state"];
    _weaponInfo params ["_turretPath", "_weaponClass", "_magClass"];

    if ((_system magazineTurretAmmo [_magClass, _turretPath]) <= 0) exitWith {};

    // A launcher whose salvo is away has nothing left to do for this target
    // (its missiles guide themselves): it no longer aims at it, so the
    // turret is free for its next assignment while they fly. It used to keep
    // aiming at it until the kill/miss was known, holding the launcher idle.
    if (!_isCiws && {(_state get "roundsFired") >= _salvoSize}) exitWith {};

    ([_system, _target, _weaponInfo, _role] call aegism_intercept_fnc_aimWeapon) params ["_aligned", "_angle", "_tolerance", "", "_feasible"];

    if (time < (_state get "assignedAt") + _reactionTime) exitWith {
        if !(_state getOrDefault ["reactionLogged", false]) then {
            _state set ["reactionLogged", true];
            diag_log text format ["[AEGIS-M] REACTING: %1 (%2) on %3 -- crew reaction %4s, turret slewing meanwhile.", _system, _role, _target, _reactionTime];
        };
    };

    private _losClear = (lineIntersectsSurfaces [_weaponPos, getPosASL _target, _system, _target, true, 1]) isEqualTo [];

    // CIWS burst in progress: aegism_intercept_fnc_ciwsBurst fires it; this
    // tick (the aim above) keeps the turret on the lead point, and cuts the
    // burst short if it's on another target (re-assigned) or LOS is lost.
    private _burstKey = format ["AEGISM_ciwsBurst_%1", _turretPath];
    (_system getVariable [_burstKey, [-1, objNull, 0]]) params ["_burstEndsAt", "_burstTarget", "_burstId"];
    if (_isCiws && {time < _burstEndsAt}) exitWith {
        if (_burstTarget != _target || {!_losClear}) then {
            _system setVariable [_burstKey, [time, _burstTarget, _burstId], false];
        } else {
            _state set ["lastShotAt", time];
        };
    };

    // Launcher: minShotInterval since this LAUNCHER's last missile, whatever
    // it was fired at ("AEGISM_turretShotAt_<turretPath>"). CIWS: the burst
    // pause, counted from when the last burst ENDED (aegism_intercept_fnc_
    // ciwsBurst rewrites endsAt to the actual end time).
    private _interval = (_engagementSettings getOrDefault [["minShotInterval", "ciwsBurstPause"] select _isCiws, [4, 1] select _isCiws]) * (_crewMods get "shotIntervalMult");
    private _turretShotKey = format ["AEGISM_turretShotAt_%1", _turretPath];
    private _intervalFrom = [_system getVariable [_turretShotKey, -1], _burstEndsAt] select _isCiws;

    if (_intervalFrom >= 0 && {time < _intervalFrom + _interval}) exitWith {};
    if (time < (_state getOrDefault ["nextAttemptAt", -1])) exitWith {};

    if (!_losClear) exitWith {
        if !(_state getOrDefault ["losBlocked", false]) then {
            _state set ["losBlocked", true];
            diag_log text format ["[AEGIS-M] LOS-BLOCKED: %1 (%2) cannot see %3 -- holding, re-checking every tick.", _system, _role, _target];
        };
    };
    _state set ["losBlocked", false];

    if (!_feasible) exitWith {
        if (time > (_state getOrDefault ["lastSlewLog", -1e9]) + AEGISM_SLEW_LOG_INTERVAL) then {
            _state set ["lastSlewLog", time];
            diag_log text format ["[AEGIS-M] NO-SOLUTION: %1 (%2) holding on %3 -- no intercept inside the weapon's reach (target receding faster than the round can close, or meeting point beyond range).", _system, _role, _target];
        };
    };

    if (!_aligned) exitWith {
        if (time > (_state getOrDefault ["lastSlewLog", -1e9]) + AEGISM_SLEW_LOG_INTERVAL) then {
            _state set ["lastSlewLog", time];
            diag_log text format ["[AEGIS-M] SLEWING: %1 (%2) on %3 -- barrel %4 deg off aim point, need <= %5.", _system, _role, _target, round (_angle * 10) / 10, _tolerance];
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
            if (!_isCiws) then {
                // Measured time per missile when firing back to back (it
                // includes lost reliability rolls and re-aiming between
                // targets, which the configured interval alone doesn't) --
                // the Site coordinator plans each launcher's queue with it.
                // A gap longer than twice the estimate was idle time, not
                // firing rate, and is ignored.
                private _spacingKey = format ["AEGISM_turretSpacing_%1", _turretPath];
                private _spacing = _system getVariable [_spacingKey, _interval / ((_crewMods get "reliability") max 0.05)];
                private _gap = time - (_system getVariable [_turretShotKey, -1e9]);
                if (_gap <= 2 * _spacing) then {
                    _system setVariable [_spacingKey, (1 - AEGISM_SPACING_SMOOTHING) * _spacing + AEGISM_SPACING_SMOOTHING * _gap, false];
                };
            };
            _system setVariable [_turretShotKey, time, false];
        };
        case 0: {
            _state set ["nextAttemptAt", time + _interval];
        };
    };
};

if (!isNull _network) exitWith {
    // --- NETWORKED: execute every Site assignment for this System+role ---
    // Uses each record's own "target" object. The previous version resolved
    // the claims KEY through objectFromNetId, but keys were built with
    // str(netId), which adds literal quote characters -- objectFromNetId
    // returned objNull for every one, so no networked System ever executed
    // a single assignment.
    private _claims = _network getVariable ["AEGISM_claims", createHashMap];
    private _mine = [];
    {
        {
            private _target = _x getOrDefault ["target", objNull];
            if ((_x get "system") == _system && {(_x get "role") == _role} && {!isNull _target} && {alive _target}) then {
                _mine pushBack _x;
            };
        } forEach _y;
    } forEach _claims;

    // A launcher can hold a queue of targets (aegism_intercept_fnc_
    // assignEngagements): per turret, only the assignment whose target
    // IMPACTS SOONEST (and whose salvo isn't away yet) is worked this tick --
    // front to back through a salvo -- while the rest wait their turn
    // instead of fighting over the turret's aim.
    private _memberPositions = ((_network getVariable ["AEGISM_networkMembers", []]) select { !isNull _x && {alive _x} }) apply { getPosASL _x };
    _mine = [_mine, [_memberPositions], {
        private _target = _x get "target";
        [_target, _x getOrDefault ["class", [_target] call aegism_detect_fnc_classifyTarget], _input0] call aegism_intercept_fnc_timeToImpact
    }, "ASCEND"] call BIS_fnc_sortBy;
    private _workingTurrets = [];
    {
        (_x get "weaponInfo") params ["_turretPath"];
        private _salvoAway = !_isCiws && {(_x get "roundsFired") >= _salvoSize};
        if (_isCiws || _salvoAway || {!(_turretPath in _workingTurrets)}) then {
            if (!_isCiws && {!_salvoAway}) then { _workingTurrets pushBack _turretPath; };
            [_x get "target", _x get "weaponInfo", _x] call _fnExecute;
        };
    } forEach _mine;
};

// --- STANDALONE ---
private _stateKey = format ["AEGISM_engagementState_%1", _role];

private _readyWeapons = _weaponPool select {
    _x params ["_turretPath", "", "_magClass"];
    (_system magazineTurretAmmo [_magClass, _turretPath]) > 0
};
if (_readyWeapons isEqualTo []) exitWith {};

private _pool = _system getVariable ["AEGISM_pooledContacts", createHashMap];
private _candidates = (values _pool) apply { [_x get "object", _x get "class"] };

([_weaponPos, _candidates, _engagementSettings, _readyWeapons, _role, _system] call aegism_intercept_fnc_selectTarget) params ["_target", "_weaponInfo"];

private _state = _system getVariable [_stateKey, createHashMap];
if (isNull _target) exitWith {
    _state set ["targetNetId", ""];
    _system setVariable [_stateKey, _state, false];
};

private _targetNetId = netId _target;
if (_targetNetId != (_state getOrDefault ["targetNetId", ""])) then {
    _state = createHashMapFromArray [
        ["targetNetId", _targetNetId],
        ["target", _target],
        ["assignedAt", time],
        ["lastShotAt", -1],
        ["roundsFired", 0],
        ["interceptors", []]
    ];
};
_system setVariable [_stateKey, _state, false];

// Salvo spent, every interceptor gone, target alive: it missed -- re-engage.
if (!_isCiws && {(_state get "roundsFired") >= _salvoSize}
    && {time > (_state get "lastShotAt") + AEGISM_INTERCEPTOR_SETTLE}
    && {((_state get "interceptors") findIf { !isNull _x && {alive _x} }) == -1}) then {
    diag_log text format ["[AEGIS-M] MISSED: %1 (%2) salvo at %3 failed -- re-engaging.", _system, _role, _target];
    _state set ["roundsFired", 0];
    _state set ["interceptors", []];
};

if (_crew getOrDefault ["costValueJudgment", false]) then {
    private _targetValue = [[_target] call aegism_detect_fnc_classifyTarget] call aegism_intercept_fnc_threatValue;
    private _moreValuable = { ([_x select 1] call aegism_intercept_fnc_threatValue) > _targetValue } count _candidates;
    private _totalAmmo = 0;
    { _x params ["_turretPath", "", "_magClass"]; _totalAmmo = _totalAmmo + (_system magazineTurretAmmo [_magClass, _turretPath]); } forEach _readyWeapons;
    if (_moreValuable >= _totalAmmo) then { _state set ["nextAttemptAt", time + 1]; };
};

[_target, _weaponInfo, _state] call _fnExecute;
