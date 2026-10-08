/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_zeusEdit

Description:
    Opens the right AEGIS-M settings dialog in Zeus for an entity: a Site's
    settings, or a vehicle's overrides.
    Full notes: docs/functions/modules_network.md

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

// A terminal (a laptop): what players can do at it.
if ([_entity] call aegism_network_fnc_isTerminal) exitWith {
    if (_open) then {
        if (isNil "zen_dialog_fnc_create") exitWith {
            hint "AEGIS-M: editing a terminal in Zeus needs the Zeus Enhanced (ZEN) mod.";
        };
        ["AEGIS-M: Terminal", [
            ["COMBO", ["Terminal Access", "What players can do at this laptop once it is synced to a Site or an air-defence vehicle. Status Only: see the live status board. Full Control: also change the settings of what it reaches."],
                [["status", "control"], ["Status Only", "Full Control"], (["status", "control"] find (_entity getVariable ["AEGISM_terminalAccess", "status"])) max 0], true],
            ["CHECKBOX", ["Manual Interception", "Gives this laptop the Interception page: a map of what its Site tracks and its weapons, from which a player can order a chosen weapon onto a chosen track (a friendly included), end those orders, and switch the Site's automation off or on."],
                _entity getVariable ["AEGISM_terminalEngage", false], true],
            ["CHECKBOX", ["Surface Strike", "With Manual Interception: lets this laptop order the Site's launchers and guns to fire at a point on the ground, picked on the Interception page's map."],
                _entity getVariable ["AEGISM_terminalSurface", false], true],
            ["CHECKBOX", ["Fixed in Place", "On: this laptop can't be picked up. Off: it can be carried off and used wherever it's put down, or from the action menu of whoever carries it."],
                _entity getVariable ["AEGISM_terminalFixed", false], true]
        ], {
            params ["_values", "_terminal"];
            if (!isNull _terminal) then {
                _terminal setVariable ["AEGISM_terminalAccess", _values select 0, true];
                _terminal setVariable ["AEGISM_terminalEngage", _values select 1, true];
                _terminal setVariable ["AEGISM_terminalSurface", _values select 2, true];
                _terminal setVariable ["AEGISM_terminalFixed", _values select 3, true];
                // (Its action again on every machine, which locks or unlocks it.)
                [_terminal, objNull] remoteExecCall ["aegism_network_fnc_terminalLink", 2];
            };
        }, {}, _entity] call zen_dialog_fnc_create;
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
        hint "AEGIS-M: choose a Site module, an air-defence vehicle (a radar, SAM launcher or CIWS/SHORAD AEGIS-M has recognised), or a terminal laptop.";
    };
};
_isAirDefence
