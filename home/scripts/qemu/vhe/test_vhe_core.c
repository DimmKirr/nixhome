/* Unit tests for the VHE emulation core (NMD-253 pre-work).
 *
 * The core is deliberately standalone C so it can be TDD'd on any host;
 * it becomes target/arm/hvf/hvf-vhe.c when folded into the QEMU patch.
 *
 * Build+run: ./test.sh
 */
#include <assert.h>
#include <stdio.h>

#include "vhe_core.h"

static int tests_run;

#define RUN(t) do { t(); tests_run++; printf("ok %d - %s\n", tests_run, #t); } while (0)

/* HCR_EL2 (3,4,1,1,0) is pure shadow state: a write lands in the state
 * struct, a read returns it. */
static void test_hcr_el2_shadow_write_read(void)
{
    VHEState s = {0};
    uint32_t target = 0;
    uint64_t val = 0;

    assert(vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 1, 1, 0), 0x80000000ULL,
                            &target) == VHE_HANDLED);
    assert(s.hcr_el2 == 0x80000000ULL);

    assert(vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 1, 1, 0), &val,
                           &target) == VHE_HANDLED);
    assert(val == 0x80000000ULL);
}

/* A sysreg the core doesn't know is UNHANDLED — caller decides what to do
 * (inject UNDEF / fall through to QEMU's own handler). */
static void test_unknown_reg_unhandled(void)
{
    VHEState s = {0};
    uint32_t target = 0;
    uint64_t val = 0;

    /* S3_7_C15_C15_7 — implementation-defined space, not in any table */
    assert(vhe_sysreg_write(&s, VHE_SYSREG(3, 7, 15, 15, 7), 1,
                            &target) == VHE_UNHANDLED);
    assert(vhe_sysreg_read(&s, VHE_SYSREG(3, 7, 15, 15, 7), &val,
                           &target) == VHE_UNHANDLED);
}

/* Every pure-shadow EL2 sysreg (no EL1 counterpart, value lives in the
 * state struct) round-trips through its own slot. Encodings from the ARM
 * ARM, cross-checked against QEMU hvf.c and parse_sysreg_trace.py. */
static void test_pure_shadow_regs_roundtrip(void)
{
    static const struct { uint32_t reg; const char *name; } regs[] = {
        { VHE_SYSREG(3, 4, 0, 0, 0),  "VPIDR_EL2" },
        { VHE_SYSREG(3, 4, 0, 0, 5),  "VMPIDR_EL2" },
        { VHE_SYSREG(3, 4, 1, 1, 0),  "HCR_EL2" },
        { VHE_SYSREG(3, 4, 1, 1, 1),  "MDCR_EL2" },
        { VHE_SYSREG(3, 4, 1, 1, 3),  "HSTR_EL2" },
        { VHE_SYSREG(3, 4, 1, 1, 7),  "HACR_EL2" },
        { VHE_SYSREG(3, 4, 2, 1, 0),  "VTTBR_EL2" },
        { VHE_SYSREG(3, 4, 2, 1, 2),  "VTCR_EL2" },
        { VHE_SYSREG(3, 4, 13, 0, 2), "TPIDR_EL2" },
        { VHE_SYSREG(3, 4, 14, 0, 3), "CNTVOFF_EL2" },
    };
    VHEState s = {0};
    uint32_t target = 0;

    for (size_t i = 0; i < sizeof(regs) / sizeof(regs[0]); i++) {
        uint64_t wval = 0x1000 + i, rval = 0;

        if (vhe_sysreg_write(&s, regs[i].reg, wval, &target) != VHE_HANDLED) {
            fprintf(stderr, "write not handled: %s\n", regs[i].name);
            assert(0);
        }
        if (vhe_sysreg_read(&s, regs[i].reg, &rval, &target) != VHE_HANDLED) {
            fprintf(stderr, "read not handled: %s\n", regs[i].name);
            assert(0);
        }
        if (rval != wval) {
            fprintf(stderr, "bad value for %s\n", regs[i].name);
            assert(0);
        }
    }
}

