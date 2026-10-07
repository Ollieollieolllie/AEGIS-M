/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_discoverCapabilities

Description:
    Reads a vehicle's own config and loadout to determine what AEGIS-M
    capabilities it has: sensors, launchers, CIWS guns.
    Full notes: docs/functions/modules_system.md

Parameters:
    _vehicle - the vehicle to inspect <OBJECT>
    _quiet - suppress the per-weapon DISCOVERY log lines (for callers
        that only need the result, e.g. sorting) <BOOLEAN, default false>

Returns:
    HashMap. Keys:
        sensors - every sensor, longest reach first, each [type, range, arc,
            aim, viewDistanceCoef, maxFog, component, verticalArc, aimDown,
            clutter, detail]:
            type - "radar" / "passive" / "ir" / "visual"
            range - reach, metres; arc - horizontal arc, degrees
            aim - turret path it turns with, or [] for the hull
            viewDistanceCoef - its AirTarget viewDistanceLimitCoef: reach is
                capped at the view distance times this where it's above 0
                (vanilla IR and visual: 1); -1 = no cap
            maxFog - maxFogSeeThrough, -1 if undefined
            component - its config class name
            verticalArc - angleRangeVertical, degrees (360 if undefined;
                the vanilla radar template's is 120)
            aimDown - degrees its boresight is tilted down (0 if undefined)
            clutter - its maxGroundNoiseDistance: how high above the ground
                a target can be lost in ground clutter, which the engine
                filters by the target's speed (the vanilla radar template:
                200 m, minSpeedThreshold 21 m/s); -1 if it has no ground
                clutter, 1e10 if it sets no ceiling
            detail - HashMap, what else decides whether it sees a munition
                (aegism_detect_fnc_sensorView): "air" and "ground" (its
                AirTarget and GroundTarget [minRange, maxRange,
                objectDistanceLimitCoef, viewDistanceLimitCoef]), "night"
                (nightRangeCoef), "noiseCoef" / "noiseMax" (groundNoise
                DistanceCoef, maxGroundNoiseDistance), "speedMin" /
                "speedMax" (min/maxSpeedThreshold), "trackSpeed" and
                "trackHeight" ([min, max] trackable speed and height above
                terrain)
        hasRadar - an active radar <BOOLEAN>
        hasSensor - a sensor of its own that finds aircraft: an active
            radar, IR or visual <BOOLEAN>
        radarRange / radarArc - the longest-reaching active radar's reach
            and arc (0 / 360 if none) <NUMBER>
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

#include "..\..\main\rpt.hpp"

#define AEGISM_CIWS_ROF_THRESHOLD 0.3

params ["_vehicle", ["_quiet", false]];

private _vehicleConfig = configOf _vehicle;

// Given a vehicle or turret config entry, returns the config holding its
// sensor component classes directly as sub-classes, checking the REAL
// nesting first (Components >> SensorsManagerComponent >> Components) and
// falling back to a bare top-level "Sensors" class for any vehicle/mod that
// still uses the older structure -- configNull (isClass false) if neither
// exists.
private _fnSensorsRoot = {
    private _cfg = _this;
    private _real = _cfg >> "Components" >> "SensorsManagerComponent" >> "Components";
    if (isClass _real) exitWith { _real };
    _cfg >> "Sensors"
};

// Every turret path with its config, including turrets nested inside
// turrets (e.g. a commander's station on the main turret).
private _turrets = (allTurrets [_vehicle, false]) apply { [_x, [_vehicle, _x] call CBA_fnc_getTurret] };

// The turret a sensor's animDirection selection belongs to: the one whose
// gun or body is that selection (vanilla: animDirection "mainGun", turret
// gun "MainGun" -- case differs). [] if none.
private _fnAimTurret = {
    private _selection = toLower _this;
    private _index = _turrets findIf {
        private _turretCfg = _x select 1;
        (toLower getText (_turretCfg >> "gun")) == _selection || {(toLower getText (_turretCfg >> "body")) == _selection}
    };
    if (_index < 0) exitWith { [] };
    (_turrets select _index) select 0
};

