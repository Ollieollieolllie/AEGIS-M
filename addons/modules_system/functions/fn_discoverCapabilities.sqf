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
    sensor config, or any Turret's) contains an ActiveRadarSensorComponent
    or PassiveRadarSensorComponent class. This is exactly the config the
    engine's own getSensorTargets already reads from, so a vehicle
    qualifying here is guaranteed to get real platform detections from it
    -- but getSensorTargets only reaches CfgVehicles-based objects with
    real target-size properties (radarTargetSize/irTargetSize/
    visualTargetSize); a fired CfgAmmo projectile has none of these (not
    even ACE3's own guided-missile CfgAmmo entries define them), so it is
    never itself a valid getSensorTargets result. Munitions are detected
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
        radarRange - real detection reach read from the qualifying sensor
            component's own config, metres (0 if hasRadar is false) <NUMBER>
        radarArc - real detection arc in degrees, from angleRangeHorizontal
            (360/omnidirectional if the sensor doesn't define one) <NUMBER>
        launcherWeapons - array of [turretPath, weaponClass, magazineClass,
            size] for each currently-loaded guided-missile/rocket weapon --
            size is the loaded ammo's indirectHitRange in metres, from
            aegism_intercept_fnc_munitionSize, used by aegism_intercept_fnc_
            assignEngagements to match a launcher's payload against a
            contact's own classified munition size <ARRAY>
        ciwsWeapons - array of [turretPath, weaponClass, magazineClass, 0]
            for each currently-loaded high-rate-of-fire gun weapon -- size
            is always 0 (a gun's fit comes from rate of fire/geometry, not
            warhead size), kept only so both arrays share one shape <ARRAY>

Examples:
    [_vehicle] call aegism_system_fnc_discoverCapabilities;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_CIWS_ROF_THRESHOLD 0.3

params ["_vehicle"];

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
            private _size = [_ammoClassName] call aegism_intercept_fnc_munitionSize;
            _launcherWeapons pushBackUnique [_turretPath, _weaponClass, _magClass, _size];
        } else {
            private _reloadTime = getNumber (configFile >> "CfgAmmo" >> _ammoClassName >> "reloadTime");
            if (_reloadTime > 0 && {_reloadTime < AEGISM_CIWS_ROF_THRESHOLD}) then {
                // A CIWS gun's own "size" is 0 (see aegism_intercept_fnc_
                // munitionSize) -- its fit for a contact comes from rate of
                // fire/engagement geometry, not warhead size, kept as a 4th
                // element anyway so launcherWeapons/ciwsWeapons share one
                // [turretPath, weaponClass, magazineClass, size] shape.
                _ciwsWeapons pushBackUnique [_turretPath, _weaponClass, _magClass, 0];
            } else {
                // Deliberately verbose -- a real autocannon that "should"
                // read as CIWS-capable but doesn't is otherwise a silent,
                // hard-to-diagnose dead end (the vehicle still qualifies as
                // a System via its other weapons, so nothing else would
                // ever surface that this specific gun was excluded, or why).
                diag_log text format ["[AEGIS-M] DISCOVERY: %1's %2 (ammo %3, reloadTime=%4) did not qualify as CIWS -- threshold is reloadTime > 0 and < %5.", _vehicle, _weaponClass, _ammoClassName, _reloadTime, AEGISM_CIWS_ROF_THRESHOLD];
            };
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
