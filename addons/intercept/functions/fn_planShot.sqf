/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_planShot

Description:
    The earliest shot one launcher can make at one incoming munition from a
    given moment on that meets it before a given time (its impact).
    Full notes: docs/functions/intercept.md

Parameters:
    _candSystem - the launcher's vehicle <OBJECT>
    _weaponInfo - its weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _bounds - its envelope (aegism_intercept_fnc_envelopeBounds) <ARRAY>
    _object - the munition <OBJECT>
    _ballistic - whether it falls under gravity (artilleryShell, rocket,
        bomb) <BOOLEAN>
    _start - seconds from now the launcher can first fire <NUMBER>
    _tti - seconds from now the shot has to land by <NUMBER>
    _key - the munition's contact key (aegism_fnc_contactKey) <STRING>
    _plan - this frame's plan work, changed here: [the Site's plan cache
        <HASHMAP>, the diag_tickTime past which no new step is begun (-1:
        never cut short) <NUMBER>, new steps worked out <NUMBER>, the
        questions cut short, as this function's first eight parameters with
        _start and _tti as game times <ARRAY>] <ARRAY>

Returns:
    [fire time, intercept time], seconds from now, or [] if there's none --
    or it was cut short (the question is then among those kept) <ARRAY>

Examples:
    [_spartan, _weaponInfo, _bounds, _rocket, true, 4, 31, _key, _plan] call aegism_intercept_fnc_planShot;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"
#include "..\plan.hpp"

#define AEGISM_GRAVITY 9.80665

params ["_candSystem", "_weaponInfo", "_bounds", "_object", "_ballistic", "_start", "_tti", "_key", "_plan"];
_plan params ["_planCache", "_cutAfter"];

