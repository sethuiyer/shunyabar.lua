-- HYBRID SOLVER: Casimir + Walksat Refinement
-- First: Casimir Langevin dynamics for continuous relaxation
-- Then: Walksat local search for discrete refinement
-- Author: Sethu Iyer | License: Apache 2.0

local S = dofile(debug.getinfo(1).source:match("@?(.*/)") .. "shunyabar.lua")
local walksat = dofile(debug.getinfo(1).source:match("@?(.*/)") .. "walksat.lua")

local hybrid = {}
-- Expose submodules for convenience
local casimir = dofile(debug.getinfo(1).source:match("@?(.*/)") .. "casimir.lua")

--- Hybrid solve: Casimir first, Walksat refinement if needed
--- @param num_vars number
--- @param clauses {{int,...},...}
--- @param opts table {casimir_opts, walksat_opts, verbose}
--- @return assignment, steps, status
function hybrid.solve(num_vars, clauses, opts)
  opts = opts or {}
  local verbose = opts.verbose ~= false

  if verbose then
    print("=" .. string.rep("=", 70))
    print("HYBRID SOLVER: Casimir + Walksat Refinement")
    print("=" .. string.rep("=", 70))
    print("Problem: " .. num_vars .. " variables, " .. #clauses .. " clauses")
    print("Target: " .. (#clauses == 0 and 0 or 100) .. "% satisfaction")
    print("-" .. string.rep("-", 70))
  end

  -- Phase 1: Casimir Langevin dynamics
  if verbose then
    print("[PHASE 1] Casimir Langevin dynamics...")
  end

  local cas_start = os.clock()
  local cas_solver = casimir.Solver(num_vars, clauses, opts.casimir_opts or {})
  local assignment, cas_steps, cas_energy = cas_solver:solve(opts.max_casimir_steps or 2000)
  local cas_time = os.clock() - cas_start

  local cas_satisfaction = casimir.verify_solution(clauses, assignment)
  local cas_converged = cas_solver:is_converged()

  if verbose then
    print("  Steps: " .. cas_steps)
    print("  Energy: " .. string.format("%.6f", cas_energy))
    print("  Satisfaction: " .. string.format("%.2f", cas_satisfaction) .. "%")
    print("  Converged: " .. (cas_converged and "YES" or "NO"))
    print("  Time: " .. string.format("%.3f", cas_time) .. "s")
  end

  -- Check if Casimir fully solved it OR if problem is trivially SAT (no clauses)
  if cas_satisfaction >= 99.9 or #clauses == 0 then
    if verbose then
      print("[RESULT] Casimir solved it! (" .. string.format("%.2f", cas_satisfaction) .. "%)")
    end
    return assignment, cas_steps, "CASIMIR_SOLVED"
  end

  -- Phase 2: Walksat refinement from Casimir's partial assignment
  if verbose then
    print("[PHASE 2] Walksat refinement from Casimir assignment...")
  end

  local walk_start = os.clock()
  local walk_solver = walksat.Solver(num_vars, clauses, opts.walksat_opts or {})
  local refined_assignment, walk_flips, walk_status = walk_solver:run(assignment)
  local walk_time = os.clock() - walk_start

  local final_satisfaction = walksat.verify(clauses, refined_assignment) * 100.0

  if verbose then
    print("  Flips: " .. walk_flips)
    print("  Status: " .. walk_status)
    print("  Satisfaction: " .. string.format("%.2f", final_satisfaction) .. "%")
    print("  Time: " .. string.format("%.3f", walk_time) .. "s")
  end

  local total_steps = cas_steps + walk_flips
  local total_time = cas_time + walk_time

  if verbose then
    print("-" .. string.rep("-", 70))
    print("SUMMARY")
    print("  Total steps: " .. total_steps)
    print("  Total time: " .. string.format("%.3f", total_time) .. "s")
    print("  Casimir: " .. string.format("%.1f", cas_satisfaction) .. "% -> Walksat: " ..
          string.format("%.1f", final_satisfaction) .. "%")
    print("  Improvement: +" .. string.format("%.2f", final_satisfaction - cas_satisfaction) .. "%")
    print("=" .. string.rep("=", 70))
  end

  return refined_assignment, total_steps,
         (final_satisfaction >= 99.9 and "HYBRID_SOLVED" or
          final_satisfaction > cas_satisfaction and "IMPROVED" or "NO_IMPROVEMENT")
end

--- Run a benchmark comparison
--- @param problems {{num_vars, clauses, name},...}
--- @param opts table
function hybrid.benchmark(problems, opts)
  opts = opts or {}

  print("=" .. string.rep("=", 80))
  print("BENCHMARK: Casimir vs Walksat vs Hybrid")
  print("=" .. string.rep("=", 80))

  local results = {}

  for _, prob in ipairs(problems) do
    print("\n[PROBLEM] " .. prob.name)
    print("  Vars: " .. prob.num_vars .. ", Clauses: " .. #prob.clauses)

    -- Casimir only
    local cas_solver = casimir.Solver(prob.num_vars, prob.clauses, opts.casimir_opts or {})
    local t0 = os.clock()
    local cas_assign, cas_steps, cas_energy = cas_solver:solve(opts.max_casimir_steps or 2000)
    local cas_time = os.clock() - t0
    local cas_sat = casimir.verify_solution(prob.clauses, cas_assign)

    print("  Casimir: " .. string.format("%6.2f", cas_sat) .. "% satisfaction, " ..
          string.format("%6.3f", cas_time) .. "s, " .. cas_steps .. " steps")

    -- Walksat only (fresh random start)
    local walk_solver = walksat.Solver(prob.num_vars, prob.clauses, opts.walksat_opts or {})
    t0 = os.clock()
    local walk_assign, walk_flips, walk_status = walk_solver:solve()
    local walk_time = os.clock() - t0
    local walk_sat = walksat.verify(prob.clauses, walk_assign)

    print("  Walksat: " .. string.format("%6.2f", walk_sat) .. "% satisfaction, " ..
          string.format("%6.3f", walk_time) .. "s, " .. walk_flips .. " flips")

    -- Hybrid
    local hybrid_assign, hybrid_steps, hybrid_status = hybrid.solve(
      prob.num_vars, prob.clauses,
      { verbose = false, casimir_opts = opts.casimir_opts, walksat_opts = opts.walksat_opts }
    )
    local hybrid_sat = walksat.verify(prob.clauses, hybrid_assign)

    print("  Hybrid:  " .. string.format("%6.2f", hybrid_sat) .. "% satisfaction, " ..
          string.format("%6.2f", hybrid_steps) .. " steps")

    results[#results + 1] = {
      name = prob.name,
      casimir = { sat = cas_sat, time = cas_time },
      walksat = { sat = walk_sat, time = walk_time },
      hybrid = { sat = hybrid_sat, time = hybrid_steps }
    }
  end

  -- Summary table
  print("\n" .. "=" .. string.rep("=", 80))
  print("SUMMARY")
  print("=" .. string.rep("=", 80))
  print(string.format("%-25s %12s %12s %12s", "Problem", "Casimir", "Walksat", "Hybrid"))
  print(string.rep("-", 80))

  for _, r in ipairs(results) do
    print(string.format("%-25s %10.1f%% %10.1f%% %10.1f%%",
          r.name, r.casimir.sat, r.walksat.sat, r.hybrid.sat))
  end

  return results
end

--- Generate random 3-SAT problem
--- @param num_vars number
--- @param ratio number (clauses per variable, typically 4.26 for hard)
--- @return {num_vars, clauses, name}
function hybrid.generate_3sat(num_vars, ratio)
  local clauses = {}
  local num_clauses = math.floor(num_vars * ratio)
  for i = 1, num_clauses do
    local clause = {}
    for j = 1, 3 do
      local var = math.random(1, num_vars)
      clause[#clause + 1] = (math.random() > 0.5 and 1 or -1) * var
    end
    clauses[#clauses + 1] = clause
  end
  return {
    num_vars = num_vars,
    clauses = clauses,
    name = "3-SAT(" .. num_vars .. " vars, " .. #clauses .. " clauses)"
  }
end

return hybrid