/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_classifyTarget

Description:
    Classifies a candidate contact (a fired munition object, or a detected
    platform) into one of the AEGIS-M target-class allowlist categories, so
    aegism_detect_fnc_addContact can gate it against a Site's Doctrine
    allowlist before it ever enters the tracked-contact list.

    Munitions are classified via aegism_detect_fnc_classifyAmmoClass (CfgAmmo
    inheritance). Platforms are classified via isKindOf against the vanilla
    base classes Helicopter, Plane, and UAV (checked independently, since a
    vehicle can be both e.g. a UAV helicopter).

    The answer depends only on the object's type, so it's cached per type
    ("AEGISM_cacheTargetClass") -- the aim, fuse and selection code call this
    every frame.

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
private _cache = missionNamespace getVariable "AEGISM_cacheTargetClass";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheTargetClass", _cache];
};
private _cached = _cache get _type;
if (!isNil "_cached") exitWith { _cached };

private _class = switch (true) do {
    // --- Munitions: CfgAmmo inheritance ---
    case (isClass (configFile >> "CfgAmmo" >> _type)): { [_type] call aegism_detect_fnc_classifyAmmoClass };
    // --- Platforms: CfgVehicles isKindOf ---
    case (_object isKindOf "AllVehicles"): {
        private _isUav = _object isKindOf "UAV";
        switch (true) do {
            case (_object isKindOf "Helicopter"): { ["helicopter", "drone"] select _isUav };
            case (_object isKindOf "Plane"): { ["fixedWing", "drone"] select _isUav };
            case (_isUav): { "drone" };
            default { "" };
        }
    };
    default { "" };
};

_cache set [_type, _class];
_class
