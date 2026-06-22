#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Twarge LLC
# SPDX-License-Identifier: Apache-2.0
#
# Generates observatory.xcodeproj/project.pbxproj for the Observatory app.
#
# A small, project-specific project generator (in the spirit of XcodeGen, but with zero
# external dependencies). It globs the Sources/* directories, so adding a Swift file just
# means re-running this script. The four targets and their build settings are spelled out
# explicitly below for auditability.
#
#   Targets
#     Observatory               iOS + macOS app             (Sources/Observatory)
#     ObservatoryWidgets        iOS + macOS widget ext      (Sources/ObservatoryWidgets)      -> embedded in app
#     ObservatoryWatch          watchOS app                 (Sources/ObservatoryWatch)
#     ObservatoryWatchWidgets   watchOS widget ext          (Sources/ObservatoryWatchWidgets) -> embedded in watch app
#
#   All targets also compile the shared Sources/ObservatoryCore and Sources/ObservatoryPlot.

import os
import re
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "observatory"
ORG = "Twarge LLC"

# ---------------------------------------------------------------------------- IDs

_counter = [0]
_ids = {}

def gid(key):
    """Stable 24-char id for a logical key (deterministic across runs)."""
    if key not in _ids:
        _counter[0] += 1
        _ids[key] = "%024X" % _counter[0]
    return _ids[key]

def q(s):
    s = str(s)
    if re.fullmatch(r"[A-Za-z0-9_.]+", s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def setting_value(v, indent):
    if isinstance(v, list):
        pad = "\t" * (indent + 1)
        close = "\t" * indent
        return "(\n" + "".join(pad + q(x) + ",\n" for x in v) + close + ")"
    return q(v)

def emit_settings(settings, indent):
    pad = "\t" * indent
    return "\n".join(pad + q(k) + " = " + setting_value(settings[k], indent) + ";" for k in settings)

# ---------------------------------------------------------------------------- source discovery

SRC_DIRS = {
    "core": "Sources/ObservatoryCore",
    "plot": "Sources/ObservatoryPlot",
    "app": "Sources/Observatory",
    "widgets": "Sources/ObservatoryWidgets",
    "watch": "Sources/ObservatoryWatch",
    "watchwidgets": "Sources/ObservatoryWatchWidgets",
}

GROUP_NAMES = {
    "core": "ObservatoryCore",
    "plot": "ObservatoryPlot",
    "app": "Observatory",
    "widgets": "ObservatoryWidgets",
    "watch": "ObservatoryWatch",
    "watchwidgets": "ObservatoryWatchWidgets",
}

def swift_files(key):
    pattern = os.path.join(ROOT, SRC_DIRS[key], "*.swift")
    return [os.path.relpath(p, ROOT) for p in sorted(glob.glob(pattern))]

SOURCES = {key: swift_files(key) for key in SRC_DIRS}

# ---------------------------------------------------------------------------- build settings

COMMON_DEBUG = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}

COMMON_RELEASE = {
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
}

PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "COPY_PHASE_STRIP": "NO",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
    "MACOSX_DEPLOYMENT_TARGET": "26.0",
    "MARKETING_VERSION": "1.0",
    "SWIFT_VERSION": "5.0",
    "WATCHOS_DEPLOYMENT_TARGET": "26.0",
}

APPLE_PLATFORMS = "iphoneos iphonesimulator macosx"
WATCH_PLATFORMS = "watchos watchsimulator"

