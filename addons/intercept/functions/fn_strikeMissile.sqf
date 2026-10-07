/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_strikeMissile

Description:
    Flies a surface strike's missile onto its point: what the missile is
    told to chase is held above the point by a share of the ground still to
    cover, so it climbs, then comes down on the point from above.
    Full notes: docs/functions/intercept.md

Parameters:
    _projectile - the missile <OBJECT>
    _seeker - the object it's told to fly at (aegism_intercept_fnc_
        surfaceStrike made it; deleted here when the missile is gone) <OBJECT>
    _aimPos - the point, ASL <ARRAY>

Returns:
    Nothing

Examples:
    [_missile, _seeker, _aimPos] call aegism_intercept_fnc_strikeMissile;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\strike.hpp"

params ["_projectile", "_seeker", "_aimPos"];

if (isNull _projectile) exitWith { deleteVehicle _seeker; };

// The game's own guidance only takes a position for a missile with
// manualControl, which no SAM has: its missile is given the object as its
// target, forced (see notes). A guidance mod's has it from launch.
private _forced = (([typeOf _projectile] call aegism_intercept_fnc_missileAgility) select 0) == "engine";
if (_forced) then {
    private _taken = _projectile setMissileTarget [_seeker, true];
    diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " STRIKE: %1 on grid %2 is flown by the game's own guidance -- the object above its point %3 as its target (its state %4).",
        typeOf _projectile, mapGridPosition _aimPos, if (isNil "_taken") then { "was given" } else { ["was refused", "was taken"] select _taken }, missileState _projectile];
};

// (For a terminal's map: aegism_network_fnc_terminalPicture.)
private _flying = missionNamespace getVariable ["AEGISM_strikeMissiles", []];
_flying = _flying select { !isNull _x && {alive _x} };
_flying pushBack _projectile;
missionNamespace setVariable ["AEGISM_strikeMissiles", _flying];

[{
    params ["_args", "_handle"];
    _args params ["_projectile", "_seeker", "_aimPos", "_nearest", "_passedAt", "_ammo", "_launchedAt", "_moving", "_forced", "_lockState"];

    if (isNull _projectile || {!alive _projectile}) exitWith {
        [_handle] call CBA_fnc_removePerFrameHandler;
        deleteVehicle _seeker;
        diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " STRIKE: %1 on grid %2 ended %3s after launch, having come within %4m of its point.%5",
            _ammo, mapGridPosition _aimPos, (CBA_missionTime - _launchedAt) toFixed 1, round _nearest,
            ["", format [" The game last reported its lock as %1.", [_lockState, "none"] select (_lockState == "")]] select _forced];
    };

    private _position = getPosASLVisual _projectile;
    private _separation = _position distance _aimPos;
    // Past its point (it came near, and is going away): set off there if
    // it came very near; a miss is ended a moment later, not left to fly on.
    if (_separation < _nearest) then {
        _nearest = _separation;
        _passedAt = -1;
    } else {
        if (_passedAt < 0 && {_nearest <= AEGISM_STRIKE_PASS} && {_separation > _nearest + 1}) then { _passedAt = CBA_missionTime; };
    };
    _args set [3, _nearest];
    _args set [4, _passedAt];
    if (_passedAt >= 0 && {_nearest <= AEGISM_STRIKE_FUZE || {CBA_missionTime - _passedAt > AEGISM_STRIKE_OVERFLY}}) exitWith { triggerAmmo _projectile; };

    // What it's told to fly at: above the point by the loft, less as the
    // ground still to cover shrinks.
    private _chase = _aimPos vectorAdd [0, 0, AEGISM_STRIKE_SEEKER_HEIGHT + AEGISM_STRIKE_LOFT_AT(_position distance2D _aimPos)];
    _seeker setPosASL _chase;
    // (A radar seeker's: kept moving along the line to the missile, toward
    // it -- up, off the ground. aegism_intercept_fnc_surfaceStrike.)
    if (_moving) then { _seeker setVelocity ((_chase vectorFromTo _position) vectorMultiply AEGISM_STRIKE_SEEKER_SPEED); };
    // (Taken only by a missile with manualControl; every other follows
    // the object.)
    _projectile setMissileTargetPos (ASLToAGL _chase);
    // (The game's own guidance: the object, given again if it has let go.)
    if (_forced) then {
        if ((missileTarget _projectile) != _seeker) then { _projectile setMissileTarget [_seeker, true]; };
        _args set [9, (missileState _projectile) param [1, ""]];
    };
}, 0, [_projectile, _seeker, _aimPos, 1e10, -1, typeOf _projectile, CBA_missionTime, (typeOf _seeker) isKindOf ["Default", configFile >> "CfgAmmo"], _forced, ""]] call CBA_fnc_addPerFrameHandler;
