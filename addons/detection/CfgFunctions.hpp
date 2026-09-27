#define R recompile = 1
class CfgFunctions
{
    class aegism_detection {
        tag = "aegism_detect";
        class functions {
            file = "\aegism_detection\functions";
            class classifyTarget {R;};
            class addContact {R;};
            class removeContact {R;};
            class firedEventHandler {R;};
            class trackMunition {R;};
            class computeConfidence {R;};
            class confidenceLoop {R;};
        };
    };
};
