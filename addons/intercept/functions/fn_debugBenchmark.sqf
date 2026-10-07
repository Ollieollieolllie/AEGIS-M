/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_debugBenchmark

Description:
    Times AEGIS-M's per-call hot paths on the running game and writes one
    BENCHMARK line per function to the RPT.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the System to time <OBJECT>
    _target - any live object to aim at <OBJECT>
    _role - "ciws" or "launcher" (default: ciws if it has a gun) <STRING>

Returns:
    [[label, ms per call], ...] <ARRAY>

Examples:
    [cursorObject, heli1] call aegism_intercept_fnc_debugBenchmark;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_BENCH_CYCLES 500

params ["_system", "_target", ["_role", ""]];

private _capabilities = _system getVariable "AEGISM_system";
if (isNil "_capabilities" || {isNull _target}) exitWith {
    private _msg = format ["[AEGIS-M] BENCHMARK: %1 isn't a recognized System, or no target given.", _system];
    hint _msg;
    diag_log text _msg;
    []
};
if (_role == "") then { _role = ["launcher", "ciws"] select ((_capabilities get "ciwsWeapons") isNotEqualTo []); };
private _weaponInfo = (_capabilities getOrDefault [_role + "Weapons", []]) param [0, []];
if (_weaponInfo isEqualTo []) exitWith { diag_log text format ["[AEGIS-M] BENCHMARK: %1 has no %2 weapon.", _system, _role]; [] };
private _settings = _system getVariable ["AEGISM_resolvedEngagementSettings", createHashMap];
private _ts = [_system, _weaponInfo select 0] call aegism_intercept_fnc_turretState;

private _results = [];
private _fnTime = {
    params ["_label", "_code", "_arguments"];
    private _ms = (diag_codePerformance [_code, _arguments, AEGISM_BENCH_CYCLES]) select 0;
    _results pushBack [_label, _ms];
    diag_log text format ["[AEGIS-M] BENCHMARK: %1 -- %2 ms per call (%3 calls).", _label, _ms toFixed 4, AEGISM_BENCH_CYCLES];
};

["classify bullet", { ["B_65x39_Caseless"] call aegism_detect_fnc_classifyAmmoClass }, []] call _fnTime;
["classify shell", { ["Sh_155mm_AMOS"] call aegism_detect_fnc_classifyAmmoClass }, []] call _fnTime;
["canEngage " + _role, { _this call aegism_intercept_fnc_canEngage }, [_system, _role, _weaponInfo, _target, _settings]] call _fnTime;
["turretPoints", { _this call aegism_intercept_fnc_turretPoints }, [_system, _weaponInfo select 0, _role]] call _fnTime;
["computeLeadPoint", { _this call aegism_intercept_fnc_computeLeadPoint }, [_system, eyePos _system, _target, _weaponInfo, _role, false]] call _fnTime;
["aimWeapon " + _role, { _this call aegism_intercept_fnc_aimWeapon }, [_system, _target, _weaponInfo, _role]] call _fnTime;
if (_role == "ciws") then {
    // A steer needs a fresh solve on this target; diag_codePerformance runs
    // within one frame, so time stands still and the solve stays fresh.
    [_system, _target, _weaponInfo, _role] call aegism_intercept_fnc_aimWeapon;
    _ts set ["trackTarget", [_target, _weaponInfo, CBA_missionTime]];
    _ts set ["aim_ciws", []];
    ["ciwsTrack steer", {
        // Cleared each call, or the tracker would return this frame's aim.
        (_this select 2) set ["aim_ciws", []];
        [_this select 0, _this select 1] call aegism_intercept_fnc_ciwsTrack
    }, [_system, _weaponInfo select 0, _ts]] call _fnTime;
};

hint format ["[AEGIS-M] BENCHMARK done, %1 functions -- see the RPT.", count _results];
_results
