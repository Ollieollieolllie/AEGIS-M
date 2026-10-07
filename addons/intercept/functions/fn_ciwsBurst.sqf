/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsBurst

Description:
    Holds a CIWS gun's trigger for one sustained burst.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the firing System vehicle <OBJECT>
    _target - the target object <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _duration - burst length, seconds <NUMBER>

Returns:
    Nothing

Examples:
    [_cheetah, _rocket, _weaponInfo, 4] call aegism_intercept_fnc_ciwsBurst;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"
#include "..\calibration.hpp"

#define AEGISM_AIM_STALE 0.5

params ["_system", "_target", "_weaponInfo", "_duration"];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;
private _burstId = (_system getVariable ["AEGISM_ciwsBurstSeq", 0]) + 1;
_system setVariable ["AEGISM_ciwsBurstSeq", _burstId, false];
_ts set ["burst", [CBA_missionTime + _duration, _target, _burstId]];

private _engagementSettings = _system getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_engagementSettings") then { _engagementSettings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
private _minElevation = _engagementSettings getOrDefault ["ciwsMinElevation", 5];

// Captured now: a munition target is usually gone (objNull) by the time the
// burst ends.
private _targetDesc = format ["%1 (%2)", _target, typeOf _target];
private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;
private _roundLifetime = ([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 7;

[{
    params ["_args", "_pfhHandle"];
    _args params ["_system", "_target", "_turretPath", "_weaponClass", "_magazineClass", "_ts", "_startedAt", "_ammoAtStart", "_minElevation", "_elevationHeld", "_burstId", "_targetDesc", "_targetClass", "_roundLifetime", "_firingTime"];

    (_ts getOrDefault ["burst", [-1, objNull, 0]]) params ["_endsAt", "", "_currentId"];
    private _ammo = if (alive _system) then { _system magazineTurretAmmo [_magazineClass, _turretPath] } else { 0 };
    private _superseded = _currentId != _burstId;

    // Engagement released: the engagement loop stopped working this gun's
    // assignment (its "tickAt" stamp went stale).
    private _released = CBA_missionTime - (_ts getOrDefault ["tickAt", -1e9]) > AEGISM_AIM_STALE;

    if (_superseded || {!alive _system} || {!alive _target} || {_ammo <= 0} || {CBA_missionTime >= _endsAt} || {_released}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        if (isNull _system) exitWith {};
        // Record the actual end time (the pause counts from it) -- only if
        // no newer burst owns the turret.
        if (!_superseded) then { _ts set ["burst", [CBA_missionTime min _endsAt, _target, _burstId]]; };
        private _fired = (_ammoAtStart - _ammo) max 0;
        // The gun's real rate of fire, over the time it was cleared to fire
        // (aegism_intercept_fnc_openFireRange): the engine fires at most once
        // a frame, so it can fall short of the config's. Never faster than
        // AEGISM_RATE_MAX_RATIO times the config's (calibration.hpp): a burst
        // measured faster was miscounted, and is left out.
        private _rateNote = "";
        if (_fired > 0 && {_firingTime > 0}) then {
            private _reloadTime = ([_system, _turretPath, _weaponClass] call aegism_intercept_fnc_fireModeStats) select 2;
            if (_reloadTime > 0 && {_fired / _firingTime > AEGISM_RATE_MAX_RATIO / _reloadTime}) exitWith {
                _rateNote = format ["; faster than its config's %1/s allows, so miscounted -- left out of its measured rate", round (1 / _reloadTime)];
            };
            _ts set ["rateRounds", (_ts getOrDefault ["rateRounds", 0]) + _fired];
            _ts set ["rateTime", (_ts getOrDefault ["rateTime", 0]) + _firingTime];
        };
        if (AEGISM_RPT_VERBOSE) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " BURST-END: %1 fired %2 round(s) of %3 at %4 in %5s%6%7.", _system, _fired, _weaponClass, _targetDesc, round ((CBA_missionTime - _startedAt) * 10) / 10,
                if (_fired > 0 && {_firingTime > 0}) then { format [" (%1/s over the %2s it was on target%3)", round (_fired / _firingTime), round (_firingTime * 10) / 10, _rateNote] } else { "" },
                ["", format [" (held %1s: barrel below the %2 deg CIWS minimum elevation)", round (_elevationHeld * 10) / 10, _minElevation]] select (_elevationHeld > 0)];
        };

        if (_fired > 0) then {
            [{
                params ["_system", "_ts", "_burstId", "_targetDesc", "_targetClass"];
                if (isNull _system) exitWith {};
                private _stats = (_ts getOrDefault ["spotStats", createHashMap]) getOrDefault [_burstId, []];
                ((_ts getOrDefault ["corrections", createHashMap]) getOrDefault [_targetClass, [0, 0]]) params ["_lead", "_elevation"];
                if (_stats isEqualTo []) exitWith {
                    if (AEGISM_RPT_VERBOSE) then {
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SPOTTING: %1 burst %2 at %3 -- no measured round passed the target.", _system, _burstId, _targetDesc];
                    };
                };
                _stats params ["_rounds", "_sumAhead", "_sumHigh", "_sumDeviation", "_deviations", ["_outliers", 0]];
                // Outliers: rounds missing far wider than its others, left
                // out (aegism_intercept_fnc_ciwsSpot, calibration.hpp).
                private _outlierNote = ["", format [" (%1 more left out as outliers, missing far wider than its others)", _outliers]] select (_outliers > 0);
                if (_rounds <= 0) exitWith {
                    if (AEGISM_RPT_VERBOSE) then {
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SPOTTING: %1 burst %2 at %3 -- no round used%4.", _system, _burstId, _targetDesc, _outlierNote];
                    };
                };
                private _ahead = _sumAhead / _rounds;
                private _high = _sumHigh / _rounds;
                private _strayed = if (_deviations > 0) then { format ["; the target strayed %1m from that track on average (evasion)", round (_sumDeviation / _deviations * 10) / 10] } else { "" };
                if (AEGISM_RPT_VERBOSE) then {
                    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SPOTTING: %1 burst %2 at %3 -- %4 round(s) measured against its predicted track%13, on average %5m %6 and %7m %8 of it%9; %10 aim correction now lead %11 ms, elevation %12 mrad.",
                        _system, _burstId, _targetDesc, _rounds,
                        round (abs _ahead * 10) / 10, ["behind", "ahead"] select (_ahead >= 0),
                        round (abs _high * 10) / 10, ["low", "high"] select (_high >= 0),
                        _strayed, _targetClass, round (_lead * 1000), round (_elevation * 10000) / 10, _outlierNote];
                };
            }, [_system, _ts, _burstId, _targetDesc, _targetClass], _roundLifetime max 0] call CBA_fnc_waitAndExecute;
        };
    };

    // Fire only on target: the aim aegism_intercept_fnc_ciwsTrack refreshes
    // every frame for this turret.
    (_ts getOrDefault ["aim_ciws", []]) params [["_angle", 180], ["_tolerance", 0], ["_aimAt", -1e9], ["_aimTarget", objNull], ["_feasible", false], ["_aligned", false]];
    if (_aimTarget != _target || {!_aligned} || {CBA_missionTime - _aimAt > AEGISM_AIM_STALE}) exitWith {};

    private _barrelElevation = asin (((([_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection) select 2) max -1) min 1);
    if (_barrelElevation < _minElevation) exitWith {
        _args set [9, _elevationHeld + AEGISM_frameDelta];
    };
    _args set [14, _firingTime + AEGISM_frameDelta];

    (weaponState [_system, _turretPath, _weaponClass]) params ["", "", "", "_loadedMagazine", "_loadedAmmo", ["_reloadPhase", 0]];
    if (_reloadPhase != 0 || {_loadedAmmo <= 0}) exitWith {};

    // The loaded magazine's id (see notes): refreshed when the magazine
    // changes.
    private _magazineId = _ts getOrDefault ["magazineId", []];
    if (_magazineId isEqualTo [] || {(_magazineId select 0) != _loadedMagazine} || {_loadedAmmo > (_magazineId select 3)}) then {
        private _index = (magazinesAllTurrets _system) findIf {
            _x params ["_class", "_path", "_count"];
            _path isEqualTo _turretPath && {_class == _loadedMagazine} && {_count == _loadedAmmo}
        };
        _magazineId = if (_index == -1) then { [] } else {
            ((magazinesAllTurrets _system) select _index) params ["", "", "", "_id", "_creator"];
            [_loadedMagazine, _id, _creator, _loadedAmmo]
        };
        _ts set ["magazineId", _magazineId];
    };
    if (_magazineId isEqualTo []) exitWith {
        [_system, _weaponClass, _turretPath] call BIS_fnc_fire;
    };
    _magazineId set [3, _loadedAmmo];
    _magazineId params ["", "_id", "_creator"];
    private _gunner = _system turretUnit _turretPath;
    if (_system turretLocal _turretPath) then {
        _system action ["UseMagazine", _system, _gunner, _creator, _id];
    } else {
        [_system, ["UseMagazine", _system, _gunner, _creator, _id]] remoteExec ["action", _system turretOwner _turretPath];
    };
}, 0, [_system, _target, _turretPath, _weaponClass, _magazineClass, _ts, CBA_missionTime, _system magazineTurretAmmo [_magazineClass, _turretPath], _minElevation, 0, _burstId, _targetDesc, _targetClass, _roundLifetime, 0]] call CBA_fnc_addPerFrameHandler;
