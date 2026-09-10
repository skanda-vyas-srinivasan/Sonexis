#!/usr/bin/env python3
"""Build repeatable offline audit executables without changing application source.

The live helper is compiled but NEVER started by this script. It plays a quiet
generated tone and needs separate, supervised execution with a timeout.
"""
import pathlib
import platform
import shlex
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build' / 'ReleaseAudit'
EVIDENCE = ROOT / 'docs' / 'release-2.1.0-evidence'
EVIDENCE.mkdir(parents=True, exist_ok=True)


def run(args, log):
    with (EVIDENCE / log).open('w') as output:
        subprocess.run(args, cwd=ROOT, stdout=output,
                       stderr=subprocess.STDOUT, check=True)


run(['xcodebuild', '-project', 'Sonexis.xcodeproj', '-scheme', 'Sonexis',
     '-configuration', 'Release', '-derivedDataPath', str(BUILD),
     '-destination', 'platform=macOS', 'build', 'CODE_SIGNING_ALLOWED=NO',
     'ENABLE_TESTABILITY=YES'], 'audit-prepare-build.log')

arch = platform.machine()
objects = (BUILD / 'Build/Intermediates.noindex/Sonexis.build/Release/'
           'Sonexis.build/Objects-normal' / arch)
developer = pathlib.Path(subprocess.check_output(
    ['xcode-select', '-p'], text=True).strip())
toolchain = developer / 'Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx'
sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
library = BUILD / 'libSonexisAudit.dylib'
# Re-link the exact optimized app objects as a test library. @testable visibility
# is enabled above; these helpers and this library are not distribution artifacts.
run(['xcrun', 'clang++', '-dynamiclib', '-target', f'{arch}-apple-macos14.4',
     '-isysroot', sdk, '-filelist', str(objects / 'Sonexis.LinkFileList'),
     '-L' + str(toolchain), '-L/usr/lib/swift', '-framework', 'Accelerate',
     '-fobjc-arc', '-fobjc-link-runtime',
     '@' + str(objects / 'Sonexis-linker-args.resp'),
     '-install_name', str(library), '-o', str(library)], 'audit-prepare-link.log')

products = BUILD / 'Build/Products/Release'
for source, name in [('main.swift', 'audit'), ('worker.swift', 'worker-audit'),
                     ('longrun.swift', 'longrun-audit'), ('live.swift', 'live-audit'),
                     ('import_fuzz.swift', 'import-fuzz')]:
    run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(BUILD / 'module-cache'),
         '-I', str(products), str(ROOT / 'Tests/ReleaseAudit' / source),
         str(library), '-o', str(BUILD / name)], f'audit-prepare-{name}.log')

run(['xcrun', 'clang', '-O1', '-g', '-fsanitize=address,undefined',
     '-I', str(ROOT / 'Sonexis/ProcessTapEngine'),
     str(ROOT / 'Tests/ReleaseAudit/ring_stress.c'),
     str(ROOT / 'Sonexis/ProcessTapEngine/RealtimeAudioRing.c'),
     '-framework', 'CoreAudio', '-o', str(BUILD / 'ring-stress')],
    'audit-prepare-ring.log')
print('Prepared offline audit tools in', BUILD)
print('Example:', shlex.join([str(BUILD / 'audit'), 'pitch-edit']))
