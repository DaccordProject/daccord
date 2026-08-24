# frozen_string_literal: true

module Daccord
  # Pure policy for deciding whether an App Store review submission is safe to
  # create. App Store Connect objects are flattened into hashes by the Fastfile
  # adapter, keeping this logic deterministic and independently testable.
  class ReviewSubmissionPolicy
    ACTIVE_REVIEW_STATES = %w[
      CANCELING
      IN_REVIEW
      UNRESOLVED_ISSUES
      WAITING_FOR_REVIEW
    ].freeze
    IDEMPOTENT_REVIEW_STATES = %w[IN_REVIEW WAITING_FOR_REVIEW].freeze
    ACTIVE_VERSION_STATES = %w[IN_REVIEW WAITING_FOR_REVIEW].freeze
    AUTOMATIC_RELEASE_TYPE = "AFTER_APPROVAL"

    Decision = Struct.new(:action, :message, keyword_init: true) do
      def submit?
        action == :submit
      end

      def skip?
        action == :skip
      end

      def fail?
        action == :fail
      end
    end

    def self.decide(target_version:, target_build:, submissions:)
      if submissions.empty?
        return Decision.new(
          action: :submit,
          message: "No App Store review is in progress; submission will continue.",
        )
      end

      if submissions.length != 1
        return failure(
          "App Store Connect returned #{submissions.length} active review submissions; " \
          "refusing to guess which one belongs to this release.",
        )
      end

      submission = submissions.first
      state = submission[:state]
      version = submission[:version]
      build = submission[:build]
      version_state = submission[:version_state]
      release_type = submission[:release_type]

      missing = {
        state: state,
        version: version,
        build: build,
        version_state: version_state,
        release_type: release_type,
      }.select { |_key, value| value.nil? || value.to_s.empty? }.keys
      unless missing.empty?
        return failure(
          "The active App Store review is missing #{missing.join(', ')}; " \
          "its state cannot be verified safely.",
        )
      end

      unless IDEMPOTENT_REVIEW_STATES.include?(state)
        return failure(
          "App Store review #{version} (#{build}) is #{state}; resolve that " \
          "submission in App Store Connect before retrying.",
        )
      end

      if version != target_version || build.to_s != target_build.to_s
        return failure(
          "App Store review #{version} (#{build}) is already #{state}, but this " \
          "release is #{target_version} (#{target_build}).",
        )
      end

      unless ACTIVE_VERSION_STATES.include?(version_state)
        return failure(
          "App Store review #{version} (#{build}) is #{state}, but its version " \
          "state is #{version_state}; refusing to treat inconsistent state as success.",
        )
      end

      unless release_type == AUTOMATIC_RELEASE_TYPE
        return failure(
          "App Store review #{version} (#{build}) is not configured for automatic " \
          "release after approval (release type: #{release_type}).",
        )
      end

      Decision.new(
        action: :skip,
        message: "App Store review #{version} (#{build}) is already #{state} " \
                 "with automatic release; duplicate upload and submission " \
                 "will be skipped.",
      )
    end

    def self.failure(message)
      Decision.new(action: :fail, message: message)
    end
    private_class_method :failure
  end
end
