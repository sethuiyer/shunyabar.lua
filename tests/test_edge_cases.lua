-- Edge case tests for hybrid solver
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"

local framework = dofile(script_path .. "test_framework.lua")
local hybrid = dofile(script_path .. "../src/hybrid.lua")
local casimir = dofile(script_path .. "../src/casimir.lua")
local walksat = dofile(script_path .. "../src/walksat.lua")

local suite = framework.suite("Edge Case Tests")

-- Test 1: Empty problem
framework.test("Empty problem (0 vars, 0 clauses)", function()
  local assignment, steps, status = hybrid.solve(0, {}, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should handle empty problem")
  framework.assert.equals(status, "CASIMIR_SOLVED", "Empty problem should be trivially solved")
end)

-- Test 2: No clauses (trivially SAT)
framework.test("No clauses (trivially SAT)", function()
  local assignment, steps, status = hybrid.solve(5, {}, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should return assignment")
  framework.assert.equals(#assignment, 5, "Should have 5 variables")
  framework.assert.equals(status, "CASIMIR_SOLVED", "No clauses is trivially SAT")
end)

-- Test 3: Single variable, single clause
framework.test("Single variable, single clause", function()
  local clauses = {{1}}  -- x1 must be true
  local assignment, steps, status = hybrid.solve(1, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should return assignment")
  framework.assert.equals(assignment[1], 1, "x1 should be true")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.equals(satisfaction, 100.0, "Should fully satisfy")
end)

-- Test 4: Tautology (always SAT)
framework.test("Tautology clauses", function()
  local clauses = {
    {1, -1},   -- x1 OR NOT x1 (always true)
    {2, -2},   -- x2 OR NOT x2 (always true)
    {3, -3}    -- x3 OR NOT x3 (always true)
  }
  local assignment, steps, status = hybrid.solve(3, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should return assignment")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.equals(satisfaction, 100.0, "Tautologies should be 100% satisfied")
end)

-- Test 5: Direct contradiction
framework.test("Direct contradiction", function()
  local clauses = {
    {1},    -- x1 must be true
    {-1}    -- x1 must be false
  }
  local assignment, steps, status = hybrid.solve(1, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should return assignment")
  
  -- Cannot satisfy both, should satisfy exactly 1
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.equals(satisfaction, 50.0, "Should satisfy exactly 50% (1 of 2 clauses)")
end)

-- Test 6: Large clause sizes (beyond 3-SAT)
framework.test("Large clause sizes (5-SAT)", function()
  local clauses = {
    {1, 2, 3, 4, 5},
    {-1, -2, -3, -4, -5},
    {1, -2, 3, -4, 5}
  }
  local assignment, steps, status = hybrid.solve(5, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should handle large clauses")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 50.0, "Should satisfy majority of clauses")
end)

-- Test 7: Single-literal clauses only
framework.test("Only single-literal clauses", function()
  local clauses = {
    {1},
    {2},
    {-3},
    {4},
    {-5}
  }
  local assignment, steps, status = hybrid.solve(5, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should return assignment")
  framework.assert.equals(assignment[1], 1, "x1 should be true")
  framework.assert.equals(assignment[2], 1, "x2 should be true")
  framework.assert.equals(assignment[3], 0, "x3 should be false")
  framework.assert.equals(assignment[4], 1, "x4 should be true")
  framework.assert.equals(assignment[5], 0, "x5 should be false")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.equals(satisfaction, 100.0, "Should fully satisfy unit clauses")
end)

-- Test 8: All negative literals
framework.test("All negative literals", function()
  local clauses = {
    {-1, -2, -3},
    {-1, -2, -4},
    {-2, -3, -4}
  }
  local assignment, steps, status = hybrid.solve(4, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should handle all negative literals")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 80.0, "Should satisfy most clauses")
end)

-- Test 9: All positive literals
framework.test("All positive literals", function()
  local clauses = {
    {1, 2, 3},
    {1, 2, 4},
    {2, 3, 4}
  }
  local assignment, steps, status = hybrid.solve(4, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should handle all positive literals")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 80.0, "Should satisfy most clauses")
end)

-- Test 10: Very small problem (2 vars, 1 clause)
framework.test("Very small problem", function()
  local clauses = {{1, 2}}
  local assignment, steps, status = hybrid.solve(2, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should return assignment")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.equals(satisfaction, 100.0, "Should fully satisfy small problem")
end)

-- Test 11: Duplicate clauses
framework.test("Duplicate clauses", function()
  local clauses = {
    {1, 2, 3},
    {1, 2, 3},  -- Duplicate
    {1, 2, 3}   -- Duplicate
  }
  local assignment, steps, status = hybrid.solve(3, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should handle duplicate clauses")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 80.0, "Should satisfy duplicates")
end)

-- Test 12: Clauses with repeated variables
framework.test("Clauses with repeated variables", function()
  local clauses = {
    {1, 1, 2},    -- x1 appears twice
    {-2, -2, 3}   -- x2 appears twice (negated)
  }
  local assignment, steps, status = hybrid.solve(3, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should handle repeated variables in clauses")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 50.0, "Should satisfy some clauses")
end)

-- Test 13: Maximum variable index
framework.test("Sparse variable usage", function()
  local clauses = {
    {1, 50, 100},    -- Uses vars 1, 50, 100
    {25, 75, 100}    -- Uses vars 25, 75, 100
  }
  local assignment, steps, status = hybrid.solve(100, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should handle sparse variable usage")
  framework.assert.equals(#assignment, 100, "Should have 100 variables")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.greater_than(satisfaction, 50.0, "Should satisfy some clauses")
end)

-- Test 14: Horn clauses
framework.test("Horn clauses", function()
  -- Horn clauses have at most one positive literal
  local clauses = {
    {1},           -- Unit clause
    {-1, 2},       -- x1 => x2
    {-2, 3},       -- x2 => x3
    {-1, -2, 4}    -- (x1 AND x2) => x4
  }
  local assignment, steps, status = hybrid.solve(4, clauses, {verbose = false})
  
  framework.assert.not_nil(assignment, "Should handle Horn clauses")
  
  local satisfaction = walksat.verify(clauses, assignment) * 100.0
  framework.assert.equals(satisfaction, 100.0, "Horn clauses should be fully satisfiable")
end)

-- Run the suite
if not pcall(debug.getlocal, 4, 1) then
  -- Only run if executed directly (not required as module)
  framework.run_suite("Edge Case Tests")
end

return suite
