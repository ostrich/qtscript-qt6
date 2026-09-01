#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
qt_root="${QT_ROOT_DIR:-}"
configuration="Release"
work_root=""
install_prefix=""
parallel="$(sysctl -n hw.logicalcpu)"
include_ported_tests=0

usage() {
    echo "Usage: $0 [--qt-root PATH] [--configuration Debug|Release] [--work-root PATH] [--install-prefix PATH] [--parallel N] [--include-ported-tests]"
}

while (($#)); do
    case "$1" in
        --qt-root) qt_root="$2"; shift 2 ;;
        --configuration) configuration="$2"; shift 2 ;;
        --work-root) work_root="$2"; shift 2 ;;
        --install-prefix) install_prefix="$2"; shift 2 ;;
        --parallel) parallel="$2"; shift 2 ;;
        --include-ported-tests) include_ported_tests=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ "$configuration" == Debug || "$configuration" == Release ]] ||
    { echo "Configuration must be Debug or Release." >&2; exit 2; }
[[ -n "$qt_root" && -d "$qt_root" ]] ||
    { echo "Specify --qt-root or set QT_ROOT_DIR." >&2; exit 1; }
[[ "$parallel" =~ ^[0-9]+$ && "$parallel" -ge 1 ]] ||
    { echo "Parallel must be a positive integer." >&2; exit 2; }
for command in cmake ninja git lipo otool shasum; do
    command -v "$command" >/dev/null ||
        { echo "$command was not found on PATH." >&2; exit 1; }
done

qt_root="$(cd "$qt_root" && pwd)"
qt_key="$(printf '%s' "$qt_root" | shasum -a 256)"
qt_key="${qt_key:0:12}"
qt_cmake=""
for candidate in "$qt_root/bin/qt-cmake-private" "$qt_root/libexec/qt-cmake-private"; do
    [[ -x "$candidate" ]] && { qt_cmake="$candidate"; break; }
done
[[ -n "$qt_cmake" ]] ||
    { echo "Qt private module build helper was not found under $qt_root." >&2; exit 1; }

[[ -n "$work_root" ]] || work_root="$repo_root/.work/$qt_key/$configuration"
[[ -n "$install_prefix" ]] || install_prefix="$work_root/install"

source_dir="$work_root/src"
build_dir="$work_root/build"
if [[ "$include_ported_tests" -eq 1 ]]; then
    bash "$repo_root/scripts/apply-patches.sh" "$source_dir" --include-ported-tests
else
    bash "$repo_root/scripts/apply-patches.sh" "$source_dir"
fi

tests_option=-DQT_BUILD_TESTS=OFF
[[ "$include_ported_tests" -eq 1 ]] && tests_option=-DQT_BUILD_TESTS=ON

apple_check_args=(-DQT_FORCE_WARN_APPLE_SDK_AND_XCODE_CHECK=ON)
if ! command -v xcodebuild >/dev/null || ! xcodebuild -version >/dev/null 2>&1; then
    # Qt 6.11 otherwise rejects Command Line Tools-only hosts before compiling.
    # GitHub's macOS runners have full Xcode and retain Qt's version check.
    apple_check_args+=(-DQT_NO_XCODE_MIN_VERSION_CHECK=ON)
fi

"$qt_cmake" -S "$source_dir" -B "$build_dir" -G Ninja \
    "-DCMAKE_BUILD_TYPE=$configuration" \
    "-DCMAKE_INSTALL_PREFIX=$install_prefix" \
    "$tests_option" -DQT_BUILD_EXAMPLES=OFF \
    "${apple_check_args[@]}" \
    -DWARNINGS_ARE_ERRORS=OFF -DQT_REPO_NOT_WARNINGS_CLEAN=ON
cmake --build "$build_dir" --parallel "$parallel"
cmake --install "$build_dir"

script_binary="$install_prefix/lib/QtScript.framework/Versions/A/QtScript"
scripttools_binary="$install_prefix/lib/QtScriptTools.framework/Versions/A/QtScriptTools"
[[ -f "$script_binary" ]] || { echo "QtScript framework was not installed." >&2; exit 1; }
[[ -f "$scripttools_binary" ]] || { echo "QtScriptTools framework was not installed." >&2; exit 1; }
qt_core="$qt_root/lib/QtCore.framework/Versions/A/QtCore"
[[ -f "$qt_core" ]] || { echo "QtCore framework was not found under $qt_root." >&2; exit 1; }
for binary in "$script_binary" "$scripttools_binary"; do
    binary_architectures=" $(lipo -archs "$binary") "
    for qt_architecture in $(lipo -archs "$qt_core"); do
        if [[ "$binary_architectures" != *" $qt_architecture "* ]]; then
            echo "$(basename "$binary") is missing Qt's $qt_architecture architecture." >&2
            exit 1
        fi
    done
done
if otool -L "$script_binary" | grep -E 'Core5Compat|Qt5Compat' >/dev/null; then
    echo "QtScript links to Core5Compat or Qt5Compat." >&2
    exit 1
fi

smoke_dir="$work_root/smoke-build"
cmake -S "$repo_root/tests/smoke" -B "$smoke_dir" -G Ninja \
    "-DCMAKE_BUILD_TYPE=$configuration" \
    "-DCMAKE_PREFIX_PATH=$qt_root" \
    "-DQt6Script_DIR=$install_prefix/lib/cmake/Qt6Script" \
    "-DQt6ScriptTools_DIR=$install_prefix/lib/cmake/Qt6ScriptTools"
cmake --build "$smoke_dir" --parallel "$parallel"
QT_QPA_PLATFORM=offscreen \
DYLD_FRAMEWORK_PATH="$install_prefix/lib:${DYLD_FRAMEWORK_PATH:-}" \
    ctest --test-dir "$smoke_dir" --output-on-failure

echo "QtScript $configuration installed into $install_prefix"
