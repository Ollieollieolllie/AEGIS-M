/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsRounds

Description:
    Tracks a CIWS gun's rounds in flight: proximity fuse against a munition
    target, and spotting against the target's predicted track. One handler
    per gun turret works through every round it has in the air (turret state
    "rounds"); it used to be one per-frame handler per ROUND -- a Phalanx
    firing ~53 rounds a second had 20-100 of them running at once.

    A round is only examined while it can be near the target: from half its
    predicted flight time to the intercept (the aim solve's own, turret state
    "trackTof") onward. Before that it's still on its way out and nothing is
    done with it.

    Fuse (munition targets): the engine has no projectile-vs-projectile
    collision, so a round passing through an incoming shell does nothing
    unless scripted. Hit radius: the round's own blast radius (CfgAmmo
    indirectHitRange) widened to the target's own half-size (aegism_
    intercept_fnc_targetHitRadius). Closest approach is computed on RELATIVE
    motion between frames (both move; at a 1500 m/s closing speed that's
    ~25m per frame). No detonation before the round's own CfgAmmo
    fuseDistance. On a hit: aegism_intercept_fnc_interceptHit. A round stops
    being fuzed once it has closed on the target and started opening (it
    can't come back), or the target is gone.

    Spotting (every AEGISM_SPOT_EVERY-th round, aegism_intercept_fnc_
    onSystemFired): the round's closest pass to the track the target was
    PREDICTED to fly when it was fired goes to aegism_intercept_fnc_
    ciwsSpot. Measuring against the prediction keeps the gun's own errors
    (turret lag, flight time, drop) apart from the target's evasion. A round
    that ends before it passes (it hit, or detonated) has its pass
    extrapolated from its last motion relative to the predicted target.
    Gun rounds against aircraft are tracked for spotting alone (the engine's
    own collision decides hits on aircraft).

    A round that hasn't resolved by twice its predicted flight time plus a
    second (or its CfgAmmo timeToLive if the flight time isn't known) is
    dropped.

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
#define AEGISM_ROUND_WINDOW_FRACTION 0.5

params ["_system", "_turretPath", "_ts", "_projectile", "_target", "_targetIsMunition", "_spot"];

if (isNull _projectile || {isNull _target}) exitWith {};

private _track = _ts getOrDefault ["track", []];
private _spotting = _spot && {_track isNotEqualTo []};

// Per-target constants, worked out once while the gun stays on one target.
private _targetInfo = _ts getOrDefault ["roundTarget", []];
if ((_targetInfo param [0, objNull]) != _target || {(_targetInfo param [1, ""]) != typeOf _projectile}) then {
    private _roundCfg = configOf _projectile;
    private _targetRadius = [_target] call aegism_intercept_fnc_targetHitRadius;
    private _blastRadius = [typeOf _projectile] call aegism_intercept_fnc_munitionSize;
    private _lifetime = getNumber (_roundCfg >> "timeToLive");
    _targetInfo = [_target, typeOf _projectile, _targetRadius, [_blastRadius, _blastRadius max _targetRadius] select _targetIsMunition,
        getNumber (_roundCfg >> "fuseDistance"), [1e10, _lifetime] select (_lifetime > 0), [_target] call aegism_detect_fnc_classifyTarget];
    _ts set ["roundTarget", _targetInfo];
};
_targetInfo params ["", "_roundClass", "_targetRadius", "_hitRadius", "_armDistance", "_lifetime", "_targetClass"];

private _fuzed = _targetIsMunition && {_hitRadius > 0};
if (!_fuzed && {!_spotting}) exitWith {};

PERF_INC(PERF_ROUNDS_ADDED);

private _tof = _ts getOrDefault ["trackTof", -1];
private _windowAt = time + ((_tof * AEGISM_ROUND_WINDOW_FRACTION) max 0);
private _expiresAt = time + ([_lifetime, 2 * _tof + 1] select (_tof > 0));
private _spotData = if (_spotting) then {
    [_system, _turretPath, (_ts getOrDefault ["burst", [0, objNull, 0]]) select 2,
        +((_ts getOrDefault ["corrections", createHashMap]) getOrDefault [_targetClass, [0, 0]]), _track, _roundClass, _targetClass]
} else { [] };

private _rounds = _ts get "rounds";
if (isNil "_rounds") then { _rounds = []; _ts set ["rounds", _rounds]; };
// 0 projectile, 1 target, 2 launch time, 3 launch pos, 4 window opens, 5
// expires, 6 spot data, 7 hit radius (0 = not fuzed), 8 target radius, 9
// arm distance, 10 primed, 11 last round pos, 12 last target pos, 13 last
// separation, 14 closed on target, 15 fuse done, 16 spotted, 17 last
// round-ghost offset, 18 last ghost separation, 19 closed on ghost, 20
// round-ghost relative velocity
_rounds pushBack [_projectile, _target, time, getPosASLVisual _projectile, _windowAt, _expiresAt, _spotData, [0, _hitRadius] select _fuzed, _targetRadius, _armDistance,
    false, [0, 0, 0], [0, 0, 0], 1e10, false, !_fuzed, !_spotting, [0, 0, 0], 1e10, false, [0, 0, 0]];

if (_ts getOrDefault ["roundsRunning", false]) exitWith {};
_ts set ["roundsRunning", true];

[{
    params ["_args", "_pfhHandle"];
    _args params ["_ts", "_rounds"];

    private _started = diag_tickTime;

    // The predicted target now: [position, velocity].
    private _fnGhost = {
        (_this select 4) params ["_trackTime", "_trackPos", "_trackVelocity", "_trackAcceleration"];
        private _dt = time - _trackTime;
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
        [_spot, _miss, _ghostPos, _ghostVelocity, time - _launchTime, _targetRadius, _deviation] call aegism_intercept_fnc_ciwsSpot;
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
        if (isNull _projectile || {!alive _projectile} || {time > (_round select 5)}) then {
            if ((_round select 10) && {!(_round select 16)}) then { [_round] call _fnSpotExtrapolated; };
            _remove = true;
        } else {
            // Still on its way out: nothing to do yet (most rounds, most frames).
            if (time < (_round select 4)) then {
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
                            private _targetPos = getPosASLVisual _target;
                            _round set [11, _projPos];
                            _round set [12, _targetPos];
                            _round set [13, _projPos distance _targetPos];
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
                            _round set [20, _seg vectorMultiply (1 / (diag_deltaTime max 0.001))];
                        };
                    };

                    // --- Proximity fuse against the real target.
                    if (!_realDone) then {
                        if (isNull _target || {!alive _target}) then {
                            _realDone = true;
                        } else {
                            private _targetPos = getPosASLVisual _target;
                            private _rel0 = _lastProjPos vectorDiff _lastTargetPos;
                            private _rel1 = _projPos vectorDiff _targetPos;
                            private _seg = _rel1 vectorDiff _rel0;
                            private _segLenSqr = _seg vectorDotProduct _seg;
                            private _minDistance = vectorMagnitude (if (_segLenSqr <= 0.0001) then {
                                _rel1
                            } else {
                                _rel0 vectorAdd (_seg vectorMultiply (0 max (1 min (-(_rel0 vectorDotProduct _seg) / _segLenSqr))))
                            });
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
