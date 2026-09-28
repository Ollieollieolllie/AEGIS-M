/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_applyCrewModulation

Description:
    Derives engagement timing/reliability modifiers from a resolved
    Crew/Personality data (skillTier x temperament, from AEGISM_Module_
    Site's own Attributes), per the AEGIS-M
    README's description of Crew as modulating "the linked doctrine's
    timing and reliability rather than owning its own numbers" -- the
    engagement loop and fire/guidance functions never read skillTier or
    temperament directly, they call this once and use the returned
    modifiers.

    skillTier sets the baseline reaction time (seconds of hesitation after
    a target is first acquired, before the first shot) and baseline
    reliability (probability the crew gets a clean fire command off on a
    given cycle at all, see aegism_intercept_fnc_fireWeapon -- the actual
    hit-or-miss outcome from there is the game's own weapon/AI simulation,
    not anything AEGIS-M fakes). temperament then scales both, plus how
    eagerly the crew re-engages within a salvo (shotIntervalMult, applied
    to the doctrine's minShotInterval): aggressive/nervous crews shoot
    faster but sloppier, cautious crews are slower but steadier, standard
    is a neutral 1x baseline.

Parameters:
    _crew - resolved crew data, from aegism_system_fnc_resolveCrew <HASHMAP>

Returns:
    Modifiers <HASHMAP>. Keys:
        reactionTime - seconds of hesitation before the first shot at a
            newly-acquired target <NUMBER>
        reliability - probability, 0-1, that the crew gets a clean shot off
            when a fire cycle comes up; a failure costs one fire cycle (see
            aegism_intercept_fnc_engagementLoop) <NUMBER>
        shotIntervalMult - multiplier applied to the doctrine's
            minShotInterval <NUMBER>

Examples:
    [_crew] call aegism_intercept_fnc_applyCrewModulation;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_crew"];

private _skillTier = _crew getOrDefault ["skillTier", "regular"];
private _temperament = _crew getOrDefault ["temperament", "standard"];

private _skillBase = switch (_skillTier) do {
    case "green": { [4.0, 0.55] };
    case "veteran": { [1.2, 0.85] };
    case "elite": { [0.5, 0.95] };
    default { [2.5, 0.70] }; // "regular"
};
_skillBase params ["_baseReactionTime", "_baseReliability"];

// [reactionMult, reliabilityMult, shotIntervalMult]
private _temperamentMods = switch (_temperament) do {
    case "cautious": { [1.3, 1.05, 1.2] };
    case "aggressive": { [0.7, 0.95, 0.8] };
    case "nervous": { [0.6, 0.85, 0.75] };
    default { [1.0, 1.0, 1.0] }; // "standard"
};
_temperamentMods params ["_reactionMult", "_reliabilityMult", "_shotIntervalMult"];

createHashMapFromArray [
    ["reactionTime", _baseReactionTime * _reactionMult],
    ["reliability", (_baseReliability * _reliabilityMult) min 1],
    ["shotIntervalMult", _shotIntervalMult]
]
