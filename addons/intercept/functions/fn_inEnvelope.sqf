/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_inEnvelope

Description:
    Whether a contact at a given slant range and height can be engaged by a
    specific weapon under the resolved doctrine.
    Full notes: docs/functions/intercept.md

Parameters:
    _engagementSettings - resolved doctrine <HASHMAP>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _distance - slant range from the weapon to the contact, metres <NUMBER>
    _height - contact height above ground, metres <NUMBER>
    _role - "launcher" or "ciws" (optional, default "launcher") <STRING>
    _elevation - contact elevation above the weapon's horizon, degrees
        (optional, default 90; see aegism_intercept_fnc_elevationAngle) <NUMBER>

Returns:
    <BOOLEAN>

Examples:
    [_settings, _weaponInfo, 3200, 150, "launcher"] call aegism_intercept_fnc_inEnvelope;
    [_settings, _weaponInfo, 900, 60, "ciws", 3.8] call aegism_intercept_fnc_inEnvelope;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_engagementSettings", "_weaponInfo", "_distance", "_height", ["_role", "launcher"], ["_elevation", 90]];

if (_role == "ciws" && {_elevation < (_engagementSettings getOrDefault ["ciwsMinElevation", 5])}) exitWith { false };

([_engagementSettings, _weaponInfo, _role] call aegism_intercept_fnc_envelopeBounds) params ["_minRange", "_maxRange", "_minAltitude", "_maxAltitude"];

(_distance >= _minRange)
    && {_distance <= _maxRange}
    && {_height >= _minAltitude}
    && {_maxAltitude <= 0 || {_height <= _maxAltitude}}
