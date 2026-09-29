/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretState

Description:
    One weapon turret's runtime state: a HashMap, created on first use, kept
    in the System's "AEGISM_turrets" (turret path -> state). Everything AEGIS-M
    tracks per turret lives here, instead of one string-keyed object variable
    per value (which cost a format call per read, several per aim).

    Keys (all optional; readers use getOrDefault):
        lockAt - last time the turret was locked on an aim point
        ciwsAimAt - last CIWS aim (a launcher on a shared turret yields to it)
        aim_ciws / aim_launcher - latest alignment record, per role:
            [angle, tolerance, time, target, feasible, aligned, aimPoint]
        solve - CIWS: latest full aim solve, steered from every frame
            (aegism_intercept_fnc_ciwsTrack)
        trend - launcher: [angle, target, ticks not closing]
        settle - CIWS: [target, best angle, time it last improved]
        lastDitchLogged / lastDitchHeld - CIWS: target last logged
        correction - CIWS spotting correction [lead s, elevation rad]
        track - CIWS: [time, position, velocity, acceleration] the aim was
            solved against, and trackTof: its flight time
        estimate - CIWS spotting estimates, target class -> HashMap
        spotStats - CIWS: burstId -> per-burst spotting stats
        spotSeq - CIWS: rounds fired, for spotting every Nth one
        burst - CIWS: [endsAt, target, burstId]
        tickAt - CIWS: last engagement tick that worked this turret
        trackTarget / tracking - CIWS per-frame tracker target and flag
        rounds / roundsRunning - CIWS rounds in flight (aegism_intercept_fnc_
            ciwsRounds)
        magazineId - CIWS: [magazine id, owner, ammo] for direct fire
        shotAt, holdUntil, spacing, shots, intervalLogged - launcher timing
        capture - fire context for the rounds this turret produces
        fireHold - debug hold (aegism_intercept_fnc_debugSetFireHold)
        standalone_launcher / standalone_ciws - a standalone System's own
            engagement state for this turret, and inFlight_launcher: its
            salvos still flying

Parameters:
    _system - the System vehicle <OBJECT>
    _turretPath - turret path <ARRAY>

Returns:
    The turret's state <HASHMAP>

Examples:
    ([_praetorian, [0]] call aegism_intercept_fnc_turretState) get "aim_ciws";

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath"];

private _all = _system getVariable "AEGISM_turrets";
if (isNil "_all") then {
    _all = createHashMap;
    _system setVariable ["AEGISM_turrets", _all, false];
};
private _state = _all get _turretPath;
if (isNil "_state") then {
    _state = createHashMap;
    _all set [_turretPath, _state];
};
_state