// Appends the sensors under one sensors root (see _fnSensorsRoot) to
// _sensors. A sensor is identified by its componentType, NOT its class
// name: vanilla happens to name the class after its type, but mods don't
// -- the POOK AN/TPY-2's radar is class MIM23BCPRadarSensorComponent.
// _ownerPath is the turret whose config holds it ([] for the vehicle's own).
private _sensorTypes = createHashMapFromArray [
    ["activeradarsensorcomponent", "radar"],
    ["passiveradarsensorcomponent", "passive"],
    ["irsensorcomponent", "ir"],
    ["visualsensorcomponent", "visual"]
];
private _sensors = [];
private _fnReadSensors = {
    params ["_root", "_ownerPath"];
    if (!isClass _root) exitWith {};
    {
        private _componentCfg = _x;
        private _type = _sensorTypes getOrDefault [toLower getText (_componentCfg >> "componentType"), ""];
        if (_type != "") then {
            // configProperties [entry, condition, inherited] lists the
            // component's own target-type blocks (AirTarget, GroundTarget).
            private _airCfg = _componentCfg >> "AirTarget";
            private _range = 0;
            if (isClass _airCfg) then {
                _range = getNumber (_airCfg >> "maxRange");
            } else {
                { _range = _range max (getNumber (_x >> "maxRange")); } forEach (configProperties [_componentCfg, "isClass _x", true]);
            };
            private _viewDistanceCoef = if (isNumber (_airCfg >> "viewDistanceLimitCoef")) then { getNumber (_airCfg >> "viewDistanceLimitCoef") } else { -1 };
            private _arc = if (isNumber (_componentCfg >> "angleRangeHorizontal")) then { getNumber (_componentCfg >> "angleRangeHorizontal") } else { 360 };
            private _verticalArc = if (isNumber (_componentCfg >> "angleRangeVertical")) then { getNumber (_componentCfg >> "angleRangeVertical") } else { 360 };
            private _maxFog = if (isNumber (_componentCfg >> "maxFogSeeThrough")) then { getNumber (_componentCfg >> "maxFogSeeThrough") } else { -1 };

            // Where it points: with its animDirection's turret; otherwise
            // the hull (the vehicle's own config) or, inside a turret's own
            // config, all-round -- that turret slews it, and nothing says
            // which way.
            private _animDirection = getText (_componentCfg >> "animDirection");
            private _aim = if (_animDirection == "") then { [] } else { _animDirection call _fnAimTurret };
            if (_aim isEqualTo [] && {_ownerPath isNotEqualTo []}) then { _arc = 360; };
            if (_arc >= 360) then { _aim = []; };

            // Ground clutter: how high above the ground a target can still be
            // lost in it -- -1 if the sensor has none (groundNoiseDistanceCoef
            // -1 or undefined), 1e10 if it sets no ceiling.
            private _clutter = -1;
            if (isNumber (_componentCfg >> "groundNoiseDistanceCoef") && {getNumber (_componentCfg >> "groundNoiseDistanceCoef") >= 0}) then {
                _clutter = getNumber (_componentCfg >> "maxGroundNoiseDistance");
                if (!isNumber (_componentCfg >> "maxGroundNoiseDistance") || {_clutter < 0}) then { _clutter = 1e10; };
            };

            // The rest of what decides whether it sees a munition (aegism_
            // detect_fnc_sensorView): its ranges against a sky and a ground
            // background ([minRange, maxRange, objectDistanceLimitCoef,
            // viewDistanceLimitCoef] each; one stands in for a missing other),
            // and its night, ground-clutter, speed and height limits, with
            // the engine's own defaults where it sets none (BI's Sensors
            // config reference).
            private _fnNumber = { params ["_entry", "_default"]; [_default, getNumber _entry] select (isNumber _entry) };
            private _fnRanges = {
                params ["_cfg"];
                if (!isClass _cfg) exitWith { [] };
                [[_cfg >> "minRange", -1] call _fnNumber, [_cfg >> "maxRange", -1] call _fnNumber,
                    [_cfg >> "objectDistanceLimitCoef", -1] call _fnNumber, [_cfg >> "viewDistanceLimitCoef", -1] call _fnNumber]
            };
            private _airRanges = [_airCfg] call _fnRanges;
            private _groundRanges = [_componentCfg >> "GroundTarget"] call _fnRanges;
            if (_airRanges isEqualTo []) then { _airRanges = [[-1, _range, -1, -1], _groundRanges] select (_groundRanges isNotEqualTo []); };
            if (_groundRanges isEqualTo []) then { _groundRanges = _airRanges; };
            private _detail = createHashMapFromArray [
                ["air", _airRanges],
                ["ground", _groundRanges],
                ["night", [_componentCfg >> "nightRangeCoef", 1] call _fnNumber],
                ["noiseCoef", [_componentCfg >> "groundNoiseDistanceCoef", -1] call _fnNumber],
                ["noiseMax", [_componentCfg >> "maxGroundNoiseDistance", -1] call _fnNumber],
                ["speedMin", [_componentCfg >> "minSpeedThreshold", 0] call _fnNumber],
                ["speedMax", [_componentCfg >> "maxSpeedThreshold", 1000] call _fnNumber],
                ["trackSpeed", [[_componentCfg >> "minTrackableSpeed", -1e10] call _fnNumber, [_componentCfg >> "maxTrackableSpeed", 1e10] call _fnNumber]],
                ["trackHeight", [[_componentCfg >> "minTrackableATL", -1e10] call _fnNumber, [_componentCfg >> "maxTrackableATL", 1e10] call _fnNumber]]
            ];

            if (_range > 0) then {
                _sensors pushBack [_type, _range, _arc min 360, _aim, _viewDistanceCoef, _maxFog, configName _componentCfg, _verticalArc min 360, getNumber (_componentCfg >> "aimDown"), _clutter, _detail];
            };
        };
    } forEach (configProperties [_root, "isClass _x", true]);
};

