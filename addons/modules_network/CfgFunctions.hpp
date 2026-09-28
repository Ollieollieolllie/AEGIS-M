#define R recompile = 1
class CfgFunctions
{
    class aegism_modules_network {
        tag = "aegism_network";
        class functions {
            file = "\x\aegism\addons\modules_network\functions";
            class moduleInit {R;};
            class scanForUninitSites {R;};
        };
    };
};
