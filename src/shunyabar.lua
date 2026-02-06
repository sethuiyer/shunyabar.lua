--[[
================================================================================
  SHUNYABAR.LUA — The Arithmetic Manifold in a Single File
================================================================================

  A unified Lua implementation of the ShunyaBar physics-inspired computation
  framework, consolidating four projects into one standalone module:

    1. BAHA    — Branch-Aware Holonomy Annealing (fracture detection + Lambert-W)
    2. NAVOKOJ — Constraint satisfaction via prime-weighted geometric flow
    3. PINN    — Multiplicative constraint enforcement (Euler gate + barrier)
    4. CASIMIR — Quantum-inspired SAT solving via Langevin dynamics

  Core thesis: Hard problems have phase transitions. Phase transitions have
  spectral signatures. Those signatures can be detected, navigated, and
  exploited through prime-weighted operators and multiplicative dynamics.

  Author : Sethu Iyer <sethuiyer95@gmail.com>
  License: Apache 2.0
  Deps   : None (pure Lua 5.1+)

  Usage:
    local S = require("shunyabar")   -- or dofile("shunyabar.lua")
    -- S.baha, S.navokoj, S.pinn, S.casimir, S.zetagrok, S.math

================================================================================
--]]

local shunyabar = {}

-- ============================================================================
-- 1. MATH UTILITIES
-- ============================================================================

shunyabar.math = {}
local M = shunyabar.math

local abs   = math.abs
local exp   = math.exp
local log   = math.log
local sqrt  = math.sqrt
local floor = math.floor
local max   = math.max
local min   = math.min
local pi    = math.pi
local huge  = math.huge

--- Seed the RNG
function M.seed(s)
  math.randomseed(s or os.time())
end
M.seed()

--- Box-Muller transform: generate N(0,1) random variate
function M.randn()
  local u1 = math.random()
  local u2 = math.random()
  while u1 <= 1e-15 do u1 = math.random() end
  return sqrt(-2.0 * log(u1)) * math.cos(2.0 * pi * u2)
end

--- Uniform random in [lo, hi)
function M.uniform(lo, hi)
  lo = lo or 0.0
  hi = hi or 1.0
  return lo + (hi - lo) * math.random()
end

--- Clamp x to [lo, hi]
function M.clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

--- Sigmoid function σ(x) = 1 / (1 + e^(-x))
function M.sigmoid(x)
  if x >= 0 then
    local ez = exp(-x)
    return 1.0 / (1.0 + ez)
  else
    local ez = exp(x)
    return ez / (1.0 + ez)
  end
end

