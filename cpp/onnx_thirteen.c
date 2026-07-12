/*
 * onnx_thirteen.c — ONNX Runtime C wrapper + 十三水特征编码
 *
 * 跨平台版（去除 windows.h 依赖）
 *
 * Compile (Android NDK):
 *   ${NDK}/toolchains/llvm/prebuilt/windows-x86_64/bin/clang
 *     -target aarch64-linux-android24
 *     -I../flutter/lib/src/backend/include
 *     -I${ONNXRT_HOME}/include
 *     -shared -fPIC -o libonnx_thirteen.so onnx_thirteen.c
 *     -L${ONNXRT_HOME}/lib -lonnxruntime
 */

#include <onnxruntime_c_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ======================== 导出宏 (跨平台) ======================== */
#if defined(_WIN32)
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default")))
#endif

/* ======================== ORT 基础 ======================== */

static const OrtApi* api = NULL;
static char _last_error[512] = "";

static void _set_error(const OrtStatus* s) {
    if (!s) { _last_error[0] = '\0'; return; }
    const char* msg = api->GetErrorMessage(s);
    if (msg) { strncpy(_last_error, msg, sizeof(_last_error) - 1); _last_error[sizeof(_last_error) - 1] = '\0'; }
    api->ReleaseStatus(s);
}

EXPORT const char* oh_last_error(void) { return _last_error; }

EXPORT int oh_init(void) {
    if (api) return 0;
    OrtApiBase* base = (OrtApiBase*)OrtGetApiBase();
    if (!base) return -1;
    api = base->GetApi(ORT_API_VERSION);
    if (!api) return -2;
    return 0;
}

EXPORT void* oh_create_env(void) {
    OrtEnv* env = NULL;
    const OrtStatus* s = api->CreateEnv(2, "flutter", &env);
    if (s) { _set_error(s); return NULL; }
    return (void*)env;
}

EXPORT void oh_release_env(void* env) {
    if (env) api->ReleaseEnv((OrtEnv*)env);
}

EXPORT void* oh_create_session(void* env, const char* model_path) {
    OrtSessionOptions* opts = NULL;
    OrtSession* session = NULL;
    const OrtStatus* s;

    s = api->CreateSessionOptions(&opts);
    if (s) { _set_error(s); return NULL; }

    s = api->SetSessionExecutionMode(opts, ORT_SEQUENTIAL);
    if (s) { _set_error(s); api->ReleaseSessionOptions(opts); return NULL; }
    s = api->SetIntraOpNumThreads(opts, 1);
    if (s) { _set_error(s); api->ReleaseSessionOptions(opts); return NULL; }
    s = api->SetInterOpNumThreads(opts, 1);
    if (s) { _set_error(s); api->ReleaseSessionOptions(opts); return NULL; }
    s = api->SetSessionGraphOptimizationLevel(opts, ORT_ENABLE_BASIC);
    if (s) { _set_error(s); api->ReleaseSessionOptions(opts); return NULL; }

#if defined(_WIN32)
    int wlen = MultiByteToWideChar(CP_UTF8, 0, model_path, -1, NULL, 0);
    wchar_t* wpath = (wchar_t*)malloc(wlen * sizeof(wchar_t));
    MultiByteToWideChar(CP_UTF8, 0, model_path, -1, wpath, wlen);
    s = api->CreateSession((OrtEnv*)env, (const ORTCHAR_T*)wpath, opts, &session);
    free(wpath);
#else
    s = api->CreateSession((OrtEnv*)env, (const ORTCHAR_T*)model_path, opts, &session);
#endif

    if (s) { _set_error(s); api->ReleaseSessionOptions(opts); return NULL; }

    api->ReleaseSessionOptions(opts);
    _last_error[0] = '\0';
    return (void*)session;
}

EXPORT void oh_release_session(void* session) {
    if (session) api->ReleaseSession((OrtSession*)session);
}

/* ================================================================
 *  十三水特征编码 — 数据结构 & 辅助函数
 * ================================================================ */

