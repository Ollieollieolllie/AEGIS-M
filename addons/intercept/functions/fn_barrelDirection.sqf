/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_barrelDirection

Description:
    World-space unit vector a System weapon's barrel (or missile rail)
    currently points along.

    weaponDirection is tried first. It looks the weapon up by NAME, and for
    some turrets it returns [0,0,0] -- e.g. the POOK C-RAM's second turret
    (LF_Turret, pook_SAM_M2HB): every alignment check against a zero vector
    reads exactly 90 degrees, so that gun logged "barrel 90 deg off" forever
    and never fired. The fallback reads the specific turret's own barrel
    memory points from its config (gunBeg/gunEnd, or missileBeg/missileEnd
    for a launcher) -- beginning (muzzle) minus end (breech) -- which follow
    the turret's animation.

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - the weapon's turret path <ARRAY>
    _weaponClass - CfgWeapons class <STRING>

Returns:
    Unit direction vector, world space; [0,0,0] if it can't be determined <ARRAY>

Examples:
    [_cram, [1], "pook_SAM_M2HB"] call aegism_intercept_fnc_barrelDirection;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath", "_weaponClass"];

private _direction = _system weaponDirection _weaponClass;
if (_direction isNotEqualTo [0, 0, 0]) exitWith { _direction };

private _turretCfg = [_system, _turretPath] call CBA_fnc_getTurret;
{
    _x params ["_begKey", "_endKey"];
    private _beg = getText (_turretCfg >> _begKey);
    private _end = getText (_turretCfg >> _endKey);
    if (_beg != "" && {_end != ""}) then {
        private _axis = (_system selectionPosition [_beg, "Memory"]) vectorDiff (_system selectionPosition [_end, "Memory"]);
        if (_axis isNotEqualTo [0, 0, 0] && {_direction isEqualTo [0, 0, 0]}) then {
            _direction = vectorNormalized (_system vectorModelToWorldVisual _axis);
        };
    };
} forEach [["gunBeg", "gunEnd"], ["missileBeg", "missileEnd"]];

_direction
