/* ----------------------------------------------------------------------------
Function: aegism_fnc_applyAttributeValues

Description:
    Sets an object's Eden attributes from script, the way Eden itself does:
    each attribute's own "expression" runs with _this = the object and
    _value = the new value.
    Full notes: docs/functions/main.md

Parameters:
    _target - the object <OBJECT>
    _attributesCfg - the attributes config class <CONFIG>
    _pairs - [property, value] pairs <ARRAY>

Returns:
    Nothing

Examples:
    [_site, configOf _site >> "Attributes", [["maxRange", 8000]]] call aegism_fnc_applyAttributeValues;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_target", "_attributesCfg", "_pairs"];

private _expressions = createHashMap;
{
    _expressions set [getText (_x >> "property"), getText (_x >> "expression")];
} forEach configProperties [_attributesCfg, "isClass _x && {getText (_x >> 'control') != 'SubCategory'}", true];

{
    _x params ["_property", "_value"];
    private _expression = _expressions get _property;
    if (!isNil "_expression") then {
        _target setVariable [_property, nil];
        // The expression reads _value from this scope.
        _target call compile _expression;
    };
} forEach _pairs;
