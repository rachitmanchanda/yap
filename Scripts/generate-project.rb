#!/usr/bin/env ruby
# frozen_string_literal: true

# This dependency-free generator keeps target membership readable without committing a fragile hand-edited graph.
require "digest"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
PROJECT = File.join(ROOT, "VoiceCards.xcodeproj")

def uuid(key)
  Digest::SHA1.hexdigest(key).upcase[0, 24]
end

def quote(value)
  return value if value.match?(/\A[A-Za-z0-9_.\/+-]+\z/)
  %("#{value.gsub('"', '\\"')}")
end

all_shared = Dir.glob(File.join(ROOT, "Shared/**/*.swift")).map { |path| path.delete_prefix("#{ROOT}/") }.sort
app_sources = all_shared + Dir.glob(File.join(ROOT, "VoiceCardsApp/**/*.swift")).map { |p| p.delete_prefix("#{ROOT}/") }.sort

extension_shared = %w[
  Shared/Intents/StartKeyboardDictationIntent.swift
  Shared/Models/BuiltInModes.swift
  Shared/Models/Card.swift
  Shared/Models/CardSourceType.swift
  Shared/Models/ClipboardItem.swift
  Shared/Models/KeyboardDictationSession.swift
  Shared/Models/PendingOperation.swift
  Shared/Models/PersonalTerm.swift
  Shared/Models/RewriteMode.swift
  Shared/Persistence/CardRepository.swift
  Shared/Persistence/ClipboardRepository.swift
  Shared/Persistence/ModeRepository.swift
  Shared/Persistence/SharedModelContainer.swift
  Shared/Services/ClipboardAssetStore.swift
  Shared/Services/ClipboardCaptureService.swift
  Shared/Utilities/AppGroup.swift
  Shared/Utilities/AppPreferences.swift
  Shared/Utilities/RelativeDateFormatter.swift
  Shared/Utilities/TextNormalizer.swift
]

keyboard_sources = extension_shared + Dir.glob(File.join(ROOT, "VoiceCardsKeyboard/*.swift")).map { |p| p.delete_prefix("#{ROOT}/") }.sort
share_sources = extension_shared + Dir.glob(File.join(ROOT, "VoiceCardsShare/*.swift")).map { |p| p.delete_prefix("#{ROOT}/") }.sort
live_activity_sources = ["Shared/Models/DictationActivityAttributes.swift"] +
  Dir.glob(File.join(ROOT, "VoiceCardsLiveActivity/*.swift")).map { |p| p.delete_prefix("#{ROOT}/") }.sort
test_sources = Dir.glob(File.join(ROOT, "VoiceCardsTests/*.swift")).map { |p| p.delete_prefix("#{ROOT}/") }.sort
ui_test_sources = Dir.glob(File.join(ROOT, "VoiceCardsUITests/*.swift")).map { |p| p.delete_prefix("#{ROOT}/") }.sort

targets = {
  "VoiceCardsApp" => {
    product: "VoiceCards.app",
    product_type: "com.apple.product-type.application",
    sources: app_sources,
    resources: ["VoiceCardsApp/Resources/Assets.xcassets", "VoiceCardsApp/Resources/Localizable.xcstrings"]
  },
  "VoiceCardsKeyboard" => {
    product: "VoiceCardsKeyboard.appex",
    product_type: "com.apple.product-type.app-extension",
    sources: keyboard_sources,
    resources: []
  },
  "VoiceCardsShare" => {
    product: "VoiceCardsShare.appex",
    product_type: "com.apple.product-type.app-extension",
    sources: share_sources,
    resources: []
  },
  "VoiceCardsLiveActivity" => {
    product: "VoiceCardsLiveActivity.appex",
    product_type: "com.apple.product-type.app-extension",
    sources: live_activity_sources,
    resources: []
  },
  "VoiceCardsTests" => {
    product: "VoiceCardsTests.xctest",
    product_type: "com.apple.product-type.bundle.unit-test",
    sources: test_sources,
    resources: []
  },
  "VoiceCardsUITests" => {
    product: "VoiceCardsUITests.xctest",
    product_type: "com.apple.product-type.bundle.ui-testing",
    sources: ui_test_sources,
    resources: []
  }
}

