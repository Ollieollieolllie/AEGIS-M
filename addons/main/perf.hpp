// Server performance counters, summarised to the RPT by aegism_fnc_perfLog.
// Indices into AEGISM_perfCounts, a plain array created by main XEH_preInit
// on every machine (so an increment never hits nil), reset by each summary.
// Timings ("_MS") come from diag_tickTime, a 32-bit float: after an hour of
// game time it only resolves to ~0.25ms, so treat single values as rough and
// sums over many calls as approximate.
#define PERF_COORD_RUNS 0
#define PERF_COORD_MS 1
#define PERF_COORD_MAX_MS 2
#define PERF_ENGAGE_TICKS 3
#define PERF_AIM_SOLVES 4
#define PERF_STEER_FRAMES 5
#define PERF_ROUNDS_ADDED 6
#define PERF_ROUND_CHECKS 7
#define PERF_ROUND_WAITS 8
#define PERF_CAN_ENGAGE 9
#define PERF_FIRED_EH 10
#define PERF_FIRED_THREATS 11
#define PERF_TRACKER_CHECKS 12
#define PERF_LOS_RAYS 13
#define PERF_PLAN_HITS 14
#define PERF_PLAN_BUILDS 15
#define PERF_SELECT_FULL 16
#define PERF_ROUNDS_MS 17
#define PERF_TRACKER_MS 18
#define PERF_IGNORED 19
#define PERF_COUNT 20

#define PERF_INC(INDEX) AEGISM_perfCounts set [INDEX, (AEGISM_perfCounts select INDEX) + 1]
#define PERF_ADD(INDEX,VALUE) AEGISM_perfCounts set [INDEX, (AEGISM_perfCounts select INDEX) + (VALUE)]
