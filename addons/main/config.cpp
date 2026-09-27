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