struct tc_hand_result { int position; const char* hand_name; int rank_order; int score; };
struct tc_hand_unit { int card_count; int cards[5]; struct tc_hand_result result; };
struct tc_hand_combo {
    int unit_count;
    struct tc_hand_unit units[3];
    int typed_score;
    int loose_count;
    int loose_cards[13];
};
struct tc_dfs_result {
    int is_special;
    int special_score;
    const char* special_name;
    int combo_count;
    struct tc_hand_combo combos[128];
};

#define TC_CARD_DIM   17
#define TC_COMBO_DIM  74
#define TC_MAX_COMBOS 128

static inline int _tc_rank(int card_id) { return (card_id % 52) / 4; }
static inline int _tc_suit(int card_id) { return (card_id % 52) % 4; }

static int _tc_has_pair(const int* ranks, int n) {
    for (int i = 0; i < n; i++)
        for (int j = i + 1; j < n; j++)
            if (ranks[i] == ranks[j]) return 1;
    return 0;
}

static int _tc_has_trips(const int* ranks, int n) {
    int counts[13] = {0};
    for (int i = 0; i < n; i++) if (ranks[i] >= 0 && ranks[i] < 13) counts[ranks[i]]++;
    for (int i = 0; i < 13; i++) if (counts[i] >= 3) return 1;
    return 0;
}

static int _tc_is_straight(const int* ranks, int n) {
    if (n < 5) return 0;
    int seen[13] = {0};
    int sorted[13], m = 0;
    for (int i = 0; i < n; i++) if (ranks[i] >= 0 && ranks[i] < 13 && !seen[ranks[i]]) {
        seen[ranks[i]] = 1; sorted[m++] = ranks[i];
    }
    for (int i = 0; i < m - 1; i++)
        for (int j = 0; j < m - 1 - i; j++)
            if (sorted[j] > sorted[j + 1]) { int t = sorted[j]; sorted[j] = sorted[j + 1]; sorted[j + 1] = t; }
    for (int i = 0; i <= m - 5; i++)
        if (sorted[i + 4] - sorted[i] == 4) return 1;
    if (seen[12] && seen[0] && seen[1] && seen[2] && seen[3]) return 1;
    return 0;
}

/* ---------- 手牌编码 ---------- */

EXPORT int oh_tc_encode_hand(const int hand13[13], float* out_hand_tokens)
{
    for (int i = 0; i < 13; i++) {
        int card = hand13[i] % 52;
        int suit = _tc_suit(card);
        int rank = _tc_rank(card);
        float* v = out_hand_tokens + i * TC_CARD_DIM;
        memset(v, 0, TC_CARD_DIM * sizeof(float));
        v[suit] = 1.0f;
        v[4 + rank] = 1.0f;
    }
    return 0;
}

/* ---------- 单组合编码 (74-dim) ---------- */

static void _tc_unit_features(const struct tc_hand_unit* u, float* v) {
    memset(v, 0, 10 * sizeof(float));
    if (!u || u->card_count <= 0) return;

    v[0] = (u->card_count == 3) ? 1.0f : 0.0f;
    v[1] = u->result.rank_order / 10.0f;
    v[2] = u->result.score / 10.0f;

    int max_r = 0, min_r = 12;
    int suit_set[4] = {0};
    int ranks[5];
    int n_ranks = 0;
    for (int i = 0; i < u->card_count && i < 5; i++) {
        int cid = u->cards[i];
        int r = _tc_rank(cid);
        int s = _tc_suit(cid);
        if (r > max_r) max_r = r;
        if (r < min_r) min_r = r;
        suit_set[s] = 1;
        if (n_ranks < 5) ranks[n_ranks++] = r;
    }
    v[3] = max_r / 12.0f;
    v[4] = min_r / 12.0f;
    int n_suits = suit_set[0] + suit_set[1] + suit_set[2] + suit_set[3];
    v[5] = n_suits / 4.0f;
    v[6] = _tc_has_pair(ranks, n_ranks) ? 1.0f : 0.0f;
    v[7] = _tc_has_trips(ranks, n_ranks) ? 1.0f : 0.0f;
    v[8] = _tc_is_straight(ranks, n_ranks) ? 1.0f : 0.0f;
    v[9] = (n_suits == 1) ? 1.0f : 0.0f;
}

