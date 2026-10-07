/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_interceptHit

Description:
    Detonates an interceptor that has reached its target, and a munition
    target with it.
    Full notes: docs/functions/intercept.md

Parameters:
    _projectile - the interceptor <OBJECT>
    _target - its target <OBJECT>
    _isMunitionTarget - the target is a munition <BOOLEAN>
    _minDistance - closest approach, m (for the log): to a munition's body
        (aegism_intercept_fnc_bodyPass), an aircraft's centre <NUMBER>
    _hitRadius - the radius it was inside, m (for the log): the round's
        blast or proximity fuse <NUMBER>
    _at - optional: where it went off, ASL, if it's already gone <ARRAY>
    _ammo - optional: its ammo class, if it's already gone <STRING>

Returns:
    Nothing

Examples:
    [_round, _shell, true, 0.8, 1.2] call aegism_intercept_fnc_interceptHit;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_projectile", "_target", "_isMunitionTarget", "_minDistance", "_hitRadius", ["_at", []], ["_ammo", ""]];

private _gone = isNull _projectile || {!alive _projectile};
if (_ammo == "") then { _ammo = typeOf _projectile; };

// Where: from the vehicle that fired it, and the height above the ground.
private _shooter = if (isNull _projectile) then { objNull } else { (getShotParents _projectile) param [0, objNull] };
private _where = if (_at isEqualTo []) then { getPosASL _projectile } else { _at };
private _whereText = format ["%1m up", round ((ASLToAGL _where) select 2)];
if (!isNull _shooter) then { _whereText = format ["%1m from %2, %3", round ((getPosASL _shooter) distance _where), _shooter, _whereText]; };

// The munition first, then the interceptor's own blast.
private _targetAt = getPosASL _target;
private _targetBlast = getNumber (configOf _target >> "indirectHitRange");
private _targetType = typeOf _target;
if (_isMunitionTarget) then { [_target] call aegism_detect_fnc_destroyMunition; };
if (!_gone) then { triggerAmmo _projectile; };
diag_log text format ["[AEGIS-M] t=" + (CBA_missionTime toFixed 1) + " INTERCEPT: %1 hit %2 at %3 (%4%5).", _ammo, _target, _whereText,
    if (_isMunitionTarget) then {
        format ["passed %1m from its body, within the round's %2m", (_minDistance max 0) toFixed 2, _hitRadius toFixed 2]
    } else {
        format ["closest %1m, hit radius %2m", (_minDistance max 0) toFixed 2, _hitRadius toFixed 2]
    },
    ["", "; the game's own fuse set it off first"] select _gone];

// The rockets beside it: caught in either blast.
if (_isMunitionTarget) then {
    [_where, getNumber (configFile >> "CfgAmmo" >> _ammo >> "indirectHitRange"), _ammo, [_target]] call aegism_detect_fnc_blastMunitions;
    [_targetAt, _targetBlast, format ["%1 (the munition it destroyed)", _targetType], [_target]] call aegism_detect_fnc_blastMunitions;
};
