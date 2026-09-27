/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_defaultCrew

Description:
    Hardcoded fallback personality used by a System (or unmanned Launcher/
    CIWS) with no directly-synced or Network-inherited AEGISM_Module_Crew,
    so unmanned/uncrewed point-defense still behaves per a sane baseline
    rather than having no engagement decision logic at all.

Parameters:
    None

Returns:
    Default crew data <HASHMAP>. Keys:
        skillTier - "green" | "regular" | "veteran" | "elite" <STRING>
        temperament - "cautious" | "standard" | "aggressive" | "nervous" <STRING>
        costValueJudgment - optional saturation heuristic toggle <BOOLEAN>

Examples:
    [] call aegism_system_fnc_defaultCrew;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

createHashMapFromArray [
    ["skillTier", "regular"],
    ["temperament", "standard"],
    ["costValueJudgment", false]
]
