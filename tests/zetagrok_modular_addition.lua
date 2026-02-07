-- Neural Network Training with ZetaGrok Loss (REAL TRAINING)
-- Task: Modular Addition (classic grokking problem)
-- Author: Sethu Iyer | License: Apache 2.0

local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
local S = dofile(script_path .. "../src/shunyabar.lua")
local M = S.math
local zg = S.zetagrok

print([[
================================================================================
  ZETAGROK NEURAL NETWORK TRAINING (REAL)
  Task: Modular Addition (a + b) mod p
================================================================================
]])

M.seed(42)

-- ============================================================================
-- PROBLEM: Modular Addition (simplified: p=13 for faster training)
-- ============================================================================

local p = 7  -- Tiny modulus for purely fast demo

print(string.format("\nTask: Learn (a + b) mod %d", p))
print(string.format("Dataset size: %d examples\n", p * p))

-- Generate dataset
local function generate_dataset()
  local data = {}
  for a = 0, p - 1 do
    for b = 0, p - 1 do
      data[#data + 1] = {
        input = {a / p, b / p},  -- Normalize to [0,1]
        output = (a + b) % p
      }
    end
  end
  return data
end

local full_data = generate_dataset()

-- Train/test split (50/50)
for i = #full_data, 2, -1 do
  local j = math.random(i)
  full_data[i], full_data[j] = full_data[j], full_data[i]
end

