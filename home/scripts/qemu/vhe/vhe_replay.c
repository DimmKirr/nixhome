/* Line-protocol driver for replaying sysreg traces through vhe_core.
 *
 * stdin:  one access per line: "r <reg_hex> <val_hex>" or "w <reg_hex> <val_hex>"
 * stdout: one result per line: "handled" | "redirect <target_hex>" | "unhandled"
 *
 * State persists across lines (a single vCPU's shadow EL2 file), so an
 * HCR_EL2.E2H write changes how later accesses dispatch — same as a boot.
 */
#include <inttypes.h>
#include <stdio.h>

#include "vhe_core.h"

int main(void)
{
    VHEState s = {0};
    char rw;
    uint32_t reg;
    uint64_t val;

    while (scanf(" %c %" SCNx32 " %" SCNx64, &rw, &reg, &val) == 3) {
        uint32_t target = 0;
        VHEAction act;

        if (rw == 'r') {
            uint64_t out = 0;
            act = vhe_sysreg_read(&s, reg, &out, &target);
        } else {
            act = vhe_sysreg_write(&s, reg, val, &target);
        }

        switch (act) {
        case VHE_HANDLED:
            puts("handled");
            break;
        case VHE_REDIRECT_EL1:
            printf("redirect %x\n", target);
            break;
        default:
            puts("unhandled");
            break;
        }
        fflush(stdout);
    }
    return 0;
}
