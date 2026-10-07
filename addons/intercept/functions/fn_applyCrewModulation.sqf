/* ----------------------------------------------------------------------------
Function: aegism_intercept_fnc_applyCrewModulation

Description:
    Derives engagement timing and reliability modifiers from a resolved
    Crew/Personality (skill tier x temperament).
    Full notes: docs/functions/intercept.md

Parameters:
    _crew - resolved crew data, from aegism_system_fnc_resolveCrew <HASHMAP>
    _system - optional, the System vehicle; needed for the automated-system
        rule <OBJECT>

Returns:
    Modifiers <HASHMAP>. Keys:
        reactionTime - seconds of hesitation before the first shot at a
            newly-acquired target <NUMBER>
        reliability - probability, 0-1, that the crew gets a clean shot off
            when a fire cycle comes up; a failure costs one fire cycle (see
            aegism_intercept_fnc_engagementLoop) <NUMBER>
        shotIntervalMult - multiplier applied to the doctrine's
            minShotInterval <NUMBER>
        combatReactionMult - multiplier on reactionTime once the crew is
            in combat (crew setting combatReaction, percent: a crew already
            at its stations, weapons free, is quicker onto each next target;
            aegism_intercept_fnc_engagementLoop) <NUMBER>

Examples:
    [_crew, _samLauncher] call aegism_intercept_fnc_applyCrewModulation;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

params ["_crew", ["_system", objNull]];

if (!isNull _system && {unitIsUAV _system} && {!(_crew getOrDefault ["crewOnAutomated", false])}) exitWith {
    createHashMapFromArray [
        ["reactionTime", 0],
        ["reliability", 1],
        ["shotIntervalMult", 1],
        ["combatReactionMult", 1]
    ]
};

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
    ["shotIntervalMult", _shotIntervalMult],
    ["combatReactionMult", ((_crew getOrDefault ["combatReaction", 50]) max 0) / 100]
]
