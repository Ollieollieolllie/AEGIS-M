class CfgPatches
{
    class aegism_main
    {
        units[] = {};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"cba_main", "cba_settings", "A3_Modules_F"};
        #include "version.hpp"
    };
};

#include "CfgFunctions.hpp"

// CBA's Extended Event Handler system does NOT auto-detect a bare
// XEH_preInit.sqf/XEH_postInit.sqf by filename or PBO prefix -- despite
// those exact filenames being near-universal convention, they only run
// because every CBA-based addon's own config.cpp explicitly wires them up
// through a class like this (CBA's own component template does the same
// thing internally, via macros that expand to this same class). Without
// this block, the file sits in the PBO, fully compiled, and is simply
// never called -- confirmed the hard way this session: every CBA_
// fnc_addSetting call, the isGlobal netId fix, and everything else in
// these two files silently never ran for the entire mod until this was
// added.
class Extended_PreInit_EventHandlers
{
    class aegism_main
    {
        init = "call compile preprocessFileLineNumbers '\x\aegism\addons\main\XEH_preInit.sqf'";
    };
};

class Extended_PostInit_EventHandlers
{
    class aegism_main
    {
        init = "call compile preprocessFileLineNumbers '\x\aegism\addons\main\XEH_postInit.sqf'";
    };
};

// Module browser folder for every AEGIS-M module, in both Eden (Systems >
// Modules) and Zeus (Modules tab). Modules are grouped by their `category`,
// a CfgFactionClasses entry -- NOT by editorCategory/editorSubcategory,
// which only group props/objects. The Site used to set only those, so it
// fell into the default "Other" folder. Defined once here (main is a hard
// dependency of every other AEGIS-M addon).
class CfgFactionClasses
{
    class NO_CATEGORY;
    class AEGISM_Modules: NO_CATEGORY
    {
        displayName = "AEGIS-M";
    };
};
