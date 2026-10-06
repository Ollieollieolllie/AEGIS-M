/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_weaponReload
Description:
    Whether a turret's weapon can fire right now, and how long until it can,
    from the engine's own reload state (weaponState [vehicle, turret,
    weapon], Arma 3 2.06+):
        magazineReloadPhase - 1 -> 0 while it loads its next magazine, 0
            once loaded
        roundReloadPhase - 1 -> 0 while it readies the next round (-1 with
            no magazine)

    The time left is the phase times how long that reload REALLY takes,
    measured here from how fast the phase itself falls (turret state
    "reload|<weapon>"); until a tenth of one reload has been watched
    (AEGISM_RELOAD_MEASURE_PHASE) it's the config's time -- CfgWeapons
    magazineReloadTime, or the fire mode's reloadTime (aegism_intercept_fnc_
    fireModeStats). The config's time alone ran short: POOK's 9K332 (reloadTime
    6.5) fired every 9.7-10 s, and its S-400 launcher (reloadTime 25) took 37
    and 42 s over two reloads, its "ready in" slipping 0.4 s every second.
    The coordinator booked each a queue it could never fire, releasing the
    claims one after another as their turn failed to come (2026-10-06).
    Logged when first measured for a weapon (RELOAD-TIME).

    A launcher that has just fired the last missile of a magazine already
    shows the next magazine's full count while it's still loading it, and a
    fire command then fires nothing: POOK's 9K331 fired six times into its
    reload, each taken for a missed shot, and its targets got through
    (2026-10-06). POOK's launchers reload for minutes (the S-125's
    magazineReloadTime is 900 s).

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>
    _weaponClass - CfgWeapons class <STRING>

Returns:
    [ready <BOOLEAN>, seconds until it is (0 if it is, or if nothing gives
     a reload time) <NUMBER>, loading a magazine <BOOLEAN>,
     [roundReloadPhase, magazineReloadPhase] as reported <ARRAY>,
     seconds it takes to ready a round -- as measured, its config's until
     then <NUMBER>] <ARRAY>

Examples:
    [_tor, [0], "pook_9K331_TLAR"] call aegism_intercept_fnc_weaponReload;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"
#include "..\calibration.hpp"

params ["_system", "_turretPath", "_weaponClass"];

(weaponState [_system, _turretPath, _weaponClass]) params ["", "", "", "", "", ["_roundPhase", 0], ["_magazinePhase", 0]];

// What's been watched of this weapon's reloads, a round's then a magazine's:
// [this reload first seen at, its phase then, last seen at, its phase then,
// seconds a whole one takes as measured (-1: not yet)].
private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;
private _key = "reload|" + _weaponClass;
private _watched = _ts get _key;
if (isNil "_watched") then {
    _watched = [-1, 0, -1, 0, -1, -1, 0, -1, 0, -1];
    _ts set [_key, _watched];
};

// Seconds left of one reload at _phase, and how long a whole one takes
// (measured, else its config's): [left, whole].
private _fnLeft = {
    params ["_phase", "_at", "_configTime", "_what"];
    private _measured = _watched select (_at + 4);
    private _whole = [_configTime, _measured] select (_measured > 0);
    if (_phase <= 0) exitWith { _watched set [_at, -1]; [0, _whole] };
    (_watched select [_at, 4]) params ["_fromAt", "_fromPhase", "_lastAt", "_lastPhase"];
    // Another reload than the one being watched: its phase is back up, or it
    // wasn't looked at for longer than was left of that one.
    if (_fromAt < 0 || {_phase > _lastPhase} || {_whole > 0 && {CBA_missionTime - _lastAt > _lastPhase * _whole}}) then {
        _watched set [_at, CBA_missionTime];
        _watched set [_at + 1, _phase];
    } else {
        if (_fromPhase - _phase >= AEGISM_RELOAD_MEASURE_PHASE) then {
            _whole = (CBA_missionTime - _fromAt) / (_fromPhase - _phase);
            _watched set [_at + 4, _whole];
            if (_measured < 0 && {AEGISM_RPT_VERBOSE}) then {
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " RELOAD-TIME: %1 turret %2 %3 -- %4 in about %5s, by how fast its own reload state falls; its config says %6s. Its shots are planned on the measured time.",
                    _system, _turretPath, _weaponClass, _what, round (_whole * 10) / 10, _configTime];
            };
        };
    };
    _watched set [_at + 2, CBA_missionTime];
    _watched set [_at + 3, _phase];
    [_phase * _whole, _whole]
};

private _loading = _magazinePhase > 0;
private _wait = 0;
if (_loading) then {
    _wait = ([_magazinePhase, 5, getNumber (configFile >> "CfgWeapons" >> _weaponClass >> "magazineReloadTime"), "loads a magazine"] call _fnLeft) select 0;
};
([_roundPhase, 0, ([_system, _turretPath, _weaponClass] call aegism_intercept_fnc_fireModeStats) select 2, "readies its next round"] call _fnLeft) params ["_roundWait", "_roundTime"];
_wait = _wait max _roundWait;

[!_loading && {_roundPhase == 0}, _wait max 0, _loading, [_roundPhase, _magazinePhase], _roundTime]
