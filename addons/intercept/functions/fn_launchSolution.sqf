/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_launchSolution

Description:
    How one launcher gets a missile onto one target, from what the launcher
    and the missile can actually do.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the launcher vehicle <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _target - the target <OBJECT>
    _origin - ASL position the missile leaves from <ARRAY>
    _considerNow - also consider launching as the barrel points now <BOOLEAN>
    _withSlew - count the turret's swing <BOOLEAN>
    _useAcceleration - sample the target's acceleration (the engagement
        loop's own solve only) <BOOLEAN>
    _delay - optional, seconds from now the shot leaves (planning) <NUMBER>
    _ballistic - optional, project the target on gravity alone <BOOLEAN>
    _timeToImpact - optional, seconds until an incoming munition comes down
        (aegism_intercept_fnc_timeToImpact); 1e10 for anything else <NUMBER>

Returns:
    [feasible <BOOLEAN>, reason if not <STRING>, way ("onBore", "slew",
     "now", "fixed") <STRING>, launch direction (world) <ARRAY>, flight time s
     <NUMBER>, swing time s <NUMBER>, off-bore angle deg <NUMBER>, turn time
     s <NUMBER>, calibrated (false: off-bore on an unknown turn rate)
     <BOOLEAN>, intercept point ASL <ARRAY>, intercept distance m <NUMBER>,
     where the turn ends ASL <ARRAY>, straight intercept direction <ARRAY>,
     the off-bore limit for the way it launches, deg <NUMBER>, the closest direction the turret can
     reach -- where it should keep swinging, whichever way wins <ARRAY>] <ARRAY>

Examples:
    [_vls, _weaponInfo, _rocket, _origin, true, true, true] call aegism_intercept_fnc_launchSolution;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Off by no more than this, a launch is straight: aegism_intercept_fnc_
// aimWeapon's own on-target tolerance.
#define AEGISM_LAUNCH_ON_BORE 2

params ["_system", "_weaponInfo", "_target", "_origin", "_considerNow", "_withSlew", "_useAcceleration", ["_delay", 0], ["_ballistic", false], ["_timeToImpact", 1e10]];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

([_system, _origin, _target, _weaponInfo, "launcher", _useAcceleration, _delay, _ballistic] call aegism_intercept_fnc_computeLeadPoint)
    params ["_aimPoint", "_feasible", "_tof", "_interceptDistance", "", "_interceptPoint"];
if (!_feasible) exitWith {
    [false, format ["missile cannot catch it (%1m, receding faster than it closes, or beyond its reach)", round (_origin distance _target)], "", [], -1, 0, 0, 0, true, _interceptPoint, _interceptDistance, _origin, [], 0, []]
};
private _leadDir = _origin vectorFromTo _aimPoint;

