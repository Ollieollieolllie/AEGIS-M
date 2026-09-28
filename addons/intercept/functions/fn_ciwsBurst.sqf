/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsBurst

Description:
    Holds a CIWS gun's trigger for one sustained burst. Every frame the
    weapon has cycled (weaponState roundReloadPhase back to 0) and the
    turret is on its aim point, it fires again, so the gun runs at its own
    config rate of fire (reloadTime) for the whole burst.

    Why: BIS_fnc_fire is ONE trigger pull in the turret's currently selected
    fire mode. A Cheetah gunner's selected mode is its player mode "manual"
    (burst = 2), so one call per engagement tick gave 2-round pops about a
    second apart instead of sustained fire.

    Fires only while the latest aim record (aegism_intercept_fnc_aimWeapon,
    refreshed every CIWS engagement tick) is for THIS target, fresh, and
    within tolerance: a turret that falls off the lead point mid-burst holds
    fire until it's back on. It also holds fire while the barrel itself
    (weaponDirection, world space) is below doctrine ciwsMinElevation, so a
    target dipping low mid-burst never pulls rounds into the ground or
    friendly positions; the time held is reported in BURST-END.
    The burst ends at its deadline -- which the
    engagement loop pulls in if the target changes or LOS is lost -- or when
    the target dies, ammo runs out, or the aim record goes stale (the
    engagement was released).

    Per-turret state on the System, "AEGISM_ciwsBurst_<turretPath>":
    [endsAt, target, burstId]. endsAt is the planned deadline while the
    burst runs and is rewritten to the actual end time when it stops, so
    the engagement loop's pause between bursts counts from it. burstId makes
    each handler exit as soon as a newer burst owns the turret -- without
    it, a new burst started in the frame between the old one's deadline and
    its own exit check re-extended the old handler, and several ran at once.

Parameters:
    _system - the firing System vehicle <OBJECT>
    _target - the target object <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _duration - burst length, seconds <NUMBER>

Returns:
    Nothing

Examples:
    [_cheetah, _rocket, _weaponInfo, 4] call aegism_intercept_fnc_ciwsBurst;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_AIM_STALE 0.5

params ["_system", "_target", "_weaponInfo", "_duration"];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

private _burstKey = format ["AEGISM_ciwsBurst_%1", _turretPath];
private _burstId = (_system getVariable ["AEGISM_ciwsBurstSeq", 0]) + 1;
_system setVariable ["AEGISM_ciwsBurstSeq", _burstId, false];
_system setVariable [_burstKey, [time + _duration, _target, _burstId], false];

private _engagementSettings = _system getVariable "AEGISM_resolvedEngagementSettings";
if (isNil "_engagementSettings") then { _engagementSettings = [_system] call aegism_system_fnc_resolveEngagementSettings; };
private _minElevation = _engagementSettings getOrDefault ["ciwsMinElevation", 5];

// Captured now: a munition target is usually gone (objNull) by the time the
// burst ends.
private _targetDesc = format ["%1 (%2)", _target, typeOf _target];

[{
    params ["_args", "_pfhHandle"];
    _args params ["_system", "_target", "_turretPath", "_weaponClass", "_magazineClass", "_burstKey", "_startedAt", "_ammoAtStart", "_minElevation", "_elevationHeld", "_burstId", "_targetDesc"];

    (_system getVariable [_burstKey, [-1, objNull, 0]]) params ["_endsAt", "", "_currentId"];
    (_system getVariable ["AEGISM_aim_ciws", []]) params [["_angle", 180], ["_tolerance", 0], ["_aimAt", -1e9], ["_aimTarget", objNull]];
    private _ammo = if (alive _system) then { _system magazineTurretAmmo [_magazineClass, _turretPath] } else { 0 };
    private _superseded = _currentId != _burstId;

    if (_superseded || {!alive _system} || {!alive _target} || {_ammo <= 0} || {time >= _endsAt} || {time - _aimAt > AEGISM_AIM_STALE}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        if (isNull _system) exitWith {};
        // Record the actual end time (the pause counts from it) -- only if
        // no newer burst owns the turret.
        if (!_superseded) then { _system setVariable [_burstKey, [time min _endsAt, _target, _burstId], false]; };
        diag_log text format ["[AEGIS-M] BURST-END: %1 fired %2 round(s) of %3 at %4 in %5s%6.", _system, (_ammoAtStart - _ammo) max 0, _weaponClass, _targetDesc, round ((time - _startedAt) * 10) / 10,
            ["", format [" (held %1s: barrel below the %2 deg CIWS minimum elevation)", round (_elevationHeld * 10) / 10, _minElevation]] select (_elevationHeld > 0)];
    };

    if (_aimTarget != _target || {_angle > _tolerance}) exitWith {};

    private _barrelElevation = asin ((((_system weaponDirection _weaponClass) select 2) max -1) min 1);
    if (_barrelElevation < _minElevation) exitWith {
        _args set [9, _elevationHeld + diag_deltaTime];
    };

    if (((weaponState [_system, _turretPath, _weaponClass]) param [5, 0]) == 0) then {
        [_system, _weaponClass, _turretPath] call BIS_fnc_fire;
    };
}, 0, [_system, _target, _turretPath, _weaponClass, _magazineClass, _burstKey, time, _system magazineTurretAmmo [_magazineClass, _turretPath], _minElevation, 0, _burstId, _targetDesc]] call CBA_fnc_addPerFrameHandler;
