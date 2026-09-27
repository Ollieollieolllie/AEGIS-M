/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_discoverCapabilities

Description:
    Reads a vehicle's own native config and current loadout to determine
    what AEGIS-M capabilities it has, rather than relying on a mission
    designer to declare a role by hand: if it has a radar, it has a radar;
    if it has guided missiles, it's a launcher; if it also has a high-rate-
    of-fire gun (because it's a SHORAD or Tigris-style all-in-one vehicle),
    it's also a CIWS/CRAM. AEGIS-M never spawns or tracks its own ammo --
    everything here points back at the vehicle's real turrets/weapons/
    magazines, used later via fireAtTarget and magazineTurretAmmo.

    Radar: true if the vehicle's CfgVehicles config (its own top-level
    Sensors, or any Turret's Sensors) contains an ActiveRadarSensorComponent
    or PassiveRadarSensorComponent class. This is exactly the config the
    engine's own getSensorTargets already reads from, so a vehicle
    qualifying here is guaranteed to get real detections from it.

    Launcher/CIWS: walks every currently-loaded magazine (magazinesAllTurrets,
    so a resupplied/rearmed vehicle is reflected correctly) and, for each
    one, classifies its ammo via aegism_detect_fnc_classifyAmmoClass and
    resolves which weapon on that turret actually fires it (cross-
    referencing CfgWeapons' own "magazines" list, since magazinesAllTurrets
    gives magazine/turret pairs, not the firing weapon's classname that
    aegism_intercept_fnc_fireWeapon's fireAtTarget call needs). A magazine
    classifying as "missile" or "rocket" makes it a launcher weapon. Plain
    (non-guided) gun ammo with a very short CfgAmmo reloadTime (below
    AEGISM_CIWS_ROF_THRESHOLD, i.e. a genuinely high-rate-of-fire autocannon
    rather than e.g. a tank's main gun) makes it a CIWS weapon -- an
    inherent heuristic, since there's no clean "this is an anti-air gun"
    config flag to read.

Parameters:
    _vehicle - the vehicle to inspect <OBJECT>

Returns:
    HashMap. Keys:
        hasRadar - <BOOLEAN>
        launcherWeapons - array of [turretPath, weaponClass, magazineClass]
            for each currently-loaded guided-missile/rocket weapon <ARRAY>
        ciwsWeapons - array of [turretPath, weaponClass, magazineClass] for
            each currently-loaded high-rate-of-fire gun weapon <ARRAY>

Examples:
    [_vehicle] call aegism_system_fnc_discoverCapabilities;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_CIWS_ROF_THRESHOLD 0.3

params ["_vehicle"];

private _vehicleConfig = configOf _vehicle;

// configProperties [configEntry, conditionString, recursive] (unary,
// single array argument) lists a config entry's sub-entries matching
// condition -- "isClass _x" filters to sub-classes only (a Turrets/
// Sensors block also carries plain scalar properties we don't want here).
private _hasSensorComponent = {
    private _sensorsCfg = _this;
    private _found = false;
    {
        if (isClass (_x >> "ActiveRadarSensorComponent") || {isClass (_x >> "PassiveRadarSensorComponent")}) then {
            _found = true;
        };
    } forEach (configProperties [_sensorsCfg, "isClass _x", false]);
    _found
};

private _hasRadar = false;
if (isClass (_vehicleConfig >> "Sensors")) then {
    _hasRadar = (_vehicleConfig >> "Sensors") call _hasSensorComponent;
};
if (!_hasRadar && {isClass (_vehicleConfig >> "Turrets")}) then {
    {
        if (isClass (_x >> "Sensors") && {(_x >> "Sensors") call _hasSensorComponent}) then {
            _hasRadar = true;
        };
    } forEach (configProperties [(_vehicleConfig >> "Turrets"), "isClass _x", false]);
};

private _launcherWeapons = [];
private _ciwsWeapons = [];

{
    // magazinesAllTurrets returns [className, turretPath, ammoCount, id,
    // creator] per entry -- turretPath is index 1, not 2.
    _x params ["_magClass", "_turretPath", "_ammoCount"];

    private _ammoClassName = getText (configFile >> "CfgMagazines" >> _magClass >> "ammo");
    private _class = [_ammoClassName] call aegism_detect_fnc_classifyAmmoClass;

    // magazinesAllTurrets gives the magazine/turret pair, not the weapon
    // that fires it -- cross-reference each weapon mounted on this turret
    // against its own CfgWeapons "magazines" list to find the match.
    private _weaponClass = "";
    {
        if (_magClass in (getArray (configFile >> "CfgWeapons" >> _x >> "magazines"))) exitWith {
            _weaponClass = _x;
        };
    } forEach (_vehicle weaponsTurret _turretPath);

    if (_weaponClass != "") then {
        if (_class in ["missile", "rocket"]) then {
            _launcherWeapons pushBackUnique [_turretPath, _weaponClass, _magClass];
        } else {
            private _reloadTime = getNumber (configFile >> "CfgAmmo" >> _ammoClassName >> "reloadTime");
            if (_reloadTime > 0 && {_reloadTime < AEGISM_CIWS_ROF_THRESHOLD}) then {
                _ciwsWeapons pushBackUnique [_turretPath, _weaponClass, _magClass];
            };
        };
    };
} forEach (magazinesAllTurrets _vehicle);

createHashMapFromArray [
    ["hasRadar", _hasRadar],
    ["launcherWeapons", _launcherWeapons],
    ["ciwsWeapons", _ciwsWeapons]
]
