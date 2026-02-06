-- 50-Node HARD List Coloring Problem using BAHA
-- Increased difficulty: denser graph, tighter lists, more conflicts
-- Author: Sethu Iyer | License: Apache 2.0

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
local S = dofile(script_path .. "../src/shunyabar.lua")

print([[
================================================================================
  50-NODE HARD LIST COLORING PROBLEM
  Using BAHA (Branch-Aware Holonomy Annealing)
  Difficulty: HARD (dense graph, tight lists)
================================================================================
]])

-- ============================================================================
-- 1. GRAPH GENERATION: Denser Scale-Free Network
-- ============================================================================

--- Generate scale-free graph with MORE edges (harder)
local function generate_dense_scale_free_graph(n, m)
  local adj = {}
  for i = 1, n do adj[i] = {} end
  
  -- Start with m fully connected nodes
  for i = 1, m do
    for j = i + 1, m do
      adj[i][j] = true
      adj[j][i] = true
    end
  end
  
  -- Add remaining nodes with preferential attachment (MORE connections)
  for i = m + 1, n do
    local degrees = {}
    local total_degree = 0
    
    for j = 1, i - 1 do
      local deg = 0
      for k = 1, i - 1 do
        if adj[j][k] then deg = deg + 1 end
      end
      degrees[j] = deg
      total_degree = total_degree + deg
    end
    
    -- Connect to MORE nodes (m+2 instead of m)
    local connected = {}
    local connections = 0
    local target_connections = math.min(m + 2, i - 1)
    
    while connections < target_connections do
      local r = math.random() * (total_degree + i - 1)
      local cumsum = 0
      for j = 1, i - 1 do
        if not connected[j] then
          cumsum = cumsum + degrees[j] + 1
          if r <= cumsum then
            adj[i][j] = true
            adj[j][i] = true
            connected[j] = true
            connections = connections + 1
            break
          end
        end
      end
    end
  end
  
  return adj
end

local function get_degree(adj, node)
  local deg = 0
  for neighbor, _ in pairs(adj[node]) do
    deg = deg + 1
  end
  return deg
end

