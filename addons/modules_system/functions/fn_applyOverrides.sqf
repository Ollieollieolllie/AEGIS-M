/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_applyOverrides

Description:
    Applies a vehicle's own per-vehicle overrides on top of the settings it
    would otherwise use (its Site's, or the defaults when standalone).
    Full notes: docs/functions/modules_system.md

Parameters:
    _vehicle - the System vehicle <OBJECT>
    _settings - the inherited settings, never modified <HASHMAP>
    _kind - "engagement" or "crew" <STRING>
    _changes - optional; each applied override is appended as "key=value"
        (by reference, for logging) <ARRAY>

Returns:
    The effective settings: _settings itself if the vehicle has no active
    overrides, otherwise a modified copy <HASHMAP>

Examples:
    [_patriot, _siteSettings, "engagement"] call aegism_system_fnc_applyOverrides;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle", "_settings", "_kind", ["_changes", []]];

if !(_vehicle getVariable ["AEGISM_ovr_enabled", false]) exitWith { _settings };

private _keys = if (_kind == "crew") then {
    ["skillTier", "temperament", "costValueJudgment", "crewOnAutomated", "combatReaction"]
} else {
    ["targetPriority", "infiniteAmmo", "minAltitude", "maxAltitude", "engageFriendlyThreats", "engageOnlyThreats", "friendlyThreatRadius",
     "minRange", "maxRange", "salvoSize", "minShotInterval", "maxOffBoreSwing", "maxOffBoreLimit",
     "ciwsMaxRange", "ciwsMinElevation", "ciwsOpenFireChance", "ciwsCueAhead", "ciwsMinWindow", "ciwsBurstMin", "ciwsBurstMax", "ciwsBurstPause", "ciwsMode", "ciwsSelfDestruct",
     "emcon", "emconHold", "emconBurstOn", "emconBurstOff", "armShutdown"]
};

private _result = +_settings;
{
    private _value = _vehicle getVariable ("AEGISM_ovr_" + _x);
    if (!isNil "_value") then {
        _result set [_x, _value];
        _changes pushBack format ["%1=%2", _x, _value];
    };
} forEach _keys;

if (_kind == "engagement") then {
    // A mission saved with the old Last Resort Only override.
    private _lastResort = _vehicle getVariable "AEGISM_ovr_ciwsLastResort";
    if (!isNil "_lastResort" && {isNil { _vehicle getVariable "AEGISM_ovr_ciwsMode" }}) then {
        _result set ["ciwsMode", ["overlap", "lastResort"] select _lastResort];
        _changes pushBack format ["ciwsMode=%1", _result get "ciwsMode"];
    };
    private _allowlist = +(_result getOrDefault ["targetClassAllowlist", []]);
    {
        private _allow = _vehicle getVariable ("AEGISM_ovr_allow_" + _x);
        if (!isNil "_allow") then {
            if (_allow) then { _allowlist pushBackUnique _x; } else { _allowlist = _allowlist - [_x]; };
            _changes pushBack format ["engage %1=%2", _x, _allow];
        };
    } forEach ["missile", "rocket", "bomb", "artilleryShell", "fixedWing", "helicopter", "drone"];
    _result set ["targetClassAllowlist", _allowlist];
};

_result
