/* ----------------------------------------------------------------------------
Function: aegism_fnc_zeusAttributeDialog

Description:
    Opens a Zeus dialog (Zeus Enhanced, zen_dialog_fnc_create) for one set of
    AEGIS-M Eden attributes on one object -- the Site module's own settings,
    or a vehicle's AEGIS-M overrides -- built straight from that attribute
    config, so Zeus shows exactly what Eden does: every attribute's display
    name, tooltip and choices, with the object's CURRENT values filled in
    (every row forces its value: ZEN would otherwise show whatever was last
    confirmed in a dialog of the same title, i.e. another Site's values).

        Combo - a list of its Values (a value set by the attribute's own
            expression as true/false shows as its "on"/"off" entry)
        Checkbox - a checkbox
        Edit - a text box (a number, or blank)

    ZEN dialogs have no headings, so Eden's section headings (SubCategory)
    go into each row's tooltip, and a name used in two sections ("Max Range
    (m)" for launchers and for CIWS) is prefixed with its section.

    On confirm the chosen values go, as [property, value] pairs, to
    _applyFunction on every machine, and to anyone joining later (one JIP
    entry per object and function, replaced by each edit): it runs each
    attribute's own Eden expression, so Zeus and Eden set exactly the same
    variables, and every machine's copy (what this dialog reads) stays
    current.

    Without Zeus Enhanced there's no dialog to open: a hint says so.

Parameters:
    _target - the object being edited <OBJECT>
    _attributesCfg - the attributes config class (its sub-classes are the
        attributes) <CONFIG>
    _title - dialog title <STRING>
    _applyFunction - name of the function that applies [_target, pairs] <STRING>

Returns:
    Nothing

Examples:
    [_site, configOf _site >> "Attributes", "AEGIS-M: Site Settings", "aegism_network_fnc_zeusApplySite"] call aegism_fnc_zeusAttributeDialog;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_target", "_attributesCfg", "_title", "_applyFunction"];

if (isNull _target) exitWith {};
if (isNil "zen_dialog_fnc_create") exitWith {
    hint "AEGIS-M: editing Sites and vehicles in Zeus needs the Zeus Enhanced (ZEN) mod.";
};

// [config, section] per attribute, and how often each display name occurs.
private _entries = [];
private _nameCounts = createHashMap;
private _section = "";
{
    private _control = getText (_x >> "control");
    if (_control == "SubCategory") then {
        _section = getText (_x >> "displayName");
    } else {
        if (_control != "") then {
            _entries pushBack [_x, _section];
            private _name = getText (_x >> "displayName");
            _nameCounts set [_name, (_nameCounts getOrDefault [_name, 0]) + 1];
        };
    };
} forEach configProperties [_attributesCfg, "isClass _x", true];

// [property, control, typeName, dialog row] per attribute.
private _attributes = [];
{
    _x params ["_cfg", "_section"];
    private _control = getText (_cfg >> "control");
    private _property = getText (_cfg >> "property");
    private _typeName = getText (_cfg >> "typeName");
    private _name = getText (_cfg >> "displayName");
    // "Launchers (Missiles)" -> "Launchers"
    private _sectionShort = [(_section splitString "(") param [0, ""]] call CBA_fnc_trim;
    if ((_nameCounts get _name) > 1 && {_sectionShort != ""}) then { _name = _sectionShort + " " + _name; };
    private _tooltip = getText (_cfg >> "tooltip");
    if (_section != "") then { _tooltip = _section + ": " + _tooltip; };
    private _label = [_name, _tooltip];

    private _default = call compile (getText (_cfg >> "defaultValue"));
    if (isNil "_default") then { _default = ""; };
    private _current = _target getVariable _property;
    if (isNil "_current") then { _current = _default; };

    private _row = switch (_control) do {
        case "Combo": {
            private _values = [];
            private _labels = [];
            {
                _values pushBack ([getText (_x >> "value"), getNumber (_x >> "value")] select (isNumber (_x >> "value")));
                _labels pushBack getText (_x >> "name");
            } forEach configProperties [_cfg >> "Values", "isClass _x", true];
            // A value stored as true/false (a "Site setting / On / Off"
            // combo's own expression does that) shows as on/off.
            if (_current isEqualType true) then { _current = ["off", "on"] select (_current isEqualTo true); };
            ["COMBO", _label, [_values, _labels, (_values find _current) max 0], true]
        };
        case "Checkbox": {
            ["CHECKBOX", _label, [_current isEqualTo true], true]
        };
        default {
            ["EDIT", _label, [[str _current, _current] select (_current isEqualType "")], true]
        };
    };
    _attributes pushBack [_property, _control, _typeName, _row];
} forEach _entries;

[_title, _attributes apply { _x select 3 }, {
    params ["_dialogValues", "_args"];
    _args params ["_target", "_attributes", "_applyFunction"];
    if (isNull _target) exitWith {};
    private _pairs = [];
    {
        _x params ["_property", "_control", "_typeName"];
        private _value = _dialogValues select _forEachIndex;
        // A number typed into a box goes in as a number where Eden gives one.
        if (_control == "Edit" && {_typeName == "NUMBER"}) then { _value = parseNumber _value; };
        _pairs pushBack [_property, _value];
    } forEach _attributes;
    [_target, _pairs] remoteExecCall [_applyFunction, 0, format ["AEGISM_zeus_%1_%2", _applyFunction, netId _target]];
}, {}, [_target, _attributes, _applyFunction]] call zen_dialog_fnc_create;
