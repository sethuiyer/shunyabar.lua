--[[
  SUBTREE ISOMORPHISM SOLVER
  Using ShunyaBar framework to determine if a pattern tree is isomorphic to a subtree of a target tree
  
  The approach:
  1. Encode the subtree isomorphism problem as a boolean satisfiability problem (SAT)
  2. Use Navokoj's prime-weighted geometric flow to find a valid assignment
  3. Constraints ensure the mapping is injective and preserves parent-child relationships
]]

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"
local S = dofile(script_path .. "../src/shunyabar.lua")
local M = S.math
local navokoj = S.navokoj

local subtree_iso = {}

--- Create a simple tree structure
--- @param nodes table { {children={child_indices}}, ... }
function subtree_iso.create_tree(nodes)
  return {
    nodes = nodes,
    size = #nodes
  }
end

--- Check if pattern_tree is isomorphic to a subtree of target_tree
--- @param pattern_tree table Tree structure with nodes and children
--- @param target_tree table Tree structure with nodes and children
--- @param opts table Optional parameters
--- @return boolean, table Isomorphic and mapping if found
function subtree_iso.solve(pattern_tree, target_tree, opts)
  opts = opts or {}
  local p_size = pattern_tree.size
  local t_size = target_tree.size
  
  -- If pattern is larger than target, no solution exists
  if p_size > t_size then
    return false, {}
  end

  -- Default options for Navokoj
  if not opts.beta_max then opts.beta_max = 5.0 end

  
  -- Encode variables: x[p][t] -> index in SAT variables
  -- var_idx = (p-1) * t_size + t
  local function get_var(p, t)
    return (p - 1) * t_size + t
  end
  
  local clauses = {}
  
  -- Constraint 1: Each pattern node maps to AT LEAST ONE target node (Highest Priority)
  -- This provides the "positive pressure" to prevent all-zero collapse
  for p = 1, p_size do
    local clause = {}
    for t = 1, t_size do
      clause[#clause + 1] = get_var(p, t)
    end
    clauses[#clauses + 1] = clause
  end
  
  -- Precompute target adjacency for fast lookup
  local target_adj = {}
  for t = 1, t_size do
    target_adj[t] = {}
    for _, child in ipairs(target_tree.nodes[t].children or {}) do
      target_adj[t][child] = true
    end
  end
  
  -- Constraint 2: Structure Preservation
  -- If (p, pc) is an edge in Pattern, then (map(p), map(pc)) must be an edge in Target
  for p = 1, p_size do
    for _, pc in ipairs(pattern_tree.nodes[p].children or {}) do
      for t1 = 1, t_size do
        for t2 = 1, t_size do
          -- If t2 is NOT a child of t1 in target
          if not target_adj[t1][t2] then
            -- Then we cannot simultaneously map p->t1 and pc->t2
            clauses[#clauses + 1] = { -get_var(p, t1), -get_var(pc, t2) }
          end
        end
      end
    end
  end

  -- Constraint 3: Injectivity - Each target node is mapped to AT MOST one pattern node
  for t = 1, t_size do
    for p1 = 1, p_size do
      for p2 = p1 + 1, p_size do
        clauses[#clauses + 1] = { -get_var(p1, t), -get_var(p2, t) }
      end
    end
  end
  
  -- Constraint 4: Each pattern node maps to AT MOST ONE target node
  -- (Can be lower priority, as "at least one" plus injectivity/structure usually forces uniqueness)
  for p = 1, p_size do
    for t1 = 1, t_size do
      for t2 = t1 + 1, t_size do
        clauses[#clauses + 1] = { -get_var(p, t1), -get_var(p, t2) }
      end
    end
  end
  
  -- Solve SAT
  local num_vars = p_size * t_size
  local assignment = navokoj.solve_sat(num_vars, clauses, opts)
  
  -- Verify completeness (Navokoj is heuristic/continuous, might return invalid assignment)
  -- But we can just try to build the mapping and verify it.
  
  local mapping = {}
  local reverse_mapping = {} -- used to check injectivity quickly here
  
  for p = 1, p_size do
    local found = false
    for t = 1, t_size do
      if assignment[get_var(p, t)] == 1 then
        if found then
           -- Multiple targets for one pattern - invalid
           return false, {}
        end
        mapping[p] = t
        found = true
      end
    end
    if not found then
      -- No target for this pattern - invalid
      return false, {}
    end
  end
  
  -- Verify using the robust verify_mapping function
  if subtree_iso.verify_mapping(pattern_tree, target_tree, mapping) then
    return true, mapping
  else
    return false, mapping
  end
end

--- Helper function to create a simple tree from adjacency list
function subtree_iso.from_adjacency_list(adj_list)
  local nodes = {}
  for i = 1, #adj_list do
    nodes[i] = { children = adj_list[i] or {} }
  end
  return subtree_iso.create_tree(nodes)
end

--- Helper function to create a path tree
function subtree_iso.create_path_tree(length)
  local nodes = {}
  for i = 1, length do
    if i == length then
      nodes[i] = { children = {} }
    else
      nodes[i] = { children = {i + 1} }
    end
  end
  return subtree_iso.create_tree(nodes)
end

--- Helper function to create a star tree
function subtree_iso.create_star_tree(branches)
  local nodes = {}
  -- Root node (index 1) has all other nodes as children
  nodes[1] = { children = {} }
  for i = 2, branches + 1 do
    nodes[1].children[#nodes[1].children + 1] = i
    nodes[i] = { children = {} }  -- leaf nodes
  end
  return subtree_iso.create_tree(nodes)
end

--- Verify a mapping is valid
function subtree_iso.verify_mapping(pattern_tree, target_tree, mapping)
  if not mapping then return false end
  
  -- Check that mapping is injective (one-to-one)
  local used = {}
  local count = 0
  for p, t in pairs(mapping) do
    if used[t] then
      return false  -- Two pattern nodes mapped to same target node
    end
    used[t] = true
    count = count + 1
  end
  
  -- Check that all pattern nodes are mapped
  if count ~= pattern_tree.size then
    return false
  end
  
  -- Check that parent-child relationships are preserved
  for p = 1, pattern_tree.size do
    local t = mapping[p]
    if not t then
      return false
    end
    
    -- For each child of p, check if it maps to a child of t
    for _, pc in ipairs(pattern_tree.nodes[p].children or {}) do
      local tc = mapping[pc]
      if tc then
        -- Verify tc is a child of t in target tree
        local is_child = false
        for _, target_child in ipairs(target_tree.nodes[t].children or {}) do
          if target_child == tc then
            is_child = true
            break
          end
        end
        if not is_child then
          -- print("DEBUG: Pattern node " .. p .. "(mapped to " .. t .. ") has child " .. pc .. 
          --       "(mapped to " .. tc .. ") but " .. tc .. " is not a child of " .. t)
          return false
        end
      end
    end
  end
  
  return true
end

return subtree_iso