-- TEST FRAMEWORK
-- Lightweight testing utilities for shunyabar.lua
-- Author: Sethu Iyer | License: Apache 2.0

local framework = {}

-- Test suite state
framework.suites = {}
framework.current_suite = nil

--- Create a new test suite
--- @param name string
--- @return table
function framework.suite(name)
  local suite = {
    name = name,
    tests = {},
    setup = nil,
    teardown = nil,
    results = {
      passed = 0,
      failed = 0,
      errors = 0,
      total_time = 0
    }
  }
  
  framework.suites[#framework.suites + 1] = suite
  framework.current_suite = suite
  return suite
end

--- Add a test case to current suite
--- @param name string
--- @param fn function
function framework.test(name, fn)
  if not framework.current_suite then
    error("No active test suite. Call framework.suite() first.")
  end
  
  local test = {
    name = name,
    fn = fn,
    passed = false,
    error_msg = nil,
    time = 0,
    metrics = {}
  }
  
  framework.current_suite.tests[#framework.current_suite.tests + 1] = test
end

--- Assertion utilities
framework.assert = {}

function framework.assert.equals(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s\nExpected: %s\nActual: %s", 
      msg or "Assertion failed", tostring(expected), tostring(actual)))
  end
end

function framework.assert.not_equals(actual, expected, msg)
  if actual == expected then
    error(string.format("%s\nExpected not equal to: %s", 
      msg or "Assertion failed", tostring(expected)))
  end
end

function framework.assert.is_true(value, msg)
  if not value then
    error(msg or "Expected true, got false")
  end
end

function framework.assert.is_false(value, msg)
  if value then
    error(msg or "Expected false, got true")
  end
end

function framework.assert.is_nil(value, msg)
  if value ~= nil then
    error(string.format("%s\nExpected nil, got: %s", 
      msg or "Assertion failed", tostring(value)))
  end
end

function framework.assert.not_nil(value, msg)
  if value == nil then
    error(msg or "Expected non-nil value")
  end
end

function framework.assert.greater_than(actual, threshold, msg)
  if not (actual > threshold) then
    error(string.format("%s\nExpected > %s, got: %s", 
      msg or "Assertion failed", tostring(threshold), tostring(actual)))
  end
end

function framework.assert.less_than(actual, threshold, msg)
  if not (actual < threshold) then
    error(string.format("%s\nExpected < %s, got: %s", 
      msg or "Assertion failed", tostring(threshold), tostring(actual)))
  end
end

function framework.assert.greater_or_equal(actual, threshold, msg)
  if not (actual >= threshold) then
    error(string.format("%s\nExpected >= %s, got: %s", 
      msg or "Assertion failed", tostring(threshold), tostring(actual)))
  end
end

function framework.assert.less_or_equal(actual, threshold, msg)
  if not (actual <= threshold) then
    error(string.format("%s\nExpected <= %s, got: %s", 
      msg or "Assertion failed", tostring(threshold), tostring(actual)))
  end
end

function framework.assert.in_range(actual, min_val, max_val, msg)
  if not (actual >= min_val and actual <= max_val) then
    error(string.format("%s\nExpected in range [%s, %s], got: %s", 
      msg or "Assertion failed", tostring(min_val), tostring(max_val), tostring(actual)))
  end
end

function framework.assert.table_equals(actual, expected, msg)
  if type(actual) ~= "table" or type(expected) ~= "table" then
    error(msg or "Both values must be tables")
  end
  
  if #actual ~= #expected then
    error(string.format("%s\nTable length mismatch: expected %d, got %d", 
      msg or "Assertion failed", #expected, #actual))
  end
  
  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      error(string.format("%s\nTable mismatch at index %d: expected %s, got %s", 
        msg or "Assertion failed", i, tostring(expected[i]), tostring(actual[i])))
    end
  end
end

--- Run all test suites
--- @param verbose boolean
--- @return table  Summary results
function framework.run_all(verbose)
  verbose = verbose ~= false
  
  local total_results = {
    passed = 0,
    failed = 0,
    errors = 0,
    total_time = 0,
    suites = 0
  }
  
  print("\n" .. string.rep("=", 80))
  print("RUNNING TEST SUITES")
  print(string.rep("=", 80))
  
  for _, suite in ipairs(framework.suites) do
    total_results.suites = total_results.suites + 1
    
    if verbose then
      print("\n[SUITE] " .. suite.name)
      print(string.rep("-", 80))
    end
    
    for _, test in ipairs(suite.tests) do
      local start_time = os.clock()
      local success, err = pcall(function()
        if suite.setup then suite.setup() end
        test.fn()
        if suite.teardown then suite.teardown() end
      end)
      test.time = os.clock() - start_time
      
      if success then
        test.passed = true
        suite.results.passed = suite.results.passed + 1
        total_results.passed = total_results.passed + 1
        if verbose then
          print(string.format("  ✓ %s (%.3fs)", test.name, test.time))
        end
      else
        test.passed = false
        test.error_msg = err
        suite.results.failed = suite.results.failed + 1
        total_results.failed = total_results.failed + 1
        if verbose then
          print(string.format("  ✗ %s (%.3fs)", test.name, test.time))
          print("    Error: " .. tostring(err))
        end
      end
      
      suite.results.total_time = suite.results.total_time + test.time
      total_results.total_time = total_results.total_time + test.time
    end
    
    if verbose then
      print(string.format("\n  Suite Results: %d passed, %d failed (%.3fs)", 
        suite.results.passed, suite.results.failed, suite.results.total_time))
    end
  end
  
  -- Summary
  print("\n" .. string.rep("=", 80))
  print("SUMMARY")
  print(string.rep("=", 80))
  print(string.format("Suites:  %d", total_results.suites))
  print(string.format("Tests:   %d total, %d passed, %d failed", 
    total_results.passed + total_results.failed, 
    total_results.passed, 
    total_results.failed))
  print(string.format("Time:    %.3fs", total_results.total_time))
  
  if total_results.failed == 0 then
    print("\n✓ ALL TESTS PASSED")
  else
    print("\n✗ SOME TESTS FAILED")
  end
  print(string.rep("=", 80) .. "\n")
  
  return total_results
end

--- Run a specific suite by name
--- @param name string
--- @param verbose boolean
function framework.run_suite(name, verbose)
  verbose = verbose ~= false
  
  for _, suite in ipairs(framework.suites) do
    if suite.name == name then
      print("\n" .. string.rep("=", 80))
      print("[SUITE] " .. suite.name)
      print(string.rep("=", 80))
      
      for _, test in ipairs(suite.tests) do
        local start_time = os.clock()
        local success, err = pcall(function()
          if suite.setup then suite.setup() end
          test.fn()
          if suite.teardown then suite.teardown() end
        end)
        test.time = os.clock() - start_time
        
        if success then
          test.passed = true
          suite.results.passed = suite.results.passed + 1
          if verbose then
            print(string.format("  ✓ %s (%.3fs)", test.name, test.time))
          end
        else
          test.passed = false
          test.error_msg = err
          suite.results.failed = suite.results.failed + 1
          if verbose then
            print(string.format("  ✗ %s (%.3fs)", test.name, test.time))
            print("    Error: " .. tostring(err))
          end
        end
        
        suite.results.total_time = suite.results.total_time + test.time
      end
      
      print(string.format("\nResults: %d passed, %d failed (%.3fs)", 
        suite.results.passed, suite.results.failed, suite.results.total_time))
      print(string.rep("=", 80) .. "\n")
      
      return suite.results
    end
  end
  
  error("Suite not found: " .. name)
end

return framework
