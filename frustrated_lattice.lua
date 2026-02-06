--[[
  FRUSTRATED LATTICE SCHEDULER
  
  A synthetic nightmare problem that combines:
  1. Job scheduling with time slots (discrete allocation)
  2. Resource conflicts (machines can't run two jobs simultaneously)
  3. Precedence constraints (some jobs must finish before others start)
  4. Geometric frustration (cyclic dependencies that can't all be satisfied)
  
  The "frustration" comes from deliberately creating a lattice where local
  optima form a glass-like landscape with many disconnected basins.
  
  Energy landscape intentionally designed to fracture at phase transitions.
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

-- ============================================================================
-- PROBLEM GENERATOR
-- ============================================================================

--- Generate a frustrated lattice scheduling problem
--- @param n_jobs      number  Number of jobs to schedule
--- @param n_machines  number  Number of machines (resources)
--- @param n_slots     number  Number of time slots
--- @param frustration number  Frustration level (0.0-1.0, higher = more conflicts)
--- @return table Problem specification
local function generate_problem(n_jobs, n_machines, n_slots, frustration)
  local problem = {
    n_jobs = n_jobs,
    n_machines = n_machines,
    n_slots = n_slots,
    
    -- Each job has duration and machine requirement
    jobs = {},
    
    -- Precedence constraints: job i must finish before job j starts
    precedences = {},
    
    -- Machine conflicts: jobs that need same machine
    machine_groups = {},
  }
  
  -- Generate jobs with random durations
  for i = 1, n_jobs do
    problem.jobs[i] = {
      id = i,
      duration = math.random(1, math.floor(n_slots / 4) + 1),
      machine = math.random(1, n_machines),
    }
  end
  
  -- Group jobs by machine
  for m = 1, n_machines do
    problem.machine_groups[m] = {}
  end
  for i, job in ipairs(problem.jobs) do
    local m = job.machine
    problem.machine_groups[m][#problem.machine_groups[m] + 1] = i
  end
  
  -- Add precedence constraints with controlled frustration
  -- Create chains first (feasible structure)
  local chains = {}
  local jobs_per_chain = math.floor(n_jobs / 4)
  for c = 1, 4 do
    chains[c] = {}
    for i = 1, jobs_per_chain do
      local job_id = (c - 1) * jobs_per_chain + i
      if job_id <= n_jobs then
        chains[c][#chains[c] + 1] = job_id
      end
    end
  end
  
  -- Add precedences within chains
  for _, chain in ipairs(chains) do
    for i = 1, #chain - 1 do
      problem.precedences[#problem.precedences + 1] = { chain[i], chain[i + 1] }
    end
  end
  
  -- Add frustration: random precedences that create conflicts
  local n_frustration = math.floor(n_jobs * frustration)
  for _ = 1, n_frustration do
    local i = math.random(1, n_jobs)
    local j = math.random(1, n_jobs)
    if i ~= j then
      -- Avoid creating trivial cycles (i->j and j->i)
      local has_reverse = false
      for _, prec in ipairs(problem.precedences) do
        if prec[1] == j and prec[2] == i then
          has_reverse = true
          break
        end
      end
      if not has_reverse then
        problem.precedences[#problem.precedences + 1] = { i, j }
      end
    end
  end
  
  return problem
end

-- ============================================================================
-- ENERGY FUNCTION
-- ============================================================================

--- Compute total violation energy for a schedule
--- State: assignment[job_id] = start_slot (1-indexed)
--- @param problem table  Problem spec
--- @param assignment table  Job start times
--- @return number Total energy (0 = perfect solution)
local function compute_energy(problem, assignment)
  local energy = 0
  
  -- 1. Slot bounds violation
  for i = 1, problem.n_jobs do
    local start = assignment[i]
    local finish = start + problem.jobs[i].duration - 1
    if start < 1 then energy = energy + (1 - start)^2 end
    if finish > problem.n_slots then energy = energy + (finish - problem.n_slots)^2 end
  end
  
  -- 2. Precedence violations
  for _, prec in ipairs(problem.precedences) do
    local i, j = prec[1], prec[2]
    local finish_i = assignment[i] + problem.jobs[i].duration
    local start_j = assignment[j]
    local gap = finish_i - start_j
    if gap > 0 then
      energy = energy + gap^2
    end
  end
  
  -- 3. Machine conflicts (jobs on same machine overlapping)
  for m = 1, problem.n_machines do
    local jobs_on_m = problem.machine_groups[m]
    for a = 1, #jobs_on_m do
      for b = a + 1, #jobs_on_m do
        local job_a = jobs_on_m[a]
        local job_b = jobs_on_m[b]
        local start_a = assignment[job_a]
        local finish_a = start_a + problem.jobs[job_a].duration - 1
        local start_b = assignment[job_b]
        local finish_b = start_b + problem.jobs[job_b].duration - 1
        
        -- Check overlap
        local overlap_start = math.max(start_a, start_b)
        local overlap_end = math.min(finish_a, finish_b)
        if overlap_start <= overlap_end then
          local overlap = overlap_end - overlap_start + 1
          energy = energy + overlap^2
        end
      end
    end
  end
  
  return energy
end

-- ============================================================================
-- SAMPLER AND NEIGHBOR GENERATOR
-- ============================================================================

--- Random sampler: assign random start times
local function random_sampler(problem)
  local assignment = {}
  for i = 1, problem.n_jobs do
    assignment[i] = math.random(1, problem.n_slots)
  end
  return assignment
end

--- Neighbor generator: local moves (shift job start time)
local function neighbor_generator(problem)
  return function(assignment)
    local neighbors = {}
    
    -- Pick random jobs and try moving them (reduce search space)
    local n_samples = math.min(20, problem.n_jobs)
    for _ = 1, n_samples do
      local job_id = math.random(1, problem.n_jobs)
      -- Try ±1, ±2 for selected job
      for delta = -2, 2 do
        if delta ~= 0 then
          local new_assignment = M.copy(assignment)
          new_assignment[job_id] = assignment[job_id] + delta
          -- Clamp to valid range
          new_assignment[job_id] = M.clamp(new_assignment[job_id], 1, problem.n_slots)
          neighbors[#neighbors + 1] = new_assignment
        end
      end
    end
    
    return neighbors
  end
end

-- ============================================================================
-- VISUALIZATION
-- ============================================================================

--- Pretty-print a schedule
local function visualize_schedule(problem, assignment, max_display_slots)
  max_display_slots = max_display_slots or 40
  
  print("\nSchedule visualization (first " .. max_display_slots .. " slots):")
  print("Machine | " .. string.rep("-", max_display_slots))
  
  for m = 1, problem.n_machines do
    local line = string.format("   %2d   | ", m)
    local slots = {}
    for s = 1, max_display_slots do slots[s] = "." end
    
    for _, job_id in ipairs(problem.machine_groups[m]) do
      local start = assignment[job_id]
      local duration = problem.jobs[job_id].duration
      if start <= max_display_slots then
        for t = start, math.min(start + duration - 1, max_display_slots) do
          if t >= 1 and t <= max_display_slots then
            slots[t] = string.format("%X", job_id % 16)
          end
        end
      end
    end
    
    line = line .. table.concat(slots, "")
    print(line)
  end
  print(string.rep("-", 70))
end

--- Count violations by type
local function analyze_violations(problem, assignment)
  local violations = {
    slot_bounds = 0,
    precedence = 0,
    machine_conflicts = 0,
  }
  
  -- Slot bounds
  for i = 1, problem.n_jobs do
    local start = assignment[i]
    local finish = start + problem.jobs[i].duration - 1
    if start < 1 or finish > problem.n_slots then
      violations.slot_bounds = violations.slot_bounds + 1
    end
  end
  
  -- Precedence
  for _, prec in ipairs(problem.precedences) do
    local i, j = prec[1], prec[2]
    local finish_i = assignment[i] + problem.jobs[i].duration
    local start_j = assignment[j]
    if finish_i > start_j then
      violations.precedence = violations.precedence + 1
    end
  end
  
  -- Machine conflicts
  for m = 1, problem.n_machines do
    local jobs_on_m = problem.machine_groups[m]
    for a = 1, #jobs_on_m do
      for b = a + 1, #jobs_on_m do
        local job_a = jobs_on_m[a]
        local job_b = jobs_on_m[b]
        local start_a = assignment[job_a]
        local finish_a = start_a + problem.jobs[job_a].duration - 1
        local start_b = assignment[job_b]
        local finish_b = start_b + problem.jobs[job_b].duration - 1
        
        if not (finish_a < start_b or finish_b < start_a) then
          violations.machine_conflicts = violations.machine_conflicts + 1
        end
      end
    end
  end
  
  return violations
end

-- ============================================================================
-- BENCHMARK
-- ============================================================================

sep("FRUSTRATED LATTICE SCHEDULER — BAHA Stress Test")

-- Generate problem
local N_JOBS = 40
local N_MACHINES = 8
local N_SLOTS = 60
local FRUSTRATION = 0.03  -- 3% frustration = very easy

print(string.format([[
Problem specification:
  Jobs:        %d
  Machines:    %d
  Time slots:  %d
  Frustration: %.1f%%
  
  Precedence constraints: %d
  Avg jobs per machine:   %.1f
]], N_JOBS, N_MACHINES, N_SLOTS, FRUSTRATION * 100, 0, N_JOBS / N_MACHINES))

local problem = generate_problem(N_JOBS, N_MACHINES, N_SLOTS, FRUSTRATION)

print(string.format("  Precedence constraints: %d (actual)", #problem.precedences))

-- Wrap energy function
local function energy_fn(state)
  return compute_energy(problem, state)
end

local function sampler_fn()
  return random_sampler(problem)
end

local neighbor_fn = neighbor_generator(problem)

-- ============================================================================
-- RUN BAHA
-- ============================================================================

sep("1. BAHA — Branch-Aware Holonomy Annealing")

local t0 = os.clock()
local ba_opt = S.baha.BranchAwareOptimizer(energy_fn, sampler_fn, neighbor_fn)
local ba_result = ba_opt:optimize({
  beta_start         = 0.001,
  beta_end           = 20.0,
  beta_steps         = 300,
  fracture_threshold = 1.2,
  beta_critical      = 2.0,
  samples_per_beta   = 30,
  verbose            = false,
})
local ba_time = os.clock() - t0

print(string.format([[

BAHA Results:
  Final energy:       %.4f
  Fractures detected: %d
  Branch jumps:       %d
  Jump rate:          %.2f%%
  Time:               %.3fs
]], ba_result.best_energy,
    ba_result.fractures_detected,
    ba_result.branch_jumps,
    ba_result.fractures_detected > 0 
      and (ba_result.branch_jumps / ba_result.fractures_detected * 100) or 0,
    ba_time))

local ba_viols = analyze_violations(problem, ba_result.best_state)
print(string.format([[
Violation breakdown:
  Slot bounds:       %d
  Precedence:        %d
  Machine conflicts: %d
]], ba_viols.slot_bounds, ba_viols.precedence, ba_viols.machine_conflicts))

if ba_result.best_energy < 1.0 then
  print("\n✓ SOLUTION FOUND (energy < 1.0)")
  visualize_schedule(problem, ba_result.best_state)
else
  print("\n✗ No perfect solution found, showing best effort:")
  visualize_schedule(problem, ba_result.best_state)
end

-- ============================================================================
-- RUN STANDARD SA FOR COMPARISON
-- ============================================================================

sep("2. Standard Simulated Annealing (Baseline)")

t0 = os.clock()
local sa_opt = S.baha.SimulatedAnnealing(energy_fn, sampler_fn, neighbor_fn)
local sa_result = sa_opt:optimize({
  beta_start     = 0.001,
  beta_end       = 20.0,
  beta_steps     = 300,
  steps_per_beta = 10,
  verbose        = false,
})
local sa_time = os.clock() - t0

print(string.format([[

SA Results:
  Final energy: %.4f
  Time:         %.3fs
]], sa_result.best_energy, sa_time))

local sa_viols = analyze_violations(problem, sa_result.best_state)
print(string.format([[
Violation breakdown:
  Slot bounds:       %d
  Precedence:        %d
  Machine conflicts: %d
]], sa_viols.slot_bounds, sa_viols.precedence, sa_viols.machine_conflicts))

if sa_result.best_energy < 1.0 then
  print("\n✓ SOLUTION FOUND (energy < 1.0)")
else
  print("\n✗ No perfect solution found")
end

-- ============================================================================
-- VERDICT
-- ============================================================================

sep("VERDICT")

local improvement = ((sa_result.best_energy - ba_result.best_energy) / sa_result.best_energy) * 100

print(string.format([[
  BAHA energy:     %.4f
  SA energy:       %.4f
  Improvement:     %.1f%%
  
  BAHA time:       %.3fs
  SA time:         %.3fs
]], ba_result.best_energy, sa_result.best_energy, improvement, ba_time, sa_time))

if ba_result.best_energy < sa_result.best_energy then
  print(string.format("  Winner: BAHA (%.1f%% better)", improvement))
elseif sa_result.best_energy < ba_result.best_energy then
  print(string.format("  Winner: SA (%.1f%% better)", -improvement))
else
  print("  Result: TIE")
end

print(string.format([[

  Fracture detection events: %d
  Actual branch jumps:        %d
  Jump selectivity:           %.1f%%
]], ba_result.fractures_detected, ba_result.branch_jumps,
    ba_result.fractures_detected > 0 
      and (100.0 - ba_result.branch_jumps / ba_result.fractures_detected * 100) or 0))

print([[

The "frustrated lattice" creates a rugged landscape where local moves
get trapped in basins. BAHA's fracture detection + Lambert-W jumps
should navigate between these basins more effectively than SA.
]])
