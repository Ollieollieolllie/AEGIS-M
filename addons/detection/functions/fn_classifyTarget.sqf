/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_classifyTarget

Description:
    Classifies a candidate contact (a fired munition object, or a detected
    platform) into one of the AEGIS-M target-class allowlist categories, so
    aegism_detect_fnc_addContact can gate it against a Site's Doctrine
    allowlist before it ever enters the tracked-contact list.

    Munitions are classified via aegism_detect_fnc_classifyAmmoClass (a
    CfgAmmo inheritance-chain walk). Platforms are classified via isKindOf
    against the vanilla base classes Helicopter, Plane, and UAV (checked
    independently, since a vehicle can be both e.g. a UAV helicopter).

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
if (isClass (configFile >> "CfgAmmo" >> _type)) exitWith {
    [_type] call aegism_detect_fnc_classifyAmmoClass
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
