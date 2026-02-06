--[[
  TSP_BAHA — Solving the Travelling Salesman Problem
                with Branch-Aware Holonomy Annealing

  Benchmark: bayg29 — 29 cities in Bavaria (TSPLIB, Groetschel/Juenger/Reinelt)
  Known optimal tour length: 1610

  BAHA detects phase transitions in the TSP energy landscape and jumps
  between thermodynamic sheets via Lambert-W branch enumeration.
  Compared head-to-head against standard Simulated Annealing.
]]

package.path = package.path .. ";./?.lua"
local S = dofile("shunyabar.lua")
local M = S.math

M.seed(42)

local function sep(title)
  print("\n" .. string.rep("=", 70))
  print("  " .. title)
  print(string.rep("=", 70))
end

local function elapsed(t0)
  return string.format("%.3fs", os.clock() - t0)
end

-- ========================================================================
-- BAYG29 DISTANCE MATRIX
-- 29 Cities in Bavaria, geographical distances
-- Source: TSPLIB (Groetschel, Juenger, Reinelt)
-- Format: UPPER_ROW — upper triangle without diagonal
-- Optimal tour length: 1610
-- ========================================================================

local N = 29
local OPTIMAL = 1610

-- Upper triangle (row-major order): dist(i,j) for i < j
local upper = {
  -- 1→{2..29}
  97,205,139,86,60,220,65,111,115,227,95,82,225,168,103,266,205,149,120,58,257,152,52,180,136,82,34,145,
  -- 2→{3..29}
  129,103,71,105,258,154,112,65,204,150,87,176,137,142,204,148,148,49,41,211,226,116,197,89,153,124,74,
  -- 3→{4..29}
  219,125,175,386,269,134,184,313,201,215,267,248,271,274,236,272,160,151,300,350,239,322,78,276,220,60,
  -- 4→{5..29}
  167,182,180,162,208,39,102,227,60,86,34,96,129,69,58,60,120,119,192,114,110,192,136,173,173,
  -- 5→{6..29}
  51,296,150,42,131,268,88,131,245,201,175,275,218,202,119,50,281,238,131,244,51,166,95,69,
  -- 6→{7..29}
  279,114,56,150,278,46,133,266,214,162,302,242,203,146,67,300,205,111,238,98,139,52,120,
  -- 7→{8..29}
  178,328,206,147,308,172,203,165,121,251,216,122,231,249,209,111,169,72,338,144,237,331,
  -- 8→{9..29}
  169,151,227,133,104,242,182,84,290,230,146,165,121,270,91,48,158,200,39,64,210,
  -- 9→{10..29}
  172,309,68,169,286,242,208,315,259,240,160,90,322,260,160,281,57,192,107,90,
  -- 10→{11..29}
  140,195,51,117,72,104,153,93,88,25,85,152,200,104,139,154,134,149,135,
  -- 11→{12..29}
  320,146,64,68,143,106,88,81,159,219,63,216,187,88,293,191,258,272,
  -- 12→{13..29}
  174,311,258,196,347,288,243,192,113,345,222,144,274,124,165,71,153,
  -- 13→{14..29}
  144,86,57,189,128,71,71,82,176,150,56,114,168,83,115,160,
  -- 14→{15..29}
  61,165,51,32,105,127,201,36,254,196,136,260,212,258,234,
  -- 15→{16..29}
  106,110,56,49,91,153,91,197,136,94,225,151,201,205,
  -- 16→{17..29}
  215,159,64,126,128,190,98,53,78,218,48,127,214,
  -- 17→{18..29}
  61,155,157,235,47,305,243,186,282,261,300,252,
  -- 18→{19..29}
  105,100,176,66,253,183,146,231,203,239,204,
  -- 19→{20..29}
  113,152,127,150,106,52,235,112,179,221,
  -- 20→{21..29}
  79,163,220,119,164,135,152,153,114,
  -- 21→{22..29}
  236,201,90,195,90,127,84,91,
  -- 22→{23..29}
  273,226,148,296,238,291,269,
  -- 23→{24..29}
  112,130,286,74,155,291,
  -- 24→{25..29}
  130,178,38,75,180,
  -- 25→{26..29}
  281,120,205,270,
  -- 26→{27..29}
  213,145,36,
  -- 27→{28..29}
  94,217,
  -- 28→{29}
  162,
}

-- Build full symmetric distance matrix
local dist = {}
for i = 1, N do
  dist[i] = {}
  for j = 1, N do dist[i][j] = 0 end
end

