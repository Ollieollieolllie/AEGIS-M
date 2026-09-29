/* ----------------------------------------------------------------------------
Function: aegism_fnc_setWeaponAiSuppressed

Description:
    Enables or disables a specific turret's own crewman's independent AI
    targeting/engagement (disableAI "TARGET"/"AUTOTARGET"), so that turret's
    weapon only ever fires when AEGIS-M's own aegism_intercept_fnc_fireWeapon
    commands it via BIS_fnc_fire -- a real fire-control gate, not just AEGIS-M
    picking targets in parallel with a crew that can ALSO independently
    decide to shoot on its own. Without this, a launcher/CIWS turret's crew
    can engage a target the moment they spot it themselves, completely
    outside AEGIS-M's own assignment/ammo/reaction-time/cooldown/LOS/
    reliability gates -- which is indistinguishable, from the outside, from
    AEGIS-M "not preventing" a shot it never actually decided to take.

    "AUTOTARGET" stops independent target ACQUISITION (the AI won't scan
    for/acquire a new target on its own); "TARGET" stops independent
    ENGAGEMENT/reaction to an already-known target (the AI won't fire or
    maneuver to fire even at something it's aware of). Both are disabled
    together since the goal is to prevent ANY self-initiated fire, not just
    self-initiated target discovery -- BIS_fnc_fire and lockCameraTo (AEGIS-M's
    own aim/fire commands) are separate scripted command paths that keep
    working on a unit with these AI subsystems disabled.

    Scoped to ONE turret's crewman (via turretUnit), not the whole vehicle
    -- a Tigris/ZSU-style vehicle's coax MG or a multi-turret vehicle's other
    stations are untouched; only the specific turret(s) AEGIS-M discovered
    as a launcher/CIWS weapon should ever be suppressed.

    disableAI's disabled state is tied to the UNIT object, not the turret/
    vehicle context (confirmed against BIKI) -- it follows that crewman if
    they change seats or eject, and is NOT automatically cleared by vehicle
    destruction. It's restored only when a vehicle is unsynced from a Site
    and isn't a System in its own right (aegism_network_fnc_moduleInit); a
    destroyed System's crew stays suppressed.

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
        } else {
            _gunner enableAI "TARGET";
            _gunner enableAI "AUTOTARGET";
        };
    };
} forEach _turretPaths;
