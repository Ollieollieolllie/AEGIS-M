#define R recompile = 1
class CfgFunctions
{
    class aegism_modules_system {
        tag = "aegism_system";
        class functions {
            file = "\x\aegism\addons\modules_system\functions";
            class moduleInit {R;};
            class discoverCapabilities {R;};
            class resolveContactSource {R;};
            class resolveEngagementSettings {R;};
            class resolveCrew {R;};
            class applyOverrides {R;};
            class defaultEngagementSettings {R;};
            class defaultCrew {R;};
            class scanForRoles {R;};
            class debugCheckCiws {R;};
        };
    };
};
