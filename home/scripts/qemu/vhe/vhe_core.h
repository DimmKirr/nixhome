/*
 * VHE emulation core — shadow EL2 state and sysreg dispatch (NMD-253).
 *
 * Standalone-compilable; folds into target/arm/hvf/hvf-vhe.{c,h} in the
 * QEMU patch. The QEMU glue owns the real registers (via hv_vcpu_*); this
 * core only decides what a trapped access means:
 *
 *   VHE_UNHANDLED    — not ours; caller injects UNDEF or falls through
 *   VHE_HANDLED      — shadow state updated / value produced
 *   VHE_REDIRECT_EL1 — VHE E2H aliasing: caller must apply the access to
 *                      the real EL1 register named by *target
 */
#ifndef VHE_CORE_H
#define VHE_CORE_H

#include <stdint.h>

/* Packed sysreg encoding — identical to QEMU's SYSREG() in hvf.c */
#define VHE_SYSREG(op0, op1, crn, crm, op2) \
    (((op0) << 20) | ((op2) << 17) | ((op1) << 14) | ((crn) << 10) | ((crm) << 1))

typedef enum {
    VHE_UNHANDLED = 0,
    VHE_HANDLED,
    VHE_REDIRECT_EL1,
} VHEAction;

/* HCR_EL2 control bits (ARM ARM D19.2.48) */
#define VHE_HCR_TGE (1ULL << 27)
#define VHE_HCR_E2H (1ULL << 34)

typedef struct {
    /* Pure-shadow EL2 registers (no EL1 counterpart) */
    uint64_t vpidr_el2;
    uint64_t vmpidr_el2;
    uint64_t hcr_el2;
    uint64_t mdcr_el2;
    uint64_t hstr_el2;
    uint64_t hacr_el2;
    uint64_t vttbr_el2;
    uint64_t vtcr_el2;
    uint64_t tpidr_el2;
    uint64_t cntvoff_el2;
    /* Exception + fault reporting */
    uint64_t elr_el2;
    uint64_t spsr_el2;
    uint64_t hpfar_el2;
    /* EL2 physical timer (CNTHP_*) */
    uint64_t cnthp_ctl_el2;
    uint64_t cnthp_cval_el2;
    uint64_t cnthp_tval_el2;
    /* EL2 virtual timer (CNTHV_*, FEAT_VHE) */
    uint64_t cnthv_ctl_el2;
    uint64_t cnthv_cval_el2;
    uint64_t cnthv_tval_el2;
    /* E2H-aliased registers: shadow slot used when E2H=0 (independent
     * EL2 registers); with E2H=1 accesses redirect to the EL1 register */
    uint64_t sctlr_el2;
    uint64_t cptr_el2;
    uint64_t ttbr0_el2;
    uint64_t ttbr1_el2;
    uint64_t tcr_el2;
    uint64_t afsr0_el2;
    uint64_t afsr1_el2;
    uint64_t esr_el2;
    uint64_t far_el2;
    uint64_t mair_el2;
    uint64_t amair_el2;
    uint64_t vbar_el2;
    uint64_t contextidr_el2;
    uint64_t cnthctl_el2;
} VHEState;

VHEAction vhe_sysreg_read(VHEState *s, uint32_t reg, uint64_t *val,
                          uint32_t *target);
VHEAction vhe_sysreg_write(VHEState *s, uint32_t reg, uint64_t val,
                           uint32_t *target);

#endif
