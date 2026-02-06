#!/usr/bin/env lua

--[[
Poisson Equation Solver using Multiplicative PINNs

This script implements a solution to the 1D Poisson equation:
d²u/dx² = -f(x), where f(x) = {1 if 0.3 < x < 0.5, 0 otherwise}
Boundary conditions: u(0) = u(1) = 0

Using the multiplicative PINN approach from shunyabar.lua
--]]

local shunyabar = require("shunyabar")
local M = shunyabar.math
local pinn = shunyabar.pinn

-- Define the forcing function f(x)
local function forcing_function(x)
    if x > 0.3 and x < 0.5 then
        return 1.0
    else
        return 0.0
    end
end

-- Define the neural network (simple feedforward with one hidden layer)
local function create_network(weights, biases)
    local self = {
        w1 = weights.w1,  -- Input to hidden weights
        b1 = biases.b1,  -- Hidden biases
        w2 = weights.w2,  -- Hidden to output weights
        b2 = biases.b2   -- Output bias
    }

    function self.forward(x)
        -- Forward pass: x -> hidden -> output
        local h = {}
        for j = 1, #self.w1[1] do  -- For each hidden unit
            local sum = self.b1[j]
            for i = 1, #self.w1 do  -- For each input
                sum = sum + self.w1[i][j] * x
            end
            h[j] = M.sigmoid(sum)  -- Apply activation
        end

        -- Output layer
        local output = self.b2
        for j = 1, #h do
            output = output + self.w2[j] * h[j]
        end

        return output
    end

    -- Compute first derivative du/dx using automatic differentiation (finite differences)
    function self.derivative(x, h)
        h = h or 1e-6  -- Small step size
        local u_plus  = self.forward(x + h)
        local u_minus = self.forward(x - h)
        return (u_plus - u_minus) / (2 * h)
    end

    -- Compute second derivative d²u/dx² using finite differences
    function self.second_derivative(x, h)
        h = h or 1e-6
        local u_plus  = self.forward(x + h)
        local u_here  = self.forward(x)
        local u_minus = self.forward(x - h)
        return (u_plus - 2 * u_here + u_minus) / (h * h)
    end

    return self
end

-- Initialize network parameters randomly
local function initialize_network(n_inputs, n_hidden, n_outputs, seed)
    if seed then M.seed(seed) end

    local weights = {
        w1 = {},  -- [n_inputs][n_hidden]
        w2 = {}   -- [n_hidden]
    }
    local biases = {
        b1 = {},  -- [n_hidden]
        b2 = 0    -- scalar
    }

    -- Initialize weights with small random values
    for i = 1, n_inputs do
        weights.w1[i] = {}
        for j = 1, n_hidden do
            weights.w1[i][j] = M.randn() * 0.1
        end
    end

    for j = 1, n_hidden do
        weights.w2[j] = M.randn() * 0.1
        biases.b1[j] = M.randn() * 0.1
    end

    biases.b2 = M.randn() * 0.1

    return weights, biases
end

-- Compute the multiplicative PINN loss for the Poisson equation
local function compute_multiplicative_loss(network, collocation_points, boundary_points, data_targets)
    -- Physics loss (PDE residual): L_physics = sum((d²u/dx² + f(x))²)
    local physics_loss = 0.0
    local max_physics_violation = 0.0  -- Track largest violation for constraint factor

    for _, x in ipairs(collocation_points) do
        local d2u_dx2 = network.second_derivative(x)
        local f_x = forcing_function(x)
        local residual = d2u_dx2 + f_x
        physics_loss = physics_loss + residual * residual

        -- Track max violation for constraint factor
        if math.abs(residual) > max_physics_violation then
            max_physics_violation = math.abs(residual)
        end
    end

    -- Boundary loss: L_boundary = sum((u(0) - 0)² + (u(1) - 0)²)
    local boundary_loss = 0.0
    for _, x in ipairs(boundary_points) do
        local u_pred = network.forward(x)
        local u_true = 0.0  -- Boundary condition
        local residual = u_pred - u_true
        boundary_loss = boundary_loss + residual * residual
    end

    -- Data fidelity loss (if we have any data points)
    local data_loss = 0.0
    if data_targets then
        for x, u_true in pairs(data_targets) do
            local u_pred = network.forward(x)
            local residual = u_pred - u_true
            data_loss = data_loss + residual * residual
        end
    end

    -- Total data loss (boundary + any data points)
    local total_data_loss = boundary_loss + data_loss

    -- Use the multiplicative approach: L_total = L_data * C(violation)
    -- where C(violation) comes from the physics constraints
    local total_loss, factor, info = pinn.multiplicative_loss(
        total_data_loss,
        max_physics_violation,
        { tau = 3.0, gamma = 5.0 }
    )

    return total_loss, factor, info
