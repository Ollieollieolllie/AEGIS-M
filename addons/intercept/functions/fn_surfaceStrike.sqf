/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_surfaceStrike

Description:
    Has one weapon fire at a point on the ground, on a terminal's order: a
    launcher one missile, lofted onto it; a gun one burst. It takes the
    turret for as long as that needs, and the Site's own use of it waits.
    Full notes: docs/functions/intercept.md

Parameters:
    _system - the firing vehicle <OBJECT>
    _role - "launcher" or "ciws" <STRING>
    _weaponInfo - weaponInfo, see aegism_system_fnc_discoverCapabilities <ARRAY>
    _aimPos - the point, ASL <ARRAY>
    _site - the Site whose terminals are told how it ended (its
        "AEGISM_manualLog") <OBJECT, default objNull>

Returns:
    [started <BOOLEAN>, why not <STRING>]

Examples:
    [_patriot, "launcher", _weaponInfo, AGLToASL _position] call aegism_intercept_fnc_surfaceStrike;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\strike.hpp"

params ["_system", "_role", "_weaponInfo", "_aimPos", ["_site", objNull]];
_weaponInfo params ["_turretPath"];

private _shot = [_system, _role, _weaponInfo, _aimPos] call aegism_intercept_fnc_surfaceShot;
if !(_shot select 0) exitWith { [false, _shot select 1] };
private _ts = [_system, _turretPath] call aegism_intercept_fnc_turretState;
if (CBA_missionTime < (_ts getOrDefault ["strikeUntil", -1])) exitWith { [false, "it's on another strike"] };

// "strikeUntil", kept a second ahead while this runs: the vehicle's own loop
// leaves the turret alone meanwhile (aegism_intercept_fnc_engagementLoop).
_ts set ["strikeUntil", CBA_missionTime + 1];