TARGETS = [
    {
        "key": "app", "name": "Observatory",
        "type": "com.apple.product-type.application",
        "product": "Observatory.app", "product_filetype": "wrapper.application",
        "sources": ["core", "plot", "app"], "assets": ["app_assets"],
        "embeds": ["widgets"], "deps": ["widgets"],
        "settings": {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_ENTITLEMENTS": "Resources/App/Observatory.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_KEY_CFBundleDisplayName": "Observatory",
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.utilities",
            "INFOPLIST_KEY_NSHumanReadableCopyright": "Copyright 2026 Twarge LLC.",
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
            "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
            "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
            "LD_RUNPATH_SEARCH_PATHS[sdk=iphoneos*]": "@executable_path/Frameworks",
            "LD_RUNPATH_SEARCH_PATHS[sdk=iphonesimulator*]": "@executable_path/Frameworks",
            "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": "@executable_path/../Frameworks",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.twarge.observatory",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "auto",
            "SUPPORTED_PLATFORMS": APPLE_PLATFORMS,
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "TARGETED_DEVICE_FAMILY": "1,2",
        },
    },
    {
        "key": "widgets", "name": "ObservatoryWidgets",
        "type": "com.apple.product-type.app-extension",
        "product": "ObservatoryWidgets.appex", "product_filetype": "wrapper.app-extension",
        "sources": ["core", "plot", "widgets"], "assets": [],
        "embeds": [], "deps": [],
        "settings": {
            "CODE_SIGN_ENTITLEMENTS": "Resources/Widgets/ObservatoryWidgets.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "Resources/Widgets/ObservatoryWidgets-Info.plist",
            "LD_RUNPATH_SEARCH_PATHS[sdk=iphoneos*]": "@executable_path/Frameworks @executable_path/../../Frameworks",
            "LD_RUNPATH_SEARCH_PATHS[sdk=iphonesimulator*]": "@executable_path/Frameworks @executable_path/../../Frameworks",
            "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": "@executable_path/../Frameworks @executable_path/../../../../Frameworks",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.twarge.observatory.widgets",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "auto",
            "SKIP_INSTALL": "YES",
            "SUPPORTED_PLATFORMS": APPLE_PLATFORMS,
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "TARGETED_DEVICE_FAMILY": "1,2",
        },
    },
    {
        "key": "watch", "name": "ObservatoryWatch",
        "type": "com.apple.product-type.application",
        "product": "ObservatoryWatch.app", "product_filetype": "wrapper.application",
        "sources": ["core", "plot", "watch"], "assets": ["watch_assets"],
        "embeds": ["watchwidgets"], "deps": ["watchwidgets"],
        "settings": {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_ENTITLEMENTS": "Resources/Watch/ObservatoryWatch.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_KEY_CFBundleDisplayName": "Observatory",
            "INFOPLIST_KEY_NSHumanReadableCopyright": "Copyright 2026 Twarge LLC.",
            "INFOPLIST_KEY_WKApplication": "YES",
            "INFOPLIST_KEY_WKWatchOnly": "YES",
            "LD_RUNPATH_SEARCH_PATHS": "@executable_path/Frameworks",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.twarge.observatory.watch",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "watchos",
            "SUPPORTED_PLATFORMS": WATCH_PLATFORMS,
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "TARGETED_DEVICE_FAMILY": "4",
        },
    },
    {
        "key": "watchwidgets", "name": "ObservatoryWatchWidgets",
        "type": "com.apple.product-type.app-extension",
        "product": "ObservatoryWatchWidgets.appex", "product_filetype": "wrapper.app-extension",
        "sources": ["core", "plot", "watchwidgets"], "assets": [],
        "embeds": [], "deps": [],
        "settings": {
            "CODE_SIGN_ENTITLEMENTS": "Resources/WatchWidgets/ObservatoryWatchWidgets.entitlements",
            "CODE_SIGN_STYLE": "Automatic",
            "ENABLE_PREVIEWS": "YES",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "Resources/WatchWidgets/ObservatoryWatchWidgets-Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": "@executable_path/Frameworks @executable_path/../../Frameworks",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.twarge.observatory.watch.widgets",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SDKROOT": "watchos",
            "SKIP_INSTALL": "YES",
            "SUPPORTED_PLATFORMS": WATCH_PLATFORMS,
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "TARGETED_DEVICE_FAMILY": "4",
        },
    },
]

TARGET_BY_KEY = {t["key"]: t for t in TARGETS}

ASSET_FILES = {
    "app_assets": "Resources/App/Assets.xcassets",
    "watch_assets": "Resources/Watch/Assets.xcassets",
}