private _ammoClass = ([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 0;
([_ammoClass] call aegism_intercept_fnc_missileAgility) params ["_guidance", "_turnRate", "_rateSource", "_cone"];

// One way to launch, along _dir after _slew s: [feasible, reason, way, dir,
// flight time, swing, off-bore, turn time, calibrated, intercept point,
// intercept distance, turn end].
private _fnWay = {
    params ["_way", "_dir", "_slew"];
    private _offBore = acos (((_dir vectorCos _leadDir) min 1) max -1);
    if (_offBore <= AEGISM_LAUNCH_ON_BORE) exitWith {
        [true, "", [_way, "onBore"] select (_way == "slew"), _dir, _tof, _slew, _offBore, 0, true, _interceptPoint, _interceptDistance, _origin]
    };
    ([_way] call _fnCone) params ["_wayCone", "_coneSource"];
    if (_offBore > _wayCone) exitWith {
        [false, format ["intercept %1 deg off the launch direction, beyond %2", round _offBore, _coneSource], _way, _dir, -1, _slew, _offBore, 0, true, _interceptPoint, _interceptDistance, _origin]
    };
    if (_turnRate <= 0) exitWith {
        [true, "", _way, _dir, _tof, _slew, _offBore, 0, false, _interceptPoint, _interceptDistance, _origin]
    };
    // The target projected as the straight solve projected it: with its
    // acceleration where that sampled it (a second solve in the same tick
    // reuses the sample). Without, a falling rocket's off-bore meeting came
    // out up to 1 s of flight later than the missile then took, and beyond
    // the launcher's reach when it was inside.
    ([_system, _origin, _target, _weaponInfo, "launcher", _useAcceleration, _delay + _slew, _ballistic, 0, _dir, _turnRate] call aegism_intercept_fnc_computeLeadPoint)
        params ["", "_turnFeasible", "_turnTof", "_turnDistance", "", "_turnIntercept", "_turn"];
    if (!_turnFeasible) exitWith {
        [false, format ["too close to turn onto: %1 deg off the launch direction at %2 deg/s (%3)", round _offBore, _turnRate, _rateSource], _way, _dir, -1, _slew, _offBore, 0, true, _interceptPoint, _interceptDistance, _origin]
    };
    [true, "", _way, _dir, _turnTof, _slew, _offBore, _turn select 1, true, _turnIntercept, _turnDistance, _turn select 2]
};

// Slew: the closest direction the turret can reach. On an axis the mount
// can't move (aegism_intercept_fnc_turretConfig), where the barrel actually
// points is the truth, not the config's limits: a vertical launch cell's
// turret config needn't say it's vertical.
private _mount = ([_system, _turretPath] call aegism_intercept_fnc_turretConfig) select 10;

// How far off-bore it may launch, one way: [degrees, what limits it]. The
// missile's own post-launch cone, and, for a launcher that can move, the
// doctrine limit for the way it launches (see notes): "slew" -- the turret
// as close as it can get, at its limit -- Max Off-Bore Launch At Turret
// Limit; firing "now", while it swings, or with it trailing a target it's
// still swinging after ("onBore"), Max Off-Bore Launch While Swinging. A
// fixed mount can't do otherwise, so only the missile limits it.
private _settings = _system getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_settings") then { _settings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
private _fnCone = {
    params ["_way"];
    if (_mount == "fixed") exitWith { [_cone, format ["the missile's %1 deg post-launch cone", round _cone]] };
    private _atLimit = _way == "slew";
    private _limit = _settings getOrDefault [["maxOffBoreSwing", "maxOffBoreLimit"] select _atLimit, [20, 30] select _atLimit];
    if (_limit >= _cone) exitWith { [_cone, format ["the missile's %1 deg post-launch cone", round _cone]] };
    [_limit, format ["the launcher's %1 deg Max Off-Bore Launch %2", round _limit, ["While Swinging", "At Turret Limit"] select _atLimit]]
};

private _reach = ([_system, _turretPath, _leadDir] call aegism_intercept_fnc_turretCanPoint) select 4;
if (_mount != "trainable") then {
    private _barrel = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection;
    if (_barrel isNotEqualTo [0, 0, 0]) then {
        private _fnAngles = {
            private _local = vectorNormalized (_system vectorWorldToModelVisual _this);
            [(_local select 0) atan2 (_local select 1), asin (((_local select 2) max -1) min 1)]
        };
        (_reach call _fnAngles) params ["_azimuth", "_elevation"];
        (_barrel call _fnAngles) params ["_barrelAzimuth", "_barrelElevation"];
        if (_mount in ["fixed", "elevating"]) then { _azimuth = _barrelAzimuth; };
        if (_mount in ["fixed", "traversing"]) then { _elevation = _barrelElevation; };
        _reach = _system vectorModelToWorldVisual [(sin _azimuth) * (cos _elevation), (cos _azimuth) * (cos _elevation), sin _elevation];
    };
};
private _slewTime = if (_withSlew && {_mount != "fixed"}) then { [_system, _turretPath, _weaponClass, _reach] call aegism_intercept_fnc_turretSlewTime } else { 0 };
private _best = [["slew", "fixed"] select (_mount == "fixed"), _reach, _slewTime] call _fnWay;

// Now: along the barrel as it points, before the turret is round -- only to
// make an intercept it otherwise couldn't: swinging first has no solution,
// or would get the missile there after the target comes down. With time in
// hand (the start of an engagement) the turret swings fully first. Needs
// the missile's turn known (see notes).
if (_considerNow && {_slewTime > 0} && {_turnRate > 0} && {!(_best select 0) || {(_best select 5) + (_best select 4) >= _timeToImpact}}) then {
    private _barrel = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection;
    if (_barrel isNotEqualTo [0, 0, 0]) then {
        private _now = ["now", _barrel, 0] call _fnWay;
        if ((_now select 0) && {(_now select 4) < _timeToImpact}) then { _best = _now; };
    };
};

_best + [_leadDir, ([_best select 2] call _fnCone) select 0, _reach]
