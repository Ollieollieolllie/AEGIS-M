/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_defaultCrew

Description:
    Hardcoded fallback personality for a System with no directly-set or
    Site-inherited one.
    Full notes: docs/functions/modules_system.md

Parameters:
    None

Returns:
    Default crew data <HASHMAP>. Keys:
        skillTier - "green" | "regular" | "veteran" | "elite" <STRING>
        temperament - "cautious" | "standard" | "aggressive" | "nervous" <STRING>
        costValueJudgment - optional saturation heuristic toggle <BOOLEAN>
        crewOnAutomated - apply the crew model to automated (UAV-crewed)
            systems too; off = they never hesitate or skip <BOOLEAN>
        combatReaction - percent of its reaction time a crew takes on each
            new target once in combat <NUMBER>

Examples:
    [] call aegism_system_fnc_defaultCrew;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

createHashMapFromArray [
    ["skillTier", "regular"],
    ["temperament", "standard"],
    ["costValueJudgment", false],
    ["crewOnAutomated", false],
    ["combatReaction", 50]
]
