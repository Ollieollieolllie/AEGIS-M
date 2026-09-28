/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_envelopeBounds

Description:
    The range and height limits of one weapon under the resolved doctrine --
    the intersection aegism_intercept_fnc_inEnvelope tests against (see its
    header for the rules). Split out so a caller testing many positions for
    one weapon (the Site coordinator's layered-reserve plan) resolves them
    once.

Parameters:
    _engagementSettings - resolved doctrine <HASHMAP>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _role - "launcher" or "ciws" (optional, default "launcher") <STRING>

Returns:
    [minRange, maxRange, minAltitude, maxAltitude (0 = no cap)] metres <ARRAY>

Examples:
    [_settings, _weaponInfo, "launcher"] call aegism_intercept_fnc_envelopeBounds;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_engagementSettings", "_weaponInfo", ["_role", "launcher"]];
_weaponInfo params ["", "", "", "", ["_weaponMin", 0], ["_weaponMax", 0]];

private _isCiws = _role == "ciws";
private _doctrineMin = if (_isCiws) then { 0 } else {
    [_engagementSettings getOrDefault ["minRange", 0]] call aegism_fnc_scaledRange
};
private _doctrineMax = [_engagementSettings getOrDefault [["maxRange", "ciwsMaxRange"] select _isCiws, 0]] call aegism_fnc_scaledRange;

[
    _weaponMin max _doctrineMin,
    [_weaponMax, _weaponMax min _doctrineMax] select (_doctrineMax > 0),
    _engagementSettings getOrDefault ["minAltitude", 0],
    _engagementSettings getOrDefault ["maxAltitude", 0]
]
