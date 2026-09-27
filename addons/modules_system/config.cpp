class CfgPatches
{
    class aegism_modules_system
    {
        units[] = {};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"aegism_main", "aegism_detection", "aegism_intercept"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"

// See addons/main/config.cpp's own Extended_PreInit_EventHandlers comment
// -- CBA does not auto-run a bare XEH_postInit.sqf by filename, it has to
// be wired up explicitly per addon. Without this, aegism_system_fnc_
// scanForRoles's periodic discovery scan never registers at all, so no
// vehicle in the mission is ever recognized as an AEGIS-M System no matter
// how correctly configured -- the root cause of an entire mission running
// with zero AEGIS-M behavior and no diagnostic output whatsoever.
class Extended_PostInit_EventHandlers
{
    class aegism_modules_system
    {
        init = "call compile preprocessFileLineNumbers '\x\aegism\addons\modules_system\XEH_postInit.sqf'";
    };
};
