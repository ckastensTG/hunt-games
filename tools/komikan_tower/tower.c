// Komikan: can the dogs ever trap a puma that stays in the tower?
//
// Build and run (any C compiler):
//   cc -O2 -o /tmp/tower tools/komikan_tower/tower.c && /tmp/tower [--sideways] [--simulate=N]
//
// The check is an abstract game that is deliberately generous to the dogs:
//  - only the tower (13 points) and its apex are modelled, because the apex is
//    the tower's only way in;
//  - the dogs may pass whenever they like (in the real game that is a move
//    elsewhere on the board, and dogs that can't move lose);
//  - any dog not yet in the tower may appear on the empty apex in one move.
// The puma only steps inside the tower and only makes captures that land in
// it. Inside those limits both sides play perfectly (a least-fixpoint
// "attractor" over every position: about 700,000 for each side to move).
//
// If the dogs can't force a trap here, a real puma that stays in the tower is
// never trapped, so the real dogs (forward only, so finitely many moves) run
// out of moves and lose: the puma wins with correct play. --sideways lets the
// dogs also step sideways (never back) to compare.
//
// --simulate=N plays N games under the real rules on the whole board: the
// puma follows the tower strategy, the dogs play random or tower-rushing
// forward moves. It checks the abstraction against the real move generator.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "board.h"

typedef unsigned long long u64;
#define B(i) (1ULL << (i))
#define NL 14  // the apex (22) and the 13 tower points

static const int G[NL] = {22, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37};
static int L[NP];  // board point -> local index, or -1
static int sideways = 0;
// [dogs in the modelled points][puma][dogs not in the tower]: 1 = the dogs can force a trap
static unsigned char Wp[1 << NL][NL][13];  // puma to move
static unsigned char Wd[1 << NL][NL][13];  // dogs to move

static int forward(int from, int to) {
    return RANK[to] > RANK[from] || (sideways && RANK[to] == RANK[from]);
}

// Capture chains from `at` inside the tower. Captured dogs stay on the board
// until the chain ends and can't be jumped twice; the puma's start is empty.
static int chains(int mask, int at, int taken, int origin, int out_taken[], int out_at[], int n) {
    int g = G[at];
    for (int k = 0; k < NJ[g]; k++) {
        int o = L[OVER[g][k]], l = L[LAND[g][k]];
        if (o < 0 || l <= 0) continue;  // landing must be inside the tower
        if (!(mask >> o & 1) || (taken >> o & 1)) continue;
        if ((mask >> l & 1) && l != origin) continue;
        int nt = taken | (1 << o), dup = 0;
        for (int i = 0; i < n; i++)
            if (out_taken[i] == nt && out_at[i] == l) dup = 1;
        if (dup) continue;
        out_taken[n] = nt;
        out_at[n] = l;
        n++;
        n = chains(mask, l, nt, origin, out_taken, out_at, n);
    }
    return n;
}

static void solve(void) {
    memset(Wp, 0, sizeof Wp);
    memset(Wd, 0, sizeof Wd);
    int changed = 1;
    while (changed) {
        changed = 0;
        for (int m = 0; m < (1 << NL); m++) {
            int nd = __builtin_popcount(m);
            for (int p = 1; p < NL; p++) {
                if (m >> p & 1) continue;
                for (int r = 0; r + nd <= 12; r++) {
                    if (!Wp[m][p][r]) {  // trapped, or every tower move loses
                        int all = 1, g = G[p];
                        for (int k = 0; k < NADJ[g] && all; k++) {
                            int j = L[ADJ[g][k]];
                            if (j > 0 && !(m >> j & 1) && !Wd[m][j][r]) all = 0;
                        }
                        int ot[256], oa[256], n = all ? chains(m, p, 0, p, ot, oa, 0) : 0;
                        for (int i = 0; i < n && all; i++)
                            if (!Wd[m & ~ot[i]][oa[i]][r]) all = 0;
                        if (all) { Wp[m][p][r] = 1; changed = 1; }
                    }
                    if (!Wd[m][p][r]) {  // pass, bring a dog to the apex, or step
                        int win = Wp[m][p][r];
                        if (!win && r > 0 && !(m & 1)) win = Wp[m | 1][p][r - 1];
                        for (int i = 0; i < NL && !win; i++) {
                            if (!(m >> i & 1)) continue;
                            for (int k = 0; k < NADJ[G[i]] && !win; k++) {
                                int j = L[ADJ[G[i]][k]];
                                if (j < 0 || j == p || (m >> j & 1) || !forward(G[i], G[j])) continue;
                                if (Wp[(m & ~(1 << i)) | (1 << j)][p][r]) win = 1;
                            }
                        }
                        if (win) { Wd[m][p][r] = 1; changed = 1; }
                    }
                }
            }
        }
    }
}