static void _tc_encode_combo(const struct tc_hand_combo* combo,
                             const int hand13[13], float* out)
{
    memset(out, 0, TC_COMBO_DIM * sizeof(float));
    int off = 0;

    out[off++] = combo->typed_score / 30.0f;
    out[off++] = combo->unit_count / 3.0f;
    out[off++] = combo->loose_count / 13.0f;

    int u3_idx[3], n_u3 = 0;
    int u5_idx[3], n_u5 = 0;
    for (int i = 0; i < combo->unit_count && i < 3; i++) {
        if (combo->units[i].card_count == 3) u3_idx[n_u3++] = i;
        else u5_idx[n_u5++] = i;
    }
    int ordered_idx[3], n_ordered = 0;
    for (int i = 0; i < n_u3; i++) ordered_idx[n_ordered++] = u3_idx[i];
    for (int i = 0; i < n_u5; i++) ordered_idx[n_ordered++] = u5_idx[i];

    float unit_feat[10];
    for (int i = 0; i < 3; i++) {
        if (i < n_ordered) {
            _tc_unit_features(&combo->units[ordered_idx[i]], unit_feat);
        } else {
            memset(unit_feat, 0, sizeof(unit_feat));
        }
        for (int j = 0; j < 10; j++) out[off++] = unit_feat[j];
    }

    for (int i = 0; i < combo->loose_count && i < 13; i++) {
        int r = _tc_rank(combo->loose_cards[i]);
        if (r >= 0 && r < 13) out[off + r] += 1.0f;
    }
    float loose_max = 0;
    for (int i = 0; i < 13; i++) if (out[off + i] > loose_max) loose_max = out[off + i];
    if (loose_max > 0)
        for (int i = 0; i < 13; i++) out[off + i] /= loose_max;
    off += 13;

    for (int i = 0; i < combo->loose_count && i < 13; i++) {
        int s = _tc_suit(combo->loose_cards[i]);
        if (s >= 0 && s < 4 && combo->loose_count > 0)
            out[off + s] += 1.0f / combo->loose_count;
    }
    off += 4;

    if (combo->loose_count > 0) {
        int max_r = 0;
        for (int i = 0; i < combo->loose_count && i < 13; i++) {
            int r = _tc_rank(combo->loose_cards[i]);
            if (r > max_r) max_r = r;
        }
        out[off++] = max_r / 12.0f;
    } else {
        off++;
    }

    {
        int cnt[13] = {0};
        for (int i = 0; i < combo->loose_count && i < 13; i++) {
            int r = _tc_rank(combo->loose_cards[i]);
            if (r >= 0 && r < 13) cnt[r]++;
        }
        int pairs = 0;
        for (int i = 0; i < 13; i++) if (cnt[i] >= 2) pairs++;
        out[off++] = pairs / 6.0f;
    }

    for (int i = 0; i < 13; i++) {
        int r = _tc_rank(hand13[i]);
        if (r >= 0 && r < 13) out[off + r] += 1.0f / 4.0f;
    }
    off += 13;

    for (int i = 0; i < 13; i++) {
        int s = _tc_suit(hand13[i]);
        if (s >= 0 && s < 4) out[off + s] += 1.0f / 13.0f;
    }
    off += 4;

    {
        int all_ranks[13];
        int all_suits[13];
        int cnt[13] = {0};
        for (int i = 0; i < 13; i++) {
            all_ranks[i] = _tc_rank(hand13[i]);
            all_suits[i] = _tc_suit(hand13[i]);
            if (all_ranks[i] >= 0 && all_ranks[i] < 13) cnt[all_ranks[i]]++;
        }
        int has_trips = 0, has_quads = 0;
        for (int i = 0; i < 13; i++) {
            if (cnt[i] >= 3) has_trips = 1;
            if (cnt[i] >= 4) has_quads = 1;
        }
        out[off++] = has_trips ? 1.0f : 0.0f;
        out[off++] = has_quads ? 1.0f : 0.0f;
        out[off++] = _tc_is_straight(all_ranks, 13) ? 1.0f : 0.0f;
        int suit_seen[4] = {0};
        for (int i = 0; i < 13; i++) if (all_suits[i] >= 0 && all_suits[i] < 4) suit_seen[all_suits[i]] = 1;
        int n_suits = suit_seen[0] + suit_seen[1] + suit_seen[2] + suit_seen[3];
        out[off++] = (n_suits == 1) ? 1.0f : 0.0f;
    }

    out[off] = (out[off - 2] > 0 && out[off - 1] > 0) ? 1.0f : 0.0f;
}