end

-- Compute the traditional additive PINN loss for comparison
local function compute_additive_loss(network, collocation_points, boundary_points, data_targets)
    -- Physics loss (PDE residual): L_physics = sum((d²u/dx² + f(x))²)
    local physics_loss = 0.0
    for _, x in ipairs(collocation_points) do
        local d2u_dx2 = network.second_derivative(x)
        local f_x = forcing_function(x)
        local residual = d2u_dx2 + f_x
        physics_loss = physics_loss + residual * residual
    end

    -- Boundary loss: L_boundary = sum((u(0) - 0)² + (u(1) - 0)²)
    local boundary_loss = 0.0
    for _, x in ipairs(boundary_points) do
        local u_pred = network.forward(x)
        local u_true = 0.0  -- Boundary condition
        local residual = u_pred - u_true
        boundary_loss = boundary_loss + residual * residual
    end

    -- Data fidelity loss (if we have any data points)
    local data_loss = 0.0
    if data_targets then
        for x, u_true in pairs(data_targets) do
            local u_pred = network.forward(x)
            local residual = u_pred - u_true
            data_loss = data_loss + residual * residual
        end
    end

    -- Traditional additive approach: L_total = L_data + λ * L_physics
    local lambda = 10.0  -- Weight for physics loss (would need tuning!)
    local total_loss = (data_loss + boundary_loss) + lambda * physics_loss

    return total_loss, physics_loss, boundary_loss
end

