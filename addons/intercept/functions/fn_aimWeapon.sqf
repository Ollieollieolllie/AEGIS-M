/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_aimWeapon

Description:
    Slews one System weapon's turret toward its intercept point (lockCameraTo
    on that turret, see aegism_intercept_fnc_lockTurret) and reports whether
    the barrel is currently aligned closely enough to fire. Each lock stamps
    "AEGISM_turretLockAt_<turretPath>"; aegism_intercept_fnc_engagementLoop
    hands the turret back to its crew once that goes stale.
    Called every engagement tick from the moment a target is assigned --
    including during the crew reaction window -- so the turret is already on
    target when the crew is ready, instead of only starting to traverse
    after the reaction timer.

    Aim point (aegism_intercept_fnc_computeLeadPoint) for both roles:
        ciws - where the unguided round meets the target, raised for drop
        launcher - where the missile (from its real speed profile) meets
            the target. Launchers used to point at the target's current
            position, so every missile left the rail and immediately turned
            hard toward the real intercept point.
    When there is no feasible intercept (the target is receding faster than
    the round can close, or the meeting point is beyond the weapon's reach)
    the turret tracks the target itself and the weapon is not aligned.

    Tolerances: AEGISM_AIM_TOLERANCE_LAUNCHER 20 degrees (ACE3's own tuned
    missile-defense launch angle), AEGISM_AIM_TOLERANCE_CIWS 2 degrees.
    Barrel direction: aegism_intercept_fnc_barrelDirection.

    Shared turrets: a vehicle whose launcher and gun sit on the same turret
    (e.g. the Cheetah) would have both engagement loops issuing competing
    aim orders. The CIWS loop owns the turret while it is actively aiming; a
    launcher on the same turret skips its own lock for AEGISM_CIWS_AIM_
    OWNERSHIP seconds and only checks alignment.

    Records [angle, tolerance, time, target, feasible] as "AEGISM_aim_<role>"
    on the System for aegism_fnc_debugDraw and aegism_intercept_fnc_ciwsBurst
    (which only fires while this is fresh, on its target, feasible and in
    tolerance).

Parameters:
    _system - the firing System vehicle <OBJECT>
    _target - the target object <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _role - "launcher" or "ciws" <STRING>

Returns:
    [aligned <BOOLEAN>, angle <NUMBER>, tolerance <NUMBER>, aimPoint <ARRAY, ASL>,
     feasible <BOOLEAN>]

Examples:
    [_cheetah, _heli, _weaponInfo, "ciws"] call aegism_intercept_fnc_aimWeapon;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_AIM_TOLERANCE_LAUNCHER 20
#define AEGISM_AIM_TOLERANCE_CIWS 2
#define AEGISM_CIWS_AIM_OWNERSHIP 0.5

params ["_system", "_target", "_weaponInfo", "_role"];
_weaponInfo params ["_turretPath", "_weaponClass"];

private _isCiws = _role == "ciws";
private _tolerance = [AEGISM_AIM_TOLERANCE_LAUNCHER, AEGISM_AIM_TOLERANCE_CIWS] select _isCiws;

// Measured from the turret's own crewman (close to the weapon) rather than
// the vehicle origin, which can be metres away on a large vehicle.
private _gunner = _system turretUnit _turretPath;
private _origin = if (isNull _gunner) then { getPosASLVisual _system } else { eyePos _gunner };

([_system, _origin, _target, _weaponInfo, _role] call aegism_intercept_fnc_computeLeadPoint) params ["_aimPoint", "_feasible"];

private _ownerKey = format ["AEGISM_ciwsAimAt_%1", _turretPath];
if (_isCiws) then { _system setVariable [_ownerKey, time, false]; };
if (_isCiws || {time - (_system getVariable [_ownerKey, -1e9]) > AEGISM_CIWS_AIM_OWNERSHIP}) then {
    [_system, _turretPath, _aimPoint] call aegism_intercept_fnc_lockTurret;
    _system setVariable [format ["AEGISM_turretLockAt_%1", _turretPath], time, false];
};

private _barrel = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection;
// Clamped: float error can push vectorCos fractionally past 1, and acos of
// that is undefined.
private _angle = acos (((_barrel vectorCos (_origin vectorFromTo _aimPoint)) min 1) max -1);

_system setVariable [format ["AEGISM_aim_%1", _role], [_angle, _tolerance, time, _target, _feasible], false];

[_feasible && {_angle <= _tolerance}, _angle, _tolerance, _aimPoint, _feasible]
