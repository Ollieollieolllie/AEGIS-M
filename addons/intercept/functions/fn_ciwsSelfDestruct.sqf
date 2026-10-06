/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsSelfDestruct

Description:
    Self-destructs a CIWS round that hits nothing (the "Self-Destruct
    Rounds" setting), as a C-RAM round's self-destruct fuze does: once it
    has passed the gun's reach -- its CIWS Max Range, or the gun's own config
    reach (aegism_intercept_fnc_envelopeBounds) -- so a round that misses
    bursts out there instead of flying on. Never later than
    AEGISM_SELF_DESTRUCT_MARGIN before its own lifetime (CfgAmmo
    timeToLive), when the engine removes it.

    The fuze time is the round's flight to the gun's reach under its drag
    (CfgAmmo airFriction, the same model as aegism_intercept_fnc_
    openFireRange), from the speed it actually left the muzzle at. Each
    ammo's lifetime and drag are read once per ammo type and cached
    ("AEGISM_cacheLifetime"): they differ from one weapon system to the
    next, and mods change them (the vanilla 35mm lives 6 s, from BulletBase;
    ACE makes it 30 s). The fuze time is worked out per gun, refreshed every
    AEGISM_SELF_DESTRUCT_REFRESH s (so a Zeus edit of CIWS Max Range takes
    effect), and logged when it changes (SELF-DESTRUCT-FUZE).

    One queue per gun turret (turret state "selfDestruct"): a gun's rounds
    share one fuze time and leave in order, so they come due in order, and
    each frame only looks at the due rounds at its head. A round that has
    already hit something, or was fuzed on its target (aegism_intercept_fnc_
    interceptHit), is gone by then and skipped. When the queue empties, how
    many rounds self-destructed and how many were already gone is logged
    (SELF-DESTRUCT).

Parameters:
    _system - the CIWS vehicle <OBJECT>
    _turretPath - its gun turret <ARRAY>
    _ts - that turret's state <HASHMAP>
    _projectile - the round, just fired <OBJECT>
    _weaponClass - the gun <STRING>

Returns:
    Nothing

Examples:
    [_praetorian, [0], _ts, _round, "weapon_Cannon_Phalanx"] call aegism_intercept_fnc_ciwsSelfDestruct;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

#define AEGISM_SELF_DESTRUCT_MARGIN 0.15
#define AEGISM_SELF_DESTRUCT_REFRESH 1
#define AEGISM_MAX_DRAG_EXPONENT 30

params ["_system", "_turretPath", "_ts", "_projectile", "_weaponClass"];

private _ammo = typeOf _projectile;

// This gun's fuze time for this ammo: [ammo, seconds, worked out at].
private _fuze = _ts getOrDefault ["selfDestructFuze", []];
if (_fuze isEqualTo [] || {(_fuze select 0) != _ammo} || {CBA_missionTime - (_fuze select 2) > AEGISM_SELF_DESTRUCT_REFRESH}) then {
    // The ammo's lifetime and drag, read once per ammo type.
    private _cache = missionNamespace getVariable "AEGISM_cacheLifetime";
    if (isNil "_cache") then {
        _cache = createHashMap;
        missionNamespace setVariable ["AEGISM_cacheLifetime", _cache];
    };
    private _ammoInfo = _cache get _ammo;
    if (isNil "_ammoInfo") then {
        // How long it really flies: an airburst round's flight ends at its
        // burst (aegism_intercept_fnc_ammoBurst).
        _ammoInfo = [([_ammo] call aegism_intercept_fnc_ammoBurst) select 0, abs ((getNumber (configOf _projectile >> "airFriction")) min 0)];
        _cache set [_ammo, _ammoInfo];
    };
    _ammoInfo params ["_lifetime", "_k"];

    // The gun's reach, and the round's flight to it.
    private _v0 = vectorMagnitude velocity _projectile;
    private _weapons = (_system getVariable ["AEGISM_system", createHashMap]) getOrDefault ["ciwsWeapons", []];
    private _weaponIndex = _weapons findIf { (_x select 0) isEqualTo _turretPath && {(_x select 1) == _weaponClass} };
    private _reach = 0;
    if (_weaponIndex != -1) then {
        private _settings = _system getVariable ["AEGISM_resolvedEngagementSettings", createHashMap];
        _reach = ([_settings, _weapons select _weaponIndex, "ciws"] call aegism_intercept_fnc_envelopeBounds) select 1;
    };
    private _seconds = switch (true) do {
        case (_reach <= 0 || {_v0 <= 0}): { 1e10 };
        case (_k > 0): { ((exp ((_k * _reach) min AEGISM_MAX_DRAG_EXPONENT)) - 1) / (_k * _v0) };
        default { _reach / _v0 };
    };
    private _byLifetime = _lifetime > 0 && {_seconds > _lifetime - AEGISM_SELF_DESTRUCT_MARGIN};
    if (_byLifetime) then { _seconds = _lifetime - AEGISM_SELF_DESTRUCT_MARGIN; };

    if (abs ((_fuze param [1, -1]) - _seconds) > 0.01) then {
        if (AEGISM_RPT_VERBOSE) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SELF-DESTRUCT-FUZE: %1 turret %2 -- %3 rounds burst %4s after firing, %5 (muzzle %6 m/s, airFriction %7, lifetime %8s).",
                _system, _turretPath, _ammo, round (_seconds * 100) / 100,
                if (_byLifetime) then { "just before their lifetime runs out" } else { format ["once past the gun's %1m reach", round _reach] },
                round _v0, _k, _lifetime];
        };
    };
    _fuze = [_ammo, _seconds, CBA_missionTime];
    _ts set ["selfDestructFuze", _fuze];
};
private _seconds = _fuze select 1;
if (_seconds <= 0 || {_seconds >= 1e10}) exitWith {};

private _queue = _ts get "selfDestruct";
if (isNil "_queue") then { _queue = []; _ts set ["selfDestruct", _queue]; };
_queue pushBack [CBA_missionTime + _seconds, _projectile];

if (_ts getOrDefault ["selfDestructRunning", false]) exitWith {};
_ts set ["selfDestructRunning", true];

[{
    params ["_args", "_pfhHandle"];
    _args params ["_system", "_turretPath", "_ts", "_queue", "_detonated", "_gone", "_ammo"];
    while { _queue isNotEqualTo [] && {((_queue select 0) select 0) <= CBA_missionTime} } do {
        private _projectile = (_queue deleteAt 0) select 1;
        if (!isNull _projectile && {alive _projectile}) then {
            if (_ammo == "") then { _ammo = typeOf _projectile; _args set [6, _ammo]; };
            triggerAmmo _projectile;
            _detonated = _detonated + 1;
        } else {
            _gone = _gone + 1;
        };
    };
    _args set [4, _detonated];
    _args set [5, _gone];
    if (_queue isEqualTo []) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        _ts set ["selfDestructRunning", false];
        if (AEGISM_RPT_VERBOSE) then {
            diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " SELF-DESTRUCT: %1 turret %2 -- %3 round(s)%4 self-destructed %5s after firing; %6 had already hit something or been fuzed.", _system, _turretPath, _detonated,
                ["", format [" of %1", _ammo]] select (_ammo != ""), round (((_ts getOrDefault ["selfDestructFuze", ["", 0]]) select 1) * 100) / 100, _gone];
        };
    };
}, 0, [_system, _turretPath, _ts, _queue, 0, 0, ""]] call CBA_fnc_addPerFrameHandler;
