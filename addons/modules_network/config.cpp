class CfgPatches
{
    class aegism_modules_network
    {
        units[] = {"AEGISM_Module_Site"};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main"};
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
                tooltip = "Drives reaction time and shot/intercept reliability.";
                property = "skillTier";
                control = "Combo";
                expression = "_this setVariable ['skillTier', _value];";
                typeName = "STRING";
                defaultValue = "'regular'";
                class Values
                {
                    class Green
                    {
                        name = "Green";
                        value = "green";
                    };
                    class Regular
                    {
                        name = "Regular";
                        value = "regular";
                    };
                    class Veteran
                    {
                        name = "Veteran";
                        value = "veteran";
                    };
                    class Elite
                    {
                        name = "Elite";
                        value = "elite";
                    };
                };
            };
            class Temperament
            {
                displayName = "Personality: Temperament";
                tooltip = "Drives willingness to hold fire vs. engage early.";
                property = "temperament";
                control = "Combo";
                expression = "_this setVariable ['temperament', _value];";
                typeName = "STRING";
                defaultValue = "'standard'";
                class Values
                {
                    class Cautious
                    {
                        name = "Cautious";
                        value = "cautious";
                    };
                    class Standard
                    {
                        name = "Standard";
                        value = "standard";
                    };
                    class Aggressive
                    {
                        name = "Aggressive";
                        value = "aggressive";
                    };
                    class Nervous
                    {
                        name = "Nervous";
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
