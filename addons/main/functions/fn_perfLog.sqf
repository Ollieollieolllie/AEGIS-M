/* ----------------------------------------------------------------------------
Function: aegism_fnc_perfLog

Description:
    Writes one PERF line to the RPT summarising what AEGIS-M did on this
    machine since the last one (the counters in AEGISM_perfCounts, see
    perf.hpp), then resets them. Registered on the server every
    AEGISM_PERF_INTERVAL seconds (main XEH_postInit) while the CBA setting
    "RPT Performance Summary" is on. Silent when nothing happened, so an
    idle mission logs nothing.

    Columns (per interval):
        coord - Site coordinator runs, total and worst single run (ms)
        ticks - engagement loop ticks that had work to do
        aim - full CIWS/launcher aim solves / CIWS per-frame steers
        rounds - CIWS rounds tracked, per-frame checks near the target,
            frames skipped while still in flight, total ms in the round
            manager
        canEngage - engageability checks (coordinator + standalone)
        select - standalone full target re-evaluations
        fired - Fired events seen / threats among them / ignored as landing
            clear of every Site
        tracker - munition tracker checks, radar LOS rays, total ms
        plan - reserve plan cache hits / rebuilds
        openFire - CIWS open-fire range recalculations (aegism_intercept_
            fnc_openFireRange; at most one a second per gun and target type)
        fps - server FPS now / minimum over the last 16 frames

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
private _active = (_c findIf { _x > 0 }) != -1;

AEGISM_perfCounts = [];
AEGISM_perfCounts resize [PERF_COUNT, 0];

if (!_active) exitWith {};

private _ms = { (round (_this * 10)) / 10 };

diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " PERF: coord %1 runs %2ms (max %3ms) | ticks %4 | aim %5 solves / %6 steers | rounds %7 tracked, %8 checks, %9 waits, %10ms | canEngage %11 | select %12 | fired %13 / threats %14 / ignored %15 | tracker %16 checks, %17 LOS, %18ms | plan %19 hit / %20 built | openFire %23 built | fps %21 (min %22)",
    _c select PERF_COORD_RUNS, (_c select PERF_COORD_MS) call _ms, (_c select PERF_COORD_MAX_MS) call _ms,
    _c select PERF_ENGAGE_TICKS,
    _c select PERF_AIM_SOLVES, _c select PERF_STEER_FRAMES,
    _c select PERF_ROUNDS_ADDED, _c select PERF_ROUND_CHECKS, _c select PERF_ROUND_WAITS, (_c select PERF_ROUNDS_MS) call _ms,
    _c select PERF_CAN_ENGAGE,
    _c select PERF_SELECT_FULL,
    _c select PERF_FIRED_EH, _c select PERF_FIRED_THREATS, _c select PERF_IGNORED,
    _c select PERF_TRACKER_CHECKS, _c select PERF_LOS_RAYS, (_c select PERF_TRACKER_MS) call _ms,
    _c select PERF_PLAN_HITS, _c select PERF_PLAN_BUILDS,
    round diag_fps, round diag_fpsMin,
    _c select PERF_OPEN_FIRE_BUILDS];