local function get_edges(adj)
  local edges = {}
  for u = 1, #adj do
    for v, _ in pairs(adj[u]) do
      if u < v then
        edges[#edges + 1] = {u, v}
      end
    end
  end
  return edges
end

-- ============================================================================
-- 2. TIGHTER COLOR LIST ASSIGNMENT
-- ============================================================================

--- Assign SMALLER color lists (harder problem)
local function assign_tight_color_lists(adj, n_colors)
  local lists = {}
  
  for node = 1, #adj do
    local degree = get_degree(adj, node)
    
    -- MUCH tighter: high-degree nodes get only 2-3 colors!
    local list_size = math.max(2, n_colors - math.floor(degree / 2))
    
    -- Random subset
    local available = {}
    for c = 1, n_colors do available[c] = c end
    
    local list = {}
    for i = 1, list_size do
      local idx = math.random(#available)
      list[#list + 1] = available[idx]
      table.remove(available, idx)
    end
    
    lists[node] = list
  end
  
  return lists
end

local function in_list(color, list)
  for _, c in ipairs(list) do
    if c == color then return true end
  end
  return false
end

-- ============================================================================
-- 3. BAHA SETUP
-- ============================================================================

local graph = nil
local lists = nil
local edges = nil

local function energy_fn(state)
  local conflicts = 0
  local violations = 0
  
  for _, edge in ipairs(edges) do
    local u, v = edge[1], edge[2]
    if state[u] == state[v] then
      conflicts = conflicts + 1
    end
  end
  
  for node, color in pairs(state) do
    if not in_list(color, lists[node]) then
      violations = violations + 1
    end
  end
  
  return conflicts + 10 * violations
end

local function sampler_fn()
  local state = {}
  for node = 1, #graph do
    local list = lists[node]
    state[node] = list[math.random(#list)]
  end
  return state
end

local function neighbor_fn(state)
  local neighbors = {}
  
  for node = 1, #graph do
    for _, color in ipairs(lists[node]) do
      if color ~= state[node] then
        local new_state = {}
        for k, v in pairs(state) do new_state[k] = v end
        new_state[node] = color
        neighbors[#neighbors + 1] = new_state
      end
    end
  end
  
  return neighbors
end

-- ============================================================================
-- 4. PROBLEM GENERATION (HARDER)
-- ============================================================================

print("Generating DENSE 50-node scale-free graph...")
math.randomseed(os.time())  -- Different each time
graph = generate_dense_scale_free_graph(50, 4)  -- More initial connections
edges = get_edges(graph)

print("Assigning TIGHT color lists...")
lists = assign_tight_color_lists(graph, 6)  -- Fewer colors, tighter lists

-- Statistics
local degrees = {}
local max_deg, min_deg = 0, 1000
local list_sizes = {}
for node = 1, #graph do
  local deg = get_degree(graph, node)
  degrees[node] = deg
  max_deg = math.max(max_deg, deg)
  min_deg = math.min(min_deg, deg)
  list_sizes[node] = #lists[node]
end

print("\nGraph Statistics:")
print("  Nodes: " .. #graph)
print("  Edges: " .. #edges)
print("  Degree range: " .. min_deg .. " - " .. max_deg)
print("  List sizes: " .. math.min(table.unpack(list_sizes)) .. " - " .. 
      math.max(table.unpack(list_sizes)))
print("  Density: " .. string.format("%.2f%%", (#edges / (50 * 49 / 2)) * 100))

-- ============================================================================
-- 5. RUN BAHA
-- ============================================================================

print("\n" .. string.rep("=", 80))
print("RUNNING BAHA")
print(string.rep("=", 80))

local optimizer = S.baha.BranchAwareOptimizer(energy_fn, sampler_fn, neighbor_fn)

local result = optimizer:optimize({
  beta_start = 0.01,
  beta_end = 10.0,
  beta_steps = 1000,  -- More steps
  fracture_threshold = 1.5,
  beta_critical = 1.0,
  max_branches = 5,
  samples_per_beta = 200,  -- More samples
  verbose = true
})

-- ============================================================================
-- 6. RESULTS
-- ============================================================================

print("\n" .. string.rep("=", 80))
print("RESULTS")
print(string.rep("=", 80))

print(string.format("Final Energy: %.1f", result.best_energy))
print(string.format("Fractures Detected: %d", result.fractures_detected))
print(string.format("Branch Jumps: %d", result.branch_jumps))

if result.branch_jumps > 0 then
  local jump_rate = (result.branch_jumps / result.fractures_detected) * 100
  print(string.format("Jump Rate: %.2f%% (selectivity: %.2f%%)", 
    jump_rate, 100 - jump_rate))
end

print(string.format("Beta at Solution: %.3f", result.beta_at_solution))
print(string.format("Steps Taken: %d", result.steps_taken))
print(string.format("Time: %.2fs", result.time_s))

if result.best_energy == 0 then
  print("\n✓ PERFECT SOLUTION FOUND!")
  print("  Zero conflicts, all list constraints satisfied")
  
  print("\nNode Colorings (showing high-degree hubs):")
  local hubs = {}
  for i = 1, #graph do
    if degrees[i] >= 10 then
      hubs[#hubs + 1] = i
    end
  end
  table.sort(hubs, function(a, b) return degrees[a] > degrees[b] end)
  
  for i = 1, math.min(10, #hubs) do
    local node = hubs[i]
    local color = result.best_state[node]
    local list_str = table.concat(lists[node], ",")
    print(string.format("  Node %2d: Color %d (list: [%s], degree: %d)", 
      node, color, list_str, degrees[node]))
  end
elseif result.best_energy < 10 then
  print("\n⚠ Near-optimal solution (E=" .. result.best_energy .. ")")
  print("  Some conflicts remain")
else
  print("\n✗ Solution incomplete (E=" .. result.best_energy .. ")")
end

print("\n" .. string.rep("=", 80))
