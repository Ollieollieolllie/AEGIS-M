/* ----------------------------------------------------------------------------
Function: aegism_fnc_perfLog

Description:
    Writes one PERF line to the RPT summarising what AEGIS-M did on this
    machine since the last one (the counters in AEGISM_perfCounts, see
    perf.hpp), then resets them.
    Full notes: docs/functions/main.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_fnc_perfLog;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\perf.hpp"

private _c = +AEGISM_perfCounts;
private _active = ((_c select [0, PERF_WORK_COUNT]) findIf { _x > 0 }) != -1;
private _span = diag_tickTime - (missionNamespace getVariable ["AEGISM_perfWindowStart", diag_tickTime - 10]);
private _missionSpan = CBA_missionTime - (missionNamespace getVariable ["AEGISM_perfWindowMission", CBA_missionTime]);
private _gameSpan = time - (missionNamespace getVariable ["AEGISM_perfWindowGame", time]);

AEGISM_perfCounts = [];
AEGISM_perfCounts resize [PERF_COUNT, 0];
missionNamespace setVariable ["AEGISM_perfWindowStart", diag_tickTime];
missionNamespace setVariable ["AEGISM_perfWindowMission", CBA_missionTime];
missionNamespace setVariable ["AEGISM_perfWindowGame", time];

if (!_active) exitWith {};

private _ms = { (round (_this * 10)) / 10 };

diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " PERF: coord %1 runs %2ms (max %3ms; review %28 / reserve %29 / assign %30ms) + %32ms in %31 frames between, %33 looks put off | ticks %4 | aim %5 solves / %6 steers | rounds %7 tracked, %8 checks, %9 waits, %10ms | canEngage %11 | select %12 | fired %13 / threats %14 / ignored %15 | tracker %16 checks, %18ms | sensors %17 munitions seen, %27 rays, %24ms | plan %19 hit / %20 built / %26 solves | openFire %23 built | fps %21 avg, worst frame %22ms, %25 slow frames | clock %34s mission / %35s game in %36s real",
    _c select PERF_COORD_RUNS, (_c select PERF_COORD_MS) call _ms, (_c select PERF_COORD_MAX_MS) call _ms,
    _c select PERF_ENGAGE_TICKS,
    _c select PERF_AIM_SOLVES, _c select PERF_STEER_FRAMES,
    _c select PERF_ROUNDS_ADDED, _c select PERF_ROUND_CHECKS, _c select PERF_ROUND_WAITS, (_c select PERF_ROUNDS_MS) call _ms,
    _c select PERF_CAN_ENGAGE,
    _c select PERF_SELECT_FULL,
    _c select PERF_FIRED_EH, _c select PERF_FIRED_THREATS, _c select PERF_IGNORED,
    _c select PERF_TRACKER_CHECKS, _c select PERF_MUNITIONS_SEEN, (_c select PERF_TRACKER_MS) call _ms,
    _c select PERF_PLAN_HITS, _c select PERF_PLAN_BUILDS,
    round ((_c select PERF_FRAMES) / (_span max 0.001)), round (_c select PERF_FRAME_MAX_MS),
    _c select PERF_OPEN_FIRE_BUILDS, (_c select PERF_SENSOR_MS) call _ms,
    _c select PERF_SLOW_FRAMES, _c select PERF_PLAN_SOLVES, _c select PERF_LOS_RAYS,
    (_c select PERF_COORD_REVIEW_MS) call _ms, (_c select PERF_COORD_RESERVE_MS) call _ms, (_c select PERF_COORD_ASSIGN_MS) call _ms, _c select PERF_COORD_CARRIED, (_c select PERF_COORD_AHEAD_MS) call _ms, _c select PERF_COORD_PUT_OFF,
    _missionSpan call _ms, _gameSpan call _ms, _span call _ms];
