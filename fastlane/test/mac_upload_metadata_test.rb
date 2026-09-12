# frozen_string_literal: true

require "fastlane"
require "deliver"
require "tmpdir"
require "fileutils"

# Evaluate the real lane, replacing only signing/build/network actions. Deliver's
# actual folder validator must accept the resulting paths with iOS metadata in
# the checkout, even though this lane uploads no listing data.
fastfile_path = File.expand_path("../Fastfile", __dir__)
fastfile = Fastlane::FastFile.new(fastfile_path)
options = nil
fastfile.define_singleton_method(:asc_api_key) { {} }
fastfile.define_singleton_method(:force_manual_signing) { |*| nil }
fastfile.define_singleton_method(:upload_to_app_store) { |**args| options = args }

ENV["MAC_PROFILE_NAME"] = "test-profile"
ENV["APP_BUNDLE_ID"] = "test.daccord"
ENV["APPLE_TEAM_ID"] = "TESTTEAMID"
ENV["APP_STORE_VERSION"] = "0.2.20"

Dir.mktmpdir("daccord-mac-metadata-test-") do |root|
  pkg = File.join(root, "Daccord.pkg")
  File.write(pkg, "test package")
  fastfile.define_singleton_method(:build_app) { |**| pkg }
  Dir.chdir(root) do
    FileUtils.mkdir_p("fastlane/metadata/ios/en-US")
    FileUtils.mkdir_p("fastlane/screenshots/ios/en-US")
    File.write("fastlane/metadata/ios/en-US/privacy_url.txt", "https://example.test/privacy")
    fastfile.runner.lanes.fetch(:mac).fetch(:appstore).call({})

    raise "Lane did not upload the built package" unless options[:pkg] == pkg
    %i[skip_metadata skip_screenshots skip_app_version_update].each do |key|
      raise "Upload-only policy changed: #{key}" unless options[key] == true
    end
    raise "Mac lane must not submit for review" unless options[:submit_for_review] == false
    raise "Language validation must remain enabled" if options[:ignore_language_directory_validation]

    %i[metadata_path screenshots_path].each do |key|
      path = options[key] || "fastlane/#{key == :metadata_path ? 'metadata' : 'screenshots'}"
      # Fresh CI checkouts need not contain any Mac listing directories.
      raise "Unexpected listing files" unless Deliver::Loader.language_folders(path, false).empty?
      FileUtils.mkdir_p(File.join(path, "en-US"))
      languages = Deliver::Loader.language_folders(path, false).map(&:language)
      raise "Mac listing directory is not usable" unless languages == ["en-US"]
    end
  end
end

puts "Mac upload metadata regression passed (missing and populated Mac directories)."
