/* ----------------------------------------------------------------------------
Function: aegism_network_fnc_terminalSelect

Description:
    Shows one of the things a terminal reaches on this machine's open
    terminal screen, on the Status or the Settings tab: asks the server for
    its board, or builds its settings form from the same attribute config
    Eden uses.
    Full notes: docs/functions/modules_network.md

Parameters:
    _index - the node picked, -1 to keep the one shown <NUMBER, default -1>
    _tab - "status" or "settings", "" to keep the one shown <STRING, default "">
    _rebuild - build the settings form again from the current values
        (Revert) <BOOLEAN, default false>

Returns:
    Nothing

Examples:
    [2] call aegism_network_fnc_terminalSelect;
    [-1, "settings"] call aegism_network_fnc_terminalSelect;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\terminal.hpp"

params [["_index", -1], ["_tab", ""], ["_rebuild", false]];

private _display = uiNamespace getVariable ["AEGISM_terminalDisplay", displayNull];
private _state = uiNamespace getVariable "AEGISM_terminalState";
if (isNull _display || {isNil "_state"}) exitWith {};

if (_index >= 0) then { _state set ["node", _index]; };
if (_tab != "") then { _state set ["tab", _tab]; };
if ((_state get "access") != "control") then { _state set ["tab", "status"]; };

private _node = (_state get "nodes") param [_state get "node", []];
if (_node isEqualTo []) exitWith {};
_node params ["_target", "_label", "_kind"];
private _isSite = _kind == "site";
private _settings = (_state get "tab") == "settings";

(_display displayCtrl AEGISM_TERMINAL_HEADING_IDC) ctrlSetStructuredText parseText format [
    "<t size='0.95' color='%1'>%2</t><t size='0.8' color='%3'>   %4</t>",
    AEGISM_TERMINAL_ACCENT_HEX, _label, AEGISM_TERMINAL_DIM_HEX,
    if (_settings) then { ["this vehicle's overrides of its Site's settings", "the Site's settings"] select _isSite } else { "live status" }];

(_display displayCtrl AEGISM_TERMINAL_GROUP_IDC) ctrlShow !_settings;
{ (_display displayCtrl _x) ctrlShow _settings; } forEach [AEGISM_TERMINAL_FORM_IDC, AEGISM_TERMINAL_APPLY_IDC, AEGISM_TERMINAL_REVERT_IDC];
// The tab shown is marked in its text as well as its colour (a menu button
// doesn't always take a text colour).
(_display displayCtrl AEGISM_TERMINAL_TAB_STATUS_IDC) ctrlSetText (["> STATUS", "STATUS"] select _settings);
(_display displayCtrl AEGISM_TERMINAL_TAB_STATUS_IDC) ctrlSetTextColor ([AEGISM_TERMINAL_ACCENT, AEGISM_TERMINAL_DIM] select _settings);
(_display displayCtrl AEGISM_TERMINAL_TAB_SETTINGS_IDC) ctrlSetText (["SETTINGS", "> SETTINGS"] select _settings);
(_display displayCtrl AEGISM_TERMINAL_TAB_SETTINGS_IDC) ctrlSetTextColor ([AEGISM_TERMINAL_DIM, AEGISM_TERMINAL_ACCENT] select _settings);

if (!_settings) exitWith {
    (_display displayCtrl AEGISM_TERMINAL_NOTE_IDC) ctrlSetStructuredText parseText "";
    [_target] remoteExecCall ["aegism_network_fnc_terminalRequest", 2];
};
if (!_rebuild && {(_state get "formFor") isEqualTo _target}) exitWith {};

// --- The settings form ---------------------------------------------------------
// One row per attribute, under Eden's own section headings, each showing the
// target's current value: [property, control, typeName, the control, a
// combo's values].
{ ctrlDelete _x; } forEach (_state get "formControls");
(_display displayCtrl AEGISM_TERMINAL_NOTE_IDC) ctrlSetStructuredText parseText "";

private _attributesCfg = if (_isSite) then { configOf _target >> "Attributes" } else {
    configFile >> "Cfg3DEN" >> "Object" >> "AttributeCategories" >> "AEGISM_VehicleOverrides" >> "Attributes"
};
private _form = _display displayCtrl AEGISM_TERMINAL_FORM_IDC;
private _formW = ((ctrlPosition _form) select 2) - 0.02 * safeZoneW;
private _rowH = 0.034 * safeZoneH;
private _gap = 0.003 * safeZoneH;
private _labelW = 0.58 * _formW;
private _valueX = _labelW + 0.01 * _formW;
private _valueW = _formW - _valueX;
private _y = 0;
private _rows = [];
private _controls = [];
private _shade = false;
{
    private _cfg = _x;
    private _control = getText (_cfg >> "control");
    if (_control == "SubCategory") then {
        if (_y > 0) then { _y = _y + 2 * _gap; };
        private _head = _display ctrlCreate ["RscStructuredText", -1, _form];
        _head ctrlSetPosition [0, _y, _formW, _rowH];
        _head ctrlSetBackgroundColor [0.09, 0.2, 0.27, 0.9];
        _head ctrlSetStructuredText parseText format ["<t font='PuristaSemibold' color='%1'>%2</t>", AEGISM_TERMINAL_ACCENT_HEX, toUpper getText (_cfg >> "displayName")];
        _head ctrlCommit 0;
        _controls pushBack _head;
        _y = _y + _rowH + _gap;
        _shade = false;
    } else {
        if (_control != "") then {
            private _property = getText (_cfg >> "property");
            private _typeName = getText (_cfg >> "typeName");
            private _tooltip = getText (_cfg >> "tooltip");
            private _default = call compile (getText (_cfg >> "defaultValue"));
            if (isNil "_default") then { _default = ""; };
            private _current = _target getVariable _property;
            if (isNil "_current") then { _current = _default; };

            private _labelCtrl = _display ctrlCreate ["RscText", -1, _form];
            _labelCtrl ctrlSetPosition [0, _y, _labelW, _rowH];
            _labelCtrl ctrlSetText getText (_cfg >> "displayName");
            _labelCtrl ctrlSetTooltip _tooltip;
            if (_shade) then { _labelCtrl ctrlSetBackgroundColor [1, 1, 1, 0.04]; };
            _labelCtrl ctrlCommit 0;
            _controls pushBack _labelCtrl;

            private _values = [];
            private _valueCtrl = switch (_control) do {
                case "Combo": {
                    private _combo = _display ctrlCreate ["RscCombo", -1, _form];
                    _combo ctrlSetPosition [_valueX, _y, _valueW, _rowH];
                    {
                        _values pushBack ([getText (_x >> "value"), getNumber (_x >> "value")] select (isNumber (_x >> "value")));
                        _combo lbAdd getText (_x >> "name");
                    } forEach configProperties [_cfg >> "Values", "isClass _x", true];
                    // A value stored as true/false (a "Site setting / On / Off"
                    // combo's own expression does that) shows as on/off.
                    if (_current isEqualType true) then { _current = ["off", "on"] select _current; };
                    _combo lbSetCurSel ((_values find _current) max 0);
                    _combo
                };
                case "Checkbox": {
                    private _box = _display ctrlCreate ["RscCheckBox", -1, _form];
                    _box ctrlSetPosition [_valueX, _y, 0.75 * _rowH, _rowH];
                    _box cbSetChecked (_current isEqualTo true);
                    _box
                };
                default {
                    private _edit = _display ctrlCreate ["RscEdit", -1, _form];
                    _edit ctrlSetPosition [_valueX, _y, _valueW, _rowH];
                    _edit ctrlSetBackgroundColor [0, 0, 0, 0.45];
                    _edit ctrlSetText ([str _current, _current] select (_current isEqualType ""));
                    _edit
                };
            };
            _valueCtrl ctrlSetTooltip _tooltip;
            _valueCtrl ctrlCommit 0;
            _controls pushBack _valueCtrl;
            _rows pushBack [_property, _control, _typeName, _valueCtrl, _values];
            _y = _y + _rowH + _gap;
            _shade = !_shade;
        };
    };
} forEach configProperties [_attributesCfg, "isClass _x", true];

_state set ["rows", _rows];
_state set ["formControls", _controls];
_state set ["formFor", _target];