/* Distinct registers must not share a slot. */
static void test_shadow_slots_are_distinct(void)
{
    VHEState s = {0};
    uint32_t target = 0;
    uint64_t val = 0;

    vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 2, 1, 0), 0xAAAA, &target); /* VTTBR */
    vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 2, 1, 2), 0xBBBB, &target); /* VTCR */
    vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 2, 1, 0), &val, &target);
    assert(val == 0xAAAA);
}

/* VHE E2H redirection (ARM ARM D8.1.3, KVM arch/arm64/kvm/nested.c):
 * with HCR_EL2.E2H=1, accesses to these _EL2 registers are aliases of
 * their _EL1 counterparts. Our fake "EL2" runs at real EL1, so the core
 * answers REDIRECT_EL1 with the op1=0 counterpart encoding and the QEMU
 * glue applies it to the real register. */
static void test_e2h_set_redirects_sctlr_el2_to_el1(void)
{
    VHEState s = { .hcr_el2 = VHE_HCR_E2H };
    uint32_t target = 0;
    uint64_t val = 0;

    assert(vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 1, 0, 0), 0x30D00805,
                            &target) == VHE_REDIRECT_EL1);
    assert(target == VHE_SYSREG(3, 0, 1, 0, 0)); /* SCTLR_EL1 */

    target = 0;
    assert(vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 1, 0, 0), &val,
                           &target) == VHE_REDIRECT_EL1);
    assert(target == VHE_SYSREG(3, 0, 1, 0, 0));
}

/* With E2H clear (nVHE view), the same registers are independent EL2
 * registers — plain shadow storage, no redirection. */
static void test_e2h_clear_sctlr_el2_is_shadow(void)
{
    VHEState s = {0};
    uint32_t target = 0;
    uint64_t val = 0;

    assert(vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 1, 0, 0), 0x1234,
                            &target) == VHE_HANDLED);
    assert(vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 1, 0, 0), &val,
                           &target) == VHE_HANDLED);
    assert(val == 0x1234);
}

/* Full E2H alias table: each EL2 register maps to its EL1 counterpart. */
static void test_e2h_redirect_table(void)
{
    static const struct {
        uint32_t el2, el1;
        const char *name;
    } aliases[] = {
        { VHE_SYSREG(3, 4, 1, 0, 0),  VHE_SYSREG(3, 0, 1, 0, 0),  "SCTLR" },
        { VHE_SYSREG(3, 4, 1, 1, 2),  VHE_SYSREG(3, 0, 1, 0, 2),  "CPTR->CPACR" },
        { VHE_SYSREG(3, 4, 2, 0, 0),  VHE_SYSREG(3, 0, 2, 0, 0),  "TTBR0" },
        { VHE_SYSREG(3, 4, 2, 0, 1),  VHE_SYSREG(3, 0, 2, 0, 1),  "TTBR1" },
        { VHE_SYSREG(3, 4, 2, 0, 2),  VHE_SYSREG(3, 0, 2, 0, 2),  "TCR" },
        { VHE_SYSREG(3, 4, 5, 1, 0),  VHE_SYSREG(3, 0, 5, 1, 0),  "AFSR0" },
        { VHE_SYSREG(3, 4, 5, 1, 1),  VHE_SYSREG(3, 0, 5, 1, 1),  "AFSR1" },
        { VHE_SYSREG(3, 4, 5, 2, 0),  VHE_SYSREG(3, 0, 5, 2, 0),  "ESR" },
        { VHE_SYSREG(3, 4, 6, 0, 0),  VHE_SYSREG(3, 0, 6, 0, 0),  "FAR" },
        { VHE_SYSREG(3, 4, 10, 2, 0), VHE_SYSREG(3, 0, 10, 2, 0), "MAIR" },
        { VHE_SYSREG(3, 4, 10, 3, 0), VHE_SYSREG(3, 0, 10, 3, 0), "AMAIR" },
        { VHE_SYSREG(3, 4, 12, 0, 0), VHE_SYSREG(3, 0, 12, 0, 0), "VBAR" },
        { VHE_SYSREG(3, 4, 13, 0, 1), VHE_SYSREG(3, 0, 13, 0, 1), "CONTEXTIDR" },
        { VHE_SYSREG(3, 4, 14, 1, 0), VHE_SYSREG(3, 0, 14, 1, 0), "CNTHCTL->CNTKCTL" },
    };
    VHEState s = { .hcr_el2 = VHE_HCR_E2H };
    uint32_t target;

    for (size_t i = 0; i < sizeof(aliases) / sizeof(aliases[0]); i++) {
        target = 0;
        if (vhe_sysreg_write(&s, aliases[i].el2, 0, &target)
                != VHE_REDIRECT_EL1 || target != aliases[i].el1) {
            fprintf(stderr, "bad redirect: %s\n", aliases[i].name);
            assert(0);
        }
    }
}

