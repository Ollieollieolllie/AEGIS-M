/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_fireWeapon

Description:
    Fires a System's own real weapon: one missile for a launcher, or opens
    one sustained burst for a CIWS gun (aegism_intercept_fnc_ciwsBurst, at
    the gun's own rate of fire). AEGIS-M never spawns projectiles:
    ballistics, guidance and damage are the game's own.

    The caller (aegism_intercept_fnc_engagementLoop) has already aimed the
    turret and confirmed alignment; this function only rolls crew
    reliability and fires, via BIS_fnc_fire (a real single fire command --
    fireAtTarget hands the decision to AI judgement and was observed firing
    several missiles per call).

    Crew reliability is rolled here, once per missile or per CIWS burst. A
    failed roll returns 0, which the engagement loop treats as a lost fire
    cycle (it waits one shot interval / burst pause before trying again).

    Before firing it writes a capture context on the turret ("capture" in
    aegism_intercept_fnc_turretState, naming the weapon) and makes sure the
    vehicle has AEGIS-M's persistent Fired handler; aegism_intercept_fnc_
    onSystemFired then hands a launched missile its target
    (setMissileTarget), records it as an in-flight interceptor, and starts
    its proximity fuse.

    Crew locality: the engagement pipeline runs on the server, and a
    missile can only be given its target where it's simulated -- where the
    crew is local. An AI crew simulated on another machine (a headless
    client, or a player's AI group) is moved to the server (setGroupOwner)
    and this fire cycle skipped; a PLAYER in the turret can't be, so its
    missiles fly without AEGIS-M's target. Logged once per turret
    (NONLOCAL).

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
    _state - optional, launcher only: the engagement state the shot counts
        in (aegism_intercept_fnc_engagementLoop). If no missile leaves --
        the fire command fired nothing -- the shot is taken back off its
        roundsFired (FIRE-FAILED), so it isn't judged a miss <HASHMAP>

Returns:
    1 fired, 0 crew hesitated (reliability roll failed), -1 could not fire
    (hold, dead target, no ammo, crew being moved to the server) <NUMBER>

Examples:
    [_samSite, _heli, _weaponInfo, 0.85, "launcher", _interceptors, 0, _engagementState] call aegism_intercept_fnc_fireWeapon;
    [_cheetah, _rocket, _weaponInfo, 0.85, "ciws", _interceptors, 4] call aegism_intercept_fnc_fireWeapon;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

// aegism_intercept_fnc_launchSolution's own on-bore tolerance: off by more,
// a launch is off-bore (OFFBORE-LAUNCH).
#define AEGISM_LAUNCH_ON_BORE 2

params ["_system", "_target", "_weaponInfo", "_reliability", "_role", ["_interceptors", []], ["_burstDuration", 0], ["_state", createHashMap]];
_weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

private _isCiws = _role == "ciws";
private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;

// Debug circuit breaker (aegism_intercept_fnc_debugSetFireHold): the single
// choke point every AEGIS-M fire command passes through.
if (_ts getOrDefault ["fireHold", false]) exitWith { -1 };
if (isNull _target || {!alive _target}) exitWith { -1 };

private _ammoBefore = _system magazineTurretAmmo [_magazineClass, _turretPath];
if (_ammoBefore <= 0) exitWith { -1 };

// Crew simulated elsewhere: bring an AI crew to the server (see header).
private _gunner = _system turretUnit _turretPath;
private _crewElsewhere = !isNull _gunner && {!local _gunner};
private _playerCrew = _crewElsewhere && {((units group _gunner) findIf { isPlayer _x }) != -1};
if (_crewElsewhere) then {
    if ((_ts getOrDefault ["nonLocalLogged", -1]) != owner _gunner) then {
        _ts set ["nonLocalLogged", owner _gunner];
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " NONLOCAL: %1 turret %2 crew (%3) is simulated on machine %4, not the server -- %5",
            _system, _turretPath, _gunner, owner _gunner,
            ["its AI group is being moved to the server so AEGIS-M can guide its missiles.", "a player is in that group, so it can't be moved: missiles fired from it won't get AEGIS-M's target."] select _playerCrew];
    };
    if (!_playerCrew) then { (group _gunner) setGroupOwner clientOwner; };
};
if (_crewElsewhere && {!_playerCrew}) exitWith { -1 };

if (random 1 > _reliability) exitWith {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " FIRE-SKIP: %1 (%2) at %3 -- crew reliability roll failed (reliability=%4), losing this fire cycle.", _system, _role, _target, _reliability];
    0
};

