/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_fireWeapon

Description:
    Fires a System's own real weapon: one missile for a launcher, or opens
    one sustained burst for a CIWS gun (aegism_intercept_fnc_ciwsBurst, at
    the gun's own rate of fire). AEGIS-M never spawns projectiles:
    ballistics, guidance and damage are the game's own.

    The caller (aegism_intercept_fnc_engagementLoop) has already aimed the
    turret and confirmed alignment via aegism_intercept_fnc_aimWeapon; this
    function only rolls crew reliability and fires, via BIS_fnc_fire (a
    real single fire command -- fireAtTarget hands the decision to AI
    judgement and was observed firing several missiles per call).

    Crew reliability is rolled here, once per missile or per CIWS burst. A
    failed roll returns 0, which the engagement loop treats as a lost fire
    cycle (it waits one shot interval / burst pause before trying again).

    Before firing it writes a capture context for this weapon ("AEGISM_
    capture_<weapon>") and makes sure the vehicle has AEGIS-M's persistent
    Fired handler; aegism_intercept_fnc_onSystemFired then hands a launched
    missile its target (setMissileTarget), records it as an in-flight
    interceptor, and starts its proximity fuse.

    Third-party scripted missile guidance: if that mod is loaded and the
    ammo declares its guidance class explicitly with enabled=1, the target
    is written to the variable its own Fired handler reads, on both the
    turret's gunner and the vehicle. That mod's own AI-guidance setting must
    still allow AI shots for it to take effect.

Parameters:
    _system - the firing System vehicle <OBJECT>
    _target - the target object <OBJECT>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _reliability - crew reliability 0-1, from aegism_intercept_fnc_
        applyCrewModulation <NUMBER>
    _role - "launcher" or "ciws" <STRING>
    _interceptors - the assignment's in-flight interceptor list; a fired
        missile is appended to it (by reference) <ARRAY>
    _burstDuration - CIWS only: sustained burst length, seconds <NUMBER>

Returns:
    1 fired, 0 crew hesitated (reliability roll failed), -1 could not fire
    (hold, dead target, no ammo) <NUMBER>

Examples:
    [_samSite, _heli, _weaponInfo, 0.85, "launcher", _interceptors] call aegism_intercept_fnc_fireWeapon;
    [_cheetah, _rocket, _weaponInfo, 0.85, "ciws", _interceptors, 4] call aegism_intercept_fnc_fireWeapon;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_target", "_weaponInfo", "_reliability", "_role", ["_interceptors", []], ["_burstDuration", 0]];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

private _isCiws = _role == "ciws";

// Debug circuit breaker (aegism_intercept_fnc_debugSetFireHold): the single
// choke point every AEGIS-M fire command passes through.
if (_system getVariable [format ["AEGISM_fireHold_%1", _turretPath], false]) exitWith { -1 };
if (isNull _target || {!alive _target}) exitWith { -1 };

private _ammoBefore = _system magazineTurretAmmo [_magazineClass, _turretPath];
if (_ammoBefore <= 0) exitWith { -1 };

if (random 1 > _reliability) exitWith {
    diag_log text format ["[AEGIS-M] FIRE-SKIP: %1 (%2) at %3 -- crew reliability roll failed (reliability=%4), losing this fire cycle.", _system, _role, _target, _reliability];
    0
};

private _ammoClassName = getText (configFile >> "CfgMagazines" >> _magazineClass >> "ammo");
private _gunner = _system turretUnit _turretPath;

if (!isNil "ace_missileguidance_fnc_onFired") then {
    private _guidanceCfg = configFile >> "CfgAmmo" >> _ammoClassName >> "ace_missileguidance";
    // configName check: an INHERITED guidance block doesn't count -- that
    // mod's own Fired handler requires it declared on the ammo itself.
    if (isClass _guidanceCfg && {(configName _guidanceCfg) == "ace_missileguidance"} && {(getNumber (_guidanceCfg >> "enabled")) == 1}) then {
        if (!isNull _gunner) then { _gunner setVariable ["ace_missileguidance_target", _target]; };
        _system setVariable ["ace_missileguidance_target", _target];
    };
};

if !(_system getVariable ["AEGISM_firedEhAdded", false]) then {
    _system setVariable ["AEGISM_firedEhAdded", true, false];
    _system addEventHandler ["Fired", {
        params ["_vehicle", "_weapon", "", "", "", "", "_projectile"];
        [_vehicle, _weapon, _projectile] call aegism_intercept_fnc_onSystemFired;
    }];
};

// Context lifetime: a launcher's round leaves within a moment of the fire
// command; a CIWS burst lasts its own duration.
private _targetIsMunition = ([_target] call aegism_detect_fnc_classifyTarget) in ["missile", "rocket", "bomb", "artilleryShell"];
private _contextLifetime = [2, _burstDuration + 0.5] select _isCiws;
_system setVariable [format ["AEGISM_capture_%1", _weaponClass], [_target, _role, _interceptors, time + _contextLifetime, _targetIsMunition], false];

if (_isCiws) then {
    diag_log text format ["[AEGIS-M] FIRE: %1 (%2) opens a %3s burst of %4 (%5, %6 rounds left) at %7 (%8) -- ciws.", _system, typeOf _system, round (_burstDuration * 10) / 10, _weaponClass, _magazineClass, _ammoBefore, _target, typeOf _target];
    [_system, _target, _weaponInfo, _burstDuration] call aegism_intercept_fnc_ciwsBurst;
} else {
    diag_log text format ["[AEGIS-M] FIRE: %1 (%2) fires %3 (%4, %5 rounds left) at %6 (%7) -- %8.", _system, typeOf _system, _weaponClass, _magazineClass, _ammoBefore, _target, typeOf _target, _role];
    [_system, _weaponClass, _turretPath] call BIS_fnc_fire;
};

// Each launcher fire command should consume exactly one missile; more means
// the engine fired a ripple. Counted against the fire commands actually
// issued to this turret in the meantime ("AEGISM_turretShots_<path>") -- a
// launcher on a 1s interval legitimately fires its NEXT missile inside the
// 1s check window, which used to be reported as an anomaly. (A CIWS burst
// reports its own count, BURST-END.)
if (!_isCiws) then {
    private _shotsKey = format ["AEGISM_turretShots_%1", _turretPath];
    private _shotsBefore = _system getVariable [_shotsKey, 0];
    _system setVariable [_shotsKey, _shotsBefore + 1, false];
    [{
        params ["_system", "_magazineClass", "_turretPath", "_ammoBefore", "_shotsKey", "_shotsBefore"];
        if (isNull _system) exitWith {};
        private _consumed = _ammoBefore - (_system magazineTurretAmmo [_magazineClass, _turretPath]);
        private _commanded = (_system getVariable [_shotsKey, 0]) - _shotsBefore;
        // A reload in the window refills the count; only an excess is an anomaly.
        if (_consumed > _commanded) then {
            diag_log text format ["[AEGIS-M] FIRE-ANOMALY: %1 -- %2 fire command(s) consumed %3 missiles.", _system, _commanded, _consumed];
        };
    }, [_system, _magazineClass, _turretPath, _ammoBefore, _shotsKey, _shotsBefore], 1] call CBA_fnc_waitAndExecute;
};

1
