#!/usr/bin/env ruby
# Generates Typecase.xcodeproj. Re-run after adding or removing source files:
#
#   gem install xcodeproj
#   ruby Tools/generate_xcodeproj.rb
#
# One app target compiles three groups of files: the SwiftUI app (Typecase/), the UI-free logic shared with
# the Swift package used for tests (Core/Sources/GlyphCore/) and the bundled character database (Data/).

require 'fileutils'
require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)

APP_NAME        = 'Typecase'
BUNDLE_ID       = 'com.milanelsen.typecase'
DEPLOYMENT      = '15.0'
PROJECT_PATH    = "#{APP_NAME}.xcodeproj"

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastUpgradeCheck'] = '1600'
project.root_object.attributes['LastSwiftUpdateCheck'] = '1600'
project.root_object.development_region = 'en'
project.root_object.known_regions = %w[en Base nl de]

target = project.new_target(:application, APP_NAME, :osx, DEPLOYMENT)

# ---------------------------------------------------------------- files
swift_files = lambda do |dir|
  Dir.glob("#{dir}/*.swift").sort
end

app_group = project.main_group.new_group(APP_NAME, APP_NAME)
%w[App Services Views].each do |sub|
  group = app_group.new_group(sub, sub)
  swift_files.call("#{APP_NAME}/#{sub}").each do |path|
    target.add_file_references([group.new_file(File.basename(path))])
  end
end

core_group = project.main_group.new_group('GlyphCore', 'Core/Sources/GlyphCore')
swift_files.call('Core/Sources/GlyphCore').each do |path|
  target.add_file_references([core_group.new_file(File.basename(path))])
end

resources_group = app_group.new_group('Resources', 'Resources')
assets = resources_group.new_file('Assets.xcassets')
strings = resources_group.new_file('Localizable.xcstrings')
strings.last_known_file_type = 'text.json.xcstrings'
privacy = resources_group.new_file('PrivacyInfo.xcprivacy')
privacy.last_known_file_type = 'text.xml'
fonts = %w[TypecaseFallback TypecaseFallbackUpper].map { |n| resources_group.new_file("Fonts/#{n}.otf") }
[assets, strings, privacy, *fonts].each { |ref| target.resources_build_phase.add_file_reference(ref) }

data_group = project.main_group.new_group('Data', 'Data')
database = data_group.new_file('characters.json')
target.resources_build_phase.add_file_reference(database)

# Configuration files that are not part of any build phase.
config_group = app_group.new_group('Configuration', nil)
%w[Info.plist Typecase.entitlements Typecase-Direct.entitlements].each do |name|
  ref = config_group.new_file(name)
  ref.last_known_file_type = 'text.plist.entitlements' if name.end_with?('.entitlements')
end

docs_group = project.main_group.new_group('Documentation', nil)
%w[README.md PLAN.md].each { |name| docs_group.new_file(name) if File.exist?(name) }

# ---------------------------------------------------------------- build configurations
def deep_dup(obj)
  Marshal.load(Marshal.dump(obj))
end

# Release-Direct = Release without the App Sandbox, with automatic pasting compiled in (Developer ID builds).
project_release = project.build_configuration_list['Release']
direct_project = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
direct_project.name = 'Release-Direct'
direct_project.build_settings = deep_dup(project_release.build_settings)
project.build_configuration_list.build_configurations << direct_project

target_release = target.build_configuration_list['Release']
direct_target = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
direct_target.name = 'Release-Direct'
direct_target.build_settings = deep_dup(target_release.build_settings)
target.build_configuration_list.build_configurations << direct_target

project.build_configurations.each do |config|
  config.build_settings.merge!(
    'MACOSX_DEPLOYMENT_TARGET' => DEPLOYMENT,
    'SDKROOT' => 'macosx',
    'LOCALIZATION_PREFERS_STRING_CATALOGS' => 'YES',
    'SWIFT_VERSION' => '5.0',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES',
    'CLANG_ENABLE_MODULES' => 'YES',
    'CLANG_ENABLE_OBJC_ARC' => 'YES',
    'ENABLE_STRICT_OBJC_MSGSEND' => 'YES'
  )
end

common = {
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
  'MARKETING_VERSION' => '1.0',
  'CURRENT_PROJECT_VERSION' => '1',
  'SWIFT_VERSION' => '5.0',
  'MACOSX_DEPLOYMENT_TARGET' => DEPLOYMENT,
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'INFOPLIST_FILE' => "#{APP_NAME}/Info.plist",
  'INFOPLIST_KEY_CFBundleDisplayName' => APP_NAME,
  'INFOPLIST_KEY_NSPrincipalClass' => 'NSApplication',
  'ENABLE_HARDENED_RUNTIME' => 'YES',
  'ENABLE_PREVIEWS' => 'YES',
  'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
  'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
  'COMBINE_HIDPI_IMAGES' => 'YES',
  'DEAD_CODE_STRIPPING' => 'YES',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
  'STRING_CATALOG_GENERATE_SYMBOLS' => 'NO',
  'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks'],
  'DEVELOPMENT_TEAM' => '',
  'CODE_SIGN_ENTITLEMENTS' => "#{APP_NAME}/#{APP_NAME}.entitlements",
}

target.build_configurations.each do |config|
  config.build_settings.merge!(common)
  case config.name
  when 'Debug'
    # Signs "to run locally" so the app builds and runs without an Apple Developer account.
    config.build_settings.merge!(
      'CODE_SIGN_STYLE' => 'Manual',
      'CODE_SIGN_IDENTITY' => '-',
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG $(inherited)'
    )
  when 'Release'
    config.build_settings.merge!(
      'CODE_SIGN_STYLE' => 'Automatic',
      'CODE_SIGN_IDENTITY' => 'Apple Development'
    )
  when 'Release-Direct'
    config.build_settings.merge!(
      'CODE_SIGN_STYLE' => 'Automatic',
      'CODE_SIGN_IDENTITY' => 'Apple Development',
      'CODE_SIGN_ENTITLEMENTS' => "#{APP_NAME}/#{APP_NAME}-Direct.entitlements",
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DIRECT_DISTRIBUTION $(inherited)'
    )
  end
end

# ---------------------------------------------------------------- schemes
def make_scheme(project, target, name, archive_configuration)
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.set_launch_target(target)
  scheme.launch_action.build_configuration = 'Debug'
  scheme.test_action.build_configuration = 'Debug'
  scheme.profile_action.build_configuration = 'Release'
  scheme.analyze_action.build_configuration = 'Debug'
  scheme.archive_action.build_configuration = archive_configuration
  scheme.save_as(project.path, name, true)
end

make_scheme(project, target, APP_NAME, 'Release')
make_scheme(project, target, "#{APP_NAME} (Direct)", 'Release-Direct')

project.save

# ---------------------------------------------------------------- sanity checks
missing = project.files
                 .select { |ref| ref.source_tree == '<group>' || ref.source_tree == 'SOURCE_ROOT' }
                 .map(&:real_path)
                 .reject { |p| File.exist?(p) }
abort("Missing files referenced by the project:\n#{missing.join("\n")}") unless missing.empty?
puts "Generated #{PROJECT_PATH}: #{target.source_build_phase.files.count} sources, " \
     "#{target.resources_build_phase.files.count} resources, configurations: " \
     "#{project.build_configurations.map(&:name).join(', ')}"
