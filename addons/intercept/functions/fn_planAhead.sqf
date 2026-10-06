/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_planAhead

Description:
    Works out, between the Site coordinator's turns, the launcher shots of
    the munitions whose look its last run put off (it had worked out AEGISM_
    PLAN_STEPS new steps already, aegism_intercept_fnc_assignEngagements):
    the questions kept on the Site ("AEGISM_planLeft") are asked, soonest
    impact first, for AEGISM_PLAN_BUDGET s a frame, and what's still
    unanswered is kept for the next frame. Nothing is decided here -- the
    answers go into the Site's plan cache, where the coordinator's next turn
    finds them.

    A salvo coming into view costs several short frames this way instead of
    one long one. The coordinator's first way of spreading it was to run
    itself again the next frame: with its whole sweep of every contact and
    weapon each time, that cost four times what it saved (85 of 121 runs in
    10 s, 2.4 s of server time, 2026-10-06). Its second was to cut its own
    questions short and decide nothing for those munitions until this had
    answered them: under a salvo the newest rockets waited 15-20 s for their
    first look (2026-10-06). Now a run never waits on this: a munition it
    looks at, it works out in full, with whatever this has ready.

    A question whose munition is urgent by now (AEGISM_URGENT_TTI) is dropped:
    the coordinator looks at those on every run.

Parameters:
    _logic - the Site logic (its linked group's lead) <OBJECT>

Returns:
    Nothing

Examples:
    [_site] call aegism_intercept_fnc_planAhead;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

#include "..\..\main\perf.hpp"
#include "..\..\main\coordinator.hpp"

params ["_logic"];

private _startedAt = diag_tickTime;
private _left = _logic getVariable ["AEGISM_planLeft", []];
private _planCache = _logic getVariable ["AEGISM_planCache", createHashMap];
// This frame's plan work (aegism_intercept_fnc_planShot): no new step is
// begun once its time is up.
private _plan = [_planCache, _startedAt + AEGISM_PLAN_BUDGET, 0, []];
private _stillLeft = _plan select 3;
{
    _x params ["_candSystem", "_weaponInfo", "_bounds", "_object", "_ballistic", "_startAt", "_impactAt", "_key"];
    if (!isNull _object && {alive _object} && {!isNull _candSystem} && {alive _candSystem} && {_impactAt - CBA_missionTime > AEGISM_URGENT_TTI}) then {
        [_candSystem, _weaponInfo, _bounds, _object, _ballistic, (_startAt - CBA_missionTime) max 0, _impactAt - CBA_missionTime, _key, _plan] call aegism_intercept_fnc_planShot;
    };
    // This frame's time is spent -- on new steps (a question cut short), or
    // on going through questions already answered: the rest wait as they are.
    if (_stillLeft isNotEqualTo [] || {diag_tickTime - _startedAt > AEGISM_PLAN_BUDGET}) exitWith {
        _stillLeft append (_left select [_forEachIndex + 1]);
    };
} forEach _left;

_logic setVariable ["AEGISM_planLeft", _stillLeft, false];
if (_stillLeft isEqualTo []) then { _logic setVariable ["AEGISM_assignMore", false, false]; };

PERF_INC(PERF_COORD_CARRIED);
PERF_ADD(PERF_COORD_AHEAD_MS,(diag_tickTime - _startedAt) * 1000);
