#!/usr/bin/env python3
"""Generate a small dependency-free Xcode project. Stable IDs keep diffs readable."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "ios"
objects = {}

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(identity, isa, **values):
    key = ident(identity)
    objects[key] = dict(isa=isa, **values)
    return key

def render(value):
    if isinstance(value, dict):
        return "{ " + " ".join(f"{json.dumps(k)} = {render(v)};" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "(" + ", ".join(render(v) for v in value) + ")"
    return json.dumps(str(value))

def configs(name, settings):
    refs = []
    for config in ["Debug", "Release"]:
        s = dict(settings, SWIFT_OPTIMIZATION_LEVEL="-Onone" if config == "Debug" else "-O")
        refs.append(add(name+config, "XCBuildConfiguration", name=config, buildSettings=s))
    return add(name+"configs", "XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")

children, products, targets = [], [], []
for target, folder, suffix, product_type in [
    ("A11yGateDemo", "A11yGateDemo", ".app", "application"),
    ("A11yGateUITests", "A11yGateUITests", ".xctest", "bundle.ui-testing")
]:
    sources = list((IOS / folder).glob("*.swift"))
    if target.endswith("UITests"):
        sources += list((ROOT / "Sources/A11yGateCore").glob("*.swift"))
    builds = []
    import os
    for file in sorted(sources):
        path = os.path.relpath(file, IOS)
        ref = add(path, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=path, sourceTree="<group>")
        children.append(ref)
        builds.append(add(path+"build", "PBXBuildFile", fileRef=ref))
    phase = add(target+"sources", "PBXSourcesBuildPhase", buildActionMask=2147483647,
                files=builds, runOnlyForDeploymentPostprocessing=0)
    framework = add(target+"frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647,
                    files=[], runOnlyForDeploymentPostprocessing=0)
    product = add(target+"product", "PBXFileReference", explicitFileType="wrapper.application" if suffix == ".app" else "wrapper.cfbundle",
                  path=target+suffix, sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    settings = dict(PRODUCT_NAME="$(TARGET_NAME)", PRODUCT_BUNDLE_IDENTIFIER="org.a11ygate."+target,
                    CODE_SIGN_STYLE="Automatic", GENERATE_INFOPLIST_FILE="YES", TARGETED_DEVICE_FAMILY="1",
                    SUPPORTED_PLATFORMS="iphoneos", SUPPORTS_MACCATALYST="NO",
                    CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="0.1.0",
                    LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks @loader_path/Frameworks")
    dependencies = []
    if suffix == ".app":
        settings.update(INFOPLIST_KEY_UILaunchScreen_Generation="YES", INFOPLIST_KEY_UIApplicationSceneManifest_Generation="YES",
                        INFOPLIST_KEY_UISupportedInterfaceOrientations="UIInterfaceOrientationPortrait")
    else:
        settings["TEST_TARGET_NAME"] = "A11yGateDemo"
        settings["INFOPLIST_KEY_NSLocalNetworkUsageDescription"] = "Connect the synthetic accessibility test runner to the optional planner on your Mac."
        proxy = add("proxy", "PBXContainerItemProxy", containerPortal=ident("project"), proxyType=1,
                    remoteGlobalIDString=ident("A11yGateDemo"), remoteInfo="A11yGateDemo")
        dependencies = [add("dependency", "PBXTargetDependency", target=ident("A11yGateDemo"), targetProxy=proxy)]
    targets.append(add(target, "PBXNativeTarget", name=target, productName=target, productReference=product,
                       productType="com.apple.product-type."+product_type, buildConfigurationList=configs(target, settings),
                       buildPhases=[phase, framework], buildRules=[], dependencies=dependencies))

product_group = add("products", "PBXGroup", name="Products", children=products, sourceTree="<group>")
group = add("root", "PBXGroup", children=children+[product_group], sourceTree="<group>")
project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "2660"},
              buildConfigurationList=configs("project", dict(SDKROOT="iphoneos", IPHONEOS_DEPLOYMENT_TARGET="17.0",
                                                            SWIFT_VERSION="6.0", CLANG_ENABLE_MODULES="YES")),
              compatibilityVersion="Xcode 14.0", developmentRegion="en", knownRegions=["en","Base"],
              mainGroup=group, productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets)
out = IOS / "A11yGateDemo.xcodeproj"
out.mkdir(exist_ok=True)
(out / "project.pbxproj").write_text("// !$*UTF8*$!\n"+render(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project))+"\n")
scheme = out / "xcshareddata/xcschemes"
scheme.mkdir(parents=True, exist_ok=True)
def reference(name):
    product = name+(".app" if name == "A11yGateDemo" else ".xctest")
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(name)}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:A11yGateDemo.xcodeproj"/>'
(scheme / "A11yGateDemo.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{reference("A11yGateDemo")}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES" onlyGenerateCoverageForSpecifiedTargets="NO">
<Testables><TestableReference skipped="NO" parallelizable="NO">{reference("A11yGateUITests")}</TestableReference></Testables>
</TestAction>
<LaunchAction buildConfiguration="Debug" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{reference("A11yGateDemo")}</BuildableProductRunnable></LaunchAction>
</Scheme>''')
print(out)
