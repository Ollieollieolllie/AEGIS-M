class CfgPatches
{
    class aegism_modules_network
    {
        units[] = {"AEGISM_Module_Site"};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main", "aegism_intercept"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"

class CfgVehicles
{
    class Module_F;
    class ModuleDescription;

    class AEGISM_Module_Site: Module_F
    {
        scope = 2;
        displayName = "AEGIS-M: Site";
        icon = "\x\aegism\addons\main\data\aegism_icon_network_ca.paa";
        editorCategory = "AEGISM_EditorCategory";
        editorSubcategory = "AEGISM_EditorSubcategory_Modules";
        function = "aegism_network_fnc_moduleInit";
        functionPriority = 0;
        isGlobal = 1;
        isTriggerActivated = 0;
        is3DEN = 1;

        class Attributes
        {
            class MinRange
            {
                displayName = "Doctrine: Envelope - Min Range (m, real-world base)";
                tooltip = "Minimum engagement range. Scaled at runtime by the AEGIS-M Range Scale setting.";
                property = "minRange";
                control = "Edit";
                expression = "_this setVariable ['minRange', _value];";
                typeName = "NUMBER";
                defaultValue = "500";
            };
            class MaxRange
            {
                displayName = "Doctrine: Envelope - Max Range (m, real-world base)";
                tooltip = "Maximum engagement range. Scaled at runtime by the AEGIS-M Range Scale setting.";
                property = "maxRange";
                control = "Edit";
                expression = "_this setVariable ['maxRange', _value];";
                typeName = "NUMBER";
                defaultValue = "8000";
            };
            class MinAltitude
            {
                displayName = "Doctrine: Envelope - Min Altitude (m)";
                tooltip = "Minimum target altitude to consider engaging.";
                property = "minAltitude";
                control = "Edit";
                expression = "_this setVariable ['minAltitude', _value];";
                typeName = "NUMBER";
                defaultValue = "0";
            };
            class MaxAltitude
            {
                displayName = "Doctrine: Envelope - Max Altitude (m)";
                tooltip = "Maximum target altitude to consider engaging.";
                property = "maxAltitude";
                control = "Edit";
                expression = "_this setVariable ['maxAltitude', _value];";
                typeName = "NUMBER";
                defaultValue = "6000";
            };
            class TargetPriority
            {
                displayName = "Doctrine: Target Priority Rule";
                tooltip = "Which in-envelope contact to engage first.";
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
            class SalvoSize
            {
                displayName = "Doctrine: Salvo - Rounds Per Engagement";
                tooltip = "Rounds fired per engagement under this doctrine.";
                property = "salvoSize";
                control = "Edit";
                expression = "_this setVariable ['salvoSize', _value];";
                typeName = "NUMBER";
                defaultValue = "1";
            };
            class MinShotInterval
            {
                displayName = "Doctrine: Salvo - Minimum Shot Interval (s)";
                tooltip = "Minimum seconds between shots within a salvo.";
                property = "minShotInterval";
                control = "Edit";
                expression = "_this setVariable ['minShotInterval', _value];";
                typeName = "NUMBER";
                defaultValue = "4";
            };
            class CiwsLastResort
            {
                displayName = "Doctrine: CIWS Engages as Last Resort Only";
                tooltip = "Off (default): CIWS engages a contact immediately alongside any launcher already assigned to it -- appropriate for fast/close threats a missile shot shouldn't be waited on. On: CIWS is withheld from a contact until every launcher assignment against it has failed (out of envelope/ammo, or fired without a kill) or the contact has closed inside CIWS's own effective engagement range, whichever comes first.";
                property = "ciwsLastResort";
                control = "Checkbox";
                expression = "_this setVariable ['ciwsLastResort', _value];";
                typeName = "BOOL";
                defaultValue = "false";
            };
            class AllowMissile
            {
                displayName = "Doctrine: Allow - Missile";
                tooltip = "Permit engaging tracked missile contacts.";
                property = "allowMissile";
                control = "Checkbox";
                expression = "_this setVariable ['allowMissile', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowRocket
            {
                displayName = "Doctrine: Allow - Rocket";
                tooltip = "Permit engaging tracked rocket contacts.";
                property = "allowRocket";
                control = "Checkbox";
                expression = "_this setVariable ['allowRocket', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowBomb
            {
                displayName = "Doctrine: Allow - Bomb";
                tooltip = "Permit engaging tracked bomb contacts.";
                property = "allowBomb";
                control = "Checkbox";
                expression = "_this setVariable ['allowBomb', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowArtilleryShell
            {
                displayName = "Doctrine: Allow - Artillery Shell";
                tooltip = "Permit engaging tracked artillery/mortar shell contacts (CRAM role).";
                property = "allowArtilleryShell";
                control = "Checkbox";
                expression = "_this setVariable ['allowArtilleryShell', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowFixedWing
            {
                displayName = "Doctrine: Allow - Fixed-Wing Aircraft";
                tooltip = "Permit engaging fixed-wing aircraft.";
                property = "allowFixedWing";
                control = "Checkbox";
                expression = "_this setVariable ['allowFixedWing', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowHelicopter
            {
                displayName = "Doctrine: Allow - Helicopter";
                tooltip = "Permit engaging helicopters.";
                property = "allowHelicopter";
                control = "Checkbox";
                expression = "_this setVariable ['allowHelicopter', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class AllowDrone
            {
                displayName = "Doctrine: Allow - Drone (UAV/UCAV)";
                tooltip = "Permit engaging unmanned aerial vehicles.";
                property = "allowDrone";
                control = "Checkbox";
                expression = "_this setVariable ['allowDrone', _value];";
                typeName = "BOOL";
                defaultValue = "true";
            };
            class SkillTier
            {
                displayName = "Personality: Skill Tier";
                tooltip = "Baseline crew reaction time (hesitation before first shot at a newly-acquired target) and reliability (chance of a clean fire command each cycle). Green: 4.0s, 55% reliable. Regular: 2.5s, 70%. Veteran: 1.2s, 85%. Elite: 0.5s, 95%. Temperament scales both further.";
                property = "skillTier";
                control = "Combo";
                expression = "_this setVariable ['skillTier', _value];";
                typeName = "STRING";
                defaultValue = "'regular'";
                class Values
                {
                    class Green
                    {
                        name = "Green (slow, 55% reliable)";
                        value = "green";
                    };
                    class Regular
                    {
                        name = "Regular (baseline, 70% reliable)";
                        value = "regular";
                    };
                    class Veteran
                    {
                        name = "Veteran (fast, 85% reliable)";
                        value = "veteran";
                    };
                    class Elite
                    {
                        name = "Elite (fastest, 95% reliable)";
                        value = "elite";
                    };
                };
            };
            class Temperament
            {
                displayName = "Personality: Temperament";
                tooltip = "Multiplies Skill Tier's reaction time/reliability and the doctrine's minimum shot interval. Cautious: slower to shoot (x1.3 reaction) but steadier (x1.05 reliability) and waits longer between shots (x1.2 interval). Aggressive: faster (x0.7) and shoots more often (x0.8 interval) but slightly sloppier (x0.95 reliability). Nervous: fastest to shoot (x0.6) and quickest between shots (x0.75 interval) but least reliable (x0.85). Standard: neutral 1x baseline.";
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
                        name = "Standard (neutral baseline)";
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
                displayName = "Personality: Enable Cost/Value Judgment";
                tooltip = "Optional: crew declines to fire on a contact if doing so would leave fewer rounds than there are currently-tracked contacts of strictly higher threat value, saving stock for those instead. Disabled by default.";
                property = "costValueJudgment";
                control = "Checkbox";
                expression = "_this setVariable ['costValueJudgment', _value];";
                typeName = "BOOL";
                defaultValue = "false";
            };
        };

        class ModuleDescription: ModuleDescription
        {
            description = "The one AEGIS-M module: sync it to every radar, launcher, SHORAD, and CIWS vehicle that makes up a site (each vehicle declares its own role via its own Attributes -- see any vehicle's Attributes panel) to link them into one battery under this doctrine and personality, and to pool/deconflict their contacts. A vehicle with a role checked still works standalone with sane defaults even if never synced to a Site.";
            sync[] = {"AnyVehicle"};
        };
    };
};
