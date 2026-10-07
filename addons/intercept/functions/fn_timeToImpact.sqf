/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_timeToImpact

Description:
    Seconds until a contact reaches the Site: the urgency the coordinator
    orders engagements by ("Soonest Impact" Target Priority), queues a
    launcher's targets by, and checks every queued shot against.
    Full notes: docs/functions/intercept.md

Parameters:
    _object - the contact <OBJECT>
    _class - its threat class (aegism_detect_fnc_classifyTarget) <STRING>
    _positions - ASL positions of the vehicles it threatens <ARRAY>

Returns:
    Seconds <NUMBER>

Examples:
    [_rocket, "artilleryShell", _memberPositions] call aegism_intercept_fnc_timeToImpact;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#define AEGISM_GRAVITY 9.80665
#define AEGISM_NOT_COMING 1e10

params ["_object", "_class", "_positions"];

if (isNull _object || {_positions isEqualTo []}) exitWith { AEGISM_NOT_COMING };

private _pos = getPosASL _object;
private _velocity = velocity _object;

if (_class in ["artilleryShell", "rocket", "bomb"]) then {
    private _vz = _velocity select 2;
    private _soonest = AEGISM_NOT_COMING;
    {
        private _disc = _vz * _vz + 2 * AEGISM_GRAVITY * ((_pos select 2) - (_x select 2));
        if (_disc >= 0) then {
            private _t = (_vz + sqrt _disc) / AEGISM_GRAVITY;
            if (_t > 0) then { _soonest = _soonest min _t; };
        };
    } forEach _positions;
    _soonest
} else {
    private _nearest = _positions select 0;
    { if ((_pos distance _x) < (_pos distance _nearest)) then { _nearest = _x; }; } forEach _positions;
    private _closing = _velocity vectorDotProduct (_pos vectorFromTo _nearest);
    // if/else, not [a, b] select: both elements of an array literal are
    // evaluated, so a hovering contact (closing speed 0) divided by zero.
    if (_closing > 0) then { (_pos distance _nearest) / _closing } else { AEGISM_NOT_COMING }
}
