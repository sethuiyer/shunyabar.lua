# ShunyaBar

**The Arithmetic Manifold in a Single File**

> *"When you align your algorithm with how nature actually works, you stop fighting the problem and start flowing with it."*

`shunyabar.lua` is a standalone, zero-dependency Lua implementation of the ShunyaBar physics-inspired computation framework. It consolidates four open-source projects — **BAHA**, **Navokoj**, **Multiplicative PINN Framework**, and **Casimir SAT Solver** — into a single coherent module.

| Project                 | Problem Type                               | Key Mechanism                                        |
| ----------------------- | ------------------------------------------ | ---------------------------------------------------- |
| **BAHA**                | Discrete optimization (SAT, coloring, TSP) | Lambert-W branch jumping when landscape fractures    |
| **Navokoj**             | Constraint satisfaction                    | Prime-weighted geometric flow in continuous space    |
| **Multiplicative PINN** | Physics-informed neural networks           | Multiplicative (not additive) constraint enforcement |
| **Casimir SAT**         | Boolean satisfiability                     | Langevin dynamics with quantum-inspired noise        |


## The Core Thesis

Hard problems have phase transitions. Phase transitions have spectral signatures. Spectral signatures can be detected, navigated, and exploited through prime-weighted operators and multiplicative dynamics.

Every project begins with the same object — the **partition function**:

$$Z(\beta) = \sum_{s \in \mathcal{S}} e^{-\beta E(s)}$$

where $\mathcal{S}$ is the state space, $E(s)$ is the energy of state $s$, and $\beta$ is inverse temperature. This single function encodes everything about the system: its ground states, its metastable configurations, its phase transitions.

The four projects use $Z(\beta)$ differently:

| Project | Role of $Z(\beta)$ |
|---------|---------------------|
| **BAHA** | Monitors $\rho = \|d/d\beta \log Z\|$ to detect landscape fractures |
| **Navokoj** | Defines energy $E = -w \cdot \log P(\text{clause satisfied})$ for geometric flow |
| **Multiplicative PINN** | Constraint factor $C(v) \sim e^{\gamma v}$ is a local partition function |
| **Casimir SAT** | Langevin dynamics samples from $P(s) \propto e^{-\beta E(s)}$ |

---

Read the math and the code at this interactive blog: [Shunyabar](https://shunyabar.lovable.app/)

## Test Suite

The project includes a comprehensive test suite with **48 tests** across **5 test files**, achieving **100% pass rate**. Tests cover unit testing, integration testing, stress testing, and edge cases.

### Running Tests

```bash
# Run all tests
cd tests && lua run_all_tests.lua

# Run individual test suites
lua test_casimir.lua          # Casimir solver unit tests
lua test_walksat_unit.lua     # Walksat solver unit tests  
lua test_edge_cases.lua       # Edge case tests
lua test_hybrid.lua           # Integration tests
lua test_stress.lua           # Stress tests (takes ~3 minutes)
```

### Test Files

| File | Tests | Purpose | Runtime | Coverage |
|------|-------|---------|---------|----------|
| **test_framework.lua** | — | Lightweight testing framework with suite management, 12 assertion types, and result reporting | — | Testing infrastructure |
| **test_casimir.lua** | 10 | Unit tests for Casimir solver: energy minimization, convergence, gradients, annealing, verification | <1s | Casimir solver mechanics |
| **test_walksat_unit.lua** | 12 | Unit tests for Walksat solver: flipping, noise, tries, verification, best solution tracking | <1s | Walksat solver mechanics |
| **test_edge_cases.lua** | 14 | Boundary conditions: empty problems, tautologies, contradictions, UNSAT, Horn clauses, sparse variables | <1s | Edge case handling |
| **test_hybrid.lua** | 4 | Integration tests: simple 3-SAT, random 3-SAT, hard 3-SAT (N=100), AI Escargot Sudoku | ~60s | Hybrid solver (Casimir + Walksat) |
| **test_stress.lua** | 8 | Hard instances: N=100/200 3-SAT, AI Escargot, 8/12-Queens, over-constrained, UNSAT, consistency | ~180s | Performance on challenging problems |
| **run_all_tests.lua** | — | Master test runner: loads all suites, executes tests, aggregates results, generates summary | Variable | Test orchestration |

### Test Coverage by Problem Type

| Problem Type | Variables | Clauses | Test Files | Purpose |
|--------------|-----------|---------|------------|---------|
| **Trivial** | 0-3 | 0-3 | Unit tests, Edge cases | Verify correctness of basic mechanics |
| **Simple** | 6-20 | 5-85 | Unit tests, Integration | Validate solver on easy instances |
| **Medium** | 30-64 | 127-426 | Integration, Stress | Test scaling behavior |
| **Hard** | 100-200 | 426-852 | Stress | Challenge solver at phase transition (ratio=4.26) |
| **Real-World** | 729 | 8850 | Integration, Stress | AI Escargot Sudoku (world's hardest) |
| **Structured** | 64-144 | Many | Stress | N-Queens constraint satisfaction |
| **UNSAT** | 1-50 | 2-300 | Edge cases, Stress | Test graceful degradation |

## Papers

All open access on Zenodo:

- [Multiplicative Calculus for Hardness Detection](https://doi.org/10.5281/zenodo.14631250)
- [ShunyaBar: Spectral-Arithmetic Phase Transitions](https://doi.org/10.5281/zenodo.14655513)
- [Solving SAT with Quantum Vacuum Dynamics](https://doi.org/10.5281/zenodo.14687449)
- [Spectral-Multiplicative Optimization Framework](https://doi.org/10.5281/zenodo.14631250)

## Repositories

- [baha](https://github.com/sethuiyer/baha) — Branch-Aware Holonomy Annealing
- [navokoj](https://github.com/sethuiyer/navokoj) — Physics-inspired constraint satisfaction
- [multiplicative-pinn-framework](https://github.com/sethuiyer/multiplicative-pinn-framework) — PDE solving with multiplicative constraints
- [casimir-sat-solver](https://github.com/sethuiyer/casimir-sat-solver) — Quantum-inspired SAT solving

## License

Apache 2.0

## Author

**Sethu Iyer** — [sethuiyer95@gmail.com](mailto:sethuiyer95@gmail.com)
