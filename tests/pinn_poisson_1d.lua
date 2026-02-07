#!/usr/bin/env lua

--[[
Multiplicative PINN – 1D Poisson (pinn_poisson_1d.lua)
u''(x) = -π² sin(πx)  on  x∈[-1,1]  ,  u(-1)=u(1)=0
Exact solution: u(x)=sin(πx)

Simplified Network Structure similar to poisson_multiplicative_pinn.lua
--]]

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "../src/?.lua"
local shunyabar = dofile(script_path .. "../src/shunyabar.lua")
local M = shunyabar.math
local pinn = shunyabar.pinn

-- 1. Problem Definition
local pi = math.pi
local function exact_u(x) return math.sin(pi * x) end
local function exact_f(x) return -pi * pi * math.sin(pi * x) end -- RHS f(x)

-- 2. Neural Network (Basic Single Layer)
local function create_network(weights, biases)
    local self = {
        w1 = weights.w1, -- Input -> Hidden
        b1 = biases.b1,  -- Hidden biases
        w2 = weights.w2, -- Hidden -> Output
        b2 = biases.b2   -- Output bias
    }

    function self.forward(x)
        -- Layer 1: Input -> Hidden
        local h = {}
        for j = 1, #self.w1[1] do
            local sum = self.b1[j]
            -- Since input is scalar x
            for i = 1, #self.w1 do
                sum = sum + self.w1[i][j] * x
            end
            h[j] = math.tanh(sum) -- Using tanh as activation
        end

        -- Layer 2: Hidden -> Output
        local output = self.b2
        for j = 1, #h do
            output = output + self.w2[j] * h[j]
        end

        return output
    end
    function self.second_derivative(x, h)
        h = h or 1e-4
        local u_plus  = self.forward(x + h)
        local u_here  = self.forward(x)
        local u_minus = self.forward(x - h)
        return (u_plus - 2 * u_here + u_minus) / (h * h)
    end

    return self
end
local function initialize_network(n_inputs, n_hidden, n_outputs, seed)
    if seed then M.seed(seed) end
    local weights = {
        w1 = {}, -- [input][hidden]
        w2 = {}  -- [hidden]
    }
    local biases = {
        b1 = {}, -- [hidden]
        b2 = 0.0 -- scalar
    }

    -- Xavier Initialization for Tanh
    local scale_w1 = math.sqrt(2 / (n_inputs + n_hidden))
    for i = 1, n_inputs do
        weights.w1[i] = {}
        for j = 1, n_hidden do
            weights.w1[i][j] = M.randn() * scale_w1
        end
    end

    local scale_w2 = math.sqrt(2 / (n_hidden + n_outputs))
    for j = 1, n_hidden do
        weights.w2[j] = M.randn() * scale_w2
        biases.b1[j] = 0.0
    end
    biases.b2 = 0.0

    return weights, biases
end
-- 3. Loss Function
local function compute_loss(network, collocation_points, boundary_points, opts)
    -- Physics Loss: residual = u'' - f
    local physics_loss = 0.0
    local max_violation = 0.0

    for _, x in ipairs(collocation_points) do
        local u_xx = network.second_derivative(x)
        local f = exact_f(x)
        local res = u_xx - f
        physics_loss = physics_loss + res * res
        if math.abs(res) > max_violation then max_violation = math.abs(res) end
    end
    physics_loss = physics_loss / #collocation_points

    -- Boundary Loss
    local boundary_loss = 0.0
    for _, x in ipairs(boundary_points) do
        local u_pred = network.forward(x)
        local u_true = exact_u(x) -- 0
        local err = u_pred - u_true
        boundary_loss = boundary_loss + err * err
    end

    -- Multiplicative Loss
    local total_loss, factor, info = pinn.multiplicative_loss(
        boundary_loss + 1.0, -- Add constant to ensure physics gradient is always active
        max_violation,
        opts
    )

    return total_loss, info