/* HCR_EL2 itself must NEVER redirect — it's always shadow state, even
 * with E2H set (writing it is how the guest controls E2H). */
static void test_hcr_el2_never_redirects(void)
{
    VHEState s = { .hcr_el2 = VHE_HCR_E2H };
    uint32_t target = 0;

    assert(vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 1, 1, 0),
                            VHE_HCR_E2H, &target) == VHE_HANDLED);
}

/* RES0 masking on write (ARM ARM register definitions): reserved bits
 * read as zero regardless of what the guest wrote. HSTR_EL2 defines only
 * T<n> in bits [15:0]; everything above is RES0. */
static void test_hstr_el2_res0_masked_on_write(void)
{
    VHEState s = {0};
    uint32_t target = 0;
    uint64_t val = 0;

    assert(vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 1, 1, 3), ~0ULL,
                            &target) == VHE_HANDLED);
    assert(vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 1, 1, 3), &val,
                           &target) == VHE_HANDLED);
    assert(val == 0x000000000000FFFFULL);
}

/* VTCR_EL2 is a 32-bit configuration register: bits [63:32] are RES0. */
static void test_vtcr_el2_high_bits_res0(void)
{
    VHEState s = {0};
    uint32_t target = 0;
    uint64_t val = 0;

    vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 2, 1, 2), ~0ULL, &target);
    vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 2, 1, 2), &val, &target);
    assert((val >> 32) == 0);
}

/* Registers with no RES0 mask keep the full 64-bit value (e.g. CNTVOFF). */
static void test_full_width_reg_unmasked(void)
{
    VHEState s = {0};
    uint32_t target = 0;
    uint64_t val = 0;

    vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 14, 0, 3), ~0ULL, &target);
    vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 14, 0, 3), &val, &target);
    assert(val == ~0ULL);
}

/* ARM ARM: when HCR_EL2.TGE==1, the PE behaves as if HCR_EL2.E2H==1 for
 * all purposes other than reading the bit. So SCTLR_EL2 redirects even
 * with E2H physically 0, as long as TGE is set. */
static void test_tge_forces_effective_e2h(void)
{
    VHEState s = { .hcr_el2 = VHE_HCR_TGE };  /* TGE=1, E2H=0 */
    uint32_t target = 0;

    assert(vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 1, 0, 0), 0,
                            &target) == VHE_REDIRECT_EL1);
    assert(target == VHE_SYSREG(3, 0, 1, 0, 0));
}

/* ...but the "other than reading the bit" carve-out: reading HCR_EL2 back
 * returns exactly what was written (E2H stays physically 0). */
static void test_tge_does_not_forge_e2h_bit_on_read(void)
{
    VHEState s = {0};
    uint32_t target = 0;
    uint64_t val = 0;

    vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 1, 1, 0), VHE_HCR_TGE, &target);
    vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 1, 1, 0), &val, &target);
    assert(val == VHE_HCR_TGE);              /* E2H bit still 0 */
    assert((val & VHE_HCR_E2H) == 0);
}

