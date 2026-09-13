#!/usr/bin/env ruby
require 'json'
require 'digest'

abort 'Usage: ruby ci/screenshots/select-card.rb CAPTURE_PROJECT CARD_ID' unless ARGV.length == 2
output = File.realpath(ARGV[0])
root = File.expand_path('../..', __dir__)
abort 'Only temporary capture projects may be updated' unless File.basename(output).start_with?('whiskers-screenshots-')
provenance_path = File.join(output, 'capture-provenance.json')
provenance = JSON.parse(File.read(provenance_path))
abort 'Not an isolated screenshot project' unless provenance.fetch('mode') == 'isolated-preview-no-live-auth'
manifest_path = File.join(root, 'DailyWhiskers/Resources/daily_whiskers_content.json')
abort 'Manifest changed; regenerate the capture project' unless Digest::SHA256.file(manifest_path).hexdigest == provenance.fetch('manifest_sha256')
provenance.fetch('source_sha256').each do |relative, expected|
  original = File.join(root, relative)
  copied = File.join(output, 'Sources', relative)
  unless [original, copied].all? { |path| Digest::SHA256.file(path).hexdigest == expected }
    abort "Source changed; regenerate the capture project: #{relative}"
  end
end
card = JSON.parse(File.read(manifest_path)).fetch('cards').find { |entry| entry.fetch('id') == ARGV[1] }
abort "Unknown card: #{ARGV[1]}" unless card
File.write(File.join(output, 'Resources/daily_whiskers_content.json'), JSON.pretty_generate('cards' => [card]) + "\n")
provenance['card'] = card
File.write(provenance_path, JSON.pretty_generate(provenance) + "\n")
puts "Selected #{card.fetch('id')}; rebuild before capture."
