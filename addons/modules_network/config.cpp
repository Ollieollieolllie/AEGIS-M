class CfgPatches
{
    class aegism_modules_network
    {
        units[] = {"AEGISM_Module_Site"};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main", "aegism_intercept", "A3_Modules_F"};
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

class CfgVehicles
{
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
                tooltip = "Which contacts get weapons first when there are more threats than free weapons. Nearest: closest to any Site vehicle. Fastest Closing: highest speed toward the nearest Site vehicle. Highest Value: by threat class (missile, then bomb, then aircraft, then drone/rocket, then artillery), then nearest.";
                property = "targetPriority";
                control = "Combo";
                expression = "_this setVariable ['targetPriority', _value];";
                typeName = "STRING";
                defaultValue = "'nearest'";
                class Values
                {
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
            class FriendlyThreatRadius
            {
                displayName = "Friendly Threat Radius (m)";
                tooltip = "How close to a Site vehicle a friendly munition's predicted impact must be to count as a threat. 0 (default) = that munition's own config danger radius (CfgAmmo dangerRadiusHit, the radius the game's AI keeps friendlies out of: 750m for 155mm, 1250m for MLRS, 1000m for bombs), or its blast radius (indirectHitRange) when that isn't set.";
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
                tooltip = "Minimum seconds between two missiles from the same launcher (scaled by Crew Temperament).";
                property = "minShotInterval";
                control = "Edit";
                expression = "_this setVariable ['minShotInterval', _value];";
                typeName = "NUMBER";
                defaultValue = "4";
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
                tooltip = "Seconds a gun pauses after one burst ends before starting the next (scaled by Crew Temperament).";
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
        };

        class ModuleDescription: ModuleDescription
        {
            description = "The one AEGIS-M module: sync it to every radar, launcher, SHORAD, and CIWS vehicle that makes up a site to link them into one battery under these settings, with a shared coordinator assigning each detected threat to the best-fit weapon. Roles are discovered automatically from each vehicle's real sensors and loaded ammo. Any vehicle can override these settings for itself in its own attributes (AEGIS-M: Vehicle Overrides). A qualifying vehicle still works standalone with default settings if never synced to a Site.";
            sync[] = {"AnyVehicle"};
        };
    };
};
