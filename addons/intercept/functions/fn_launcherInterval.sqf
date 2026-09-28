/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_launcherInterval

Description:
    Seconds between two missiles from one launcher turret, before crew
    temperament scaling.

    A positive "Seconds Between Missiles" (Site setting, or the vehicle's own
    override) is used as given. 0, the default, is Auto: the launcher's own
    rate of fire, the reloadTime of the fire mode it is in (CfgWeapons,
    falling back to the weapon class itself when the mode has no class of its
    own). That is the weapon's own authored fire rate and it already scales
    with the missile it carries -- vanilla MIM-145 Defender 4s, Mk49 Spartan
    (RIM-116) 2s, Mk21 Centurion (RIM-162) 1s -- and it covers mod launchers
    without a table here.

    Logs the interval (and where it came from) whenever it changes for a
    turret.

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
private _interval = _configured;
private _source = "Seconds Between Missiles setting";

if (_configured <= 0) then {
    private _weaponCfg = configFile >> "CfgWeapons" >> _weaponClass;
    // weaponState reports a weapon with no modes[] of its own ("this") under
    // its own class name, which isn't a sub-class -- the weapon itself is.
    private _mode = (weaponState [_system, _turretPath, _weaponClass]) param [2, ""];
    private _modeCfg = _weaponCfg >> _mode;
    if (!isClass _modeCfg) then { _modeCfg = _weaponCfg; };
    _interval = getNumber (_modeCfg >> "reloadTime") max 0;
    _source = format ["auto, %1 reloadTime", configName _modeCfg];
};

private _logKey = format ["AEGISM_intervalLogged_%1", _turretPath];
if ((_system getVariable [_logKey, -1]) != _interval) then {
    _system setVariable [_logKey, _interval, false];
    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " FIRE-RATE: %1 (%2) %3 -- %4s between missiles (%5).", _system, typeOf _system, _weaponClass, _interval, _source];
};

_interval
