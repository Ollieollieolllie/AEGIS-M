/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_zeusEdit

Description:
    Opens the right AEGIS-M settings dialog in Zeus for an entity:
        a Site module - the Site's own settings (every Site attribute)
        an air-defence vehicle, or one of its crew - that vehicle's AEGIS-M
            overrides (the same "AEGIS-M: Vehicle Overrides" as in Eden)
    An air-defence vehicle is one AEGIS-M has adopted as a System, or found
    capable and deferred until it is synced to a Site.

    With _open false it only answers whether the entity can be edited (for
    Zeus Enhanced menu and button conditions).

Parameters:
    _entity - the entity <OBJECT>
    _open - open the dialog (default true) <BOOL>

Returns:
    Whether the entity has AEGIS-M settings to edit <BOOL>

Examples:
    [_site] call aegism_network_fnc_zeusEdit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_entity", objNull], ["_open", true]];

if !(_entity isEqualType objNull) exitWith { false };

if (_entity isKindOf "AEGISM_Module_Site") exitWith {
    if (_open) then {
        [_entity, configOf _entity >> "Attributes", "AEGIS-M: Site Settings", "aegism_network_fnc_zeusApplySite"] call aegism_fnc_zeusAttributeDialog;
    };
    true
};

private _vehicle = vehicle _entity;
private _isAirDefence = !isNull _vehicle && {!isNil {_vehicle getVariable "AEGISM_system"} || {_vehicle getVariable ["AEGISM_systemDeferred", false]}};
if (_open) then {
    if (_isAirDefence) then {
        [_vehicle, configFile >> "Cfg3DEN" >> "Object" >> "AttributeCategories" >> "AEGISM_VehicleOverrides" >> "Attributes",
            format ["AEGIS-M: %1 Overrides", getText (configOf _vehicle >> "displayName")], "aegism_system_fnc_zeusApplyOverrides"] call aegism_fnc_zeusAttributeDialog;
    } else {
        hint "AEGIS-M: choose a Site module, or an air-defence vehicle (a radar, SAM launcher or CIWS/SHORAD AEGIS-M has recognised).";
    };
};
_isAirDefence
