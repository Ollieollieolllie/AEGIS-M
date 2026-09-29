/* ----------------------------------------------------------------------------
Function: aegism_fnc_applyAttributeValues

Description:
    Sets an object's Eden attributes from script, the way Eden itself does:
    each attribute's own "expression" runs with _this = the object and
    _value = the new value. Used by the Zeus dialogs (aegism_fnc_
    zeusAttributeDialog), so a Zeus edit sets exactly the same variables an
    Eden edit would.

    Each attribute's variable is cleared first: an override left on "Site
    setting" (or blank) has an expression that sets nothing, and has to go
    back to nil (inheriting from the Site) rather than keep its old value.

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
