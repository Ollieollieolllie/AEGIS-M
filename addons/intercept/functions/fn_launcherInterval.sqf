/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_launcherInterval

Description:
    Seconds between two missiles from one launcher turret, before crew
    temperament scaling.

    A positive "Seconds Between Missiles" (Site setting, or the vehicle's own
    override) is used as given. 0, the default, is Auto: the launcher's own
    rate of fire, the reloadTime of the fire mode it is in (aegism_intercept_
    fnc_fireModeStats). That is the weapon's own authored fire rate and it
    already scales with the missile it carries -- vanilla MIM-145 Defender
    4s, Mk49 Spartan (RIM-116) 2s, Mk21 Centurion (RIM-162) 1s -- and it
    covers mod launchers without a table here.

    Logs the interval (and where it came from) whenever it changes for a
    turret (FIRE-RATE).

Parameters:
    _system - the launcher System vehicle <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _settings - the System's effective engagement settings <HASHMAP>

Returns:
    Seconds <NUMBER>

Examples:
    [_patriot, _weaponInfo, _settings] call aegism_intercept_fnc_launcherInterval;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_weaponInfo", "_settings"];
_weaponInfo params ["_turretPath", "_weaponClass"];

private _configured = _settings getOrDefault ["minShotInterval", 0];
private _mode = [];
private _interval = if (_configured > 0) then { _configured } else {
    _mode = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_fireModeStats;
    _mode select 2
};

private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;
if ((_ts getOrDefault ["intervalLogged", -1]) != _interval) then {
    _ts set ["intervalLogged", _interval];
    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " FIRE-RATE: %1 (%2) %3 -- %4s between missiles (%5).", _system, typeOf _system, _weaponClass, _interval,
        ["Seconds Between Missiles setting", format ["auto, %1 reloadTime", _mode param [0, ""]]] select (_configured <= 0)];
};

_interval
