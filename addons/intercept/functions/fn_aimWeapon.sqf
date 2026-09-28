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

    Alignment:
        ciws - barrel within AEGISM_AIM_ON_TARGET degrees of the aim point.
        launcher - barrel within AEGISM_AIM_ON_TARGET degrees, OR the turret
            has stopped closing on the aim point (the angle hasn't shrunk for
            AEGISM_AIM_SETTLE_TICKS checks in a row: it's at its elevation
            limit, or trailing a fast-moving lead point) -- either way only
            inside the missile's own lock cone (CfgAmmo missileLockCone, no
            limit if the ammo doesn't set one), so it never fires at
            something its seeker can't take. It used to be a flat 20 degrees,
            which a turret still slewing passed on its way past: missiles
            left the rail well off the aim point and turned hard after.
    Barrel direction: aegism_intercept_fnc_barrelDirection.

    Shared turrets: a vehicle whose launcher and gun sit on the same turret
    (e.g. the Cheetah) would have both engagement loops issuing competing
    aim orders. The CIWS loop owns the turret while it is actively aiming; a
    launcher on the same turret skips its own lock for AEGISM_CIWS_AIM_
    OWNERSHIP seconds and only checks alignment.

    Records [angle, tolerance, time, target, feasible] as "AEGISM_aim_<role>"
    on the System for aegism_fnc_debugDraw, aegism_intercept_fnc_fireWeapon
    (the launch angle in its FIRE line) and aegism_intercept_fnc_ciwsBurst
    (which only fires while this is fresh, on its target, feasible and in
    tolerance). Per turret, "AEGISM_aimTrend_<turretPath>" [angle, target,
    ticks not closing] tracks whether a launcher's turret is still closing.

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

#define AEGISM_AIM_ON_TARGET 2
#define AEGISM_AIM_SETTLE_TICKS 2
#define AEGISM_CIWS_AIM_OWNERSHIP 0.5

params ["_system", "_target", "_weaponInfo", "_role"];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

private _isCiws = _role == "ciws";
private _tolerance = AEGISM_AIM_ON_TARGET;

// The intercept is solved from the MUZZLE, and the camera lockCameraTo
// points is aimed at the aim point shifted by (camera - muzzle), so the
// parallel barrel line passes through the aim point itself (see
// aegism_intercept_fnc_turretPoints: this offset put CIWS rounds about a
// metre low).
([_system, _turretPath, _role] call aegism_intercept_fnc_turretPoints) params ["_origin", "_camera"];

([_system, _origin, _target, _weaponInfo, _role] call aegism_intercept_fnc_computeLeadPoint) params ["_aimPoint", "_feasible"];

private _ownerKey = format ["AEGISM_ciwsAimAt_%1", _turretPath];
if (_isCiws) then { _system setVariable [_ownerKey, time, false]; };
if (_isCiws || {time - (_system getVariable [_ownerKey, -1e9]) > AEGISM_CIWS_AIM_OWNERSHIP}) then {
    [_system, _turretPath, _aimPoint vectorAdd (_camera vectorDiff _origin)] call aegism_intercept_fnc_lockTurret;
    _system setVariable [format ["AEGISM_turretLockAt_%1", _turretPath], time, false];
};

private _barrel = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection;
// Clamped: float error can push vectorCos fractionally past 1, and acos of
// that is undefined.
private _angle = acos (((_barrel vectorCos (_origin vectorFromTo _aimPoint)) min 1) max -1);

_system setVariable [format ["AEGISM_aim_%1", _role], [_angle, _tolerance, time, _target, _feasible], false];

private _aligned = _feasible && {_angle <= _tolerance};
if (!_isCiws) then {
    private _trendKey = format ["AEGISM_aimTrend_%1", _turretPath];
    (_system getVariable [_trendKey, [1e9, objNull, 0]]) params ["_lastAngle", "_lastTarget", "_notClosing"];
    _notClosing = if (_lastTarget == _target && {_angle >= _lastAngle}) then { _notClosing + 1 } else { 0 };
    _system setVariable [_trendKey, [_angle, _target, _notClosing], false];

    private _lockCone = getNumber (configFile >> "CfgAmmo" >> getText (configFile >> "CfgMagazines" >> _magazineClass >> "ammo") >> "missileLockCone");
    if (_lockCone <= 0) then { _lockCone = 180; };
    _aligned = _feasible && {_angle <= _lockCone} && {_angle <= _tolerance || {_notClosing >= AEGISM_AIM_SETTLE_TICKS}};
};

[_aligned, _angle, _tolerance, _aimPoint, _feasible]