[_vehicleConfig call _fnSensorsRoot, []] call _fnReadSensors;
{ _x params ["_path", "_turretCfg"]; [_turretCfg call _fnSensorsRoot, _path] call _fnReadSensors; } forEach _turrets;
_sensors = [_sensors, [], { _x select 1 }, "DESCEND"] call BIS_fnc_sortBy;

private _radars = _sensors select { (_x select 0) == "radar" };
private _hasRadar = _radars isNotEqualTo [];
private _radarRange = 0;
private _radarArc = 360;
if (_hasRadar) then {
    _radarRange = (_radars select 0) select 1;
    _radarArc = (_radars select 0) select 2;
};
private _hasSensor = (_sensors findIf { (_x select 0) in ["radar", "ir", "visual"] }) != -1;

private _launcherWeapons = [];
private _ciwsWeapons = [];
// Which rapid-fire guns count as CIWS (see notes): "auto" cannons only,
// "all", or "none" -- the vehicle's own override, with its master switch on.
private _ciwsGuns = if (_vehicle getVariable ["AEGISM_ovr_enabled", false]) then { _vehicle getVariable ["AEGISM_ovr_ciwsGuns", "auto"] } else { "auto" };

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
            if (AEGISM_RPT_VERBOSE) then {
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DISCOVERY: %1's %2 (ammo %3) ignored -- ammo airLock < 1, cannot engage air targets.", _vehicle, _weaponClass, _ammoClassName];
            };
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
            private _machineGun = _weaponClass isKindOf ["MGunCore", configFile >> "CfgWeapons"];
            // Once per vehicle and gun: it has a line per magazine, and is
            // discovered more than once.
            private _skipLogged = _vehicle getVariable ["AEGISM_ciwsSkipLogged", []];
            private _logSkip = !_quiet && {AEGISM_RPT_VERBOSE} && {!(_weaponClass in _skipLogged)};
            if (_logSkip && {(_ciwsGuns == "none") || {_machineGun && {_ciwsGuns != "all"}}}) then {
                _skipLogged pushBack _weaponClass;
                _vehicle setVariable ["AEGISM_ciwsSkipLogged", _skipLogged];
            };
            switch (true) do {
                case (_ciwsGuns == "none"): {
                    if (_logSkip) then {
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DISCOVERY: %1's %2 not used as CIWS -- its vehicle override Guns Used as CIWS is None.", _vehicle, _weaponClass];
                    };
                };
                case (_machineGun && {_ciwsGuns != "all"}): {
                    if (_logSkip) then {
                        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DISCOVERY: %1's %2 (%3) not used as CIWS -- a machine gun (CfgWeapons MGunCore), not a cannon; its vehicle override Guns Used as CIWS = Every Rapid-Fire Gun uses it.", _vehicle, _weaponClass, _ammoClassName];
                    };
                };
                default {
                    _ciwsWeapons pushBackUnique [_turretPath, _weaponClass, _magClass, 0, _modeMin, _modeMax, _burstTime];
                };
            };
        } else {
            if (_quiet) exitWith {};
            if (AEGISM_RPT_VERBOSE) then {
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " DISCOVERY: %1's %2 (fastest mode reloadTime=%3) did not qualify as CIWS -- threshold is reloadTime > 0 and < %4.", _vehicle, _weaponClass, _fastestReload, AEGISM_CIWS_ROF_THRESHOLD];
            };
        };
    };
} forEach (magazinesAllTurrets _vehicle);

createHashMapFromArray [
    ["sensors", _sensors],
    ["hasRadar", _hasRadar],
    ["hasSensor", _hasSensor],
    ["radarRange", _radarRange],
    ["radarArc", _radarArc],
    ["launcherWeapons", _launcherWeapons],
    ["ciwsWeapons", _ciwsWeapons]
]
