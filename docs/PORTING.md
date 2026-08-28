# Porting notes

## Upstream source

- Repository: `https://invent.kde.org/qt/qt/qtscript.git`
- Release branch: `5.15.19`
- Pinned commit: `bcd7cae6215df8f1c8b45a338f3327da51edeaff`

The repository stores patches, not a snapshot of the upstream sources. The
platform build scripts fetch the exact QtScript commit above, copy the Qt 6
CMake entry point from `cmake/`, apply the files in `patches/` in lexical
order, and optionally apply the selected test changes in
`patches/optional/tests` with `-IncludePortedTests`.

Update the source pin only in a dedicated commit after confirming that the new
commit belongs to the intended KDE release branch and that the complete CI
matrix passes with the unchanged patch series.

The scripts reuse an existing clean source directory that has already been
patched. Delete that directory under `.work/` before applying a changed patch
series.

## CMake entry point

`cmake/` mirrors the Qt 6 build files at their in-tree paths
(`CMakeLists.txt`, `.cmake.conf`, `src/CMakeLists.txt`,
`src/script/CMakeLists.txt`, `src/scripttools/CMakeLists.txt`) and is copied
verbatim by the apply scripts; it is not a patch. The module never depends on
QtCore5Compat. The legacy `QRegExp` compatibility API is compiled in by
default and can be disabled with `-DSCRIPT_QREGEXP=OFF`, which defines
`QT_NO_REGEXP` and drops the `QtScript/QRegExp` header.

## Default patch series

1. `0001-Remove-Core5Compat-dependency.patch` supplies the legacy public
   `QRegExp` API using `QRegularExpression`, preserves key Qt 5 regexp
   behavior, and removes the Core5Compat dependency; the shim and the
   `QT_NO_REGEXP` guards it relies on stay intact for the optional build.
2. `0002-Port-JavaScriptCore-subset-to-C-17.patch` contains the C++17/MSVC
   adaptations exercised by the CMake source manifest.
3. `0003-Adapt-QtScript-API-and-metatypes-to-Qt-6.patch` handles Qt 6 API,
   container, enum/metatype, atomic, and date/time differences.
4. `0004-Adapt-QObject-bridge-to-Qt-6.patch` contains the QObject, Qt 6
   metaobject, method invocation, property, and signal bridge changes.
5. `0005-Replace-removed-QBoolBlocker-helper.patch` replaces the removed
   private Qt helper with `QScopedValueRollback<bool>`.
6. `0006-Add-Linux-core-build-support.patch` selects the platform-specific
   JavaScriptCore stack allocator for Linux builds; the CMake source
   selection itself lives in the copied `cmake/` files.
7. `0007-Promote-INT32_MIN-negation-to-double-in-negate-opcode.patch` fixes
   `QTBUG-32829`: signed overflow when negating the smallest 32-bit integer.
8. `0008-Add-ScriptTools-debugger-module.patch` ports the ScriptTools
   debugger module to Qt 6: replaces the removed `QScopedSharedPointer` with
   a module-local equivalent (`qscopedsharedpointer_p.h`), drops
   forward-declared `QStringList` for the Qt 6 alias include, swaps
   `QSet::toList`/`QList::toSet` for range constructors, and replaces the
   removed `QRegExpValidator` with `QRegularExpressionValidator`.
9. `0009-Remove-obsolete-Darwin-ceil-workaround.patch` removes a workaround
   for a long-fixed macOS libc bug whose `ceil` macro conflicts with modern
   libc++ headers.
10. `0010-Support-Darwin-AArch64-GC-thread-registers.patch` teaches the
    conservative JavaScriptCore collector to read stack registers on Apple
    Silicon.
11. `0011-Fix-engine-initialization-locking-on-Darwin.patch` holds the
    JavaScriptCore lock while constructing the initial engine state. Darwin
    enables the engine's multiple-thread support, whose Debug assertions
    require this lock before the first garbage-collected allocation.

## Optional test layer

`patches/optional/tests` updates selected upstream tests and is applied with
`-IncludePortedTests`. The normal module build keeps `QT_BUILD_TESTS=OFF`.
The optional test layer is not required to compile or smoke-test the core
module.

## Build scope

The Qt 6 CMake entry point builds the `Script` module and the `ScriptTools`
debugger module (`Qt6::ScriptTools`, including the `QScriptEngineDebugger`
widget and the `scripttools_debugging` resources). It exports `Qt6::Script`
and `Qt6::ScriptTools`, their public/private headers, and CMake package
metadata. Examples, documentation, qmake integration, and 32-bit targets are
outside the acceptance scope. CI covers Linux x64, Windows x64, macOS x64, and
macOS arm64.
