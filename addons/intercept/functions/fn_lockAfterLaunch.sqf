/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_lockAfterLaunch

Description:
    Whether a launcher's missile is fired to lock on after launch and isn't
    flown by ACE's guidance: one that takes no surface strike.
    Full notes: docs/functions/intercept.md

Parameters:
    _weaponClass - CfgWeapons class <STRING>
    _magazineClass - CfgMagazines class <STRING>

Returns:
    [fired to lock on after launch and not flown by ACE's guidance
     <BOOLEAN>, the flight profile it's fired in ("" if it locks before
     launch) <STRING>] <ARRAY>

Examples:
    ["weapon_mim145Launcher", "magazine_Missile_mim145_x4"] call aegism_intercept_fnc_lockAfterLaunch;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_weaponClass", "_magazineClass"];

private _cache = missionNamespace getVariable "AEGISM_cacheLockAfterLaunch";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheLockAfterLaunch", _cache];
};

// Config part, read once: [ammo class, flight profile, logged].
private _key = _weaponClass + "|" + _magazineClass;
private _config = _cache get _key;
if (isNil "_config") then {
    private _ammoClass = ([_weaponClass, _magazineClass] call aegism_intercept_fnc_weaponKinematics) select 0;
    // The profile it's fired in: the weapon's first fire mode, where the
    // ammo has a flight profile of that name (see notes).
    private _mode = (getArray (configFile >> "CfgWeapons" >> _weaponClass >> "modes")) param [0, ""];
    private _profile = "";
    if (((toLower _mode) find "loal") == 0 && {((getArray (configFile >> "CfgAmmo" >> _ammoClass >> "flightProfiles")) findIf { _x == _mode }) != -1}) then { _profile = _mode; };
    _config = [_ammoClass, _profile, false];
    _cache set [_key, _config];
};
_config params ["_ammoClass", "_profile", "_logged"];

if (_profile == "") exitWith { [false, ""] };
// Live: ACE's setting can change during a mission.
if ((([_ammoClass] call aegism_intercept_fnc_missileAgility) select 0) == "ace") exitWith { [false, _profile] };

if (!_logged) then {
    _config set [2, true];
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " LOCK-AFTER-LAUNCH: %1 (%2) is fired in its %3 mode and isn't flown by ACE's guidance. Not offered for a surface strike: the game doesn't send it to a point.",
        _weaponClass, _ammoClass, _profile];
};

[true, _profile]
