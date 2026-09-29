/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_turretCanPoint

Description:
    Whether a turret can physically elevate to a world direction: the
    direction taken into the vehicle's own model space (so a vehicle on a
    slope is handled) and checked against the turret config's own elevation
    limits, minElev/maxElev. (Traverse limits, minTurn/maxTurn, aren't
    checked: their reference direction and sign aren't verified here, and a
    wrong guess would reject targets the turret can reach.)

    Why: a CIWS whose aim point was beyond its travel could never get its
    barrel within tolerance, so it held fire on that target until the target
    landed. The Praetorian 1C (B_AAA_System_01_F, maxElev 85) sat with its
    barrel pinned 1.5-4 degrees short of shells coming down steeply beside
    it for over 5s each, while other shells it could have reached got
    through.

Parameters:
    _system - the vehicle <OBJECT>
    _turretPath - turret path <ARRAY>
    _direction - world-space direction to point along <ARRAY>

Returns:
    [can point <BOOLEAN>, elevation deg, min elevation deg, max elevation
     deg] -- elevation of the direction in the vehicle's own frame <ARRAY>

Examples:
    [_praetorian, [0], _origin vectorFromTo _aimPoint] call aegism_intercept_fnc_turretCanPoint;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_system", "_turretPath", "_direction"];

private _turretCfg = [_system, _turretPath] call CBA_fnc_getTurret;
private _local = vectorNormalized (_system vectorWorldToModelVisual _direction);
private _elevation = asin (((_local select 2) max -1) min 1);

private _minElevation = getNumber (_turretCfg >> "minElev");
private _maxElevation = getNumber (_turretCfg >> "maxElev");

[_elevation >= _minElevation && {_elevation <= _maxElevation}, _elevation, _minElevation, _maxElevation]
