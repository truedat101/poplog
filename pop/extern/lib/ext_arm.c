#include <string.h>
#include <stdint.h>

#if defined(__aarch64__)

/*
 * AArch64 (ARM64) external call argument marshalling.
 *
 * AAPCS64 calling convention:
 *   - 8 integer argument registers: x0-x7 (64-bit)
 *   - 8 FP argument registers: d0-d7 (singles use s0-s7)
 *   - Stack arguments are 8 bytes each, 16-byte aligned stack
 *
 * Unlike ARM32, there is no interleaving of single/double FP allocation.
 * Each FP argument simply uses the next available FP register (d0-d7),
 * regardless of whether it's single or double precision.
 */

struct registers_buffer {
    uint64_t i_reg[8];
    double f_reg[8];
};

typedef struct registers_buffer reg_buff;

typedef struct arg_state { int ni; int fi; int si; } arg_state;

static void
store_single(arg_state * as, void * sp, reg_buff * rp, float val) {
    double dval_storage;
    int fi = as->fi;
    if (fi < 8) {
        /* Store single in FP register slot (zero-extended to double width) */
        memset(&dval_storage, 0, sizeof(dval_storage));
        memcpy(&dval_storage, &val, sizeof(val));
        rp->f_reg[fi] = dval_storage;
        as->fi++;
    } else {
        /* Spill to stack as 8-byte slot */
        uint64_t slot = 0;
        memcpy(&slot, &val, sizeof(val));
        *((uint64_t *)sp + as->si) = slot;
        as->si++;
    }
}

static void
store_double(arg_state * as, void * sp, reg_buff * rp, double val) {
    int fi = as->fi;
    if (fi < 8) {
        rp->f_reg[fi] = val;
        as->fi++;
    } else {
        *((double *)((uint64_t *)sp + as->si)) = val;
        as->si++;
    }
}

static void
store_int(arg_state * as, void * sp, reg_buff * rp, uint64_t val) {
    int ni = as->ni;
    if (ni < 8) {
        rp->i_reg[ni] = val;
        as->ni++;
    } else {
        *((uint64_t *)sp + as->si) = val;
        as->si++;
    }
}

/* Must agree with syscomp/wordflags.p */
#define ET_DDEC 2

/* Must agree with offset in syscomp/symdefs.p
 * On 64-bit the key pointer points at K_FLAGS; K_EXTERN_TYPE is at
 *   2 ints (K_FLAGS, K_GC_TYPE)            =  8 bytes
 * + 10 fulls (K_GET_SIZE .. K_HASH)        = 80 bytes
 * + 2 bytes (K_NUMBER_TYPE, K_PLOG_TYPE)   =  2 bytes  -> 90.
 * (The old value 98 mis-counted the two ints as fulls: it read a byte
 * of K_CONS_R instead, so every compound arg looked "dereference" --
 * exfunc closures were passed by content and ET_DDEC never matched.)
 */
#define ET_OFF 90

void
copy_external_arguments(int n, uint64_t * ap, void * sp, reg_buff * rp,
                        int fltsingle) {
    int i;
    arg_state as = {0, 0, 0};
    ap += (n - 1);
    for(i = 0; i < n; i++, fltsingle >>= 1) {
        uint64_t ai = *ap;
        ap--;
        if (ai & 1) {
            /* simple */
            if (ai & 2) {
                /* integer */
                store_int(&as, sp, rp, (int64_t)ai >> 2);
            } else {
                /* single float - value is in upper bits minus tag */
                uint32_t raw = (uint32_t)(ai - 1);
                float fval;
                memcpy(&fval, &raw, sizeof(fval));
                if (fltsingle & 1) {
                    store_single(&as, sp, rp, fval);
                } else {
                    double dval = fval;
                    store_double(&as, sp, rp, dval);
                }
            }
        } else {
            unsigned char * ak = ((unsigned char * *)ai)[-1];
            unsigned char et = *(ak + ET_OFF);
            if (et == ET_DDEC) {
                double dval;
                memcpy(&dval, (void *)ai, sizeof(double));
                if (fltsingle & 1) {
                    float fval = dval;
                    store_single(&as, sp, rp, fval);
                } else {
                    store_double(&as, sp, rp, dval);
                }
            } else {
                uint64_t val;
                if (et == 0) {
                    val = ai;
                } else {
                    /* External pointer or bignum: dereference */
                    val = *(uint64_t *)ai;
                }
                store_int(&as, sp, rp, val);
            }
        }
    }
}

