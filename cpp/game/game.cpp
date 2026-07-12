#include "game.h"

#include "cards/cards.h"
#include "pattern/pattern.h"

#include <algorithm>
#include <array>
#include <cstring>
#include <new>
#include <random>

namespace {

struct Strength {
    int category = 0;
    int tie[5] = {0, 0, 0, 0, 0};
    int tie_count = 0;
};

struct Action { int type, card, position; };

struct Manager {
    int status[13] = {};
    int pile[3][5];
    int count[3] = {};
    Action actions[1024];
    int action_count = 0;
    Manager() { std::memset(pile, -1, sizeof(pile)); }
};

struct PlayerState {
    int hand[13] = {};
    bool special = false;
    bool submitted = false;
    TcHandResult special_result = {};
    Manager manager;
    int total_score = 0;
    uint32_t achievements = 0;
};

struct Game {
    int player_count;
    int phase = TC_PHASE_IDLE;
    uint64_t seed = 0;
    bool seed_set = false;
    std::mt19937_64 rng;
    PlayerState players[12];
    TcPlayerSettlement results[12] = {};
    TcPairSettlement pairs[66] = {};
    int pair_count = 0;
    explicit Game(int n) : player_count(n), rng(std::random_device{}()) {}
};

static Game* as_game(tc_game_t h) { return reinterpret_cast<Game*>(h); }
static int pile_limit(int p) { return p == 0 ? 3 : 5; }
static bool valid_player(const Game* g, int p) { return g && p >= 0 && p < g->player_count; }

static void copy_result(const HandResult& src, TcHandResult* dst) {
    std::memset(dst, 0, sizeof(*dst));
    dst->position = src.position;
    dst->rank_order = src.rank_order;
    dst->score = src.score;
    if (src.hand_name) {
        std::strncpy(dst->hand_name, src.hand_name, sizeof(dst->hand_name) - 1);
    }
}

static Strength strength_of(const int* cards, int count) {
    Strength s;
    int freq[13] = {};
    for (int i = 0; i < count; ++i) ++freq[card_rank(cards[i])];

    int five = -1, four = -1, three = -1;
    int pairs[2] = {-1, -1}, pair_count = 0;
    int singles[5] = {}, single_count = 0;
    for (int r = 12; r >= 0; --r) {
        if (freq[r] == 5) five = r;
        else if (freq[r] == 4) four = r;
        else if (freq[r] == 3) three = r;
        else if (freq[r] == 2 && pair_count < 2) pairs[pair_count++] = r;
        else if (freq[r] == 1) singles[single_count++] = r;
    }

    if (count == 3) {
        if (three >= 0) { s.category = 4; s.tie[0] = three; s.tie_count = 1; }
        else if (pair_count) { s.category = 2; s.tie[0] = pairs[0]; s.tie[1] = singles[0]; s.tie_count = 2; }
        else { s.category = 1; std::copy(singles, singles + 3, s.tie); s.tie_count = 3; }
        return s;
    }

    bool flush = true;
    int suit = card_suit(cards[0]);
    for (int i = 1; i < 5; ++i) flush = flush && card_suit(cards[i]) == suit;
    int straight_high = -1;
    if (freq[12] && freq[0] && freq[1] && freq[2] && freq[3]) straight_high = 3;
    for (int hi = 12; hi >= 4 && straight_high < 0; --hi)
        if (freq[hi] && freq[hi-1] && freq[hi-2] && freq[hi-3] && freq[hi-4]) straight_high = hi;

    if (five >= 0) { s.category = 10; s.tie[0] = five; s.tie_count = 1; }
    else if (flush && straight_high >= 0) { s.category = 9; s.tie[0] = straight_high; s.tie_count = 1; }
    else if (four >= 0) { s.category = 8; s.tie[0] = four; s.tie[1] = singles[0]; s.tie_count = 2; }
    else if (three >= 0 && pair_count) { s.category = 7; s.tie[0] = three; s.tie[1] = pairs[0]; s.tie_count = 2; }
    else if (flush) { s.category = 6; std::copy(singles, singles + 5, s.tie); s.tie_count = 5; }
    else if (straight_high >= 0) { s.category = 5; s.tie[0] = straight_high; s.tie_count = 1; }
    else if (three >= 0) { s.category = 4; s.tie[0] = three; std::copy(singles, singles + 2, s.tie + 1); s.tie_count = 3; }
    else if (pair_count == 2) { s.category = 3; s.tie[0] = pairs[0]; s.tie[1] = pairs[1]; s.tie[2] = singles[0]; s.tie_count = 3; }
    else if (pair_count == 1) { s.category = 2; s.tie[0] = pairs[0]; std::copy(singles, singles + 3, s.tie + 1); s.tie_count = 4; }
    else { s.category = 1; std::copy(singles, singles + 5, s.tie); s.tie_count = 5; }
    return s;
}

static int compare_strength(const Strength& a, const Strength& b) {
    if (a.category != b.category) return a.category > b.category ? 1 : -1;
    int n = std::max(a.tie_count, b.tie_count);
    for (int i = 0; i < n; ++i) if (a.tie[i] != b.tie[i]) return a.tie[i] > b.tie[i] ? 1 : -1;
    return 0;
}

static int evaluate_arrangement(const int head[3], const int middle[5], const int tail[5], TcArrangement* out) {
    HandResult h = search_pattern(0, head, 3);
    HandResult m = search_pattern(1, middle, 5);
    HandResult t = search_pattern(2, tail, 5);
    copy_result(h, &out->head_result); copy_result(m, &out->middle_result); copy_result(t, &out->tail_result);
    // 倒水检查：只比牌型等级（rank_order），同牌型不计倒水
    if (t.rank_order < m.rank_order || m.rank_order < h.rank_order) return TC_ARR_FOULED;
    return TC_ARR_VALID;
}

static void reset_player_round(PlayerState& p) {
    p.special = false; p.submitted = false; p.special_result = {};
    p.manager = Manager();
}

static uint32_t special_achievement(const TcHandResult& r) {
    if (std::strcmp(r.hand_name, "Royal Straight Flush 13") == 0) return 1u << 0;
    if (std::strcmp(r.hand_name, "Straight 13") == 0) return 1u << 1;
    if (std::strcmp(r.hand_name, "Twelve Royals") == 0) return 1u << 2;
    if (std::strcmp(r.hand_name, "Three Straight Flush") == 0) return 1u << 3;
    if (std::strcmp(r.hand_name, "Three Four of a Kind") == 0) return 1u << 4;
    return 0;
}

static int arrangement_from_manager(const PlayerState& p, TcArrangement* out) {
    if (p.special) { out->is_special = 1; out->special_result = p.special_result; return TC_ARR_SPECIAL; }
    for (int pos = 0; pos < 3; ++pos) if (p.manager.count[pos] != pile_limit(pos)) return TC_ARR_INCOMPLETE;
    std::memset(out, 0, sizeof(*out));
    for (int i = 0; i < 3; ++i) out->head[i] = p.hand[p.manager.pile[0][i]];
    for (int i = 0; i < 5; ++i) out->middle[i] = p.hand[p.manager.pile[1][i]];
    for (int i = 0; i < 5; ++i) out->tail[i] = p.hand[p.manager.pile[2][i]];
    return evaluate_arrangement(out->head, out->middle, out->tail, out);
}

static int arrangement_utility(const TcArrangement& a, int strategy) {
    int base = a.head_result.score + a.middle_result.score + a.tail_result.score;
    int rank = a.head_result.rank_order + a.middle_result.rank_order * 4 + a.tail_result.rank_order * 8;
    if (strategy == 1) return base * 10000 + a.head_result.rank_order * 1000 + rank;
    if (strategy == 2) return base * 10000 + a.tail_result.rank_order * 1000 + rank;
    return base * 10000 + rank;
}

static bool arrangement_uses_hand(const PlayerState& p, const TcArrangement& a) {
    bool used[13] = {};
    const int* piles[3] = {a.head, a.middle, a.tail};
    for (int pos = 0; pos < 3; ++pos) {
        for (int j = 0; j < pile_limit(pos); ++j) {
            int found = -1;
            for (int i = 0; i < 13; ++i) {
                if (!used[i] && p.hand[i] == piles[pos][j]) { found = i; break; }
            }
            if (found < 0) return false;
            used[found] = true;
        }
    }
    return true;
}

static int recommend(const PlayerState& p, int strategy, TcArrangement* out) {
    if (p.special) {
        std::memset(out, 0, sizeof(*out)); out->is_special = 1; out->special_result = p.special_result; return TC_OK;
    }
    bool found = false;
    int best = -2147483647;
    for (int a = 0; a < 11; ++a) for (int b = a + 1; b < 12; ++b) for (int c = b + 1; c < 13; ++c) {
        bool used[13] = {}; used[a] = used[b] = used[c] = true;
        int rem[10], rn = 0; for (int i = 0; i < 13; ++i) if (!used[i]) rem[rn++] = i;
        for (int i0 = 0; i0 < 6; ++i0) for (int i1 = i0+1; i1 < 7; ++i1)
        for (int i2 = i1+1; i2 < 8; ++i2) for (int i3 = i2+1; i3 < 9; ++i3)
        for (int i4 = i3+1; i4 < 10; ++i4) {
            bool mid_used[10] = {}; mid_used[i0]=mid_used[i1]=mid_used[i2]=mid_used[i3]=mid_used[i4]=true;
            TcArrangement cand = {};
            cand.head[0]=p.hand[a]; cand.head[1]=p.hand[b]; cand.head[2]=p.hand[c];
            int mids[5]={i0,i1,i2,i3,i4}; for(int k=0;k<5;++k)cand.middle[k]=p.hand[rem[mids[k]]];
            int tn=0; for(int k=0;k<10;++k)if(!mid_used[k])cand.tail[tn++]=p.hand[rem[k]];
            if (evaluate_arrangement(cand.head, cand.middle, cand.tail, &cand) != TC_ARR_VALID) continue;
            int u = arrangement_utility(cand, strategy);
            if (!found || u > best) { found = true; best = u; cand.utility_score = u; *out = cand; }
        }
    }
    return found ? TC_OK : TC_ERR_FOULED;
}

static void load_arrangement(PlayerState& p, const TcArrangement& a) {
    p.manager = Manager();
    const int* piles[3] = {a.head, a.middle, a.tail};
    for (int pos = 0; pos < 3; ++pos) for (int j = 0; j < pile_limit(pos); ++j) {
        for (int i = 0; i < 13; ++i) if (p.manager.status[i] == 0 && p.hand[i] == piles[pos][j]) {
            p.manager.status[i] = 2; p.manager.pile[pos][p.manager.count[pos]++] = i; break;
        }
    }
}

static int pair_compare(const TcPlayerSettlement& a, const TcPlayerSettlement& b, TcPairSettlement* out) {
    if (a.is_special || b.is_special) {
        int ar = a.is_special ? a.special_result.rank_order : 0;
        int br = b.is_special ? b.special_result.rank_order : 0;
        if (ar == br) return 0;
        out->winner = ar > br ? 1 : -1;
        out->base_score = ar > br ? a.special_result.score : b.special_result.score;
        return 0;
    }
    const int* ac[3] = {a.head,a.middle,a.tail}; const int* bc[3] = {b.head,b.middle,b.tail};
    const TcHandResult* ah[3] = {&a.head_result,&a.middle_result,&a.tail_result};
    const TcHandResult* bh[3] = {&b.head_result,&b.middle_result,&b.tail_result};
    int* cmps[3] = {&out->head_cmp,&out->middle_cmp,&out->tail_cmp};
    int score = 0, wa = 0, wb = 0;
    for(int pos=0;pos<3;++pos){int cmp=compare_strength(strength_of(ac[pos],pile_limit(pos)),strength_of(bc[pos],pile_limit(pos)));*cmps[pos]=cmp;if(cmp>0){score+=ah[pos]->score;++wa;}else if(cmp<0){score-=bh[pos]->score;++wb;}}
    out->shoot_a = wa == 3; out->shoot_b = wb == 3;
    out->winner = score > 0 ? 1 : score < 0 ? -1 : 0; out->base_score = score < 0 ? -score : score;
    return 0;
}

} // namespace