file_paths = targets.values.flat_map { |target| target[:sources] + target[:resources] }.uniq.sort
file_paths += %w[
  Configuration/Debug.xcconfig
  Configuration/Release.xcconfig
  Configuration/Shared.xcconfig
  VoiceCardsApp/Info.plist
  VoiceCardsApp/VoiceCards.entitlements
  VoiceCardsKeyboard/Info.plist
  VoiceCardsKeyboard/VoiceCardsKeyboard.entitlements
  VoiceCardsShare/Info.plist
  VoiceCardsShare/VoiceCardsShare.entitlements
  VoiceCardsLiveActivity/Info.plist
]
file_paths.uniq!

file_type = lambda do |path|
  case path
  when /\.swift$/ then "sourcecode.swift"
  when /\.xcconfig$/ then "text.xcconfig"
  when /\.plist$/, /\.entitlements$/ then "text.plist.xml"
  when /\.xcassets$/ then "folder.assetcatalog"
  when /\.xcstrings$/ then "text.json.xcstrings"
  else "text"
  end
end

out = +"// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n\n"

out << "/* Begin PBXBuildFile section */\n"
targets.each do |target_name, target|
  (target[:sources] + target[:resources]).each do |path|
    out << "\t\t#{uuid("build:#{target_name}:#{path}")} /* #{File.basename(path)} in #{target[:resources].include?(path) ? "Resources" : "Sources"} */ = {isa = PBXBuildFile; fileRef = #{uuid("file:#{path}")} /* #{File.basename(path)} */; };\n"
  end
end
%w[VoiceCardsKeyboard VoiceCardsShare VoiceCardsLiveActivity].each do |name|
  out << "\t\t#{uuid("embed:#{name}")} /* #{name}.appex in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = #{uuid("product:#{name}")} /* #{name}.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };\n"
end
out << "/* End PBXBuildFile section */\n\n"

out << "/* Begin PBXContainerItemProxy section */\n"
%w[VoiceCardsKeyboard VoiceCardsShare VoiceCardsLiveActivity VoiceCardsApp].each do |name|
  out << "\t\t#{uuid("proxy:#{name}")} = {isa = PBXContainerItemProxy; containerPortal = #{uuid("project")} /* Project object */; proxyType = 1; remoteGlobalIDString = #{uuid("target:#{name}")}; remoteInfo = #{name}; };\n"
end
out << "/* End PBXContainerItemProxy section */\n\n"

