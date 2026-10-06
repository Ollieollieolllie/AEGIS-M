/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_zeusApplyOverrides

Description:
    Applies a vehicle's AEGIS-M overrides as edited in Zeus (aegism_fnc_
    zeusAttributeDialog), on every machine: each override's own Eden
    expression runs (aegism_fnc_applyAttributeValues), so the same
    "AEGISM_ovr_*" variables are set as by the vehicle's Eden attributes.
    On the server the vehicle's settings are then re-resolved at once
    rather than at its next 5-second poll, and the result is logged
    (OVERRIDES).

    Nothing applies unless "Override Site Settings" is ticked. Settings
    entered with it off are saved and ignored -- five edits in one test went
    that way, each a minimum range that never took effect -- so that's said
    to whoever is in Zeus here (a hint and a chat line), and in the log, with
    the settings it left out.

Parameters:
    _vehicle - the vehicle <OBJECT>
    _pairs - [property, value] pairs from the dialog <ARRAY>

Returns:
    Nothing

Examples:
    [_patriot, [["AEGISM_ovr_enabled", true], ["AEGISM_ovr_salvoSize", "2"]]] remoteExecCall ["aegism_system_fnc_zeusApplyOverrides", 0];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle", "_pairs"];

if (isNull _vehicle) exitWith {};

private _attributesCfg = configFile >> "Cfg3DEN" >> "Object" >> "AttributeCategories" >> "AEGISM_VehicleOverrides" >> "Attributes";
[_vehicle, _attributesCfg, _pairs] call aegism_fnc_applyAttributeValues;

// Settings entered while the master switch is off: saved, but ignored. An
// override left on "Site setting" or blank is "".
private _enabled = _vehicle getVariable ["AEGISM_ovr_enabled", false];
private _ignored = [];
if (!_enabled) then {
    {
        _x params ["_property", "_value"];
        if (_property != "AEGISM_ovr_enabled" && {_value isEqualType ""} && {_value != ""}) then {
            _ignored pushBack format ["%1 = %2", getText (_attributesCfg >> _property >> "displayName"), _value];
        };
    } forEach _pairs;
};
if (_ignored isNotEqualTo [] && {hasInterface} && {!isNull (getAssignedCuratorLogic player)}) then {
    private _text = format ["AEGIS-M: %1 -- 'Override Site Settings' is OFF, so these are saved but NOT applied: %2. Tick it (the first row) to use them.",
        getText (configOf _vehicle >> "displayName"), _ignored joinString ", "];
    hint _text;
    systemChat _text;
};

if (!isServer || {isNil {_vehicle getVariable "AEGISM_system"}}) exitWith {
    if (isServer) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " OVERRIDES: %1 edited in Zeus -- takes effect once it's an AEGIS-M System (synced to a Site, or a self-contained AA vehicle).", _vehicle];
    };
};

private _overrides = [_vehicle] call aegism_system_fnc_resolveSettings;
private _summary = "off -- follows its Site's settings";
if (_enabled) then {
    _summary = if (_overrides isEqualTo []) then { "on, but every setting is left on 'Site setting'" } else { "on: " + (_overrides joinString ", ") };
} else {
    if (_ignored isNotEqualTo []) then {
        _summary = format ["OFF ('Override Site Settings' not ticked) -- follows its Site's settings; entered but NOT applied: %1", _ignored joinString ", "];
    };
};
diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " OVERRIDES: %1 edited in Zeus -- %2", _vehicle, _summary];
