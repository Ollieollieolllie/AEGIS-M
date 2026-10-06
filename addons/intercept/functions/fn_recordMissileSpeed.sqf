/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_recordMissileSpeed
Description:
    One AEGIS-M missile's flight (aegism_intercept_fnc_interceptorPFH),
    folded into its learned speed curve: its real speed 1, 2, 3... s after
    launch joins the samples for that second ("AEGISM_missileSpeedSamples",
    per flight config, aegism_intercept_fnc_missileFlightKey, from the start
    of each mission), and its
    profile is rebuilt from them (aegism_intercept_fnc_missileProfile) --
    the speeds AEGIS-M predicts its flights with from then on.

    Every flight counts, however it ended: a miss, a lost target, a
    retarget or the game's own proximity fuse fly the same speeds as a hit
    (the RIM-162's engine-fused kills left it with no speed data at all
    while only intercepts counted). Speeds, not flight times: a time also
    takes in an off-bore launch's turn, which the lead solver lays out
    itself -- a factor measured on flight times counted it twice, and ACE's
    RIM-116 was predicted ~9% long once it applied (2026-10-06). This
    replaces that factor.

    Safeguards (calibration.hpp): a speed outside AEGISM_SPEED_RATIO_MIN-MAX
    times the config simulation's at that second is a measuring problem,
    not the missile, and isn't used; each second keeps its last AEGISM_
    SPEED_SAMPLES; the curve uses a second's median once AEGISM_SPEED_MIN_
    SAMPLES flights have reached it, so one odd flight can't move it.

    Logged per flight (MISSILE-SPEED, Verbose): its real speed every second
    against what was predicted (the curve in use before this flight), and
    for an intercept its flight time against the predicted time for the
    path it flew -- to check each new missile.

Parameters:
    _weaponClass - CfgWeapons class it was fired from <STRING>
    _magazineClass - its CfgMagazines class <STRING>
    _flightTime - seconds from launch to the end of its flight <NUMBER>
    _distance - an intercept: metres it flew along its path; -1 otherwise
        <NUMBER>
    _speeds - its real speed 1, 2, 3... s after launch, m/s <ARRAY>
    _ended - optional, how a flight that DIDN'T end in its intercept ended;
        "" (default) for one that did <STRING>
    _straight - optional, metres from where it was launched to the
        intercept, for the log <NUMBER>

Returns:
    Nothing

Examples:
    ["weapon_rim116Launcher", "magazine_Missiles_rim116_x21", 9.1, 4400, [327, 561, 725], "", 4300] call aegism_intercept_fnc_recordMissileSpeed;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"
#include "..\calibration.hpp"

params ["_weaponClass", "_magazineClass", "_flightTime", "_distance", ["_speeds", []], ["_ended", ""], ["_straight", -1]];

if (_weaponClass == "" || {_magazineClass == ""}) exitWith {};
private _sim = [_weaponClass, _magazineClass, true] call aegism_intercept_fnc_missileProfile;
if (_sim isEqualTo []) exitWith {};
// What its flights were predicted with until now.
private _predicted = [_weaponClass, _magazineClass] call aegism_intercept_fnc_missileProfile;

// Kept per flight config, not per weapon (aegism_intercept_fnc_
// missileFlightKey): missiles that fly alike learn together.
private _key = [_weaponClass, _magazineClass] call aegism_intercept_fnc_missileFlightKey;
private _table = missionNamespace getVariable "AEGISM_missileSpeedSamples";
if (isNil "_table") then {
    _table = createHashMap;
    missionNamespace setVariable ["AEGISM_missileSpeedSamples", _table];
};
private _perSecond = _table getOrDefault [_key, []];
_table set [_key, _perSecond];

private _trace = [];
private _rejected = 0;
{
    private _second = _forEachIndex + 1;
    private _simSpeed = [_sim, "speed", _second] call aegism_intercept_fnc_missileProfileAt;
    _trace pushBack format ["%1s %2/%3", _second, round _x, round ([_predicted, "speed", _second] call aegism_intercept_fnc_missileProfileAt)];
    private _ratio = _x / (_simSpeed max 1);
    if (_ratio < AEGISM_SPEED_RATIO_MIN || {_ratio > AEGISM_SPEED_RATIO_MAX}) then {
        _rejected = _rejected + 1;
    } else {
        while {count _perSecond < _second} do { _perSecond pushBack []; };
        private _samples = _perSecond select (_second - 1);
        _samples pushBack _x;
        if (count _samples > AEGISM_SPEED_SAMPLES) then { _samples deleteAt 0; };
    };
} forEach _speeds;

// Every curve is rebuilt on its next use: any weapon's missile may fly like
// this one.
missionNamespace setVariable ["AEGISM_cacheMissileLearned", createHashMap];

if (AEGISM_RPT_VERBOSE) then {
    private _now = [_weaponClass, _magazineClass] call aegism_intercept_fnc_missileProfile;
    private _predictedTime = if (_ended == "" && {_distance > 0}) then { [_predicted, "time", _distance] call aegism_intercept_fnc_missileProfileAt } else { -1 };
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MISSILE-SPEED: %1 (%2) %3 Speed real/predicted, m/s: %4.%5 Its speed curve: %6.",
        ([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 0, _weaponClass,
        if (_ended == "") then {
            format ["flew %1m%2 in %3s to its intercept; predicted %4s for that path%5.", round _distance,
                ["", format [" along its path (%1m straight)", round _straight]] select (_straight >= 0),
                round (_flightTime * 10) / 10, round (_predictedTime * 10) / 10,
                ["", format [", %1x", round (_flightTime / _predictedTime * 100) / 100]] select (_predictedTime > 0)]
        } else {
            format ["flew %1s and %2.", round (_flightTime * 10) / 10, _ended]
        },
        [_trace joinString ", ", "none (under 1s)"] select (_trace isEqualTo []),
        ["", format [" %1 second(s) left out: over %2x or under %3x the config simulation's, a measuring problem.", _rejected, AEGISM_SPEED_RATIO_MAX, AEGISM_SPEED_RATIO_MIN]] select (_rejected > 0),
        if (count _now > 3) then {
            format ["learned for its first %1s, from %2 flight(s)", _now select 3, _now select 4]
        } else {
            format ["its config simulation until %1 flights have flown a second", AEGISM_SPEED_MIN_SAMPLES]
        }];
};
