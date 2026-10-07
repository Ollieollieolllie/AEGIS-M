/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsRounds

Description:
    Tracks a CIWS gun's rounds in flight: proximity fuse against a munition
    target, and spotting against the target's predicted track.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the CIWS vehicle <OBJECT>
    _turretPath - its gun turret <ARRAY>
    _ts - that turret's state <HASHMAP>
    _projectile - the round <OBJECT>
    _target - its target <OBJECT>
    _targetIsMunition - fuze it <BOOLEAN>
    _spot - measure it for spotting <BOOLEAN>

Returns:
    Nothing

Examples:
    [_praetorian, [0], _ts, _round, _shell, true, false] call aegism_intercept_fnc_ciwsRounds;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

// Rounds are examined from this fraction of their predicted flight time on.
#define AEGISM_ROUND_WINDOW_FRACTION 0.8

params ["_system", "_turretPath", "_ts", "_projectile", "_target", "_targetIsMunition", "_spot"];

if (isNull _projectile || {isNull _target}) exitWith {};

private _track = _ts getOrDefault ["track", []];
// Not a round fired only by the last-ditch rule, its barrel off the gate
// (aegism_intercept_fnc_ciwsGate): its miss is the barrel being off, not the
// gun's aim, and would throw the gun's correction and measured scatter.
private _spotting = _spot && {_track isNotEqualTo []} && {!(_ts getOrDefault ["gateOverride", false])};

// Per-target constants, worked out once while the gun stays on one target.
private _targetInfo = _ts getOrDefault ["roundTarget", []];
if ((_targetInfo param [0, objNull]) != _target || {(_targetInfo param [1, ""]) != typeOf _projectile}) then {
    private _roundCfg = configOf _projectile;
    private _targetRadius = [_target] call aegism_intercept_fnc_targetHitRadius;
    // The round's own radius: its blast or its proximity fuse.
    private _roundRadius = ([typeOf _projectile] call aegism_intercept_fnc_munitionSize) max getNumber (_roundCfg >> "proximityExplosionDistance");
    ([typeOf _projectile] call aegism_intercept_fnc_ammoBurst) params ["_lifetime", "", "_burstRadius"];
    _targetInfo = [_target, typeOf _projectile, _targetRadius, _roundRadius,
        getNumber (_roundCfg >> "fuseDistance"), [1e10, _lifetime] select (_lifetime > 0), [_target] call aegism_detect_fnc_classifyTarget, _burstRadius];
    _ts set ["roundTarget", _targetInfo];
};
_targetInfo params ["", "_roundClass", "_targetRadius", "_hitRadius", "_armDistance", "_lifetime", "_targetClass", "_burstRadius"];

// Every round is fuzed against a munition (a ball round only by passing
// through its body).
private _fuzed = _targetIsMunition;
if (!_fuzed && {!_spotting}) exitWith {};

// An airburst round: where it bursts, the target's body within the blast is
// a kill too.
if (_fuzed && {_burstRadius > 0}) then {
    _projectile setVariable ["AEGISM_burstAt", [_target, _burstRadius]];
    _projectile addEventHandler ["SubmunitionCreated", {
        params ["_round", "_burst"];
        (_round getVariable ["AEGISM_burstAt", []]) params [["_target", objNull], ["_radius", 0]];
        if (isNull _target || {!alive _target} || {isNull _burst}) exitWith {};
        private _rel = (getPosWorldVisual _burst) vectorDiff (getPosWorldVisual _target);
        private _miss = [_target, _rel, _rel, _radius] call aegism_intercept_fnc_bodyPass;
        if (_miss <= _radius) then {
            [_burst, _target, true, _miss, _radius] call aegism_intercept_fnc_interceptHit;
        };
    }];
};

PERF_INC(PERF_ROUNDS_ADDED);

private _tof = _ts getOrDefault ["trackTof", -1];
private _windowAt = CBA_missionTime + ((_tof * AEGISM_ROUND_WINDOW_FRACTION) max 0);
private _expiresAt = CBA_missionTime + ([_lifetime, 2 * _tof + 1] select (_tof > 0));
private _spotData = if (_spotting) then {
    [_system, _turretPath, (_ts getOrDefault ["burst", [0, objNull, 0]]) select 2,
        +((_ts getOrDefault ["corrections", createHashMap]) getOrDefault [_targetClass, [0, 0]]), _track, _roundClass, _targetClass]
} else { [] };

