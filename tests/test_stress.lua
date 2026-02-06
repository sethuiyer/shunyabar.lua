-- Stress tests for hybrid solver
-- Hard instances designed to challenge the solver
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"

local framework = dofile(script_path .. "test_framework.lua")
local hybrid = dofile(script_path .. "../src/hybrid.lua")
local walksat = dofile(script_path .. "../src/walksat.lua")

local suite = framework.suite("Stress Tests")

-- Test 1: Hard 3-SAT (N=100, critical ratio)
framework.test("Hard 3-SAT N=100", function()
  math.randomseed(12345)
  local n_vars = 100
  local n_clauses = math.floor(n_vars * 4.26)
  local clauses = {}
  
  for i = 1, n_clauses do
    local clause = {}
    for j = 1, 3 do
      clause[#clause + 1] = (math.random() > 0.5 and 1 or -1) * math.random(1, n_vars)
    end
    clauses[#clauses + 1] = clause
  end
  
  local assignment, steps, status = hybrid.solve(n_vars, clauses, {
    verbose = false,
    max_casimir_steps = 3000,
    walksat_opts = { max_flips = 50000, max_tries = 3 }
  })
  
  framework.assert.not_nil(assignment, "Should return assignment")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 80.0, 
    "Should achieve >80% satisfaction on hard 3-SAT")
end)

-- Test 2: Hard 3-SAT (N=200)
framework.test("Hard 3-SAT N=200", function()
  math.randomseed(54321)
  local n_vars = 200
  local n_clauses = math.floor(n_vars * 4.26)
  local clauses = {}
  
  for i = 1, n_clauses do
    local clause = {}
    for j = 1, 3 do
      clause[#clause + 1] = (math.random() > 0.5 and 1 or -1) * math.random(1, n_vars)
    end
    clauses[#clauses + 1] = clause
  end
  
  local assignment, steps, status = hybrid.solve(n_vars, clauses, {
    verbose = false,
    max_casimir_steps = 5000,
    walksat_opts = { max_flips = 100000, max_tries = 3 }
  })
  
  framework.assert.not_nil(assignment, "Should return assignment")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 70.0, 
    "Should achieve >70% satisfaction on very hard 3-SAT")
end)

-- Test 3: AI Escargot Sudoku
framework.test("AI Escargot Sudoku", function()
  local shunyabar = dofile(script_path .. "../src/shunyabar.lua")
  local ai_escargot = "800000000003600000070090200050007000000045700000100030001000068008500010090000400"
  local n_vars, clauses = shunyabar.navokoj.encode_sudoku(ai_escargot)
  
  local assignment, steps, status = hybrid.solve(n_vars, clauses, {
    verbose = false,
    max_casimir_steps = 5000,
    walksat_opts = { max_flips = 100000, max_tries = 5 }
  })
  
  framework.assert.not_nil(assignment, "Should return assignment")
  framework.assert.equals(n_vars, 729, "Sudoku should have 729 variables")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 95.0, 
    "Should achieve >95% satisfaction on AI Escargot")
end)

-- Test 4: N-Queens (N=8)
framework.test("8-Queens Problem", function()
  local shunyabar = dofile(script_path .. "../src/shunyabar.lua")
  local n_vars, clauses = shunyabar.navokoj.encode_n_queens(8)
  
  local assignment, steps, status = hybrid.solve(n_vars, clauses, {
    verbose = false,
    max_casimir_steps = 3000,
    walksat_opts = { max_flips = 50000, max_tries = 5 }
  })
  
  framework.assert.not_nil(assignment, "Should return assignment")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 90.0, 
    "Should achieve >90% satisfaction on 8-Queens")
end)

