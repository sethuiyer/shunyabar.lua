#!/usr/bin/env lua

--[[
Navier-Stokes Solver using Multiplicative PINNs

Solves 2D steady-state Poiseuille (channel) flow:

  Momentum X:   u * du/dx + v * du/dy = -1/ρ * dp/dx + ν * (d²u/dx² + d²u/dy²)
  Momentum Y:   u * dv/dx + v * dv/dy = -1/ρ * dp/dy + ν * (d²v/dx² + d²v/dy²)
  Continuity:   du/dx + dv/dy = 0  (incompressibility)

For fully-developed channel flow between parallel plates:
  - Channel height H = 1.0, length L = 2.0
  - No-slip walls: u(x,0) = u(x,H) = 0, v = 0 everywhere
  - Pressure-driven: dp/dx = const (we set -dp/dx = 1.0)
  - Kinematic viscosity: ν = 0.01

Exact solution (parabolic profile):
  u(y) = 1/(2ν) * (-dp/dx) * y * (H - y)
  v(y) = 0
  u_max = H² / (8ν) * (-dp/dx)

With our parameters: u_max = 1/(8*0.01) = 12.5
  u(y) = 50 * y * (1 - y)

We compare multiplicative vs additive PINN on satisfying:
  1. PDE residuals (momentum equations)
  2. Boundary conditions (no-slip walls)
  3. Incompressibility (divergence-free)

Using the multiplicative PINN approach from shunyabar.lua:
  L_total = L_data * C(violation)
  where C(v) = max(Euler_gate(v), exp_barrier(v))
]]

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"
local S = dofile(script_path .. "../src/shunyabar.lua")
local M = S.math
local pinn = S.pinn

M.seed(42)

-- ============================================================================
-- PHYSICAL PARAMETERS
-- ============================================================================

local H = 1.0        -- Channel height
local L = 2.0        -- Channel length
local nu = 0.01      -- Kinematic viscosity
local dpdx = -1.0    -- Pressure gradient (dp/dx), negative = flow in +x

-- Exact solution for fully-developed Poiseuille flow
local function exact_u(x, y)
  -- u(y) = 1/(2ν) * (-dp/dx) * y * (H - y)
  return (1.0 / (2.0 * nu)) * (-dpdx) * y * (H - y)
end

local function exact_v(x, y)
  return 0.0
end

local u_max = exact_u(0, H / 2)  -- Peak velocity at centerline

local function sep(title)
  print("\n" .. string.rep("=", 70))
  print("  " .. title)
  print(string.rep("=", 70))
end

-- ============================================================================
-- NEURAL NETWORK (2D input -> 2D output: u, v)
-- ============================================================================

