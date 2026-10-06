/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_recordMissileSpeed

Description:
    One AEGIS-M missile's flight to an intercept (aegism_intercept_fnc_
    interceptorPFH), folded into how fast that missile really flies: its
    real flight time over the time its flight simulated from config
    (aegism_intercept_fnc_missileProfile) gives for the length of the path
    it actually flew. Its predictions use the result from then on (aegism_
    intercept_fnc_computeLeadPoint, aegism_intercept_fnc_missileFlightTime),
    as a speed: the time to cover any path, straight or turning.

    The path flown, not the straight line from launch: the lead solver lays
    out an off-bore launch's turn itself, and a factor measured on the
    straight line also took in the turn's extra length -- counted twice,
    ACE's RIM-116 (every launch 12-21 deg off-bore) was predicted ~9% long
    once its factor applied (2026-10-06).

    Measured against the raw simulation, never the factor in use (that would
    feed on itself). Per weapon and magazine, as the simulation is; from the
    start of each mission. The factor takes in whatever the real flight
    costs in speed that the simulation leaves out: gravity on a climb, speed
    lost turning, and any error in the simulation itself (the MIM-145's
    speed levelling off, aegism_intercept_fnc_missileProfile).

    Safeguards (calibration.hpp): only a flight that ended in AEGIS-M's own
    intercept, on the target it was fired at -- not one its seeker changed to
    -- after at least AEGISM_SPEED_MIN_FLIGHT s; a flight outside AEGISM_
    SPEED_FACTOR_MIN-MAX times the simulation's time is thrown away; the factor
    used is the median of the last AEGISM_SPEED_SAMPLES flights, from AEGISM_
    SPEED_MIN_SAMPLES on, so one odd flight can't move it.

    Logged per flight (MISSILE-SPEED, Verbose), with its real speed every
    second against the simulation's -- to check the simulation on each new
    missile. A flight that ended any other way (_ended: it missed, lost its
    target, or ran out of life) is logged with its speeds too, but not
    scored: its speed still checks the simulation, and a missile that never
    hits (the RIM-162 in the 2026-10-06 test) would otherwise leave none.

Parameters:
    _weaponClass - CfgWeapons class it was fired from <STRING>
    _magazineClass - its CfgMagazines class <STRING>
    _flightTime - seconds from launch to the intercept <NUMBER>
    _distance - metres it flew, along its path, to the intercept <NUMBER>
    _retargeted - its seeker changed target in flight <BOOLEAN>
    _speeds - optional, its real speed 1, 2, 3... s after launch, m/s
        <ARRAY>
    _ended - optional, how a flight that DIDN'T end in its intercept ended;
        "" (default) for one that did <STRING>
    _straight - optional, metres from where it was launched to the
        intercept, for the log <NUMBER>

Returns:
    Nothing

Examples:
    ["weapon_rim116Launcher", "magazine_Missiles_rim116_x21", 9.1, 4400, false, [327, 561, 725], "", 4300] call aegism_intercept_fnc_recordMissileSpeed;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"
#include "..\calibration.hpp"

params ["_weaponClass", "_magazineClass", "_flightTime", "_distance", ["_retargeted", false], ["_speeds", []], ["_ended", ""], ["_straight", -1]];

if (_weaponClass == "" || {_magazineClass == ""}) exitWith {};
private _ammoClass = ([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 0;
private _profile = [_weaponClass, _magazineClass] call aegism_intercept_fnc_missileProfile;
if (_profile isEqualTo []) exitWith {};

// Its real speed each second against the simulation's.
private _fnTrace = {
    private _trace = [];
    {
        _trace pushBack format ["%1s %2/%3", _forEachIndex + 1, round _x, round ([_profile, "speed", _forEachIndex + 1] call aegism_intercept_fnc_missileProfileAt)];
    } forEach _speeds;
    [_trace joinString ", ", "none (under 1s)"] select (_trace isEqualTo [])
};

// Not its intercept: logged for its speeds, not scored (see header).
if (_ended != "") exitWith {
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MISSILE-SPEED: %1 (%2) flew %3s and %4 -- not scored. Speed real/simulated, m/s: %5.",
            _ammoClass, _weaponClass, round (_flightTime * 10) / 10, _ended, call _fnTrace];
    };
};

// The raw simulation's time for that distance.
private _profileTime = [_profile, "time", _distance] call aegism_intercept_fnc_missileProfileAt;
private _sample = if (_profileTime > 0) then { _flightTime / _profileTime } else { -1 };

private _key = _weaponClass + "|" + _magazineClass;
private _table = missionNamespace getVariable "AEGISM_missileSpeed";
if (isNil "_table") then {
    _table = createHashMap;
    missionNamespace setVariable ["AEGISM_missileSpeed", _table];
};
(_table getOrDefault [_key, [[], 1]]) params ["_samples", "_factor"];

private _rejected = switch (true) do {
    case (_retargeted): { "its seeker changed target in flight" };
    case (_flightTime < AEGISM_SPEED_MIN_FLIGHT || {_profileTime <= 0}): { format ["a %1s flight is too short to measure", round (_flightTime * 10) / 10] };
    case (_sample < AEGISM_SPEED_FACTOR_MIN || {_sample > AEGISM_SPEED_FACTOR_MAX}): {
        format ["outside %1-%2x the simulation's time, a measuring problem rather than the missile", AEGISM_SPEED_FACTOR_MIN, AEGISM_SPEED_FACTOR_MAX]
    };
    default { "" };
};

if (_rejected == "") then {
    _samples pushBack _sample;
    if (count _samples > AEGISM_SPEED_SAMPLES) then { _samples deleteAt 0; };
    private _count = count _samples;
    if (_count >= AEGISM_SPEED_MIN_SAMPLES) then {
        private _sorted = +_samples;
        _sorted sort true;
        _factor = if (_count % 2 == 1) then {
            _sorted select floor (_count / 2)
        } else {
            ((_sorted select (_count / 2 - 1)) + (_sorted select (_count / 2))) / 2
        };
    };
    _table set [_key, [_samples, _factor]];
};

if (AEGISM_RPT_VERBOSE) then {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MISSILE-SPEED: %1 (%2) flew %3m%9 in %4s; its simulated flight says %5s, %6x. %7 Speed real/simulated, m/s: %8.",
        _ammoClass, _weaponClass, round _distance, round (_flightTime * 10) / 10, round (_profileTime * 10) / 10, round (_sample * 100) / 100,
        switch (true) do {
            case (_rejected != ""): { format ["Not used: %1.", _rejected] };
            case (count _samples < AEGISM_SPEED_MIN_SAMPLES): { format ["Predictions keep the simulation's times until %1 flights are in (%2 so far).", AEGISM_SPEED_MIN_SAMPLES, count _samples] };
            default { format ["Predictions now use %1x the simulation's flight times: the median of its last %2 flight(s).", round (_factor * 100) / 100, count _samples] };
        },
        call _fnTrace,
        ["", format [" along its path (%1m straight)", round _straight]] select (_straight >= 0)];
};
