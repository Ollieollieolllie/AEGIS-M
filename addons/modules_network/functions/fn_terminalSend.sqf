/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalSend

Description:
    Apply on this machine's open terminal screen: reads the settings form
    and sends its values to the server for the Site or vehicle shown
    (aegism_network_fnc_terminalApply).
    Full notes: docs/functions/modules_network.md

Parameters:
    None

Returns:
    Nothing

Examples:
    [] call aegism_network_fnc_terminalSend;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

private _display = uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull];
private _state = uiNamespace getVariable "AEGISM_terminalState";
if (isNull _display || {isNil "_state"}) exitWith {};

private _target = _state get "formFor";
if (isNull _target || {(_state get "access") != "control"}) exitWith {};

// As Zeus sends them (aegism_fnc_zeusAttributeDialog): a combo's value as
// its config has it, a number typed into a box as a number where Eden gives
// one.
private _pairs = [];
{
    _x params ["_property", "_control", "_typeName", "_ctrl", "_values"];
    private _value = switch (_control) do {
        case "Combo": { _values param [lbCurSel _ctrl, ""] };
        case "Checkbox": { cbChecked _ctrl };
        default {
            private _text = ctrlText _ctrl;
            [_text, parseNumber _text] select (_typeName == "NUMBER")
        };
    };
    _pairs pushBack [_property, _value];
} forEach (_state get "formRows");

(_display displayCtrl AEGISM_TERMINAL_NOTE_IDC) ctrlSetStructuredText parseText format ["<t size='0.85' color='%1'>Sending...</t>", AEGISM_TERMINAL_DIM_HEX];
[_state get "terminal", _state get "anchor", _target, _pairs] remoteExecCall ["aegism_network_fnc_terminalApply", 2];