EXPORT int oh_tc_encode_combos(
    const int hand13[13],
    const struct tc_dfs_result* dfs_result,
    float* out_features,
    float* out_mask)
{
    memset(out_features, 0, TC_MAX_COMBOS * TC_COMBO_DIM * sizeof(float));
    memset(out_mask, 0, TC_MAX_COMBOS * sizeof(float));

    int n = dfs_result->combo_count;
    if (n > TC_MAX_COMBOS) n = TC_MAX_COMBOS;

    for (int i = 0; i < n; i++) {
        float* feat = out_features + i * TC_COMBO_DIM;
        _tc_encode_combo(&dfs_result->combos[i], hand13, feat);
        out_mask[i] = 1.0f;
    }
    return n;
}

EXPORT float oh_tc_attack_potential(const struct tc_hand_combo* combo) {
    double score = 0;
    for (int i = 0; i < combo->unit_count && i < 3; i++) {
        double ro = combo->units[i].result.rank_order;
        if (combo->units[i].card_count == 3) score += ro * 2;
        else score += ro;
    }
    float val = (float)(score / 26.0);
    if (val < 0) val = 0;
    if (val > 1) val = 1;
    return val;
}

EXPORT float oh_tc_defense_stability(const struct tc_hand_combo* combo) {
    double typed_norm = combo->typed_score / 30.0;
    double loose_penalty = combo->loose_count / 13.0;
    double unit_bonus = combo->unit_count / 3.0;
    float val = (float)(typed_norm * 0.5 + (1.0 - loose_penalty) * 0.3 + unit_bonus * 0.2);
    if (val < 0) val = 0;
    if (val > 1) val = 1;
    return val;
}

EXPORT int oh_sample(const float* logits, int n, double temperature) {
    if (n <= 0) return -1;
    if (temperature < 0.05) {
        int best = 0;
        for (int i = 1; i < n; i++) if (logits[i] > logits[best]) best = i;
        return best;
    }
    double temp = temperature;
    if (temp < 0.01) temp = 0.01;
    if (temp > 10.0) temp = 10.0;

    double max_l = logits[0];
    for (int i = 1; i < n; i++) if (logits[i] > max_l) max_l = logits[i];

    static unsigned long long rng_state = 123456789;
    rng_state = rng_state * 6364136223846793005ULL + 1;
    unsigned r = (unsigned)(rng_state >> 33);

    double exp_vals[TC_MAX_COMBOS];
    double sum = 0;
    for (int i = 0; i < n && i < TC_MAX_COMBOS; i++) {
        exp_vals[i] = exp((logits[i] - max_l) / temp);
        sum += exp_vals[i];
    }
    double target = (double)r / 4294967296.0 * sum;
    for (int i = 0; i < n && i < TC_MAX_COMBOS; i++) {
        target -= exp_vals[i];
        if (target <= 0) return i;
    }
    return n - 1;
}

