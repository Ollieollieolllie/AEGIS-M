class CfgPatches
{
    class aegism_intercept
    {
        units[] = {};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main", "aegism_detection", "ace_missileguidance", "ace_missile_sam", "ace_missile_manpad"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"