/* Neither bit set → nVHE view, shadow storage, no redirection. */
static void test_no_e2h_no_tge_is_shadow(void)
{
    VHEState s = {0};
    uint32_t target = 0;

    assert(vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 1, 0, 0), 0x99,
                            &target) == VHE_HANDLED);
}

/* Exception + fault-reporting EL2 registers are pure shadow state (no EL1
 * alias): ELR_EL2, SPSR_EL2, HPFAR_EL2. SPSR is 32-bit (RES0 high half). */
static void test_exception_regs_shadow(void)
{
    VHEState s = {0};
    uint32_t target = 0;
    uint64_t val = 0;

    vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 4, 0, 1), 0xFFFF000012345678ULL,
                     &target);                                  /* ELR_EL2 */
    vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 4, 0, 1), &val, &target);
    assert(val == 0xFFFF000012345678ULL);

    vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 4, 0, 0), ~0ULL, &target); /* SPSR */
    vhe_sysreg_read(&s, VHE_SYSREG(3, 4, 4, 0, 0), &val, &target);
    assert((val >> 32) == 0);

    assert(vhe_sysreg_write(&s, VHE_SYSREG(3, 4, 6, 0, 4), 1,
                            &target) == VHE_HANDLED);           /* HPFAR_EL2 */
}

/* EL2 physical and virtual timers: CNTHP_* and CNTHV_*. CTL is 3 bits;
 * CVAL is full 64-bit; TVAL is a 32-bit view. */
static void test_el2_timers_shadow_and_masks(void)
{
    static const struct { uint32_t reg; uint64_t in, out; } cases[] = {
        { VHE_SYSREG(3, 4, 14, 2, 1), ~0ULL, 0x7 },        /* CNTHP_CTL  */
        { VHE_SYSREG(3, 4, 14, 2, 2), ~0ULL, ~0ULL },      /* CNTHP_CVAL */
        { VHE_SYSREG(3, 4, 14, 2, 0), ~0ULL, 0xFFFFFFFF }, /* CNTHP_TVAL */
        { VHE_SYSREG(3, 4, 14, 3, 1), ~0ULL, 0x7 },        /* CNTHV_CTL  */
        { VHE_SYSREG(3, 4, 14, 3, 2), ~0ULL, ~0ULL },      /* CNTHV_CVAL */
        { VHE_SYSREG(3, 4, 14, 3, 0), ~0ULL, 0xFFFFFFFF }, /* CNTHV_TVAL */
    };
    VHEState s = {0};
    uint32_t target = 0;

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        uint64_t val = 0;
        assert(vhe_sysreg_write(&s, cases[i].reg, cases[i].in, &target)
               == VHE_HANDLED);
        assert(vhe_sysreg_read(&s, cases[i].reg, &val, &target)
               == VHE_HANDLED);
        if (val != cases[i].out) {
            fprintf(stderr, "timer reg %zu: got %llx want %llx\n", i,
                    (unsigned long long)val, (unsigned long long)cases[i].out);
            assert(0);
        }
    }
}

int main(void)
{
    RUN(test_hcr_el2_shadow_write_read);
    RUN(test_unknown_reg_unhandled);
    RUN(test_pure_shadow_regs_roundtrip);
    RUN(test_shadow_slots_are_distinct);
    RUN(test_e2h_set_redirects_sctlr_el2_to_el1);
    RUN(test_e2h_clear_sctlr_el2_is_shadow);
    RUN(test_e2h_redirect_table);
    RUN(test_hcr_el2_never_redirects);
    RUN(test_hstr_el2_res0_masked_on_write);
    RUN(test_vtcr_el2_high_bits_res0);
    RUN(test_full_width_reg_unmasked);
    RUN(test_tge_forces_effective_e2h);
    RUN(test_tge_does_not_forge_e2h_bit_on_read);
    RUN(test_no_e2h_no_tge_is_shadow);
    RUN(test_exception_regs_shadow);
    RUN(test_el2_timers_shadow_and_masks);
    printf("1..%d\n", tests_run);
    return 0;
}