NAV_RESOURCES = [
    "Resources/App/Assets.xcassets",
    "Resources/App/Observatory.entitlements",
    "Resources/Widgets/ObservatoryWidgets-Info.plist",
    "Resources/Widgets/ObservatoryWidgets.entitlements",
    "Resources/Watch/Assets.xcassets",
    "Resources/Watch/ObservatoryWatch.entitlements",
    "Resources/WatchWidgets/ObservatoryWatchWidgets-Info.plist",
    "Resources/WatchWidgets/ObservatoryWatchWidgets.entitlements",
]

# ---- id helpers (avoid nested f-strings entirely) ----
def file_ref(path):            return gid("fileref:" + path)
def product_ref(key):          return gid("product:" + key)
def src_build_file(tk, path):  return gid("buildfile:" + tk + ":" + path)
def res_build_file(tk, path):  return gid("buildfile:" + tk + ":" + path)
def embed_build_file(tk, ek):  return gid("embed:" + tk + ":" + ek)
def proxy_id(tk, dk):          return gid("proxy:" + tk + ":" + dk)
def dep_id(tk, dk):            return gid("dependency:" + tk + ":" + dk)
def target_id(key):            return gid("target:" + key)

def filetype(path):
    if path.endswith(".swift"):        return "sourcecode.swift"
    if path.endswith(".xcassets"):     return "folder.assetcatalog"
    if path.endswith(".entitlements"): return "text.plist.entitlements"
    if path.endswith(".plist"):        return "text.plist.xml"
    return "text"

def base(path):
    return os.path.basename(path)

# ---------------------------------------------------------------------------- emit

