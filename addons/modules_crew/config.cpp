class CfgPatches
{
    class aegism_modules_crew
    {
        units[] = {"AEGISM_Module_Crew"};
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

    class AEGISM_Module_Crew: Module_F
    {
        scope = 2;
        displayName = "AEGIS-M: Crew";
        icon = "a3\ui_f\data\IGUI\Cfg\Actions\repair_ca.paa";
        category = "AEGISM";
        function = "aegism_crew_fnc_moduleInit";
        functionPriority = 2;
        isGlobal = 1;
        isTriggerActivated = 0;
        is3DEN = 1;

        class Attributes
        {
            class SkillTier
            {
                displayName = "Skill Tier";
                tooltip = "green | regular | veteran | elite -- drives reaction time, fire discipline, shot/intercept reliability.";
                property = "skillTier";
                control = "Edit";
                expression = "_this setVariable ['skillTier', _value];";
                typeName = "STRING";
                defaultValue = "'regular'";
            };
            class Temperament
            {
                displayName = "Temperament";
                tooltip = "cautious | standard | aggressive | nervous -- drives willingness to hold fire vs. engage early.";
                property = "temperament";
                control = "Edit";
                expression = "_this setVariable ['temperament', _value];";
                typeName = "STRING";
                defaultValue = "'standard'";
            };
            class CostValueJudgment
            {
                displayName = "Enable Cost/Value Judgment";
                tooltip = "Optional: crew weighs remaining interceptor stock against simultaneous threat count/type and may decline low-value engagements. Disabled by default.";
                property = "costValueJudgment";
                control = "Checkbox";
                expression = "_this setVariable ['costValueJudgment', _value];";
                typeName = "BOOL";
                defaultValue = "false";
            };
        };

        class ModuleDescription: ModuleDescription
        {
            description = "Defines crew personality (skill tier x temperament) modulating how far a synced System deviates from its doctrine's timing and reliability. Applies uniformly to SAM, CIWS, and CRAM roles.";
            sync[] = {"Man", "AnyVehicle", "Logic"};
        };
    };
};
