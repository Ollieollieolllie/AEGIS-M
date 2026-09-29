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
        ciws - a round fired now would pass close enough to hit: the barrel's
            error at the intercept (angle x intercept distance) within the
            target's own half-size (its bounding box, aegism_intercept_fnc_
            targetHitRadius) plus the gun's own spread there (the current
            fire mode's CfgWeapons dispersion x distance). For a Phalanx
            (dispersion 0.0045) at a 155mm shell 2km out that's ~0.3 degrees;
            it used to be a flat 2 degrees -- ~70m of error at 2km, far wider
            than any target.
            LAST-DITCH: once the target is due to impact within the gun's
            own longest burst (doctrine ciwsBurstMax), it also fires as soon
            as the turret has settled -- stopped closing on the aim point for
            AEGISM_AIM_SETTLE_TICKS engagement ticks -- wherever that is:
            there is no later, better shot, and holding fire guarantees the
            round lands. (A Praetorian followed a shell to the ground 0.3
            degrees off a 0.28-degree gate.) Logged once per target
            (LAST-DITCH).
        An unguided munition's path is projected on gravity alone -- exact
        for artillery (no drag), and the same projection aegism_intercept_
        fnc_canEngage judges reach with, so the two can't disagree.
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

    CIWS aim carries the gun's own spotting correction ("AEGISM_ciws
    Correction_<turretPath>", [lead time s, elevation rad], aegism_intercept_
    fnc_ciwsSpot): its fired rounds are measured as they pass the track the
    target was PREDICTED to fly, and the systematic miss is fed back into the
    aim. The prediction each shot uses is recorded as "AEGISM_ciwsTrack_
    <turretPath>" [time, position, velocity, acceleration] for aegism_
    intercept_fnc_onSystemFired to hand each round.

    Shared turrets: a vehicle whose launcher and gun sit on the same turret
    (e.g. the Cheetah) would have both engagement loops issuing competing
    aim orders. The CIWS loop owns the turret while it is actively aiming; a
    launcher on the same turret skips its own lock for AEGISM_CIWS_AIM_
    OWNERSHIP seconds and only checks alignment.

    Records [angle, tolerance, time, target, feasible, aligned] as "AEGISM_aim_<role>"
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
// Engagement loop tick (modules_system moduleInit): a CIWS is re-aimed every
// frame, so "settled" is measured over this many seconds per settle tick.
#define AEGISM_ENGAGEMENT_TICK 0.1

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

// CIWS spotting correction (aegism_intercept_fnc_ciwsSpot): lead time added
// to the target's projection, and an elevation angle applied square to the
// line of sight -- what this gun's own rounds say it needs.
(_system getVariable [format ["AEGISM_ciwsCorrection_%1", _turretPath], [0, 0]]) params ["_leadCorrection", "_elevationCorrection"];
if (!_isCiws) then { _leadCorrection = 0; _elevationCorrection = 0; };

private _targetClass = [_target] call aegism_detect_fnc_classifyTarget;
private _ballistic = _isCiws && {_targetClass in ["artilleryShell", "rocket", "bomb"]};
([_system, _origin, _target, _weaponInfo, _role, !_ballistic, 0, _ballistic, _leadCorrection] call aegism_intercept_fnc_computeLeadPoint) params ["_aimPoint", "_feasible", "", "_interceptDistance", "_track"];
if (_isCiws) then { _system setVariable [format ["AEGISM_ciwsTrack_%1", _turretPath], [time] + _track, false]; };

if (_elevationCorrection != 0) then {
    private _los = _origin vectorFromTo _aimPoint;
    private _up = vectorNormalized ([0, 0, 1] vectorDiff (_los vectorMultiply (_los select 2)));
    _aimPoint = _aimPoint vectorAdd (_up vectorMultiply (_elevationCorrection * _interceptDistance));
};

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

if (_isCiws && {_interceptDistance > 0}) then {
    // Current fire mode: weaponState reports a weapon with no modes[] of its
    // own under its own class name, which isn't a sub-class.
    private _weaponCfg = configFile >> "CfgWeapons" >> _weaponClass;
    private _modeCfg = _weaponCfg >> ((weaponState [_system, _turretPath, _weaponClass]) param [2, ""]);
    if (!isClass _modeCfg) then { _modeCfg = _weaponCfg; };
    private _dispersion = getNumber (_modeCfg >> "dispersion");
    _tolerance = deg (_dispersion + ([_target] call aegism_intercept_fnc_targetHitRadius) / _interceptDistance);
};

private _aligned = _feasible && {_angle <= _tolerance};
if (_isCiws) then {
    // Settled: the angle hasn't set a new best for AEGISM_AIM_SETTLE_TICKS
    // engagement ticks -- the turret is as close as it's going to get.
    private _settleKey = format ["AEGISM_aimSettle_%1", _turretPath];
    (_system getVariable [_settleKey, [objNull, 1e9, time]]) params ["_settleTarget", "_bestAngle", "_improvedAt"];
    if (_settleTarget != _target || {_angle < _bestAngle}) then { _settleTarget = _target; _bestAngle = _angle; _improvedAt = time; };
    _system setVariable [_settleKey, [_settleTarget, _bestAngle, _improvedAt], false];

    if (_feasible && {!_aligned} && {time - _improvedAt >= AEGISM_AIM_SETTLE_TICKS * AEGISM_ENGAGEMENT_TICK}) then {
        private _settings = _system getVariable "AEGISM_resolvedEngagementSettings";
        if (isNil "_settings") then { _settings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
        private _timeToImpact = [_target, _targetClass, [getPosASL _system]] call aegism_intercept_fnc_timeToImpact;
        if (_timeToImpact <= (_settings getOrDefault ["ciwsBurstMax", 5])) then {
            _aligned = true;
            private _loggedKey = format ["AEGISM_lastDitchLogged_%1", _turretPath];
            if ((_system getVariable [_loggedKey, objNull]) != _target) then {
                _system setVariable [_loggedKey, _target, false];
                diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " LAST-DITCH: %1 (ciws) on %2 -- impact in %3s, turret settled %4 deg off the aim point (gate %5): firing anyway.",
                    _system, _target, round (_timeToImpact * 10) / 10, round (_angle * 100) / 100, round (_tolerance * 100) / 100];
            };
        };
    };
};
if (!_isCiws) then {
    private _trendKey = format ["AEGISM_aimTrend_%1", _turretPath];
    (_system getVariable [_trendKey, [1e9, objNull, 0]]) params ["_lastAngle", "_lastTarget", "_notClosing"];
    _notClosing = if (_lastTarget == _target && {_angle >= _lastAngle}) then { _notClosing + 1 } else { 0 };
    _system setVariable [_trendKey, [_angle, _target, _notClosing], false];

    private _lockCone = getNumber (configFile >> "CfgAmmo" >> getText (configFile >> "CfgMagazines" >> _magazineClass >> "ammo") >> "missileLockCone");
    if (_lockCone <= 0) then { _lockCone = 180; };
    _aligned = _feasible && {_angle <= _lockCone} && {_angle <= _tolerance || {_notClosing >= AEGISM_AIM_SETTLE_TICKS}};
};

_system setVariable [format ["AEGISM_aim_%1", _role], [_angle, _tolerance, time, _target, _feasible, _aligned], false];

[_aligned, _angle, _tolerance, _aimPoint, _feasible]