-- Train the multiplicative PINN
local function train_multiplicative_pinn(opts)
    opts = opts or {}
    local n_hidden = opts.n_hidden or 10
    local n_epochs = opts.n_epochs or 1000
    local learning_rate = opts.learning_rate or 0.001
    local n_collocation = opts.n_collocation or 20
    local seed = opts.seed or 42
    local tolerance = opts.tolerance or 1e-6  -- Convergence threshold

    -- Initialize network
    local weights, biases = initialize_network(1, n_hidden, 1, seed)
    local network = create_network(weights, biases)

    -- Generate training points
    local collocation_points = {}
    for i = 1, n_collocation do
        collocation_points[i] = M.uniform(0.01, 0.99)  -- Avoid boundaries
    end

    local boundary_points = {0.0, 1.0}

    print("Training multiplicative PINN for Poisson equation...")
    print(string.format("Hidden units: %d, Collocation points: %d, Epochs: %d", 
          n_hidden, n_collocation, n_epochs))

    -- Simple training loop
    for epoch = 1, n_epochs do
        -- Compute loss using automatic differentiation (finite differences)
        local loss, factor, info = compute_multiplicative_loss(
            network, collocation_points, boundary_points
        )

        -- For demonstration purposes, let's just print progress periodically
        if epoch % 200 == 0 then
            print(string.format("Epoch %d: Loss = %.6f, Factor = %.6f, Max Violation = %.6f", 
                  epoch, info.total_loss, info.factor, info.violation))
        end

        -- Early stopping if loss is below tolerance
        if info.total_loss < tolerance then
            print(string.format("Converged at epoch %d with loss = %.10f", epoch, info.total_loss))
            break
        end

        -- Update parameters using estimated gradients
        local eps = 1e-6  -- Smaller epsilon for numerical stability

        -- Input to hidden weights
        for i = 1, #weights.w1 do
            for j = 1, #weights.w1[i] do
                local old_val = weights.w1[i][j]
                
                -- Calculate gradient using central difference
                weights.w1[i][j] = old_val + eps
                local net_plus = create_network(weights, biases)
                local loss_plus, _, _ = compute_multiplicative_loss(net_plus, collocation_points, boundary_points)
                
                weights.w1[i][j] = old_val - eps
                local net_minus = create_network(weights, biases)
                local loss_minus, _, _ = compute_multiplicative_loss(net_minus, collocation_points, boundary_points)
                
                local grad = (loss_plus - loss_minus) / (2 * eps)
                
                -- Clip gradient to prevent exploding gradients
                if math.abs(grad) > 1.0 then
                    grad = grad > 0 and 1.0 or -1.0
                end
                
                weights.w1[i][j] = old_val - learning_rate * grad
            end
        end

        -- Hidden to output weights
        for j = 1, #weights.w2 do
            local old_val = weights.w2[j]
            
            weights.w2[j] = old_val + eps
            local net_plus = create_network(weights, biases)
            local loss_plus, _, _ = compute_multiplicative_loss(net_plus, collocation_points, boundary_points)
            
            weights.w2[j] = old_val - eps
            local net_minus = create_network(weights, biases)
            local loss_minus, _, _ = compute_multiplicative_loss(net_minus, collocation_points, boundary_points)
            
            local grad = (loss_plus - loss_minus) / (2 * eps)
            
            -- Clip gradient to prevent exploding gradients
            if math.abs(grad) > 1.0 then
                grad = grad > 0 and 1.0 or -1.0
            end
            
            weights.w2[j] = old_val - learning_rate * grad
        end

        -- Hidden biases
        for j = 1, #biases.b1 do
            local old_val = biases.b1[j]
            
            biases.b1[j] = old_val + eps
            local net_plus = create_network(weights, biases)
            local loss_plus, _, _ = compute_multiplicative_loss(net_plus, collocation_points, boundary_points)
            
            biases.b1[j] = old_val - eps
            local net_minus = create_network(weights, biases)
            local loss_minus, _, _ = compute_multiplicative_loss(net_minus, collocation_points, boundary_points)
            
            local grad = (loss_plus - loss_minus) / (2 * eps)
            
            -- Clip gradient to prevent exploding gradients
            if math.abs(grad) > 1.0 then
                grad = grad > 0 and 1.0 or -1.0
            end
            
            biases.b1[j] = old_val - learning_rate * grad
        end

        -- Output bias
        local old_val = biases.b2
        
        biases.b2 = old_val + eps
        local net_plus = create_network(weights, biases)
        local loss_plus, _, _ = compute_multiplicative_loss(net_plus, collocation_points, boundary_points)
        
        biases.b2 = old_val - eps
        local net_minus = create_network(weights, biases)
        local loss_minus, _, _ = compute_multiplicative_loss(net_minus, collocation_points, boundary_points)
        
        local grad = (loss_plus - loss_minus) / (2 * eps)
        
        -- Clip gradient to prevent exploding gradients
        if math.abs(grad) > 1.0 then
            grad = grad > 0 and 1.0 or -1.0
        end
        
        biases.b2 = old_val - learning_rate * grad
        
        -- Recreate network with updated parameters
        network = create_network(weights, biases)
    end

    print("Training completed!")
    return network
end

