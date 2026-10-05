/* ----------------------------------------------------------------------------
Function: aegism_detect_fnc_isHostile

Description:
    IFF check: true if _otherSide is hostile to _ownSide per the mission's
    own side relations (getFriend < 0.6, the engine's own enemy threshold).
    A renegade (sideEnemy) is always hostile, as it is to every side in the
    game. Civilian, empty, logic and unknown sides are never hostile -- an empty
    parked aircraft, a civilian helicopter, or an AEGIS-M Site logic must
    never become a contact.

    Used for platforms (so a friendly jet the radar hasn't identified yet,
    getSensorTargets relationship "unknown", isn't shot down -- real IADS
    have IFF) and for munitions (so the battery's own outgoing interceptors
    and friendly artillery are never tracked as incoming threats).

Parameters:
    _ownSide - the defending System's side <SIDE>
    _otherSide - the contact's (or munition shooter's) side <SIDE>

Returns:
    <BOOLEAN>

Examples:
    [side _radar, side _helicopter] call aegism_detect_fnc_isHostile;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_ownSide", "_otherSide"];

private _combatSides = [west, east, independent];
if !(_ownSide in _combatSides) exitWith { false };
// A renegade (side ENEMY: a unit whose rating fell through friendly fire)
// is hostile to everyone, its own former side included. It isn't one of the
// combat sides, so it used to count as never hostile -- a jet that went
// renegade bombing its own side's Site was treated as friendly.
if (_otherSide == sideEnemy) exitWith { true };
if !(_otherSide in _combatSides) exitWith { false };

(_ownSide getFriend _otherSide) < 0.6
