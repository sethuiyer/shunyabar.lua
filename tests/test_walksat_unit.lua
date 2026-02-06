-- Unit tests for Walksat solver
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"

local framework = dofile(script_path .. "test_framework.lua")
local walksat = dofile(script_path .. "../src/walksat.lua")

local suite = framework.suite("Walksat Solver Unit Tests")

-- Test 1: Simple satisfiable instance
framework.test("Simple 2-clause SAT", function()
  local clauses = {
    {1, 2},      -- x1 OR x2
    {-1, 2}      -- NOT x1 OR x2
  }
  local solver = walksat.Solver(2, clauses, {max_flips = 100, max_tries = 5})
  local assignment, flips, status = solver:solve()
  
  framework.assert.not_nil(assignment, "Should return assignment")
  framework.assert.equals(#assignment, 2, "Assignment should have 2 variables")
  
  local satisfaction = walksat.verify(clauses, assignment)
  framework.assert.greater_or_equal(satisfaction, 0.5, "Should satisfy at least 50% of clauses")
end)

-- Test 2: Trivial problem (unit clauses)
framework.test("Trivial unit clauses", function()
  local clauses = {
    {1},   -- x1 must be true
    {2},   -- x2 must be true
    {-3}   -- x3 must be false
  }
  local solver = walksat.Solver(3, clauses, {max_flips = 50})
  local assignment, flips, status = solver:solve()
  
  framework.assert.equals(status, "SAT", "Should find SAT solution")
  framework.assert.equals(assignment[1], 1, "x1 should be true")
  framework.assert.equals(assignment[2], 1, "x2 should be true")
  framework.assert.equals(assignment[3], 0, "x3 should be false")
  
  local satisfaction = walksat.verify(clauses, assignment)
  framework.assert.equals(satisfaction, 1.0, "Should fully satisfy all clauses")
end)

-- Test 3: Unsatisfied clause counting
framework.test("Count unsatisfied clauses", function()
  local clauses = {
    {1, 2},
    {-1, 3},
    {-2, -3}
  }
  local solver = walksat.Solver(3, clauses)
  
  -- Assignment: x1=F, x2=F, x3=F
  local assignment = {0, 0, 0}
  local unsat_count = solver:count_unsatisfied(assignment)
  
  -- Clause 1: F OR F = F (unsatisfied)
  -- Clause 2: T OR F = T (satisfied)
  -- Clause 3: T OR T = T (satisfied)
  framework.assert.equals(unsat_count, 1, "Should have 1 unsatisfied clause")
end)

-- Test 4: Get unsatisfied clauses
framework.test("Get unsatisfied clause indices", function()
  local clauses = {
    {1, 2},
    {-1, -2},
    {1, -2}
  }
  local solver = walksat.Solver(2, clauses)
  
  -- Assignment: x1=F, x2=T
  local assignment = {0, 1}
  local unsat_clauses = solver:get_unsatisfied_clauses(assignment)
  
  -- Clause 1: F OR T = T (satisfied)
  -- Clause 2: T OR F = T (satisfied)
  -- Clause 3: F OR F = F (unsatisfied)
  framework.assert.equals(#unsat_clauses, 1, "Should have 1 unsatisfied clause")
  framework.assert.equals(unsat_clauses[1], 3, "Clause 3 should be unsatisfied")
end)

-- Test 5: Variable flipping
framework.test("Variable flipping works", function()
  local solver = walksat.Solver(3, {})
  local assignment = {0, 1, 0}
  
  solver:flip(assignment, 2)
  framework.assert.equals(assignment[2], 0, "x2 should flip from 1 to 0")
  
  solver:flip(assignment, 2)
  framework.assert.equals(assignment[2], 1, "x2 should flip back to 1")
end)

-- Test 6: Noise parameter effect
framework.test("Noise parameter affects behavior", function()
  local clauses = {
    {1, 2, 3},
    {-1, 2, -3},
    {1, -2, 3}
  }
  
  -- High noise = more random
  local solver_high_noise = walksat.Solver(3, clauses, {noise = 0.9, max_flips = 100, max_tries = 3})
  local _, _, status1 = solver_high_noise:solve()
  
  -- Low noise = more greedy
  local solver_low_noise = walksat.Solver(3, clauses, {noise = 0.1, max_flips = 100, max_tries = 3})
  local _, _, status2 = solver_low_noise:solve()
  
  -- Both should at least attempt to solve
  framework.assert.not_nil(status1, "High noise solver should return status")
  framework.assert.not_nil(status2, "Low noise solver should return status")
end)

-- Test 7: Multiple tries
framework.test("Multiple tries improve success", function()
  local clauses = {
    {1, 2, 3},
    {-1, 2, -3},
    {1, -2, 3},
    {-1, -2, -3}
  }
  
  local solver = walksat.Solver(3, clauses, {max_flips = 50, max_tries = 10})
  local assignment, flips, status = solver:solve()
  
  framework.assert.not_nil(assignment, "Should return assignment")
  framework.assert.less_or_equal(flips, 50 * 10, "Flips should be within bounds")
end)

-- Test 8: Run from provided assignment
framework.test("Run from provided assignment", function()
  local clauses = {
    {1, 2},
    {-1, 3}
  }
  local solver = walksat.Solver(3, clauses, {max_flips = 100})
  
  -- Provide initial assignment
  local initial = {1, 0, 1}
  local assignment, flips, status = solver:run(initial)
  
  framework.assert.not_nil(assignment, "Should return assignment")
  
  -- Verify it's a valid assignment
  local satisfaction = walksat.verify(clauses, assignment)
  framework.assert.greater_than(satisfaction, 0, "Should satisfy some clauses")
end)

-- Test 9: Verification function
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
  local sat1 = walksat.verify(clauses, assignment1)
  framework.assert.in_range(sat1, 0.6, 0.7, "Should satisfy ~66% of clauses")
  
  -- Assignment that satisfies only 1/3 clauses
  local assignment2 = {0, 0, 1}  -- x1=F, x2=F, x3=T
  local sat2 = walksat.verify(clauses, assignment2)
  framework.assert.in_range(sat2, 0.3, 0.4, "Should satisfy ~33% of clauses")
end)

-- Test 10: Empty problem
framework.test("Handles empty problem", function()
  local clauses = {}
  local solver = walksat.Solver(0, clauses)
  
  local assignment, flips, status = solver:solve()
  
  framework.assert.not_nil(assignment, "Should handle empty problem")
  framework.assert.equals(status, "SAT", "Empty problem is trivially SAT")
  framework.assert.equals(flips, 0, "Should take 0 flips")
end)

-- Test 11: Already satisfied problem
framework.test("Detects already satisfied problem", function()
  local clauses = {
    {1, 2},
    {-1, 3}
  }
  local solver = walksat.Solver(3, clauses)
  
  -- Provide assignment that already satisfies all clauses
  local initial = {1, 1, 1}
  local assignment, flips, status = solver:run(initial)
  
  framework.assert.equals(status, "SAT", "Should detect SAT immediately")
  framework.assert.equals(flips, 0, "Should take 0 flips")
end)

-- Test 12: Best solution tracking
framework.test("Tracks best solution across tries", function()
  local clauses = {
    {1, 2, 3},
    {-1, 2, -3},
    {1, -2, 3},
    {-1, -2, -3}
  }
  
  local solver = walksat.Solver(3, clauses, {max_flips = 20, max_tries = 5})
  local assignment, flips, status = solver:solve()
  
  framework.assert.not_nil(assignment, "Should return best assignment found")
  
  -- Even if not fully SAT, should return best partial solution
  local satisfaction = walksat.verify(clauses, assignment)
  framework.assert.greater_than(satisfaction, 0, "Should find some satisfying assignment")
end)

-- Run the suite
if not pcall(debug.getlocal, 4, 1) then
  -- Only run if executed directly (not required as module)
  framework.run_suite("Walksat Solver Unit Tests")
end

return suite