extern "C" {

tc_game_t tc_game_create(int n) { if(n<3||n>12)return nullptr; return reinterpret_cast<tc_game_t>(new(std::nothrow) Game(n)); }
void tc_game_destroy(tc_game_t h) { delete as_game(h); }
int tc_game_set_seed(tc_game_t h,uint64_t seed){Game*g=as_game(h);if(!g)return TC_ERR_NULL;if(g->phase!=TC_PHASE_IDLE&&g->phase!=TC_PHASE_SETTLED)return TC_ERR_PHASE;g->seed=seed;g->seed_set=true;g->rng.seed(seed);return TC_OK;}
int tc_game_get_phase(tc_game_t h){Game*g=as_game(h);return g?g->phase:TC_ERR_NULL;}
int tc_game_get_player_count(tc_game_t h){Game*g=as_game(h);return g?g->player_count:TC_ERR_NULL;}

int tc_game_start_round(tc_game_t h){
    Game*g=as_game(h);if(!g)return TC_ERR_NULL;if(g->phase!=TC_PHASE_IDLE&&g->phase!=TC_PHASE_SETTLED)return TC_ERR_PHASE;
    int decks=g->player_count<=4?1:g->player_count<=8?2:3, size=decks*52; int deck[156];for(int i=0;i<size;++i)deck[i]=i;std::shuffle(deck,deck+size,g->rng);
    g->pair_count=0;std::memset(g->results,0,sizeof(g->results));std::memset(g->pairs,0,sizeof(g->pairs));
    bool all_special=true;
    for(int p=0;p<g->player_count;++p){reset_player_round(g->players[p]);std::copy(deck+p*13,deck+(p+1)*13,g->players[p].hand);HandResult sp=search_pattern(3,g->players[p].hand,13);if(sp.rank_order>0){g->players[p].special=true;g->players[p].submitted=true;copy_result(sp,&g->players[p].special_result);g->players[p].achievements|=special_achievement(g->players[p].special_result);}else all_special=false;}
    g->phase=all_special?TC_PHASE_READY:TC_PHASE_ARRANGING;return TC_OK;
}

int tc_game_get_hand(tc_game_t h,int p,int out[13]){Game*g=as_game(h);if(!g||!out)return TC_ERR_NULL;if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase==TC_PHASE_IDLE)return TC_ERR_PHASE;std::copy(g->players[p].hand,g->players[p].hand+13,out);return TC_OK;}
int tc_game_is_special(tc_game_t h,int p){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;return g->players[p].special?1:0;}
int tc_game_get_special_result(tc_game_t h,int p,TcHandResult*out){Game*g=as_game(h);if(!g||!out)return TC_ERR_NULL;if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(!g->players[p].special)return TC_ERR_SPECIAL_HAND;*out=g->players[p].special_result;return TC_OK;}

