/* VHE emulation core — see vhe_core.h. */
#include <stddef.h>

#include "vhe_core.h"

/* Bits that stay writable in a register; everything outside the mask is
 * RES0 and is cleared on write. LOW(n) = low n bits writable. */
#define LOW(n) ((n) >= 64 ? ~0ULL : ((1ULL << (n)) - 1))
#define ALL   (~0ULL)

/* Pure-shadow EL2 sysregs: value lives in VHEState, no EL1 counterpart.
 * write_mask encodes the ARM ARM RES0 layout (bits outside it read 0). */
static const struct {
    uint32_t reg;
    size_t offset;
    uint64_t write_mask;
} shadow_regs[] = {
    { VHE_SYSREG(3, 4, 0, 0, 0),  offsetof(VHEState, vpidr_el2),   ALL },
    { VHE_SYSREG(3, 4, 0, 0, 5),  offsetof(VHEState, vmpidr_el2),  ALL },
    { VHE_SYSREG(3, 4, 1, 1, 0),  offsetof(VHEState, hcr_el2),     ALL },
    { VHE_SYSREG(3, 4, 1, 1, 1),  offsetof(VHEState, mdcr_el2),    LOW(28) },
    { VHE_SYSREG(3, 4, 1, 1, 3),  offsetof(VHEState, hstr_el2),    LOW(16) },
    { VHE_SYSREG(3, 4, 1, 1, 7),  offsetof(VHEState, hacr_el2),    ALL },
    { VHE_SYSREG(3, 4, 2, 1, 0),  offsetof(VHEState, vttbr_el2),   ALL },
    { VHE_SYSREG(3, 4, 2, 1, 2),  offsetof(VHEState, vtcr_el2),    LOW(32) },
    { VHE_SYSREG(3, 4, 13, 0, 2), offsetof(VHEState, tpidr_el2),   ALL },
    { VHE_SYSREG(3, 4, 14, 0, 3), offsetof(VHEState, cntvoff_el2), ALL },
    /* Exception / fault reporting */
    { VHE_SYSREG(3, 4, 4, 0, 1),  offsetof(VHEState, elr_el2),     ALL },
    { VHE_SYSREG(3, 4, 4, 0, 0),  offsetof(VHEState, spsr_el2),    LOW(32) },
    { VHE_SYSREG(3, 4, 6, 0, 4),  offsetof(VHEState, hpfar_el2),   ALL },
    /* EL2 physical timer */
    { VHE_SYSREG(3, 4, 14, 2, 1), offsetof(VHEState, cnthp_ctl_el2),  LOW(3) },
    { VHE_SYSREG(3, 4, 14, 2, 2), offsetof(VHEState, cnthp_cval_el2), ALL },
    { VHE_SYSREG(3, 4, 14, 2, 0), offsetof(VHEState, cnthp_tval_el2), LOW(32) },
    /* EL2 virtual timer (FEAT_VHE) */
    { VHE_SYSREG(3, 4, 14, 3, 1), offsetof(VHEState, cnthv_ctl_el2),  LOW(3) },
    { VHE_SYSREG(3, 4, 14, 3, 2), offsetof(VHEState, cnthv_cval_el2), ALL },
    { VHE_SYSREG(3, 4, 14, 3, 0), offsetof(VHEState, cnthv_tval_el2), LOW(32) },
};

/* E2H-aliased registers (ARM ARM D8.1.3; KVM arch/arm64/kvm/nested.c):
 * shadow slot when E2H=0, redirect to the EL1 counterpart when E2H=1. */
