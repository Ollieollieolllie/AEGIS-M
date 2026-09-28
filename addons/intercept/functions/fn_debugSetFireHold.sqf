/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_debugSetFireHold

Description:
    On-demand hard hold/release for a System's launcher/CIWS weapons, meant
    to be run from the Arma debug console while testing -- forces a
    specific System (or every weapon it has, if no turret path is given) to
    stop firing entirely, or releases a hold previously set.

    This is a genuine circuit breaker, not a Doctrine/salvo setting: it's
    checked in aegism_intercept_fnc_fireWeapon itself, the single narrowest
    choke point every real fire command in the whole codebase passes
    through, so it guarantees no shot from that turret regardless of what
    upstream logic (assignEngagements/engagementLoop, working correctly or
    not) tries to trigger -- useful specifically while tracking down a
    suspected multi-shot bug, to isolate whether the problem is upstream
    (assignment/engagementLoop deciding to fire more than intended) or
    downstream (the engine/weapon itself firing more than commanded) of
    fireWeapon's own single choke point.

    Not something a mission should ship with set permanently -- it's a
    blunt debugging tool, not a Doctrine feature (see AEGISM_Module_Site's
    own Attributes for the real, intended ways to shape engagement
    behaviour).

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
    private _holdKey = format ["AEGISM_fireHold_%1", _x];
    _system setVariable [_holdKey, _hold, false];
} forEach _turretPaths;

private _msg = format ["[AEGIS-M] DEBUG FIRE HOLD: %1 turret(s) %2 on %3 -- %4.", count _turretPaths, _turretPaths, _system, ["RELEASED", "HELD"] select _hold];
hint _msg;
diag_log text _msg;