int tc_game_select_card(tc_game_t h,int p,int idx){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase!=TC_PHASE_ARRANGING)return TC_ERR_PHASE;PlayerState&x=g->players[p];if(x.submitted)return TC_ERR_PHASE;if(x.special)return TC_ERR_SPECIAL_HAND;if(idx<0||idx>=13)return TC_ERR_CARD_ID;if(x.manager.status[idx]!=0)return TC_ERR_DUPLICATE_CARD;if(x.manager.action_count>=1024)return TC_ERR_ALLOC;x.manager.actions[x.manager.action_count++]={0,idx,-1};x.manager.status[idx]=1;return TC_OK;}
int tc_game_deselect_card(tc_game_t h,int p,int idx){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase!=TC_PHASE_ARRANGING)return TC_ERR_PHASE;PlayerState&x=g->players[p];if(x.submitted)return TC_ERR_PHASE;if(idx<0||idx>=13)return TC_ERR_CARD_ID;if(x.manager.status[idx]!=1)return TC_ERR_CARD_NOT_OWNED;if(x.manager.action_count>=1024)return TC_ERR_ALLOC;x.manager.actions[x.manager.action_count++]={1,idx,-1};x.manager.status[idx]=0;return TC_OK;}
int tc_game_add_to_pile(tc_game_t h,int p,int pos,int idx){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase!=TC_PHASE_ARRANGING)return TC_ERR_PHASE;PlayerState&x=g->players[p];if(x.submitted)return TC_ERR_PHASE;if(pos<0||pos>2||idx<0||idx>=13)return TC_ERR_CARD_ID;if(x.manager.status[idx]!=1)return TC_ERR_CARD_NOT_OWNED;if(x.manager.count[pos]>=pile_limit(pos))return TC_ERR_PILE_FULL;if(x.manager.action_count>=1024)return TC_ERR_ALLOC;x.manager.actions[x.manager.action_count++]={2,idx,pos};x.manager.status[idx]=2;x.manager.pile[pos][x.manager.count[pos]++]=idx;return TC_OK;}
int tc_game_remove_from_pile(tc_game_t h,int p,int pos,int idx){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase!=TC_PHASE_ARRANGING)return TC_ERR_PHASE;PlayerState&x=g->players[p];if(x.submitted)return TC_ERR_PHASE;if(pos<0||pos>2||idx<0||idx>=13)return TC_ERR_CARD_ID;int at=-1;for(int i=0;i<x.manager.count[pos];++i)if(x.manager.pile[pos][i]==idx)at=i;if(at<0)return TC_ERR_CARD_NOT_OWNED;if(x.manager.action_count>=1024)return TC_ERR_ALLOC;x.manager.actions[x.manager.action_count++]={3,idx,pos};for(int i=at+1;i<x.manager.count[pos];++i)x.manager.pile[pos][i-1]=x.manager.pile[pos][i];x.manager.pile[pos][--x.manager.count[pos]]=-1;x.manager.status[idx]=1;return TC_OK;}
int tc_game_undo(tc_game_t h,int p){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase!=TC_PHASE_ARRANGING)return TC_ERR_PHASE;PlayerState&x=g->players[p];if(x.submitted)return TC_ERR_PHASE;if(x.manager.action_count==0)return TC_ERR_INCOMPLETE;Action a=x.manager.actions[--x.manager.action_count];if(a.type==0)x.manager.status[a.card]=0;else if(a.type==1)x.manager.status[a.card]=1;else if(a.type==2){int at=-1;for(int i=0;i<x.manager.count[a.position];++i)if(x.manager.pile[a.position][i]==a.card)at=i;if(at>=0){for(int i=at+1;i<x.manager.count[a.position];++i)x.manager.pile[a.position][i-1]=x.manager.pile[a.position][i];x.manager.pile[a.position][--x.manager.count[a.position]]=-1;}x.manager.status[a.card]=1;}else{x.manager.pile[a.position][x.manager.count[a.position]++]=a.card;x.manager.status[a.card]=2;}return TC_OK;}
int tc_game_get_card_status(tc_game_t h,int p,int idx){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(idx<0||idx>=13)return TC_ERR_CARD_ID;return g->players[p].manager.status[idx];}
int tc_game_get_pile(tc_game_t h,int p,int pos,int*out,int cap){Game*g=as_game(h);if(!g||!out)return TC_ERR_NULL;if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(pos<0||pos>2||cap<g->players[p].manager.count[pos])return TC_ERR_INCOMPLETE;PlayerState&x=g->players[p];for(int i=0;i<x.manager.count[pos];++i)out[i]=x.hand[x.manager.pile[pos][i]];return x.manager.count[pos];}
int tc_game_get_arrangement_status(tc_game_t h,int p){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;TcArrangement a={};return arrangement_from_manager(g->players[p],&a);}
int tc_game_submit_arrangement(tc_game_t h,int p,int allow){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase!=TC_PHASE_ARRANGING)return TC_ERR_PHASE;PlayerState&x=g->players[p];if(x.submitted)return TC_ERR_PHASE;TcArrangement a={};int st=arrangement_from_manager(x,&a);if(st==TC_ARR_INCOMPLETE)return TC_ERR_INCOMPLETE;if(st==TC_ARR_FOULED&&!allow)return TC_ERR_FOULED;x.submitted=true;bool ready=true;for(int i=0;i<g->player_count;++i)ready=ready&&g->players[i].submitted;if(ready)g->phase=TC_PHASE_READY;return TC_OK;}

