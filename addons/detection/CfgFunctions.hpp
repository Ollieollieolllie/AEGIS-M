#define R recompile = 1
class CfgFunctions
{
    class aegism_detection {
        tag = "aegism_detect";
        class functions {
            file = "\x\aegism\addons\detection\functions";
            class classifyTarget {R;};
            class classifyAmmoClass {R;};
            class addContact {R;};
            class removeContact {R;};
            class confidenceLoop {R;};
        };
    };
};
