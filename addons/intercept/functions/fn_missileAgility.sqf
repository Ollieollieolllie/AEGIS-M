/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileAgility

Description:
    What a missile can do after it leaves the rail: who steers it, its turn
    rate and its post-launch cone.
    Full notes: docs/functions/intercept.md

Parameters:
    _ammoClass - CfgAmmo class <STRING>

Returns:
    [guidance <STRING>, turn rate deg/s (0 = not known yet) <NUMBER>,
     where the rate comes from <STRING>, post-launch cone deg <NUMBER>] <ARRAY>

Examples:
    ["ammo_Missile_mim145"] call aegism_intercept_fnc_missileAgility;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\rpt.hpp"

params ["_ammoClass"];

private _cache = missionNamespace getVariable "AEGISM_cacheAgility";
if (isNil "_cache") then {
    _cache = createHashMap;
    missionNamespace setVariable ["AEGISM_cacheAgility", _cache];
};

// Config part, read once.
private _config = _cache get _ammoClass;
if (isNil "_config") then {
    private _ammoCfg = configFile >> "CfgAmmo" >> _ammoClass;
    private _guided = (toLower getText (_ammoCfg >> "simulation")) == "shotmissile";
    // ACE's own test: the class declared on the ammo itself, not inherited.
    private _aceCfg = _ammoCfg >> "ace_missileguidance";
    private _aceDeclared = ("configName _x == 'ace_missileguidance'" configClasses _ammoCfg) isNotEqualTo [] && {(getNumber (_aceCfg >> "enabled")) == 1};
    private _aceRate = 30;
    if (isNumber (_aceCfg >> "pitchRate")) then { _aceRate = (getNumber (_aceCfg >> "pitchRate")) min (getNumber (_aceCfg >> "yawRate")); };
    private _aceCone = if ((getText (_aceCfg >> "defaultSeekerLockMode")) == "LOBL") then { getNumber (_aceCfg >> "seekerAngle") } else { 180 };
    private _keepCone = getNumber (_ammoCfg >> "missileKeepLockedCone");
    if (_keepCone <= 0) then { _keepCone = getNumber (_ammoCfg >> "missileLockCone"); };
    if (_keepCone <= 0) then { _keepCone = 180; };
    private _loal = (getNumber (_ammoCfg >> "autoSeekTarget")) == 1 || {((getArray (_ammoCfg >> "flightProfiles")) findIf { ((toLower _x) find "loal") == 0 }) != -1};
    private _engineSteers = (getNumber (_ammoCfg >> "maneuvrability")) > 0;
    _config = [_guided, _aceDeclared, _aceRate, _aceCone, _keepCone, _loal, _engineSteers];
    _cache set [_ammoClass, _config];
    if (AEGISM_RPT_VERBOSE) then {
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " AGILITY: %1 -- %2", _ammoClass,
            if (!_guided) then { "unguided" } else {
                format ["ACE guidance declared %1 (turn %2 deg/s, post-launch cone %3 deg); engine guidance %4: post-launch cone %5 deg (missileKeepLockedCone), locks on after launch %6, turn rate measured in flight (MISSILE-TURN).",
                    _aceDeclared, _aceRate, _aceCone, ["off (maneuvrability 0)", "on"] select _engineSteers, _keepCone, _loal]
            }];
    };
};
_config params ["_guided", "_aceDeclared", "_aceRate", "_aceCone", "_keepCone", "", "_engineSteers"];

if (!_guided) exitWith { ["none", 0, "unguided", 0] };

// Live: ACE's setting can change during a mission.
if (_aceDeclared && {!isNil "ace_missileguidance_fnc_onFired"} && {(missionNamespace getVariable ["ace_missileguidance_enabled", 0]) >= 2}) exitWith {
    ["ace", _aceRate, "ACE guidance config", _aceCone]
};
if (!_engineSteers) exitWith { ["none", 0, "maneuvrability 0 and ACE isn't guiding AI shots", 0] };

private _measured = (missionNamespace getVariable ["AEGISM_missileTurn", createHashMap]) getOrDefault [_ammoClass, [0, 0, 0]];
_measured params ["_flights", "_turnedFlights", "_rate"];
if (_turnedFlights > 0 && {_rate > 0}) exitWith {
    ["engine", _rate, format ["measured over %1 turning flight(s)", _turnedFlights], _keepCone]
};
["engine", 0, "not measured yet", _keepCone]