static const struct {
    uint32_t reg;
    uint32_t el1_target;
    size_t offset;
} e2h_alias_regs[] = {
    { VHE_SYSREG(3, 4, 1, 0, 0),  VHE_SYSREG(3, 0, 1, 0, 0),
      offsetof(VHEState, sctlr_el2) },
    { VHE_SYSREG(3, 4, 1, 1, 2),  VHE_SYSREG(3, 0, 1, 0, 2),  /* CPACR_EL1 */
      offsetof(VHEState, cptr_el2) },
    { VHE_SYSREG(3, 4, 2, 0, 0),  VHE_SYSREG(3, 0, 2, 0, 0),
      offsetof(VHEState, ttbr0_el2) },
    { VHE_SYSREG(3, 4, 2, 0, 1),  VHE_SYSREG(3, 0, 2, 0, 1),
      offsetof(VHEState, ttbr1_el2) },
    { VHE_SYSREG(3, 4, 2, 0, 2),  VHE_SYSREG(3, 0, 2, 0, 2),
      offsetof(VHEState, tcr_el2) },
    { VHE_SYSREG(3, 4, 5, 1, 0),  VHE_SYSREG(3, 0, 5, 1, 0),
      offsetof(VHEState, afsr0_el2) },
    { VHE_SYSREG(3, 4, 5, 1, 1),  VHE_SYSREG(3, 0, 5, 1, 1),
      offsetof(VHEState, afsr1_el2) },
    { VHE_SYSREG(3, 4, 5, 2, 0),  VHE_SYSREG(3, 0, 5, 2, 0),
      offsetof(VHEState, esr_el2) },
    { VHE_SYSREG(3, 4, 6, 0, 0),  VHE_SYSREG(3, 0, 6, 0, 0),
      offsetof(VHEState, far_el2) },
    { VHE_SYSREG(3, 4, 10, 2, 0), VHE_SYSREG(3, 0, 10, 2, 0),
      offsetof(VHEState, mair_el2) },
    { VHE_SYSREG(3, 4, 10, 3, 0), VHE_SYSREG(3, 0, 10, 3, 0),
      offsetof(VHEState, amair_el2) },
    { VHE_SYSREG(3, 4, 12, 0, 0), VHE_SYSREG(3, 0, 12, 0, 0),
      offsetof(VHEState, vbar_el2) },
    { VHE_SYSREG(3, 4, 13, 0, 1), VHE_SYSREG(3, 0, 13, 0, 1),
      offsetof(VHEState, contextidr_el2) },
    { VHE_SYSREG(3, 4, 14, 1, 0), VHE_SYSREG(3, 0, 14, 1, 0), /* CNTKCTL_EL1 */
      offsetof(VHEState, cnthctl_el2) },
};

#define ARRAY_LEN(a) (sizeof(a) / sizeof((a)[0]))

/* Effective E2H governs the register aliasing view. ARM ARM: when
 * HCR_EL2.TGE==1 the PE behaves as if E2H==1 for all purposes other than
 * reading the bit — so TGE forces the aliased (host) view on. */
static int e2h_enabled(const VHEState *s)
{
    return (s->hcr_el2 & (VHE_HCR_E2H | VHE_HCR_TGE)) != 0;
}

/* Resolve reg to either a shadow slot or an EL1 redirect target.
 * On VHE_HANDLED fills *slot and *mask; on VHE_REDIRECT_EL1 fills *target.
 * E2H-aliased registers get RES0 masking on the real EL1 register, so the
 * shadow-fallback path here masks nothing (ALL). */
static VHEAction resolve(VHEState *s, uint32_t reg, uint64_t **slot,
                         uint64_t *mask, uint32_t *target)
{
    for (size_t i = 0; i < ARRAY_LEN(shadow_regs); i++) {
        if (shadow_regs[i].reg == reg) {
            *slot = (uint64_t *)((char *)s + shadow_regs[i].offset);
            *mask = shadow_regs[i].write_mask;
            return VHE_HANDLED;
        }
    }
    for (size_t i = 0; i < ARRAY_LEN(e2h_alias_regs); i++) {
        if (e2h_alias_regs[i].reg == reg) {
            if (e2h_enabled(s)) {
                *target = e2h_alias_regs[i].el1_target;
                return VHE_REDIRECT_EL1;
            }
            *slot = (uint64_t *)((char *)s + e2h_alias_regs[i].offset);
            *mask = ALL;
            return VHE_HANDLED;
        }
    }
    return VHE_UNHANDLED;
}

VHEAction vhe_sysreg_read(VHEState *s, uint32_t reg, uint64_t *val,
                          uint32_t *target)
{
    uint64_t *slot = NULL, mask = ALL;
    VHEAction act = resolve(s, reg, &slot, &mask, target);

    if (act == VHE_HANDLED) {
        *val = *slot;
    }
    return act;
}

VHEAction vhe_sysreg_write(VHEState *s, uint32_t reg, uint64_t val,
                           uint32_t *target)
{
    uint64_t *slot = NULL, mask = ALL;
    VHEAction act = resolve(s, reg, &slot, &mask, target);

    if (act == VHE_HANDLED) {
        *slot = val & mask;
    }
    return act;
}
