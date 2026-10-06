/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileProfile

Description:
    A launcher's missile's flight from launch: how far it has flown and how
    fast it's going every AEGISM_PROFILE_STEP s, to the end of its lifetime.
    Every missile flight AEGIS-M predicts is read from it (aegism_intercept_
    fnc_missileProfileAt): the lead solver, the coordinator's in-time checks.
    Per weapon + magazine.

    LEARNED once its own flights have shown it (aegism_intercept_fnc_
    recordMissileSpeed): every second after launch that at least AEGISM_
    SPEED_MIN_SAMPLES flights have reached, its speed is the median of their
    real speeds then (the last AEGISM_SPEED_SAMPLES of them). Between those
    seconds, and from launch to the first, the config simulation's own curve
    is scaled to them; past the last, scaled as at the last. So it flies
    whatever the missile really does -- a missile that stops at its maxSpeed
    (POOK's PAC-2 and PAC-3, at 1750 m/s) and one that doesn't (the
    MIM-145, ~1390 m/s past its 850; the 9M317 and 9M331), one a mod flies by
    script -- which no single rule from config got right. Rebuilt when a
    flight adds to it ("AEGISM_cacheMissileLearned"). Learned per flight
    config (its launch speed, motor, drag, lifetime and maxSpeed), not per
    weapon: missiles that fly alike learn together -- POOK's SA-8 has six
    one-missile launchers, each its own weapon, magazine and ammo, which
    would otherwise never see a second flight.

    SIMULATED from its config until then, once and cached ("AEGISM_cache
    MissileProfile"). The engine's rules for a missile (BI wiki, CfgAmmo
    Config Reference; values from aegism_intercept_fnc_weaponKinematics):
        launch - its initSpeed
        motor - lights initTime s after launch; thrust is an acceleration
            (m/s^2), at full for the first 75% of thrustTime, then fading
            linearly to nothing at thrustTime
        drag - along its nose, a = AEGISM_MISSILE_DRAG x airFriction x v^2:
            airFriction is each missile's own; the multiplier is the
            engine's, in no config. A community fit to recorded NLAW, Titan,
            RPG, DAGR and ASRAAM flights (BI forums, 2016) put it at 0.002;
            AEGIS-M's own missiles' speed every second in flight (2026-10-06
            tests, MISSILE-SPEED) fit 0.0022 (RIM-162), 0.00224 (Stinger)
            and 0.00228 (RIM-116) -- and 0.0025 for the MIM-145, whose
            real speed levels off near 1390 m/s. 13 missile types, POOK's
            among them, then flew within 5% of the simulation's times
        maxSpeed - NOT applied, though the wiki calls it the top speed
            (AEGISM_PROFILE_SPEED_CAP): some missiles stop at it and some
            don't (above); the learned curve settles which
    Not simulated: gravity on a climb, speed lost turning (sideAirFriction).
    Midpoint steps: within a metre of a 0.5 ms step over 30 s of the
    RIM-116's and MIM-145's flights. Logged once per missile
    (MISSILE-PROFILE, Verbose).

Parameters:
    _weaponClass - CfgWeapons class <STRING>
    _magazineClass - CfgMagazines class <STRING>
    _raw - optional, the config simulation even once a curve is learned
        (what the learned speeds are scaled from) <BOOLEAN>

Returns:
    [step s, distances m, speeds m/s] <ARRAY> -- entry i is i x step s after
    launch; [] with no speed in config (no initSpeed, no motor). A learned
    profile also carries [.., seconds learned, flights behind its first
    second].

Examples:
    ["weapon_mim145Launcher", "magazine_Missile_mim145_x4"] call aegism_intercept_fnc_missileProfile;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"
#include "..\calibration.hpp"

// Simulation step, s (see header).
#define AEGISM_PROFILE_STEP 0.1
// How long a missile with no timeToLive is simulated, s.
#define AEGISM_PROFILE_MAX_TIME 60
// Drag along the nose per unit of a missile's airFriction (see header).
#define AEGISM_MISSILE_DRAG 0.00225
// Top speed as a multiple of CfgAmmo maxSpeed; 0 = none (see header).
#define AEGISM_PROFILE_SPEED_CAP 0

params ["_weaponClass", "_magazineClass", ["_raw", false]];

private _key = _weaponClass + "|" + _magazineClass;

// --- The config simulation (see header), once ---------------------------------
private _cache = missionNamespace getVariable "AEGISM_cacheMissileProfile";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheMissileProfile", _cache];
};
private _sim = _cache get _key;
if (isNil "_sim") then {
    ([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics)
        params ["_ammoClass", "_v0", "", "_thrust", "_thrustTime", "_initTime", "_friction", "_lifetime", "", "", "", "", "_maxSpeed"];
    if (_thrust <= 0 || {_thrustTime <= 0}) then { _thrust = 0; };
    if (_v0 <= 0 && {_thrust <= 0}) exitWith { _sim = []; };

    private _k = AEGISM_MISSILE_DRAG * _friction;
    private _cap = if (AEGISM_PROFILE_SPEED_CAP > 0 && {_maxSpeed > 0}) then { AEGISM_PROFILE_SPEED_CAP * _maxSpeed } else { 1e10 };
    private _end = [AEGISM_PROFILE_MAX_TIME, _lifetime] select (_lifetime > 0);
    private _step = AEGISM_PROFILE_STEP;

    // Its acceleration _t s after launch, going _v m/s.
    private _fnAccel = {
        params ["_t", "_v"];
        private _burning = _t - _initTime;
        (if (_thrust > 0 && {_burning >= 0} && {_burning < _thrustTime}) then { _thrust * (1 min ((_thrustTime - _burning) * 4 / _thrustTime)) } else { 0 }) - _k * _v * _v
    };

    private _distances = [0];
    private _speeds = [_v0];
    private _t = 0;
    private _x = 0;
    private _v = _v0;
    for "_i" from 1 to ceil (_end / _step) do {
        private _vMid = ((_v + 0.5 * _step * ([_t, _v] call _fnAccel)) min _cap) max 0;
        _x = _x + _vMid * _step;
        _v = ((_v + _step * ([_t + 0.5 * _step, _vMid] call _fnAccel)) min _cap) max 0;
        _t = _t + _step;
        _distances pushBack _x;
        _speeds pushBack _v;
    };
    _sim = [_step, _distances, _speeds];

    if (AEGISM_RPT_VERBOSE) then {
        private _peak = selectMax _speeds;
        private _total = _distances select -1;
        // Its time to every km mark (every few km for a long flight).
        private _mark = 1000 * (ceil (_total / 8000) max 1);
        private _marks = [];
        for "_d" from _mark to _total step _mark do {
            _marks pushBack format ["%1 km in %2s", _d / 1000, ([_sim, "time", _d] call aegism_intercept_fnc_missileProfileAt) toFixed 1];
        };
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MISSILE-PROFILE: %1 (%2), simulated from config -- launched at %3 m/s; motor %4 m/s2 from %5s, fading out at %6s; drag %7 x airFriction %8; maxSpeed %9 %10. Peaks at %11 m/s after %12s; %13 m/s at the end of its %14s life, %15 km out. Flies %16.",
            _ammoClass, _weaponClass, _v0, _thrust, _initTime, _initTime + _thrustTime, AEGISM_MISSILE_DRAG, _friction, _maxSpeed,
            ["not applied", format ["applied at %1 m/s", round _cap]] select (_cap < 1e9),
            round _peak, ((_speeds find _peak) * _step) toFixed 1, round (_speeds select -1), _end, (_total / 1000) toFixed 1,
            [_marks joinString ", ", "under 1 km"] select (_marks isEqualTo [])];
    };
};
_cache set [_key, _sim];
if (_raw || {_sim isEqualTo []}) exitWith { _sim };