EXPORT int oh_tc_recommend(
    const int hand13[13],
    const struct tc_dfs_result* dfs_result,
    void* session,
    double temperature,
    double aggression,
    int* out_best_idx,
    float* out_logits)
{
    if (dfs_result->is_special) { *out_best_idx = 0; return 1; }
    int n_combos = dfs_result->combo_count;
    if (n_combos > TC_MAX_COMBOS) n_combos = TC_MAX_COMBOS;
    if (n_combos <= 0) return -1;

    float hand_tokens[13 * TC_CARD_DIM];
    oh_tc_encode_hand(hand13, hand_tokens);
    float features[TC_MAX_COMBOS * TC_COMBO_DIM];
    float mask[TC_MAX_COMBOS];
    int n_valid = oh_tc_encode_combos(hand13, dfs_result, features, mask);

    const char* input_names[] = {"hand_tokens", "combo_features", "combo_mask"};
    const int64_t hand_shape[] = {1, 13, TC_CARD_DIM};
    const int64_t feat_shape[] = {1, TC_MAX_COMBOS, TC_COMBO_DIM};
    const int64_t mask_shape[] = {1, TC_MAX_COMBOS};
    const float* input_data[] = {hand_tokens, features, mask};
    const int64_t* input_shapes[] = {hand_shape, feat_shape, mask_shape};
    const int input_ndims[] = {3, 3, 2};
    const char* output_names[] = {"logits"};
    float logits_buf[TC_MAX_COMBOS];
    float* output_data[] = {logits_buf};
    const int output_sizes[] = {TC_MAX_COMBOS};

    OrtValue* input_tensors[3];
    OrtMemoryInfo* mem_info = NULL;
    OrtValue* output_tensor = NULL;
    const OrtStatus* s;

    s = api->CreateMemoryInfo("Cpu", 0, 0, 0, &mem_info);
    if (s) { _set_error(s); return -2; }

    for (int i = 0; i < 3; i++) {
        int64_t total = 1;
        for (int d = 0; d < input_ndims[i]; d++) total *= input_shapes[i][d];
        s = api->CreateTensorWithDataAsOrtValue(
            mem_info, (void*)input_data[i], total * sizeof(float),
            input_shapes[i], input_ndims[i], 1, &input_tensors[i]);
        if (s) {
            _set_error(s);
            for (int j = 0; j < i; j++) api->ReleaseValue(input_tensors[j]);
            api->ReleaseMemoryInfo(mem_info);
            return -3;
        }
    }

    s = api->Run((OrtSession*)session, NULL,
                 input_names, (const OrtValue* const*)input_tensors, 3,
                 output_names, 1, &output_tensor);
    if (s) {
        _set_error(s);
        for (int i = 0; i < 3; i++) api->ReleaseValue(input_tensors[i]);
        api->ReleaseMemoryInfo(mem_info);
        return -4;
    }

    void* raw = NULL;
    api->GetTensorMutableData(output_tensor, &raw);
    if (raw) memcpy(logits_buf, raw, TC_MAX_COMBOS * sizeof(float));
    api->ReleaseValue(output_tensor);
    for (int i = 0; i < 3; i++) api->ReleaseValue(input_tensors[i]);
    api->ReleaseMemoryInfo(mem_info);

    if (out_logits) memcpy(out_logits, logits_buf, TC_MAX_COMBOS * sizeof(float));

    float adjusted[TC_MAX_COMBOS];
    memcpy(adjusted, logits_buf, TC_MAX_COMBOS * sizeof(float));
    if (aggression != 0.0) {
        for (int i = 0; i < n_valid; i++) {
            float adj = 0;
            if (aggression > 0)
                adj = (float)aggression * oh_tc_attack_potential(&dfs_result->combos[i]);
            else
                adj = (float)(-aggression) * oh_tc_defense_stability(&dfs_result->combos[i]);
            adjusted[i] += adj;
        }
    }
    *out_best_idx = oh_sample(adjusted, n_valid, temperature);
    return 0;
}

EXPORT int oh_tc_select(
    const struct tc_dfs_result* dfs_result,
    const float* logits,
    double temperature,
    double aggression,
    int* out_best_idx)
{
    int n = dfs_result->combo_count;
    if (n > TC_MAX_COMBOS) n = TC_MAX_COMBOS;
    if (n <= 0 || !logits || !out_best_idx) return -1;
    float adjusted[TC_MAX_COMBOS];
    memcpy(adjusted, logits, n * sizeof(float));
    if (aggression != 0.0) {
        for (int i = 0; i < n; i++) {
            if (aggression > 0)
                adjusted[i] += (float)aggression * oh_tc_attack_potential(&dfs_result->combos[i]);
            else
                adjusted[i] += (float)(-aggression) * oh_tc_defense_stability(&dfs_result->combos[i]);
        }
    }
    *out_best_idx = oh_sample(adjusted, n, temperature);
    return 0;
}
