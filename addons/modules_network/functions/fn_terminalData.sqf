/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalData

Description:
    What a terminal may do and what it's connected to, whether it's a laptop
    on the ground or one a unit is carrying.
    Full notes: docs/functions/modules_network.md

Parameters:
    _terminal - the laptop, or the unit carrying one <OBJECT>

Returns:
    [access ("status" or "control") <STRING>, manual interception <BOOLEAN>,
     surface strike <BOOLEAN>, the Sites and vehicles it's connected to
     <ARRAY>] <ARRAY>

Examples:
    ([_laptop] call aegism_network_fnc_terminalData) params ["_access", "_engage", "_surface", "_link"];

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params [["_terminal", objNull]];

if (isNull _terminal) exitWith { ["status", false, false, []] };

// Carried: the first of the unit's laptops that it still has on it.
if (_terminal isKindOf "CAManBase") exitWith {
    private _held = ((items _terminal) + (magazines _terminal)) apply { toLower _x };
    private _carried = (_terminal getVariable ["AEGISM_terminalCarried", []]) select { (toLower (_x select 0)) in _held };
    if (!alive _terminal || {_carried isEqualTo []}) exitWith { ["status", false, false, []] };
    (_carried select 0) params ["", ["_link", []], ["_access", "status"], ["_engage", false], ["_surface", false]];
    [_access, _engage, _surface, _link select { !isNull _x }]
};

[
    _terminal getVariable ["AEGISM_terminalAccess", "status"],
    _terminal getVariable ["AEGISM_terminalEngage", false],
    _terminal getVariable ["AEGISM_terminalSurface", false],
    (_terminal getVariable ["AEGISM_terminalLink", []]) select { !isNull _x }
]
