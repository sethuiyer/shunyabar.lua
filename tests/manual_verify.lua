--[[
  MANUAL VERIFICATION OF CUSTOM TREE CASE
]]

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"
local S = dofile(script_path .. "../src/shunyabar.lua")
local subtree_iso = dofile(script_path .. "subtree_isomorphism.lua")

-- Define the trees as before
local custom_pattern_nodes = {
  { children = {2, 3} },  -- Node 1 has children 2, 3
  { children = {4} },     -- Node 2 has child 4
  { children = {} },      -- Node 3 has no children
  { children = {} }       -- Node 4 has no children
}

local custom_target_nodes = {
  { children = {2, 3, 5} },  -- Node 1 has children 2, 3, 5
  { children = {4} },        -- Node 2 has child 4
  { children = {} },         -- Node 3 has no children
  { children = {} },         -- Node 4 has no children
  { children = {6} },        -- Node 5 has child 6
  { children = {} }          -- Node 6 has no children
}

local custom_pattern = subtree_iso.create_tree(custom_pattern_nodes)
local custom_target = subtree_iso.create_tree(custom_target_nodes)

print("Trees defined:")
print("Pattern has " .. custom_pattern.size .. " nodes")
print("Target has " .. custom_target.size .. " nodes")

-- Test the expected mapping: 1->1, 2->2, 3->3, 4->4
local expected_mapping = {
  [1] = 1,
  [2] = 2, 
  [3] = 3,
  [4] = 4
}

print("\nTesting expected mapping: 1->1, 2->2, 3->3, 4->4")
print("Verification result: " .. tostring(subtree_iso.verify_mapping(custom_pattern, custom_target, expected_mapping)))

-- Let's manually trace through the verification:
print("\nManual verification trace:")
print("1. Check if pattern node 1 (children {2,3}) maps to target node 1 (children {2,3,5}): Yes")
print("   - Pattern child 2 (maps to 2) should be child of target 1: Yes, 2 is in {2,3,5}")
print("   - Pattern child 3 (maps to 3) should be child of target 1: Yes, 3 is in {2,3,5}")

print("2. Check if pattern node 2 (children {4}) maps to target node 2 (children {4}): Yes")
print("   - Pattern child 4 (maps to 4) should be child of target 2: Yes, 4 is in {4}")

print("3. Check if pattern node 3 (children {}) maps to target node 3 (children {}): Yes")
print("   - No children to check")

print("4. Check if pattern node 4 (children {}) maps to target node 4 (children {}): Yes")
print("   - No children to check")

print("\nThe expected mapping should be valid!")