--[[
  TEST SUBTREE ISOMORPHISM
  Testing the subtree isomorphism solver with various tree structures
]]

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"
local subtree_iso = dofile(script_path .. "subtree_isomorphism.lua")

local function print_tree(tree, label)
  print(label .. ":")
  for i = 1, tree.size do
    local children_str = table.concat(tree.nodes[i].children or {}, ", ")
    print("  Node " .. i .. " -> children {" .. children_str .. "}")
  end
end

local function print_mapping(mapping, label)
  if not mapping or next(mapping) == nil then
    print(label .. ": No valid mapping found")
    return
  end
  print(label .. ":")
  for p, t in pairs(mapping) do
    print("  Pattern node " .. p .. " -> Target node " .. t)
  end
end

print("=========================================")
print("SUBTREE ISOMORPHISM TESTS")
print("=========================================")

-- Test 1: Path trees (simplest case)
print("\n--- Test 1: Path trees ---")
local pattern = subtree_iso.create_path_tree(2)  -- Path of length 2: 1->2
local target = subtree_iso.create_path_tree(4)   -- Path of length 4: 1->2->3->4

print_tree(pattern, "Pattern (2-node path)")
print_tree(target, "Target (4-node path)")

local isomorphic, mapping = subtree_iso.solve(pattern, target, { steps = 1000, learning_rate = 0.05 })
print_mapping(mapping, "Result mapping")
print("Isomorphic: " .. tostring(isomorphic))
print("Verified: " .. tostring(subtree_iso.verify_mapping(pattern, target, mapping)))

-- Test 2: Star trees
print("\n--- Test 2: Star trees ---")
local pattern_star = subtree_iso.create_star_tree(2)  -- Star with 2 branches: center connects to 2 leaves
local target_star = subtree_iso.create_star_tree(5)   -- Star with 5 branches: center connects to 5 leaves

print_tree(pattern_star, "Pattern (star with 2 branches)")
print_tree(target_star, "Target (star with 5 branches)")

local isomorphic2, mapping2 = subtree_iso.solve(pattern_star, target_star, { steps = 1000, learning_rate = 0.05 })
print_mapping(mapping2, "Result mapping")
print("Isomorphic: " .. tostring(isomorphic2))
print("Verified: " .. tostring(subtree_iso.verify_mapping(pattern_star, target_star, mapping2)))

-- Test 3: Pattern not contained in target
print("\n--- Test 3: Pattern not contained in target ---")
local pattern_path = subtree_iso.create_path_tree(5)  -- Path of length 5
local target_star_small = subtree_iso.create_star_tree(3)  -- Star with 3 branches

print_tree(pattern_path, "Pattern (5-node path)")
print_tree(target_star_small, "Target (star with 3 branches)")

local isomorphic3, mapping3 = subtree_iso.solve(pattern_path, target_star_small, { steps = 1000, learning_rate = 0.05 })
print_mapping(mapping3, "Result mapping")
print("Isomorphic: " .. tostring(isomorphic3))
print("Verified: " .. tostring(subtree_iso.verify_mapping(pattern_path, target_star_small, mapping3)))

-- Test 4: Custom tree structures
print("\n--- Test 4: Custom tree structures ---")
-- Pattern: 1 -> {2, 3}, 2 -> {4}, 3 -> {}, 4 -> {}
local custom_pattern_nodes = {
  { children = {2, 3} },  -- Node 1 has children 2, 3
  { children = {4} },     -- Node 2 has child 4
  { children = {} },      -- Node 3 has no children
  { children = {} }       -- Node 4 has no children
}

-- Target: 1 -> {2, 3, 5}, 2 -> {4}, 3 -> {}, 4 -> {}, 5 -> {6}, 6 -> {}
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

print_tree(custom_pattern, "Pattern (custom tree)")
print_tree(custom_target, "Target (larger custom tree)")

local isomorphic4, mapping4 = subtree_iso.solve(custom_pattern, custom_target, { steps = 1500, learning_rate = 0.05 })
print_mapping(mapping4, "Result mapping")
print("Isomorphic: " .. tostring(isomorphic4))
print("Verified: " .. tostring(subtree_iso.verify_mapping(custom_pattern, custom_target, mapping4)))

print("\n=========================================")
print("SUBTREE ISOMORPHISM TESTS COMPLETE")
print("=========================================")