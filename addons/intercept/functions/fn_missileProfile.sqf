/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileProfile

Description:
    A launcher's missile's flight from launch, simulated once per weapon +
    magazine from its config and cached ("AEGISM_cacheMissileProfile"): how
    far it has flown and how fast it's going every AEGISM_PROFILE_STEP s, to
    the end of its lifetime. Every missile flight AEGIS-M predicts is read
    from it (aegism_intercept_fnc_missileProfileAt): the lead solver, the
    coordinator's in-time checks, the measured speed's baseline.

    The engine's rules for a missile (BI wiki, CfgAmmo Config Reference;
    values from aegism_intercept_fnc_weaponKinematics):
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
            real speed levels off near 1390 m/s
        maxSpeed - NOT applied, though the wiki calls it the top speed
            (AEGISM_PROFILE_SPEED_CAP): the MIM-145 flies far past its 850
            m/s. The RIM-116 and RIM-162 never reach theirs either way.

    The old profile -- thrust up to maxSpeed, then that speed for good --
    put ACE's RIM-116 ~38% further along than it really was: drag holds it
    to a ~730 m/s peak at 3.4 s, and slows it to ~300 m/s by 9 s.

    Not simulated: gravity on a climb (~3% of the RIM-116's distance on a
    50 deg climb), speed lost turning (sideAirFriction), the curve its
    guidance flies. The speed measured in flight picks those up (aegism_
    intercept_fnc_recordMissileSpeed).

    Midpoint steps: within a metre of a 0.5 ms step over 30 s of the
    RIM-116's and MIM-145's flights. Logged once per missile
    (MISSILE-PROFILE, Verbose).

Parameters:
    _weaponClass - CfgWeapons class <STRING>
    _magazineClass - CfgMagazines class <STRING>

Returns:
    [step s, distances m, speeds m/s] <ARRAY> -- entry i is i x step s after
    launch; [] with no speed in config (no initSpeed, no motor)

Examples:
    ["weapon_mim145Launcher", "magazine_Missile_mim145_x4"] call aegism_intercept_fnc_missileProfile;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

// Simulation step, s (see header).
#define AEGISM_PROFILE_STEP 0.1
// How long a missile with no timeToLive is simulated, s.
#define AEGISM_PROFILE_MAX_TIME 60
// Drag along the nose per unit of a missile's airFriction (see header).
#define AEGISM_MISSILE_DRAG 0.00225
// Top speed as a multiple of CfgAmmo maxSpeed; 0 = none (see header).
#define AEGISM_PROFILE_SPEED_CAP 0

params ["_weaponClass", "_magazineClass"];

private _cache = missionNamespace getVariable "AEGISM_cacheMissileProfile";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheMissileProfile", _cache];
};
private _key = _weaponClass + "|" + _magazineClass;
private _cached = _cache get _key;
if (!isNil "_cached") exitWith { _cached };

([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics)
    params ["_ammoClass", "_v0", "", "_thrust", "_thrustTime", "_initTime", "_friction", "_lifetime", "", "", "", "", "_maxSpeed"];
if (_thrust <= 0 || {_thrustTime <= 0}) then { _thrust = 0; };
if (_v0 <= 0 && {_thrust <= 0}) exitWith {
    _cache set [_key, []];
    []
};

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

_cached = [_step, _distances, _speeds];
_cache set [_key, _cached];

if (AEGISM_RPT_VERBOSE) then {
    private _peak = selectMax _speeds;
    private _total = _distances select -1;
    // Its time to every km mark (every few km for a long flight).
    private _mark = 1000 * (ceil (_total / 8000) max 1);
    private _marks = [];
    for "_d" from _mark to _total step _mark do {
        _marks pushBack format ["%1 km in %2s", _d / 1000, ([_cached, "time", _d] call aegism_intercept_fnc_missileProfileAt) toFixed 1];
    };
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MISSILE-PROFILE: %1 (%2), simulated from config -- launched at %3 m/s; motor %4 m/s2 from %5s, fading out at %6s; drag %7 x airFriction %8; maxSpeed %9 %10. Peaks at %11 m/s after %12s; %13 m/s at the end of its %14s life, %15 km out. Flies %16.",
        _ammoClass, _weaponClass, _v0, _thrust, _initTime, _initTime + _thrustTime, AEGISM_MISSILE_DRAG, _friction, _maxSpeed,
        ["not applied", format ["applied at %1 m/s", round _cap]] select (_cap < 1e9),
        round _peak, ((_speeds find _peak) * _step) toFixed 1, round (_speeds select -1), _end, (_total / 1000) toFixed 1,
        [_marks joinString ", ", "under 1 km"] select (_marks isEqualTo [])];
};

_cached