private _kinematics = [_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics;

if (!isNil "ace_missileguidance_fnc_onFired") then {
    private _guidanceCfg = configFile >> "CfgAmmo" >> (_kinematics select 0) >> "ace_missileguidance";
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
        params ["_vehicle", "_weapon", "", "", "", "", "_projectile", "_gunner"];
        [_vehicle, _weapon, _projectile, _gunner] call aegism_intercept_fnc_onSystemFired;
    }];
};

// Context lifetime: a launcher's round leaves within a moment of the fire
// command; a CIWS burst lasts its own duration.
private _targetIsMunition = ([_target] call aegism_detect_fnc_classifyTarget) in ["missile", "rocket", "bomb", "artilleryShell"];
private _contextLifetime = [2, _burstDuration + 0.5] select _isCiws;
// A missile's launch plan (aegism_intercept_fnc_aimWeapon's, for this
// target): how far off the intercept it leaves, and the predicted flight --
// checked against the real one in flight (aegism_intercept_fnc_
// interceptorPFH, MISSILE-TURN) -- and what it was fired from, for its
// speed (MISSILE-SPEED).
(_ts getOrDefault ["launchPlan", []]) params [["_planTarget", objNull], ["_way", ""], ["_offBore", 0], ["_turnTime", 0], ["_predictedFlight", -1], ["_calibrated", true]];
if (_planTarget != _target) then { _way = ""; _offBore = 0; _turnTime = 0; _predictedFlight = -1; };
_ts set ["capture", [_target, _role, _interceptors, CBA_missionTime + _contextLifetime, _targetIsMunition, _turretPath, _weaponClass, [_offBore, _predictedFlight, CBA_missionTime, _weaponClass, _magazineClass]]];

if (_isCiws) then {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " FIRE: %1 (%2) opens a %3s burst of %4 (%5, %6 rounds left) at %7 (%8) -- ciws.", _system, typeOf _system, round (_burstDuration * 10) / 10, _weaponClass, _magazineClass, _ammoBefore, _target, typeOf _target];
    [_system, _target, _weaponInfo, _burstDuration] call aegism_intercept_fnc_ciwsBurst;
} else {
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " FIRE: %1 (%2) fires %3 (%4, %5 rounds left) at %6 (%7) -- %8, launched %9, %10 deg off the intercept.", _system, typeOf _system, _weaponClass, _magazineClass, _ammoBefore, _target, typeOf _target, _role,
        switch (_way) do {
            case "onBore": { "on it" };
            case "slew": { "as close as the turret gets" };
            case "now": { "before the turret is round (swinging first would be too late to intercept)" };
            case "fixed": { "from a fixed mount" };
            default { "" };
        }, round (_offBore * 10) / 10];
    if (_offBore > AEGISM_LAUNCH_ON_BORE) then {
        if (AEGISM_RPT_VERBOSE) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " OFFBORE-LAUNCH: %1 turret %2 -- %3 deg off the intercept on %4: %5.", _system, _turretPath, round _offBore, _target,
                if (_calibrated) then {
                    format ["predicted turn %1s, flight %2s", round (_turnTime * 10) / 10, round (_predictedFlight * 10) / 10]
                } else {
                    format ["its turn rate isn't measured yet, so its flight (%1s) is predicted as if straight -- this flight measures it", round (_predictedFlight * 10) / 10]
                }];
        };
    };
    // An aircraft: its gunner has held a lock on it (aegism_intercept_fnc_
    // gunnerLock), so the missile leaves with the aircraft warned. Logged:
    // what the aircraft's own sensors show of this launcher and the gunner's
    // assigned target, and whether the game warns it (IncomingMissile,
    // logged once per missile as MISSILE-WARNING; added once per aircraft,
    // where it's simulated here).
    if (!_targetIsMunition) then {
        if (AEGISM_RPT_VERBOSE) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " LOCK: %1 fires on %2 -- its sensors show this launcher as %3; gunner's assigned target %4.", _system, _target,
                ((getSensorThreats _target) select { (_x param [0, objNull]) isEqualTo _system }) apply { _x select [1] }, assignedTarget _gunner];
        };
        if (local _target && {!(_target getVariable ["AEGISM_warningLogged", false])}) then {
            _target setVariable ["AEGISM_warningLogged", true];
            _target addEventHandler ["IncomingMissile", {
                params ["_target", "_ammo", "_vehicle"];
                diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " MISSILE-WARNING: %1 (%2) is warned of an incoming %3 from %4.", _target, typeOf _target, _ammo, _vehicle];
            }];
        };
    };
    [_system, _weaponClass, _turretPath] call BIS_fnc_fire;
};

