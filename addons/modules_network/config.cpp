class CfgPatches
{
    class aegism_modules_network
    {
        units[] = {"AEGISM_Module_Site"};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main", "aegism_intercept", "aegism_modules_system", "A3_Modules_F", "A3_Sounds_F"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"

// See addons/modules_system/config.cpp's own Extended_PostInit_EventHandlers
// comment -- CBA does not auto-run a bare XEH_postInit.sqf by filename, it
// has to be wired up explicitly per addon. Without this, aegism_network_
// fnc_scanForUninitSites' fallback scan never registers at all, defeating
// the entire point of it existing (see that function's own doc comment for
// the real, observed Eden Preview module-activation gap it exists to route
// around).
class Extended_PostInit_EventHandlers
{
    class aegism_modules_network
    {
        init = "call compile preprocessFileLineNumbers '\x\aegism\addons\modules_network\XEH_postInit.sqf'";
    };
};

// Site alarms (aegism_network_fnc_siteAlarm): one looping sound per tone,
// built exactly like vanilla's own "Alarm" sound source (CfgSFX AlarmSfx,
// CfgVehicles Sound_Alarm): volume 1, heard to 400m, played back to back.
// Every tone is a distinct vanilla recording (the vanilla alarm_BLUFOR,
// alarm_OPFOR and alarm_Independent files are byte-for-byte the same
// recording, so they're one tone here: "base"). Lengths measured from the
// files themselves.
class CfgSFX
{
    class AEGISM_Alarm_Base_Sfx
    {
        name = "AEGIS-M: Base alarm";
        sounds[] = {"alarm"};
        alarm[] = {"A3\Sounds_F\sfx\alarm_BLUFOR", 1, 1, 400, 1, 0, 0, 0}; // 6.6s
        empty[] = {"", 0, 0, 0, 0, 0, 0, 0};
    };
    class AEGISM_Alarm_Klaxon_Sfx: AEGISM_Alarm_Base_Sfx
    {
        name = "AEGIS-M: Klaxon";
        alarm[] = {"A3\Sounds_F\sfx\alarm", 1, 1, 400, 1, 0, 0, 0}; // 1.6s
    };
    class AEGISM_Alarm_Klaxon2_Sfx: AEGISM_Alarm_Base_Sfx
    {
        name = "AEGIS-M: Klaxon 2";
        alarm[] = {"A3\Sounds_F\sfx\alarm_3", 1, 1, 400, 1, 0, 0, 0}; // 2.1s
    };
    class AEGISM_Alarm_Siren_Sfx: AEGISM_Alarm_Base_Sfx
    {
        name = "AEGIS-M: Siren";
        alarm[] = {"A3\Sounds_F\sfx\siren", 1, 1, 400, 1, 0, 0, 0}; // 1.4s
    };
    class AEGISM_Alarm_Zone_Sfx: AEGISM_Alarm_Base_Sfx
    {
        name = "AEGIS-M: Restricted-zone warning";
        alarm[] = {"A3\Sounds_F_Orange\MissionSFX\Orange_ZoneRestriction_Warning", 1, 1, 400, 1, 0, 0, 0}; // 4.6s
    };
    class AEGISM_Alarm_HeliNato_Sfx: AEGISM_Alarm_Base_Sfx
    {
        name = "AEGIS-M: Helicopter warning (NATO)";
        alarm[] = {"A3\Sounds_F\vehicles\air\noises\heli_alarm_bluefor", 1, 1, 400, 1, 0, 0, 0}; // 2.0s
    };
    class AEGISM_Alarm_HeliCsat_Sfx: AEGISM_Alarm_Base_Sfx
    {
        name = "AEGIS-M: Helicopter warning (CSAT)";
        alarm[] = {"A3\Sounds_F\vehicles\air\noises\heli_alarm_opfor", 1, 1, 400, 1, 0, 0, 0}; // 1.5s
    };
    class AEGISM_Alarm_Lock_Sfx: AEGISM_Alarm_Base_Sfx
    {
        name = "AEGIS-M: Missile-lock tone";
        alarm[] = {"A3\Sounds_F\vehicles\air\noises\alarm_locked_by_missile_2", 1, 1, 400, 1, 0, 0, 0}; // 0.2s
    };
};

class CfgVehicles
{
    class Sound;
    class AEGISM_Alarm_Base: Sound
    {
        author = "Snow(Dryden)";
        scope = 1;
        sound = "AEGISM_Alarm_Base_Sfx";
        displayName = "AEGIS-M: Base alarm";
    };
    class AEGISM_Alarm_Klaxon: AEGISM_Alarm_Base
    {
        sound = "AEGISM_Alarm_Klaxon_Sfx";
        displayName = "AEGIS-M: Klaxon";
    };
    class AEGISM_Alarm_Klaxon2: AEGISM_Alarm_Base
    {
        sound = "AEGISM_Alarm_Klaxon2_Sfx";
        displayName = "AEGIS-M: Klaxon 2";
    };
    class AEGISM_Alarm_Siren: AEGISM_Alarm_Base
    {
        sound = "AEGISM_Alarm_Siren_Sfx";
        displayName = "AEGIS-M: Siren";
    };
    class AEGISM_Alarm_Zone: AEGISM_Alarm_Base
    {
        sound = "AEGISM_Alarm_Zone_Sfx";
        displayName = "AEGIS-M: Restricted-zone warning";
    };
    class AEGISM_Alarm_HeliNato: AEGISM_Alarm_Base
    {
        sound = "AEGISM_Alarm_HeliNato_Sfx";
        displayName = "AEGIS-M: Helicopter warning (NATO)";
    };
    class AEGISM_Alarm_HeliCsat: AEGISM_Alarm_Base
    {
        sound = "AEGISM_Alarm_HeliCsat_Sfx";
        displayName = "AEGIS-M: Helicopter warning (CSAT)";
    };
    class AEGISM_Alarm_Lock: AEGISM_Alarm_Base
    {
        sound = "AEGISM_Alarm_Lock_Sfx";
        displayName = "AEGIS-M: Missile-lock tone";
    };

    // ModuleDescription is a class NESTED in Module_F, so it is declared
    // there. It used to be declared at the root of CfgVehicles, which created
    // an empty *vehicle* class called ModuleDescription: the engine then
    // tried to load it as a vehicle (hundreds of "No entry
    // CfgVehicles/ModuleDescription.scope/.icon/..." RPT warnings) and it
    // polluted the Eden/Zeus asset lists.
    class Logic;
    class Module_F: Logic
    {
        class ModuleDescription;
    };

    class AEGISM_Module_Site: Module_F
    {
        scope = 2;
        scopeCurator = 2;
        displayName = "AEGIS-M: Site";
        icon = "\x\aegism\addons\main\data\aegism_logo_ca.paa";
        portrait = "\x\aegism\addons\main\data\aegism_logo_ca.paa";
        category = "AEGISM_Modules";
        function = "aegism_network_fnc_moduleInit";
        functionPriority = 0;
        isGlobal = 1;
        isTriggerActivated = 0;
        is3DEN = 1;

        // Four sections, each opened by an Eden "SubCategory" heading (the
        // same control vanilla uses for its Garbage Collection sections).
        // Eden lists attributes in the order declared here. Property names
        // are unchanged from the old flat list, so values saved in existing
        // missions carry over. Any vehicle can override most of these for
        // itself -- see addons/modules_system/config.cpp (Cfg3DEN).
        class Attributes
        {
            // ================================================= SITE SETTINGS
            class Section_Site
            {
                property = "aegism_site_section_site";
                control = "SubCategory";
                displayName = "Site Settings";
                title = "Site Settings";
                description = "";
            };
            class TargetPriority
            {
                displayName = "Target Priority";
                tooltip = "Which contacts get weapons first when there are more threats than free weapons. Soonest Impact (default): the contact that will reach the Site first -- works an incoming salvo front to back (ballistic arc for rockets/shells/bombs, closing speed for missiles/aircraft). Nearest: closest to any Site vehicle. Fastest Closing: highest speed toward the nearest Site vehicle. Highest Value: by threat class (missile, then bomb, then aircraft, then drone/rocket, then artillery), then nearest.";
                property = "targetPriority";
                control = "Combo";
                expression = "_this setVariable ['targetPriority', _value];";
                typeName = "STRING";
                defaultValue = "'soonestImpact'";
                class Values
                {
                    class SoonestImpact
                    {
                        name = "Soonest Impact";
                        value = "soonestImpact";
                    };
                    class Nearest
                    {
                        name = "Nearest";
                        value = "nearest";
                    };
                    class FastestClosing
                    {
                        name = "Fastest Closing";
                        value = "fastestClosing";
                    };
                    class HighestValue
                    {
                        name = "Highest Value";
                        value = "highestValue";
                    };
                };
            };
            class SkillTier
            {
                displayName = "Crew Skill";
                tooltip = "Crew reaction time (hesitation before the first shot at a newly assigned target) and reliability (chance a fire command goes out clean -- rolled once per missile or per CIWS burst). Green: 4.0s, 55%. Regular: 2.5s, 70%. Veteran: 1.2s, 85%. Elite: 0.5s, 95%. CIWS reaction is capped at 1s (automated fire control). Temperament scales both further.";
                property = "skillTier";
                control = "Combo";
                expression = "_this setVariable ['skillTier', _value];";
                typeName = "STRING";
                defaultValue = "'regular'";
                class Values
                {
                    class Green
                    {
                        name = "Green (4.0s, 55% reliable)";
                        value = "green";
                    };
                    class Regular
                    {
                        name = "Regular (2.5s, 70% reliable)";
                        value = "regular";
                    };
                    class Veteran
                    {
                        name = "Veteran (1.2s, 85% reliable)";
                        value = "veteran";
                    };
                    class Elite
                    {
                        name = "Elite (0.5s, 95% reliable)";
                        value = "elite";
                    };
                };
            };
            class Temperament
            {
                displayName = "Crew Temperament";
                tooltip = "Scales Crew Skill's reaction time and reliability, and the pause between shots (Launchers: Seconds Between Missiles; CIWS: Pause Between Bursts). Cautious: x1.3 reaction, x1.05 reliability, x1.2 pause. Standard: x1. Aggressive: x0.7 reaction, x0.95 reliability, x0.8 pause. Nervous: x0.6 reaction, x0.85 reliability, x0.75 pause.";
                property = "temperament";
                control = "Combo";
                expression = "_this setVariable ['temperament', _value];";
                typeName = "STRING";
                defaultValue = "'standard'";
                class Values
                {
                    class Cautious
                    {
                        name = "Cautious (slower, steadier)";
                        value = "cautious";
                    };
                    class Standard
                    {
                        name = "Standard (neutral)";
                        value = "standard";
                    };
                    class Aggressive
                    {
                        name = "Aggressive (faster, sloppier)";
                        value = "aggressive";
                    };
                    class Nervous
                    {
                        name = "Nervous (fastest, least reliable)";
                        value = "nervous";
                    };
                };
            };
            class CrewOnAutomated
            {
                displayName = "Crew Skill on Automated Systems";
                tooltip = "Off (default): automated systems -- anything crewed by UAV AI, e.g. Phalanx, RAM, MIM-145, radar units -- ignore Crew Skill and Temperament: no reaction delay, no skipped fire cycles, no interval scaling. On: they get the same crew model as manned systems.";
                property = "crewOnAutomated";
                control = "Checkbox";
                expression = "_this setVariable ['crewOnAutomated', _value];";
                typeName = "BOOL";
                defaultValue = "false";
            };
            class CostValueJudgment
            {
                displayName = "Save Ammo for Bigger Threats";
                tooltip = "Crew holds fire on a contact if firing would leave fewer rounds than there are tracked contacts of strictly higher threat value. Off by default.";
                property = "costValueJudgment";
                control = "Checkbox";
                expression = "_this setVariable ['costValueJudgment', _value];";
                typeName = "BOOL";
                defaultValue = "false";
            };

            // ========================================== INTERCEPTION TARGETS
            class Section_Targets
            {
                property = "aegism_site_section_targets";
                control = "SubCategory";
                displayName = "Interception Targets";
                title = "Interception Targets";
                description = "";
            };
            class AllowMissile
            {
                displayName = "Engage Missiles";
                tooltip = "Guided missiles (CfgAmmo MissileCore).";
                property = "allowMissile";
                control = "Checkbox";
                expression = "_this setVariable ['allowMissile', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowRocket
            {
                displayName = "Engage Rockets";
                tooltip = "Unguided rockets (CfgAmmo RocketCore).";
                property = "allowRocket";
                control = "Checkbox";
                expression = "_this setVariable ['allowRocket', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowBomb
            {
                displayName = "Engage Bombs";
                tooltip = "Aircraft bombs (CfgAmmo BombCore).";
                property = "allowBomb";
                control = "Checkbox";
                expression = "_this setVariable ['allowBomb', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowArtilleryShell
            {
                displayName = "Engage Artillery, Mortar and MLRS Rounds";
                tooltip = "Indirect-fire rounds (CfgAmmo artilleryLock = 1) -- the C-RAM role. Tank main-gun rounds never count.";
                property = "allowArtilleryShell";
                control = "Checkbox";
                expression = "_this setVariable ['allowArtilleryShell', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowFixedWing
            {
                displayName = "Engage Fixed-Wing Aircraft";
                tooltip = "Hostile manned planes.";
                property = "allowFixedWing";
                control = "Checkbox";
                expression = "_this setVariable ['allowFixedWing', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowHelicopter
            {
                displayName = "Engage Helicopters";
                tooltip = "Hostile manned helicopters.";
                property = "allowHelicopter";
                control = "Checkbox";
                expression = "_this setVariable ['allowHelicopter', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowDrone
            {
                displayName = "Engage Drones";
                tooltip = "Hostile unmanned aircraft (UAV/UCAV).";
                property = "allowDrone";
                control = "Checkbox";
                expression = "_this setVariable ['allowDrone', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class MinAltitude
            {
                displayName = "Target Min Height (m above ground)";
                tooltip = "Ignore contacts lower than this above the ground. Applies to launchers and CIWS.";
                property = "minAltitude";
                control = "Edit";
                expression = "_this setVariable ['minAltitude', _value];";
                typeName = "NUMBER";
                defaultValue = "0";
            };
            class MaxAltitude
            {
                displayName = "Target Max Height (m above ground)";
                tooltip = "Ignore contacts higher than this above the ground. 0 = no limit. Applies to launchers and CIWS.";
                property = "maxAltitude";
                control = "Edit";
                expression = "_this setVariable ['maxAltitude', _value];";
                typeName = "NUMBER";
                defaultValue = "0";
            };
            class EngageFriendlyThreats
            {
                displayName = "Engage Friendly Munitions Threatening the Site";
                tooltip = "On (default): a friendly or neutral munition (e.g. a short artillery round) is also engaged if it is predicted to hit the Site -- a guided missile whose own target is a Site vehicle, or an unguided round whose predicted impact falls within the Friendly Threat Radius of a Site vehicle. AEGIS-M's own interceptors are never considered.";
                property = "engageFriendlyThreats";
                control = "Checkbox";
                expression = "_this setVariable ['engageFriendlyThreats', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class EngageOnlyThreats
            {
                displayName = "Only Engage Munitions Threatening the Site";
                tooltip = "On (default): a hostile munition is only engaged while it's a threat to a Site vehicle -- an artillery, mortar or MLRS round (or unguided rocket) predicted to land within the Threat Radius of one; a missile guided at one, or flying on a line that passes within the Threat Radius of one; a bomb whose fall or line of flight does. One landing well clear of the Site, or a missile flying at something else, doesn't cost a single round (logged once as IGNORED), and is picked up if it turns toward the Site. Off: every hostile munition in reach is engaged, wherever it's going.";
                property = "engageOnlyThreats";
                control = "Checkbox";
                expression = "_this setVariable ['engageOnlyThreats', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class FriendlyThreatRadius
            {
                displayName = "Threat Radius (m)";
                tooltip = "How close to a Site vehicle a munition's predicted impact must be to count as a threat -- for a friendly munition (Engage Friendly Munitions Threatening the Site), and for a hostile artillery round or rocket (Only Engage Munitions Threatening the Site). 0 (default) = that munition's own config danger radius (CfgAmmo dangerRadiusHit, the radius the game's AI keeps friendlies out of: 750m for 155mm, 1250m for MLRS, 1000m for bombs), or its blast radius (indirectHitRange) when that isn't set.";
                property = "friendlyThreatRadius";
                control = "Edit";
                expression = "_this setVariable ['friendlyThreatRadius', _value];";
                typeName = "NUMBER";
                defaultValue = "0";
            };

            // ===================================================== LAUNCHERS
            class Section_Launchers
            {
                property = "aegism_site_section_launchers";
                control = "SubCategory";
                displayName = "Launchers (Missiles)";
                title = "Launchers (Missiles)";
                description = "";
            };
            class MinRange
            {
                displayName = "Min Range (m)";
                tooltip = "Launchers won't fire at contacts closer than this, on top of each missile's own config minimum (e.g. MIM-145: 1000m). 0 = only the missile's own minimum. Never applies to CIWS guns. Real-world metres, scaled by the AEGIS-M Range Scale setting.";
                property = "minRange";
                control = "Edit";
                expression = "_this setVariable ['minRange', _value];";
                typeName = "NUMBER";
                defaultValue = "0";
            };
            class MaxRange
            {
                displayName = "Max Range (m)";
                tooltip = "Launchers won't fire at contacts farther than this. 0 (default) = each missile's own config reach (e.g. MIM-145: 16000m). Never applies to CIWS guns (see CIWS Max Range). Real-world metres, scaled by the AEGIS-M Range Scale setting.";
                property = "maxRange";
                control = "Edit";
                expression = "_this setVariable ['maxRange', _value];";
                typeName = "NUMBER";
                defaultValue = "0";
            };
            class SalvoSize
            {
                displayName = "Missiles per Target";
                tooltip = "Missiles fired at one target before waiting to see the result. If every missile misses and the target survives, it is engaged again.";
                property = "salvoSize";
                control = "Edit";
                expression = "_this setVariable ['salvoSize', _value];";
                typeName = "NUMBER";
                defaultValue = "1";
            };
            class MinShotInterval
            {
                displayName = "Seconds Between Missiles";
                tooltip = "Minimum seconds between two missiles from the same launcher (scaled by Crew Temperament). 0 = Auto: each launcher's own fire rate from its weapon config, which scales with the missile (vanilla MIM-145 Defender 4s, Mk49 Spartan 2s, Mk21 Centurion 1s).";
                property = "minShotInterval";
                control = "Edit";
                expression = "_this setVariable ['minShotInterval', _value];";
                typeName = "NUMBER";
                defaultValue = "0";
            };

            // ========================================================== CIWS
            class Section_Ciws
            {
                property = "aegism_site_section_ciws";
                control = "SubCategory";
                displayName = "CIWS (Guns)";
                title = "CIWS (Guns)";
                description = "";
            };
            class CiwsMaxRange
            {
                displayName = "Max Range (m)";
                tooltip = "CIWS guns won't fire at contacts farther than this. 0 (default) = the gun's own config reach (e.g. Cheetah 35mm: 2500m). Real-world metres, scaled by the AEGIS-M Range Scale setting.";
                property = "ciwsMaxRange";
                control = "Edit";
                expression = "_this setVariable ['ciwsMaxRange', _value];";
                typeName = "NUMBER";
                defaultValue = "0";
            };
            class CiwsMinElevation
            {
                displayName = "Min Elevation (deg)";
                tooltip = "A CIWS gun is never assigned a target below this elevation above its own horizon, and holds fire whenever its barrel is below it -- keeps rounds out of the ground and friendly positions around the Site.";
                property = "ciwsMinElevation";
                control = "Edit";
                expression = "_this setVariable ['ciwsMinElevation', _value];";
                typeName = "NUMBER";
                defaultValue = "5";
            };
            class CiwsOpenFireChance
            {
                displayName = "Open Fire at Hit Chance (%)";
                tooltip = "A CIWS gun tracks a target from as far as it can reach, but only fires once ONE BURST is at least this likely (40 percent by default) to put a round within hitting distance of it. Worked out from measurable things: the gun's own measured scatter (its spotted rounds' misses; the fire mode's dispersion until it has fired), how far the target strays from its predicted track, the round's flight time (initSpeed, airFriction), the hit radius (the round's blast radius or the target's own size), and the rounds in a burst (its measured rate of fire x the burst length). Never beyond the round's reach in its own lifetime (timeToLive), and never inside its arming distance (fuseDistance) against a munition. Lower = fires earlier and farther, spending more rounds for fewer hits. 0 = its full reach. The range and every input are logged (OPEN-FIRE-RANGE); a gun waiting for a target to close logs RANGE-HOLD.";
                property = "ciwsOpenFireChance";
                control = "Edit";
                expression = "_this setVariable ['ciwsOpenFireChance', _value];";
                typeName = "NUMBER";
                defaultValue = "40";
            };
            class CiwsBurstMin
            {
                displayName = "Burst Length Min (s)";
                tooltip = "Shortest sustained burst. Each burst holds the trigger for a random length between Min and Max, at the gun's own config rate of fire, while the turret is on the lead point.";
                property = "ciwsBurstMin";
                control = "Edit";
                expression = "_this setVariable ['ciwsBurstMin', _value];";
                typeName = "NUMBER";
                defaultValue = "3";
            };
            class CiwsBurstMax
            {
                displayName = "Burst Length Max (s)";
                tooltip = "Longest sustained burst (see Burst Length Min).";
                property = "ciwsBurstMax";
                control = "Edit";
                expression = "_this setVariable ['ciwsBurstMax', _value];";
                typeName = "NUMBER";
                defaultValue = "5";
            };
            class CiwsBurstPause
            {
                displayName = "Pause Between Bursts (s)";
                tooltip = "Seconds a gun pauses after one burst ends before firing again at the SAME target (scaled by Crew Temperament). After a kill, or once its target is released, it goes straight on to the next one.";
                property = "ciwsBurstPause";
                control = "Edit";
                expression = "_this setVariable ['ciwsBurstPause', _value];";
                typeName = "NUMBER";
                defaultValue = "1";
            };
            class CiwsLastResort
            {
                displayName = "Last Resort Only";
                tooltip = "Off (default): a CIWS engages a contact immediately, alongside any launcher already assigned to it. On: the CIWS holds while a launcher covers the contact, until every launcher assignment against it has failed or the contact has closed inside 40% of the gun's own reach.";
                property = "ciwsLastResort";
                control = "Checkbox";
                expression = "_this setVariable ['ciwsLastResort', _value];";
                typeName = "BOOL";
                defaultValue = "false";
            };

            // ======================================================== ALARMS
            class Section_Alarms
            {
                property = "aegism_site_section_alarms";
                control = "SubCategory";
                displayName = "Alarms";
                title = "Alarms";
                description = "";
            };
            class AlarmWarning
            {
                displayName = "Going-Live Warning";
                tooltip = "Sounds from the moment the Site commits a weapon to a target (before its first shot: the crew's reaction and the turret's slew), and keeps sounding until the Warning Lasts time after its last shot. Plays from every non-vehicle object synced to this Site (a loudspeaker, a lamp post, a Game Logic -- anything that isn't a vehicle or a unit), or from this module itself if none is. Heard to 400m, like vanilla's own alarm. The Incoming Alarm replaces it while a munition is inbound. Tone lengths are one cycle.";
                property = "alarmWarning";
                control = "Combo";
                expression = "_this setVariable ['alarmWarning', _value];";
                typeName = "STRING";
                defaultValue = "'base'";
                class Values
                {
                    class Base { name = "Base alarm (6.6s cycle)"; value = "base"; };
                    class Klaxon { name = "Klaxon (1.6s)"; value = "klaxon"; };
                    class Klaxon2 { name = "Klaxon 2 (2.1s)"; value = "klaxon2"; };
                    class Siren { name = "Siren (1.4s)"; value = "siren"; };
                    class Zone { name = "Restricted-zone warning (4.6s)"; value = "zone"; };
                    class HeliNato { name = "Helicopter warning, NATO (2.0s)"; value = "heliNato"; };
                    class HeliCsat { name = "Helicopter warning, CSAT (1.5s)"; value = "heliCsat"; };
                    class Lock { name = "Missile-lock tone (0.2s beep)"; value = "lock"; };
                    class Off { name = "Off"; value = "off"; };
                };
            };
            class AlarmIncoming
            {
                displayName = "Incoming Alarm";
                tooltip = "Sounds while a munition is inbound on the Site -- one a Site radar sees that is a threat to a Site vehicle (an artillery, mortar or MLRS round or a rocket predicted to land within the Threat Radius of one, a missile guided or flying at one, a bomb falling on one), whether it's hostile or a friendly round falling short -- and for 3s after the last one is seen (the Site's own contact expiry). Replaces the Going-Live Warning while it sounds. Auto (default): by the Site's side -- BLUFOR the NATO helicopter warning, OPFOR the CSAT one, anyone else the Klaxon.";
                property = "alarmIncoming";
                control = "Combo";
                expression = "_this setVariable ['alarmIncoming', _value];";
                typeName = "STRING";
                defaultValue = "'auto'";
                class Values
                {
                    class Auto { name = "Auto (by the Site's side)"; value = "auto"; };
                    class Base { name = "Base alarm (6.6s cycle)"; value = "base"; };
                    class Klaxon { name = "Klaxon (1.6s)"; value = "klaxon"; };
                    class Klaxon2 { name = "Klaxon 2 (2.1s)"; value = "klaxon2"; };
                    class Siren { name = "Siren (1.4s)"; value = "siren"; };
                    class Zone { name = "Restricted-zone warning (4.6s)"; value = "zone"; };
                    class HeliNato { name = "Helicopter warning, NATO (2.0s)"; value = "heliNato"; };
                    class HeliCsat { name = "Helicopter warning, CSAT (1.5s)"; value = "heliCsat"; };
                    class Lock { name = "Missile-lock tone (0.2s beep)"; value = "lock"; };
                    class Off { name = "Off"; value = "off"; };
                };
            };
            class AlarmHold
            {
                displayName = "Warning Lasts After Last Shot (s)";
                tooltip = "How long the Going-Live Warning keeps sounding after the Site's last shot (missile or gun), once no weapon is assigned any more.";
                property = "alarmHold";
                control = "Edit";
                expression = "_this setVariable ['alarmHold', _value];";
                typeName = "NUMBER";
                defaultValue = "10";
            };
            class AlarmWarningCustom
            {
                displayName = "Custom Warning Sound";
                tooltip = "Optional: the class name of any looping sound source (CfgVehicles, like vanilla's Sound_Alarm -- e.g. one from a sound mod with a real national air-raid siren). Replaces the Going-Live Warning's tone. Blank = use the tone above.";
                property = "alarmWarningCustom";
                control = "Edit";
                expression = "_this setVariable ['alarmWarningCustom', _value];";
                typeName = "STRING";
                defaultValue = "''";
            };
            class AlarmIncomingCustom
            {
                displayName = "Custom Incoming Sound";
                tooltip = "Optional: the class name of any looping sound source (CfgVehicles, like vanilla's Sound_Alarm -- e.g. one from a sound mod with a spoken 'INCOMING' alert). Replaces the Incoming Alarm's tone. Blank = use the tone above.";
                property = "alarmIncomingCustom";
                control = "Edit";
                expression = "_this setVariable ['alarmIncomingCustom', _value];";
                typeName = "STRING";
                defaultValue = "''";
            };
        };

        class ModuleDescription: ModuleDescription
        {
            description = "The one AEGIS-M module: sync it to every radar, launcher, SHORAD, and CIWS vehicle that makes up a site to link them into one battery under these settings, with a shared coordinator assigning each detected threat to the best-fit weapon. Roles are discovered automatically from each vehicle's real sensors and loaded ammo. Any vehicle can override these settings for itself in its own attributes (AEGIS-M: Vehicle Overrides). A qualifying vehicle still works standalone with default settings if never synced to a Site. Sync non-vehicle objects (a loudspeaker, a lamp post, a Game Logic) to make them the Site's alarm speakers (see Alarms). In Zeus (with Zeus Enhanced): double-click the Site, or right-click it or a vehicle for AEGIS-M Settings.";
            sync[] = {"AnyVehicle"};
        };
    };
};