private _rounds = _ts get "rounds";
if (isNil "_rounds") then { _rounds = []; _ts set ["rounds", _rounds]; };
// 0 projectile, 1 target, 2 launch time, 3 launch pos, 4 window opens, 5
// expires, 6 spot data, 7 the round's own radius, 8 target radius, 9 arm
// distance, 10 primed, 11 last round pos, 12 last target pos (its model
// origin), 13 last separation, 14 closed on target, 15 fuse done, 16
// spotted, 17 last round-ghost offset, 18 last ghost separation, 19 closed
// on ghost, 20 round-ghost relative velocity, 21 the round's last velocity,
// 22 its ammo class
_rounds pushBack [_projectile, _target, CBA_missionTime, getPosASLVisual _projectile, _windowAt, _expiresAt, _spotData, _hitRadius, _targetRadius, _armDistance,
    false, [0, 0, 0], [0, 0, 0], 1e10, false, !_fuzed, !_spotting, [0, 0, 0], 1e10, false, [0, 0, 0], [0, 0, 0], _roundClass];

if (_ts getOrDefault ["roundsRunning", false]) exitWith {};
_ts set ["roundsRunning", true];

[{
    params ["_args", "_pfhHandle"];
    _args params ["_ts", "_rounds"];

    private _started = diag_tickTime;

    // The predicted target now: [position, velocity].
    private _fnGhost = {
        (_this select 4) params ["_trackTime", "_trackPos", "_trackVelocity", "_trackAcceleration"];
        private _dt = CBA_missionTime - _trackTime;
        [
            _trackPos vectorAdd (_trackVelocity vectorMultiply _dt) vectorAdd (_trackAcceleration vectorMultiply (0.5 * _dt * _dt)),
            _trackVelocity vectorAdd (_trackAcceleration vectorMultiply _dt)
        ]
    };
    // Reports one pass of the predicted target, with how far the real target
    // strayed from it at that moment (its evasion; -1 if it's gone).
    private _fnSpot = {
        params ["_round", "_miss", "_ghostPos", "_ghostVelocity"];
        _round params ["", "_target", "_launchTime", "", "", "", "_spot", "", "_targetRadius"];
        private _deviation = if (!isNull _target && {alive _target}) then { (getPosASLVisual _target) distance _ghostPos } else { -1 };
        [_spot, _miss, _ghostPos, _ghostVelocity, CBA_missionTime - _launchTime, _targetRadius, _deviation] call aegism_intercept_fnc_ciwsSpot;
    };
    // The round ended before passing the predicted target: extrapolate its
    // pass from its last relative motion -- only if it was still closing.
    private _fnSpotExtrapolated = {
        params ["_round"];
        private _rel = _round select 17;
        private _relVelocity = _round select 20;
        private _closing = _rel vectorDotProduct _relVelocity;
        private _speedSqr = _relVelocity vectorDotProduct _relVelocity;
        if (_closing < 0 && {_speedSqr > 0}) then {
            ((_round select 6) call _fnGhost) params ["_ghostPos", "_ghostVelocity"];
            [_round, _rel vectorAdd (_relVelocity vectorMultiply (-_closing / _speedSqr)), _ghostPos, _ghostVelocity] call _fnSpot;
        };
    };

    for "_i" from (count _rounds - 1) to 0 step -1 do {
        private _round = _rounds select _i;
        private _projectile = _round select 0;

        private _remove = false;
        if (isNull _projectile || {!alive _projectile} || {CBA_missionTime > (_round select 5)}) then {
            // Gone since the last frame, still fuzed: if the stretch it was
            // on -- from where it was, at the velocity it had, for this
            // frame -- comes within its own radius of the target's body, it
            // went off within reach of it (its own fuse, the game's): a hit.
            if ((isNull _projectile || {!alive _projectile}) && {_round select 10} && {!(_round select 15)}) then {
                _round params ["", "_target", "", "_launchPos", "", "", "", "_hitRadius", "", "_armDistance", "", "_lastProjPos", "_lastTargetPos"];
                if (!isNull _target && {alive _target} && {(_launchPos distance _lastProjPos) >= _armDistance}) then {
                    private _end = _lastProjPos vectorAdd ((_round select 21) vectorMultiply AEGISM_frameDelta);
                    private _miss = [_target, _lastProjPos vectorDiff _lastTargetPos, _end vectorDiff (getPosWorldVisual _target), _hitRadius] call aegism_intercept_fnc_bodyPass;
                    if (_miss <= _hitRadius) then {
                        [_projectile, _target, true, _miss, _hitRadius, _end, _round select 22] call aegism_intercept_fnc_interceptHit;
                    };
                };
            };
            if ((_round select 10) && {!(_round select 16)}) then { [_round] call _fnSpotExtrapolated; };
            _remove = true;
        } else {
            // Still on its way out: nothing to do yet (most rounds, most frames).
            if (CBA_missionTime < (_round select 4)) then {
                PERF_INC(PERF_ROUND_WAITS);
            } else {
                PERF_INC(PERF_ROUND_CHECKS);
                _round params ["", "_target", "", "_launchPos", "", "", "_spot", "_hitRadius", "", "_armDistance",
                    "_primed", "_lastProjPos", "_lastTargetPos", "_lastSeparation", "_hasClosed", "_realDone", "_spotted", "_lastGhostRel", "_lastGhostSeparation", "_ghostClosed"];
                private _projPos = getPosASLVisual _projectile;

                if (!_primed) then {
                    // First look: take the positions, compare from next frame.
                    _round set [10, true];
                    if (!_spotted) then {
                        private _rel = _projPos vectorDiff ((_spot call _fnGhost) select 0);
                        _round set [17, _rel];
                        _round set [18, vectorMagnitude _rel];
                    };
                    if (!_realDone) then {
                        if (isNull _target || {!alive _target}) then {
                            _round set [15, true];
                        } else {
                            private _targetPos = getPosWorldVisual _target;
                            _round set [11, _projPos];
                            _round set [12, _targetPos];
                            _round set [13, _projPos distance _targetPos];
                            _round set [21, velocity _projectile];
                        };
                    };
                } else {
                    // --- Spotting: the round against the predicted target.
                    if (!_spotted) then {
                        (_spot call _fnGhost) params ["_ghostPos", "_ghostVelocity"];
                        private _rel1 = _projPos vectorDiff _ghostPos;
                        private _seg = _rel1 vectorDiff _lastGhostRel;
                        private _segLenSqr = _seg vectorDotProduct _seg;
                        private _closest = if (_segLenSqr <= 0.0001) then {
                            _rel1
                        } else {
                            _lastGhostRel vectorAdd (_seg vectorMultiply (0 max (1 min (-(_lastGhostRel vectorDotProduct _seg) / _segLenSqr))))
                        };
                        private _separation = vectorMagnitude _rel1;
                        if (_separation < _lastGhostSeparation) then { _ghostClosed = true; };
                        if (_ghostClosed && {_separation > _lastGhostSeparation}) then {
                            [_round, _closest, _ghostPos, _ghostVelocity] call _fnSpot;
                            _spotted = true;
                            _round set [16, true];
                        } else {
                            _round set [17, _rel1];
                            _round set [18, _separation];
                            _round set [19, _ghostClosed];
                            _round set [20, _seg vectorMultiply (1 / (AEGISM_frameDelta max 0.001))];
                        };
                    };

                    // --- Proximity fuse against the real target.
                    if (!_realDone) then {
                        if (isNull _target || {!alive _target}) then {
                            _realDone = true;
                        } else {
                            // The round's path this frame against the
                            // target's body (aegism_intercept_fnc_bodyPass).
                            private _targetPos = getPosWorldVisual _target;
                            private _rel0 = _lastProjPos vectorDiff _lastTargetPos;
                            private _rel1 = _projPos vectorDiff _targetPos;
                            private _minDistance = [_target, _rel0, _rel1, _hitRadius] call aegism_intercept_fnc_bodyPass;
                            private _separation = vectorMagnitude _rel1;
                            if (_minDistance <= _hitRadius && {(_launchPos distance _projPos) >= _armDistance}) then {
                                [_projectile, _target, true, _minDistance, _hitRadius] call aegism_intercept_fnc_interceptHit;
                                if (!_spotted) then { [_round] call _fnSpotExtrapolated; };
                                _remove = true;
                            } else {
                                if (_separation < _lastSeparation) then { _hasClosed = true; };
                                // Unguided: once it has closed and started opening, it can't come back.
                                if (_hasClosed && {_separation > _lastSeparation}) then { _realDone = true; };
                                _round set [11, _projPos];
                                _round set [12, _targetPos];
                                _round set [13, _separation];
                                _round set [14, _hasClosed];
                                _round set [21, velocity _projectile];
                            };
                        };
                        _round set [15, _realDone];
                    };

                    if (_realDone && {_spotted}) then { _remove = true; };
                };
            };
        };
        if (_remove) then { _rounds deleteAt _i; };
    };

    PERF_ADD(PERF_ROUNDS_MS,(diag_tickTime - _started) * 1000);

    if (_rounds isEqualTo []) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        _ts set ["roundsRunning", false];
    };
}, 0, [_ts, _rounds]] call CBA_fnc_addPerFrameHandler;
