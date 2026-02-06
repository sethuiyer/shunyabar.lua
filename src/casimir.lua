-- CASIMIR SAT SOLVER
-- Quantum-inspired Langevin dynamics SAT solver extracted from shunyabar.lua
-- Author: Sethu Iyer | License: Apache 2.0

local casimir = {}
local M = {}

-- Math utilities (minimal subset needed for Casimir)
function M.zeros(n, init)
  local arr = {}
  for i = 1, n do arr[i] = init or 0 end
  return arr
end

function M.randn()
  local u1 = math.random()
  local u2 = math.random()
  while u1 <= 1e-15 do u1 = math.random() end
  return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
end

function M.sigmoid(x)
  if x >= 0 then
    local ez = math.exp(-x)
    return 1.0 / (1.0 + ez)
  else
    local ez = math.exp(x)
    return ez / (1.0 + ez)
  end
end

function M.matrix(rows, cols, init)
  local mat = {}
  for i = 1, rows do
    mat[i] = {}
    for j = 1, cols do
      mat[i][j] = init or 0
    end
  end
  return mat
end

--- Create a CasimirSolver instance
--- @param num_vars     number
--- @param clauses      {{int,...},...}
--- @param opts         table  {temperature, learning_rate, correlation_length}
function casimir.Solver(num_vars, clauses, opts)
  opts = opts or {}
  local self = {
    num_vars           = num_vars,
    clauses            = clauses,
    temperature        = opts.temperature or 2.0,
    learning_rate      = opts.learning_rate or 0.5,
    correlation_length = opts.correlation_length or 3.0,
    step_count         = 0,
    beta               = 1.0,
  }

  -- State: continuous probabilities
  self.x = M.zeros(num_vars, 0.5)
  -- Internal logit-space state for stable dynamics
  self.u = M.zeros(num_vars, 0.0)

  --- Fractional satisfaction: s_c = 1 - ∏(1 - x_ℓ)
  function self:fractional_satisfaction(clause)
    local unsat = 1.0
    for _, lit in ipairs(clause) do
      local vi = math.abs(lit)
      if lit > 0 then
        unsat = unsat * (1.0 - self.x[vi])
      else
        unsat = unsat * self.x[vi]
      end
    end
    return 1.0 - unsat
  end

  --- Total energy: E = Σ (1 - s_c)²
  function self:total_energy()
    local E = 0.0
    for _, clause in ipairs(self.clauses) do
      local sc = self:fractional_satisfaction(clause)
      E = E + (1.0 - sc) ^ 2
    end
    return E
  end

  --- Compute gradients ∂E/∂x_i
  function self:compute_gradients()
    local grads = M.zeros(self.num_vars)
    for _, clause in ipairs(self.clauses) do
      -- P = ∏(1-x_ℓ) for positive, ∏(x_ℓ) for negative
      local unsat = 1.0
      for _, lit in ipairs(clause) do
        local vi = math.abs(lit)
        if lit > 0 then
          unsat = unsat * (1.0 - self.x[vi])
        else
          unsat = unsat * self.x[vi]
        end
      end
      if unsat == 0 then goto continue end

      -- dE/dx_i = 2 * P * dP/dx_i
      for _, lit in ipairs(clause) do
        local vi = math.abs(lit)
        if lit > 0 then
          local denom = 1.0 - self.x[vi]
          if denom > 1e-10 then
            local deriv = -unsat / denom
            grads[vi] = grads[vi] + 2.0 * unsat * deriv
          end
        else
          if self.x[vi] > 1e-10 then
            local deriv = unsat / self.x[vi]
            grads[vi] = grads[vi] + 2.0 * unsat * deriv
          end
        end
      end
      ::continue::
    end
    return grads
  end

  --- Langevin dynamics step: dx/dt = -η∇E + √(2T)ξ
  --- Uses logit-space accumulator for stability
  function self:langevin_step()
    local grads = self:compute_gradients()

    for i = 1, self.num_vars do
      local noise = math.sqrt(2.0 * self.temperature) * M.randn()
      -- Update internal logit state
      self.u[i] = self.u[i] + (-self.learning_rate * grads[i] + 0.1 * noise)
      -- Project to [0,1] via sigmoid
      self.x[i] = M.sigmoid(self.beta * self.u[i])
    end

    -- Annealing schedules
    self.step_count = self.step_count + 1
    self.temperature = 2.0 / math.log(1.0 + self.step_count * 0.05)
    self.beta = 1.0 + self.step_count * 0.01
    self.correlation_length = self.correlation_length * 0.995
  end

  --- Check if solution is found (energy near zero and values boolean-like)
  function self:is_converged(tol)
    tol = tol or 1e-3
    if self:total_energy() > tol then return false end
    for i = 1, self.num_vars do
      if self.x[i] > 0.1 and self.x[i] < 0.9 then return false end
    end
    return true
  end

  --- Extract boolean assignment from current state
  function self:get_assignment()
    local assignment = {}
    for i = 1, self.num_vars do
      assignment[i] = (self.x[i] > 0.5) and 1 or 0
    end
    return assignment
  end

  --- Run solver for up to max_steps
  function self:solve(max_steps)
    max_steps = max_steps or 1000
    for step = 1, max_steps do
      self:langevin_step()
      if self:is_converged() then
        return self:get_assignment(), step, self:total_energy()
      end
    end
    return self:get_assignment(), max_steps, self:total_energy()
  end

  --- Build variable-constraint adjacency matrix (for spectral analysis)
  function self:build_adjacency()
    local adj = M.matrix(self.num_vars, self.num_vars)
    for _, clause in ipairs(self.clauses) do
      for i = 1, #clause do
        local u = math.abs(clause[i])
        for j = i + 1, #clause do
          local v = math.abs(clause[j])
          adj[u][v] = 1.0
          adj[v][u] = 1.0
        end
      end
    end
    return adj
  end

  return self
end

--- Verify solution against clauses
--- @param clauses {{int,...},...}
--- @param assignment {int,...}
--- @return number  Satisfaction percentage
function casimir.verify_solution(clauses, assignment)
  local satisfied = 0
  for _, clause in ipairs(clauses) do
    local clause_satisfied = false
    for _, lit in ipairs(clause) do
      local vi = math.abs(lit)
      if lit > 0 then
        if assignment[vi] == 1 then
          clause_satisfied = true
          break
        end
      else
        if assignment[vi] == 0 then
          clause_satisfied = true
          break
        end
      end
    end
    if clause_satisfied then satisfied = satisfied + 1 end
  end
  return (satisfied / #clauses) * 100.0
end

--- Generate a simple SAT problem for testing
--- @param num_vars number
--- @param num_clauses number
--- @return {{int,...},...} Clauses
function casimir.generate_test_clauses(num_vars, num_clauses)
  local clauses = {}
  for i = 1, num_clauses do
    local clause = {}
    for j = 1, 3 do  -- 3-SAT
      local var = math.random(1, num_vars)
      local sign = (math.random() > 0.5) and 1 or -1
      clause[#clause + 1] = sign * var
    end
    clauses[#clauses + 1] = clause
  end
  return clauses
end

return casimir