[{
    params ["_args", "_handle"];
    _args params ["_system", "_role", "_weaponInfo", "_aimPos", "_site", "_ts", "_startedAt", "_phase", "_phaseAt", "_aimPoint", "_solvedAt", "_extra"];
    _weaponInfo params ["_turretPath", "_weaponClass", "_magazineClass"];

    private _fnEnd = {
        [_handle] call CBA_fnc_removePerFrameHandler;
        if (!isNull _system) then {
            _ts set ["strikeUntil", -1];
            // (Its turret goes back to its crew as after any target: the
            // vehicle's loop, a moment after the last aim.)
            _ts set ["lockAt", CBA_missionTime];
        };
        private _line = format ["%1's strike on grid %2 %3.", _system, mapGridPosition _aimPos, _this];
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " STRIKE: %1", _line];
        if (!isNull _site) then {
            private _log = _site getVariable ["AEGISM_manualLog", []];
            _log pushBack [CBA_missionTime, _line];
            if (count _log > 8) then { _log deleteAt 0; };
            _site setVariable ["AEGISM_manualLog", _log, false];
        };
    };
    if (isNull _system || {!alive _system}) exitWith { "ended -- the vehicle is lost" call _fnEnd; };
    // (Cease Fire at a terminal: aegism_network_fnc_terminalOrder.)
    if ((_ts getOrDefault ["strikeAbort", -1]) >= _startedAt) exitWith { "was called off" call _fnEnd; };
    _ts set ["strikeUntil", CBA_missionTime + 1];
    _ts set ["lockAt", CBA_missionTime];

    private _isGun = _role == "ciws";
    private _ammo = _system magazineTurretAmmo [_magazineClass, _turretPath];

    // --- Coming onto it ----------------------------------------------------------
    if (_phase == "aim") exitWith {
        // Solved again twice a second (the vehicle may be moving), and the
        // turret sent there.
        if (CBA_missionTime - _solvedAt >= 0.5) then {
            private _shot = [_system, _role, _weaponInfo, _aimPos] call aegism_intercept_fnc_surfaceShot;
            _args set [10, CBA_missionTime];
            if (_shot select 0) then {
                _aimPoint = _shot select 2;
                _args set [9, _aimPoint];
                [_system, _turretPath, _aimPoint] call aegism_intercept_fnc_lockTurret;
            } else {
                _args set [11, _shot select 1];
            };
        };
        if (_extra isEqualType "" && {_extra != ""}) exitWith { (format ["ended -- %1", _extra]) call _fnEnd; };

        private _origin = ([_system, _turretPath, _role] call aegism_intercept_fnc_turretPoints) select 0;
        private _barrel = [_system, _turretPath, _weaponClass] call aegism_intercept_fnc_barrelDirection;
        private _off = if (_barrel isEqualTo [0, 0, 0]) then { 180 } else { acos (((_barrel vectorCos (_origin vectorFromTo _aimPoint)) min 1) max -1) };
        private _on = _off <= ([AEGISM_STRIKE_ALIGN_LAUNCHER, AEGISM_STRIKE_ALIGN_GUN] select _isGun);
        private _ready = ([_system, _turretPath, _weaponClass] call aegism_intercept_fnc_weaponReload) select 0;
        private _late = CBA_missionTime - _startedAt > AEGISM_STRIKE_AIM_TIMEOUT;
        if (_late && {!_ready}) exitWith { "ended -- its weapon wasn't ready in time" call _fnEnd; };
        if (_late && {_isGun} && {!_on}) exitWith { (format ["ended -- its barrel didn't come onto it (%1 deg off)", round (_off * 10) / 10]) call _fnEnd; };
        if (!_ready || {!_on && {!_late}}) exitWith {};

        if (_isGun) then {
            // One burst, the vehicle's shortest (its CIWS Burst Length).
            private _settings = _system getVariable ["AEGISM_resolvedEngagementSettings", createHashMap];
            private _length = (_settings getOrDefault ["ciwsBurstMin", 2]) max 0.5;
            // (Its rounds are its own: nothing of the Site's fuses or follows
            // them. aegism_intercept_fnc_onSystemFired, "strike".)
            _ts set ["capture", [objNull, "strike", [], CBA_missionTime + _length + 0.5, false, _turretPath, _weaponClass, []]];
            _args set [7, "burst"];
            _args set [8, CBA_missionTime + _length];
            _args set [11, _ammo];
        } else {
            // What its missile is told to fly at: an object of the server's
            // own, moved in flight (aegism_intercept_fnc_strikeMissile). A
            // guidance mod's missile takes it as its target at launch.
            // One with a radar seeker (ACE's Doppler radar: the Patriot)
            // only keeps a target that is a munition or an aircraft, and
            // drops one near the ground that isn't moving along the line
            // to it -- a plain object on the ground it never followed, and
            // flew on past (2026-10-07). It's given a chemlight to chase (a
            // munition to its seeker, harmless and long-lived; an infrared
            // one where there is one, so nothing shows), kept moving along
            // that line, and shared with its side's datalink.
            private _first = _aimPos vectorAdd [0, 0, AEGISM_STRIKE_SEEKER_HEIGHT + AEGISM_STRIKE_LOFT_AT(_origin distance2D _aimPos)];
            private _guidance = configFile >> "CfgAmmo" >> (([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 0) >> "ace_missileguidance";
            private _radarSeeker = !isNil "ace_missileguidance_fnc_onFired" && {isClass _guidance} && {(getNumber (_guidance >> "enabled")) == 1}
                && {(getText (_guidance >> "defaultSeekerType")) == "DopplerRadar"};
            private _seeker = if (_radarSeeker) then {
                createVehicle [["Chemlight_green", "ACE_G_Chemlight_IR"] select (isClass (configFile >> "CfgAmmo" >> "ACE_G_Chemlight_IR")), ASLToAGL _first, [], 0, "CAN_COLLIDE"]
            } else {
                "Land_HelipadEmpty_F" createVehicleLocal [0, 0, 0]
            };
            _seeker setPosASL _first;
            if (_radarSeeker) then {
                _seeker setVelocity ((_first vectorFromTo _origin) vectorMultiply AEGISM_STRIKE_SEEKER_SPEED);
                (side _system) reportRemoteTarget [_seeker, AEGISM_STRIKE_SEEKER_SHARE];
            };
            private _gunner = _system turretUnit _turretPath;
            if (!isNil "ace_missileguidance_fnc_onFired") then {
                if (!isNull _gunner) then { _gunner setVariable ["ace_missileguidance_target", _seeker]; };
                _system setVariable ["ace_missileguidance_target", _seeker];
            };
            [_system] call aegism_intercept_fnc_firedHandler;
            _ts set ["capture", [objNull, "strike", [], CBA_missionTime + AEGISM_STRIKE_LAUNCH_WAIT, false, _turretPath, _weaponClass, [_seeker, _aimPos]]];
            [_system, _weaponClass, _turretPath] call BIS_fnc_fire;
            _args set [7, "launched"];
            _args set [8, CBA_missionTime];
            _args set [11, [_seeker, round (_off * 10) / 10]];
        };
    };

    // --- A missile: away, or not ------------------------------------------------
    if (_phase == "launched") exitWith {
        _extra params ["_seeker", "_off"];
        private _capture = _ts getOrDefault ["capture", []];
        // (Taken by the vehicle's Fired handler: it left.)
        if ((_capture param [1, ""]) != "strike") exitWith {
            (format ["-- %1 away, launched %2 deg off its first heading", _weaponClass, _off]) call _fnEnd;
        };
        if (CBA_missionTime - _phaseAt > AEGISM_STRIKE_LAUNCH_WAIT) exitWith {
            _ts deleteAt "capture";
            deleteVehicle _seeker;
            "ended -- it was told to fire and no missile left" call _fnEnd;
        };
    };

    // --- A gun's burst ------------------------------------------------------------
    if (_ammo <= 0 || {CBA_missionTime >= _phaseAt}) exitWith {
        (format ["-- %1 round(s) of %2 fired", (_extra - _ammo) max 0, _weaponClass]) call _fnEnd;
    };
    // (As a burst at anything else is fired: aegism_intercept_fnc_ciwsBurst.)
    (weaponState [_system, _turretPath, _weaponClass]) params ["", "", "", "_loadedMagazine", "_loadedAmmo", ["_reloadPhase", 0]];
    if (_reloadPhase != 0 || {_loadedAmmo <= 0}) exitWith {};
    private _index = (magazinesAllTurrets _system) findIf {
        _x params ["_class", "_path", "_count"];
        _path isEqualTo _turretPath && {_class == _loadedMagazine} && {_count == _loadedAmmo}
    };
    if (_index == -1) exitWith { [_system, _weaponClass, _turretPath] call BIS_fnc_fire; };
    ((magazinesAllTurrets _system) select _index) params ["", "", "", "_id", "_creator"];
    private _gunner = _system turretUnit _turretPath;
    if (_system turretLocal _turretPath) then {
        _system action ["UseMagazine", _system, _gunner, _creator, _id];
    } else {
        [_system, ["UseMagazine", _system, _gunner, _creator, _id]] remoteExec ["action", _system turretOwner _turretPath];
    };
}, 0, [_system, _role, _weaponInfo, _aimPos, _site, _ts, CBA_missionTime, "aim", CBA_missionTime, _shot select 2, -1, ""]] call CBA_fnc_addPerFrameHandler;

[true, ""]
