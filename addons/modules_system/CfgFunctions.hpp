#define R recompile = 1
class CfgFunctions
{
    class aegism_modules_system {
        tag = "aegism_system";
        class functions {
            file = "\aegism_modules_system\functions";
            class moduleInit {R;};
            class resolveContactSource {R;};
            class resolveEngagementSettings {R;};
            class resolveCrew {R;};
            class defaultEngagementSettings {R;};
            class defaultCrew {R;};
        };
    };
};