int tc_game_recommend_arrangement(tc_game_t h,int p,int strategy,TcArrangement*out){Game*g=as_game(h);if(!g||!out)return TC_ERR_NULL;if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase!=TC_PHASE_ARRANGING&&g->phase!=TC_PHASE_READY)return TC_ERR_PHASE;return recommend(g->players[p],strategy,out);}
int tc_game_apply_arrangement(tc_game_t h,int p,const TcArrangement*a){Game*g=as_game(h);if(!g||!a)return TC_ERR_NULL;if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase!=TC_PHASE_ARRANGING)return TC_ERR_PHASE;PlayerState&x=g->players[p];if(x.submitted)return TC_ERR_PHASE;if(x.special)return a->is_special?TC_OK:TC_ERR_SPECIAL_HAND;if(!arrangement_uses_hand(x,*a))return TC_ERR_CARD_NOT_OWNED;TcArrangement checked=*a;int status=evaluate_arrangement(a->head,a->middle,a->tail,&checked);if(status!=TC_ARR_VALID&&status!=TC_ARR_FOULED)return TC_ERR_INCOMPLETE;load_arrangement(x,checked);return TC_OK;}
int tc_game_auto_arrange(tc_game_t h,int p,int strategy){Game*g=as_game(h);if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;PlayerState&x=g->players[p];if(x.special){x.submitted=true;return TC_OK;}TcArrangement a={};int rc=recommend(x,strategy,&a);if(rc)return rc;load_arrangement(x,a);return tc_game_submit_arrangement(h,p,0);}

