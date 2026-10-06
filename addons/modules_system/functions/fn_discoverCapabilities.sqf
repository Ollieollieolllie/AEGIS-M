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

    Sensors: every sensor component in the vehicle's CfgVehicles config
    (its own sensor config, and every turret's) whose componentType is one
    AEGIS-M uses -- whatever the component class itself is called:
        radar   - ActiveRadarSensorComponent
        passive - PassiveRadarSensorComponent (hears only what emits: a
                  radar that's on). What it hears cues the Site's radars
                  (Radar Emission), but isn't engaged on its own (aegism_
                  fnc_hasTrack).
        ir      - IRSensorComponent
        visual  - VisualSensorComponent
    This is exactly the config the engine's own getSensorTargets reads, and
    the engine does all the detecting -- aircraft directly, munitions
    through the sensor proxy each one carries (aegism_detect_fnc_
    trackMunition). What's read here says what a vehicle has: whether it
    has a radar, or any sensor of its own (for adoption, aegism_system_fnc_
    moduleInit), and each sensor's reach and arc for the debug overlays.

    Each sensor's reach is its AirTarget maxRange (the largest maxRange of
    any target-type sub-class if it has no AirTarget), and its arc its
    angleRangeHorizontal (360 if undefined) -- both inherited from the
    vanilla templates where the vehicle doesn't set them: the vanilla
    Radar_System_01's radar is 120 degrees from SensorTemplateActiveRadar.
    Where it points: a sensor with an animDirection (e.g. "mainGun") turns
    with the turret whose gun or body is that selection -- the Spartan's
    IR sensor looks wherever its launcher points. Without one it's fixed to
    the hull, or, inside a turret's own config, treated as all-round.

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
    real CIWS rounds like B_35mm_AA don't define at all). Cannons only, not
    machine guns: a weapon built on CfgWeapons MGunCore (the base of every
    vanilla machine gun, which mods build on) is left out -- POOK's SAM
    vehicles' self-defence M2HB and PKT were being run as CIWS against
    rockets. Its ball rounds don't burst (vanilla .50 ball: hit 30,
    indirectHit 0; the Phalanx and 20-35 mm AA rounds: hit 60-70,
    indirectHit 6-25). The vehicle override "Guns Used as CIWS" (AEGISM_
    ovr_ciwsGuns) changes this per vehicle: "all" every rapid-fire gun,
    machine guns too; "none" no gun at all.

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
        sensors - every sensor, longest reach first, each [type, range, arc,
            aim, viewDistanceCoef, maxFog, component, verticalArc, aimDown,
            clutter]:
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
        hasRadar - an active radar <BOOLEAN>
        hasSensor - a sensor of its own that finds aircraft: an active
            radar, IR or visual <BOOLEAN>
        clutterHeight - the highest clutter of those sensors (-1 none)
            <NUMBER>
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

            if (_range > 0) then {
                _sensors pushBack [_type, _range, _arc min 360, _aim, _viewDistanceCoef, _maxFog, configName _componentCfg, _verticalArc min 360, getNumber (_componentCfg >> "aimDown"), _clutter];
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
// The highest any of its sensors that find aircraft loses a target in
// ground clutter (-1 none): a munition proxy below it is moved with its
// munition, so it shows its real speed (aegism_detect_fnc_munitionTracker).
private _clutterHeight = -1;
{ if ((_x select 0) in ["radar", "ir", "visual"]) then { _clutterHeight = _clutterHeight max (_x select 9); }; } forEach _sensors;

private _launcherWeapons = [];
private _ciwsWeapons = [];
// Which rapid-fire guns count as CIWS (see header): "auto" cannons only,
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
    ["clutterHeight", _clutterHeight],
    ["radarRange", _radarRange],
    ["radarArc", _radarArc],
    ["launcherWeapons", _launcherWeapons],
    ["ciwsWeapons", _ciwsWeapons]
]
