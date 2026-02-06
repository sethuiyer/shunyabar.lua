# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Common commands

The project is pure Lua (no build step or external deps). Run scripts with a Lua 5.1+ interpreter.

- Run the main demo/self-test:
  - `lua shunyabar.lua`
- Run stress tests (Sudoku, 8-Queens, SAT race, BAHA vs SA, ZetaGrok):
  - `lua mindbender.lua`
- Run the BAHA vs SA TSP benchmark:
  - `lua tsp_baha.lua`

## High-level architecture

This repo is intentionally minimal: the entire framework lives in a single file.

- `shunyabar.lua` is the core library and entry point. It builds a top-level `shunyabar` table that exposes:
  - `shunyabar.math`: shared math utilities (randomness, primes, softmax, matrices, etc.).
  - `shunyabar.baha`: Branch-Aware Holonomy Annealing, Lambert-W branches, fracture detector, and SA baseline.
  - `shunyabar.navokoj`: prime-weighted geometric flow solvers for SAT, graph coloring, and job scheduling, plus encoders/validators.
  - `shunyabar.pinn`: multiplicative constraint enforcement (Euler gate + barrier), prime weights, Euler product.
  - `shunyabar.casimir`: Langevin SAT solver using logit-space dynamics and spectral adjacency.
  - `shunyabar.zetagrok`: spectral entropy and multiplicative “twist” loss.
  - `shunyabar.demo()`: embedded demo/self-test; auto-runs when `shunyabar.lua` is executed directly.

- `mindbender.lua` and `tsp_baha.lua` are standalone scripts that `dofile("shunyabar.lua")` and exercise multiple subsystems end-to-end. They are the canonical examples for how modules are used together and for performance/regression checks.

## Core thesis

Hard computational problems exhibit phase transitions detectable via spectral signatures. These signatures can be detected, navigated, and exploited through:
1. **Prime-weighted operators:** Break symmetry, create spectral gap hierarchies
2. **Multiplicative dynamics:** Preserve gradient direction, avoid conflicts
3. **Partition functions:** Unify all algorithms under Z(β) = Σ_s exp(-β·E(s))
4. **Euler product structure:** Constraints compose factorially (inspired by ζ(s) = ∏_p 1/(1-p^(-s)))

## The five algorithms

### 1. BAHA — Branch-Aware Holonomy Annealing (shunyabar.baha)

**Problem:** Simulated annealing fails on fractured landscapes (disconnected basins at phase transitions).

**Solution:** Detect fractures via ρ(β) = |d/dβ log Z(β)| and jump between basins using Lambert-W branch enumeration.

**Key components:**
- **Lambert-W solver** (lines 219-263): Halley iteration computes principal W₀(z) and secondary W₋₁(z) branches
- **FractureDetector** (lines 269-300): Tracks β-history and log Z history; flags when ρ > threshold (default 1.5)
- **BranchAwareOptimizer** (lines 308-490): Estimates log Z via Monte-Carlo, enumerates branches, scores and jumps selectively

**Key insight:** Fracture selectivity. Detected 2972 fractures in 10 trials but jumped only 13 times (0.4% rate).

**Results:** 4169% better than SA on Spin Glass (64 spins), 100% vs 40% on Graph Isomorphism (N=50), 10/10 wins on TSP bayg29 (avg gap 0.86% vs SA 8.94%).

### 2. NAVOKOJ — Prime-Weighted Geometric Flow (shunyabar.navokoj)

**Problem:** Constraint satisfaction requires discrete search trees with backtracking.

**Solution:** Reformulate as continuous energy minimization using prime weights to break symmetry.

**Architecture (three sectors):**
- **Arithmetic:** Each constraint c ← prime p_c; weight w_c = 1/log(p_c). Smaller primes dominate; creates spectral gap hierarchy.
- **Geometric:** State x_i ∈ [0,1] per variable, initialized x_i = 0.5 + randn(0.001), clamped to (0.001, 0.999)
- **Dynamic:** Adiabatic cooling β(t) = t/T_max · β_max; gradient descent on P(clause unsatisfied) = ∏(1 - P(literal))

**Problem encoders:**
- `solve_sat()`: Literal clauses (positive=x, negative=¬x)
- `encode_n_queens(n)`: n² variables; rows/columns/diagonals uniqueness constraints
- `encode_sudoku(grid_str)`: 729 variables; 8850 clauses for uniqueness + clues
- `solve_qstate()`: Graph coloring via softmax flow; repulsive forces between adjacent nodes
- `schedule_jobs()`: Job scheduling on temporal manifold; precedence springs, conflict repulsion

**Verification:** `verify_solution()`, `verify_qstate()`, `verify_schedule()`

**Results:** 99.4% satisfaction on 3-SAT (critical density, 500K-1M vars), 100% on graph coloring (50 nodes), solved AI Escargot Sudoku at 99.84% (729 vars, 8850 clauses, ~19 seconds).

### 3. PINN — Multiplicative Constraint Enforcement (shunyabar.pinn)

**Problem:** Additive penalties (L_total = L_data + λL_physics) create gradient conflicts when ∇L_data and ∇L_physics point opposite.

**Solution:** Multiplicative loss preserves gradient direction: L_total = L_data · C(v), where C(v) = max(G(v), B(v))

**Constraint factor mechanisms:**
- **Euler gate** G(v) = ∏_p (1 - p^(-τ·v)) using primes {2,3,5,7,11}, τ=3. Attenuates near v=0; inspired by Riemann zeta ζ(s) = ∏_p 1/(1-p^(-s))
- **Exponential barrier** B(v) = exp(γ·v), γ=5. Amplifies high violations.

**Log-space gradient:** ∇log(L_total) = ∇log(L_data) + γ∇S_spec. Clean factorization; no conflict.