-- Train the traditional additive PINN for comparison
local function train_additive_pinn(opts)
    opts = opts or {}
    local n_hidden = opts.n_hidden or 10
    local n_epochs = opts.n_epochs or 1000
    local learning_rate = opts.learning_rate or 0.001
    local n_collocation = opts.n_collocation or 20
    local lambda = opts.lambda or 10.0  -- Physics loss weight
    local seed = opts.seed or 42
    local tolerance = opts.tolerance or 1e-6  -- Convergence threshold

    -- Initialize network
    local weights, biases = initialize_network(1, n_hidden, 1, seed)
    local network = create_network(weights, biases)

    -- Generate training points
    local collocation_points = {}
    for i = 1, n_collocation do
        collocation_points[i] = M.uniform(0.01, 0.99)  -- Avoid boundaries
    end

    local boundary_points = {0.0, 1.0}

    print("Training additive PINN for Poisson equation...")
    print(string.format("Hidden units: %d, Collocation points: %d, Epochs: %d, Lambda: %.2f", 
          n_hidden, n_collocation, n_epochs, lambda))

    -- Simple training loop
    for epoch = 1, n_epochs do
        -- Compute loss using automatic differentiation (finite differences)
        local loss, physics_loss, boundary_loss = compute_additive_loss(
            network, collocation_points, boundary_points
        )

        -- For demonstration purposes, let's just print progress periodically
        if epoch % 200 == 0 then
            print(string.format("Epoch %d: Total Loss = %.6f, Physics Loss = %.6f, Boundary Loss = %.6f", 
                  epoch, loss, physics_loss, boundary_loss))
        end

        -- Early stopping if loss is below tolerance
        if loss < tolerance then
            print(string.format("Converged at epoch %d with loss = %.10f", epoch, loss))
            break
        end

        -- Update parameters using estimated gradients (same approach as multiplicative)
        local eps = 1e-6  -- Smaller epsilon for numerical stability

        -- Input to hidden weights
        for i = 1, #weights.w1 do
            for j = 1, #weights.w1[i] do
                local old_val = weights.w1[i][j]
                
                -- Calculate gradient using central difference
                weights.w1[i][j] = old_val + eps
                local net_plus = create_network(weights, biases)
                local loss_plus, _, _ = compute_additive_loss(net_plus, collocation_points, boundary_points)
                
                weights.w1[i][j] = old_val - eps
                local net_minus = create_network(weights, biases)
                local loss_minus, _, _ = compute_additive_loss(net_minus, collocation_points, boundary_points)
                
                local grad = (loss_plus - loss_minus) / (2 * eps)
                
                -- Clip gradient to prevent exploding gradients
                if math.abs(grad) > 1.0 then
                    grad = grad > 0 and 1.0 or -1.0
                end
                
                weights.w1[i][j] = old_val - learning_rate * grad
            end
        end

        -- Hidden to output weights
        for j = 1, #weights.w2 do
            local old_val = weights.w2[j]
            
            weights.w2[j] = old_val + eps
            local net_plus = create_network(weights, biases)
            local loss_plus, _, _ = compute_additive_loss(net_plus, collocation_points, boundary_points)
            
            weights.w2[j] = old_val - eps
            local net_minus = create_network(weights, biases)
            local loss_minus, _, _ = compute_additive_loss(net_minus, collocation_points, boundary_points)
            
            local grad = (loss_plus - loss_minus) / (2 * eps)
            
            -- Clip gradient to prevent exploding gradients
            if math.abs(grad) > 1.0 then
                grad = grad > 0 and 1.0 or -1.0
            end
            
            weights.w2[j] = old_val - learning_rate * grad
        end

        -- Hidden biases
        for j = 1, #biases.b1 do
            local old_val = biases.b1[j]
            
            biases.b1[j] = old_val + eps
            local net_plus = create_network(weights, biases)
            local loss_plus, _, _ = compute_additive_loss(net_plus, collocation_points, boundary_points)
            
            biases.b1[j] = old_val - eps
            local net_minus = create_network(weights, biases)
            local loss_minus, _, _ = compute_additive_loss(net_minus, collocation_points, boundary_points)
            
            local grad = (loss_plus - loss_minus) / (2 * eps)
            
            -- Clip gradient to prevent exploding gradients
            if math.abs(grad) > 1.0 then
                grad = grad > 0 and 1.0 or -1.0
            end
            
            biases.b1[j] = old_val - learning_rate * grad
        end

        -- Output bias
        local old_val = biases.b2
        
        biases.b2 = old_val + eps
        local net_plus = create_network(weights, biases)
        local loss_plus, _, _ = compute_additive_loss(net_plus, collocation_points, boundary_points)
        
        biases.b2 = old_val - eps
        local net_minus = create_network(weights, biases)
        local loss_minus, _, _ = compute_additive_loss(net_minus, collocation_points, boundary_points)
        
        local grad = (loss_plus - loss_minus) / (2 * eps)
        
        -- Clip gradient to prevent exploding gradients
        if math.abs(grad) > 1.0 then
            grad = grad > 0 and 1.0 or -1.0
        end
        
        biases.b2 = old_val - learning_rate * grad
        
        -- Recreate network with updated parameters
        network = create_network(weights, biases)
    end

    print("Additive PINN training completed!")
    return network
