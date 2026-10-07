#!/usr/bin/env python3
"""Compare Keep's uncached calculations and runtime caches with isolated Release-style fixtures."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=Path('/tmp/keep-cache-performance'))
parser.add_argument('--realtime', action='store_true', help='Pace each 60-tick fixture over one real minute (about six minutes total).')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
args.output.mkdir(parents=True, exist_ok=True)
sources = [
    'Core/Workspace/FocusProject.swift', 'Core/FocusSession/FocusTimer.swift',
    'Core/FocusSession/PomodoroSettings.swift', 'Core/Timesheet/TimesheetLedger.swift',
    'Core/Dashboard/RecordedSession.swift', 'Core/Dashboard/WeeklyProjection.swift',
    'Core/Stats/StatsSnapshot.swift', 'Core/Stats/StatsCache.swift',
    'Services/Workspace/WorkspaceModel.swift', 'Services/Workspace/WorkspaceReadIndex.swift',
    'Services/Timesheet/TimesheetPersistence.swift', 'UI/Dashboard/DashboardQueryModel.swift',
]
executable = args.output / 'benchmarks'
subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', '-default-isolation', 'MainActor',
                *(str(repo / 'Sources/Keep' / source) for source in sources),
                str(repo / 'Tests/CacheBenchmarks.swift'), '-o', str(executable)], check=True)
for name, flags in [('baseline', ['--baseline']), ('cached', [])]:
    if args.realtime:
        flags = [*flags, '--realtime']
    log = args.output / f'{name}.log'
    with log.open('w') as output:
        subprocess.run(['/usr/bin/time', '-l', str(executable), *flags], stdout=output,
                       stderr=subprocess.STDOUT, check=True, timeout=240 if args.realtime else 120)
    print(log.read_text())
