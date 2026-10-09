# COP5612 / COP5615 - Project 2: Gossip Simulator
**Distributed Operating System Principles**  
**Instructor:** Prof. Alin Dobra  

---

## 1. Team Members
- **Danush** (UFID: Contact via eLearning / Course Portal)
- Team / Group Submission: Distributed Systems Group

---

## 2. What is Working
Everything specified in the project requirements and bonus specifications is fully implemented, rigorously tested, and working:

1. **Gossip Algorithm for Information Propagation**:
   - Spawns concurrent Erlang actors representing network nodes.
   - Initialized via a rumor fact sent by the coordinator.
   - Actors spread rumors to randomly chosen neighbors upon receive and via periodic asynchronous ticks.
   - Actors keep track of received rumors and terminate/stop transmitting once they have heard the rumor 10 times.
   - Convergence detection: 100% of network nodes receive the rumor fact.

2. **Push-Sum Algorithm for Aggregate Computation**:
   - Each actor $A_i$ maintains state $(s_i, w_i)$ initialized to $s_i = i$ and $w_i = 1.0$.
   - Coordinated start via a trigger from the master process.
   - Upon receiving $(s_{in}, w_{in})$, actors update their values, retain half, and send half to a randomly selected neighbor.
   - Local estimate computed as $s / w$.
   - Termination condition: an actor terminates when its ratio $s / w$ changes by less than $10^{-10}$ across 3 consecutive rounds.
   - Relaying mechanism ensures global sum and weight conservation throughout the network.

3. **All Four Topologies**:
   - **Full Network (`full`)**: All-to-all connectivity ($K_N$), $O(1)$ diameter.
   - **2D Grid (`2D`)**: Square lattice ($S \times S$), $S = \lceil\sqrt{N}\rceil$, 4-neighborhood (von Neumann). Automatically rounds $N$ up to the nearest perfect square.
   - **Line (`line`)**: 1D sequential arrangement, 2 neighbors (left and right), $O(N)$ diameter.
   - **Imperfect 2D Grid (`imp2D`)**: 2D grid augmented with one random shortcut connection per node (Watts-Strogatz small-world model).

4. **Accurate Timing Measurement**:
   - Running time is measured using `erlang:monotonic_time(microsecond)` as required by the assignment specification:
     ```erlang
     measure_running_time(Fun) ->
         Start = erlang:monotonic_time(microsecond),
         Res = Fun(),
         End = erlang:monotonic_time(microsecond),
         Duration = End - Start,
         {Duration, Res}.
     ```

5. **Bonus Component (30% Credit)**:
   - **Node Crash Failure Model**: Parameterized failure rate $P_f \in [0.0, 0.5]$ simulates permanent node crashes. Evaluates percolation phase transitions and network partitioning.
   - **Transient Connection / Packet Loss Model**: Parameterized packet drop rate $P_d \in [0.0, 0.8]$ simulates lossy communication links. Demonstrates epidemic self-healing dynamics.

---

## 3. Largest Networks Handled

The simulator was scaled up to tens of thousands of concurrent Erlang actors. Below are the largest network sizes successfully tested and converged:

| Topology | Algorithm | Largest Network ($N$) | Convergence Time | Key Observations |
| :--- | :--- | :--- | :--- | :--- |
| **Full Network** | Gossip | **10,000 nodes** | 463.53 ms | Complete connectivity; dense message mixing |
| **Imperfect 2D** | Gossip | **10,000 nodes** | 74.85 ms | Fastest at scale; small-world shortcuts |
| **2D Grid** | Gossip | **10,000 nodes** | 122.16 ms | 100 × 100 lattice; uniform spatial wave |
| **Line** | Gossip | **5,000 nodes** | 16,835.07 ms | $O(N)$ diameter serial wave propagation |
| **Full Network** | Push-Sum | **5,000 nodes** | 268.25 ms | Fast mixing; ratio converges to $(N+1)/2$ |
| **Imperfect 2D** | Push-Sum | **5,041 nodes** | 414.17 ms | Shortcuts speed up aggregate diffusion |
| **2D Grid** | Push-Sum | **5,041 nodes** | 4,563.29 ms | 71 × 71 lattice; spatial mixing latency |
| **Line** | Push-Sum | **2,000 nodes** | 5,839.53 ms | High mixing time across linear diameter |

---

## 4. How to Run the Code

### Compilation
Compile the Erlang source files using `erlc`:
```bash
erlc project2.erl
erlc project2_bonus.erl
```

### Running Main Project (`project2`)
The invocation format strictly follows the assignment requirements:
```bash
project2 numNodes topology algorithm
```

#### Examples:
- **Windows (Command Prompt / PowerShell)**:
  ```powershell
  .\project2.bat 1000 2D gossip
  .\project2.bat 1000 full push-sum
  ```
  Or via `escript`:
  ```powershell
  escript project2.erl 1000 2D gossip
  escript project2.erl 1000 full push-sum
  ```

- **Linux / macOS**:
  ```bash
  chmod +x project2
  ./project2 1000 2D gossip
  ./project2 1000 full push-sum
  ```

- **From Erlang Shell**:
  ```bash
  erl -noshell -pa . -eval 'project2:main(["1000", "2D", "gossip"])' -s init stop
  ```

### Running Bonus Project (`project2-bonus`)
Invocation format:
```bash
project2_bonus numNodes topology algorithm [failureRate] [failureType]
```
Where:
- `failureRate`: Float between `0.0` and `1.0` (e.g. `0.1` for 10% failure, default: `0.1`).
- `failureType`: `node` (node crash failures) or `connection` (packet loss, default: `node`).

#### Examples:
- **10% Node Failures on 2D Grid**:
  ```powershell
  escript project2_bonus.erl 196 2D gossip 0.1 node
  ```
- **30% Message Loss on Imperfect 2D Grid**:
  ```powershell
  escript project2_bonus.erl 196 imp2D gossip 0.3 connection
  ```
- **Linux / macOS**:
  ```bash
  chmod +x project2_bonus
  ./project2_bonus 196 imp2D gossip 0.1 node
  ```

---

## 5. Submission Package Contents

- **`project2.zip` / `project2.tgz`**: Source code for the main project (`project2.erl`, `project2`, `project2.bat`).
- **`project2-bonus.zip` / `project2-bonus.tgz`**: Source code for the bonus project (`project2_bonus.erl`, `project2_bonus`, `project2_bonus.bat`).
- **`Report.pdf`**: Comprehensive technical report with logarithmic convergence plots, performance tables, and theoretical analysis.
- **`Report-bonus.pdf`**: Bonus report with percolation analysis, failure model plots, and self-healing evaluations.
- **`README` / `README.md`**: Project overview, team members, scalability limits, and execution guide.