// Checked once the capture context has run out:
//   - no missile came of it (the context was never taken, aegism_intercept_
//     fnc_onSystemFired): FIRE-FAILED, and the shot is taken back off the
//     engagement's count, so the coordinator doesn't release the target as
//     missed -- the launcher holds until it can really fire (aegism_
//     intercept_fnc_weaponReload) or the target goes to another weapon.
//     POOK's launchers fired into their magazine reloads and nothing left.
//   - more missiles than commands: the engine fired a ripple. Counted
//     against the fire commands actually issued to this turret in the
//     meantime (turret state "shots") -- a launcher on a short interval
//     legitimately fires its NEXT missile inside the window.
// (A CIWS burst reports its own count, BURST-END.)
if (!_isCiws) then {
    private _shotsBefore = _ts getOrDefault ["shots", 0];
    _ts set ["shots", _shotsBefore + 1];
    private _expiresAt = (_ts get "capture") select 3;
    [{
        params ["_system", "_weaponClass", "_magazineClass", "_turretPath", "_ammoBefore", "_ts", "_shotsBefore", "_expiresAt", "_state", "_target"];
        if (isNull _system) exitWith {};
        if (((_ts getOrDefault ["capture", []]) param [3, -1]) == _expiresAt) exitWith {
            _ts deleteAt "capture";
            if ((_state getOrDefault ["roundsFired", 0]) > 0) then { _state set ["roundsFired", (_state get "roundsFired") - 1]; };
            ([_system, _turretPath, _weaponClass] call aegism_intercept_fnc_weaponReload) params ["_ready", "_wait", "_loading", "_phases"];
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " FIRE-FAILED: %1 fired %2 at %3 and no missile left -- %4 Not counted as a shot.", _system, _weaponClass, _target,
                switch (true) do {
                    case (_loading): { format ["it's loading its next magazine, ready in ~%1s.", round _wait] };
                    case (!_ready): { format ["it's readying its next round, ready in ~%1s (weaponState reload phases %2).", round _wait, _phases] };
                    default { format ["its weapon reports ready (weaponState reload phases %1, %2 rounds left); the vehicle's mod may launch some other way.", _phases, _system magazineTurretAmmo [_magazineClass, _turretPath]] };
                }];
        };
        private _consumed = _ammoBefore - (_system magazineTurretAmmo [_magazineClass, _turretPath]);
        private _commanded = (_ts getOrDefault ["shots", 0]) - _shotsBefore;
        // A reload in the window refills the count; only an excess is an anomaly.
        if (_consumed > _commanded) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " FIRE-ANOMALY: %1 -- %2 fire command(s) consumed %3 missiles.", _system, _commanded, _consumed];
        };
    }, [_system, _weaponClass, _magazineClass, _turretPath, _ammoBefore, _ts, _shotsBefore, _expiresAt, _state, _target], _contextLifetime + 0.2] call CBA_fnc_waitAndExecute;
};

1
