-- Master test runner - executes all test suites
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"

local framework = dofile(script_path .. "test_framework.lua")

print([[
================================================================================
  SHUNYABAR.LUA COMPREHENSIVE TEST SUITE
================================================================================
  Testing hybrid SAT solver (Casimir + Walksat)
  
  Test Categories:
    • Unit Tests (Casimir, Walksat)
    • Integration Tests (Hybrid)
    • Stress Tests (Hard instances)
    • Edge Cases (Boundary conditions)
    
================================================================================
]])

-- Load all test suites
print("Loading test suites...")

local suites_to_run = {
  {name = "Casimir Unit Tests", file = "test_casimir.lua"},
  {name = "Walksat Unit Tests", file = "test_walksat_unit.lua"},
  {name = "Hybrid Integration Tests", file = "test_hybrid.lua"},
  {name = "Edge Case Tests", file = "test_edge_cases.lua"},
  {name = "Stress Tests", file = "test_stress.lua"}
}

local loaded_suites = {}
local failed_to_load = {}

for _, suite_info in ipairs(suites_to_run) do
  local success, result = pcall(function()
    return dofile(script_path .. suite_info.file)
  end)
  
  if success then
    loaded_suites[#loaded_suites + 1] = suite_info.name
    print("  ✓ Loaded: " .. suite_info.name)
  else
    failed_to_load[#failed_to_load + 1] = {name = suite_info.name, error = result}
    print("  ✗ Failed to load: " .. suite_info.name)
    print("    Error: " .. tostring(result))
  end
end

if #failed_to_load > 0 then
  print("\n⚠️  WARNING: Some test suites failed to load")
  print("Continuing with loaded suites...\n")
end

-- Run all loaded tests
print("\nStarting test execution...")
print("(This may take several minutes for stress tests)\n")

local start_time = os.clock()
local results = framework.run_all(true)
local total_time = os.clock() - start_time

-- Additional summary
print("\n" .. string.rep("=", 80))
print("DETAILED SUMMARY")
print(string.rep("=", 80))
print(string.format("Total execution time: %.2f seconds", total_time))
print(string.format("Test suites loaded: %d/%d", #loaded_suites, #suites_to_run))

if #failed_to_load > 0 then
  print("\nFailed to load:")
  for _, fail in ipairs(failed_to_load) do
    print("  • " .. fail.name)
  end
end

print("\nPer-suite breakdown:")
for _, suite in ipairs(framework.suites) do
  local total_tests = suite.results.passed + suite.results.failed
  local pass_rate = total_tests > 0 and (suite.results.passed / total_tests * 100) or 0
  print(string.format("  • %-30s %3d/%3d passed (%.1f%%) in %.2fs",
    suite.name,
    suite.results.passed,
    total_tests,
    pass_rate,
    suite.results.total_time))
end

print(string.rep("=", 80))

-- Exit with appropriate code
if results.failed == 0 and #failed_to_load == 0 then
  print("\n✓ ALL TESTS PASSED - SYSTEM VERIFIED")
  os.exit(0)
else
  print("\n✗ SOME TESTS FAILED - REVIEW REQUIRED")
  os.exit(1)
end
