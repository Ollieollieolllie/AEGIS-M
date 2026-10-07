/* ----------------------------------------------------------------------------
Function: aegism_fnc_setWeaponAiSuppressed

Description:
    Enables or disables a turret crewman's own AI targeting and firing, so
    the weapon only fires when AEGIS-M fires it.
    Full notes: docs/functions/main.md

Parameters:
    _vehicle - the vehicle whose turret crewman to affect <OBJECT>
    _turretPaths - array of turret paths (each itself an ARRAY, e.g. [0] or
        [0,0]) to suppress/restore <ARRAY of ARRAY>
    _suppress - true to disable independent targeting/engagement, false to
        restore normal AI behaviour <BOOLEAN>

Returns:
    Nothing

Examples:
    [_tigris, [[0], [1]], true] call aegism_fnc_setWeaponAiSuppressed;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_vehicle", "_turretPaths", "_suppress"];

if (isNull _vehicle || {!alive _vehicle}) exitWith {};

{
    private _gunner = _vehicle turretUnit _x;
    if (!isNull _gunner) then {
        if (_suppress) then {
            _gunner disableAI "TARGET";
            _gunner disableAI "AUTOTARGET";
            _gunner disableAI "FIREWEAPON";
        } else {
            _gunner enableAI "TARGET";
            _gunner enableAI "AUTOTARGET";
            _gunner enableAI "FIREWEAPON";
        };
    };
} forEach _turretPaths;
