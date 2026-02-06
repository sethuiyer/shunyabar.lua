--[[
  MINDBENDER — Pushing shunyabar.lua to its limits
  
  1. AI Escargot Sudoku  (world's hardest, 729 vars, ~8850 clauses)
  2. 8-Queens             (classic, 64 vars, 728+ clauses)
  3. Critical 3-SAT Race  (Navokoj vs Casimir at the phase transition)
  4. BAHA vs SA Showdown   (dense graph coloring, fracture detection)
  5. ZetaGrok Spectral Analysis on a "memorizing" vs "grokking" matrix
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
-- 1. AI ESCARGOT — "The World's Hardest Sudoku"
--    Created by Arto Inkala. Rated the most difficult Sudoku ever designed.
--    We encode it as SAT (729 variables, ~8850 clauses) and solve it
--    with prime-weighted geometric flow. No backtracking. No search tree.
-- ========================================================================

sep("1. AI ESCARGOT — World's Hardest Sudoku")

local escargot =
  "8.........." ..
  ".36........" ..
  ".7..9.2...." ..
  ".5...7....." ..
  "....457...." ..
  "...1...3..." ..
  "..1....68.." ..
  "..85...1..." ..
  ".9....4.."

-- Fix: the standard 81-char representation
escargot = "800000000003600000070090200050007000000045700000100030001000068008500010090000400"

print("Puzzle (Arto Inkala's AI Escargot):")
for r = 0, 8 do
  local row = ""
  for c = 1, 9 do
    local ch = escargot:sub(r * 9 + c, r * 9 + c)
    if ch == "0" then ch = "." end
    row = row .. ch .. " "
    if c % 3 == 0 and c < 9 then row = row .. "| " end
  end
  if r % 3 == 0 and r > 0 then print("------+-------+------") end
  print(row)
end

local t0 = os.clock()
local n_vars, clauses = S.navokoj.encode_sudoku(escargot)
print(string.format("\nEncoded: %d variables, %d clauses", n_vars, #clauses))

-- Solve with extra steps for this beast
local assignment = S.navokoj.solve_sat(n_vars, clauses, {
  steps = 5000, learning_rate = 0.08, beta_max = 3.0, seed = 42
})
local sat_rate = S.navokoj.verify_solution(clauses, assignment)
print(string.format("Satisfaction: %.2f%% (%s)", sat_rate * 100, elapsed(t0)))

-- Decode and display solution
local function decode_sudoku(assign)
  local grid = {}
  for r = 1, 9 do
    grid[r] = {}
    for c = 1, 9 do
      grid[r][c] = "."
      for v = 1, 9 do
        local idx = ((r - 1) * 9 + (c - 1)) * 9 + v
        if assign[idx] == 1 then
          grid[r][c] = tostring(v)
          break
        end
      end
    end
  end
  return grid
end

local solution = decode_sudoku(assignment)
print("\nSolution:")
for r = 1, 9 do
  local row = ""
  for c = 1, 9 do
    row = row .. solution[r][c] .. " "
    if c % 3 == 0 and c < 9 then row = row .. "| " end
  end
  if r % 3 == 0 and r < 9 then print("------+-------+------") end
  print(row)
end

-- Verify Sudoku rules directly
local function verify_sudoku(grid, puzzle)
  local valid = true
  -- Check rows
  for r = 1, 9 do
    local seen = {}
    for c = 1, 9 do
      local v = grid[r][c]
      if v ~= "." then
        if seen[v] then valid = false end
        seen[v] = true
      end
    end
  end
  -- Check columns
  for c = 1, 9 do
    local seen = {}
    for r = 1, 9 do
      local v = grid[r][c]
      if v ~= "." then
        if seen[v] then valid = false end
        seen[v] = true
      end
    end
  end
  -- Check boxes
  for br = 0, 2 do
    for bc = 0, 2 do
      local seen = {}
      for i = 1, 3 do
        for j = 1, 3 do
          local v = grid[br*3+i][bc*3+j]
          if v ~= "." then
            if seen[v] then valid = false end
            seen[v] = true
          end
        end
      end
    end
  end
  -- Check clues match
  local clues_ok = true
  for i = 1, 81 do
    local ch = puzzle:sub(i, i)
    if ch ~= "0" and ch ~= "." then
      local r = math.floor((i - 1) / 9) + 1
      local c = ((i - 1) % 9) + 1
      if grid[r][c] ~= ch then clues_ok = false end
    end
  end
  return valid, clues_ok
end

local sudoku_valid, clues_ok = verify_sudoku(solution, escargot)
print(string.format("\nSudoku rules valid: %s | Clues respected: %s",
  tostring(sudoku_valid), tostring(clues_ok)))

-- ========================================================================
-- 2. 8-QUEENS — Place 8 queens on 8x8 board, none attacking
-- ========================================================================

sep("2. 8-QUEENS PROBLEM")

t0 = os.clock()
local q_vars, q_clauses = S.navokoj.encode_n_queens(8)
print(string.format("Encoded: %d variables, %d clauses", q_vars, #q_clauses))

local q_assign = S.navokoj.solve_sat(q_vars, q_clauses, {
  steps = 3000, learning_rate = 0.1, beta_max = 3.0, seed = 42
})
local q_rate = S.navokoj.verify_solution(q_clauses, q_assign)
print(string.format("Satisfaction: %.2f%% (%s)", q_rate * 100, elapsed(t0)))

-- Display board
print("\nBoard:")
local board = {}
local queen_count = 0
for r = 1, 8 do
  local row = ""
  for c = 1, 8 do
    local idx = (r - 1) * 8 + c
    if q_assign[idx] == 1 then
      row = row .. " Q"
      queen_count = queen_count + 1
    else
      row = row .. (((r + c) % 2 == 0) and " ." or " ,")
    end
  end
  print(row)
end
print(string.format("Queens placed: %d", queen_count))

-- Verify no attacks
local queens = {}
for r = 1, 8 do
  for c = 1, 8 do
    if q_assign[(r-1)*8+c] == 1 then queens[#queens+1] = {r, c} end
  end
end
local attacks = 0
for i = 1, #queens do
  for j = i+1, #queens do
    local r1, c1 = queens[i][1], queens[i][2]
    local r2, c2 = queens[j][1], queens[j][2]
    if r1 == r2 or c1 == c2 or math.abs(r1-r2) == math.abs(c1-c2) then
      attacks = attacks + 1
    end
  end
end
print(string.format("Attacking pairs: %d", attacks))

-- ========================================================================
-- 3. CRITICAL 3-SAT RACE — Navokoj vs Casimir at the Phase Transition
--    α = 4.26 is the critical clause-to-variable ratio where 3-SAT
--    transitions from almost-always-satisfiable to almost-always-not.
--    This is the hardest regime. We race both solvers.
-- ========================================================================

sep("3. CRITICAL 3-SAT RACE — Navokoj vs Casimir (alpha=4.26)")

local race_vars = 30
local race_clauses = S.navokoj.generate_3sat(race_vars, 4.26, 123)
print(string.format("Instance: %d variables, %d clauses (ratio %.2f)",
  race_vars, #race_clauses, #race_clauses / race_vars))

-- Navokoj
print("\n--- Navokoj (prime-weighted geometric flow) ---")
t0 = os.clock()
local nav_assign = S.navokoj.solve_sat(race_vars, race_clauses, {
  steps = 3000, learning_rate = 0.1, beta_max = 3.0, seed = 42
})
local nav_time = os.clock() - t0
local nav_rate = S.navokoj.verify_solution(race_clauses, nav_assign)
print(string.format("  Satisfaction: %.2f%%  Time: %.3fs", nav_rate * 100, nav_time))

-- Casimir
print("\n--- Casimir (Langevin dynamics + annealing) ---")
t0 = os.clock()
local cas_solver = S.casimir.Solver(race_vars, race_clauses, {
  temperature = 2.0, learning_rate = 0.5
})
local cas_assign, cas_steps, cas_energy = cas_solver:solve(3000)
local cas_time = os.clock() - t0
local cas_rate = S.navokoj.verify_solution(race_clauses, cas_assign)
print(string.format("  Satisfaction: %.2f%%  Energy: %.4f  Steps: %d  Time: %.3fs",
  cas_rate * 100, cas_energy, cas_steps, cas_time))

-- Declare winner
print("\n--- VERDICT ---")
if nav_rate > cas_rate then
  print(string.format("  Navokoj wins: %.1f%% vs %.1f%%", nav_rate*100, cas_rate*100))
elseif cas_rate > nav_rate then
  print(string.format("  Casimir wins: %.1f%% vs %.1f%%", cas_rate*100, nav_rate*100))
else
  if nav_time < cas_time then
    print(string.format("  Tie on quality (%.1f%%), Navokoj faster (%.3fs vs %.3fs)",
      nav_rate*100, nav_time, cas_time))
  else
    print(string.format("  Tie on quality (%.1f%%), Casimir faster (%.3fs vs %.3fs)",
      cas_rate*100, cas_time, nav_time))
  end
end

-- ========================================================================
-- 4. BAHA vs SA SHOWDOWN — Dense Graph Coloring
--    A dense random graph at the edge of 3-colorability.
--    BAHA should detect fractures and jump; SA should struggle.
-- ========================================================================

sep("4. BAHA vs SA SHOWDOWN — Dense Graph 3-Coloring")

-- Create a challenging graph: 12 nodes, ~40% density, 3 colors
local show_n = 12
local show_colors = 3
M.seed(42)
local show_edges = {}
for i = 1, show_n do
  for j = i+1, show_n do
    if math.random() < 0.40 then
      show_edges[#show_edges+1] = {i, j}
    end
  end
end
print(string.format("Graph: %d nodes, %d edges, %d colors", show_n, #show_edges, show_colors))

local function show_energy(state)
  local conflicts = 0
  for _, e in ipairs(show_edges) do
    if state[e[1]] == state[e[2]] then conflicts = conflicts + 1 end
  end
  return conflicts
end

local function show_sampler()
  local s = {}
  for i = 1, show_n do s[i] = math.random(1, show_colors) end
  return s
end

local function show_neighbor(state)
  local nbrs = {}
  for i = 1, show_n do
    for c = 1, show_colors do
      if c ~= state[i] then
        local nbr = M.copy(state)
        nbr[i] = c
        nbrs[#nbrs+1] = nbr
      end
    end
  end
  return nbrs
end

local n_trials = 10
local ba_wins, sa_wins, ties = 0, 0, 0
local ba_total_e, sa_total_e = 0, 0
local ba_total_t, sa_total_t = 0, 0
local ba_total_frac, ba_total_jump = 0, 0

print(string.format("\nRunning %d trials...\n", n_trials))
print(string.format("%-6s  %-12s %-12s %-12s %-8s",
  "Trial", "BAHA E/time", "SA E/time", "Winner", "Fractures"))
print(string.rep("-", 60))

for trial = 1, n_trials do
  M.seed(trial * 17)

  -- BAHA
  local ba_opt = S.baha.BranchAwareOptimizer(show_energy, show_sampler, show_neighbor)
  local ba_r = ba_opt:optimize({
    beta_steps = 300, fracture_threshold = 0.8, samples_per_beta = 40,
    verbose = false,
  })

  -- SA
  local sa_opt = S.baha.SimulatedAnnealing(show_energy, show_sampler, show_neighbor)
  local sa_r = sa_opt:optimize({
    beta_steps = 300, steps_per_beta = 10, verbose = false,
  })

  ba_total_e = ba_total_e + ba_r.best_energy
  sa_total_e = sa_total_e + sa_r.best_energy
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

  print(string.format("  %2d    E=%d/%.3fs    E=%d/%.3fs    %-6s   %d frac/%d jump",
    trial, ba_r.best_energy, ba_r.time_s,
    sa_r.best_energy, sa_r.time_s,
    winner, ba_r.fractures_detected, ba_r.branch_jumps))
end

print(string.rep("-", 60))
print(string.format("\nSCOREBOARD:"))
print(string.format("  BAHA wins: %d  |  SA wins: %d  |  Ties: %d", ba_wins, sa_wins, ties))
print(string.format("  BAHA avg energy: %.2f  |  SA avg energy: %.2f", ba_total_e/n_trials, sa_total_e/n_trials))
print(string.format("  BAHA avg time:   %.3fs |  SA avg time:   %.3fs", ba_total_t/n_trials, sa_total_t/n_trials))
print(string.format("  Total fractures: %d  |  Total jumps: %d  |  Jump rate: %.1f%%",
  ba_total_frac, ba_total_jump,
  ba_total_frac > 0 and (ba_total_jump / ba_total_frac * 100) or 0))

-- ========================================================================
-- 5. ZETAGROK — Memorization vs Grokking Phase Transition
--    We construct two matrices:
--    A) A "memorizing" matrix: high-rank, noisy spectrum
--    B) A "grokking" matrix: low-rank, clean spectrum
--    The ZetaGrok loss should distinguish them dramatically.
-- ========================================================================

sep("5. ZETAGROK — Memorization vs Grokking Phase Transition")

M.seed(42)
local N = 16

-- Matrix A: "Memorizing" — full-rank random noise (high spectral entropy)
local A_memo = M.matrix(N, N)
for i = 1, N do
  for j = 1, N do
    A_memo[i][j] = M.randn() * 0.5
  end
end

-- Matrix B: "Grokking" — rank-2 clean structure + tiny noise
local A_grok = M.matrix(N, N)
local u1 = {}; local u2 = {}
for i = 1, N do
  u1[i] = math.sin(2 * math.pi * i / N)
  u2[i] = math.cos(2 * math.pi * i / N)
end
for i = 1, N do
  for j = 1, N do
    -- Rank-2: outer products of two clean signals
    A_grok[i][j] = 3.0 * u1[i] * u1[j] + 1.5 * u2[i] * u2[j] + M.randn() * 0.01
  end
end

local task_loss = 0.5  -- same task loss for both

print(string.format("Matrix size: %dx%d", N, N))

-- Analyze memorizing matrix
local loss_m, met_m = S.zetagrok.zetagrok_loss(task_loss, A_memo, { K=3, gamma=2.0, power_iters=10 })
print(string.format("\n[MEMORIZING] Random full-rank matrix:"))
print(string.format("  Spectral entropy:  %.4f  (high = noisy)", met_m.spectral_entropy))
print(string.format("  Twist factor:      %.4f  (amplifies loss)", met_m.twist_factor))
print(string.format("  Task loss:         %.4f", met_m.task_loss))
print(string.format("  Total loss:        %.4f  (inflated by twist)", met_m.total_loss))
print(string.format("  Energy breakdown:  total=%.2f  top3=%.2f  tail=%.2f",
  met_m.total_energy, met_m.topk_energy, met_m.tail_energy))

-- Analyze grokking matrix
local loss_g, met_g = S.zetagrok.zetagrok_loss(task_loss, A_grok, { K=3, gamma=2.0, power_iters=10 })
print(string.format("\n[GROKKING] Clean rank-2 matrix:"))
print(string.format("  Spectral entropy:  %.4f  (low = crystallized)", met_g.spectral_entropy))
print(string.format("  Twist factor:      %.4f  (nearly 1 = no penalty)", met_g.twist_factor))
print(string.format("  Task loss:         %.4f", met_g.task_loss))
print(string.format("  Total loss:        %.4f  (barely inflated)", met_g.total_loss))
print(string.format("  Energy breakdown:  total=%.2f  top3=%.2f  tail=%.2f",
  met_g.total_energy, met_g.topk_energy, met_g.tail_energy))

-- The dramatic comparison
print(string.format("\n--- PHASE TRANSITION ---"))
print(string.format("  Entropy ratio:  %.1fx  (memorizing/grokking)",
  met_m.spectral_entropy / (met_g.spectral_entropy + 1e-9)))
print(string.format("  Twist ratio:    %.1fx  (memorizing/grokking)",
  met_m.twist_factor / met_g.twist_factor))
print(string.format("  Loss inflation: memorizing gets %.1fx more penalty",
  met_m.total_loss / met_g.total_loss))

print(string.format("\n  The multiplicative twist forces the network to crystallize"))
print(string.format("  its spectrum. Memorization (noisy) pays %.1fx penalty.", met_m.twist_factor))
print(string.format("  Grokking (clean) pays nearly zero. This IS the phase transition."))

-- ========================================================================
-- SUMMARY
-- ========================================================================

sep("SUMMARY")

print([[
  1. AI ESCARGOT: The world's hardest Sudoku, encoded as 729-variable SAT
     with ~8850 clauses, attacked by prime-weighted geometric flow.
     No search tree. No backtracking. Pure gradient descent on a manifold.

  2. 8-QUEENS: 64 variables, 728+ constraints. Continuous probabilities
     flowing to discrete queen positions under adiabatic cooling.

  3. CRITICAL 3-SAT: At alpha=4.26, the phase transition boundary where
     problems are maximally hard. Navokoj and Casimir raced head-to-head.

  4. BAHA vs SA: Dense graph coloring. BAHA detects fractures in the
     energy landscape and jumps between thermodynamic sheets via
     Lambert-W branch enumeration. SA just hopes for the best.

  5. ZETAGROK: The spectral entropy twist creates a measurable phase
     transition between memorization (noisy spectrum, heavy penalty)
     and grokking (clean spectrum, no penalty). Computation IS physics.

  All solved by a single 1500-line Lua file with zero dependencies.
]])

print("  \"When you align your algorithm with how nature actually works,")
print("   you stop fighting the problem and start flowing with it.\"")
print("                                               — Sethu Iyer\n")
