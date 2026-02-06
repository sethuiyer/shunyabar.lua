-- Unit tests for Casimir solver
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"

local framework = dofile(script_path .. "test_framework.lua")
local casimir = dofile(script_path .. "../src/casimir.lua")

local suite = framework.suite("Casimir Solver Unit Tests")

-- Test 1: Simple satisfiable instance
framework.test("Simple 2-clause SAT", function()
  local clauses = {
    {1, 2},      -- x1 OR x2
    {-1, 2}      -- NOT x1 OR x2
  }
  local solver = casimir.Solver(2, clauses, {temperature = 1.0, learning_rate = 0.3})
  local assignment, steps, energy = solver:solve(500)
  
  framework.assert.not_nil(assignment, "Should return assignment")
  framework.assert.equals(#assignment, 2, "Assignment should have 2 variables")
  
  local satisfaction = casimir.verify_solution(clauses, assignment)
  framework.assert.greater_or_equal(satisfaction, 50.0, "Should satisfy at least 50% of clauses")
end)

-- Test 2: Energy calculation
framework.test("Energy decreases over time", function()
  local clauses = {
    {1, 2, 3},
    {-1, 2, -3},
    {1, -2, 3}
  }
  local solver = casimir.Solver(3, clauses)
  
  local initial_energy = solver:total_energy()
  
  -- Run a few steps
  for i = 1, 50 do
    solver:langevin_step()
  end
  
  local final_energy = solver:total_energy()
  
  framework.assert.less_than(final_energy, initial_energy, 
    "Energy should decrease after optimization steps")
end)

-- Test 3: Convergence detection
framework.test("Convergence detection works", function()
  local clauses = {
    {1},  -- x1 must be true
    {2}   -- x2 must be true
  }
  local solver = casimir.Solver(2, clauses, {temperature = 0.5, learning_rate = 0.5})
  
  -- Should converge quickly on this trivial problem
  local assignment, steps, energy = solver:solve(1000)
  
  framework.assert.less_or_equal(steps, 1000, "Should complete within max steps")
  framework.assert.less_than(energy, 0.1, "Energy should be near zero")
  
  -- Verify solution
  local satisfaction = casimir.verify_solution(clauses, assignment)
  framework.assert.equals(satisfaction, 100.0, "Should fully satisfy trivial problem")
end)

-- Test 4: Fractional satisfaction calculation
framework.test("Fractional satisfaction is correct", function()
  local clauses = {{1, 2, 3}}
  local solver = casimir.Solver(3, clauses)
  
  -- Set specific state
  solver.x[1] = 0.1  -- Low probability
  solver.x[2] = 0.1  -- Low probability
  solver.x[3] = 0.1  -- Low probability
  
  local sat = solver:fractional_satisfaction(clauses[1])
  
  -- s_c = 1 - (1-0.1)^3 = 1 - 0.729 = 0.271
  framework.assert.in_range(sat, 0.2, 0.3, "Fractional satisfaction should be ~0.27")
end)

-- Test 5: Gradient computation
framework.test("Gradients are computed", function()
  local clauses = {
    {1, 2},
    {-1, 3}
  }
  local solver = casimir.Solver(3, clauses)
  
  local grads = solver:compute_gradients()
  
  framework.assert.not_nil(grads, "Gradients should be computed")
  framework.assert.equals(#grads, 3, "Should have gradient for each variable")
  
  -- Gradients should not all be zero (unless at optimum)
  local sum = 0
  for i = 1, #grads do
    sum = sum + math.abs(grads[i])
  end
  framework.assert.greater_than(sum, 0, "At least some gradients should be non-zero")
end)

-- Test 6: Annealing schedule
framework.test("Temperature and beta anneal correctly", function()
  local clauses = {{1, 2, 3}}
  local solver = casimir.Solver(3, clauses, {temperature = 2.0})
  
  local initial_temp = solver.temperature
  local initial_beta = solver.beta
  
  -- Run steps
  for i = 1, 100 do
    solver:langevin_step()
  end
  
  framework.assert.less_than(solver.temperature, initial_temp, 
    "Temperature should decrease")
  framework.assert.greater_than(solver.beta, initial_beta, 
    "Beta should increase")
end)

-- Test 7: Empty problem
framework.test("Handles empty problem", function()
  local clauses = {}
  local solver = casimir.Solver(0, clauses)
  
  local assignment, steps, energy = solver:solve(10)
  
  framework.assert.not_nil(assignment, "Should handle empty problem")
  framework.assert.equals(energy, 0.0, "Energy should be zero for empty problem")
end)

-- Test 8: Verification function
framework.test("Verification function is accurate", function()
  local clauses = {
    {1, 2},
    {-1, 3},
    {2, -3}
  }
  
  -- Assignment that satisfies 2/3 clauses
  -- Clause 1: {1,2} -> x1=T OR x2=T = T (satisfied)
  -- Clause 2: {-1,3} -> x1=F OR x3=T = F (NOT satisfied)
  -- Clause 3: {2,-3} -> x2=T OR x3=F = T (satisfied)
  local assignment1 = {1, 1, 0}  -- x1=T, x2=T, x3=F
  local sat1 = casimir.verify_solution(clauses, assignment1)
  framework.assert.in_range(sat1, 60, 70, "Should satisfy ~66% of clauses")
  
  -- Assignment that satisfies 2/3 clauses
  -- Clause 1: {1,2} -> x1=F OR x2=F = F (NOT satisfied)
  -- Clause 2: {-1,3} -> x1=T OR x3=F = T (satisfied)
  -- Clause 3: {2,-3} -> x2=F OR x3=T = T (satisfied)
  local assignment2 = {0, 0, 0}  -- x1=F, x2=F, x3=F
  local sat2 = casimir.verify_solution(clauses, assignment2)
  framework.assert.in_range(sat2, 60, 70, "Should satisfy ~66% of clauses")
end)

-- Test 9: Random 3-SAT generation
framework.test("Random 3-SAT generation", function()
  math.randomseed(42)
  local clauses = casimir.generate_test_clauses(10, 20)
  
  framework.assert.equals(#clauses, 20, "Should generate 20 clauses")
  
  for i, clause in ipairs(clauses) do
    framework.assert.equals(#clause, 3, "Each clause should have 3 literals")
    
    for j, lit in ipairs(clause) do
      local var = math.abs(lit)
      framework.assert.greater_than(var, 0, "Variable should be positive")
      framework.assert.less_or_equal(var, 10, "Variable should be <= num_vars")
    end
  end
end)

-- Test 10: Adjacency matrix construction
framework.test("Adjacency matrix construction", function()
  local clauses = {
    {1, 2, 3},
    {2, 3, 4}
  }
  local solver = casimir.Solver(4, clauses)
  
  local adj = solver:build_adjacency()
  
  framework.assert.not_nil(adj, "Adjacency matrix should be built")
  framework.assert.equals(#adj, 4, "Should have 4 rows")
  
  -- Check symmetry
  for i = 1, 4 do
    for j = 1, 4 do
      framework.assert.equals(adj[i][j], adj[j][i], 
        string.format("Matrix should be symmetric at [%d][%d]", i, j))
    end
  end
  
  -- Variables in same clause should be connected
  framework.assert.equals(adj[1][2], 1.0, "x1 and x2 should be connected")
  framework.assert.equals(adj[2][3], 1.0, "x2 and x3 should be connected")
end)

-- Run the suite
if not pcall(debug.getlocal, 4, 1) then
  -- Only run if executed directly (not required as module)
  framework.run_suite("Casimir Solver Unit Tests")
end

return suite
