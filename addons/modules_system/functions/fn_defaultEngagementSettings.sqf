/* ----------------------------------------------------------------------------
Function: aegism_system_fnc_defaultEngagementSettings

Description:
    Hardcoded fallback doctrine used by a System with no directly-set or
    Site-inherited Doctrine data (AEGISM_Module_Site's own Attributes), so
    a standalone vehicle with just a role checked -- no Site module synced
    at all -- remains fully functional.

Parameters:
    None

Returns:
    Default engagement settings data <HASHMAP>. Keys:
        minRange, maxRange, minAltitude, maxAltitude - real-world base
            metres, resolved through aegism_fnc_scaledRange by callers <NUMBER>
        targetPriority - "nearest" | "fastestClosing" | "highestValue" <STRING>
        salvoSize - rounds fired per engagement <NUMBER>
        minShotInterval - seconds between shots in a salvo <NUMBER>
        targetClassAllowlist - permitted contact classes <ARRAY of STRING>

Examples:
    [] call aegism_system_fnc_defaultEngagementSettings;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

createHashMapFromArray [
    ["minRange", 500],
    ["maxRange", 8000],
    ["minAltitude", 0],
    ["maxAltitude", 6000],
    ["targetPriority", "nearest"],
    ["salvoSize", 1],
    ["minShotInterval", 4],
    ["targetClassAllowlist", ["missile", "rocket", "fixedWing", "helicopter", "drone"]]
]