int tc_game_settle(tc_game_t h){
    Game*g=as_game(h);if(!g)return TC_ERR_NULL;if(g->phase==TC_PHASE_SETTLED)return TC_ERR_ALREADY_SETTLED;if(g->phase!=TC_PHASE_READY)return TC_ERR_PHASE;
    bool foul[12]={};int net[12]={},shoot[12]={},shot[12]={};
    for(int p=0;p<g->player_count;++p){PlayerState&x=g->players[p];TcPlayerSettlement&r=g->results[p];std::memset(&r,0,sizeof(r));r.player_index=p;std::copy(x.hand,x.hand+13,r.hand);r.is_special=x.special;if(x.special){r.special_result=x.special_result;std::copy(x.hand,x.hand+3,r.head);std::copy(x.hand+3,x.hand+8,r.middle);std::copy(x.hand+8,x.hand+13,r.tail);}else{TcArrangement a={};int st=arrangement_from_manager(x,&a);foul[p]=st==TC_ARR_FOULED;r.fouled=foul[p];std::copy(a.head,a.head+3,r.head);std::copy(a.middle,a.middle+5,r.middle);std::copy(a.tail,a.tail+5,r.tail);r.head_result=a.head_result;r.middle_result=a.middle_result;r.tail_result=a.tail_result;if(std::strcmp(r.middle_result.hand_name,"Five of a Kind")==0)x.achievements|=1u<<5;if(std::strcmp(r.tail_result.hand_name,"Five of a Kind")==0)x.achievements|=1u<<6;}}
    g->pair_count=0;
    for(int i=0;i<g->player_count;++i)for(int j=i+1;j<g->player_count;++j){TcPairSettlement&pr=g->pairs[g->pair_count++];std::memset(&pr,0,sizeof(pr));pr.player_a=i;pr.player_b=j;if(foul[i]||foul[j])continue;pair_compare(g->results[i],g->results[j],&pr);if(pr.shoot_a){++shoot[i];++shot[j];}if(pr.shoot_b){++shoot[j];++shot[i];}}
    bool homerun[12]={};for(int i=0;i<g->player_count;++i){if(foul[i])continue;int opp=0;for(int j=0;j<g->player_count;++j)if(i!=j&&!foul[j])++opp;homerun[i]=opp>0&&shoot[i]==opp;}
    for(int k=0;k<g->pair_count;++k){TcPairSettlement&pr=g->pairs[k];if(pr.winner==0||pr.base_score==0)continue;int w=pr.winner>0?pr.player_a:pr.player_b;int mult=homerun[w]?3:((pr.winner>0&&pr.shoot_a)||(pr.winner<0&&pr.shoot_b)?2:1);pr.multiplier=mult;pr.final_score=pr.base_score*mult;if(pr.winner>0){net[pr.player_a]+=pr.final_score;net[pr.player_b]-=pr.final_score;}else{net[pr.player_a]-=pr.final_score;net[pr.player_b]+=pr.final_score;}}
    int foul_count=0,total_bill=0;for(int i=0;i<g->player_count;++i)if(foul[i])++foul_count;
    if(foul_count){for(int i=0;i<g->player_count;++i)if(!foul[i]&&net[i]<0){total_bill-=net[i];net[i]=0;}int each=total_bill/foul_count,rem=total_bill%foul_count;for(int i=0;i<g->player_count;++i)if(foul[i])net[i]-=each+(rem-->0?1:0);}
    for(int i=0;i<g->player_count;++i){PlayerState&x=g->players[i];TcPlayerSettlement&r=g->results[i];x.total_score+=net[i];r.round_net_score=net[i];r.total_score=x.total_score;r.fouled=foul[i];r.homerun=homerun[i];r.shoot_count=shoot[i];r.shot_count=shot[i];r.achievements=x.achievements;}
    g->phase=TC_PHASE_SETTLED;return TC_OK;
}
int tc_game_get_player_settlement(tc_game_t h,int p,TcPlayerSettlement*out){Game*g=as_game(h);if(!g||!out)return TC_ERR_NULL;if(!valid_player(g,p))return TC_ERR_PLAYER_INDEX;if(g->phase!=TC_PHASE_SETTLED)return TC_ERR_PHASE;*out=g->results[p];return TC_OK;}
int tc_game_get_pair_count(tc_game_t h){Game*g=as_game(h);if(!g)return TC_ERR_NULL;if(g->phase!=TC_PHASE_SETTLED)return TC_ERR_PHASE;return g->pair_count;}
int tc_game_get_pair_settlement(tc_game_t h,int idx,TcPairSettlement*out){Game*g=as_game(h);if(!g||!out)return TC_ERR_NULL;if(g->phase!=TC_PHASE_SETTLED)return TC_ERR_PHASE;if(idx<0||idx>=g->pair_count)return TC_ERR_PLAYER_INDEX;*out=g->pairs[idx];return TC_OK;}
const char* tc_error_message(int c){switch(c){case TC_OK:return "ok";case TC_ERR_NULL:return "null";case TC_ERR_PHASE:return "invalid phase";case TC_ERR_PLAYER_COUNT:return "invalid player count";case TC_ERR_PLAYER_INDEX:return "invalid player index";case TC_ERR_CARD_ID:return "invalid card";case TC_ERR_CARD_NOT_OWNED:return "card unavailable";case TC_ERR_DUPLICATE_CARD:return "duplicate card";case TC_ERR_PILE_FULL:return "pile full";case TC_ERR_INCOMPLETE:return "incomplete";case TC_ERR_FOULED:return "fouled";case TC_ERR_SPECIAL_HAND:return "special hand";case TC_ERR_ALREADY_SETTLED:return "already settled";default:return "unknown";}}

} // extern C
