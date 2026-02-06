-- Benchmark: Casimir vs Walksat vs Hybrid
-- Hard 3-SAT at critical density

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"
casimir = dofile(script_path .. "../src/casimir.lua")
walksat = dofile(script_path .. "../src/walksat.lua")

local hybrid = {}

function hybrid.solve(num_vars, clauses, opts)
  opts = opts or {}

  local cas_solver = casimir.Solver(num_vars, clauses, opts.casimir_opts or {})
  local t0 = os.clock()
  local assignment, cas_steps, cas_energy = cas_solver:solve(opts.max_casimir_steps or 200)
  local cas_time = os.clock() - t0
  local cas_sat = casimir.verify_solution(clauses, assignment)

  if cas_sat >= 99.9 then
    return assignment, cas_steps, cas_sat, cas_time, "CASIMIR"
  end

  local walk_solver = walksat.Solver(num_vars, clauses, opts.walksat_opts or {})
  t0 = os.clock()
  local refined, walk_flips, status = walk_solver:run(assignment)
  local walk_time = os.clock() - t0
  local final_sat = walksat.verify(clauses, refined)

  return refined, cas_steps + walk_flips, final_sat, cas_time + walk_time,
         (final_sat > cas_sat and "HYBRID" or "WALKSAT")
end

print("=" .. string.rep("=", 75))
print("BENCHMARK: Casimir vs Walksat vs Hybrid")
print("=" .. string.rep("=", 75))

-- Hard problem: 50 vars, 213 clauses (4.26 * 50), critical density
math.randomseed(123)
local clauses = {}
for i = 1, 213 do
  local c = {}
  for j = 1, 3 do c[#c+1] = (math.random()>0.5 and 1 or -1) * math.random(1, 50) end
  clauses[#clauses+1] = c
end

print("\nProblem: 50 variables, 213 clauses (critical density α = 4.26)")
print(string.rep("-", 75))

-- Casimir only
local cas_solver = casimir.Solver(50, clauses, {temperature=2.0, learning_rate=0.5})
local t0 = os.clock()
local ca, cs, ce = cas_solver:solve(500)
local cas_t = os.clock() - t0
local cas_sat = casimir.verify_solution(clauses, ca)
print(string.format("%-10s %6d steps  %7.2f%%  %7.3fs", "CASIMIR", cs, cas_sat, cas_t))

-- Walksat only (fresh random start)
local walk_solver = walksat.Solver(50, clauses, {noise=0.5, max_tries=10, max_flips=10000})
t0 = os.clock()
local wa, wf, ws = walk_solver:solve()
local walk_t = os.clock() - t0
local walk_sat = walksat.verify(clauses, wa) * 100
print(string.format("%-10s %6d flips  %7.2f%%  %7.3fs", "WALKSAT", wf, walk_sat, walk_t))

-- Hybrid
t0 = os.clock()
local ha, hs, hybrid_sat, hybrid_t, method = hybrid.solve(50, clauses, {
  max_casimir_steps = 500,
  walksat_opts = {noise=0.5, max_tries=10, max_flips=10000}
})
print(string.format("%-10s %6d ops    %7.2f%%  %7.3fs  (%s)", "HYBRID", hs, hybrid_sat * 100, hybrid_t, method))

print(string.rep("-", 75))
print("\nKey insight: Casimir's continuous relaxation provides a guided starting point")
print("for Walksat, avoiding random walks in the discrete space.")
print(string.rep("=", 75))
