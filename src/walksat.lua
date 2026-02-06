-- WALKSAT SOLVER
-- Stochastic local search SAT solver
-- Author: Sethu Iyer | License: Apache 2.0

local walksat = {}

--- Create a WalksatSolver instance
--- @param num_vars number
--- @param clauses {{int,...},...}
--- @param opts table {noise, max_flips, max_tries}
function walksat.Solver(num_vars, clauses, opts)
  opts = opts or {}
  local self = {
    num_vars    = num_vars,
    clauses     = clauses,
    noise       = opts.noise or 0.5,
    max_flips   = opts.max_flips or 10000,
    max_tries   = opts.max_tries or 10,
  }

  --- Count satisfied clauses for an assignment
  function self:count_satisfied(assignment)
    local count = 0
    for _, clause in ipairs(self.clauses) do
      local satisfied = false
      for _, lit in ipairs(clause) do
        local vi = math.abs(lit)
        if lit > 0 then
          if assignment[vi] == 1 then satisfied = true; break end
        else
          if assignment[vi] == 0 then satisfied = true; break end
        end
      end
      if satisfied then count = count + 1 end
    end
    return count
  end

  --- Count unsatisfied clauses
  function self:count_unsatisfied(assignment)
    return #self.clauses - self:count_satisfied(assignment)
  end

  --- Get list of unsatisfied clause indices
  function self:get_unsatisfied_clauses(assignment)
    local unsat = {}
    for i, clause in ipairs(self.clauses) do
      local satisfied = false
      for _, lit in ipairs(clause) do
        local vi = math.abs(lit)
        if lit > 0 then
          if assignment[vi] == 1 then satisfied = true; break end
        else
          if assignment[vi] == 0 then satisfied = true; break end
        end
      end
      if not satisfied then unsat[#unsat + 1] = i end
    end
    return unsat
  end

  --- Flip variable i in assignment
  function self:flip(assignment, i)
    assignment[i] = 1 - assignment[i]
  end

  --- Run Walksat from a given assignment (or random if nil)
  function self:run(provided_assignment)
    math.randomseed(os.time())

    local best_assignment = nil
    local best_unsatisfied = #self.clauses

    for try = 1, self.max_tries do
      -- Initialize random assignment if not provided
      local assignment = provided_assignment
      if not assignment then
        assignment = {}
        for i = 1, self.num_vars do
          assignment[i] = math.random(0, 1)
        end
      end

      local unsat_clauses = self:get_unsatisfied_clauses(assignment)
      local current_unsatisfied = #unsat_clauses

      -- Check if already solved
      if current_unsatisfied == 0 then
        return assignment, 0, "SAT"
      end

      for flip = 1, self.max_flips do
        unsat_clauses = self:get_unsatisfied_clauses(assignment)
        current_unsatisfied = #unsat_clauses

        if current_unsatisfied == 0 then
          if best_unsatisfied == 0 then
            return assignment, flip, "SAT"
          end
          break
        end

        if current_unsatisfied < best_unsatisfied then
          best_unsatisfied = current_unsatisfied
          best_assignment = { table.unpack(assignment) }
        end

        -- Pick random unsatisfied clause
        local clause_idx = unsat_clauses[math.random(#unsat_clauses)]
        local clause = self.clauses[clause_idx]

        -- Decide: random walk or greedy flip
        if math.random() < self.noise then
          -- Random walk: pick random variable in clause
          local var = math.abs(clause[math.random(#clause)])
          self:flip(assignment, var)
        else
          -- Greedy: pick variable that minimizes unsatisfied clauses
          local best_var = nil
          local best_break = current_unsatisfied

          for _, lit in ipairs(clause) do
            local vi = math.abs(lit)

            -- Count what happens if we flip vi
            self:flip(assignment, vi)
            local new_count = self:count_unsatisfied(assignment)
            local break_count = new_count - current_unsatisfied

            if break_count < best_break then
              best_break = break_count
              best_var = vi
            end

            -- Undo flip
            self:flip(assignment, vi)
          end

          if best_var then
            self:flip(assignment, best_var)
          else
            -- Fallback to random flip
            local var = math.abs(clause[math.random(#clause)])
            self:flip(assignment, var)
          end
        end
      end
    end

    -- Return best found
    if best_unsatisfied < #self.clauses then
      return best_assignment or {}, self.max_flips * self.max_tries,
             "PARTIAL(" .. best_unsatisfied .. "/" .. #self.clauses .. ")"
    end

    return {}, self.max_flips * self.max_tries,
           "UNSAT(" .. self:count_unsatisfied({}) .. " remaining)"
  end

  --- Convenience: solve from random start
  function self:solve()
    return self:run(nil)
  end

  return self
end

--- Verify solution
function walksat.verify(clauses, assignment)
  local satisfied = 0
  for _, clause in ipairs(clauses) do
    local ok = false
    for _, lit in ipairs(clause) do
      local vi = math.abs(lit)
      if lit > 0 and assignment[vi] == 1 then ok = true; break end
      if lit < 0 and assignment[vi] == 0 then ok = true; break end
    end
    if ok then satisfied = satisfied + 1 end
  end
  return satisfied / #clauses
end

return walksat
