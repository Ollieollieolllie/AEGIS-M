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
    magazines, used later via BIS_fnc_fire and magazineTurretAmmo.

    Radar: true if the vehicle's CfgVehicles config (its own top-level
    sensor config, or any Turret's) contains an ActiveRadarSensorComponent
    or PassiveRadarSensorComponent class. This is exactly the config the
    engine's own getSensorTargets already reads from, so a vehicle
    qualifying here is guaranteed to get real platform detections from it
    -- but getSensorTargets only reaches CfgVehicles-based objects with
    real target-size properties (radarTargetSize/irTargetSize/
    visualTargetSize); a fired CfgAmmo projectile has none of these (not
    even vanilla CfgAmmo entries define them), so it is never itself a
    valid getSensorTargets result. Munitions are detected
    by a separate, dedicated pipeline instead (see aegism_detect_fnc_
    trackMunition), which needs this radar's own real detection reach --
    radarRange/radarArc below are read from the SAME ActiveRadar/
    PassiveRadarSensorComponent config getSensorTargets itself reads
    (maxRange across its target-type sub-classes, angleRangeHorizontal),
    not a mission-designer-set number, so a vehicle with a genuinely
    narrow or short-ranged radar behaves like one for munition tracking
    too.

    The sensor component actually lives under "Components >>
    SensorsManagerComponent >> Components" in every vanilla Arma 3 vehicle
    checked (this is the real, current nesting per BIS's own Sensors Config
    Reference and the Arma 3 sensor-overhaul devblog; a bare top-level
    "Sensors" class was an earlier assumption in this codebase that turned
    out to be wrong -- confirmed the hard way when B_Radar_System_01_F, the
    vanilla AA radar unit, never once registered as having radar during
    testing despite very obviously having one in-game). Both paths are
    checked (Components-nested first, since that's the real one; the older
    bare "Sensors" path is kept as a fallback for any mod vehicle that might
    still use it) rather than assuming either is universal.

    Launcher/CIWS: walks every currently-loaded magazine (magazinesAllTurrets)
    and resolves which weapon on that turret fires it (CfgWeapons magazines[]
    plus any CfgMagazineWells listed in magazineWell[]).

    Only AIR-CAPABLE weapons qualify: the loaded ammo's own CfgAmmo airLock
    must be >= 1 (the engine's own "can engage air targets" flag). Without
    this, an IFV's ATGM or a tank's coax would count as air defence.

    Launcher: ammo classifying as "missile" (guided). Unguided rockets can't
    intercept anything and are not launcher weapons.

    CIWS: non-missile ammo whose FIRING WEAPON has a fire mode faster than
    AEGISM_CIWS_ROF_THRESHOLD. Rate of fire is a CfgWeapons per-mode
    reloadTime, NOT CfgAmmo reloadTime (an unrelated submunition field that
    real CIWS rounds like B_35mm_AA don't define at all).

    Every weapon also carries its own REAL engagement envelope, read from
    config and never scaled by the AEGIS-M range-scale setting:
        missile - CfgAmmo missileLockMinDistance/missileLockMaxDistance
            (falling back to maxControlRange, then the weapon's modes)
        gun - min/max of CfgWeapons mode minRange/maxRange (the engine's own
            AI engagement bands, e.g. 0-2500m for autocannon_35mm)
    and CIWS weapons carry their burst duration (mode reloadTime x burst,
    longest AI mode) so the engagement loop fires one burst per burst-time
    rather than on missile salvo rules.

Parameters:
    _vehicle - the vehicle to inspect <OBJECT>
    _quiet - suppress the per-weapon DISCOVERY log lines (for callers
        that only need the result, e.g. sorting) <BOOLEAN, default false>

Returns:
    HashMap. Keys:
        hasRadar - <BOOLEAN>
        radarRange - real detection reach read from the qualifying sensor
            component's own config, metres (0 if hasRadar is false) <NUMBER>
        radarArc - real detection arc in degrees, from angleRangeHorizontal
            (360/omnidirectional if the sensor doesn't define one) <NUMBER>
        launcherWeapons / ciwsWeapons - arrays of weaponInfo:
            [turretPath, weaponClass, magazineClass, size, minRange,
             maxRange, burstTime]
            size - loaded ammo's indirectHitRange (aegism_intercept_fnc_
                munitionSize), used for launcher/threat size matching; 0 for
                CIWS
            minRange/maxRange - the weapon's own real envelope, metres
            burstTime - seconds one CIWS burst takes (0 for launchers)

Examples:
    [_vehicle] call aegism_system_fnc_discoverCapabilities;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_CIWS_ROF_THRESHOLD 0.3

params ["_vehicle", ["_quiet", false]];

private _vehicleConfig = configOf _vehicle;

// Given a vehicle or turret config entry, returns the config holding its
// ActiveRadarSensorComponent/PassiveRadarSensorComponent classes directly
// as sub-classes, checking the REAL nesting first (Components >>
// SensorsManagerComponent >> Components) and falling back to a bare
// top-level "Sensors" class for any vehicle/mod that still uses the older
// structure -- configNull (isClass false) if neither exists.
private _fnSensorsRoot = {
    private _cfg = _this;
    private _real = _cfg >> "Components" >> "SensorsManagerComponent" >> "Components";
    if (isClass _real) exitWith { _real };
    _cfg >> "Sensors"
};

// Returns [range, arc] if the given sensors-root config (see _fnSensorsRoot
// above) has an ActiveRadarSensorComponent or PassiveRadarSensorComponent
// as a DIRECT child class, or [] if neither exists. Confirmed against real
// vehicle configs (BIS's own jets, and third-party mods defining their own
// radar-equipped aircraft) that these two are always direct siblings under
// "Components >> SensorsManagerComponent >> Components" alongside things
// like IRSensorComponent/LaserSensorComponent/NVSensorComponent -- NOT
// nested inside some further intermediate wrapper class (an earlier version
// of this function wrongly assumed an extra nesting layer here, which meant
// it silently never found a real vehicle's radar at all). Range is the
// largest maxRange across the component's own target-type sub-classes
// (AirTarget, GroundTarget, ...); arc is its own angleRangeHorizontal, or
// 360 if that property isn't defined (omnidirectional).
private _findRadarComponent = {
    private _sensorsCfg = _this;
    private _radarCfg = if (isClass (_sensorsCfg >> "ActiveRadarSensorComponent")) then {
        _sensorsCfg >> "ActiveRadarSensorComponent"
    } else {
        if (isClass (_sensorsCfg >> "PassiveRadarSensorComponent")) then { _sensorsCfg >> "PassiveRadarSensorComponent" } else { configNull }
    };

    if (!isClass _radarCfg) exitWith { [] };

    // configProperties [configEntry, conditionString, recursive] (unary,
    // single array argument) lists a config entry's sub-entries matching
    // condition -- "isClass _x" filters to sub-classes only, e.g. this
    // component's own AirTarget/GroundTarget target-type blocks (a
    // component class also carries plain scalar properties, like
    // angleRangeHorizontal itself, that aren't sub-classes).
    private _maxRange = 0;
    {
        if (isNumber (_x >> "maxRange")) then {
            _maxRange = _maxRange max (getNumber (_x >> "maxRange"));
        };
    } forEach (configProperties [_radarCfg, "isClass _x", false]);

    private _arc = if (isNumber (_radarCfg >> "angleRangeHorizontal")) then {
        getNumber (_radarCfg >> "angleRangeHorizontal")
    } else {
        360
    };

    [_maxRange, _arc]
};

private _hasRadar = false;
private _radarRange = 0;
private _radarArc = 360;

// NOTE: deliberately NOT using `_found params [...]` here -- params always
// creates a fresh private binding in whatever scope it's called from, which
// would shadow the outer _radarRange/_radarArc declared above rather than
// updating them (the assigned values would be lost the moment each if-block
// exits). Plain `_radarRange = ...` assignment (no `private`) correctly
// walks up to the existing outer declaration instead.
private _vehicleSensorsRoot = _vehicleConfig call _fnSensorsRoot;
if (isClass _vehicleSensorsRoot) then {
    private _found = _vehicleSensorsRoot call _findRadarComponent;
    if (_found isNotEqualTo []) then {
        _hasRadar = true;
        _radarRange = _found select 0;
        _radarArc = _found select 1;
    };
};
if (!_hasRadar && {isClass (_vehicleConfig >> "Turrets")}) then {
    {
        if (!_hasRadar) then {
            private _turretSensorsRoot = _x call _fnSensorsRoot;
            if (isClass _turretSensorsRoot) then {
                private _found = _turretSensorsRoot call _findRadarComponent;
                if (_found isNotEqualTo []) then {
                    _hasRadar = true;
                    _radarRange = _found select 0;
                    _radarArc = _found select 1;
                };
            };
        };
    } forEach (configProperties [(_vehicleConfig >> "Turrets"), "isClass _x", false]);
};

private _launcherWeapons = [];
private _ciwsWeapons = [];

// Every magazine a weapon accepts: its own magazines[] plus every magazine
// listed in each CfgMagazineWells class named in its magazineWell[].
private _fnWeaponMagazines = {
    private _weaponCfg = _this;
    private _mags = getArray (_weaponCfg >> "magazines");
    {
        private _wellCfg = configFile >> "CfgMagazineWells" >> _x;
        { _mags append (getArray _x); } forEach (configProperties [_wellCfg, "isArray _x", true]);
    } forEach (getArray (_weaponCfg >> "magazineWell"));
    _mags apply { toLower _x }
};

// [minRange, maxRange, fastestReloadTime, longestBurstTime] across a
// weapon's own fire modes (modes[] sub-classes, or the weapon class itself
// if it has no modes).
private _fnModeStats = {
    private _weaponCfg = _this;
    private _modeCfgs = (getArray (_weaponCfg >> "modes")) apply { if (_x == "this") then { _weaponCfg } else { _weaponCfg >> _x } };
    _modeCfgs = _modeCfgs select { isClass _x };
    if (_modeCfgs isEqualTo []) then { _modeCfgs = [_weaponCfg]; };

    private _minRange = -1;
    private _maxRange = 0;
    private _fastest = -1;
    private _burstTime = 0;
    {
        private _reload = getNumber (_x >> "reloadTime");
        private _burst = getNumber (_x >> "burst") max 1;
        if (_reload > 0) then {
            if (_fastest < 0 || {_reload < _fastest}) then { _fastest = _reload; };
            _burstTime = _burstTime max (_reload * _burst);
        };
        if (isNumber (_x >> "minRange")) then {
            private _modeMin = getNumber (_x >> "minRange");
            if (_minRange < 0 || {_modeMin < _minRange}) then { _minRange = _modeMin; };
        };
        _maxRange = _maxRange max (getNumber (_x >> "maxRange"));
    } forEach _modeCfgs;

    [_minRange max 0, _maxRange, _fastest, _burstTime]
};

{
    // magazinesAllTurrets returns [className, turretPath, ammoCount, id,
    // creator] per entry -- turretPath is index 1, not 2.
    _x params ["_magClass", "_turretPath"];

    private _ammoClassName = getText (configFile >> "CfgMagazines" >> _magClass >> "ammo");
    private _ammoCfg = configFile >> "CfgAmmo" >> _ammoClassName;
    private _class = [_ammoClassName] call aegism_detect_fnc_classifyAmmoClass;
    private _magLower = toLower _magClass;

    private _weaponClass = "";
    {
        if (_magLower in ((configFile >> "CfgWeapons" >> _x) call _fnWeaponMagazines)) exitWith {
            _weaponClass = _x;
        };
    } forEach (_vehicle weaponsTurret _turretPath);

    if (_weaponClass != "" && {isClass _ammoCfg}) then {
        private _weaponCfg = configFile >> "CfgWeapons" >> _weaponClass;
        (_weaponCfg call _fnModeStats) params ["_modeMin", "_modeMax", "_fastestReload", "_burstTime"];
        private _airCapable = (getNumber (_ammoCfg >> "airLock")) >= 1;

        if (!_airCapable) exitWith {
            if (_quiet) exitWith {};
            diag_log text format ["[AEGIS-M] DISCOVERY: %1's %2 (ammo %3) ignored -- ammo airLock < 1, cannot engage air targets.", _vehicle, _weaponClass, _ammoClassName];
        };

        if (_class == "missile") exitWith {
            private _minRange = getNumber (_ammoCfg >> "missileLockMinDistance");
            if (_minRange <= 0) then { _minRange = _modeMin; };
            private _maxRange = getNumber (_ammoCfg >> "missileLockMaxDistance");
            if (_maxRange <= 0) then { _maxRange = getNumber (_ammoCfg >> "maxControlRange"); };
            if (_maxRange <= 0) then { _maxRange = _modeMax; };
            private _size = [_ammoClassName] call aegism_intercept_fnc_munitionSize;
            _launcherWeapons pushBackUnique [_turretPath, _weaponClass, _magClass, _size, _minRange, _maxRange, 0];
        };

        if (_class in ["rocket", "bomb"]) exitWith {};

        if (_fastestReload > 0 && {_fastestReload < AEGISM_CIWS_ROF_THRESHOLD}) then {
            _ciwsWeapons pushBackUnique [_turretPath, _weaponClass, _magClass, 0, _modeMin, _modeMax, _burstTime];
        } else {
            if (_quiet) exitWith {};
            diag_log text format ["[AEGIS-M] DISCOVERY: %1's %2 (fastest mode reloadTime=%3) did not qualify as CIWS -- threshold is reloadTime > 0 and < %4.", _vehicle, _weaponClass, _fastestReload, AEGISM_CIWS_ROF_THRESHOLD];
        };
    };
} forEach (magazinesAllTurrets _vehicle);

createHashMapFromArray [
    ["hasRadar", _hasRadar],
    ["radarRange", _radarRange],
    ["radarArc", _radarArc],
    ["launcherWeapons", _launcherWeapons],
    ["ciwsWeapons", _ciwsWeapons]
]