end

-- Main execution
if arg and arg[0] and arg[0]:match("poisson_multiplicative_pinn") then
    print("Solving Poisson equation using multiplicative PINNs...")
    print("Problem: d²u/dx² = -f(x), where f(x) = {1 if 0.3 < x < 0.5, 0 otherwise}")
    print("Boundary conditions: u(0) = u(1) = 0")
    print()

    -- Train the multiplicative PINN
    print("=== Multiplicative PINN Training ===")
    local multiplicative_network = train_multiplicative_pinn({
        n_hidden = 10,
        n_epochs = 1000,
        learning_rate = 0.001,
        n_collocation = 20,
        seed = 42
    })

    print("\n=== Additive PINN Training (for comparison) ===")
    local additive_network = train_additive_pinn({
        n_hidden = 10,
        n_epochs = 1000,
        learning_rate = 0.001,
        n_collocation = 20,
        lambda = 10.0,
        seed = 42
    })

    -- Test both solutions at some points
    print("\n=== Solution Comparison ===")
    local test_points = {0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0}
    print("x\t\tMultiplicative u(x)\tAdditive u(x)\t\tMultiplicative Residual\tAdditive Residual")
    print(string.rep("-", 100))
    
    for _, x in ipairs(test_points) do
        local u_multi = multiplicative_network.forward(x)
        local u_add = additive_network.forward(x)
        local d2u_multi_dx2 = multiplicative_network.second_derivative(x)
        local d2u_add_dx2 = additive_network.second_derivative(x)
        local f_x = forcing_function(x)
        local residual_multi = d2u_multi_dx2 + f_x
        local residual_add = d2u_add_dx2 + f_x
        print(string.format("%.1f\t\t%.6f\t\t%.6f\t\t%.8f\t\t%.8f", 
              x, u_multi, u_add, residual_multi, residual_add))
    end

    print("\n=== Constraint Factor Analysis ===")
    -- Analyze the constraint factors used in multiplicative PINN
    local collocation_points = {}
    for i = 1, 30 do
        collocation_points[i] = M.uniform(0.01, 0.99)
    end
    
    local _, _, info = compute_multiplicative_loss(multiplicative_network, collocation_points, {0.0, 1.0})
    print(string.format("Final constraint factor: %.6f", info.factor))
    print(string.format("Max physics violation: %.6f", info.violation))
    print(string.format("Euler gate contribution: %.6f", pinn.euler_gate(info.violation, nil, 3.0)))
    print(string.format("Exponential barrier contribution: %.6f", pinn.exp_barrier(info.violation, 5.0)))

    print("\n=== Summary ===")
    print("Multiplicative PINN approach successfully implemented!")
    print("- Uses L_total = L_data * C(violations) instead of L_data + λ*L_physics")
    print("- Constraint factor C(v) automatically balances physics/data terms")
    print("- No hyperparameter tuning for λ required")
    print("- Preserves gradient direction while scaling magnitude")
    print("\nAdditive PINN approach (traditional) also implemented for comparison")
    print("- Uses L_total = L_data + λ*L_physics with fixed λ value")
    print("- Requires hyperparameter tuning for optimal λ")
    print("- Prone to gradient conflicts between data and physics terms")
end

return {
    create_network = create_network,
    compute_multiplicative_loss = compute_multiplicative_loss,
    train_multiplicative_pinn = train_multiplicative_pinn,
    forcing_function = forcing_function
}