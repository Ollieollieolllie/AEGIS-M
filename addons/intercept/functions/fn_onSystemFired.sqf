/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_onSystemFired

Description:
    Body of the single persistent "Fired" event handler every AEGIS-M System
    vehicle gets (aegism_intercept_fnc_firedHandler).
    Full notes: docs/functions/intercept.md

Parameters:
    _vehicle - the firing System vehicle <OBJECT>
    _weapon - fired weapon class <STRING>
    _projectile - the fired projectile <OBJECT>
    _gunner - the Fired event's gunner <OBJECT>

Returns:
    Nothing

Examples:
    [_vehicle, _weapon, _projectile, _gunner] call aegism_intercept_fnc_onSystemFired;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

// Rounds measured for spotting: one in this many. A burst still gives the
// estimator dozens of samples.
#define AEGISM_SPOT_EVERY 3

params ["_vehicle", "_weapon", "_projectile", ["_gunner", objNull]];

if (isNull _projectile) exitWith {};
// None yet on a vehicle AEGIS-M hasn't worked a turret of: no fire command
// of its, then.
private _turrets = _vehicle getVariable ["AEGISM_turrets", createHashMap];

private _ts = createHashMap;
private _context = [];
if (!isNull _gunner) then {
    private _gunnerTurret = _turrets getOrDefault [_vehicle unitTurret _gunner, createHashMap];
    private _candidate = _gunnerTurret getOrDefault ["capture", []];
    if ((_candidate param [6, ""]) == _weapon) then { _ts = _gunnerTurret; _context = _candidate; };
};
if (_context isEqualTo []) then {
    {
        private _candidate = _y getOrDefault ["capture", []];
        if ((_candidate param [6, ""]) == _weapon) exitWith { _ts = _y; _context = _candidate; };
    } forEach _turrets;
};
// No fire command from AEGIS-M for this weapon: the crew fired by itself
// (its gunner ordered to lock an aircraft, aegism_intercept_fnc_gunnerLock,
// mustn't make it shoot), or another mod's script fired it. A gun's is
// logged once per vehicle and weapon; a missile's every time -- each is a
// missile gone and a reload AEGIS-M didn't plan -- with what its gunner was
// on and which of its own targeting AEGIS-M finds switched on. A player's
// own shot is nothing to log.
if (_context isEqualTo []) exitWith {
    if (isPlayer _gunner) exitWith {};
    private _logKey = "AEGISM_uncommandedLogged_" + _weapon;
    private _isMissile = _projectile isKindOf "MissileCore";
    if (_isMissile || {!(_vehicle getVariable [_logKey, false])}) then {
        _vehicle setVariable [_logKey, true];
        private _on = if (isNull _gunner) then { [] } else { ["TARGET", "AUTOTARGET", "FIREWEAPON"] select { _gunner checkAIFeature _x } };
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " UNCOMMANDED-FIRE: %1 fired %2 (%3) with no AEGIS-M fire command -- its crew's own AI or another mod's script fired. Gunner %4, its assigned target %5, its own %6.%7",
            _vehicle, _weapon, typeOf _projectile, _gunner, assignedTarget _gunner,
            ["targeting and firing all off", (_on joinString ", ") + " on"] select (_on isNotEqualTo []),
            ["", " AEGIS-M doesn't guide or fuse this missile."] select _isMissile];
    };
};
_context params ["_target", "_role", "_interceptors", "_expiresAt", "_targetIsMunition", "_turretPath", "", ["_launch", []]];

if (CBA_missionTime > _expiresAt) exitWith { _ts deleteAt "capture"; };

// A terminal's surface strike (aegism_intercept_fnc_surfaceStrike): its
// missile is flown onto its point (aegism_intercept_fnc_strikeMissile); a
// gun's rounds are left to fly as they are -- nothing fuses, follows or
// self-destructs them. (Before the Site is marked as having fired: a
// strike doesn't sound its alarm.)
if (_role == "strike") exitWith {
    _launch params [["_seeker", objNull], ["_aimPos", []]];
    if (!isNull _seeker) then {
        _ts deleteAt "capture";
        [_projectile, _seeker, _aimPos] call aegism_intercept_fnc_strikeMissile;
    };
};

// The Site's going-live alarm lasts a while after its last shot (aegism_
// network_fnc_siteAlarm), and its crews are in combat meanwhile (aegism_
// intercept_fnc_engagementLoop) -- a vehicle with no Site by its own. Every
// Site of a linked group (aegism_network_fnc_linkSites) goes live together.
_vehicle setVariable ["AEGISM_lastShotAt", CBA_missionTime];
private _site = _vehicle getVariable ["AEGISM_network", objNull];
if (!isNull _site) then {
    { _x setVariable ["AEGISM_lastShotAt", CBA_missionTime]; } forEach (_site getVariable ["AEGISM_linkSites", [_site]]);
};

if (_role == "launcher") exitWith {
    _ts deleteAt "capture";
    // Forced: set even if the target is outside the missile's own seeker
    // cone as it leaves (an off-bore launch turns onto it).
    if (!isNull _target && {alive _target}) then {
        _projectile setMissileTarget [_target, true];
    };
    _interceptors pushBack _projectile;
    [_projectile, _target, _launch] call aegism_intercept_fnc_interceptorPFH;
};

// Every round of the burst, whatever it's aimed at (Self-Destruct Rounds).
if ((_vehicle getVariable ["AEGISM_resolvedEngagementSettings", createHashMap]) getOrDefault ["ciwsSelfDestruct", false]) then {
    [_vehicle, _turretPath, _ts, _projectile, _weapon] call aegism_intercept_fnc_ciwsSelfDestruct;
};

if (isNull _target || {!alive _target}) exitWith {};
private _seq = (_ts getOrDefault ["spotSeq", 0]) + 1;
_ts set ["spotSeq", _seq];
private _spot = _seq % AEGISM_SPOT_EVERY == 0;
if (!_targetIsMunition && {!_spot}) exitWith {};
[_vehicle, _turretPath, _ts, _projectile, _target, _targetIsMunition, _spot] call aegism_intercept_fnc_ciwsRounds;
