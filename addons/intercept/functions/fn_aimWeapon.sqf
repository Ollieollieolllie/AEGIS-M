/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_aimWeapon

Description:
    Slews one System weapon's turret toward its aim point (lockCameraTo on
    that turret, see aegism_intercept_fnc_lockTurret) and reports whether
    the barrel is currently aligned closely enough to fire. Each lock stamps
    "AEGISM_turretLockAt_<turretPath>"; aegism_intercept_fnc_engagementLoop
    hands the turret back to its crew once that goes stale.
    Called every engagement tick from the moment a target is assigned --
    including during the crew reaction window -- so the turret is already on
    target when the crew is ready, instead of only starting to traverse
    after the reaction timer.

    Aim point:
        launcher - the target's current position (a guided round corrects
            itself after launch; the missile is also handed the target via
            setMissileTarget, see aegism_intercept_fnc_fireWeapon)
        ciws - a computed lead point (aegism_intercept_fnc_computeLeadPoint);
            an unguided round goes exactly where the barrel points

    Tolerances: AEGISM_AIM_TOLERANCE_LAUNCHER 20 degrees (ACE3's own tuned
    missile-defense launch angle), AEGISM_AIM_TOLERANCE_CIWS 2 degrees.
    There is deliberately no elevation floor: the angle check already
    requires the barrel to point at a target the LOS check can see, and the
    turret's own config elevation limits physically stop it pointing
    anywhere it can't. (The old elevation check decomposed the barrel
    direction in HULL model space, producing values like 165 degrees for a
    turret traversed rearward, so it passed or blocked shots at random.)

    Shared turrets: a vehicle whose launcher and gun sit on the same turret
    (e.g. the Cheetah) would have both engagement loops issuing competing
    aim orders. The CIWS loop, which needs the precise lead point, owns
    the turret while it is actively aiming; a launcher on the same turret
    skips its own lock for AEGISM_CIWS_AIM_OWNERSHIP seconds and just
    checks alignment against the (nearby) raw target position.

    Records [angle, tolerance, time, target] as "AEGISM_aim_<role>" on the
    System for aegism_fnc_debugDraw and aegism_intercept_fnc_ciwsBurst
    (which only fires while this is fresh, on its target, and in tolerance).

Parameters:
    _system - the firing System vehicle <OBJECT>
    _target - the target object <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _role - "launcher" or "ciws" <STRING>

Returns:
    [aligned <BOOLEAN>, angle <NUMBER>, tolerance <NUMBER>, aimPoint <ARRAY, ASL>]

Examples:
    [_cheetah, _heli, _weaponInfo, "ciws"] call aegism_intercept_fnc_aimWeapon;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_AIM_TOLERANCE_LAUNCHER 20
#define AEGISM_AIM_TOLERANCE_CIWS 2
#define AEGISM_CIWS_AIM_OWNERSHIP 0.5

params ["_system", "_target", "_weaponInfo", "_role"];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

private _isCiws = _role == "ciws";
private _tolerance = [AEGISM_AIM_TOLERANCE_LAUNCHER, AEGISM_AIM_TOLERANCE_CIWS] select _isCiws;

// Measured from the turret's own crewman (close to the weapon) rather than
// the vehicle origin, which can be metres away on a large vehicle.
private _gunner = _system turretUnit _turretPath;
private _origin = if (isNull _gunner) then { getPosASLVisual _system } else { eyePos _gunner };

private _aimPoint = if (_isCiws) then {
    [_system, _origin, _target, _weaponClass, _magazineClass] call aegism_intercept_fnc_computeLeadPoint
} else {
    getPosASLVisual _target
};

private _ownerKey = format ["AEGISM_ciwsAimAt_%1", _turretPath];
if (_isCiws) then { _system setVariable [_ownerKey, time, false]; };
if (_isCiws || {time - (_system getVariable [_ownerKey, -1e9]) > AEGISM_CIWS_AIM_OWNERSHIP}) then {
    [_system, _turretPath, _aimPoint] call aegism_intercept_fnc_lockTurret;
    _system setVariable [format ["AEGISM_turretLockAt_%1", _turretPath], time, false];
};

private _turretDirection = _system weaponDirection _weaponClass;
// Clamped: float error can push vectorCos fractionally past 1, and acos of
// that is undefined.
private _cos = ((_turretDirection vectorCos (_origin vectorFromTo _aimPoint)) min 1) max -1;
private _angle = acos _cos;

_system setVariable [format ["AEGISM_aim_%1", _role], [_angle, _tolerance, time, _target], false];

[_angle <= _tolerance, _angle, _tolerance, _aimPoint]