-- Test 5: N-Queens (N=12)
framework.test("12-Queens Problem", function()
  local shunyabar = dofile(script_path .. "../src/shunyabar.lua")
  local n_vars, clauses = shunyabar.navokoj.encode_n_queens(12)
  
  local assignment, steps, status = hybrid.solve(n_vars, clauses, {
    verbose = false,
    max_casimir_steps = 5000,
    walksat_opts = { max_flips = 100000, max_tries = 5 }
  })
  
  framework.assert.not_nil(assignment, "Should return assignment")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 85.0, 
    "Should achieve >85% satisfaction on 12-Queens")
end)

-- Test 6: Over-constrained 3-SAT
framework.test("Over-constrained 3-SAT (ratio=6.0)", function()
  math.randomseed(99999)
  local n_vars = 50
  local n_clauses = math.floor(n_vars * 6.0)  -- Much higher than critical
  local clauses = {}
  
  for i = 1, n_clauses do
    local clause = {}
    for j = 1, 3 do
      clause[#clause + 1] = (math.random() > 0.5 and 1 or -1) * math.random(1, n_vars)
    end
    clauses[#clauses + 1] = clause
  end
  
  local assignment, steps, status = hybrid.solve(n_vars, clauses, {
    verbose = false,
    max_casimir_steps = 3000,
    walksat_opts = { max_flips = 50000, max_tries = 3 }
  })
  
  framework.assert.not_nil(assignment, "Should return assignment")
  
  -- Over-constrained may not be fully satisfiable, but should still try
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 60.0, 
    "Should achieve >60% satisfaction on over-constrained problem")
end)

-- Test 7: Random UNSAT instance (contradictory clauses)
framework.test("UNSAT instance with contradictions", function()
  local clauses = {
    {1},      -- x1 must be true
    {-1},     -- x1 must be false (contradiction!)
    {2, 3},
    {-2, 3},
    {2, -3},
    {-2, -3}  -- x2 and x3 cannot both satisfy this with above
  }
  
  local assignment, steps, status = hybrid.solve(3, clauses, {
    verbose = false,
    max_casimir_steps = 1000,
    walksat_opts = { max_flips = 10000, max_tries = 3 }
  })
  
  framework.assert.not_nil(assignment, "Should return assignment even for UNSAT")
  
  -- Should not achieve 100% satisfaction
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.less_than(satisfaction, 100.0, 
    "Should not fully satisfy UNSAT instance")
  
  -- But should satisfy most clauses
  framework.assert.greater_than(satisfaction, 60.0, 
    "Should still satisfy majority of clauses")
end)

-- Test 8: Performance on multiple random instances
framework.test("Consistency across random instances", function()
  local successes = 0
  local total_satisfaction = 0
  local num_trials = 5
  
  for trial = 1, num_trials do
    math.randomseed(trial * 1000)
    local n_vars = 30
    local n_clauses = math.floor(n_vars * 4.26)
    local clauses = {}
    
    for i = 1, n_clauses do
      local clause = {}
      for j = 1, 3 do
        clause[#clause + 1] = (math.random() > 0.5 and 1 or -1) * math.random(1, n_vars)
      end
      clauses[#clauses + 1] = clause
    end
    
    local assignment, steps, status = hybrid.solve(n_vars, clauses, {
      verbose = false,
      max_casimir_steps = 2000,
      walksat_opts = { max_flips = 20000, max_tries = 3 }
    })
    
    local satisfaction = walksat.verify(clauses, assignment) * 100.0
    total_satisfaction = total_satisfaction + satisfaction
    
    if satisfaction >= 95.0 then
      successes = successes + 1
    end
  end
  
  local avg_satisfaction = total_satisfaction / num_trials
  framework.assert.greater_than(avg_satisfaction, 85.0, 
    "Average satisfaction should be >85% across trials")
  
  framework.assert.greater_or_equal(successes, 3, 
    "Should achieve >=95% satisfaction on at least 3/5 trials")
end)

-- Run the suite
if not pcall(debug.getlocal, 4, 1) then
  -- Only run if executed directly (not required as module)
  print("\n⚠️  WARNING: Stress tests may take several minutes to complete")
  framework.run_suite("Stress Tests")
end

return suite