static u64 rng = 88172645463325252ULL;
static u64 next_rand(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }

static void simulate(int games) {
    int trapped = 0, stuck = 0, eaten = 0, maxply = 0;
    long total = 0;
    for (int game = 0; game < games; game++) {
        u64 dogs = 0;
        for (int i = 0; i < 12; i++) dogs |= B(PREY[i]);
        int p = HSTART, ply = 0, puma_turn = !(game & 1), rush = (game % 4) >= 2;
        for (;;) {
            if (!dogs) { eaten++; break; }
            if (puma_turn) {
                int m = 0;
                for (int i = 0; i < NL; i++) if (dogs & B(G[i])) m |= 1 << i;
                int r = __builtin_popcountll(dogs) - __builtin_popcount(m), lp = L[p], g = G[lp];
                int pick_at = -1, pick_taken = 0, options = 0;
                for (int k = 0; k < NADJ[g]; k++) {
                    int j = L[ADJ[g][k]];
                    if (j > 0 && !(m >> j & 1) && !Wd[m][j][r] && next_rand() % ++options == 0) { pick_at = j; pick_taken = 0; }
                }
                int ot[256], oa[256], n = chains(m, lp, 0, lp, ot, oa, 0);
                for (int i = 0; i < n; i++)
                    if (!Wd[m & ~ot[i]][oa[i]][r] && next_rand() % ++options == 0) { pick_at = oa[i]; pick_taken = ot[i]; }
                if (pick_at < 0) { trapped++; break; }
                for (int i = 0; i < NL; i++) if (pick_taken >> i & 1) dogs &= ~B(G[i]);
                p = G[pick_at];
            } else {
                int from[256], to[256], n = 0;
                for (int i = 0; i < NP; i++) {
                    if (!(dogs & B(i))) continue;
                    for (int k = 0; k < NADJ[i]; k++) {
                        int j = ADJ[i][k];
                        if (j != p && !(dogs & B(j)) && RANK[j] > RANK[i]) { from[n] = i; to[n] = j; n++; }
                    }
                }
                if (!n) { stuck++; break; }
                int pick = next_rand() % n;
                if (rush) {
                    double best = -1;
                    for (int i = 0; i < n; i++) {
                        double score = RANK[to[i]] * 10 + next_rand() % 7;
                        if (score > best) { best = score; pick = i; }
                    }
                }
                dogs = (dogs & ~B(from[pick])) | B(to[pick]);
            }
            puma_turn = !puma_turn;
            ply++;
        }
        total += ply;
        if (ply > maxply) maxply = ply;
    }
    printf("%d games under the real rules, puma in the tower: trapped %d, dogs stuck %d, all dogs eaten %d (avg %.1f plies, max %d)\n",
           games, trapped, stuck, eaten, (double)total / games, maxply);
}

int main(int argc, char **argv) {
    int games = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--sideways")) sideways = 1;
        else if (!strncmp(argv[i], "--simulate=", 11)) games = atoi(argv[i] + 11);
    }
    memset(L, -1, sizeof L);
    for (int i = 0; i < NL; i++) L[G[i]] = i;
    solve();
    int start = L[HSTART];
    printf("Dogs %s.\n", sideways ? "step forward or sideways, never back" : "step forward only (Mátus 1918-19, the rules until 2026-11-03)");
    printf("Puma moves first: %s\n", Wp[0][start][12] ? "the dogs can force a trap in the tower" : "the dogs can't trap a puma that stays in the tower");
    printf("Dogs move first:  %s\n", Wd[0][start][12] ? "the dogs can force a trap in the tower" : "the dogs can't trap a puma that stays in the tower");
    for (int r = 1; r <= 12; r++)
        if (Wp[0][start][r]) { printf("(%d dogs are enough to force a trap.)\n", r); break; }
    if (games > 0) {
        if (sideways) printf("--simulate uses forward-only dogs; run it without --sideways.\n");
        else simulate(games);
    }
    return 0;
}
