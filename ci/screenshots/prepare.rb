#!/usr/bin/env ruby
# Generates a separate simulator project; never modifies the shipping project.
require 'json'
require 'fileutils'
require 'tmpdir'
require 'digest'
require 'open3'

root = File.expand_path('../..', __dir__)
card_id = ARGV.fetch(0) { abort 'Usage: ruby ci/screenshots/prepare.rb CARD_ID' }
abort 'Expected one card ID' unless ARGV.length == 1
manifest_path = File.join(root, 'DailyWhiskers/Resources/daily_whiskers_content.json')
manifest = JSON.parse(File.read(manifest_path))
card = manifest.fetch('cards').find { |entry| entry.fetch('id') == card_id }
abort "Unknown card: #{card_id}" unless card

output = Dir.mktmpdir('whiskers-screenshots-')
sources = File.join(output, 'Sources')
resources = File.join(output, 'Resources')
FileUtils.mkdir_p([sources, resources])
hashes = {}
Dir.glob(File.join(root, 'DailyWhiskers/**/*.swift')).sort.each do |source|
  next if %w[DailyWhiskersApp.swift AppRouter.swift].include?(File.basename(source))
  relative = source.delete_prefix(root + '/')
  destination = File.join(sources, relative)
  FileUtils.mkdir_p(File.dirname(destination))
  FileUtils.cp(source, destination)
  hashes[relative] = Digest::SHA256.file(source).hexdigest
  abort "Source copy mismatch: #{relative}" unless Digest::SHA256.file(destination).hexdigest == hashes[relative]
end
FileUtils.cp(File.join(__dir__, 'CaptureApp.swift'), sources)
FileUtils.cp_r(File.join(root, 'DailyWhiskers/Assets.xcassets'), resources)
# A single unmodified production card makes the existing date selector deterministic.
File.write(File.join(resources, 'daily_whiskers_content.json'), JSON.pretty_generate('cards' => [card]) + "\n")

lock_path = File.join(root, 'DailyWhiskers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved')
pins = JSON.parse(File.read(lock_path)).fetch('pins')
firebase = pins.find { |pin| pin.fetch('identity') == 'firebase-ios-sdk' }
abort 'Missing Firebase dependency pin' unless firebase
spec = {
  'name' => 'WhiskersScreenshots',
  'options' => { 'deploymentTarget' => { 'iOS' => '17.0' } },
  'packages' => {
    'Firebase' => { 'url' => firebase.fetch('location'), 'exactVersion' => firebase.fetch('state').fetch('version') }
  },
  'targets' => {
    'WhiskersScreenshots' => {
      'type' => 'application', 'platform' => 'iOS',
      'sources' => [{ 'path' => 'Sources' }, { 'path' => 'Resources', 'buildPhase' => 'resources' }],
      'settings' => { 'base' => {
        'PRODUCT_BUNDLE_IDENTIFIER' => 'com.kenwidemon.dailywhiskers.screenshots',
        'SWIFT_VERSION' => '5.0', 'TARGETED_DEVICE_FAMILY' => '1,2',
        'SUPPORTED_PLATFORMS' => 'iphonesimulator', 'CODE_SIGNING_ALLOWED' => 'NO',
        'GENERATE_INFOPLIST_FILE' => 'YES', 'SKIP_INSTALL' => 'YES',
        'INFOPLIST_KEY_CFBundleDisplayName' => 'Whiskers Screenshots',
        'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => true,
        'INFOPLIST_KEY_UILaunchScreen_Generation' => true,
        'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
        'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon'
      } },
      'dependencies' => [{ 'package' => 'Firebase', 'product' => 'FirebaseAuth' }]
    }
  }
}
File.write(File.join(output, 'project.json'), JSON.pretty_generate(spec) + "\n")
revision, status = Open3.capture2('git', '-C', root, 'rev-parse', 'HEAD')
abort 'Cannot read source revision' unless status.success?
File.write(File.join(output, 'capture-provenance.json'), JSON.pretty_generate(
  'revision' => revision.strip, 'card' => card,
  'manifest_sha256' => Digest::SHA256.file(manifest_path).hexdigest,
  'source_sha256' => hashes, 'mode' => 'isolated-preview-no-live-auth'
) + "\n")
abort 'XcodeGen failed' unless system('xcodegen', 'generate', '--spec', File.join(output, 'project.json'))
lock_directory = File.join(output, 'WhiskersScreenshots.xcodeproj/project.xcworkspace/xcshareddata/swiftpm')
FileUtils.mkdir_p(lock_directory)
FileUtils.cp(lock_path, lock_directory)
puts output
