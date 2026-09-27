/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_classifyTarget

Description:
    Classifies a candidate contact (a fired munition object, or a detected
    platform) into one of the AEGIS-M target-class allowlist categories, so
    aegism_detect_fnc_addContact can gate it against a System/Network's
    Engagement Settings allowlist before it ever enters the tracked-contact
    list.

    Munitions are classified by walking their CfgAmmo config-inheritance
    chain (via CBA_fnc_inheritsFrom) against the vanilla base classes
    ShellCore (artillery/mortar shells), BombCore (aircraft bombs),
    MissileCore (guided missiles), and RocketCore (unguided rockets) --
    inheritance is a more reliable discriminator than simulation-string
    matching, since mods reuse simulation types across different ammo
    roles but rarely break the base class chain. Platforms are classified
    via isKindOf against the vanilla base classes Helicopter, Plane, and
    UAV (checked independently, since a vehicle can be both e.g. a UAV
    helicopter).

Parameters:
    _object - the munition or platform object to classify <OBJECT>

Returns:
    One of "missile" | "rocket" | "bomb" | "artilleryShell" | "fixedWing" |
    "helicopter" | "drone", or "" if it could not be classified (callers
    must treat an empty string as never-allowlisted) <STRING>

Examples:
    [_projectile] call aegism_detect_fnc_classifyTarget;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_object"];

if (isNull _object) exitWith { "" };

private _type = typeOf _object;

// --- Munitions: classify via CfgAmmo inheritance chain ---
private _ammoConfig = configFile >> "CfgAmmo" >> _type;
if (isClass _ammoConfig) exitWith {
    private _missileCore = configFile >> "CfgAmmo" >> "MissileCore";
    private _bombCore = configFile >> "CfgAmmo" >> "BombCore";
    private _shellCore = configFile >> "CfgAmmo" >> "ShellCore";
    private _rocketCore = configFile >> "CfgAmmo" >> "RocketCore";

    if (isClass _missileCore && {[_ammoConfig, _missileCore] call CBA_fnc_inheritsFrom}) exitWith { "missile" };
    if (isClass _bombCore && {[_ammoConfig, _bombCore] call CBA_fnc_inheritsFrom}) exitWith { "bomb" };
    if (isClass _shellCore && {[_ammoConfig, _shellCore] call CBA_fnc_inheritsFrom}) exitWith { "artilleryShell" };
    if (isClass _rocketCore && {[_ammoConfig, _rocketCore] call CBA_fnc_inheritsFrom}) exitWith { "rocket" };

    // Fallback: simulation-string match for ammo that doesn't chain
    // through the vanilla *Core classes (some mod ammo reparents directly
    // off Default).
    private _simulation = toLower getText (_ammoConfig >> "simulation");
    if (_simulation == "shotmissile") exitWith { "missile" };
    if (_simulation == "shotrocket") exitWith { "rocket" };
    if (_simulation in ["shotshell", "shotsubmunitions"]) exitWith { "artilleryShell" };

    ""
};

// --- Platforms: classify via CfgVehicles isKindOf ---
if (_object isKindOf "AllVehicles") exitWith {
    private _isUav = _object isKindOf "UAV";
    if (_object isKindOf "Helicopter") exitWith { ["helicopter", "drone"] select _isUav };
    if (_object isKindOf "Plane") exitWith { ["fixedWing", "drone"] select _isUav };
    if (_isUav) exitWith { "drone" };

    ""
};

""