local function create_ns_network(params)
  local self = {
    -- Layer 1: 2 inputs (x,y) -> n_hidden
    w1 = params.w1,   -- [2][n_hidden]
    b1 = params.b1,   -- [n_hidden]
    -- Layer 2: n_hidden -> n_hidden
    w2 = params.w2,   -- [n_hidden][n_hidden]
    b2 = params.b2,   -- [n_hidden]
    -- Layer 3: n_hidden -> 2 outputs (u, v)
    w3 = params.w3,   -- [n_hidden][2]
    b3 = params.b3,   -- [2]
    n_hidden = #params.b1,
  }

  --- Forward pass: (x, y) -> (u, v)
  function self.forward(x, y)
    local nh = self.n_hidden

    -- Layer 1: input -> hidden
    local h1 = {}
    for j = 1, nh do
      h1[j] = M.sigmoid(self.w1[1][j] * x + self.w1[2][j] * y + self.b1[j])
    end

    -- Layer 2: hidden -> hidden
    local h2 = {}
    for j = 1, nh do
      local sum = self.b2[j]
      for k = 1, nh do sum = sum + self.w2[k][j] * h1[k] end
      h2[j] = M.sigmoid(sum)
    end

    -- Layer 3: hidden -> output (u, v)
    local u_out = self.b3[1]
    local v_out = self.b3[2]
    for j = 1, nh do
      u_out = u_out + self.w3[j][1] * h2[j]
      v_out = v_out + self.w3[j][2] * h2[j]
    end

    return u_out, v_out
  end

  --- Partial derivatives via finite differences
  local eps = 1e-5

  function self.du_dx(x, y)
    local u1 = self.forward(x + eps, y)
    local u2 = self.forward(x - eps, y)
    return (u1 - u2) / (2 * eps)
  end

  function self.du_dy(x, y)
    local u1 = self.forward(x, y + eps)
    local u2 = self.forward(x, y - eps)
    return (u1 - u2) / (2 * eps)
  end

  function self.dv_dx(x, y)
    local _, v1 = self.forward(x + eps, y)
    local _, v2 = self.forward(x - eps, y)
    return (v1 - v2) / (2 * eps)
  end

  function self.dv_dy(x, y)
    local _, v1 = self.forward(x, y + eps)
    local _, v2 = self.forward(x, y - eps)
    return (v1 - v2) / (2 * eps)
  end

  function self.d2u_dx2(x, y)
    local u1 = self.forward(x + eps, y)
    local u0 = self.forward(x, y)
    local u2 = self.forward(x - eps, y)
    return (u1 - 2 * u0 + u2) / (eps * eps)
  end

  function self.d2u_dy2(x, y)
    local u1 = self.forward(x, y + eps)
    local u0 = self.forward(x, y)
    local u2 = self.forward(x, y - eps)
    return (u1 - 2 * u0 + u2) / (eps * eps)
  end

  function self.d2v_dx2(x, y)
    local _, v1 = self.forward(x + eps, y)
    local _, v0 = self.forward(x, y)
    local _, v2 = self.forward(x - eps, y)
    return (v1 - 2 * v0 + v2) / (eps * eps)
  end

  function self.d2v_dy2(x, y)
    local _, v1 = self.forward(x, y + eps)
    local _, v0 = self.forward(x, y)
    local _, v2 = self.forward(x, y - eps)
    return (v1 - 2 * v0 + v2) / (eps * eps)
  end

  return self
end

-- ============================================================================
-- INITIALIZE NETWORK
-- ============================================================================

local function init_params(n_hidden, seed)
  if seed then M.seed(seed) end
  local scale = 0.3

  local params = {
    w1 = { {}, {} },  -- [2][nh]
    b1 = {},
    w2 = {},           -- [nh][nh]
    b2 = {},
    w3 = {},           -- [nh][2]
    b3 = { 0, 0 },
  }

  for j = 1, n_hidden do
    params.w1[1][j] = M.randn() * scale
    params.w1[2][j] = M.randn() * scale
    params.b1[j] = M.randn() * scale
    params.b2[j] = M.randn() * scale
    params.w3[j] = { M.randn() * scale, M.randn() * scale }
  end

  for i = 1, n_hidden do
    params.w2[i] = {}
    for j = 1, n_hidden do
      params.w2[i][j] = M.randn() * scale
    end
  end

  params.b3 = { M.randn() * scale, M.randn() * scale }

  return params
end

-- ============================================================================
-- FLATTEN / UNFLATTEN PARAMS (for gradient computation)
-- ============================================================================

