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
        minRange, maxRange - extra LAUNCHER range limits (real-world base
            metres, resolved through aegism_fnc_scaledRange by callers),
            applied on top of each missile's own real envelope; maxRange 0 =
            no doctrine cap <NUMBER>
        ciwsMaxRange - extra CIWS range cap, same units; 0 = the gun's own
            config reach <NUMBER>
        minAltitude, maxAltitude - height above ground, metres; maxAltitude
            0 = no cap <NUMBER>
        targetPriority - "nearest" | "fastestClosing" | "highestValue" <STRING>
        salvoSize - rounds fired per engagement <NUMBER>
        minShotInterval - seconds between two missiles from one launcher;
            0 = Auto, each launcher's own config fire rate (aegism_intercept_
            fnc_launcherInterval) <NUMBER>
        ciwsBurstMin, ciwsBurstMax - CIWS sustained-burst length, seconds;
            each burst picks a random length in this range <NUMBER>
        ciwsBurstPause - seconds a CIWS gun pauses between bursts <NUMBER>
        ciwsMinElevation - degrees; a CIWS gun never engages a target below,
            or fires with its barrel below, this elevation <NUMBER>
        engageFriendlyThreats - also engage friendly/neutral munitions that
            are predicted to hit the Site <BOOLEAN>
        friendlyThreatRadius - metres from a Site member a friendly
            munition's predicted impact must fall within to count as a
            threat; 0 = the munition's own config dangerRadiusHit <NUMBER>
        targetClassAllowlist - permitted contact classes <ARRAY of STRING>

Examples:
    [] call aegism_system_fnc_defaultEngagementSettings;

Author:
    Snow(Dryden)
---------------------------------------------------------------------------- */

createHashMapFromArray [
    ["minRange", 0],
    ["maxRange", 0],
    ["ciwsMaxRange", 0],
    ["minAltitude", 0],
    ["maxAltitude", 0],
    ["targetPriority", "soonestImpact"],
    ["salvoSize", 1],
    ["minShotInterval", 0],
    ["ciwsBurstMin", 3],
    ["ciwsBurstMax", 5],
    ["ciwsBurstPause", 1],
    ["ciwsMinElevation", 5],
    ["engageFriendlyThreats", true],
    ["friendlyThreatRadius", 0],
    ["targetClassAllowlist", ["missile", "rocket", "bomb", "artilleryShell", "fixedWing", "helicopter", "drone"]],
    ["ciwsLastResort", false]
]
