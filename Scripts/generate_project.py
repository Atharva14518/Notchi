#!/usr/bin/env python3
"""Regenerate the native Xcode project after adding Swift source files."""
from pathlib import Path
from hashlib import sha1
import re

root = Path(__file__).resolve().parent.parent
app_name = re.search(r'static let appName = "([^"]+)"', (root / 'App/AppConfig.swift').read_text()).group(1)
folders = ['App', 'Intents', 'Links', 'Notch', 'Shelf', 'Actions', 'DesignSystem', 'Resources']
sources = sorted(str(p.relative_to(root)) for folder in folders for p in (root / folder).glob('*.swift'))
tests = sorted(str(p.relative_to(root)) for p in (root / 'Tests').glob('*.swift'))
test_core = [p for p in sources if p not in ['App/NotchiApp.swift', 'App/AppDelegate.swift']]
(root / 'Resources' / 'Notchi.md').write_text((root / 'README.md').read_text())
if (root / 'POLISH_REBRAND.md').exists():
    (root / 'Resources' / 'POLISH_REBRAND.md').write_text((root / 'POLISH_REBRAND.md').read_text())
(root / 'Resources' / 'THIRD_PARTY_LICENSES.md').write_text((root / 'THIRD_PARTY_LICENSES.md').read_text())
resources = sorted(str(p.relative_to(root)) for p in (root / 'Resources').iterdir() if p.suffix in ['.icns', '.md', '.xcstrings', '.png'] or p.name in ['ffmpeg', 'ffprobe', 'FFmpegSources', 'FFmpegLicenses', 'Assets.xcassets', 'Fonts'])

def uid(name):
    return sha1(name.encode()).hexdigest()[:24].upper()

def ref(name):
    return uid(name)

def quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

objects = []
def obj(name, value):
    objects.append(f'\t\t{ref(name)} = {{ {value} }};')

def array(values):
    return '(' + ', '.join(values) + (',' if values else '') + ')'

for file in sources + tests + resources + ['Resources/Info.plist']:
    kind = 'sourcecode.swift' if file.endswith('.swift') else ('text.json.xcstrings' if file.endswith('.xcstrings') else ('image.icns' if file.endswith('.icns') else ('text' if file.endswith('.md') else 'text.plist.xml')))
    if file in ['Resources/FFmpegSources', 'Resources/FFmpegLicenses', 'Resources/Fonts']: kind = 'folder'
    if file.endswith('.xcassets'): kind = 'folder.assetcatalog'
    if file.endswith('.png'): kind = 'image.png'
    if file in ['Resources/ffmpeg', 'Resources/ffprobe']: kind = 'compiled.mach-o.executable'
    obj(file, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(Path(file).name)}; sourceTree = "<group>";')
    if file.endswith('.swift') or file in resources:
        obj('build:' + file, f'isa = PBXBuildFile; fileRef = {ref(file)};')
for file in test_core:
    obj('test-build:' + file, f'isa = PBXBuildFile; fileRef = {ref(file)};')
