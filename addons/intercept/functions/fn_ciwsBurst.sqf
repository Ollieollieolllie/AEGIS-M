/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsBurst

Description:
    Holds a CIWS gun's trigger for one sustained burst. Every frame the
    weapon has cycled (weaponState roundReloadPhase back to 0) and the
    turret is on its aim point, it fires again, so the gun runs at its own
    config rate of fire (reloadTime) for the whole burst.

    Each shot is the same command BIS_fnc_fire issues for a vehicle turret
    -- the "UseMagazine" action with the loaded magazine's id -- given
    directly: BIS_fnc_fire looks the magazine up in the vehicle's whole
    magazine list and routes the action through remoteExec on every call,
    ~53 times a second for a Phalanx. The magazine id is found once and
    reused until the magazine changes (a new one shows a higher round
    count); a turret on another machine gets the action sent to its owner,
    as BIS_fnc_fire does.

    Why sustained: BIS_fnc_fire is ONE trigger pull in the turret's selected
    fire mode. A Cheetah gunner's selected mode is its player mode "manual"
    (burst = 2), so one call per engagement tick gave 2-round pops about a
    second apart instead of sustained fire.

    Fires only while the gun's aim -- refreshed every frame by its tracker,
    aegism_intercept_fnc_ciwsTrack -- is for THIS target, fresh, and aligned
    (aegism_intercept_fnc_ciwsGate, per turret): a turret that falls off the
    lead point mid-burst holds fire until it's back on. It also holds fire
    while the barrel itself (aegism_intercept_fnc_barrelDirection, world
    space) is below doctrine ciwsMinElevation, so a target dipping low
    mid-burst never pulls rounds into the ground or friendly positions; the
    time held is reported in BURST-END.

    Once the burst's last round has had its lifetime (CfgAmmo timeToLive)
    to pass the target, a SPOTTING line reports where this burst's measured
    rounds went and the aim correction the gun now carries for that target
    class (aegism_intercept_fnc_ciwsSpot).

    The burst ends at its deadline -- which the engagement loop pulls in if
    the target changes or LOS is lost -- or when the target dies, ammo runs
    out, or the engagement loop stops working the assignment (the turret's
    "tickAt" goes stale: the engagement was released).

    Turret state "burst": [endsAt, target, burstId]. endsAt is the planned
    deadline while the burst runs and is rewritten to the actual end time
    when it stops, so the engagement loop's pause between bursts counts from
    it. burstId makes each handler exit as soon as a newer burst owns the
    turret.

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
        // a frame, so it can fall short of the config's.
        if (_fired > 0 && {_firingTime > 0}) then {
            _ts set ["rateRounds", (_ts getOrDefault ["rateRounds", 0]) + _fired];
            _ts set ["rateTime", (_ts getOrDefault ["rateTime", 0]) + _firingTime];
        };
        if (AEGISM_RPT_VERBOSE) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " BURST-END: %1 fired %2 round(s) of %3 at %4 in %5s%6%7.", _system, _fired, _weaponClass, _targetDesc, round ((CBA_missionTime - _startedAt) * 10) / 10,
                if (_fired > 0 && {_firingTime > 0}) then { format [" (%1/s over the %2s it was on target)", round (_fired / _firingTime), round (_firingTime * 10) / 10] } else { "" },
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
                _stats params ["_rounds", "_sumAhead", "_sumHigh", "_sumDeviation", "_deviations"];
                private _ahead = _sumAhead / _rounds;
                private _high = _sumHigh / _rounds;
                private _strayed = if (_deviations > 0) then { format ["; the target strayed %1m from that track on average (evasion)", round (_sumDeviation / _deviations * 10) / 10] } else { "" };
                if (AEGISM_RPT_VERBOSE) then {
                    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SPOTTING: %1 burst %2 at %3 -- %4 round(s) measured against its predicted track, on average %5m %6 and %7m %8 of it%9; %10 aim correction now lead %11 ms, elevation %12 mrad.",
                        _system, _burstId, _targetDesc, _rounds,
                        round (abs _ahead * 10) / 10, ["behind", "ahead"] select (_ahead >= 0),
                        round (abs _high * 10) / 10, ["low", "high"] select (_high >= 0),
                        _strayed, _targetClass, round (_lead * 1000), round (_elevation * 10000) / 10];
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
        _args set [9, _elevationHeld + diag_deltaTime];
    };
    _args set [14, _firingTime + diag_deltaTime];

    (weaponState [_system, _turretPath, _weaponClass]) params ["", "", "", "_loadedMagazine", "_loadedAmmo", ["_reloadPhase", 0]];
    if (_reloadPhase != 0 || {_loadedAmmo <= 0}) exitWith {};

    // The loaded magazine's id (see header): refreshed when the magazine
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
