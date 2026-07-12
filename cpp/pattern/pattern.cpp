#include "pattern.h"
#include <assert.h>   // 开发期断言

/* --------------------------------------------------------------
 * 1. 简单插入排序（升序）实现
 * -------------------------------------------------------------- */
static void insertion_sort(int *arr, int n)
{
    for (int i = 1; i < n; ++i) {
        int key = arr[i];
        int j = i - 1;
        while (j >= 0 && arr[j] > key) {
            arr[j + 1] = arr[j];
            --j;
        }
        arr[j + 1] = key;
    }
}

/* --------------------------------------------------------------
 * 2. pattern_init
 * -------------------------------------------------------------- */
int pattern_init(const int hand13[13], Pattern* out)
{
    if (!hand13 || !out) {
        return -1;   // 参数为空
    }

    for (int i = 0; i < 13; ++i) {
        out->hand[i] = hand13[i];
    }

    /* 这里不对 head / middle / tail 进行任何填充，保持未定义。
       用户会通过 pattern_set_position 提交自己的划分。 */
    return 0;
}

/* --------------------------------------------------------------
 * 3. pattern_get_position
 * -------------------------------------------------------------- */
int pattern_get_position(const Pattern* p, int position, int* out_buf)
{
    if (!p || !out_buf) {
        return -1;
    }

    switch (position) {
        case 0: // head
            for (int i = 0; i < 3; ++i) out_buf[i] = p->head[i];
            break;
        case 1: // middle
            for (int i = 0; i < 5; ++i) out_buf[i] = p->middle[i];
            break;
        case 2: // tail
            for (int i = 0; i < 5; ++i) out_buf[i] = p->tail[i];
            break;
        default:
            return -2; // 非法 position
    }
    return 0;
}

/* --------------------------------------------------------------
 * 4. pattern_set_position
 * -------------------------------------------------------------- */
int pattern_set_position(Pattern* p, int position,
                        const int* new_cards, int count)
{
    if (!p || !new_cards) {
        return -1;
    }

    if (position == 0) {               // head
        if (count != 3) return -3;
        for (int i = 0; i < 3; ++i) p->head[i] = new_cards[i];
    } else if (position == 1) {        // middle
        if (count != 5) return -3;
        for (int i = 0; i < 5; ++i) p->middle[i] = new_cards[i];
    } else if (position == 2) {        // tail
        if (count != 5) return -3;
        for (int i = 0; i < 5; ++i) p->tail[i] = new_cards[i];
    } else {
        return -2; // 非法 position
    }

    return 0;
}

/* --------------------------------------------------------------
 * 5. pattern_sort
 * -------------------------------------------------------------- */
int pattern_sort(Pattern* p)
{
    if (!p) return -1;

    /* 对 hand 整体排序 */
    insertion_sort(p->hand, 13);

    /* 对已经写入的墩位进行排序。若用户尚未写入，
       这里仍然安全地对数组进行排序（未定义内容会被排序），
       这不会影响后续用户再次写入的正确性。 */
    insertion_sort(p->head, 3);
    insertion_sort(p->middle, 5);
    insertion_sort(p->tail, 5);

    return 0;
}