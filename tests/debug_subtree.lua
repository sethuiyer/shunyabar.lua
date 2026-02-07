--[[
  DEBUG SUBTREE ISOMORPHISM
  Debugging the custom tree case that's failing
]]

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"
local S = dofile(script_path .. "../src/shunyabar.lua")
local subtree_iso = dofile(script_path .. "subtree_isomorphism.lua")

-- Custom tree structures from the test
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

print("Debug: Custom tree structures")
print("Pattern:")
for i = 1, custom_pattern.size do
  local children_str = table.concat(custom_pattern.nodes[i].children or {}, ", ")
  print("  Node " .. i .. " -> children {" .. children_str .. "}")
end

print("Target:")
for i = 1, custom_target.size do
  local children_str = table.concat(custom_target.nodes[i].children or {}, ", ")
  print("  Node " .. i .. " -> children {" .. children_str .. "}")
end

-- Manual verification: The pattern should match the target as a subtree
-- Pattern: 1->{2,3}, 2->{4}, 3->{}, 4->{}
-- Target:  1->{2,3,5}, 2->{4}, 3->{}, 4->{}, 5->{6}, 6->{}
-- Mapping: 1->1, 2->2, 3->3, 4->4 (this should work!)

print("\nManual verification of expected mapping:")
print("Mapping: 1->1, 2->2, 3->3, 4->4")
print("- Pattern node 1 (children {2,3}) should map to Target node 1 (children {2,3,5})")
print("  ✓ Children 2,3 of pattern node 1 should map to children 2,3 of target node 1")
print("- Pattern node 2 (children {4}) should map to Target node 2 (children {4})")
print("  ✓ Child 4 of pattern node 2 should map to child 4 of target node 2")
print("- Pattern node 3 (children {}) should map to Target node 3 (children {})") 
print("  ✓ Both have no children")
print("- Pattern node 4 (children {}) should map to Target node 4 (children {})")
print("  ✓ Both have no children")
print("This mapping should be valid!")

-- Run the solver
local isomorphic, mapping = subtree_iso.solve(custom_pattern, custom_target, { steps = 2000, learning_rate = 0.05 })
print("\nSolver result:")
print("Isomorphic: " .. tostring(isomorphic))
if mapping then
  for p, t in pairs(mapping) do
    print("  Pattern node " .. p .. " -> Target node " .. t)
  end
else
  print("  No mapping found")
end

-- Try with different parameters
print("\nTrying with more steps and different parameters...")
local isomorphic2, mapping2 = subtree_iso.solve(custom_pattern, custom_target, { 
  steps = 5000, 
  learning_rate = 0.03,
  beta_max = 10.0
})
print("Isomorphic: " .. tostring(isomorphic2))
if mapping2 then
  for p, t in pairs(mapping2) do
    print("  Pattern node " .. p .. " -> Target node " .. t)
  end
  print("Verified: " .. tostring(subtree_iso.verify_mapping(custom_pattern, custom_target, mapping2)))
else
  print("  No mapping found")
end