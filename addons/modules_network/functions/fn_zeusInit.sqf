/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_zeusInit

Description:
    Zeus access to AEGIS-M's settings (aegism_network_fnc_zeusEdit). Run on
    every machine with an interface, from this addon's XEH_postInit.

        Site module - double-click it, or place one: its settings dialog
            opens (Zeus Enhanced's own object window is turned off for
            Sites, see aegism_network_fnc_moduleInit)
        Vehicle - the "AEGIS-M" button in its Zeus Enhanced attributes
            window opens its overrides
        Either - right-click it: "AEGIS-M Settings" in the context menu
        Module "AEGIS-M > Edit Air Defence" - place it on a Site or an
            air-defence vehicle (or within 50 m of a Site)

    The dialogs themselves come from Zeus Enhanced (ZEN). Without it only
    the double-click/placement hooks exist, and they hint that ZEN is
    needed.

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_network_fnc_zeusInit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

if (!hasInterface) exitWith {};

#define AEGISM_ICON "\x\aegism\addons\main\data\aegism_logo_ca.paa"

// Every Game Master logic, including ones created later. The events only
// fire on the machine of the player using that Game Master.
["ModuleCurator_F", "Init", {
    params ["_curator"];
    _curator addEventHandler ["CuratorObjectDoubleClicked", {
        params ["", "_entity"];
        if (_entity isKindOf "AEGISM_Module_Site") then { [_entity] call aegism_network_fnc_zeusEdit; };
    }];
    _curator addEventHandler ["CuratorObjectPlaced", {
        params ["", "_entity"];
        if (_entity isKindOf "AEGISM_Module_Site") then {
            _entity setVariable ["zen_attributes_disabled", true];
            // Next frame: let the placement finish first.
            [aegism_network_fnc_zeusEdit, [_entity]] call CBA_fnc_execNextFrame;
        };
    }];
}, true, [], true] call CBA_fnc_addClassEventHandler;

if (!isNil "zen_attributes_fnc_addButton") then {
    ["Object", ["AEGIS-M", "This air-defence vehicle's AEGIS-M overrides (the same as its Eden 'AEGIS-M: Vehicle Overrides')."],
        { [_this] call aegism_network_fnc_zeusEdit; },
        { [_this, false] call aegism_network_fnc_zeusEdit },
        true
    ] call zen_attributes_fnc_addButton;
};

if (!isNil "zen_context_menu_fnc_createAction") then {
    private _action = ["AEGISM_Settings", "AEGIS-M Settings", AEGISM_ICON,
        {
            params ["", "", "", "", "", "_hoveredEntity"];
            [_hoveredEntity] call aegism_network_fnc_zeusEdit;
        },
        {
            params ["", "", "", "", "", "_hoveredEntity"];
            [_hoveredEntity, false] call aegism_network_fnc_zeusEdit
        }
    ] call zen_context_menu_fnc_createAction;
    [_action, [], 0] call zen_context_menu_fnc_addAction;
};

if (!isNil "zen_custom_modules_fnc_register") then {
    ["AEGIS-M", "Edit Air Defence", {
        params ["_position", "_attached"];
        // Dropped next to a Site rather than on it (a module icon isn't
        // always picked up as the object under the cursor): the nearest Site.
        if (isNull _attached) then {
            private _sites = (allMissionObjects "AEGISM_Module_Site") select { _x distance2D _position <= 50 };
            if (_sites isNotEqualTo []) then {
                _attached = ([_sites, [_position], { _x distance2D _input0 }, "ASCEND"] call BIS_fnc_sortBy) select 0;
            };
        };
        [_attached] call aegism_network_fnc_zeusEdit;
    }, AEGISM_ICON] call zen_custom_modules_fnc_register;
};
