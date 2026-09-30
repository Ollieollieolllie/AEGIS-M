/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_missileAgility

Description:
    What a missile can do AFTER it leaves the rail -- what decides whether a
    launcher can fire at something it isn't pointing at (a vertical launch
    cell, a turret at its limit, or one still swinging round; aegism_
    intercept_fnc_launchSolution). Not the lock cone before launch
    (missileLockCone): AEGIS-M fires by script and hands the missile its
    target after launch.

        guidance - who steers it:
            "ace" - ACE's scripted guidance: the ammo declares its own
                ace_missileguidance class with enabled = 1, and ACE's
                setting lets AI shots be guided (ace_missileguidance_
                enabled 2) -- as ACE's own Fired handler requires
            "engine" - the game's own (any other guided missile)
            "none" - unguided, or can't be steered: a missile with
                maneuvrability 0 (how ACE hands a missile to its own
                guidance -- ACE's RIM-116 and Stinger) when ACE isn't
                guiding AI shots flies straight
        turn rate - degrees per second it can turn its flight:
            ace - the ammo's ACE pitchRate / yawRate, the lower (ACE turns
                the missile at up to these; 30 if unset, ACE's own default)
            engine - MEASURED: the game's maneuvrability has no unit, so
                the rate comes from AEGIS-M's own missiles in flight
                (aegism_intercept_fnc_interceptorPFH, MISSILE-TURN): the
                fastest sustained turn seen on a flight that had to turn.
                0 until one has.
        post-launch cone - degrees off its flight a target can be and
            still be guided to:
            ace - 180 when it locks on after launch (the SAM default):
                ACE flies it at the target's position, not its seeker's
                view; its seekerAngle (a half-angle) if it must lock on
                before launch
            engine - CfgAmmo missileKeepLockedCone (missileLockCone if
                unset; 180 if neither -- the same fallback as aegism_
                intercept_fnc_weaponKinematics)
    Logged once per missile (AGILITY).

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
    diag_log text format ["[AEGIS-M] t=" + (time toFixed 1) + " AGILITY: %1 -- %2", _ammoClass,
        if (!_guided) then { "unguided" } else {
            format ["ACE guidance declared %1 (turn %2 deg/s, post-launch cone %3 deg); engine guidance %4: post-launch cone %5 deg (missileKeepLockedCone), locks on after launch %6, turn rate measured in flight (MISSILE-TURN).",
                _aceDeclared, _aceRate, _aceCone, ["off (maneuvrability 0)", "on"] select _engineSteers, _keepCone, _loal]
        }];
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