private _drop = [0, 0.5 * AEGISM_GRAVITY] select _ballistic;
private _cacheKey = [_key, netId _candSystem, _weaponInfo select 0];
private _entry = _planCache getOrDefault [_cacheKey, []];
private _valid = _entry isNotEqualTo [] && {
    _entry params ["_scannedAt", "_p0", "_v0"];
    private _dt = CBA_missionTime - _scannedAt;
    _dt <= AEGISM_PLAN_CACHE_MAX_AGE
        && {((_p0 vectorAdd (_v0 vectorMultiply _dt) vectorDiff [0, 0, _drop * _dt * _dt]) distance (getPosASL _object)) <= AEGISM_PLAN_CACHE_TOLERANCE}
};
if (_valid) then {
    PERF_INC(PERF_PLAN_HITS);
} else {
    PERF_INC(PERF_PLAN_BUILDS);
    _entry = [CBA_missionTime, getPosASL _object, velocity _object, createHashMap, [0, -1, -1, 1e12]];
    _planCache set [_cacheKey, _entry];
};
_entry params ["_scannedAt", "_p0", "_v", "_steps", "_known"];
_known params ["_knownFrom", "_knownTo", "_knownShot", "_knownSoonest"];
_bounds params ["_minRange", "_maxRange", "_minAltitude", "_maxAltitude"];
private _origin = eyePos _candSystem;
private _muzzle = [];
// The missile's flight to the edge of its reach, for the "too far" bound
// below (worked out when first needed).
private _span = -2;
private _impactAt = CBA_missionTime + _tti;
private _found = [];
private _cut = false;
private _first = (ceil (((CBA_missionTime + _start) - _scannedAt) / AEGISM_RESERVE_PLAN_STEP)) max 0;
private _last = floor ((_impactAt - _scannedAt) / AEGISM_RESERVE_PLAN_STEP);
// Among the steps walked this time: the first with a shot at all, and the
// soonest any of their shots lands.
private _walkedShot = -1;
private _walkedSoonest = 1e12;
private _k = _first;
while {_k <= _last && {_found isEqualTo []} && {!_cut}} do {
    // In the known stretch, with no shot in it that lands in time, or none
    // before a later step: straight to its end, or to that step.
    private _noneKnown = _knownShot < 0 || {_knownSoonest >= _impactAt};
    if (_k >= _knownFrom && {_k <= _knownTo} && {_noneKnown || {_k < _knownShot}}) then {
        _k = [_knownShot, _knownTo + 1] select _noneKnown;
    } else {
        private _shot = _steps get _k;
        if (isNil "_shot") then {
            _shot = [];
            // Seconds after the path was taken, and from now.
            private _sinceScan = _k * AEGISM_RESERVE_PLAN_STEP;
            private _p = (_p0 vectorAdd (_v vectorMultiply _sinceScan)) vectorDiff [0, 0, _drop * _sinceScan * _sinceScan];
            // Fired at from here, the missile meets it closer in -- and only
            // that meeting point has to be inside the envelope (aegism_
            // intercept_fnc_canEngage). Too far for even that, it isn't
            // solved: in the missile's flight to the edge of its reach, the
            // munition closes at most speed x t (+ g t^2 / 2 falling).
            if (_span < -1) then { _span = if (_maxRange > 0) then { [_weaponInfo, _maxRange] call aegism_intercept_fnc_missileFlightTime } else { -1 }; };
            private _speed = vectorMagnitude (_v vectorDiff [0, 0, 2 * _drop * _sinceScan]);
            if (_maxRange > 0 && {_span < 0 || {(_origin distance _p) <= _maxRange + _speed * _span + _drop * _span * _span}}) then {
                if (_cutAfter >= 0 && {diag_tickTime > _cutAfter}) then {
                    _cut = true;
                } else {
                    _plan set [2, (_plan select 2) + 1];
                    // Only a shot a missile can be put onto (aegism_intercept_
                    // fnc_launchSolution, the turret having had time to
                    // swing): a RAM planned onto rockets above its 40-degree
                    // limit held the Patriots in reserve for kills it couldn't
                    // make. A vertical launch cell's shots are off-bore, with
                    // the missile's turn.
                    if (_muzzle isEqualTo []) then { _muzzle = ([_candSystem, _weaponInfo select 0, "launcher"] call aegism_intercept_fnc_turretPoints) select 0; };
                    PERF_INC(PERF_PLAN_SOLVES);
                    ([_candSystem, _weaponInfo, _object, _muzzle, false, false, false, (_scannedAt + _sinceScan) - CBA_missionTime, _ballistic] call aegism_intercept_fnc_launchSolution)
                        params ["_launchable", "", "", "", "_flightTime", "", "", "", "", "_interceptPoint", "_interceptDistance"];
                    if (_launchable) then {
                        private _interceptHeight = (ASLToAGL _interceptPoint) select 2;
                        if (_interceptDistance >= _minRange && {_interceptDistance <= _maxRange} && {_interceptHeight >= _minAltitude} && {_maxAltitude <= 0 || {_interceptHeight <= _maxAltitude}}) then {
                            _shot = [_scannedAt + _sinceScan, _scannedAt + _sinceScan + (_flightTime max 0)];
                        };
                    };
                };
            };
            if (!_cut) then { _steps set [_k, _shot]; };
        };
        if (!_cut) then {
            if (_shot isNotEqualTo []) then {
                if (_walkedShot < 0) then { _walkedShot = _k; };
                _walkedSoonest = _walkedSoonest min (_shot select 1);
                if ((_shot select 1) < _impactAt) then { _found = _shot; };
            };
            if (_found isEqualTo []) then { _k = _k + 1; };
        };
    };
};
// Every step from _first to here is worked out now: joined to the known
// stretch if it touches it, else it's the known stretch from now on.
private _reached = [_k - 1, _k] select (_found isNotEqualTo []);
if (_reached >= _first) then {
    if (_knownTo < _knownFrom || {_first > _knownTo + 1} || {_reached < _knownFrom - 1}) then {
        _entry set [4, [_first, _reached, _walkedShot, _walkedSoonest]];
    } else {
        _entry set [4, [_knownFrom min _first, _knownTo max _reached,
            if (_knownShot >= 0 && {_walkedShot >= 0}) then { _knownShot min _walkedShot } else { _knownShot max _walkedShot },
            _knownSoonest min _walkedSoonest]];
    };
};
if (_cut) exitWith {
    (_plan select 3) pushBack [_candSystem, _weaponInfo, _bounds, _object, _ballistic, CBA_missionTime + _start, _impactAt, _key];
    []
};
if (_found isEqualTo []) exitWith { [] };
[(_found select 0) - CBA_missionTime, (_found select 1) - CBA_missionTime]
