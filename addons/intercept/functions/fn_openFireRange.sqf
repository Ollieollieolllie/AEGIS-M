/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_openFireRange

Description:
    How far out one gun turret opens fire on a target: the longest intercept
    distance at which ONE BURST is at least doctrine ciwsOpenFireChance
    likely to put a round within the hit radius -- from what's measurable,
    not from the fire modes' AI hit-probability values:

        a round's miss at intercept distance d scatters square to the line
        of sight with a per-axis RMS of
            sigma(d)^2 = (s d)^2 + (u t(d))^2 / 3
        s - the gun's angular scatter: its OWN measured misses (every
            spotted round's miss square to the line of sight, over its range,
            aegism_intercept_fnc_ciwsSpot) for this kind of target, blended
            with a prior worth AEGISM_SCATTER_PRIOR_ROUNDS rounds: the
            current fire mode's CfgWeapons dispersion (read as the RMS
            angle, its widest reading) plus the barrel being anywhere inside
            its fire gate when it fires (dispersion + hit radius / d, spread
            evenly over that disc). The prior alone is optimistic -- turret
            tracking isn't in it -- so the range comes in as the gun's own
            misses are measured: ~2.4km for a Phalanx against a shell before
            it has fired, ~1.3-1.8km at the 7-10 mrad its rounds have
            measured in play.
        u - how fast the real target strays from its predicted track, per
            second of the round's flight (measured the same way; 3D, so a
            third of it per axis)
        t(d) - the round's flight time to d: (exp(k d) - 1) / (k v0)
            (CfgMagazines initSpeed, CfgAmmo airFriction)
        one round hits if its miss is within r, the hit radius: the
            target's size to the gun (aegism_intercept_fnc_aimWeapon -- a
            munition's body as seen along the line of fire plus the round's
            own blast or proximity radius, as its fuse counts a hit; an
            aircraft's half-size):
            p = 1 - exp(-r^2 / (2 sigma^2))
        a burst is N rounds: the gun's measured rate of fire (else its fire
            mode's reloadTime) x the doctrine's mean burst length, and hits
            with 1 - (1 - p)^N

    Capped by the round's reach in its own lifetime (CfgAmmo timeToLive, or
    until an airburst round bursts, aegism_intercept_fnc_ammoBurst:
    ln(1 + k v0 T) / k). A munition target isn't engaged inside the round's
    arming distance (CfgAmmo fuseDistance) -- the scripted fuse can't
    detonate before it.

    Cached per turret, target class and hit radius for AEGISM_OPEN_FIRE_
    REFRESH s (the gun's measured scatter moves slowly; recomputing on every
    measured round -- ~17 a second while firing -- redid the search at every
    aim solve). Logged when it
    moves by more than AEGISM_OPEN_FIRE_LOG_CHANGE (OPEN-FIRE-RANGE, with
    every input). Doctrine ciwsOpenFireChance 0: no limit short of the
    round's reach.

Parameters:
    _system - the gun's vehicle <OBJECT>
    _turretPath - the gun's turret <ARRAY>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _targetClass - the target's threat class <STRING>
    _hitRadius - the hit radius against it, m <NUMBER>
    _settings - the vehicle's resolved engagement settings <HASHMAP>

Returns:
    [open-fire range m, minimum range m] <ARRAY>

Examples:
    [_praetorian, [0], _weaponInfo, "artilleryShell", 1, _settings] call aegism_intercept_fnc_openFireRange;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"
#include "..\..\main\rpt.hpp"

// How many rounds' worth of evidence the config dispersion counts as,
// against the gun's own measured misses.
#define AEGISM_SCATTER_PRIOR_ROUNDS 10
#define AEGISM_OPEN_FIRE_REFRESH 1
#define AEGISM_OPEN_FIRE_LOG_CHANGE 0.1
#define AEGISM_MAX_DRAG_EXPONENT 30

params ["_system", "_turretPath", "_weaponInfo", "_targetClass", "_hitRadius", "_settings"];
_weaponInfo params ["", "_weaponClass", "_magazineClass"];

private _chance = (((_settings getOrDefault ["ciwsOpenFireChance", 40]) / 100) max 0) min 0.999;
private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;
private _allCached = _ts get "openFire";
if (isNil "_allCached") then { _allCached = createHashMap; _ts set ["openFire", _allCached]; };
private _cacheKey = [_targetClass, _hitRadius];
private _cached = _allCached getOrDefault [_cacheKey, []];
if (_cached isNotEqualTo [] && {CBA_missionTime - (_cached select 2) < AEGISM_OPEN_FIRE_REFRESH} && {(_cached select 3) == _chance}) exitWith {
    [_cached select 0, _cached select 1]
};
PERF_INC(PERF_OPEN_FIRE_BUILDS);

