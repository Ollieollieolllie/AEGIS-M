/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_ciwsTrack

Description:
    Keeps a CIWS gun's turret on its intercept point EVERY FRAME for as long
    as it has a target, not just while a burst is running: re-aims
    (aegism_intercept_fnc_aimWeapon) each frame at the target the engagement
    loop last handed it ("AEGISM_ciwsTrackTarget_<turretPath>" [target,
    weaponInfo, time], refreshed every engagement tick).

    Why: between bursts -- and before the first one -- the turret was only
    re-aimed at the engagement loop's 0.1s tick, chasing a lead point that
    jumped every tick. Against a shell close in and crossing fast, it
    trailed by more than the fire gate allows, so the first burst never
    opened: a Praetorian followed a 155mm shell to the ground 0.5 degrees
    off the aim point without firing a round.

    One handler per turret ("AEGISM_ciwsTracking_<turretPath>"); it stops
    once the engagement loop stops refreshing its target (the engagement
    was released) for longer than AEGISM_TRACK_STALE, or the target dies.

Parameters:
    _system - the CIWS vehicle <OBJECT>
    _turretPath - its gun's turret path <ARRAY>

Returns:
    Nothing

Examples:
    [_praetorian, [0]] call aegism_intercept_fnc_ciwsTrack;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_TRACK_STALE 0.5

params ["_system", "_turretPath"];

private _runningKey = format ["AEGISM_ciwsTracking_%1", _turretPath];
if (_system getVariable [_runningKey, false]) exitWith {};
_system setVariable [_runningKey, true, false];

[{
    params ["_args", "_pfhHandle"];
    _args params ["_system", "_turretPath", "_runningKey"];

    if (isNull _system || {!alive _system}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
    };
    (_system getVariable [format ["AEGISM_ciwsTrackTarget_%1", _turretPath], [objNull, [], -1e9]]) params ["_target", "_weaponInfo", "_handedAt"];
    if (time - _handedAt > AEGISM_TRACK_STALE || {isNull _target} || {!alive _target}) exitWith {
        [_pfhHandle] call CBA_fnc_removePerFrameHandler;
        _system setVariable [_runningKey, false, false];
    };
    [_system, _target, _weaponInfo, "ciws"] call aegism_intercept_fnc_aimWeapon;
}, 0, [_system, _turretPath, _runningKey]] call CBA_fnc_addPerFrameHandler;
