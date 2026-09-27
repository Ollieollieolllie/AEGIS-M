class CfgPatches
{
    class aegism_main
    {
        units[] = {};
        weapons[] = {};
        author = "Snow(Dryden)";
        requiredVersion = 2.10;
        requiredAddons[] = {"cba_main", "cba_settings"};
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

// Eden/Zeus module browser categorization for every AEGIS-M module class.
// A Module_F-derived class needs a real editorCategory/editorSubcategory
// pair (referencing a class defined here) to appear in the module browser
// tree at all -- there is no fallback "uncategorized" bucket a mission
// designer can find it in. Defined once here (main is a hard dependency of
// every other AEGIS-M addon) rather than duplicated per module addon.
class CfgEditorCategories
{
    class AEGISM_EditorCategory
    {
        displayName = "AEGIS-M";
    };
};

class CfgEditorSubcategories
{
    class AEGISM_EditorSubcategory_Modules
    {
        displayName = "AEGIS-M Modules";
    };
};