local idx = 1
for i = 1, N - 1 do
  for j = i + 1, N do
    dist[i][j] = upper[idx]
    dist[j][i] = upper[idx]
    idx = idx + 1
  end
end

-- Sanity check: should consume all values
assert(idx - 1 == #upper,
  string.format("Matrix parse error: consumed %d, expected %d", idx - 1, #upper))

-- ========================================================================
-- TSP FUNCTIONS
-- ========================================================================

--- Energy: total tour distance (circular route)
local function tsp_energy(tour)
  local d = 0
  for i = 1, #tour - 1 do
    d = d + dist[tour[i]][tour[i + 1]]
  end
  d = d + dist[tour[#tour]][tour[1]]  -- return to start
  return d
end

--- Sampler: random permutation via Fisher-Yates shuffle
local function tsp_sampler()
  local t = {}
  for i = 1, N do t[i] = i end
  for i = N, 2, -1 do
    local j = math.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

--- Neighbor: all 2-opt moves (reverse a sub-segment of the tour)
--- For N=29, this generates ~378 neighbors per call.
local function tsp_neighbor(tour)
  local nbrs = {}
  for i = 1, N - 2 do
    for j = i + 2, N do
      -- Copy tour and reverse segment [i..j]
      local nbr = {}
      for k = 1, N do nbr[k] = tour[k] end
      local lo, hi = i, j
      while lo < hi do
        nbr[lo], nbr[hi] = nbr[hi], nbr[lo]
        lo = lo + 1
        hi = hi - 1
      end
      nbrs[#nbrs + 1] = nbr
    end
  end
  return nbrs
end

--- Pretty-print a tour
local function tour_str(tour, max_show)
  max_show = max_show or N
  local parts = {}
  for i = 1, math.min(#tour, max_show) do
    parts[#parts + 1] = tostring(tour[i])
  end
  local s = table.concat(parts, " → ")
  if max_show < #tour then s = s .. " → ..." end
  s = s .. " → " .. tostring(tour[1])
  return s
end

-- ========================================================================
-- 1. BAHA — Branch-Aware Holonomy Annealing on TSP
-- ========================================================================

sep("1. BAHA on bayg29 TSP (29 cities, optimal=" .. OPTIMAL .. ")")

print(string.format("Cities: %d  |  2-opt neighbors per step: %d  |  Optimal: %d",
  N, (N - 2) * (N - 1) / 2, OPTIMAL))

local t0 = os.clock()
local ba_opt = S.baha.BranchAwareOptimizer(tsp_energy, tsp_sampler, tsp_neighbor)
local ba_result = ba_opt:optimize({
  beta_start         = 0.001,
  beta_end           = 15.0,
  beta_steps         = 1000,
  fracture_threshold = 1.5,
  beta_critical      = 1.0,
  max_branches       = 5,
  samples_per_beta   = 50,
  verbose            = true,
})
local ba_time = os.clock() - t0

print(string.format("\n  Best distance:  %d", ba_result.best_energy))
print(string.format("  Optimal:        %d", OPTIMAL))
print(string.format("  Gap:            %.2f%%",
  (ba_result.best_energy - OPTIMAL) / OPTIMAL * 100))
print(string.format("  Fractures:      %d", ba_result.fractures_detected))
print(string.format("  Branch jumps:   %d", ba_result.branch_jumps))
print(string.format("  Jump rate:      %.1f%%",
  ba_result.fractures_detected > 0
    and (ba_result.branch_jumps / ba_result.fractures_detected * 100) or 0))
print(string.format("  Time:           %s", elapsed(t0)))
print(string.format("\n  Tour: %s", tour_str(ba_result.best_state)))

-- ========================================================================
-- 2. Standard Simulated Annealing — Baseline Comparison
-- ========================================================================

sep("2. Standard SA on bayg29 TSP (same budget)")

t0 = os.clock()
local sa_opt = S.baha.SimulatedAnnealing(tsp_energy, tsp_sampler, tsp_neighbor)
local sa_result = sa_opt:optimize({
  beta_start     = 0.001,
  beta_end       = 15.0,
  beta_steps     = 1000,
  steps_per_beta = 10,
  verbose        = false,
})
local sa_time = os.clock() - t0

print(string.format("  Best distance:  %d", sa_result.best_energy))
print(string.format("  Optimal:        %d", OPTIMAL))
print(string.format("  Gap:            %.2f%%",
  (sa_result.best_energy - OPTIMAL) / OPTIMAL * 100))
print(string.format("  Time:           %s", elapsed(t0)))
print(string.format("\n  Tour: %s", tour_str(sa_result.best_state)))

-- ========================================================================
-- 3. Multi-Trial Race — BAHA vs SA (statistical comparison)
-- ========================================================================

sep("3. BAHA vs SA — 10-Trial Race")

local n_trials = 10
local ba_wins, sa_wins, ties = 0, 0, 0
local ba_total_d, sa_total_d = 0, 0
local ba_best_d, sa_best_d = math.huge, math.huge
local ba_total_t, sa_total_t = 0, 0
local ba_total_frac, ba_total_jump = 0, 0

print(string.format("\n%-6s  %-16s %-16s %-8s %-14s",
  "Trial", "BAHA dist/time", "SA dist/time", "Winner", "Fractures"))
print(string.rep("-", 68))

for trial = 1, n_trials do
  M.seed(trial * 31)

  -- BAHA
  local ba = S.baha.BranchAwareOptimizer(tsp_energy, tsp_sampler, tsp_neighbor)
  local ba_r = ba:optimize({
    beta_start = 0.001, beta_end = 15.0,
    beta_steps = 800, fracture_threshold = 1.5,
    samples_per_beta = 40, verbose = false,
  })

  -- SA (with comparable compute budget)
  local sa = S.baha.SimulatedAnnealing(tsp_energy, tsp_sampler, tsp_neighbor)
  local sa_r = sa:optimize({
    beta_start = 0.001, beta_end = 15.0,
    beta_steps = 800, steps_per_beta = 10, verbose = false,
  })

  ba_total_d = ba_total_d + ba_r.best_energy
  sa_total_d = sa_total_d + sa_r.best_energy
  if ba_r.best_energy < ba_best_d then ba_best_d = ba_r.best_energy end
  if sa_r.best_energy < sa_best_d then sa_best_d = sa_r.best_energy end
  ba_total_t = ba_total_t + ba_r.time_s
  sa_total_t = sa_total_t + sa_r.time_s
  ba_total_frac = ba_total_frac + ba_r.fractures_detected
  ba_total_jump = ba_total_jump + ba_r.branch_jumps

  local winner
  if ba_r.best_energy < sa_r.best_energy then
    winner = "BAHA"
    ba_wins = ba_wins + 1
  elseif sa_r.best_energy < ba_r.best_energy then
    winner = "SA"
    sa_wins = sa_wins + 1
  else
    winner = "TIE"
    ties = ties + 1
  end

  print(string.format("  %2d    %5d / %.2fs    %5d / %.2fs    %-6s   %d frac / %d jump",
    trial, ba_r.best_energy, ba_r.time_s,
    sa_r.best_energy, sa_r.time_s,
    winner, ba_r.fractures_detected, ba_r.branch_jumps))
end

print(string.rep("-", 68))

-- ========================================================================
-- SUMMARY
-- ========================================================================

sep("RESULTS SUMMARY — bayg29 TSP")

print(string.format([[
  Known optimal:       %d

  BAHA
    Avg distance:      %.1f  (gap: %.2f%%)
    Best distance:     %d    (gap: %.2f%%)
    Avg time:          %.3fs
    Total fractures:   %d
    Total jumps:       %d
    Jump rate:         %.1f%%

  Standard SA
    Avg distance:      %.1f  (gap: %.2f%%)
    Best distance:     %d    (gap: %.2f%%)
    Avg time:          %.3fs

  Head-to-head:
    BAHA wins:  %d  |  SA wins:  %d  |  Ties:  %d
    Avg improvement:   %.1f  (%.2f%% closer to optimal)
]],
  OPTIMAL,
  ba_total_d / n_trials,
  (ba_total_d / n_trials - OPTIMAL) / OPTIMAL * 100,
  ba_best_d,
  (ba_best_d - OPTIMAL) / OPTIMAL * 100,
  ba_total_t / n_trials,
  ba_total_frac, ba_total_jump,
  ba_total_frac > 0 and (ba_total_jump / ba_total_frac * 100) or 0,
  sa_total_d / n_trials,
  (sa_total_d / n_trials - OPTIMAL) / OPTIMAL * 100,
  sa_best_d,
  (sa_best_d - OPTIMAL) / OPTIMAL * 100,
  sa_total_t / n_trials,
  ba_wins, sa_wins, ties,
  sa_total_d / n_trials - ba_total_d / n_trials,
  (sa_total_d / n_trials - ba_total_d / n_trials) / (sa_total_d / n_trials) * 100
))

print("  \"The energy landscape of TSP shatters as temperature drops.")
print("   BAHA detects the fractures and navigates between sheets.")
print("   SA stumbles blindly through the shards.\"")
print("                                               — Sethu Iyer\n")