def build():
    out = []
    w = out.append
    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")

    all_files = set()
    for key in SOURCES:
        all_files.update(SOURCES[key])
    all_files.update(NAV_RESOURCES)
    all_files = sorted(all_files)

    # ----- PBXBuildFile
    w("\n/* Begin PBXBuildFile section */")
    for t in TARGETS:
        tk = t["key"]
        for grp in t["sources"]:
            for f in SOURCES[grp]:
                w("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
                  % (src_build_file(tk, f), base(f), file_ref(f), base(f)))
        for a in t["assets"]:
            path = ASSET_FILES[a]
            w("\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
              % (res_build_file(tk, path), base(path), file_ref(path), base(path)))
    for t in TARGETS:
        for ek in t["embeds"]:
            et = TARGET_BY_KEY[ek]
            w("\t\t%s /* %s in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = %s /* %s */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };"
              % (embed_build_file(t["key"], ek), et["product"], product_ref(ek), et["product"]))
    w("/* End PBXBuildFile section */")

    # ----- PBXContainerItemProxy
    w("\n/* Begin PBXContainerItemProxy section */")
    for t in TARGETS:
        for dk in t["deps"]:
            dt = TARGET_BY_KEY[dk]
            w("\t\t%s /* PBXContainerItemProxy */ = {" % proxy_id(t["key"], dk))
            w("\t\t\tisa = PBXContainerItemProxy;")
            w("\t\t\tcontainerPortal = %s /* Project object */;" % gid("project"))
            w("\t\t\tproxyType = 1;")
            w("\t\t\tremoteGlobalIDString = %s;" % target_id(dk))
            w("\t\t\tremoteInfo = %s;" % q(dt["name"]))
            w("\t\t};")
    w("/* End PBXContainerItemProxy section */")

    # ----- PBXCopyFilesBuildPhase
    w("\n/* Begin PBXCopyFilesBuildPhase section */")
    for t in TARGETS:
        if not t["embeds"]:
            continue
        w("\t\t%s /* Embed App Extensions */ = {" % gid("copyphase:" + t["key"]))
        w("\t\t\tisa = PBXCopyFilesBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w('\t\t\tdstPath = "";')
        w("\t\t\tdstSubfolderSpec = 13;")
        w("\t\t\tfiles = (")
        for ek in t["embeds"]:
            et = TARGET_BY_KEY[ek]
            w("\t\t\t\t%s /* %s in Embed App Extensions */," % (embed_build_file(t["key"], ek), et["product"]))
        w("\t\t\t);")
        w('\t\t\tname = "Embed App Extensions";')
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXCopyFilesBuildPhase section */")

    # ----- PBXFileReference
    w("\n/* Begin PBXFileReference section */")
    for f in all_files:
        w("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; name = %s; path = %s; sourceTree = SOURCE_ROOT; };"
          % (file_ref(f), base(f), filetype(f), q(base(f)), q(f)))
    for t in TARGETS:
        w("\t\t%s /* %s */ = {isa = PBXFileReference; explicitFileType = %s; includeInIndex = 0; path = %s; sourceTree = BUILT_PRODUCTS_DIR; };"
          % (product_ref(t["key"]), t["product"], q(t["product_filetype"]), q(t["product"])))
    w("/* End PBXFileReference section */")

    # ----- PBXFrameworksBuildPhase
    w("\n/* Begin PBXFrameworksBuildPhase section */")
    for t in TARGETS:
        w("\t\t%s /* Frameworks */ = {" % gid("frameworks:" + t["key"]))
        w("\t\t\tisa = PBXFrameworksBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")

    # ----- PBXGroup
    w("\n/* Begin PBXGroup section */")
    w("\t\t%s = {" % gid("maingroup"))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* Sources */," % gid("group:Sources"))
    w("\t\t\t\t%s /* Resources */," % gid("group:Resources"))
    w("\t\t\t\t%s /* Products */," % gid("group:Products"))
    w("\t\t\t);")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")
    w("\t\t%s /* Sources */ = {" % gid("group:Sources"))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for key in SRC_DIRS:
        w("\t\t\t\t%s /* %s */," % (gid("group:src:" + key), GROUP_NAMES[key]))
    w("\t\t\t);")
    w("\t\t\tname = Sources;")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")
    for key in SRC_DIRS:
        w("\t\t%s /* %s */ = {" % (gid("group:src:" + key), GROUP_NAMES[key]))
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for f in SOURCES[key]:
            w("\t\t\t\t%s /* %s */," % (file_ref(f), base(f)))
        w("\t\t\t);")
        w("\t\t\tname = %s;" % q(GROUP_NAMES[key]))
        w('\t\t\tsourceTree = "<group>";')
        w("\t\t};")
    w("\t\t%s /* Resources */ = {" % gid("group:Resources"))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for f in NAV_RESOURCES:
        w("\t\t\t\t%s /* %s */," % (file_ref(f), base(f)))
    w("\t\t\t);")
    w("\t\t\tname = Resources;")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")
    w("\t\t%s /* Products */ = {" % gid("group:Products"))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for t in TARGETS:
        w("\t\t\t\t%s /* %s */," % (product_ref(t["key"]), t["product"]))
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w('\t\t\tsourceTree = "<group>";')
    w("\t\t};")
    w("/* End PBXGroup section */")

    # ----- PBXNativeTarget
    w("\n/* Begin PBXNativeTarget section */")
    for t in TARGETS:
        tk = t["key"]
        w("\t\t%s /* %s */ = {" % (target_id(tk), t["name"]))
        w("\t\t\tisa = PBXNativeTarget;")
        w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget %s */;"
          % (gid("configlist:target:" + tk), q(t["name"])))
        w("\t\t\tbuildPhases = (")
        w("\t\t\t\t%s /* Sources */," % gid("sources:" + tk))
        w("\t\t\t\t%s /* Frameworks */," % gid("frameworks:" + tk))
        w("\t\t\t\t%s /* Resources */," % gid("resources:" + tk))
        if t["embeds"]:
            w("\t\t\t\t%s /* Embed App Extensions */," % gid("copyphase:" + tk))
        w("\t\t\t);")
        w("\t\t\tbuildRules = (")
        w("\t\t\t);")
        w("\t\t\tdependencies = (")
        for dk in t["deps"]:
            w("\t\t\t\t%s /* PBXTargetDependency */," % dep_id(tk, dk))
        w("\t\t\t);")
        w("\t\t\tname = %s;" % q(t["name"]))
        w("\t\t\tproductName = %s;" % q(t["name"]))
        w("\t\t\tproductReference = %s /* %s */;" % (product_ref(tk), t["product"]))
        w("\t\t\tproductType = %s;" % q(t["type"]))
        w("\t\t};")
    w("/* End PBXNativeTarget section */")

    # ----- PBXProject
    w("\n/* Begin PBXProject section */")
    w("\t\t%s /* Project object */ = {" % gid("project"))
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = YES;")
    w("\t\t\t\tLastSwiftUpdateCheck = 2640;")
    w("\t\t\t\tLastUpgradeCheck = 2640;")
    w("\t\t\t\tORGANIZATIONNAME = %s;" % q(ORG))
    w("\t\t\t\tTargetAttributes = {")
    for t in TARGETS:
        w("\t\t\t\t\t%s = {" % target_id(t["key"]))
        w("\t\t\t\t\t\tCreatedOnToolsVersion = 26.4;")
        w("\t\t\t\t\t};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject */;" % gid("configlist:project"))
    w('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\tBase,")
    w("\t\t\t);")
    w("\t\t\tmainGroup = %s;" % gid("maingroup"))
    w("\t\t\tproductRefGroup = %s /* Products */;" % gid("group:Products"))
    w('\t\t\tprojectDirPath = "";')
    w('\t\t\tprojectRoot = "";')
    w("\t\t\ttargets = (")
    for t in TARGETS:
        w("\t\t\t\t%s /* %s */," % (target_id(t["key"]), t["name"]))
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")

    # ----- PBXResourcesBuildPhase
    w("\n/* Begin PBXResourcesBuildPhase section */")
    for t in TARGETS:
        w("\t\t%s /* Resources */ = {" % gid("resources:" + t["key"]))
        w("\t\t\tisa = PBXResourcesBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        for a in t["assets"]:
            path = ASSET_FILES[a]
            w("\t\t\t\t%s /* %s in Resources */," % (res_build_file(t["key"], path), base(path)))
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")

    # ----- PBXSourcesBuildPhase
    w("\n/* Begin PBXSourcesBuildPhase section */")
    for t in TARGETS:
        tk = t["key"]
        w("\t\t%s /* Sources */ = {" % gid("sources:" + tk))
        w("\t\t\tisa = PBXSourcesBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        for grp in t["sources"]:
            for f in SOURCES[grp]:
                w("\t\t\t\t%s /* %s in Sources */," % (src_build_file(tk, f), base(f)))
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")

    # ----- PBXTargetDependency
    w("\n/* Begin PBXTargetDependency section */")
    for t in TARGETS:
        for dk in t["deps"]:
            w("\t\t%s /* PBXTargetDependency */ = {" % dep_id(t["key"], dk))
            w("\t\t\tisa = PBXTargetDependency;")
            w("\t\t\ttarget = %s /* %s */;" % (target_id(dk), TARGET_BY_KEY[dk]["name"]))
            w("\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;" % proxy_id(t["key"], dk))
            w("\t\t};")
    w("/* End PBXTargetDependency section */")

    # ----- XCBuildConfiguration
    w("\n/* Begin XCBuildConfiguration section */")
    for cfg, extra in (("Debug", COMMON_DEBUG), ("Release", COMMON_RELEASE)):
        merged = dict(PROJECT_COMMON)
        merged.update(extra)
        w("\t\t%s /* %s */ = {" % (gid("buildconfig:project:" + cfg), cfg))
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        w(emit_settings(merged, 4))
        w("\t\t\t};")
        w("\t\t\tname = %s;" % cfg)
        w("\t\t};")
    for t in TARGETS:
        for cfg in ("Debug", "Release"):
            w("\t\t%s /* %s */ = {" % (gid("buildconfig:target:" + t["key"] + ":" + cfg), cfg))
            w("\t\t\tisa = XCBuildConfiguration;")
            w("\t\t\tbuildSettings = {")
            w(emit_settings(t["settings"], 4))
            w("\t\t\t};")
            w("\t\t\tname = %s;" % cfg)
            w("\t\t};")
    w("/* End XCBuildConfiguration section */")

    # ----- XCConfigurationList
    w("\n/* Begin XCConfigurationList section */")
    w("\t\t%s /* Build configuration list for PBXProject */ = {" % gid("configlist:project"))
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w("\t\t\t\t%s /* Debug */," % gid("buildconfig:project:Debug"))
    w("\t\t\t\t%s /* Release */," % gid("buildconfig:project:Release"))
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    for t in TARGETS:
        w("\t\t%s /* Build configuration list for PBXNativeTarget %s */ = {"
          % (gid("configlist:target:" + t["key"]), q(t["name"])))
        w("\t\t\tisa = XCConfigurationList;")
        w("\t\t\tbuildConfigurations = (")
        w("\t\t\t\t%s /* Debug */," % gid("buildconfig:target:" + t["key"] + ":Debug"))
        w("\t\t\t\t%s /* Release */," % gid("buildconfig:target:" + t["key"] + ":Release"))
        w("\t\t\t);")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w("\t\t\tdefaultConfigurationName = Release;")
        w("\t\t};")
    w("/* End XCConfigurationList section */")

    w("\t};")
    w("\trootObject = %s /* Project object */;" % gid("project"))
    w("}")
    return "\n".join(out) + "\n"


def scheme_xml(t):
    tid = target_id(t["key"])
    is_app = t["type"].endswith("application")
    ref = ('<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="%s" '
           'BuildableName="%s" BlueprintName="%s" '
           'ReferencedContainer="container:%s.xcodeproj"></BuildableReference>'
           % (tid, t["product"], t["name"], PROJECT_NAME))
    runnable = ('      <BuildableProductRunnable runnableDebuggingMode="0">\n        %s\n'
                '      </BuildableProductRunnable>\n' % ref) if is_app else ""
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Scheme LastUpgradeVersion="2640" version="1.7">\n'
        '   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">\n'
        '      <BuildActionEntries>\n'
        '         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">\n'
        '            %s\n'
        '         </BuildActionEntry>\n'
        '      </BuildActionEntries>\n'
        '   </BuildAction>\n'
        '   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">\n'
        '      <Testables></Testables>\n'
        '   </TestAction>\n'
        '   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">\n'
        '%s'
        '   </LaunchAction>\n'
        '   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">\n'
        '%s'
        '   </ProfileAction>\n'
        '   <AnalyzeAction buildConfiguration="Debug"></AnalyzeAction>\n'
        '   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"></ArchiveAction>\n'
        '</Scheme>\n'
        % (ref, runnable, runnable)
    )


def main():
    proj_dir = os.path.join(ROOT, PROJECT_NAME + ".xcodeproj")
    os.makedirs(proj_dir, exist_ok=True)
    with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
        f.write(build())
    ws_dir = os.path.join(proj_dir, "project.xcworkspace")
    os.makedirs(ws_dir, exist_ok=True)
    with open(os.path.join(ws_dir, "contents.xcworkspacedata"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0">\n'
                '   <FileRef location="self:">\n   </FileRef>\n</Workspace>\n')
    # Shared schemes so a fresh checkout builds with `xcodebuild -scheme` and Xcode shows them.
    schemes_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
    os.makedirs(schemes_dir, exist_ok=True)
    for t in TARGETS:
        with open(os.path.join(schemes_dir, t["name"] + ".xcscheme"), "w") as f:
            f.write(scheme_xml(t))
    n = sum(len(SOURCES[k]) for k in SOURCES)
    print("Wrote " + os.path.join(proj_dir, "project.pbxproj"))
    print("  %d targets; source files: %s" % (len(TARGETS), {k: len(SOURCES[k]) for k in SOURCES}))
    print("  %d shared schemes" % len(TARGETS))


if __name__ == "__main__":
    main()
