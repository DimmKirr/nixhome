// Bare-metal aarch64 EL2 "poke-and-see" probe (NMD-251).
//
// Boots directly at EL2 under `-machine virt,virtualization=on -kernel
// el2_probe.bin`. No Linux => no idreg-override refusal, no PARange confound,
// no PCI. It interrogates the guest-EL2 from many angles:
//   - baseline reads of ID + EL2 core registers (what does Apple expose?)
//   - write/read-back of EL2 + nested (stage-2) registers (what sticks?)
//   - set HCR_EL2.E2H, then poke VHE-only registers + _EL12 aliases + VHE
//     timers (does VHE behavior exist, or do they UNDEF?)
//
// Every access is tagged; a sync exception is caught by our EL2 vector table,
// which prints [EL2-PROBE] EXC tag/esr/far and RESUMES (skips the faulting
// instruction) so ONE undef doesn't stop the battery. Read-back sentinel is
// 0xffffffffffffffff => "access was skipped (UNDEF)".
//
// Verdict keys (compare HVF vs the TCG control):
//   E2H_readback=...0x1 + TTBR1_EL2 round-trips 0x5678abcd1234 => VHE EXISTS
//   E2H_readback=...0x0  OR  EXC on VHE regs                   => VHE ABSENT

    .cpu generic+nofp

    // read sysreg <sreg>, print "<name>=0x...."; sentinel -1 if it UNDEFs
    .macro RD name, sreg, tag
    mov     x27, #\tag
    adr     x0, \name
    bl      puts
    movn    x1, #0                       // sentinel 0xffff...
    mrs     x1, \sreg
    mov     x0, x1
    bl      puthex64
    bl      putnl
    .endm

    // write sentinel to <sreg>, read back, print; either op may UNDEF (caught)
    .macro WR name, sreg, tag
    mov     x27, #\tag
    adr     x0, \name
    bl      puts
    movz    x2, #0x1234
    movk    x2, #0xabcd, lsl #16
    movk    x2, #0x5678, lsl #32
    msr     \sreg, x2
    isb
    movn    x1, #0
    mrs     x1, \sreg
    mov     x0, x1
    bl      puthex64
    bl      putnl
    .endm

    .section .text.start,"ax"
    .globl _start
_start:
    ldr     x19, =0x09000000            // PL011 UART DR
    adr     x0, vectors
    msr     VBAR_EL2, x0
    isb
    mov     x27, #0

    adr     x0, s_banner
    bl      puts

    // ---- (A) baseline: current EL + ID registers ----
    RD s_el,     CurrentEL,          1
    RD s_mmfr0,  ID_AA64MMFR0_EL1,   2
    RD s_mmfr1,  ID_AA64MMFR1_EL1,   3
    RD s_mmfr2,  ID_AA64MMFR2_EL1,   4
    RD s_pfr0,   ID_AA64PFR0_EL1,    5
    RD s_dfr0,   ID_AA64DFR0_EL1,    6
    RD s_midr,   MIDR_EL1,           7
    RD s_mpidr,  MPIDR_EL1,          8

    // ---- (B) EL2 core registers (should be present at EL2) ----
    RD s_hcr,    HCR_EL2,            10
    RD s_sctlr2, SCTLR_EL2,          11
    RD s_cptr2,  CPTR_EL2,           12
    RD s_cnthctl,S3_4_C14_C1_0,      13   // CNTHCTL_EL2
    RD s_mdcr2,  MDCR_EL2,           14

    // ---- (C) nested / stage-2 registers (needed for L2 VMs) ----
    WR s_vttbr,  S3_4_C2_C1_0,        20
    WR s_vtcr,   S3_4_C2_C1_2,        21

    // ---- (D) set HCR_EL2.E2H (bit 34), read back ----
    mrs     x21, HCR_EL2
    mov     x22, #1
    lsl     x22, x22, #34
    orr     x23, x21, x22
    msr     HCR_EL2, x23
    isb
    RD s_hcr_e2h, HCR_EL2,           30   // full HCR_EL2 after set (x1=value)
    // print E2H bit alone (robust verdict signal, independent of other bits)
    adr     x0, s_e2hbit
    bl      puts
    ubfx    x0, x1, #34, #1
    add     x0, x0, #'0'
    str     w0, [x19]
    mov     w0, #10
    str     w0, [x19]

    // ---- (E) VHE-only registers (valid ONLY if VHE behavior exists) ----
    WR s_ttbr1,  S3_4_C2_C0_1,       40   // TTBR1_EL2
    WR s_ctxid2, S3_4_C13_C0_1,      41   // CONTEXTIDR_EL2
    WR s_cnthvc, S3_4_C14_C3_1,      42   // CNTHV_CTL_EL2 (VHE vtimer)
    // ---- (F) _EL12 aliases (only valid when E2H=1) ----
    WR s_sctl12, S3_5_C1_C0_0,       50   // SCTLR_EL12
    WR s_ttbr012,S3_5_C2_C0_0,       51   // TTBR0_EL12

    adr     x0, s_done
    bl      puts
