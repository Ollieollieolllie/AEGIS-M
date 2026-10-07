/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsTrack

Description:
    Keeps a CIWS gun's turret on its intercept point EVERY FRAME for as long
    as it has a target, not just while a burst is running, and returns the
    gun's current aim for the engagement loop.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the CIWS vehicle <OBJECT>
    _turretPath - its gun's turret path <ARRAY>

Returns:
    [aligned, angle, tolerance, aimPoint, feasible, inRange] -- the gun's
    current aim at its track target <ARRAY>

Examples:
    [_praetorian, [0]] call aegism_intercept_fnc_ciwsTrack;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"

#define AEGISM_TRACK_STALE 0.5
#define AEGISM_CIWS_SOLVE_INTERVAL 0.05

params ["_system", "_turretPath"];

private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;

// One frame of tracking. Returns the aim tuple.
private _fnTrack = {
    params ["_system", "_turretPath", "_ts"];
    (_ts getOrDefault ["trackTarget", [objNull, [], -1e9]]) params ["_target", "_weaponInfo"];

    private _solve = _ts getOrDefault ["solve", []];
    if (_solve isEqualTo [] || {(_solve select 8) != _target} || {CBA_missionTime - (_solve select 0) >= AEGISM_CIWS_SOLVE_INTERVAL}) exitWith {
        [_system, _target, _weaponInfo, "ciws"] call aegism_intercept_fnc_aimWeapon
    };

    PERF_INC(PERF_STEER_FRAMES);
    _solve params ["_solvedAt", "_solvedAim", "_aimVelocity", "_cameraOffset", "_origin", "_tolerance", "_feasible", "_interceptDistance", "", "_targetClass", "_openFireRange", "_minRange"];
    private _aimPoint = _solvedAim vectorAdd (_aimVelocity vectorMultiply (CBA_missionTime - _solvedAt));
    if (_system turretLocal _turretPath) then {
        _system lockCameraTo [_aimPoint vectorAdd _cameraOffset, _turretPath, false];
        _ts set ["lockAt", CBA_missionTime];
    };
    _ts set ["ciwsAimAt", CBA_missionTime];

    private _barrel = [_system, _turretPath, _weaponInfo select 1] call aegism_intercept_fnc_barrelDirection;
    private _angle = acos (((_barrel vectorCos (_origin vectorFromTo _aimPoint)) min 1) max -1);
    private _aligned = [_system, _ts, _target, _targetClass, _angle, _tolerance, _feasible, _aimPoint, _interceptDistance, _openFireRange, _minRange] call aegism_intercept_fnc_ciwsGate;
    [_aligned, _angle, _tolerance, _aimPoint, _feasible, _interceptDistance <= _openFireRange && {_interceptDistance >= _minRange}]
};

if !(_ts getOrDefault ["tracking", false]) then {
    _ts set ["tracking", true];
    [{
        params ["_args", "_pfhHandle"];
        _args params ["_system", "_turretPath", "_ts", "_fnTrack"];

        if (isNull _system || {!alive _system}) exitWith {
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
            _ts set ["tracking", false];
        };
        (_ts getOrDefault ["trackTarget", [objNull, [], -1e9]]) params ["_target", "", "_handedAt"];
        if (CBA_missionTime - _handedAt > AEGISM_TRACK_STALE || {isNull _target} || {!alive _target}) exitWith {
            [_pfhHandle] call CBA_fnc_removePerFrameHandler;
            _ts set ["tracking", false];
        };
        // Already aimed this frame (the engagement tick ran first).
        if (((_ts getOrDefault ["aim_ciws", [0, 0, -1]]) select 2) == CBA_missionTime) exitWith {};
        // A turret owned by another machine is aimed at the engagement tick
        // only: a lock every frame would be a network message every frame.
        if (_system turretLocal _turretPath) then { [_system, _turretPath, _ts] call _fnTrack; };
    }, 0, [_system, _turretPath, _ts, _fnTrack]] call CBA_fnc_addPerFrameHandler;
};

// The aim for the engagement loop: this frame's, if the tracker already ran.
private _target = (_ts getOrDefault ["trackTarget", [objNull]]) select 0;
private _aim = _ts getOrDefault ["aim_ciws", []];
if (_aim isNotEqualTo [] && {(_aim select 3) == _target} && {(_aim select 2) == CBA_missionTime}) exitWith {
    _aim params ["_angle", "_tolerance", "", "", "_feasible", "_aligned", "_aimPoint", ["_inRange", true]];
    [_aligned, _angle, _tolerance, _aimPoint, _feasible, _inRange]
};
[_system, _turretPath, _ts] call _fnTrack
