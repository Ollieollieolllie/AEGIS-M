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

[_vehicle, configFile >> "Cfg3DEN" >> "Object" >> "AttributeCategories" >> "AEGISM_VehicleOverrides" >> "Attributes", _pairs] call aegism_fnc_applyAttributeValues;

if (!isServer || {isNil {_vehicle getVariable "AEGISM_system"}}) exitWith {
    if (isServer) then {
        diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " OVERRIDES: %1 edited in Zeus -- takes effect once it's an AEGIS-M System (synced to a Site, or a self-contained AA vehicle).", _vehicle];
    };
};

private _overrides = [_vehicle] call aegism_system_fnc_resolveSettings;
private _summary = "off -- follows its Site's settings";
if (_vehicle getVariable ["AEGISM_ovr_enabled", false]) then {
    _summary = if (_overrides isEqualTo []) then { "on, but every setting is left on 'Site setting'" } else { "on: " + (_overrides joinString ", ") };
};
diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " OVERRIDES: %1 edited in Zeus -- %2", _vehicle, _summary];