**Prime weights:** w_c = 1/log(p_c) creates irreducible hierarchy (no constraint combo equals another).

**Euler product:** `euler_product_zeta(s, n_primes)` computes ζ(s) ≈ ∏_p 1/(1-p^(-s)). Validated: ζ(2.0) ≈ 1.6386 (true π²/6 ≈ 1.6449).

**Results:** Navier-Stokes residual 99.64% reduction (0.0028→1×10⁻⁵), 0% monotonicity violations (from 31.31%), incompressibility <1×10⁻⁹, inference 745,919× faster than CFD.

### 4. CASIMIR SAT — Quantum-Inspired Langevin Dynamics (shunyabar.casimir)

**Problem:** Discrete SAT solving gets stuck in local minima.

**Solution:** Continuous Langevin dynamics with thermal noise and logit-space stabilization.

**Physics model:** Variables are probabilities x_i ∈ [0,1]. Dynamics: dx/dt = -η∇E + √(2T)ξ

**Energy:** E = Σ_c (1 - s_c)², where s_c = 1 - ∏_ℓ∈c (1 - x_ℓ) is fractional clause satisfaction. Smooth, differentiable.

**Logit-space accumulation** (line 1186): Internal state u_i accumulates gradients; projected x_i = σ(β·u_i). Avoids saturation.

**Annealing schedules:**
- Temperature: T = 2.0/log(1 + step·0.05) — decays as 1/log(step)
- β = 1 + step·0.01 — increases linearly for crystallization
- Correlation length: multiplied by 0.995 per step

**Convergence:** Energy < 1e-3 AND all x_i ∈ {0.1, 0.9}

**Results:** 90% success on easy SAT (below critical density), 100% on test (5 vars, 7 clauses, converged in 57 steps).

### 5. ZETAGROK — Spectral Entropy × Multiplicative Twist (shunyabar.zetagrok)

**Problem:** Neural networks transition from memorization (noisy spectrum) to grokking (clean spectrum) with no explicit mechanism.

**Solution:** Multiplicative twist loss proportional to spectral disorder: L_total = L_task · exp(γ·S_spec)

**Spectral entropy:** S_spec = E_tail / E_total = (E_total - E_topk) / E_total
- E_total = ||A||_F² = Σ A_ij² (Frobenius norm squared)
- E_topk = Σ λ_j² (top K eigenvalue energy via power iteration)
- E_tail = E_total - E_topk (remaining energy)

**Power iteration** (lines 1271-1338): K random vectors, Modified Gram-Schmidt orthogonalization, Rayleigh quotients λ_j = q_j^T·A·q_j. Typically K=3, 5-10 iterations.

**Twist mechanism:** High entropy (memorizing)→large twist→violent gradients→explore. Low entropy (grokking)→twist≈1→stable gradients→exploit.

**Results:** Memorizing matrix (16×16 random): entropy 0.9427, twist 6.59×, loss 3.29. Grokking matrix (rank-2): entropy 0.00003, twist 1.00×, loss 0.50. Entropy ratio: 32,493×. Loss inflation: 6.6×.

## Mathematical unification

All algorithms use partition function Z(β) = Σ_s exp(-β·E(s)):
- **BAHA:** Monitor ρ = |d/dβ log Z| for phase transitions
- **Navokoj:** Energy E = -w·log P(clause satisfied) on geometric manifold
- **PINN:** Constraint factor C(v) ~ exp(γ·v) is local partition function
- **Casimir:** Langevin samples from P(s) ∝ exp(-β·E(s))
- **ZetaGrok:** Spectral disorder induces twist in loss landscape

Euler product (ζ(s) = ∏_p 1/(1-p^(-s))) connects all five:
- **Irreducibility:** Each constraint has unique prime (no combos)
- **Hierarchy:** Smaller primes dominate, larger refine
- **Factorization:** Constraints compose multiplicatively (avoids gradient conflicts)

## Numerical stability patterns

1. **Log-sum-exp trick** (lines 107-119): Avoid overflow in partition function estimation
2. **Sigmoid with branching** (lines 77-85): Branches to avoid exp(large_positive)
3. **Clamp to avoid saturation** (lines 627, 1010): Prevent x_i from hitting exactly 0 or 1
4. **Epsilon guards** (lines 614-615, 1162-1165): Avoid division by zero in gradients

## Performance notes

**Time complexity (Navokoj SAT):**
- Per step: O(n_vars × n_clauses)
- Total: O(steps × n_vars × n_clauses)
- Example: 729 vars, 8850 clauses, 5000 steps ≈ 32 billion ops; ~19 seconds

**Key benchmarks:**
- Sudoku AI Escargot: 99.84% satisfaction in 19 seconds
- 8-Queens: 100% in <1 second
- 3-SAT critical: Navokoj 100% in 0.235s, Casimir 100% in 0.014s (17× faster)
- TSP bayg29: BAHA 10/10 wins (avg gap 0.86%), SA 0/10 (avg gap 8.94%)

## Testing

**Self-test:**
```bash
lua shunyabar.lua
```
Tests all 6 modules with Lambert-W, Euler gate, small SAT, graph coloring, job scheduling, Casimir, spectral entropy.

**Stress tests:**
```bash
lua mindbender.lua
```
1. AI Escargot Sudoku (729 vars, 8850 clauses)
2. 8-Queens (64 vars, 728 clauses)
3. Critical 3-SAT race at phase transition (Navokoj vs Casimir)
4. BAHA vs SA comparison (dense 12-node graph, 10 trials)
5. ZetaGrok spectral analysis (memorizing vs grokking matrices)

**TSP benchmark:**
```bash
lua tsp_baha.lua
```
bayg29: 29 cities, known optimal 1610, 2-opt neighborhood (~378 neighbors), 10-trial race.