([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) params ["", "_v0", "_k", "", "", "", "", "_lifetime", "", "_fuseDistance"];
([_system, _turretPath, _weaponClass] call aegism_intercept_fnc_fireModeStats) params ["", "_dispersion", "_reloadTime"];

// The round's reach in its lifetime, and its flight time to a distance.
private _reach = switch (true) do {
    case (_lifetime <= 0 || {_v0 <= 0}): { 1e10 };
    case (_k > 0): { (ln (1 + _k * _v0 * _lifetime)) / _k };
    default { _v0 * _lifetime };
};
private _fnFlightTime = {
    params ["_d"];
    if (_v0 <= 0) exitWith { 0 };
    if (_k <= 0) exitWith { _d / _v0 };
    ((exp ((_k * _d) min AEGISM_MAX_DRAG_EXPONENT)) - 1) / (_k * _v0)
};
private _minRange = [0, _fuseDistance] select (_targetClass in ["missile", "rocket", "bomb", "artilleryShell"]);

// Rounds in one burst: measured rate of fire, else the fire mode's.
private _firedRounds = _ts getOrDefault ["rateRounds", 0];
private _firingTime = _ts getOrDefault ["rateTime", 0];
private _rateMeasured = _firingTime > 0 && {_firedRounds > 0};
private _rate = if (_rateMeasured) then { _firedRounds / _firingTime } else { [0, 1 / _reloadTime] select (_reloadTime > 0) };
private _burstLength = ((_settings getOrDefault ["ciwsBurstMin", 3]) + ((_settings getOrDefault ["ciwsBurstMax", 5]) max (_settings getOrDefault ["ciwsBurstMin", 3]))) / 2;
private _roundsPerBurst = (_rate * _burstLength) max 1;

// The gun's scatter and the target's straying (aegism_intercept_fnc_ciwsSpot).
// Until rounds are measured, the scatter is what's known about how it
// fires: the round's own dispersion, plus the barrel being anywhere inside
// its fire gate (aegism_intercept_fnc_ciwsGate: dispersion + target size /
// distance) when it fires -- spread evenly over that disc, a quarter of its
// square per axis.
((_ts getOrDefault ["scatter", createHashMap]) getOrDefault [_targetClass, ["", 0, 0, 0, 0]]) params ["", "_rounds", "_sumAngleSq", "_sumDeviationSq", "_sumFlightSq"];
private _strayRateSq = if (_sumFlightSq > 0) then { _sumDeviationSq / _sumFlightSq } else { 0 };
private _fnScatterSq = {
    params ["_d"];
    private _gate = _dispersion + _hitRadius / (_d max 1);
    private _priorSq = _dispersion * _dispersion + _gate * _gate / 4;
    (AEGISM_SCATTER_PRIOR_ROUNDS * _priorSq + _sumAngleSq / 2) / (AEGISM_SCATTER_PRIOR_ROUNDS + _rounds)
};
private _fnSigmaSq = {
    params ["_d"];
    private _t = [_d] call _fnFlightTime;
    ([_d] call _fnScatterSq) * _d * _d + _strayRateSq * _t * _t / 3
};

// The largest miss spread (per axis) at which one burst still hits with
// _chance: (1 - p)^N <= 1 - _chance.
private _range = _reach;
if (_chance > 0 && {_hitRadius > 0}) then {
    private _roundChance = 1 - ((1 - _chance) ^ (1 / _roundsPerBurst));
    private _sigmaMaxSq = (_hitRadius * _hitRadius) / (-2 * (ln (1 - _roundChance)));
    if (([_reach min 1e5] call _fnSigmaSq) > _sigmaMaxSq) then {
        // Spread only grows with distance: bisect for where it reaches the limit.
        private _near = 0;
        private _far = _reach min 1e5;
        for "_i" from 1 to 24 do {
            private _mid = (_near + _far) / 2;
            if (([_mid] call _fnSigmaSq) <= _sigmaMaxSq) then { _near = _mid; } else { _far = _mid; };
        };
        _range = _near;
    };
};
if (_hitRadius <= 0 && {_chance > 0}) then { _range = 0; };

_allCached set [_cacheKey, [_range, _minRange, CBA_missionTime, _chance]];

// Logged when it moves noticeably.
private _logged = _ts get "openFireLogged";
if (isNil "_logged") then { _logged = createHashMap; _ts set ["openFireLogged", _logged]; };
private _lastLogged = _logged getOrDefault [_targetClass, -1];
if (_lastLogged < 0 || {abs (_range - _lastLogged) > AEGISM_OPEN_FIRE_LOG_CHANGE * (_lastLogged max 1)}) then {
    _logged set [_targetClass, _range];
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " OPEN-FIRE-RANGE: %1 %2 vs %3 -- fires inside %4 (round reach %5m in its %6s life%7). There one %8s burst, ~%9 rounds at %10/s (%11), puts a round within %12m of the target %13 percent of the time: rounds scatter %14 mrad RMS (%15), the target strays %16 m/s of flight from its predicted track.",
            _system, _weaponClass, _targetClass,
            [format ["%1m", round _range], "its full reach"] select (_range >= _reach),
            round (_reach min 1e5), _lifetime, [format [", arms at %1m", _minRange], ""] select (_minRange <= 0),
            round (_burstLength * 10) / 10, round _roundsPerBurst, round _rate, ["config fire rate", "measured"] select _rateMeasured,
            round (_hitRadius * 100) / 100, round (_chance * 100),
            round ((sqrt ([_range min (_reach min 1e5)] call _fnScatterSq)) * 10000) / 10,
            [format ["config dispersion %1 mrad plus its fire gate, nothing measured yet", round (_dispersion * 10000) / 10],
             format ["measured over %1 rounds, blended with config dispersion %2 mrad plus its fire gate", round _rounds, round (_dispersion * 10000) / 10]] select (_rounds >= 1),
            round ((sqrt _strayRateSq) * 100) / 100];
    };
};

[_range, _minRange]
