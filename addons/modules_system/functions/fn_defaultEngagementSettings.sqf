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
        maxOffBoreSwing, maxOffBoreLimit - degrees; the most a launcher that
            can move may launch off the intercept and leave the missile to
            turn (aegism_intercept_fnc_launchSolution): while its turret is
            still swinging round, and once the turret is as close as it can
            get (at its elevation or traverse limit, or a mount that can't
            move on one axis). A fixed mount -- a vertical launch cell -- is
            exempt: it can't do otherwise <NUMBER>
        ciwsBurstMin, ciwsBurstMax - CIWS sustained-burst length, seconds;
            each burst picks a random length in this range <NUMBER>
        ciwsBurstPause - seconds a CIWS gun pauses between bursts <NUMBER>
        ciwsMinElevation - degrees; a CIWS gun never engages a target below,
            or fires with its barrel below, this elevation <NUMBER>
        ciwsOpenFireChance - percent; a CIWS gun only fires where one burst
            is at least this likely to hit, from its measured accuracy and
            the round's flight (aegism_intercept_fnc_openFireRange); 0 = its
            full reach <NUMBER>
        ciwsCueAhead - seconds; a CIWS gun is assigned a target this long
            before it comes into reach, so it's reacted and on it by then
            (aegism_intercept_fnc_canEngage); 0 = only once in reach <NUMBER>
        ciwsMinWindow - seconds; a CIWS gun is only given an incoming
            munition it has this long to fire at before impact; one with
            less is a last-ditch shot, taken only with nothing better
            (aegism_intercept_fnc_assignEngagements); 0 = any it can reach
            in time <NUMBER>
        engageFriendlyThreats - also engage friendly/neutral munitions that
            are predicted to hit the Site <BOOLEAN>
        engageOnlyThreats - a hostile artillery round or rocket is only
            engaged while predicted to land within the threat radius of a
            Site vehicle (aegism_detect_fnc_munitionCheck) <BOOLEAN>
        friendlyThreatRadius - metres from a Site member a friendly
            munition's predicted impact must fall within to count as a
            threat; 0 = the munition's own config dangerRadiusHit <NUMBER>
        protectRadius - a Site's protected area: metres round its module
            inside which a hostile munition landing, or guided at anything,
            is a threat (aegism_detect_fnc_munitionThreat); 0 = only the
            Site's vehicles. A Site's own setting, not a vehicle's (a
            standalone vehicle has no area) <NUMBER>
        targetClassAllowlist - permitted contact classes <ARRAY of STRING>
        ciwsLastResort - a CIWS gun holds while a launcher covers the
            contact <BOOLEAN>
        ciwsSelfDestruct - a CIWS round that hits nothing detonates just
            before its lifetime runs out (aegism_intercept_fnc_
            ciwsSelfDestruct) <BOOLEAN>
        emcon - Radar Emission: "auto" (Automatic) | "ai" (the AI
            decides) | "on" | "cued" (silent until cued) | "intermittent"
            (aegism_system_fnc_emconUpdate) <STRING>
        emconHold - seconds a cued radar stays lit after the last contact
            in its coverage <NUMBER>
        emconBurstOn, emconBurstOff - search bursts (Intermittent, and
            Automatic while quiet): seconds on, then
            seconds off <NUMBER>
        radarHoldSector - the Site's turning radars hold their sectors still
            when their arcs cover them (aegism_system_fnc_radarSchedule);
            false: they swing across them regardless <BOOLEAN>
        armShutdown - a radar shuts down while an anti-radiation missile is
            inbound on it, in every Radar Emission mode <BOOLEAN>

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
    ["maxOffBoreSwing", 20],
    ["maxOffBoreLimit", 30],
    ["ciwsBurstMin", 3],
    ["ciwsBurstMax", 5],
    ["ciwsBurstPause", 1],
    ["ciwsMinElevation", 5],
    ["ciwsOpenFireChance", 40],
    ["ciwsCueAhead", 5],
    ["ciwsMinWindow", 3],
    ["engageFriendlyThreats", true],
    ["engageOnlyThreats", true],
    ["friendlyThreatRadius", 0],
    ["protectRadius", 750],
    ["targetClassAllowlist", ["missile", "rocket", "bomb", "artilleryShell", "fixedWing", "helicopter", "drone"]],
    ["ciwsLastResort", false],
    ["ciwsSelfDestruct", false],
    ["emcon", "auto"],
    ["emconHold", 10],
    ["emconBurstOn", 5],
    ["emconBurstOff", 15],
    ["armShutdown", true],
    ["radarHoldSector", false]
]