// --- The learned curve (see header) ------------------------------------------
private _learnedCache = missionNamespace getVariable "AEGISM_cacheMissileLearned";
if (isNil "_learnedCache") then {
    _learnedCache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheMissileLearned", _learnedCache];
};
private _learned = _learnedCache get _key;
if (!isNil "_learned") exitWith { _learned };

_sim params ["_step", "_simDistances", "_simSpeeds"];
private _last = (count _simSpeeds) - 1;
// Each second's real speed over the simulation's then: from launch (1, it
// leaves at its initSpeed) to the last second enough flights have reached.
private _ratios = [1];
private _flights = 0;
{
    if (count _x < AEGISM_SPEED_MIN_SAMPLES) exitWith {};
    if (_forEachIndex == 0) then { _flights = count _x; };
    private _sorted = +_x;
    _sorted sort true;
    private _n = count _sorted;
    private _median = if (_n % 2 == 1) then { _sorted select floor (_n / 2) } else { ((_sorted select (_n / 2 - 1)) + (_sorted select (_n / 2))) / 2 };
    _ratios pushBack (_median / ((_simSpeeds select ((round ((_forEachIndex + 1) / _step)) min _last)) max 1));
} forEach ((missionNamespace getVariable ["AEGISM_missileSpeedSamples", createHashMap]) getOrDefault [[_weaponClass, _magazineClass] call aegism_intercept_fnc_missileFlightKey, []]);

private _learnedSeconds = (count _ratios) - 1;
if (_learnedSeconds == 0) exitWith {
    _learnedCache set [_key, _sim];
    _sim
};
private _speeds = [];
private _distances = [0];
{
    private _t = _forEachIndex * _step;
    private _ratio = if (_t >= _learnedSeconds) then { _ratios select _learnedSeconds } else {
        private _from = _ratios select (floor _t);
        _from + ((_ratios select (floor _t + 1)) - _from) * (_t - floor _t)
    };
    private _v = _x * _ratio;
    if (_forEachIndex > 0) then { _distances pushBack ((_distances select -1) + 0.5 * ((_speeds select -1) + _v) * _step); };
    _speeds pushBack _v;
} forEach _simSpeeds;

_learned = [_step, _distances, _speeds, _learnedSeconds, _flights];
_learnedCache set [_key, _learned];
_learned
