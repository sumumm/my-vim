// examples/fold_demo.c
// 用于验证 Vim 语法折叠：函数、if/else、for、while、switch、#if 0、块注释

#include <stdio.h>
#include <stdlib.h>

#define MAX_ITEMS 8

typedef struct {
    int id;
    const char *name;
} Item;

/*
 * 块注释本身也会形成折叠区域，
 * 把光标放在下面按 zc 可以收起这段注释。
 */

#if 0
/* 这段不参与编译，用于演示 #if 0 的预处理折叠 */
static void unused_helper(void)
{
    printf("unused\n");
}
#endif

static int sum_even(const int *values, int count)
{
    int sum = 0;

    for (int i = 0; i < count; i++) {
        if (values[i] % 2 != 0) {
            continue;
        }

        sum += values[i];
    }

    return sum;
}

static const char *classify(int value)
{
    if (value < 0) {
        return "negative";
    } else if (value == 0) {
        return "zero";
    } else {
        return "positive";
    }
}

static void print_items(const Item *items, int count)
{
    int i = 0;

    while (i < count) {
        switch (items[i].id % 3) {
        case 0:
            printf("[%d] %s (id %% 3 == 0)\n", items[i].id, items[i].name);
            break;
        case 1:
            printf("[%d] %s (id %% 3 == 1)\n", items[i].id, items[i].name);
            break;
        default:
            printf("[%d] %s (id %% 3 == 2)\n", items[i].id, items[i].name);
            break;
        }

        i++;
    }
}

int main(void)
{
    int values[] = {1, 2, 3, 4, 5, 6, 7, 8};
    Item items[MAX_ITEMS] = {
        {1, "alpha"},
        {2, "beta"},
        {3, "gamma"},
        {4, "delta"},
        {5, "epsilon"},
        {6, "zeta"},
        {7, "eta"},
        {8, "theta"},
    };
    int count = (int)(sizeof(values) / sizeof(values[0]));

    printf("sum of even values: %d\n", sum_even(values, count));
    printf("classify(-1) = %s\n", classify(-1));
    printf("classify(0)  = %s\n", classify(0));
    print_items(items, MAX_ITEMS);

    return EXIT_SUCCESS;
}
