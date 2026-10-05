/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_gunnerLock

Description:
    Keeps a launcher turret's gunner locked on the aircraft it's assigned --
    as a real crew locks on before launch -- or lets go of it. Called every
    tick the launcher works an engagement (aegism_intercept_fnc_
    engagementLoop), from the moment it's assigned.

    AEGIS-M aims and fires the turret itself, with the crew's own targeting
    off (aegism_fnc_setWeaponAiSuppressed), so the gunner never has a target
    of its own. The game only warns a target of an incoming missile
    (IncomingMissile) launched locked on it or aimed at it by AI -- a missile
    fired without one gives the aircraft no launch warning, and its crew
    never reacts (no flares, no evasion). reveal + doTarget gives the gunner
    the target (logged, LOCK-ON): the aircraft gets its lock warning while
    the launcher reacts and slews, and its missile warning at launch
    (MISSILE-WARNING, aegism_intercept_fnc_fireWeapon).

    The lock takes the weapon's own time (CfgWeapons weaponLockDelay: 0.5 s
    for ACE's SAM launchers, 1.5 s for the vanilla MIM-145, 3 s for the
    vanilla RIM-116), and a missile fired before it's complete leaves
    unlocked: a Defender, with no sensor of its own to lock with, given its
    target at the instant of launch, only ever gave a "locking" warning.
    So this returns how much longer the lock needs, and the launcher holds
    fire until it's done ("locking").

    The gunner's "TARGET" AI, off since AEGIS-M took the turret (aegism_fnc_
    setWeaponAiSuppressed), is back on while it's locked: with it off a
    Defender -- whose target only comes from the Site's datalink -- held one
    for 12 s and never locked (no missile warning at launch). Its
    "AUTOTARGET" stays off, so it doesn't pick a target of its own, and its
    "FIREWEAPON" off, so it can't fire on its own: a gunner holding a target
    fired at it by itself without that (in testing, some 3.5 s after being
    given it -- UNCOMMANDED-FIRE). A munition is never locked (nothing locks
    on a projectile): a turret moving from an aircraft to a munition lets
    go, as does a turret handed back to its crew.

Parameters:
    _system - the launcher vehicle <OBJECT>
    _turretPath - the launcher's turret path <ARRAY>
    _target - its target, or objNull to let go <OBJECT>
    _weaponClass - the launcher's weapon, for its lock time <STRING, default "">

Returns:
    Seconds until the lock is complete; 0 when locked, or nothing to lock <NUMBER>

Examples:
    [_samSite, [0], _helicopter, "weapon_mim145Launcher"] call aegism_intercept_fnc_gunnerLock;
    [_samSite, [0], objNull] call aegism_intercept_fnc_gunnerLock;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

params ["_system", "_turretPath", "_target", ["_weaponClass", ""]];

private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;
private _gunner = _system turretUnit _turretPath;

private _wanted = _target;
if (!isNull _wanted && {([_wanted] call aegism_detect_fnc_classifyTarget) in ["missile", "rocket", "bomb", "artilleryShell"]}) then { _wanted = objNull; };

if (isNull _wanted) exitWith {
    if (!isNull (_ts getOrDefault ["lockTarget", objNull])) then {
        _ts set ["lockTarget", objNull];
        if (!isNull _gunner) then {
            _gunner doTarget objNull;
            _gunner disableAI "TARGET";
        };
    };
    0
};
if (isNull _gunner) exitWith { 0 };

if ((_ts getOrDefault ["lockTarget", objNull]) isNotEqualTo _wanted) then {
    _ts set ["lockTarget", _wanted];
    _ts set ["lockSince", CBA_missionTime];
    _gunner enableAI "TARGET";
    _gunner reveal [_wanted, 4];
    _gunner doTarget _wanted;
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " LOCK-ON: %1 turret %2 -- gunner %3 locking %4 (%5), %6m; %7 s to lock.", _system, _turretPath, _gunner, _wanted, typeOf _wanted, round (_system distance _wanted),
            getNumber (configFile >> "CfgWeapons" >> _weaponClass >> "weaponLockDelay")];
    };
};

((_ts get "lockSince") + getNumber (configFile >> "CfgWeapons" >> _weaponClass >> "weaponLockDelay") - CBA_missionTime) max 0
