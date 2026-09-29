/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsGate

Description:
    A CIWS gun's fire gate for one aim: whether a round fired now would pass
    close enough to hit, recorded as the turret's "aim_ciws" [angle,
    tolerance, time, target, feasible, aligned, aimPoint] -- what its burst
    (aegism_intercept_fnc_ciwsBurst) checks every frame. Run on every full
    solve (aegism_intercept_fnc_aimWeapon) and every steered frame in
    between (aegism_intercept_fnc_ciwsTrack).

        aligned - a feasible intercept and the barrel within tolerance: the
            target's half-size plus the gun's dispersion, as an angle at the
            intercept distance
        LAST-DITCH - once the target is due to impact within the gun's own
            longest burst (doctrine ciwsBurstMax), it also fires as soon as
            the turret has settled -- stopped closing on the aim point for
            AEGISM_AIM_SETTLE_TICKS engagement ticks -- wherever that is,
            as long as it's within AEGISM_LAST_DITCH_MAX_GATES times the
            gate: there's no later, better shot, and holding fire guarantees
            the round lands. A Praetorian followed a shell to the ground 0.3
            degrees off a 0.28-degree gate (1.1x); the cap stops what came
            after -- the last shell of a salvo took 113 rounds at 6.3
            degrees (22x the gate), with no chance of a hit. Logged once per
            target either way (LAST-DITCH / LAST-DITCH-HOLD).

Parameters:
    _system - the CIWS vehicle <OBJECT>
    _ts - its gun turret's state (aegism_intercept_fnc_turretState) <HASHMAP>
    _target - the target <OBJECT>
    _targetClass - its threat class <STRING>
    _angle - barrel off the aim point, degrees <NUMBER>
    _tolerance - the gate, degrees <NUMBER>
    _feasible - an intercept exists <BOOLEAN>
    _aimPoint - the aim point, ASL <ARRAY>

Returns:
    Aligned <BOOLEAN>

Examples:
    [_praetorian, _ts, _shell, "artilleryShell", 0.4, 0.28, true, _aimPoint] call aegism_intercept_fnc_ciwsGate;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_AIM_SETTLE_TICKS 2
// Engagement loop tick (modules_system moduleInit): "settled" is measured
// over this many seconds per settle tick.
#define AEGISM_ENGAGEMENT_TICK 0.1
#define AEGISM_LAST_DITCH_MAX_GATES 5

params ["_system", "_ts", "_target", "_targetClass", "_angle", "_tolerance", "_feasible", "_aimPoint"];

private _aligned = _feasible && {_angle <= _tolerance};

// Settled: the angle hasn't set a new best for AEGISM_AIM_SETTLE_TICKS
// engagement ticks -- the turret is as close as it's going to get.
(_ts getOrDefault ["settle", [objNull, 1e9, time]]) params ["_settleTarget", "_bestAngle", "_improvedAt"];
if (_settleTarget != _target || {_angle < _bestAngle}) then { _settleTarget = _target; _bestAngle = _angle; _improvedAt = time; };
_ts set ["settle", [_settleTarget, _bestAngle, _improvedAt]];

if (_feasible && {!_aligned} && {time - _improvedAt >= AEGISM_AIM_SETTLE_TICKS * AEGISM_ENGAGEMENT_TICK}) then {
    private _settings = _system getVariable "AEGISM_resolvedEngagementSettings";
    if (isNil "_settings") then { _settings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
    private _timeToImpact = [_target, _targetClass, [getPosASL _system]] call aegism_intercept_fnc_timeToImpact;
    if (_timeToImpact <= (_settings getOrDefault ["ciwsBurstMax", 5])) then {
        if (_angle <= AEGISM_LAST_DITCH_MAX_GATES * _tolerance) then {
            _aligned = true;
            if ((_ts getOrDefault ["lastDitchLogged", objNull]) != _target) then {
                _ts set ["lastDitchLogged", _target];
                diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " LAST-DITCH: %1 (ciws) on %2 -- impact in %3s, turret settled %4 deg off the aim point (gate %5): firing anyway.",
                    _system, _target, round (_timeToImpact * 10) / 10, round (_angle * 100) / 100, round (_tolerance * 100) / 100];
            };
        } else {
            if ((_ts getOrDefault ["lastDitchHeld", objNull]) != _target) then {
                _ts set ["lastDitchHeld", _target];
                diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " LAST-DITCH-HOLD: %1 (ciws) on %2 -- impact in %3s, turret settled %4 deg off the aim point, over %5x the %6 deg gate: no chance of a hit, holding fire.",
                    _system, _target, round (_timeToImpact * 10) / 10, round (_angle * 100) / 100, AEGISM_LAST_DITCH_MAX_GATES, round (_tolerance * 100) / 100];
            };
        };
    };
};

_ts set ["aim_ciws", [_angle, _tolerance, time, _target, _feasible, _aligned, _aimPoint]];
_aligned