#elif defined(__arm__)

/*
 * ARM32 external call argument marshalling.
 *
 * AAPCS calling convention:
 *   - 4 integer argument registers: r0-r3 (32-bit)
 *   - 8 FP co-processor registers d0-d7 (with single/double interleaving)
 */

struct registers_buffer {
    int i_reg[4];
    union {double d; struct {float sl; float sh;} sf2;} f_reg[8];
};

typedef struct registers_buffer reg_buff;

typedef struct arg_state { int ni; int sfi; int dfi; int si;} arg_state;

#if 0

#include <stdio.h>

void
print_arg_state(arg_state * as) {
    printf("ni = %d, sfi = %d, dfi = %d, si = %d\n",
           as->ni, as->sfi, as->dfi, as->si);
}

#define PR_AS (print_arg_state(as))

#else

#define PR_AS do {} while(0)

#endif
static void
store_single(arg_state * as, void * sp, reg_buff * rp, float val) {
    float * dst;
    int sfi = as->sfi;
    PR_AS;
    if (sfi < 16) {
        int dfi1 = sfi >> 1;
        if (sfi & 1) {
            dst = &(rp->f_reg[dfi1].sf2.sh);
            as->sfi = (as->dfi)<<1;
        } else {
            dst = &(rp->f_reg[dfi1].sf2.sl);
            as->sfi++;
            as->dfi = (as->dfi > dfi1)?as->dfi:(dfi1 + 1);
        }
    } else {
        dst = (float *)sp + as->si;
        as->si++;
    }
    memcpy(dst, &val, sizeof(val));
}

static void
store_double(arg_state * as, void * sp, reg_buff * rp, double val) {
    int dfi = as->dfi;
    double * dst;
    PR_AS;
    if (dfi < 8) {
        dst = &(rp->f_reg[dfi].d);
        as->dfi++;
        if (as->sfi == (dfi<<1)) {
            as->sfi = (as->dfi<<1);
        }
    } else {
        int si = as->si;
        as->sfi = 16;
        si = (si + 1)&(~1);
        dst = (double *)sp + (si>>1);
        as->si = si + 2;
    }
    memcpy(dst, &val, sizeof(val));
}

static void
store_int(arg_state * as, void * sp, reg_buff * rp, int val) {
    int ni = as->ni;
    PR_AS;
    if (ni < 4) {
        rp->i_reg[ni] = val;
        as->ni++;
    } else {
        *((int *)sp + as->si) = val;
        as->si++;
    }
}

/* Must agree with syscomp/wordflags.p */
#define ET_DDEC 2

/* Must agree with offset in syscomp/symdefs.p */
#define ET_OFF (4*12+2)
void
copy_external_arguments(int n, int * ap, void * sp, reg_buff * rp,
                        int fltsingle) {
    int i;
    arg_state as = {0, 0, 0, 0};
    ap += (n - 1);
    for(i = 0; i < n; i++, fltsingle >>= 1) {
        int ai = *ap;
        ap--;
        if (ai & 1) {
            /* simple */
            if (ai & 2) {
                /* integer */
                store_int(&as, sp, rp, ai >>= 2);
            } else {
                /* single float */
                ai -= 1;
                float fval;
                memcpy(&fval, &ai, sizeof(ai));
                if (fltsingle & 1) {
                    store_single(&as, sp, rp, fval);
                } else {
                    double dval = fval;
                    store_double(&as, sp, rp, dval);
                }
            }
        } else {
            unsigned char * ak = ((unsigned char * *)ai)[-1];
            unsigned char et = *(ak + ET_OFF);
            if (et == ET_DDEC) {
                double dval;
                memcpy(&dval, (int *)ai, 4);
                memcpy(((int *)&dval)+1, (int *)ai - 2, 4);
                if (fltsingle & 1) {
                    float fval = dval;
                    store_single(&as, sp, rp, fval);
                } else {
                    store_double(&as, sp, rp, dval);
                }
            } else {
                int val;
                if (et == 0) {
                    val = ai;
                } else {
                    /* External pointer of bignum: derefernce */
                    val = *(int *)ai;
                }
                store_int(&as, sp, rp, val);
            }
        }
    }
}

#endif /* __arm__ */