local function flatten_params(params)
  local flat = {}
  local nh = #params.b1

  -- w1: [2][nh]
  for i = 1, 2 do
    for j = 1, nh do flat[#flat + 1] = params.w1[i][j] end
  end
  -- b1: [nh]
  for j = 1, nh do flat[#flat + 1] = params.b1[j] end
  -- w2: [nh][nh]
  for i = 1, nh do
    for j = 1, nh do flat[#flat + 1] = params.w2[i][j] end
  end
  -- b2: [nh]
  for j = 1, nh do flat[#flat + 1] = params.b2[j] end
  -- w3: [nh][2]
  for j = 1, nh do
    for k = 1, 2 do flat[#flat + 1] = params.w3[j][k] end
  end
  -- b3: [2]
  flat[#flat + 1] = params.b3[1]
  flat[#flat + 1] = params.b3[2]

  return flat
end

local function unflatten_params(flat, nh)
  local params = { w1 = { {}, {} }, b1 = {}, w2 = {}, b2 = {}, w3 = {}, b3 = {} }
  local idx = 1

  for i = 1, 2 do
    for j = 1, nh do params.w1[i][j] = flat[idx]; idx = idx + 1 end
  end
  for j = 1, nh do params.b1[j] = flat[idx]; idx = idx + 1 end
  for i = 1, nh do
    params.w2[i] = {}
    for j = 1, nh do params.w2[i][j] = flat[idx]; idx = idx + 1 end
  end
  for j = 1, nh do params.b2[j] = flat[idx]; idx = idx + 1 end
  for j = 1, nh do
    params.w3[j] = {}
    for k = 1, 2 do params.w3[j][k] = flat[idx]; idx = idx + 1 end
  end
  params.b3[1] = flat[idx]; idx = idx + 1
  params.b3[2] = flat[idx]

  return params
end

-- ============================================================================
-- LOSS FUNCTIONS
-- ============================================================================

--- Compute NS residuals at a point
local function ns_residuals(net, x, y)
  local u, v = net.forward(x, y)

  -- Derivatives
  local du_dx = net.du_dx(x, y)
  local du_dy = net.du_dy(x, y)
  local dv_dx = net.dv_dx(x, y)
  local dv_dy = net.dv_dy(x, y)
  local d2u_dx2 = net.d2u_dx2(x, y)
  local d2u_dy2 = net.d2u_dy2(x, y)
  local d2v_dx2 = net.d2v_dx2(x, y)
  local d2v_dy2 = net.d2v_dy2(x, y)

  -- Momentum X: u*du/dx + v*du/dy + dp/dx - ν*(d²u/dx² + d²u/dy²) = 0
  local res_mx = u * du_dx + v * du_dy + dpdx - nu * (d2u_dx2 + d2u_dy2)

  -- Momentum Y: u*dv/dx + v*dv/dy - ν*(d²v/dx² + d²v/dy²) = 0
  -- (dp/dy = 0 for this problem)
  local res_my = u * dv_dx + v * dv_dy - nu * (d2v_dx2 + d2v_dy2)

  -- Continuity: du/dx + dv/dy = 0
  local res_cont = du_dx + dv_dy

  return res_mx, res_my, res_cont
end

--- Generate training points
local function generate_points(n_interior, n_boundary)
  local interior = {}
  for i = 1, n_interior do
    interior[i] = { M.uniform(0.01, L - 0.01), M.uniform(0.01, H - 0.01) }
  end

  local boundary = {}
  -- Bottom wall (y=0)
  for i = 1, n_boundary do
    boundary[#boundary + 1] = { M.uniform(0, L), 0.0, "wall" }
  end
  -- Top wall (y=H)
  for i = 1, n_boundary do
    boundary[#boundary + 1] = { M.uniform(0, L), H, "wall" }
  end
  -- Inlet (x=0): use exact solution
  for i = 1, n_boundary do
    local y = M.uniform(0.01, H - 0.01)
    boundary[#boundary + 1] = { 0.0, y, "inlet" }
  end

  return interior, boundary
end

--- Compute multiplicative PINN loss
local function compute_mult_loss(net, interior, boundary)
  -- Boundary loss (data fidelity)
  local bc_loss = 0.0
  for _, bp in ipairs(boundary) do
    local x, y, btype = bp[1], bp[2], bp[3]
    local u_pred, v_pred = net.forward(x, y)

    if btype == "wall" then
      -- No-slip: u=0, v=0
      bc_loss = bc_loss + u_pred^2 + v_pred^2
    elseif btype == "inlet" then
      -- Inlet: u = exact parabolic profile, v = 0
      local u_exact = exact_u(x, y)
      bc_loss = bc_loss + (u_pred - u_exact)^2 + v_pred^2
    end
  end
  bc_loss = bc_loss / #boundary

  -- Physics residual (violation magnitude)
  local physics_loss = 0.0
  local max_violation = 0.0
  local continuity_loss = 0.0

  for _, pt in ipairs(interior) do
    local res_mx, res_my, res_cont = ns_residuals(net, pt[1], pt[2])
    physics_loss = physics_loss + res_mx^2 + res_my^2
    continuity_loss = continuity_loss + res_cont^2

    local v = math.abs(res_mx) + math.abs(res_my) + math.abs(res_cont)
    if v > max_violation then max_violation = v end
  end
  physics_loss = physics_loss / #interior
  continuity_loss = continuity_loss / #interior

  -- Multiplicative loss: L_total = L_bc * C(max_violation)
  local total_loss, factor, info = pinn.multiplicative_loss(
    bc_loss + 1e-10,  -- ensure non-zero
    max_violation,
    { tau = 3.0, gamma = 3.0 }
  )

  return total_loss, {
    bc_loss = bc_loss,
    physics_loss = physics_loss,
    continuity_loss = continuity_loss,
    max_violation = max_violation,
    factor = factor,
    total_loss = total_loss,
  }
end

--- Compute additive PINN loss
local function compute_add_loss(net, interior, boundary, lambda)
  lambda = lambda or 10.0

  -- Boundary loss
  local bc_loss = 0.0
  for _, bp in ipairs(boundary) do
    local x, y, btype = bp[1], bp[2], bp[3]
    local u_pred, v_pred = net.forward(x, y)

    if btype == "wall" then
      bc_loss = bc_loss + u_pred^2 + v_pred^2
    elseif btype == "inlet" then
      local u_exact = exact_u(x, y)
      bc_loss = bc_loss + (u_pred - u_exact)^2 + v_pred^2
    end
  end
  bc_loss = bc_loss / #boundary

  -- Physics loss
  local physics_loss = 0.0
  local continuity_loss = 0.0
  for _, pt in ipairs(interior) do
    local res_mx, res_my, res_cont = ns_residuals(net, pt[1], pt[2])
    physics_loss = physics_loss + res_mx^2 + res_my^2
    continuity_loss = continuity_loss + res_cont^2
  end
  physics_loss = physics_loss / #interior
  continuity_loss = continuity_loss / #interior

  local total = bc_loss + lambda * (physics_loss + continuity_loss)

  return total, {
    bc_loss = bc_loss,
    physics_loss = physics_loss,
    continuity_loss = continuity_loss,
    total_loss = total,
  }
end

-- ============================================================================
-- TRAINING LOOP
-- ============================================================================

local function train(mode, opts)
  opts = opts or {}
  local nh = opts.n_hidden or 8
  local epochs = opts.epochs or 500
  local lr = opts.learning_rate or 0.0005
  local n_interior = opts.n_interior or 15
  local n_boundary = opts.n_boundary or 8
  local seed = opts.seed or 42

  local params = init_params(nh, seed)
  local flat = flatten_params(params)
  local n_params = #flat

  local interior, boundary = generate_points(n_interior, n_boundary)

  print(string.format("  Mode: %s | Hidden: %d | Params: %d | Interior: %d | Boundary: %d",
    mode, nh, n_params, n_interior, #boundary))

  local best_loss = math.huge
  local best_flat = M.copy(flat)
  local loss_history = {}

  for epoch = 1, epochs do
    -- Compute loss
    local net = create_ns_network(unflatten_params(flat, nh))
    local loss, info

    if mode == "multiplicative" then
      loss, info = compute_mult_loss(net, interior, boundary)
    else
      loss, info = compute_add_loss(net, interior, boundary, 10.0)
    end

    if loss < best_loss then
      best_loss = loss
      best_flat = M.copy(flat)
    end

    loss_history[#loss_history + 1] = loss

    -- Print progress
    if epoch % 100 == 0 or epoch == 1 then
      if mode == "multiplicative" then
        print(string.format("  Epoch %4d: total=%.6f  bc=%.6f  phys=%.6f  cont=%.6f  factor=%.2f",
          epoch, info.total_loss, info.bc_loss, info.physics_loss, info.continuity_loss, info.factor))
      else
        print(string.format("  Epoch %4d: total=%.6f  bc=%.6f  phys=%.6f  cont=%.6f",
          epoch, info.total_loss, info.bc_loss, info.physics_loss, info.continuity_loss))
      end
    end

    -- Compute gradients via finite differences (parameter-space)
    local grad_eps = 1e-5
    local grads = {}

    for p = 1, n_params do
      local old = flat[p]

      flat[p] = old + grad_eps
      local net_p = create_ns_network(unflatten_params(flat, nh))
      local loss_plus
      if mode == "multiplicative" then
        loss_plus = compute_mult_loss(net_p, interior, boundary)
      else
        loss_plus = compute_add_loss(net_p, interior, boundary, 10.0)
      end

      flat[p] = old - grad_eps
      local net_m = create_ns_network(unflatten_params(flat, nh))
      local loss_minus
      if mode == "multiplicative" then
        loss_minus = compute_mult_loss(net_m, interior, boundary)
      else
        loss_minus = compute_add_loss(net_m, interior, boundary, 10.0)
      end

      flat[p] = old
      grads[p] = (loss_plus - loss_minus) / (2 * grad_eps)

      -- Gradient clipping
      if math.abs(grads[p]) > 5.0 then
        grads[p] = grads[p] > 0 and 5.0 or -5.0
      end
    end

    -- Update parameters
    for p = 1, n_params do
      flat[p] = flat[p] - lr * grads[p]
    end
  end

  -- Return best network
  local best_params = unflatten_params(best_flat, nh)
  local best_net = create_ns_network(best_params)
  return best_net, best_loss, loss_history
end

-- ============================================================================
-- EVALUATION
-- ============================================================================

local function evaluate(net, label)
  print(string.format("\n  %s — Solution at x=1.0 (mid-channel):", label))
  print(string.format("  %-8s %-14s %-14s %-14s %-12s", "y", "u_pred", "u_exact", "error", "v_pred"))
  print("  " .. string.rep("-", 66))

  local total_u_err = 0
  local total_v_err = 0
  local max_u_err = 0
  local n_eval = 0
  local max_div = 0

  for i = 0, 10 do
    local y = i / 10.0 * H
    local x = 1.0

    local u_pred, v_pred = net.forward(x, y)
    local u_ex = exact_u(x, y)
    local u_err = math.abs(u_pred - u_ex)

    total_u_err = total_u_err + u_err^2
    total_v_err = total_v_err + v_pred^2
    if u_err > max_u_err then max_u_err = u_err end
    n_eval = n_eval + 1

    -- Divergence
    local div = math.abs(net.du_dx(x, y) + net.dv_dy(x, y))
    if div > max_div then max_div = div end

    print(string.format("  %-8.1f %-14.6f %-14.6f %-14.6f %-12.6f",
      y, u_pred, u_ex, u_err, v_pred))
  end

  local rmse_u = math.sqrt(total_u_err / n_eval)
  local rmse_v = math.sqrt(total_v_err / n_eval)

  print(string.format("\n  RMSE(u): %.6f | RMSE(v): %.6f | Max u error: %.6f | Max |∇·u|: %.2e",
    rmse_u, rmse_v, max_u_err, max_div))

  return rmse_u, rmse_v, max_u_err, max_div
end

-- ============================================================================
-- MAIN
-- ============================================================================

sep("NAVIER-STOKES MULTIPLICATIVE PINN")

print(string.format([[
  Problem: 2D Poiseuille (channel) flow
  Domain:  [0, %.1f] x [0, %.1f]
  ν = %.4f,  dp/dx = %.1f
  Exact solution: u(y) = %.1f * y * (1 - y),  u_max = %.2f
  
  Constraints:
    1. X-momentum: u·∂u/∂x + v·∂u/∂y = -∂p/∂x + ν·∇²u
    2. Y-momentum: u·∂v/∂x + v·∂v/∂y = ν·∇²v
    3. Continuity: ∂u/∂x + ∂v/∂y = 0
    4. No-slip walls: u(x,0) = u(x,H) = 0
    5. Inlet profile: u(0,y) = exact parabolic
]], L, H, nu, dpdx, 1/(2*nu)*(-dpdx), u_max))

-- Train multiplicative PINN
sep("1. MULTIPLICATIVE PINN (L = L_bc × C(violation))")
local t0 = os.clock()
local mult_net, mult_loss, mult_hist = train("multiplicative", {
  n_hidden = 8,
  epochs = 500,
  learning_rate = 0.0005,
  n_interior = 15,
  n_boundary = 8,
  seed = 42,
})
local mult_time = os.clock() - t0
print(string.format("\n  Final loss: %.8f | Time: %.1fs", mult_loss, mult_time))
local mult_rmse_u, mult_rmse_v, mult_max_err, mult_max_div = evaluate(mult_net, "MULTIPLICATIVE")

-- Train additive PINN
sep("2. ADDITIVE PINN (L = L_bc + λ·L_physics)")
t0 = os.clock()
local add_net, add_loss, add_hist = train("additive", {
  n_hidden = 8,
  epochs = 500,
  learning_rate = 0.0005,
  n_interior = 15,
  n_boundary = 8,
  seed = 42,
})
local add_time = os.clock() - t0
print(string.format("\n  Final loss: %.8f | Time: %.1fs", add_loss, add_time))
local add_rmse_u, add_rmse_v, add_max_err, add_max_div = evaluate(add_net, "ADDITIVE")

-- ============================================================================
-- VERDICT
-- ============================================================================

sep("VERDICT — Navier-Stokes Poiseuille Flow")

print(string.format([[
  Metric                  Multiplicative      Additive         Winner
  ─────────────────────   ──────────────      ──────────       ──────
  Final loss              %.8f        %.8f     %s
  RMSE(u)                 %.6f            %.6f         %s
  RMSE(v)                 %.6f            %.6f         %s
  Max u error             %.6f            %.6f         %s
  Max |∇·u|              %.2e            %.2e         %s
  Time                    %.1fs                %.1fs             %s
]],
  mult_loss, add_loss,
  mult_loss < add_loss and "MULT" or "ADD",
  mult_rmse_u, add_rmse_u,
  mult_rmse_u < add_rmse_u and "MULT" or "ADD",
  mult_rmse_v, add_rmse_v,
  mult_rmse_v < add_rmse_v and "MULT" or "ADD",
  mult_max_err, add_max_err,
  mult_max_err < add_max_err and "MULT" or "ADD",
  mult_max_div, add_max_div,
  mult_max_div < add_max_div and "MULT" or "ADD",
  mult_time, add_time,
  mult_time < add_time and "MULT" or "ADD"
))

-- Improvement percentages
if add_rmse_u > 0 then
  local u_improvement = (add_rmse_u - mult_rmse_u) / add_rmse_u * 100
  print(string.format("  Velocity accuracy improvement: %.1f%%", u_improvement))
end

if add_max_div > 0 then
  local div_improvement = (add_max_div - mult_max_div) / add_max_div * 100
  print(string.format("  Incompressibility improvement: %.1f%%", div_improvement))
end

print([[

  The multiplicative PINN enforces Navier-Stokes constraints through
  L_total = L_data × C(violation), where C(v) = max(Euler_gate, exp_barrier).
  
  No gradient conflicts. No λ tuning. The constraint factor adapts
  automatically based on violation magnitude.
  
  "The partition function isn't a metaphor — it IS the physics."
]])
