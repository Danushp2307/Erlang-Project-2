import os
import csv
import matplotlib.pyplot as plt
import numpy as np

# Set aesthetic style
plt.style.use('seaborn-v0_8-whitegrid' if 'seaborn-v0_8-whitegrid' in plt.style.available else 'default')
plt.rcParams['font.sans-serif'] = 'Helvetica', 'Arial', 'DejaVu Sans'
plt.rcParams['axes.edgecolor'] = '#cccccc'
plt.rcParams['axes.linewidth'] = 0.8

# Load main benchmark data
main_data = []
with open('main_benchmark_data.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        main_data.append({
            'algorithm': row['algorithm'],
            'topology': row['topology'].replace("'", ""),
            'n': int(row['n']),
            'actual_n': int(row['actual_n']),
            'time_ms': float(row['time_ms'])
        })

# Color palette and markers
topo_colors = {
    'full': '#1f77b4',   # Blue
    '2D': '#ff7f0e',     # Orange
    'line': '#d62728',   # Red
    'imp2D': '#2ca02c'   # Green
}
topo_markers = {
    'full': 'o',
    '2D': 's',
    'line': '^',
    'imp2D': 'D'
}
topo_labels = {
    'full': 'Full Network',
    '2D': '2D Grid',
    'line': 'Line',
    'imp2D': 'Imperfect 2D Grid'
}

# ----------------------------------------------------
# 1. Gossip Convergence Plot
# ----------------------------------------------------
plt.figure(figsize=(8, 5.5), dpi=300)
for topo in ['full', '2D', 'imp2D', 'line']:
    sub = [r for r in main_data if r['algorithm'] == 'gossip' and r['topology'] == topo]
    sub.sort(key=lambda x: x['actual_n'])
    xs = [r['actual_n'] for r in sub]
    ys = [r['time_ms'] for r in sub]
    plt.plot(xs, ys, marker=topo_markers[topo], color=topo_colors[topo],
             label=topo_labels[topo], linewidth=2.2, markersize=7)

plt.xscale('log')
plt.yscale('log')
plt.xlabel('Network Size (Number of Nodes, N)', fontsize=12, fontweight='bold', labelpad=8)
plt.ylabel('Convergence Time (milliseconds, log scale)', fontsize=12, fontweight='bold', labelpad=8)
plt.title('Gossip Algorithm: Convergence Time vs Network Size', fontsize=14, fontweight='bold', pad=12)
plt.grid(True, which='both', linestyle='--', alpha=0.5)
plt.legend(frameon=True, facecolor='white', framealpha=0.9, fontsize=10.5, loc='upper left')
plt.tight_layout()
plt.savefig('gossip_convergence.png', dpi=300)
plt.close()
print("Saved gossip_convergence.png")

# ----------------------------------------------------
# 2. Push-Sum Convergence Plot
# ----------------------------------------------------
plt.figure(figsize=(8, 5.5), dpi=300)
for topo in ['full', 'imp2D', '2D', 'line']:
    sub = [r for r in main_data if r['algorithm'] == 'push-sum' and r['topology'] == topo]
    sub.sort(key=lambda x: x['actual_n'])
    xs = [r['actual_n'] for r in sub]
    ys = [r['time_ms'] for r in sub]
    plt.plot(xs, ys, marker=topo_markers[topo], color=topo_colors[topo],
             label=topo_labels[topo], linewidth=2.2, markersize=7)

plt.xscale('log')
plt.yscale('log')
plt.xlabel('Network Size (Number of Nodes, N)', fontsize=12, fontweight='bold', labelpad=8)
plt.ylabel('Convergence Time (milliseconds, log scale)', fontsize=12, fontweight='bold', labelpad=8)
plt.title('Push-Sum Algorithm: Convergence Time vs Network Size', fontsize=14, fontweight='bold', pad=12)
plt.grid(True, which='both', linestyle='--', alpha=0.5)
plt.legend(frameon=True, facecolor='white', framealpha=0.9, fontsize=10.5, loc='upper left')
plt.tight_layout()
plt.savefig('push_sum_convergence.png', dpi=300)
plt.close()
print("Saved push_sum_convergence.png")

# ----------------------------------------------------
# 3. Bonus Benchmark Data
# ----------------------------------------------------
bonus_data = []
with open('bonus_benchmark_data.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        bonus_data.append({
            'model': row['model'],
            'param': float(row['param']),
            'topology': row['topology'].replace("'", ""),
            'n': int(row['n']),
            'coverage_pct': float(row['coverage_pct']),
            'time_ms': float(row['time_ms'])
        })

# 3A. Bonus: Node Failure vs Coverage %
plt.figure(figsize=(8, 5.2), dpi=300)
node_sub = [r for r in bonus_data if r['model'] == 'node']
for topo in ['full', 'imp2D', '2D', 'line']:
    sub = [r for r in node_sub if r['topology'] == topo]
    sub.sort(key=lambda x: x['param'])
    xs = [r['param'] * 100 for r in sub]
    ys = [r['coverage_pct'] for r in sub]
    plt.plot(xs, ys, marker=topo_markers[topo], color=topo_colors[topo],
             label=topo_labels[topo], linewidth=2.2, markersize=7)

plt.xlabel('Node Failure Rate (%)', fontsize=12, fontweight='bold', labelpad=8)
plt.ylabel('Information Coverage among Alive Nodes (%)', fontsize=12, fontweight='bold', labelpad=8)
plt.title('Fault Tolerance: Rumor Coverage vs Node Failure Rate (N=196)', fontsize=13, fontweight='bold', pad=12)
plt.ylim(-5, 105)
plt.grid(True, linestyle='--', alpha=0.5)
plt.legend(frameon=True, facecolor='white', framealpha=0.9, fontsize=10.5, loc='lower left')
plt.tight_layout()
plt.savefig('bonus_node_failure_coverage.png', dpi=300)
plt.close()
print("Saved bonus_node_failure_coverage.png")

# 3B. Bonus: Connection Drop Rate vs Convergence Time
plt.figure(figsize=(8, 5.2), dpi=300)
conn_sub = [r for r in bonus_data if r['model'] == 'connection']
for topo in ['full', 'imp2D', '2D']:
    sub = [r for r in conn_sub if r['topology'] == topo]
    sub.sort(key=lambda x: x['param'])
    xs = [r['param'] * 100 for r in sub]
    ys = [r['time_ms'] for r in sub]
    plt.plot(xs, ys, marker=topo_markers[topo], color=topo_colors[topo],
             label=topo_labels[topo], linewidth=2.2, markersize=7)

plt.xlabel('Transient Connection Drop / Loss Rate (%)', fontsize=12, fontweight='bold', labelpad=8)
plt.ylabel('Convergence Time (milliseconds)', fontsize=12, fontweight='bold', labelpad=8)
plt.title('Self-Healing Dynamics: Convergence Time vs Message Drop Rate (N=196)', fontsize=13, fontweight='bold', pad=12)
plt.grid(True, linestyle='--', alpha=0.5)
plt.legend(frameon=True, facecolor='white', framealpha=0.9, fontsize=10.5, loc='upper left')
plt.tight_layout()
plt.savefig('bonus_connection_loss_time.png', dpi=300)
plt.close()
print("Saved bonus_connection_loss_time.png")