halt:
    wfi
    b       halt

// ---- exception handler: print tag/esr/far, SKIP faulting insn, resume ----
exc_common:
    adr     x0, s_exc
    bl      puts
    mov     x0, x27
    bl      puthex64
    adr     x0, s_esr
    bl      puts
    mrs     x0, ESR_EL2
    bl      puthex64
    adr     x0, s_far
    bl      puts
    mrs     x0, FAR_EL2
    bl      puthex64
    bl      putnl
    mrs     x0, ELR_EL2
    add     x0, x0, #4                  // skip the faulting instruction
    msr     ELR_EL2, x0
    eret

// ---- UART helpers (leaf, no stack) ----
puts:
    mov     x9, x0
1:  ldrb    w0, [x9], #1
    cbz     w0, 2f
    str     w0, [x19]
    b       1b
2:  ret
putnl:
    mov     w0, #10
    str     w0, [x19]
    ret
puthex64:
    mov     x10, x0
    mov     w0, #'0'
    str     w0, [x19]
    mov     w0, #'x'
    str     w0, [x19]
    mov     x11, #60
1:  lsr     x0, x10, x11
    and     x0, x0, #0xf
    cmp     x0, #10
    blt     3f
    add     x0, x0, #('a'-10)
    b       4f
3:  add     x0, x0, #'0'
4:  str     w0, [x19]
    subs    x11, x11, #4
    bge     1b
    ret

    .balign 0x800
vectors:
    .balign 0x80
    b exc_common
    .balign 0x80
    b exc_common
    .balign 0x80
    b exc_common
    .balign 0x80
    b exc_common
    .balign 0x80
    b exc_common
    .balign 0x80
    b exc_common
    .balign 0x80
    b exc_common
    .balign 0x80
    b exc_common

    .section .rodata
s_banner: .asciz "\n[EL2-PROBE] poke-and-see EL2/VHE battery\n"
s_el:     .asciz "[EL2-PROBE] CurrentEL="
s_mmfr0:  .asciz "[EL2-PROBE] ID_AA64MMFR0_EL1="
s_mmfr1:  .asciz "[EL2-PROBE] ID_AA64MMFR1_EL1(VH@8-11)="
s_mmfr2:  .asciz "[EL2-PROBE] ID_AA64MMFR2_EL1="
s_pfr0:   .asciz "[EL2-PROBE] ID_AA64PFR0_EL1(EL2@8-11)="
s_dfr0:   .asciz "[EL2-PROBE] ID_AA64DFR0_EL1="
s_midr:   .asciz "[EL2-PROBE] MIDR_EL1="
s_mpidr:  .asciz "[EL2-PROBE] MPIDR_EL1="
s_hcr:    .asciz "[EL2-PROBE] HCR_EL2_before="
s_sctlr2: .asciz "[EL2-PROBE] SCTLR_EL2="
s_cptr2:  .asciz "[EL2-PROBE] CPTR_EL2="
s_cnthctl:.asciz "[EL2-PROBE] CNTHCTL_EL2="
s_mdcr2:  .asciz "[EL2-PROBE] MDCR_EL2="
s_vttbr:  .asciz "[EL2-PROBE] VTTBR_EL2_wr="
s_vtcr:   .asciz "[EL2-PROBE] VTCR_EL2_wr="
s_hcr_e2h:.asciz "[EL2-PROBE] HCR_EL2_after_setE2H="
s_e2hbit: .asciz "[EL2-PROBE] E2H_bit="
s_ttbr1:  .asciz "[EL2-PROBE] TTBR1_EL2_wr(VHE)="
s_ctxid2: .asciz "[EL2-PROBE] CONTEXTIDR_EL2_wr(VHE)="
s_cnthvc: .asciz "[EL2-PROBE] CNTHV_CTL_EL2_wr(VHE)="
s_sctl12: .asciz "[EL2-PROBE] SCTLR_EL12_wr(alias)="
s_ttbr012:.asciz "[EL2-PROBE] TTBR0_EL12_wr(alias)="
s_exc:    .asciz "[EL2-PROBE] EXC tag="
s_esr:    .asciz " esr="
s_far:    .asciz " far="
s_done:   .asciz "[EL2-PROBE] DONE\n"
