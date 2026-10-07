/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_debugSetFireHold

Description:
    Debug console: forces a System's launcher/CIWS weapons to stop firing,
    or releases that hold.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the System vehicle to hold/release <OBJECT>
    _hold - true to set the hold (stop firing), false to release it <BOOLEAN>
    _turretPath - a specific turret path to hold/release, or [] to affect
        EVERY launcher/CIWS turret this System has (from its own cached
        AEGISM_system capability -- the System must already be recognized;
        run aegism_fnc_debugCheckSite first if unsure) <ARRAY, optional>

Returns:
    Nothing

Examples:
    [cursorObject, true] call aegism_intercept_fnc_debugSetFireHold;
    [cursorObject, false] call aegism_intercept_fnc_debugSetFireHold;
    [cursorObject, true, [0]] call aegism_intercept_fnc_debugSetFireHold;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_hold", ["_turretPath", []]];

if (isNull _system) exitWith {
    hint "[AEGIS-M] DEBUG FIRE HOLD: no vehicle given (pass cursorObject or a specific object).";
};

private _turretPaths = if (_turretPath isEqualTo []) then {
    private _capabilities = _system getVariable "AEGISM_system";
    if (isNil "_capabilities") exitWith {
        hint format ["[AEGIS-M] DEBUG FIRE HOLD: %1 has no cached AEGISM_system -- it's not a recognized System, so it has no known turrets to hold. Run aegism_fnc_debugCheckSite or aegism_system_fnc_debugCheckCiws first.", _system];
        []
    };
    ((_capabilities get "launcherWeapons") + (_capabilities get "ciwsWeapons")) apply { _x select 0 }
} else {
    [_turretPath]
};

{
    ([_system, _x] call aegism_intercept_fnc_turretState) set ["fireHold", _hold];
} forEach _turretPaths;

private _msg = format ["[AEGIS-M] DEBUG FIRE HOLD: %1 turret(s) %2 on %3 -- %4.", count _turretPaths, _turretPaths, _system, ["RELEASED", "HELD"] select _hold];
hint _msg;
diag_log text _msg;