local n_train = math.floor(#full_data * 0.5)
local train_data, test_data = {}, {}
for i = 1, n_train do train_data[i] = full_data[i] end
for i = n_train + 1, #full_data do test_data[#test_data + 1] = full_data[i] end

print(string.format("Train: %d | Test: %d", #train_data, #test_data))

-- ============================================================================
-- NEURAL NETWORK (3-layer with square hidden-to-hidden for spectral entropy)
-- ============================================================================

local hidden_dim = 16
print(string.format("Network: 2 → %d → %d → %d\n", hidden_dim, hidden_dim, p))

local function init_network()
  local net = {
    W1 = M.matrix(2, hidden_dim),
    b1 = M.zeros(hidden_dim),
    W2 = M.matrix(hidden_dim, hidden_dim),  -- Square! For spectral entropy
    b2 = M.zeros(hidden_dim),
    W3 = M.matrix(hidden_dim, p),
    b3 = M.zeros(p)
  }
  -- Xavier Initialization
  for i = 1, 2 do for j = 1, hidden_dim do net.W1[i][j] = M.randn() * math.sqrt(2/2) end end
  for i = 1, hidden_dim do for j = 1, hidden_dim do net.W2[i][j] = M.randn() * math.sqrt(2/hidden_dim) end end
  for i = 1, hidden_dim do for j = 1, p do net.W3[i][j] = M.randn() * math.sqrt(2/hidden_dim) end end
  return net
end

-- Forward pass
local function forward(net, x)
  -- Layer 1
  local h1 = {}
  for j = 1, hidden_dim do
    local z = net.b1[j]
    for i = 1, 2 do z = z + x[i] * net.W1[i][j] end
    h1[j] = math.tanh(z)
  end
  
  -- Layer 2 (square W2 - this is where we track spectral entropy!)
  local h2 = {}
  for j = 1, hidden_dim do
    local z = net.b2[j]
    for i = 1, hidden_dim do z = z + h1[i] * net.W2[i][j] end
    h2[j] = math.tanh(z)
  end
  
  -- Layer 3 (output)
  local logits = {}
  for j = 1, p do
    local z = net.b3[j]
    for i = 1, hidden_dim do z = z + h2[i] * net.W3[i][j] end
    logits[j] = z
  end
  
  -- Softmax
  local max_l = logits[1]
  for j = 2, p do if logits[j] > max_l then max_l = logits[j] end end
  
  local probs, sum = {}, 0
  for j = 1, p do
    probs[j] = math.exp(logits[j] - max_l)
    sum = sum + probs[j]
  end
  for j = 1, p do probs[j] = probs[j] / sum end
  
  return probs
end

-- Loss and accuracy
local function cross_entropy(probs, target)
  return -math.log(probs[target + 1] + 1e-10)
end

local function evaluate(net, dataset)
  local correct, total_loss = 0, 0
  for _, ex in ipairs(dataset) do
    local probs = forward(net, ex.input)
    local pred = 1
    for j = 2, p do if probs[j] > probs[pred] then pred = j end end
    if pred - 1 == ex.output then correct = correct + 1 end
    total_loss = total_loss + cross_entropy(probs, ex.output)
  end
  return correct / #dataset, total_loss / #dataset
end

-- ============================================================================
-- TRAINING WITH ZETAGROK LOSS
-- ============================================================================

local net = init_network()
local lr = 0.2
local epochs = 500
local gamma = 1.5

print(string.rep("=", 80))
print("TRAINING")
print(string.rep("=", 80))
print(string.format("Epochs: %d | LR: %.2f | γ: %.1f\n", epochs, lr, gamma))

print("Epoch  Train Acc  Test Acc   Task Loss  S_spec    Twist     Total Loss")
print(string.rep("-", 80))

for epoch = 1, epochs do
  -- Shuffle training data
  for i = #train_data, 2, -1 do
    local j = math.random(i)
    train_data[i], train_data[j] = train_data[j], train_data[i]
  end
  
  -- Batch Gradient Descent with Finite Differences
  -- (Much faster than SGD given the expensive gradient calculation)
  
  -- 1. Compute baseline loss over entire training set
  local epoch_loss = 0
  for _, ex in ipairs(train_data) do
    local probs = forward(net, ex.input)
    epoch_loss = epoch_loss + cross_entropy(probs, ex.output)
  end
  epoch_loss = epoch_loss / #train_data
  
  -- 2. Update W2 (Hidden-to-Hidden) using finite differences on BATCH loss
  local eps = 1e-4
  local momentum = 0.9
  if not net.W2_velocity then net.W2_velocity = M.matrix(hidden_dim, hidden_dim) end
  
  for i = 1, hidden_dim do
    for j = 1, hidden_dim do
      local old_val = net.W2[i][j]
      
      -- Perturb +eps
      net.W2[i][j] = old_val + eps
      local loss_plus = 0
      for _, ex in ipairs(train_data) do
        local probs = forward(net, ex.input)
        loss_plus = loss_plus + cross_entropy(probs, ex.output)
      end
      loss_plus = loss_plus / #train_data
      local total_plus, _ = zg.zetagrok_loss(loss_plus, net.W2, {K=3, gamma=gamma, power_iters=3})
      
      -- Perturb -eps
      net.W2[i][j] = old_val - eps
      local loss_minus = 0
      for _, ex in ipairs(train_data) do
        local probs = forward(net, ex.input)
        loss_minus = loss_minus + cross_entropy(probs, ex.output)
      end
      loss_minus = loss_minus / #train_data
      local total_minus, _ = zg.zetagrok_loss(loss_minus, net.W2, {K=3, gamma=gamma, power_iters=3})
      
      -- Restore
      net.W2[i][j] = old_val
      
      -- Compute gradient
      local grad = (total_plus - total_minus) / (2 * eps)
      
      -- Gradient clipping
      if math.abs(grad) > 1.0 then grad = grad > 0 and 1.0 or -1.0 end
      
      -- Update with Momentum
      net.W2_velocity[i][j] = momentum * net.W2_velocity[i][j] - lr * grad
      net.W2[i][j] = net.W2[i][j] + net.W2_velocity[i][j]
    end
  end
  
  -- Also update W1 and W3 using standard backprop (approx) or just random walk?
  -- For this demo, let's just do a simple random walk / annealing on W1/W3 
  -- or a very rough finite difference on a random subset to save time?
  -- Actually, let's just apply the same batch FD approach to W1 and W3 but only for TASK loss (no spectral term needed)
  -- To keep it feasible, we'll just do W2 updates as that's where the "grokking" (spectral entropy) happens.
  -- The other layers can stay fixed or move slowly.
  -- Let's add a small random noise to W1/W3 to simulate "drifting" if we don't train them.
  -- BETTER: Train them too! It's only 2*16 + 16*11 = 32 + 176 = 208 more weights.
  -- Total 256 (W2) + 208 = 464 weights. Batch update is fine.
  
  -- Update W3 (Output Layer)
  if not net.W3_velocity then net.W3_velocity = M.matrix(hidden_dim, p) end
  for i = 1, hidden_dim do
    for j = 1, p do
       local old = net.W3[i][j]
       net.W3[i][j] = old + eps
       local l_plus = 0
       for _, ex in ipairs(train_data) do l_plus = l_plus + cross_entropy(forward(net, ex.input), ex.output) end
       
       net.W3[i][j] = old - eps
       local l_minus = 0
       for _, ex in ipairs(train_data) do l_minus = l_minus + cross_entropy(forward(net, ex.input), ex.output) end
       
       net.W3[i][j] = old
       local grad = (l_plus - l_minus) / (2 * eps * #train_data)
       if math.abs(grad) > 1.0 then grad = grad > 0 and 1.0 or -1.0 end
       
       net.W3_velocity[i][j] = momentum * net.W3_velocity[i][j] - lr * grad
       net.W3[i][j] = net.W3[i][j] + net.W3_velocity[i][j]
    end
  end

  -- Update W1 (Input Layer)
  if not net.W1_velocity then net.W1_velocity = M.matrix(2, hidden_dim) end
  for i = 1, 2 do
    for j = 1, hidden_dim do
       local old = net.W1[i][j]
       net.W1[i][j] = old + eps
       local l_plus = 0
       for _, ex in ipairs(train_data) do l_plus = l_plus + cross_entropy(forward(net, ex.input), ex.output) end
       
       net.W1[i][j] = old - eps
       local l_minus = 0
       for _, ex in ipairs(train_data) do l_minus = l_minus + cross_entropy(forward(net, ex.input), ex.output) end
       
       net.W1[i][j] = old
       local grad = (l_plus - l_minus) / (2 * eps * #train_data)
       if math.abs(grad) > 1.0 then grad = grad > 0 and 1.0 or -1.0 end
       
       net.W1_velocity[i][j] = momentum * net.W1_velocity[i][j] - lr * grad
       net.W1[i][j] = net.W1[i][j] + net.W1_velocity[i][j]
    end
  end
  
  -- Evaluate every 5 epochs
  if epoch % 5 == 0 or epoch == 1 then
    local train_acc, train_loss = evaluate(net, train_data)
    local test_acc, test_loss = evaluate(net, test_data)
    
    -- Compute spectral metrics
    local entropy, _ = zg.spectral_entropy(net.W2, 3, 5)
    local _, metrics = zg.zetagrok_loss(1.0, net.W2, {K=3, gamma=gamma})
    
    print(string.format("%5d  %9.1f%%  %8.1f%%  %10.4f  %8.4f  %8.2fx  %11.4f",
      epoch, train_acc * 100, test_acc * 100, train_loss, entropy, 
      metrics.twist_factor, train_loss * metrics.twist_factor))
  end
end

-- ============================================================================
-- RESULTS
-- ============================================================================

print("\n" .. string.rep("=", 80))
print("RESULTS")
print(string.rep("=", 80))

local final_train_acc, _ = evaluate(net, train_data)
local final_test_acc, _ = evaluate(net, test_data)

print(string.format("\nFinal Train Accuracy: %.1f%%", final_train_acc * 100))
print(string.format("Final Test Accuracy:  %.1f%%", final_test_acc * 100))
print(string.format("Generalization Gap:   %.1f%%", (final_train_acc - final_test_acc) * 100))

if final_test_acc > 0.9 then
  print("\n✓ GROKKING ACHIEVED!")
elseif final_test_acc > 0.7 then
  print("\n⚠ PARTIAL GROKKING (may need more epochs)")
else
  print("\n✗ MEMORIZATION ONLY")
end

print("\nNote: This is a REAL neural network training with ZetaGrok loss!")
print("The spectral entropy of W2 drives the multiplicative twist factor.")
print("\n" .. string.rep("=", 80))
