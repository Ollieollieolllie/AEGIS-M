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
        tracker - munition tracker checks, total ms (creating each
            munition's sensor proxy, and moving those that aren't attached
            every frame, included)
        sensors - vehicles' sensor reads (aegism_detect_fnc_confidenceLoop):
            munition proxies seen across them, total ms
        plan - reserve plan cache hits / rebuilds / intercept solves it ran
            (aegism_intercept_fnc_assignEngagements' _fnPlanShot)
        openFire - CIWS open-fire range recalculations (aegism_intercept_
            fnc_openFireRange; at most one a second per gun and target type)
        fps - the server's frames over the whole interval, timed every
            frame (main XEH_postInit): average fps, the worst frame (ms),
            and how many frames took longer than PERF_SLOW_FRAME_MS (below
            20 fps)

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

AEGISM_perfCounts = [];
AEGISM_perfCounts resize [PERF_COUNT, 0];
missionNamespace setVariable ["AEGISM_perfWindowStart", diag_tickTime];

if (!_active) exitWith {};

private _ms = { (round (_this * 10)) / 10 };

diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " PERF: coord %1 runs %2ms (max %3ms) | ticks %4 | aim %5 solves / %6 steers | rounds %7 tracked, %8 checks, %9 waits, %10ms | canEngage %11 | select %12 | fired %13 / threats %14 / ignored %15 | tracker %16 checks, %18ms | sensors %17 munitions seen, %24ms | plan %19 hit / %20 built / %26 solves | openFire %23 built | fps %21 avg, worst frame %22ms, %25 slow frames",
    _c select PERF_COORD_RUNS, (_c select PERF_COORD_MS) call _ms, (_c select PERF_COORD_MAX_MS) call _ms,
    _c select PERF_ENGAGE_TICKS,
    _c select PERF_AIM_SOLVES, _c select PERF_STEER_FRAMES,
    _c select PERF_ROUNDS_ADDED, _c select PERF_ROUND_CHECKS, _c select PERF_ROUND_WAITS, (_c select PERF_ROUNDS_MS) call _ms,
    _c select PERF_CAN_ENGAGE,
    _c select PERF_SELECT_FULL,
    _c select PERF_FIRED_EH, _c select PERF_FIRED_THREATS, _c select PERF_IGNORED,
    _c select PERF_TRACKER_CHECKS, _c select PERF_PROXY_SEEN, (_c select PERF_TRACKER_MS) call _ms,
    _c select PERF_PLAN_HITS, _c select PERF_PLAN_BUILDS,
    round ((_c select PERF_FRAMES) / (_span max 0.001)), round (_c select PERF_FRAME_MAX_MS),
    _c select PERF_OPEN_FIRE_BUILDS, (_c select PERF_SENSOR_MS) call _ms,
    _c select PERF_SLOW_FRAMES, _c select PERF_PLAN_SOLVES];