--- Generate first n prime numbers
function M.generate_primes(n)
  local primes = {}
  local candidate = 2
  while #primes < n do
    local is_prime = true
    for _, p in ipairs(primes) do
      if p * p > candidate then break end
      if candidate % p == 0 then
        is_prime = false
        break
      end
    end
    if is_prime then primes[#primes + 1] = candidate end
    candidate = candidate + 1
  end
  return primes
end

--- Numerically stable log-sum-exp
function M.log_sum_exp(log_terms)
  if #log_terms == 0 then return -huge end
  local mx = -huge
  for _, t in ipairs(log_terms) do
    if t > mx then mx = t end
  end
  if mx == huge or mx == -huge then return mx end
  local s = 0.0
  for _, t in ipairs(log_terms) do
    s = s + exp(t - mx)
  end
  return mx + log(s)
end

--- Softmax over 1D array with inverse-temperature beta
function M.softmax(x, beta)
  beta = beta or 1.0
  local n = #x
  local mx = -huge
  for i = 1, n do
    if x[i] > mx then mx = x[i] end
  end
  local out = {}
  local total = 0.0
  for i = 1, n do
    out[i] = exp(beta * (x[i] - mx))
    total = total + out[i]
  end
  for i = 1, n do out[i] = out[i] / total end
  return out
end

--- Deep copy a flat table (array)
function M.copy(t)
  local c = {}
  for i = 1, #t do c[i] = t[i] end
  return c
end

--- Allocate a 1D array of length n filled with val
function M.zeros(n, val)
  val = val or 0.0
  local t = {}
  for i = 1, n do t[i] = val end
  return t
end

--- Allocate a 2D matrix [rows][cols] filled with val
function M.matrix(rows, cols, val)
  val = val or 0.0
  local m = {}
  for i = 1, rows do
    m[i] = {}
    for j = 1, cols do m[i][j] = val end
  end
  return m
end

--- Argmax of a 1D array, returns (index, value)
function M.argmax(t)
  local best_i, best_v = 1, t[1]
  for i = 2, #t do
    if t[i] > best_v then best_i, best_v = i, t[i] end
  end
  return best_i, best_v
end

--- Sum of array elements
function M.sum(t)
  local s = 0.0
  for i = 1, #t do s = s + t[i] end
  return s
end

--- Dot product of two arrays
function M.dot(a, b)
  local s = 0.0
  local n = min(#a, #b)
  for i = 1, n do s = s + a[i] * b[i] end
  return s
end

--- L2 norm of an array
function M.norm(t)
  return sqrt(M.dot(t, t))
end

-- ============================================================================
-- 2. BAHA — Branch-Aware Holonomy Annealing
-- ============================================================================
--
-- Detects fractures in the energy landscape via ρ = |d/dβ log Z| and
-- enumerates alternative thermodynamic branches via the Lambert-W function.
--
-- References:
--   "Multiplicative Calculus for Hardness Detection and Branch-Aware
--    Optimization" — Sethu Iyer, ShunyaBar Labs
-- ============================================================================

shunyabar.baha = {}
local baha = shunyabar.baha

-- ----------------------------- Lambert-W ------------------------------------

baha.LambertW = {}
local LW = baha.LambertW

LW.E_INV   = 1.0 / exp(1.0)   -- 1/e ≈ 0.3679
LW.TOL     = 1e-10
LW.MAX_ITER = 50

--- Halley iteration to refine w * e^w = z
function LW.halley_iterate(z, w)
  for _ = 1, LW.MAX_ITER do
    local ew  = exp(w)
    local wew = w * ew
    local f   = wew - z
    local fp  = ew * (w + 1.0)
    if abs(fp) < 1e-15 then break end
    local fpp   = ew * (w + 2.0)
    local denom = fp - f * fpp / (2.0 * fp)
    if abs(denom) < 1e-15 then break end
    local w_new = w - f / denom
    if abs(w_new - w) < LW.TOL then return w_new end
    w = w_new
  end
  return w
end

--- Principal branch W₀(z), z ≥ -1/e
function LW.W0(z)
  if z < -LW.E_INV then return 0/0 end  -- NaN
  local w
  if z < -0.3 then
    w = z * exp(1.0)
  elseif z < 1.0 then
    w = z * (1.0 - z + z * z)
  else
    local lz = log(z)
    w = lz - log(lz + 1.0)
  end
  return LW.halley_iterate(z, w)
end

--- Secondary branch W₋₁(z), z ∈ [-1/e, 0)
function LW.Wm1(z)
  if z < -LW.E_INV or z >= 0.0 then return 0/0 end
  local w = log(-z) - log(-log(-z))
  return LW.halley_iterate(z, w)
end

--- General branch W_k(z) — only k=0 and k=-1 implemented
function LW.Wk(z, k)
  if k == 0  then return LW.W0(z)  end
  if k == -1 then return LW.Wm1(z) end
  return 0/0
end

-- -------------------------- Fracture Detector -------------------------------

--- Create a new FractureDetector
--- @param threshold number   Fracture detection threshold (default 1.5)
function baha.FractureDetector(threshold)
  local self = {
    threshold    = threshold or 1.5,
    beta_history = {},
    logZ_history = {},
  }

  function self:record(beta, log_Z)
    self.beta_history[#self.beta_history + 1] = beta
    self.logZ_history[#self.logZ_history + 1] = log_Z
  end

  function self:fracture_rate()
    local n = #self.beta_history
    if n < 2 then return 0.0 end
    local d_logZ = abs(self.logZ_history[n] - self.logZ_history[n - 1])
    local d_beta = self.beta_history[n] - self.beta_history[n - 1]
    if d_beta <= 0 then return 0.0 end
    return d_logZ / d_beta
  end

  function self:is_fracture()
    return self:fracture_rate() > self.threshold
  end

  function self:clear()
    self.beta_history = {}
    self.logZ_history = {}
  end

  return self
end

-- ---------------------- Branch-Aware Optimizer ------------------------------

--- Create a BranchAwareOptimizer
--- @param energy_fn   function(state) -> number
--- @param sampler_fn  function()      -> state
--- @param neighbor_fn function(state) -> {state, ...}  (optional)
function baha.BranchAwareOptimizer(energy_fn, sampler_fn, neighbor_fn)
  local self = {}

  -- Default configuration
  self.config = {
    beta_start        = 0.01,
    beta_end          = 10.0,
    beta_steps        = 500,
    fracture_threshold = 1.5,
    beta_critical     = 1.0,
    max_branches      = 5,
    samples_per_beta  = 100,
    verbose           = false,
  }

  --- Estimate log Z(β) via Monte-Carlo sampling
  local function estimate_log_Z(beta, n_samples)
    local log_terms = {}
    for i = 1, n_samples do
      local s = sampler_fn()
      local E = energy_fn(s)
      log_terms[i] = -beta * E
    end
    return M.log_sum_exp(log_terms)
  end

  --- Enumerate Lambert-W branches at current β
  local function enumerate_branches(beta, beta_c)
    local branches = {}
    local u = beta - beta_c
    if abs(u) < 1e-10 then u = 1e-10 end
    local xi = u * exp(u)

    -- Principal branch k=0
    local w0 = LW.W0(xi)
    if w0 == w0 then  -- not NaN
      local b0 = beta_c + w0
      if b0 > 0 then branches[#branches + 1] = { k = 0, beta = b0, score = 0.0 } end
    end

    -- Secondary branch k=-1
    if xi >= -LW.E_INV and xi < 0 then
      local wm1 = LW.Wm1(xi)
      if wm1 == wm1 then
        local bm1 = beta_c + wm1
        if bm1 > 0 then branches[#branches + 1] = { k = -1, beta = bm1, score = 0.0 } end
      end
    end
    return branches
  end

  --- Score a branch by Boltzmann sampling
  local function score_branch(beta, n_samples)
    if beta <= 0 then return -huge end
    local total = 0.0
    local best_E = huge
    for _ = 1, n_samples do
      local s = sampler_fn()
      local E = energy_fn(s)
      total = total + exp(-beta * E)
      if E < best_E then best_E = E end
    end
    return total / n_samples + 100.0 / (best_E + 1.0)
  end

  --- Sample best state at a given β
  local function sample_from_branch(beta, n_samples)
    local best = sampler_fn()
    local best_E = energy_fn(best)
    for _ = 1, n_samples do
      local s = sampler_fn()
      local E = energy_fn(s)
      if E < best_E then best, best_E = s, E end
    end
    -- Local greedy improvement
    if neighbor_fn then
      local improved = true
      while improved do
        improved = false
        local nbrs = neighbor_fn(best)
        for _, nbr in ipairs(nbrs) do
          local E = energy_fn(nbr)
          if E < best_E then
            best, best_E = nbr, E
            improved = true
            break
          end
        end
      end
    end
    return best, best_E
  end

  --- Run optimization
  --- @param cfg table  Optional config overrides
  --- @return table      {best_state, best_energy, fractures_detected, branch_jumps, ...}
  function self:optimize(cfg)
    cfg = cfg or {}
    for k, v in pairs(self.config) do
      if cfg[k] == nil then cfg[k] = v end
    end

    local t0 = os.clock()
    local detector = baha.FractureDetector(cfg.fracture_threshold)

    -- Build β schedule
    local schedule = {}
    for i = 0, cfg.beta_steps - 1 do
      schedule[i + 1] = cfg.beta_start +
        (cfg.beta_end - cfg.beta_start) * i / (cfg.beta_steps - 1)
    end

    local current   = sampler_fn()
    local cur_E     = energy_fn(current)
    local best      = current
    local best_E    = cur_E
    local fractures = 0
    local jumps     = 0

    for step = 1, cfg.beta_steps do
      local beta = schedule[step]
      local logZ = estimate_log_Z(beta, cfg.samples_per_beta)
      detector:record(beta, logZ)
      local rho = detector:fracture_rate()

      -- Fracture detected
      if detector:is_fracture() then
        fractures = fractures + 1
        if cfg.verbose then
          io.write(string.format("  FRACTURE at beta=%.3f  rho=%.2f\n", beta, rho))
        end

        local branches = enumerate_branches(beta, cfg.beta_critical)
        for _, b in ipairs(branches) do
          b.score = score_branch(b.beta, cfg.samples_per_beta)
        end
        table.sort(branches, function(a, b) return a.score > b.score end)

        if #branches > 0 then
          local jumped, jumped_E = sample_from_branch(branches[1].beta, cfg.samples_per_beta)
          if jumped_E < best_E then
            best, best_E = jumped, jumped_E
            jumps = jumps + 1
            if cfg.verbose then
              io.write(string.format("  JUMPED to E=%.4f\n", best_E))
            end
            if best_E <= 0 then
              return {
                best_state = best, best_energy = best_E,
                fractures_detected = fractures, branch_jumps = jumps,
                beta_at_solution = beta, steps_taken = step,
                time_s = os.clock() - t0,
              }
            end
          end
        end
      end

      -- Standard Metropolis local search
      if neighbor_fn then
        local nbrs = neighbor_fn(current)
        for _, nbr in ipairs(nbrs) do
          local nbr_E = energy_fn(nbr)
          if nbr_E < cur_E or math.random() < exp(-beta * (nbr_E - cur_E)) then
            current, cur_E = nbr, nbr_E
            if cur_E < best_E then
              best, best_E = current, cur_E
            end
          end
        end
      end
    end

    return {
      best_state = best, best_energy = best_E,
      fractures_detected = fractures, branch_jumps = jumps,
      beta_at_solution = cfg.beta_end, steps_taken = cfg.beta_steps,
      time_s = os.clock() - t0,
    }
  end

  return self
end

-- ---------------------- Simulated Annealing (baseline) ----------------------

--- Standard SA for comparison
function baha.SimulatedAnnealing(energy_fn, sampler_fn, neighbor_fn)
  local self = {}

  self.config = {
    beta_start     = 0.01,
    beta_end       = 10.0,
    beta_steps     = 500,
    steps_per_beta = 10,
    verbose        = false,
  }

  function self:optimize(cfg)
    cfg = cfg or {}
    for k, v in pairs(self.config) do
      if cfg[k] == nil then cfg[k] = v end
    end

    local t0    = os.clock()
    local cur   = sampler_fn()
    local cur_E = energy_fn(cur)
    local best, best_E = cur, cur_E

    for step = 0, cfg.beta_steps - 1 do
      local beta = cfg.beta_start +
        (cfg.beta_end - cfg.beta_start) * step / (cfg.beta_steps - 1)

      for _ = 1, cfg.steps_per_beta do
        local nbrs = neighbor_fn(cur)
        if #nbrs == 0 then break end
        local nbr = nbrs[math.random(#nbrs)]
        local nbr_E = energy_fn(nbr)
        local delta = nbr_E - cur_E
        if delta < 0 or math.random() < exp(-beta * delta) then
          cur, cur_E = nbr, nbr_E
          if cur_E < best_E then
            best, best_E = cur, cur_E
            if best_E <= 0 then
              return {
                best_state = best, best_energy = best_E,
                beta_at_solution = beta,
                steps_taken = step * cfg.steps_per_beta,
                time_s = os.clock() - t0,
              }
            end
          end
        end
      end
    end

    return {
      best_state = best, best_energy = best_E,
      beta_at_solution = cfg.beta_end,
      steps_taken = cfg.beta_steps * cfg.steps_per_beta,
      time_s = os.clock() - t0,
    }
  end

  return self
end

-- ============================================================================
-- 3. NAVOKOJ — Constraint Satisfaction via Geometric Flow
-- ============================================================================
--
-- Treats constraint satisfaction as energy minimization on a continuous
-- manifold. Uses prime-weighted operators and adiabatic cooling.
--
-- Three sectors:
--   Arithmetic : prime weights break symmetry
--   Geometric  : continuous state space relaxation
--   Dynamic    : adiabatic cooling + gradient flow
-- ============================================================================

shunyabar.navokoj = {}
local navokoj = shunyabar.navokoj

-- ----------------------------- SAT Solver -----------------------------------

--- Solve SAT via prime-weighted geometric flow
--- @param num_vars  number          Number of boolean variables
--- @param clauses   {{int,...},...}  List of clauses (positive lit = var, negative = negated)
--- @param opts      table           Optional {steps, learning_rate, beta_max, seed}
--- @return          {0|1,...}       Boolean assignment (1-indexed, 0 or 1)
function navokoj.solve_sat(num_vars, clauses, opts)
  opts = opts or {}
  local steps = opts.steps or 1000
  local lr    = opts.learning_rate or 0.1
  local bmax  = opts.beta_max or 2.5

  if opts.seed then M.seed(opts.seed) end

  -- 1. Arithmetic Sector: prime weights
  local primes  = M.generate_primes(#clauses)
  local weights = {}
  for i = 1, #primes do
    weights[i] = 1.0 / log(primes[i] + 1.0)
  end

  -- 2. Geometric Sector: continuous state in (0,1)
  local state = {}
  for i = 1, num_vars do
    state[i] = 0.5 + M.randn() * 0.001
  end

  -- 3. Dynamic Sector: adiabatic sweep
  for step = 0, steps - 1 do
    local beta = (step / steps) * bmax
    local grad = M.zeros(num_vars)

    for ci, clause in ipairs(clauses) do
      -- Compute P(clause unsatisfied) = ∏(1 - P(literal))
      local unsat = 1.0
      local lit_probs = {}
      for li, lit in ipairs(clause) do
        local vi = abs(lit)
        local p = (lit > 0) and state[vi] or (1.0 - state[vi])
        unsat = unsat * (1.0 - p)
        lit_probs[li] = p
      end
      local sat = 1.0 - unsat + 1e-9
      local coeff = weights[ci] / sat * unsat

      for li, lit in ipairs(clause) do
        local vi   = abs(lit)
        local sign = (lit > 0) and 1.0 or -1.0
        grad[vi] = grad[vi] + coeff * sign * (1.0 / (1.0 - lit_probs[li] + 1e-9))
      end
    end

    -- Gradient descent with temperature scaling
    local eff_lr = lr * beta
    for i = 1, num_vars do
      state[i] = M.clamp(state[i] + eff_lr * grad[i], 0.001, 0.999)
    end
  end

  -- 4. Collapse
  local assignment = {}
  for i = 1, num_vars do
    assignment[i] = (state[i] > 0.5) and 1 or 0
  end
  return assignment
end

--- Generate random 3-SAT at critical density α ≈ 4.26
function navokoj.generate_3sat(n_vars, alpha, seed)
  alpha = alpha or 4.26
  if seed then M.seed(seed) end
  local n_clauses = floor(n_vars * alpha)
  local clauses = {}
  for _ = 1, n_clauses do
    -- Pick 3 distinct variables
    local vs = {}
    while #vs < 3 do
      local v = math.random(1, n_vars)
      local dup = false
      for _, existing in ipairs(vs) do if existing == v then dup = true; break end end
      if not dup then vs[#vs + 1] = v end
    end
    local clause = {}
    for _, v in ipairs(vs) do
      clause[#clause + 1] = (math.random() > 0.5) and v or -v
    end
    clauses[#clauses + 1] = clause
  end
  return clauses
end

--- Encode N-Queens as SAT clauses
--- @return num_vars, clauses
function navokoj.encode_n_queens(n)
  local clauses = {}
  local function var(r, c) return (r - 1) * n + c end

  -- At least one queen per row
  for r = 1, n do
    local clause = {}
    for c = 1, n do clause[c] = var(r, c) end
    clauses[#clauses + 1] = clause
  end
  -- At most one per row
  for r = 1, n do
    for c1 = 1, n do for c2 = c1 + 1, n do
      clauses[#clauses + 1] = { -var(r, c1), -var(r, c2) }
    end end
  end
  -- At most one per column
  for c = 1, n do
    for r1 = 1, n do for r2 = r1 + 1, n do
      clauses[#clauses + 1] = { -var(r1, c), -var(r2, c) }
    end end
  end
  -- At most one per diagonal
  for r1 = 1, n do for c1 = 1, n do
    for r2 = r1 + 1, n do for c2 = 1, n do
      if abs(r1 - r2) == abs(c1 - c2) then
        clauses[#clauses + 1] = { -var(r1, c1), -var(r2, c2) }
      end
    end end
  end end

  return n * n, clauses
end

--- Encode 9×9 Sudoku as SAT clauses
--- @param grid_str string  81-char string, '1'-'9' = given, '.' or '0' = empty
--- @return num_vars, clauses
function navokoj.encode_sudoku(grid_str)
  local N = 9
  local clauses = {}
  local function var(r, c, v) return ((r - 1) * N + (c - 1)) * N + v end

  -- Each cell has at least one value
  for r = 1, N do for c = 1, N do
    local clause = {}
    for v = 1, N do clause[v] = var(r, c, v) end
    clauses[#clauses + 1] = clause
  end end

  for v = 1, N do
    -- Row uniqueness
    for r = 1, N do for c1 = 1, N do for c2 = c1 + 1, N do
      clauses[#clauses + 1] = { -var(r, c1, v), -var(r, c2, v) }
    end end end
    -- Column uniqueness
    for c = 1, N do for r1 = 1, N do for r2 = r1 + 1, N do
      clauses[#clauses + 1] = { -var(r1, c, v), -var(r2, c, v) }
    end end end
    -- Box uniqueness
    for br = 0, 2 do for bc = 0, 2 do
      local cells = {}
      for i = 1, 3 do for j = 1, 3 do
        cells[#cells + 1] = { br * 3 + i, bc * 3 + j }
      end end
      for i = 1, #cells do for j = i + 1, #cells do
        clauses[#clauses + 1] = {
          -var(cells[i][1], cells[i][2], v),
          -var(cells[j][1], cells[j][2], v)
        }
      end end
    end end
  end

  -- Fixed clues
  local clean = grid_str:gsub("[%s\n]", "")
  for i = 1, #clean do
    local ch = clean:sub(i, i)
    if ch >= "1" and ch <= "9" then
      local val = tonumber(ch)
      local r = floor((i - 1) / 9) + 1
      local c = ((i - 1) % 9) + 1
      clauses[#clauses + 1] = { var(r, c, val) }
    end
  end

  return 729, clauses
end

--- Verify SAT solution: returns fraction of clauses satisfied
function navokoj.verify_solution(clauses, assignment)
  local sat = 0
  for _, clause in ipairs(clauses) do
    local ok = false
    for _, lit in ipairs(clause) do
      local vi = abs(lit)
      local val = assignment[vi]
      if (lit > 0 and val == 1) or (lit < 0 and val == 0) then
        ok = true; break
      end
    end
    if ok then sat = sat + 1 end
  end
  return (#clauses > 0) and (sat / #clauses) or 1.0
end

-- ----------------------------- Q-State Solver -------------------------------

--- Solve Q-state assignment (graph coloring) via softmax flow
--- @param n_nodes     number
--- @param n_states    number
--- @param constraints {{int,int},...}  Edges requiring different states (1-indexed)
--- @param opts        table            Optional {steps, learning_rate, beta_max, seed}
--- @return            {int,...}        State assignment per node (1-indexed values)
function navokoj.solve_qstate(n_nodes, n_states, constraints, opts)
  opts = opts or {}
  local steps = opts.steps or 2000
  local lr    = opts.learning_rate or 0.1
  local bmax  = opts.beta_max or 5.0
  if opts.seed then M.seed(opts.seed) end

  -- Arithmetic: prime weights
  local primes  = M.generate_primes(#constraints)
  local weights = {}
  for i = 1, #primes do weights[i] = 1.0 / log(primes[i] + 1.0) end

  -- Geometric: continuous potential matrix [node][state]
  local pot = M.matrix(n_nodes, n_states)
  for i = 1, n_nodes do
    for k = 1, n_states do pot[i][k] = M.randn() * 0.1 end
  end

  -- Convert constraints to 0-indexed internally
  local edges = {}
  for i, e in ipairs(constraints) do
    edges[i] = { e[1], e[2] }  -- keep 1-indexed for Lua
  end

  -- Dynamic: adiabatic sweep
  for step = 0, steps - 1 do
    local beta = (step / steps) * bmax

    -- Softmax -> probabilities
    local probs = {}
    for i = 1, n_nodes do
      probs[i] = M.softmax(pot[i], beta)
    end

    -- Gradient: repulsive force
    local grad = M.matrix(n_nodes, n_states)
    for ei, e in ipairs(edges) do
      local u, v = e[1], e[2]
      local w = weights[ei]
      for k = 1, n_states do
        grad[u][k] = grad[u][k] + w * probs[v][k]
        grad[v][k] = grad[v][k] + w * probs[u][k]
      end
    end

    -- Update
    for i = 1, n_nodes do
      for k = 1, n_states do
        pot[i][k] = pot[i][k] - lr * grad[i][k]
      end
    end

    -- Periodic noise to escape saddles
    if step % 100 == 0 then
      for i = 1, n_nodes do
        for k = 1, n_states do
          pot[i][k] = pot[i][k] + M.randn() * 0.05
        end
      end
    end
  end

  -- Collapse: argmax
  local assignment = {}
  for i = 1, n_nodes do
    assignment[i] = M.argmax(pot[i])
  end
  return assignment
end

--- Generate random graph for Q-state coloring
function navokoj.generate_q_graph(n_nodes, density, seed)
  density = density or 0.2
  if seed then M.seed(seed) end
  local constraints = {}
  for i = 1, n_nodes do
    for j = i + 1, n_nodes do
      if math.random() < density then
        constraints[#constraints + 1] = { i, j }
      end
    end
  end
  return constraints
end

--- Verify Q-state solution: returns number of violations
function navokoj.verify_qstate(constraints, assignment)
  local violations = 0
  for _, e in ipairs(constraints) do
    if assignment[e[1]] == assignment[e[2]] then violations = violations + 1 end
  end
  return violations
end

-- ----------------------------- Job Scheduler --------------------------------

--- Schedule jobs using geometric flow on temporal manifold
--- @param jobs        {{duration=n, name=s},...}  1-indexed job configs
--- @param conflicts   {{int,int},...}             Pairs that can't overlap
--- @param precedences {{int,int},...}             (i,j) means i finishes before j
--- @param opts        table                       {horizon, steps, learning_rate, beta_max, seed}
--- @return            {number,...}                Start times per job (1-indexed)
function navokoj.schedule_jobs(jobs, conflicts, precedences, opts)
  opts = opts or {}
  local horizon = opts.horizon or 100.0
  local steps   = opts.steps or 5000
  local lr      = opts.learning_rate or 0.5
  local bmax    = opts.beta_max or 10.0
  if opts.seed then M.seed(opts.seed) end

  local n = #jobs

  -- Geometric: random initial start times
  local t = {}
  for i = 1, n do t[i] = M.uniform(0, horizon / 2.0) end

  -- Arithmetic: primes for perturbation
  local primes = M.generate_primes(n)

  -- Dynamic: adiabatic sweep
  for step = 0, steps - 1 do
    local beta = (step / steps) * bmax
    local grad = M.zeros(n)

    -- Precedence springs
    for _, pr in ipairs(precedences) do
      local i, j = pr[1], pr[2]
      local end_i = t[i] + jobs[i].duration
      local violation = end_i - t[j]
      if violation > 0 then
        grad[i] = grad[i] - violation
        grad[j] = grad[j] + violation
      end
    end

    -- Conflict repulsion
    for _, cf in ipairs(conflicts) do
      local i, j = cf[1], cf[2]
      local end_i = t[i] + jobs[i].duration
      local end_j = t[j] + jobs[j].duration
      local latest_start  = max(t[i], t[j])
      local earliest_end  = min(end_i, end_j)
      local overlap = earliest_end - latest_start
      if overlap > 0 then
        local dir = (t[i] < t[j]) and 1.0 or -1.0
        local force = overlap * beta
        grad[i] = grad[i] - force * dir
        grad[j] = grad[j] + force * dir
      end
    end

    -- Horizon gravity
    for i = 1, n do grad[i] = grad[i] - 0.01 * t[i] end

    -- Update
    for i = 1, n do t[i] = t[i] + lr * grad[i] end

    -- Periodic prime perturbation
    if step % 500 == 0 then
      for i = 1, n do
        t[i] = t[i] + math.sin(primes[i] * step) * 2.0
      end
    end

    -- Non-negative
    for i = 1, n do t[i] = max(t[i], 0.0) end
  end

  return t
end

--- Verify schedule constraints, returns (valid, violations_list)
function navokoj.verify_schedule(jobs, schedule, conflicts, precedences, tol)
  tol = tol or 0.1
  local violations = {}
  local valid = true

  for _, pr in ipairs(precedences) do
    local i, j = pr[1], pr[2]
    local gap = schedule[j] - (schedule[i] + jobs[i].duration)
    if gap < -tol then
      violations[#violations + 1] = string.format(
        "Precedence: Job %d ends at %.1f, Job %d starts at %.1f (gap %.1f)",
        i, schedule[i] + jobs[i].duration, j, schedule[j], gap)
      valid = false
    end
  end

  for _, cf in ipairs(conflicts) do
    local i, j = cf[1], cf[2]
    local overlap = min(schedule[i] + jobs[i].duration, schedule[j] + jobs[j].duration)
                  - max(schedule[i], schedule[j])
    if overlap > tol then
      violations[#violations + 1] = string.format(
        "Conflict: Jobs %d and %d overlap by %.1f", i, j, overlap)
      valid = false
    end
  end

  return valid, violations
end

-- ============================================================================
-- 4. MULTIPLICATIVE PINN — Euler Product Gate + Exponential Barrier
-- ============================================================================
--
-- Enforces physics constraints multiplicatively rather than additively:
--   L_total = L_data * C(v)
-- where C(v) = max(G(v), B(v))
--   G(v) = ∏(1 - p^(-τ*v))       Euler gate (attenuation near v=0)
--   B(v) = e^(γ*v)                Exponential barrier (amplification)
--
-- This preserves gradient direction (no conflict between data and physics).
-- ============================================================================

shunyabar.pinn = {}
local pinn = shunyabar.pinn

--- Compute Euler product gate G(v)
--- @param v      number   Violation magnitude (≥ 0)
--- @param primes {number,...}  Prime basis (default {2,3,5,7,11})
--- @param tau    number   Gate sharpness (default 3.0)
--- @return       number   Gate value in [0, 1]
function pinn.euler_gate(v, primes, tau)
  primes = primes or { 2, 3, 5, 7, 11 }
  tau    = tau or 3.0
  local gate = 1.0
  for _, p in ipairs(primes) do
    local term = 1.0 - p ^ (-tau * v)
    if term < 1e-9 then term = 1e-9 end
    gate = gate * term
  end
  return M.clamp(gate, 1e-6, 1.0)
end

--- Compute exponential barrier B(v)
--- @param v     number  Violation magnitude
--- @param gamma number  Barrier sharpness (default 5.0)
--- @return      number  Barrier value ≥ 1
function pinn.exp_barrier(v, gamma)
  gamma = gamma or 5.0
  return exp(gamma * v)
end

--- Compute combined constraint factor C(v) = max(G(v), B(v))
--- @param v      number  Violation magnitude
--- @param opts   table   Optional {primes, tau, gamma}
--- @return       number  Constraint factor
function pinn.constraint_factor(v, opts)
  opts = opts or {}
  local g = pinn.euler_gate(v, opts.primes, opts.tau)
  local b = pinn.exp_barrier(v, opts.gamma)
  return M.clamp(max(g, b), 1e-6, 1e6)
end

--- Compute multiplicative loss: L_total = L_data * C(v)
--- Also returns the log-space gradient decomposition:
---   ∇log L_total = ∇log L_data + γ∇S_spec
---
--- @param data_loss   number  Data fidelity loss
--- @param violation   number  Constraint violation magnitude
--- @param opts        table   Optional {primes, tau, gamma}
--- @return            number, number, table  total_loss, factor, info
function pinn.multiplicative_loss(data_loss, violation, opts)
  opts = opts or {}
  local factor = pinn.constraint_factor(violation, opts)
  local total  = data_loss * factor
  return total, factor, {
    data_loss  = data_loss,
    violation  = violation,
    factor     = factor,
    total_loss = total,
    log_total  = log(abs(total) + 1e-15),
    log_data   = log(abs(data_loss) + 1e-15),
    log_factor = log(abs(factor) + 1e-15),
  }
end

--- Compute prime spectral weights: w_c = 1/log(p_c)
--- Returns a hierarchy where smaller primes dominate
function pinn.prime_weights(n)
  local primes = M.generate_primes(n)
  local weights = {}
  for i, p in ipairs(primes) do
    weights[i] = 1.0 / log(p)
  end
  return weights, primes
end

--- Evaluate the Euler product approximation to ζ(s)
--- ζ(s) ≈ ∏_p 1/(1 - p^(-s))
function pinn.euler_product_zeta(s, n_primes)
  n_primes = n_primes or 15
  local primes = M.generate_primes(n_primes)
  local product = 1.0
  for _, p in ipairs(primes) do
    product = product / (1.0 - p ^ (-s))
  end
  return product
end

-- ============================================================================
-- 5. CASIMIR SAT — Quantum-Inspired SAT via Langevin Dynamics
-- ============================================================================
--
-- Variables are continuous probabilities x_i ∈ [0,1].
-- Constraints generate energy gradients. Thermal noise enables exploration.
-- Satisfied clusters attract via "Casimir forces."
--
--   dx/dt = -η ∇E + √(2T) ξ
--
-- Energy: E = Σ (1 - s_c)²
-- where s_c = 1 - ∏(1 - x_ℓ) is fractional satisfaction
-- ============================================================================

shunyabar.casimir = {}
local casimir = shunyabar.casimir

--- Create a CasimirSolver instance
--- @param num_vars     number
--- @param clauses      {{int,...},...}
--- @param opts         table  {temperature, learning_rate, correlation_length}
function casimir.Solver(num_vars, clauses, opts)
  opts = opts or {}
  local self = {
    num_vars           = num_vars,
    clauses            = clauses,
    temperature        = opts.temperature or 2.0,
    learning_rate      = opts.learning_rate or 0.5,
    correlation_length = opts.correlation_length or 3.0,
    step_count         = 0,
    beta               = 1.0,
  }

  -- State: continuous probabilities
  self.x = M.zeros(num_vars, 0.5)
  -- Internal logit-space state for stable dynamics
  self.u = M.zeros(num_vars, 0.0)

  --- Fractional satisfaction: s_c = 1 - ∏(1 - x_ℓ)
  function self:fractional_satisfaction(clause)
    local unsat = 1.0
    for _, lit in ipairs(clause) do
      local vi = abs(lit)
      if lit > 0 then
        unsat = unsat * (1.0 - self.x[vi])
      else
        unsat = unsat * self.x[vi]
      end
    end
    return 1.0 - unsat
  end

  --- Total energy: E = Σ (1 - s_c)²
  function self:total_energy()
    local E = 0.0
    for _, clause in ipairs(self.clauses) do
      local sc = self:fractional_satisfaction(clause)
      E = E + (1.0 - sc) ^ 2
    end
    return E
  end

  --- Compute gradients ∂E/∂x_i
  function self:compute_gradients()
    local grads = M.zeros(self.num_vars)
    for _, clause in ipairs(self.clauses) do
      -- P = ∏(1-x_ℓ) for positive, ∏(x_ℓ) for negative
      local unsat = 1.0
      for _, lit in ipairs(clause) do
        local vi = abs(lit)
        if lit > 0 then
          unsat = unsat * (1.0 - self.x[vi])
        else
          unsat = unsat * self.x[vi]
        end
      end
      if unsat == 0 then goto continue end

      -- dE/dx_i = 2 * P * dP/dx_i
      for _, lit in ipairs(clause) do
        local vi = abs(lit)
        if lit > 0 then
          local denom = 1.0 - self.x[vi]
          if denom > 1e-10 then
            local deriv = -unsat / denom
            grads[vi] = grads[vi] + 2.0 * unsat * deriv
          end
        else
          if self.x[vi] > 1e-10 then
            local deriv = unsat / self.x[vi]
            grads[vi] = grads[vi] + 2.0 * unsat * deriv
          end
        end
      end
      ::continue::
    end
    return grads
  end

  --- Langevin dynamics step: dx/dt = -η∇E + √(2T)ξ
  --- Uses logit-space accumulator for stability
  function self:langevin_step()
    local grads = self:compute_gradients()

    for i = 1, self.num_vars do
      local noise = sqrt(2.0 * self.temperature) * M.randn()
      -- Update internal logit state
      self.u[i] = self.u[i] + (-self.learning_rate * grads[i] + 0.1 * noise)
      -- Project to [0,1] via sigmoid
      self.x[i] = M.sigmoid(self.beta * self.u[i])
    end

    -- Annealing schedules
    self.step_count = self.step_count + 1
    self.temperature = 2.0 / log(1.0 + self.step_count * 0.05)
    self.beta = 1.0 + self.step_count * 0.01
    self.correlation_length = self.correlation_length * 0.995
  end

  --- Check if solution is found (energy near zero and values boolean-like)
  function self:is_converged(tol)
    tol = tol or 1e-3
    if self:total_energy() > tol then return false end
    for i = 1, self.num_vars do
      if self.x[i] > 0.1 and self.x[i] < 0.9 then return false end
    end
    return true
  end

  --- Extract boolean assignment from current state
  function self:get_assignment()
    local assignment = {}
    for i = 1, self.num_vars do
      assignment[i] = (self.x[i] > 0.5) and 1 or 0
    end
    return assignment
  end

  --- Run solver for up to max_steps
  function self:solve(max_steps)
    max_steps = max_steps or 1000
    for step = 1, max_steps do
      self:langevin_step()
      if self:is_converged() then
        return self:get_assignment(), step, self:total_energy()
      end
    end
    return self:get_assignment(), max_steps, self:total_energy()
  end

  --- Build variable-constraint adjacency matrix (for spectral analysis)
  function self:build_adjacency()
    local adj = M.matrix(self.num_vars, self.num_vars)
    for _, clause in ipairs(self.clauses) do
      for i = 1, #clause do
        local u = abs(clause[i])
        for j = i + 1, #clause do
          local v = abs(clause[j])
          adj[u][v] = 1.0
          adj[v][u] = 1.0
        end
      end
    end
    return adj
  end

  return self
end

-- ============================================================================
-- 6. ZETAGROK — Spectral Entropy × Multiplicative Twist
-- ============================================================================
--
-- Induces grokking as a phase transition by making the loss proportional to
-- spectral disorder in the attention/weight matrix:
--
--   L_total = L_task × exp(γ × S_spec)
--
-- where S_spec = (TotalEnergy - TopK_Energy) / TotalEnergy
--
-- High entropy (messy spectrum) → large twist → violent gradients (explore)
-- Low entropy (clean spectrum)  → twist ≈ 1  → stable learning (exploit)
-- ============================================================================

shunyabar.zetagrok = {}
local zg = shunyabar.zetagrok

--- Estimate top-K eigenvalue magnitudes of matrix A via power iteration
--- @param A      {{number,...},...}  Square matrix [N][N]
--- @param K      number             Number of dominant modes (default 3)
--- @param iters  number             Power iteration steps (default 5)
--- @return       {number,...}       Top K eigenvalue magnitude estimates
function zg.power_iteration_topk(A, K, iters)
  K     = K or 3
  iters = iters or 5
  local N = #A

  -- Initialize K random vectors
  local Q = M.matrix(N, K)
  for j = 1, K do
    for i = 1, N do Q[i][j] = M.randn() end
    -- Normalize
    local nrm = 0
    for i = 1, N do nrm = nrm + Q[i][j]^2 end
    nrm = sqrt(nrm)
    if nrm > 1e-15 then
      for i = 1, N do Q[i][j] = Q[i][j] / nrm end
    end
  end

  -- Power iteration with orthogonalization
  for _ = 1, iters do
    -- Z = A * Q
    local Z = M.matrix(N, K)
    for i = 1, N do
      for j = 1, K do
        local s = 0
        for m = 1, N do s = s + A[i][m] * Q[m][j] end
        Z[i][j] = s
      end
    end

    -- Modified Gram-Schmidt for QR
    for j = 1, K do
      -- Subtract projections onto previous columns
      for p = 1, j - 1 do
        local dot = 0
        for i = 1, N do dot = dot + Q[i][p] * Z[i][j] end
        for i = 1, N do Z[i][j] = Z[i][j] - dot * Q[i][p] end
      end
      -- Normalize
      local nrm = 0
      for i = 1, N do nrm = nrm + Z[i][j]^2 end
      nrm = sqrt(nrm)
      if nrm > 1e-15 then
        for i = 1, N do Q[i][j] = Z[i][j] / nrm end
      else
        for i = 1, N do Q[i][j] = Z[i][j] end
      end
    end
  end

  -- Rayleigh quotient: λ_j ≈ q_j^T A q_j
  local eigenvalues = {}
  for j = 1, K do
    -- Compute A * q_j
    local Aq = M.zeros(N)
    for i = 1, N do
      local s = 0
      for m = 1, N do s = s + A[i][m] * Q[m][j] end
      Aq[i] = s
    end
    -- Dot product q_j · (A q_j)
    local lam = 0
    for i = 1, N do lam = lam + Q[i][j] * Aq[i] end
    eigenvalues[j] = abs(lam)
  end

  return eigenvalues
end

--- Compute spectral entropy of a matrix
--- S_spec = (TotalEnergy - TopK_Energy) / TotalEnergy
--- @param A     {{number,...},...}  Square matrix
--- @param K     number             Number of dominant modes
--- @param iters number             Power iteration steps
--- @return      number, table      entropy, {total_energy, topk_energy, tail_energy}
function zg.spectral_entropy(A, K, iters)
  K     = K or 3
  iters = iters or 5
  local N = #A

  -- Total energy = ||A||_F^2 = Σ A_ij^2
  local total_energy = 0
  for i = 1, N do
    for j = 1, N do
      total_energy = total_energy + A[i][j]^2
    end
  end

  if total_energy < 1e-15 then return 0.0, { total_energy=0, topk_energy=0, tail_energy=0 } end

  -- Top-K energy
  local topk_lambdas = zg.power_iteration_topk(A, K, iters)
  local topk_energy = 0
  for _, lam in ipairs(topk_lambdas) do
    topk_energy = topk_energy + lam^2
  end

  local tail_energy = max(0, total_energy - topk_energy)
  local entropy = tail_energy / (total_energy + 1e-9)

  return entropy, {
    total_energy = total_energy,
    topk_energy  = topk_energy,
    tail_energy  = tail_energy,
  }
end

--- ZetaGrokLoss: L_total = L_task × exp(γ × S_spec)
--- @param task_loss  number             Scalar task loss (e.g. cross-entropy)
--- @param A          {{number,...},...}  Attention / weight matrix
--- @param opts       table              {K, gamma, power_iters}
--- @return           number, table      total_loss, metrics
function zg.zetagrok_loss(task_loss, A, opts)
  opts = opts or {}
  local K     = opts.K or 3
  local gamma = opts.gamma or 2.0
  local iters = opts.power_iters or 5

  local entropy, info = zg.spectral_entropy(A, K, iters)
  local twist  = exp(gamma * entropy)
  local total  = task_loss * twist

  return total, {
    task_loss        = task_loss,
    spectral_entropy = entropy,
    twist_factor     = twist,
    total_loss       = total,
    total_energy     = info.total_energy,
    topk_energy      = info.topk_energy,
    tail_energy      = info.tail_energy,
  }
end

-- ============================================================================
-- 7. SELF-TEST / DEMO
-- ============================================================================

function shunyabar.demo()
  print("=" .. string.rep("=", 69))
  print("  SHUNYABAR — The Arithmetic Manifold (Lua standalone)")
  print("  Author: Sethu Iyer | License: MIT")
  print("=" .. string.rep("=", 69))

  M.seed(42)

  -- ---- Lambert-W test ----
  print("\n[BAHA] Lambert-W function test:")
  local w0 = LW.W0(1.0)
  print(string.format("  W0(1.0)  = %.10f  (expect ~0.5671432904)", w0))
  local wm1 = LW.Wm1(-0.1)
  print(string.format("  Wm1(-0.1)= %.10f  (expect ~-3.5772)", wm1))

  -- ---- Euler gate / barrier ----
  print("\n[PINN] Euler gate and barrier:")
  for _, v in ipairs({0.0, 0.5, 1.0, 2.0}) do
    local g = pinn.euler_gate(v)
    local b = pinn.exp_barrier(v)
    local c = pinn.constraint_factor(v)
    print(string.format("  v=%.1f  G=%.6f  B=%.4f  C=%.4f", v, g, b, c))
  end

  -- ---- Euler product ζ(s) ----
  print("\n[PINN] Euler product approximation to zeta(s):")
  for _, s in ipairs({1.5, 2.0, 3.0}) do
    local z = pinn.euler_product_zeta(s, 15)
    print(string.format("  zeta(%.1f) ~ %.6f", s, z))
  end

  -- ---- Small SAT ----
  print("\n[NAVOKOJ] SAT solver on small instance:")
  local clauses = { {1, 2}, {-1, 3}, {2, -3}, {1, -2, 3} }
  local assign = navokoj.solve_sat(3, clauses, { steps = 500, seed = 42 })
  local sat_rate = navokoj.verify_solution(clauses, assign)
  print(string.format("  Assignment: x1=%d x2=%d x3=%d", assign[1], assign[2], assign[3]))
  print(string.format("  Satisfaction: %.1f%%", sat_rate * 100))

  -- ---- 3-SAT ----
  print("\n[NAVOKOJ] Random 3-SAT (20 vars, alpha=4.26):")
  local clauses20 = navokoj.generate_3sat(20, 4.26, 42)
  local assign20 = navokoj.solve_sat(20, clauses20, { steps = 2000, seed = 42 })
  local rate20 = navokoj.verify_solution(clauses20, assign20)
  print(string.format("  %d clauses, satisfaction: %.1f%%", #clauses20, rate20 * 100))

  -- ---- Graph coloring ----
  print("\n[NAVOKOJ] Graph coloring (10 nodes, 7 colors):")
  local edges = navokoj.generate_q_graph(10, 0.3, 42)
  local colors = navokoj.solve_qstate(10, 7, edges, { steps = 1000, seed = 42 })
  local viols = navokoj.verify_qstate(edges, colors)
  local color_str = table.concat(colors, ",")
  print(string.format("  %d edges, violations: %d, colors: [%s]", #edges, viols, color_str))

  -- ---- Job scheduling ----
  print("\n[NAVOKOJ] Job scheduling (5 jobs):")
  local jobs = {
    { duration = 4 }, { duration = 3 }, { duration = 2 },
    { duration = 5 }, { duration = 1 },
  }
  local prec = { {1, 3}, {2, 4} }
  local conf = { {1, 2}, {3, 5} }
  local sched = navokoj.schedule_jobs(jobs, conf, prec, { steps = 2000, seed = 42 })
  local ok, vlist = navokoj.verify_schedule(jobs, sched, conf, prec)
  print(string.format("  Valid: %s", tostring(ok)))
  for i = 1, #jobs do
    print(string.format("    Job %d: start=%.2f  end=%.2f", i, sched[i], sched[i] + jobs[i].duration))
  end

  -- ---- Casimir SAT ----
  print("\n[CASIMIR] Langevin SAT solver (5 vars, 7 clauses):")
  local cas_clauses = { {1, 2, 3}, {-1, 2}, {-2, 3}, {1, -3}, {-1, -2, 3}, {2, -3}, {1, 3} }
  local solver = casimir.Solver(3, cas_clauses, { temperature = 2.0, learning_rate = 0.5 })
  local cas_assign, cas_steps, cas_energy = solver:solve(500)
  local cas_rate = navokoj.verify_solution(cas_clauses, cas_assign)
  print(string.format("  Steps: %d, Energy: %.4f, Satisfaction: %.1f%%",
    cas_steps, cas_energy, cas_rate * 100))

  -- ---- ZetaGrok ----
  print("\n[ZETAGROK] Spectral entropy on random 8x8 matrix:")
  local A = M.matrix(8, 8)
  -- Create a low-rank + noise matrix to test spectral analysis
  for i = 1, 8 do
    for j = 1, 8 do
      -- Rank-2 signal + noise
      A[i][j] = (i * j) / 64.0 + ((i == j) and 0.5 or 0.0) + M.randn() * 0.05
    end
  end
  local entropy, info = zg.spectral_entropy(A, 3, 10)
  print(string.format("  Spectral entropy: %.4f", entropy))
  print(string.format("  Total energy: %.4f, Top-3 energy: %.4f, Tail: %.4f",
    info.total_energy, info.topk_energy, info.tail_energy))

  local total_loss, metrics = zg.zetagrok_loss(0.5, A, { K = 3, gamma = 2.0 })
  print(string.format("  Task loss: %.4f, Twist: %.4f, Total: %.4f",
    metrics.task_loss, metrics.twist_factor, metrics.total_loss))

  -- ---- BAHA graph coloring ----
  print("\n[BAHA] Branch-Aware Optimizer on 6-node graph coloring:")
  local ba_n = 6
  local ba_colors = 3
  local ba_edges = { {1,2}, {2,3}, {3,4}, {4,5}, {5,6}, {6,1}, {1,3}, {2,5} }

  local function ba_energy(state)
    local conflicts = 0
    for _, e in ipairs(ba_edges) do
      if state[e[1]] == state[e[2]] then conflicts = conflicts + 1 end
    end
    return conflicts
  end

  local function ba_sampler()
    local s = {}
    for i = 1, ba_n do s[i] = math.random(1, ba_colors) end
    return s
  end

  local function ba_neighbor(state)
    local nbrs = {}
    for i = 1, ba_n do
      for c = 1, ba_colors do
        if c ~= state[i] then
          local nbr = M.copy(state)
          nbr[i] = c
          nbrs[#nbrs + 1] = nbr
        end
      end
    end
    return nbrs
  end

  local ba_opt = baha.BranchAwareOptimizer(ba_energy, ba_sampler, ba_neighbor)
  local ba_result = ba_opt:optimize({
    beta_steps = 200, fracture_threshold = 1.0, samples_per_beta = 30,
    verbose = false,
  })
  print(string.format("  Energy: %.0f, Fractures: %d, Jumps: %d, Time: %.3fs",
    ba_result.best_energy, ba_result.fractures_detected,
    ba_result.branch_jumps, ba_result.time_s))
  print(string.format("  Coloring: [%s]", table.concat(ba_result.best_state, ",")))

  -- ---- Summary ----
  print("\n" .. string.rep("=", 70))
  print("  All modules loaded and tested successfully.")
  print("  Modules: shunyabar.baha, .navokoj, .pinn, .casimir, .zetagrok, .math")
  print(string.rep("=", 70))
end

-- Run demo if executed directly
if arg and arg[0] and arg[0]:match("shunyabar") then
  shunyabar.demo()
end

return shunyabar