out << "/* Begin PBXCopyFilesBuildPhase section */\n"
out << "\t\t#{uuid("phase:embed")} /* Embed App Extensions */ = {isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = \"\"; dstSubfolderSpec = 13; files = (\n"
%w[VoiceCardsKeyboard VoiceCardsShare VoiceCardsLiveActivity].each { |name| out << "\t\t\t#{uuid("embed:#{name}")} /* #{name}.appex in Embed App Extensions */,\n" }
out << "\t\t); name = \"Embed App Extensions\"; runOnlyForDeploymentPostprocessing = 0; };\n"
out << "/* End PBXCopyFilesBuildPhase section */\n\n"

out << "/* Begin PBXFileReference section */\n"
file_paths.each do |path|
  out << "\t\t#{uuid("file:#{path}")} /* #{File.basename(path)} */ = {isa = PBXFileReference; lastKnownFileType = #{file_type.call(path)}; path = #{quote(path)}; sourceTree = \"<group>\"; };\n"
end
targets.each do |name, target|
  explicit = target[:product_type].include?("application") ? "wrapper.application" : (target[:product_type].include?("app-extension") ? "wrapper.app-extension" : "wrapper.cfbundle")
  out << "\t\t#{uuid("product:#{name}")} /* #{target[:product]} */ = {isa = PBXFileReference; explicitFileType = #{explicit}; includeInIndex = 0; path = #{target[:product]}; sourceTree = BUILT_PRODUCTS_DIR; };\n"
end
out << "/* End PBXFileReference section */\n\n"

out << "/* Begin PBXFrameworksBuildPhase section */\n"
targets.each_key { |name| out << "\t\t#{uuid("phase:frameworks:#{name}")} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };\n" }
out << "/* End PBXFrameworksBuildPhase section */\n\n"

out << "/* Begin PBXGroup section */\n"
out << "\t\t#{uuid("group:main")} = {isa = PBXGroup; children = (\n"
file_paths.each { |path| out << "\t\t\t#{uuid("file:#{path}")} /* #{File.basename(path)} */,\n" }
out << "\t\t\t#{uuid("group:products")} /* Products */,\n\t\t); sourceTree = \"<group>\"; };\n"
out << "\t\t#{uuid("group:products")} /* Products */ = {isa = PBXGroup; children = (\n"
targets.each_key { |name| out << "\t\t\t#{uuid("product:#{name}")} /* #{targets[name][:product]} */,\n" }
out << "\t\t); name = Products; sourceTree = \"<group>\"; };\n"
out << "/* End PBXGroup section */\n\n"

out << "/* Begin PBXNativeTarget section */\n"
targets.each do |name, target|
  phases = [
    uuid("phase:sources:#{name}"),
    uuid("phase:frameworks:#{name}"),
    uuid("phase:resources:#{name}")
  ]
  phases << uuid("phase:embed") if name == "VoiceCardsApp"
  deps = case name
         when "VoiceCardsApp" then %w[VoiceCardsKeyboard VoiceCardsShare VoiceCardsLiveActivity]
         when "VoiceCardsTests", "VoiceCardsUITests" then %w[VoiceCardsApp]
         else []
         end
  out << "\t\t#{uuid("target:#{name}")} /* #{name} */ = {isa = PBXNativeTarget; buildConfigurationList = #{uuid("configlist:target:#{name}")}; buildPhases = (\n"
  phases.each { |phase| out << "\t\t\t#{phase},\n" }
  out << "\t\t); buildRules = (); dependencies = (\n"
  deps.each { |dep| out << "\t\t\t#{uuid("dependency:#{name}:#{dep}")},\n" }
  out << "\t\t); name = #{name}; productName = #{name}; productReference = #{uuid("product:#{name}")} /* #{target[:product]} */; productType = \"#{target[:product_type]}\"; };\n"
end
out << "/* End PBXNativeTarget section */\n\n"

out << "/* Begin PBXProject section */\n"
out << "\t\t#{uuid("project")} /* Project object */ = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2660; LastUpgradeCheck = 2660; TargetAttributes = {\n"
targets.each_key { |name| out << "\t\t\t#{uuid("target:#{name}")} = {CreatedOnToolsVersion = 26.6; ProvisioningStyle = Automatic; };\n" }
out << "\t\t}; }; buildConfigurationList = #{uuid("configlist:project")}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = #{uuid("group:main")}; productRefGroup = #{uuid("group:products")}; projectDirPath = \"\"; projectRoot = \"\"; targets = (\n"
targets.each_key { |name| out << "\t\t\t#{uuid("target:#{name}")} /* #{name} */,\n" }
out << "\t\t); };\n/* End PBXProject section */\n\n"

out << "/* Begin PBXResourcesBuildPhase section */\n"
targets.each do |name, target|
  out << "\t\t#{uuid("phase:resources:#{name}")} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (\n"
  target[:resources].each { |path| out << "\t\t\t#{uuid("build:#{name}:#{path}")} /* #{File.basename(path)} in Resources */,\n" }
  out << "\t\t); runOnlyForDeploymentPostprocessing = 0; };\n"
end
out << "/* End PBXResourcesBuildPhase section */\n\n"

out << "/* Begin PBXSourcesBuildPhase section */\n"
targets.each do |name, target|
  out << "\t\t#{uuid("phase:sources:#{name}")} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\n"
  target[:sources].each { |path| out << "\t\t\t#{uuid("build:#{name}:#{path}")} /* #{File.basename(path)} in Sources */,\n" }
  out << "\t\t); runOnlyForDeploymentPostprocessing = 0; };\n"
end
out << "/* End PBXSourcesBuildPhase section */\n\n"

out << "/* Begin PBXTargetDependency section */\n"
{
  "VoiceCardsApp" => %w[VoiceCardsKeyboard VoiceCardsShare VoiceCardsLiveActivity],
  "VoiceCardsTests" => %w[VoiceCardsApp],
  "VoiceCardsUITests" => %w[VoiceCardsApp]
}.each do |owner, dependencies|
  dependencies.each do |dep|
    out << "\t\t#{uuid("dependency:#{owner}:#{dep}")} = {isa = PBXTargetDependency; target = #{uuid("target:#{dep}")}; targetProxy = #{uuid("proxy:#{dep}")}; };\n"
  end
end
out << "/* End PBXTargetDependency section */\n\n"

settings_for = lambda do |name, configuration|
  common = {
    "GENERATE_INFOPLIST_FILE" => "NO",
    "PRODUCT_NAME" => "$(TARGET_NAME)",
    "SDKROOT" => "iphoneos"
  }
  specific = case name
             when "VoiceCardsApp"
               {
                 "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
                 "CODE_SIGN_ENTITLEMENTS" => "VoiceCardsApp/VoiceCards.entitlements",
                 "DEVELOPMENT_TEAM" => "6D64M4KBHV",
                 "INFOPLIST_FILE" => "VoiceCardsApp/Info.plist",
                 "PRODUCT_BUNDLE_IDENTIFIER" => "com.APP.VoiceCards",
                 "PRODUCT_NAME" => "VoiceCards"
               }
             when "VoiceCardsKeyboard"
               {
                 "APPLICATION_EXTENSION_API_ONLY" => "YES",
                 "CODE_SIGN_ENTITLEMENTS" => "VoiceCardsKeyboard/VoiceCardsKeyboard.entitlements",
                 "DEVELOPMENT_TEAM" => "6D64M4KBHV",
                 "INFOPLIST_FILE" => "VoiceCardsKeyboard/Info.plist",
                 "PRODUCT_BUNDLE_IDENTIFIER" => "com.APP.VoiceCards.Keyboard",
                 "SKIP_INSTALL" => "YES"
               }
             when "VoiceCardsShare"
               {
                 "APPLICATION_EXTENSION_API_ONLY" => "YES",
                 "CODE_SIGN_ENTITLEMENTS" => "VoiceCardsShare/VoiceCardsShare.entitlements",
                 "DEVELOPMENT_TEAM" => "6D64M4KBHV",
                 "INFOPLIST_FILE" => "VoiceCardsShare/Info.plist",
                 "PRODUCT_BUNDLE_IDENTIFIER" => "com.APP.VoiceCards.Share",
                 "SKIP_INSTALL" => "YES"
               }
             when "VoiceCardsLiveActivity"
               {
                 "APPLICATION_EXTENSION_API_ONLY" => "YES",
                 "INFOPLIST_FILE" => "VoiceCardsLiveActivity/Info.plist",
                 "PRODUCT_BUNDLE_IDENTIFIER" => "com.APP.VoiceCards.LiveActivity",
                 "SKIP_INSTALL" => "YES"
               }
             when "VoiceCardsTests"
               {
                 "BUNDLE_LOADER" => "$(TEST_HOST)",
                 "GENERATE_INFOPLIST_FILE" => "YES",
                 "PRODUCT_BUNDLE_IDENTIFIER" => "com.APP.VoiceCards.Tests",
                 "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/VoiceCards.app/VoiceCards"
               }
             else
               {
                 "GENERATE_INFOPLIST_FILE" => "YES",
                 "PRODUCT_BUNDLE_IDENTIFIER" => "com.APP.VoiceCards.UITests",
                 "TEST_TARGET_NAME" => "VoiceCardsApp"
               }
             end
  common.merge(specific).merge("DEBUG_INFORMATION_FORMAT" => configuration == "Debug" ? "dwarf" : "dwarf-with-dsym")
end

out << "/* Begin XCBuildConfiguration section */\n"
%w[Debug Release].each do |configuration|
  config_ref = uuid("file:Configuration/#{configuration}.xcconfig")
  out << "\t\t#{uuid("config:project:#{configuration}")} = {isa = XCBuildConfiguration; baseConfigurationReference = #{config_ref}; buildSettings = {ALWAYS_SEARCH_USER_PATHS = NO; ENABLE_USER_SCRIPT_SANDBOXING = YES; }; name = #{configuration}; };\n"
end
targets.each_key do |name|
  %w[Debug Release].each do |configuration|
    config_ref = uuid("file:Configuration/#{configuration}.xcconfig")
    out << "\t\t#{uuid("config:target:#{name}:#{configuration}")} = {isa = XCBuildConfiguration; baseConfigurationReference = #{config_ref}; buildSettings = {\n"
    settings_for.call(name, configuration).sort.each { |key, value| out << "\t\t\t#{key} = #{quote(value)};\n" }
    out << "\t\t}; name = #{configuration}; };\n"
  end
end
out << "/* End XCBuildConfiguration section */\n\n"

out << "/* Begin XCConfigurationList section */\n"
out << "\t\t#{uuid("configlist:project")} = {isa = XCConfigurationList; buildConfigurations = (#{uuid("config:project:Debug")}, #{uuid("config:project:Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };\n"
targets.each_key do |name|
  out << "\t\t#{uuid("configlist:target:#{name}")} = {isa = XCConfigurationList; buildConfigurations = (#{uuid("config:target:#{name}:Debug")}, #{uuid("config:target:#{name}:Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };\n"
end
out << "/* End XCConfigurationList section */\n\n"
out << "\t};\n\trootObject = #{uuid("project")} /* Project object */;\n}\n"

FileUtils.mkdir_p(PROJECT)
File.write(File.join(PROJECT, "project.pbxproj"), out)

scheme_dir = File.join(PROJECT, "xcshareddata/xcschemes")
FileUtils.mkdir_p(scheme_dir)

def scheme_xml(name, product, runnable:, test_targets: [])
  buildable = uuid("target:#{name}")
  test_entries = test_targets.map do |target|
    %(<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{uuid("target:#{target}")}" BuildableName="#{target}.xctest" BlueprintName="#{target}" ReferencedContainer="container:VoiceCards.xcodeproj"/></TestableReference>)
  end.join
  runnable_xml = runnable ? %(<BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{buildable}" BuildableName="#{product}" BlueprintName="#{name}" ReferencedContainer="container:VoiceCards.xcodeproj"/></BuildableProductRunnable>) : ""
  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme LastUpgradeVersion="2660" version="1.7">
      <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
        <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{buildable}" BuildableName="#{product}" BlueprintName="#{name}" ReferencedContainer="container:VoiceCards.xcodeproj"/></BuildActionEntry></BuildActionEntries>
      </BuildAction>
      <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>#{test_entries}</Testables></TestAction>
      <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">#{runnable_xml}</LaunchAction>
      <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">#{runnable_xml}</ProfileAction>
      <AnalyzeAction buildConfiguration="Debug"/>
      <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
    </Scheme>
  XML
end

File.write(File.join(scheme_dir, "VoiceCards.xcscheme"), scheme_xml("VoiceCardsApp", "VoiceCards.app", runnable: true, test_targets: %w[VoiceCardsTests VoiceCardsUITests]))
File.write(File.join(scheme_dir, "VoiceCardsKeyboard.xcscheme"), scheme_xml("VoiceCardsKeyboard", "VoiceCardsKeyboard.appex", runnable: false))
File.write(File.join(scheme_dir, "VoiceCardsShare.xcscheme"), scheme_xml("VoiceCardsShare", "VoiceCardsShare.appex", runnable: false))
File.write(File.join(scheme_dir, "VoiceCardsLiveActivity.xcscheme"), scheme_xml("VoiceCardsLiveActivity", "VoiceCardsLiveActivity.appex", runnable: false))
