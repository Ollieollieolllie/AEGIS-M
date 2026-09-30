/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_applyOverrides

Description:
    Applies a vehicle's own per-vehicle overrides on top of the settings it
    would otherwise use (its Site's, or the defaults when standalone).

    Overrides come from the vehicle's Eden attributes, category "AEGIS-M:
    Vehicle Overrides" (addons/modules_system/config.cpp, Cfg3DEN), or from
    script. They only apply while the master switch "AEGISM_ovr_enabled" is
    true. Each setting is an object variable "AEGISM_ovr_<key>"; one that
    was left on "Site setting" (or blank) is never set, so it stays nil and
    that setting falls back to the Site's value.

        _vehicle setVariable ["AEGISM_ovr_enabled", true];
        _vehicle setVariable ["AEGISM_ovr_salvoSize", 2];
        _vehicle setVariable ["AEGISM_ovr_allow_artilleryShell", false];

    Target classes are overridden one at a time ("AEGISM_ovr_allow_<class>"
    true/false) and applied to the inherited allowlist.

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
    ["targetPriority", "minAltitude", "maxAltitude", "engageFriendlyThreats", "engageOnlyThreats", "friendlyThreatRadius",
     "minRange", "maxRange", "salvoSize", "minShotInterval", "maxOffBore",
     "ciwsMaxRange", "ciwsMinElevation", "ciwsOpenFireChance", "ciwsBurstMin", "ciwsBurstMax", "ciwsBurstPause", "ciwsLastResort"]
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
