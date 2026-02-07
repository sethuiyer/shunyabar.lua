# Benchmarks

The following table summarizes the performance of the ShunyaBar framework (including Navokoj, BAHA, Casimir) on various hard computational problems.

| Problem | Result | Detail |
| :--- | :--- | :--- |
| **Ramsey R(5,5,5)** (N=52) | **E=0 (solved)** | 2.6M constraints, 5.6s |
| **Spin Glass** (64 spins) | **4169% better than SA** | Phase transition exploited |
| **Graph Isomorphism** (N=50) | **100% success** | vs 40% for standard SA |
| **N-Queens** (N=100) | **Solved** | 19-30 seconds |
| **Number Partition** (N=100K) | **Solved** | 13.6 seconds |
| **TSP** (bayg29) | **Optimal (1610)** | TSPLIB benchmark |
| **Frustrated Lattice** (3%) | **61.2% better than SA** | 299 fractures, 2 jumps |
| **Frustrated Lattice** (30%) | **21.4% better than SA** | 299 fractures, 3 jumps |
| **3-SAT** (critical density) | **99.4% satisfaction** | 500K-1M variables |
| **Graph Coloring** (N=50) | **100% success** | 7 colors, zero violations |
| **Sudoku** (AI Escargot) | **Solved** | 729 vars, 8850 clauses |
| **SAT 2024 Industrial** | **92.57% perfect** | 4199 problems |
| **Poisson 1D** | **1,052,442× better** | vs additive (L=39.99) |
| **Navier-Stokes** | **82.6% better** | incompressibility 5.8× better |
| **Easy SAT** (below α_c) | **90% success** | Langevin crystallization |
