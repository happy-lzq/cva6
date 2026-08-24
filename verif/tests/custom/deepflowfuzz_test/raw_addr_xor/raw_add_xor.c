#include <stdint.h>

static volatile uint64_t observed[4];

int main(void) {
    asm volatile(
        ".option push\n"
        ".option norvc\n"

        "li   t0, 17\n"
        "li   t1, 25\n"

        /* 正样本：add -> xor */
        "add  t2, t0, t1\n"
        "xor  t3, t2, t1\n"

        /* 负样本：xor 不读取 add 结果 */
        "add  t4, t0, t1\n"
        "xor  t5, t0, t1\n"

        "sd   t2,  0(%[out])\n"
        "sd   t3,  8(%[out])\n"
        "sd   t4, 16(%[out])\n"
        "sd   t5, 24(%[out])\n"

        ".option pop\n"
        :
        : [out] "r"(observed)
        : "t0", "t1", "t2", "t3", "t4", "t5", "memory"
    );

    if (observed[0] == 42 &&
        observed[1] == 51 &&
        observed[2] == 42 &&
        observed[3] == 8) {
        return 0;
    }

    return 1;
}