end
local function train(opts)
    local n_hidden = opts.n_hidden or 10
    local n_epochs = opts.n_epochs or 2000
    local lr       = opts.lr or 0.001
    
    local weights, biases = initialize_network(1, n_hidden, 1, 42)
    local network = create_network(weights, biases)

    local collocation = {}
    for i = 1, 20 do
        collocation[i] = -1 + 2 * (i-1)/19 -- linspace(-1, 1, 20)
    end
    local boundary = {-1.0, 1.0}


    print(string.format("%5s %12s %12s %12s %12s", "Ep", "Loss", "Factor", "MaxViol", "BCLoss"))
    print(string.rep("-", 60))

    for epoch = 1, n_epochs do
        local loss, info = compute_loss(network, collocation, boundary, {gamma=0.5, tau=2.0})

        if epoch % 200 == 0 or epoch == 1 then
            print(string.format("%5d %12.4e %12.4e %12.4e %12.4e", 
                epoch, loss, info.factor, info.violation, info.data_loss))
        end

        if loss < 1e-6 then break end

        -- Finite Difference Update
        local eps = 1e-4

        -- Update W1
        for i=1, #weights.w1 do for j=1, #weights.w1[i] do
            local old = weights.w1[i][j]
            weights.w1[i][j] = old + eps
            local l_plus = compute_loss(create_network(weights, biases), collocation, boundary, {gamma=0.5, tau=2.0})
            weights.w1[i][j] = old - eps
            local l_minus = compute_loss(create_network(weights, biases), collocation, boundary, {gamma=0.5, tau=2.0})
            weights.w1[i][j] = old - lr * M.clamp((l_plus - l_minus)/(2*eps), -1.0, 1.0)
        end end

        -- Update W2
        for j=1, #weights.w2 do
            local old = weights.w2[j]
            weights.w2[j] = old + eps
            local l_plus = compute_loss(create_network(weights, biases), collocation, boundary, {gamma=0.5, tau=2.0})
            weights.w2[j] = old - eps
            local l_minus = compute_loss(create_network(weights, biases), collocation, boundary, {gamma=0.5, tau=2.0})
            weights.w2[j] = old - lr * M.clamp((l_plus - l_minus)/(2*eps), -1.0, 1.0)
        end

        -- Update biases.b1
        for j=1, #biases.b1 do
            local old = biases.b1[j]
            biases.b1[j] = old + eps
            local l_plus = compute_loss(create_network(weights, biases), collocation, boundary, {gamma=0.5, tau=2.0})
            biases.b1[j] = old - eps
            local l_minus = compute_loss(create_network(weights, biases), collocation, boundary, {gamma=0.5, tau=2.0})
            biases.b1[j] = old - lr * M.clamp((l_plus - l_minus)/(2*eps), -1.0, 1.0)
        end
        
        -- Update bias.b2
        local old = biases.b2
        biases.b2 = old + eps
        local l_plus = compute_loss(create_network(weights, biases), collocation, boundary, {gamma=0.5, tau=2.0})
        biases.b2 = old - eps
        local l_minus = compute_loss(create_network(weights, biases), collocation, boundary, {gamma=0.5, tau=2.0})
        biases.b2 = old - lr * M.clamp((l_plus - l_minus)/(2*eps), -1.0, 1.0)

        network = create_network(weights, biases)
    end
    return network
end

print("\n=== Training Multiplicative PINN for u'' = -pi^2 sin(pi x) ===")
local b_net = train({n_hidden=40, n_epochs=5000, lr=0.01})

print("\n=== Final Evaluation ===")
local mse = 0.0
for i = 0, 10 do
    local x = -1 + 2*i/10
    local u_pred = b_net.forward(x)
    local u_ref  = exact_u(x)
    print(string.format("x=%5.2f  u_nn=%7.4f  u_ref=%7.4f  err=%7.4f", x, u_pred, u_ref, math.abs(u_pred - u_ref)))
    mse = mse + (u_pred - u_ref)^2
end
print(string.format("\nMSE: %.4e", mse/11))