-- Test script for hybrid solver
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"
local casimir = dofile(script_path .. "../src/casimir.lua")
local walksat = dofile(script_path .. "../src/walksat.lua")

-- Use the core hybrid module
local hybrid = dofile(script_path .. "../src/hybrid.lua")

-- Run tests
print("\n" .. string.rep("=", 70))
print("HYBRID SOLVER TEST")
print(string.rep("=", 70))

-- Test 1: Simple SAT
print("\n[Test 1] Simple 3-SAT (6 vars, 5 clauses)")
local clauses1 = {
  {1, 2, 3},      -- x1 OR x2 OR x3
  {-1, 4, -5},   -- NOT x1 OR x4 OR NOT x5
  {2, -3, 6},    -- x2 OR NOT x3 OR x6
  {1, -2, 5},    -- x1 OR NOT x2 OR x5
  {-3, -4, 6},  -- NOT x3 OR NOT x4 OR x6
}
hybrid.solve(6, clauses1, {verbose = true})

-- Test 2: Random 3-SAT
print("\n[Test 2] Random 3-SAT (20 vars, ratio=4.26)")
math.randomseed(42)
local clauses2 = {}
for i = 1, 85 do
  local clause = {}
  for j = 1, 3 do
    clause[#clause + 1] = (math.random() > 0.5 and 1 or -1) * math.random(1, 20)
  end
  clauses2[#clauses2 + 1] = clause
end
hybrid.solve(20, clauses2, {verbose = true})

-- Test 3: Hard Random 3-SAT (N=100, ratio=4.26)
print("\n[Test 3] Hard Random 3-SAT (100 vars, ~426 clauses)")
math.randomseed(12345)
local clauses3 = {}
local n_vars3 = 100
local n_clauses3 = math.floor(n_vars3 * 4.26)
for i = 1, n_clauses3 do
  local clause = {}
  for j = 1, 3 do
    clause[#clause + 1] = (math.random() > 0.5 and 1 or -1) * math.random(1, n_vars3)
  end
  clauses3[#clauses3 + 1] = clause
end
hybrid.solve(n_vars3, clauses3, {verbose = true})

-- Test 4: AI Escargot Sudoku (Real World Hard)
print("\n[Test 4] AI Escargot Sudoku (729 vars, 8850 clauses)")
local shunyabar = dofile(script_path .. "../src/shunyabar.lua")
local ai_escargot = "800000000003600000070090200050007000000045700000100030001000068008500010090000400"
local n_vars_sod, clauses_sod = shunyabar.navokoj.encode_sudoku(ai_escargot)
-- Run with higher limits for this hard problem
hybrid.solve(n_vars_sod, clauses_sod, {
  verbose = true,
  max_casimir_steps = 5000,
  walksat_opts = { max_flips = 100000, max_tries = 5 }
})

print("\n" .. string.rep("=", 70))
print("TESTS COMPLETE")
print(string.rep("=", 70))