obj('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Notchi.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = NotchiTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
for folder in folders + ['Tests']:
    files = [p for p in sources + tests + resources + ['Resources/Info.plist'] if Path(p).parent.name == folder]
    obj('group:' + folder, f'isa = PBXGroup; children = {array([ref(p) for p in files])}; path = {folder}; sourceTree = "<group>";')
obj('products', f'isa = PBXGroup; children = {array([ref("app-product"), ref("test-product")])}; name = Products; sourceTree = "<group>";')
obj('root', f'isa = PBXGroup; children = {array([ref("group:" + f) for f in folders + ["Tests"]] + [ref("products")])}; sourceTree = "<group>";')
for target, files in [('app', sources), ('test', test_core + tests)]:
    for phase, isa, buildfiles in [('sources', 'PBXSourcesBuildPhase', files), ('frameworks', 'PBXFrameworksBuildPhase', []), ('resources', 'PBXResourcesBuildPhase', resources if target == 'app' else [])]:
        obj(target + '-' + phase, f'isa = {isa}; buildActionMask = 2147483647; files = {array([ref(("test-build:" if target == "test" and f in test_core else "build:") + f) for f in buildfiles])}; runOnlyForDeploymentPostprocessing = 0;')
obj('app-sign-media', 'isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); alwaysOutOfDate = 1; name = "Sign LGPL media engines"; shellPath = /bin/sh; shellScript = ' + quote('"${SRCROOT}/Scripts/sign_media_engines.sh"') + '; runOnlyForDeploymentPostprocessing = 0;')
obj('proxy', f'isa = PBXContainerItemProxy; containerPortal = {ref("project")}; proxyType = 1; remoteGlobalIDString = {ref("app-target")}; remoteInfo = Notchi;')
obj('dependency', f'isa = PBXTargetDependency; target = {ref("app-target")}; targetProxy = {ref("proxy")};')
for target, name, product, type_ in [('app', 'Notchi', 'app-product', 'com.apple.product-type.application'), ('test', 'NotchiTests', 'test-product', 'com.apple.product-type.bundle.unit-test')]:
    deps = [ref('dependency')] if target == 'test' else []
    obj(target + '-target', f'isa = PBXNativeTarget; buildConfigurationList = {ref(target + "-configs")}; buildPhases = {array([ref(target + "-" + p) for p in (["sources", "frameworks", "resources", "sign-media"] if target == "app" else ["sources", "frameworks", "resources"])])}; buildRules = (); dependencies = {array(deps)}; name = {name}; productName = {name}; productReference = {ref(product)}; productType = {quote(type_)};')
for scope in ['project', 'app', 'test']:
    for configuration in ['Debug', 'Release']:
        settings = {}
        if scope == 'project':
            settings = {'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'MACOSX_DEPLOYMENT_TARGET': '14.0', 'SDKROOT': 'macosx', 'SWIFT_VERSION': '5.0', 'SWIFT_STRICT_CONCURRENCY': 'targeted', 'GCC_WARN_UNINITIALIZED_AUTOS': 'YES_AGGRESSIVE', 'CLANG_WARN_DOCUMENTATION_COMMENTS': 'YES', 'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if configuration == 'Debug' else '-O', 'DEBUG_INFORMATION_FORMAT': 'dwarf' if configuration == 'Debug' else 'dwarf-with-dsym'}
            if configuration == 'Debug':
                settings.update({'ENABLE_TESTABILITY': 'YES', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG', 'ONLY_ACTIVE_ARCH': 'YES'})
        elif scope == 'app':
            settings = {'PRODUCT_NAME': app_name, 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'NOTCHI_APP_NAME': app_name, 'SWIFT_EMIT_LOC_STRINGS': 'YES', 'LOCALIZATION_PREFERS_STRING_CATALOGS': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.notchi.Notchi', 'INFOPLIST_FILE': 'Resources/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO', 'CODE_SIGN_STYLE': 'Automatic', 'CODE_SIGN_IDENTITY': '-', 'ENABLE_APP_SANDBOX': 'NO', 'ENABLE_HARDENED_RUNTIME': 'YES', 'COMBINE_HIDPI_IMAGES': 'YES', 'ENABLE_USER_SCRIPT_SANDBOXING': 'NO', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/../Frameworks'}
        else:
            settings = {'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.notchi.NotchiTests', 'GENERATE_INFOPLIST_FILE': 'YES', 'CODE_SIGN_STYLE': 'Automatic', 'CODE_SIGN_IDENTITY': '-', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'}
        encoded = ' '.join(f'{key} = {quote(value)};' for key, value in settings.items())
        obj(scope + '-' + configuration, f'isa = XCBuildConfiguration; buildSettings = {{ {encoded} }}; name = {configuration};')
    obj(scope + '-configs', f'isa = XCConfigurationList; buildConfigurations = {array([ref(scope + "-" + c) for c in ["Debug", "Release"]])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1500; TargetAttributes = {{ {ref("app-target")} = {{ CreatedOnToolsVersion = 15.0; }}; {ref("test-target")} = {{ CreatedOnToolsVersion = 15.0; }}; }}; }}; buildConfigurationList = {ref("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {ref("root")}; productRefGroup = {ref("products")}; projectDirPath = ""; projectRoot = ""; targets = {array([ref("app-target"), ref("test-target")])};')
project = root / 'Notchi.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {ref("project")};\n}}\n')
scheme_dir = project / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
def buildable(target, product, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(target)}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:Notchi.xcodeproj"/>'
app = buildable('app-target', 'Notchi.app', 'Notchi')
test = buildable('test-target', 'NotchiTests.xctest', 'NotchiTests')
(scheme_dir / 'Notchi.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO">{test}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f'Generated Notchi.xcodeproj with {len(sources)} app sources and {len(tests)} test sources.')
