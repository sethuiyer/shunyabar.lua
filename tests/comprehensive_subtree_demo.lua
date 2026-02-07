--[[
  COMPREHENSIVE SUBTREE ISOMORPHISM DEMONSTRATION
  Demonstrating the subtree isomorphism solver with various tree structures
]]

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"
local S = dofile(script_path .. "../src/shunyabar.lua")
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
print("COMPREHENSIVE SUBTREE ISOMORPHISM DEMO")
print("Using ShunyaBar Framework")
print("=========================================")

-- Test 1: Path trees (simplest case)
print("\n--- Test 1: Path trees (Linear chains) ---")
local pattern = subtree_iso.create_path_tree(3)  -- Path of length 3: 1->2->3
local target = subtree_iso.create_path_tree(6)   -- Path of length 6: 1->2->3->4->5->6

print_tree(pattern, "Pattern (3-node path)")
print_tree(target, "Target (6-node path)")

local isomorphic, mapping = subtree_iso.solve(pattern, target, { steps = 2000, learning_rate = 0.05 })
print_mapping(mapping, "Result mapping")
print("Isomorphic: " .. tostring(isomorphic))
print("Verified: " .. tostring(subtree_iso.verify_mapping(pattern, target, mapping)))

-- Test 2: Star trees
print("\n--- Test 2: Star trees ---")
local pattern_star = subtree_iso.create_star_tree(3)  -- Star with 3 branches: center connects to 3 leaves
local target_star = subtree_iso.create_star_tree(7)   -- Star with 7 branches: center connects to 7 leaves

print_tree(pattern_star, "Pattern (star with 3 branches)")
print_tree(target_star, "Target (star with 7 branches)")

local isomorphic2, mapping2 = subtree_iso.solve(pattern_star, target_star, { steps = 2000, learning_rate = 0.05 })
print_mapping(mapping2, "Result mapping")
print("Isomorphic: " .. tostring(isomorphic2))
print("Verified: " .. tostring(subtree_iso.verify_mapping(pattern_star, target_star, mapping2)))

-- Test 3: Pattern not contained in target
print("\n--- Test 3: Impossible case ---")
local pattern_large = subtree_iso.create_path_tree(8)  -- Path of length 8
local target_small = subtree_iso.create_star_tree(4)   -- Star with 4 nodes total

print_tree(pattern_large, "Pattern (8-node path)")
print_tree(target_small, "Target (star with 4 nodes total)")

local isomorphic3, mapping3 = subtree_iso.solve(pattern_large, target_small, { steps = 1500, learning_rate = 0.05 })
print_mapping(mapping3, "Result mapping")
print("Isomorphic: " .. tostring(isomorphic3))
print("Verified: " .. tostring(subtree_iso.verify_mapping(pattern_large, target_small, mapping3)))

-- Test 4: Different tree structures
print("\n--- Test 4: Binary tree patterns ---")
-- Pattern: Binary tree - 1 -> {2, 3}, 2 -> {4, 5}, 3 -> {}, 4 -> {}, 5 -> {}
local binary_pattern_nodes = {
  { children = {2, 3} },   -- Node 1 has children 2, 3
  { children = {4, 5} },   -- Node 2 has children 4, 5
  { children = {} },       -- Node 3 has no children
  { children = {} },       -- Node 4 has no children
  { children = {} }        -- Node 5 has no children
}

-- Target: Larger binary tree - 1 -> {2, 3}, 2 -> {4, 5}, 3 -> {6, 7}, 4 -> {8, 9}, 5 -> {}, 6 -> {}, 7 -> {}, 8 -> {}, 9 -> {}
local binary_target_nodes = {
  { children = {2, 3} },   -- Node 1 has children 2, 3
  { children = {4, 5} },   -- Node 2 has children 4, 5
  { children = {6, 7} },   -- Node 3 has children 6, 7
  { children = {8, 9} },   -- Node 4 has children 8, 9
  { children = {} },       -- Node 5 has no children
  { children = {} },       -- Node 6 has no children
  { children = {} },       -- Node 7 has no children
  { children = {} },       -- Node 8 has no children
  { children = {} }        -- Node 9 has no children
}

local binary_pattern = subtree_iso.create_tree(binary_pattern_nodes)
local binary_target = subtree_iso.create_tree(binary_target_nodes)

print_tree(binary_pattern, "Pattern (binary tree: depth 2)")
print_tree(binary_target, "Target (binary tree: depth 3)")

local isomorphic4, mapping4 = subtree_iso.solve(binary_pattern, binary_target, { steps = 3000, learning_rate = 0.03 })
print_mapping(mapping4, "Result mapping")
print("Isomorphic: " .. tostring(isomorphic4))
print("Verified: " .. tostring(subtree_iso.verify_mapping(binary_pattern, binary_target, mapping4)))

-- Test 5: Chain embedded in a tree
print("\n--- Test 5: Path embedded in tree ---")
-- Pattern: Simple path 1->2->3
local path_pattern_nodes = {
  { children = {2} },      -- Node 1 has child 2
  { children = {3} },      -- Node 2 has child 3
  { children = {} }        -- Node 3 has no children
}

-- Target: Tree that contains the path as a branch
local tree_with_path_nodes = {
  { children = {2, 4} },   -- Node 1 has children 2, 4
  { children = {3} },      -- Node 2 has child 3 (this is our path!)
  { children = {} },       -- Node 3 has no children
  { children = {5, 6} },   -- Node 4 has children 5, 6
  { children = {} },       -- Node 5 has no children
  { children = {} }        -- Node 6 has no children
}

local path_pattern = subtree_iso.create_tree(path_pattern_nodes)
local tree_with_path = subtree_iso.create_tree(tree_with_path_nodes)

print_tree(path_pattern, "Pattern (3-node path: 1->2->3)")
print_tree(tree_with_path, "Target (tree containing the path as a branch)")

local isomorphic5, mapping5 = subtree_iso.solve(path_pattern, tree_with_path, { steps = 2000, learning_rate = 0.05 })
print_mapping(mapping5, "Result mapping")
print("Isomorphic: " .. tostring(isomorphic5))
print("Verified: " .. tostring(subtree_iso.verify_mapping(path_pattern, tree_with_path, mapping5)))

print("\n=========================================")
print("SUMMARY")
print("=========================================")
print("Test 1 (Path trees): " .. (isomorphic and "PASS" or "FAIL"))
print("Test 2 (Star trees): " .. (isomorphic2 and "PASS" or "FAIL"))  
print("Test 3 (Impossible): " .. (not isomorphic3 and "PASS" or "FAIL"))
print("Test 4 (Binary trees): " .. (isomorphic4 and "PASS" or "FAIL"))
print("Test 5 (Embedded path): " .. (isomorphic5 and "PASS" or "FAIL"))

local total_passed = 0
if isomorphic then total_passed = total_passed + 1 end
if isomorphic2 then total_passed = total_passed + 1 end
if not isomorphic3 then total_passed = total_passed + 1 end
if isomorphic4 then total_passed = total_passed + 1 end
if isomorphic5 then total_passed = total_passed + 1 end

print("\nOverall: " .. total_passed .. "/5 tests passed")
print("Success rate: " .. math.floor((total_passed/5)*100) .. "%")

print("\nThis demonstrates that the ShunyaBar framework can successfully solve")
print("subtree isomorphism problems using prime-weighted geometric flow!")
print("=========================================")