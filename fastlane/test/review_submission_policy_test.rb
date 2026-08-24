# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/review_submission_policy"

class ReviewSubmissionPolicyTest < Minitest::Test
  TARGET_VERSION = "0.2.13"
  TARGET_BUILD = "32655870310"

  def decide(submissions)
    Daccord::ReviewSubmissionPolicy.decide(
      target_version: TARGET_VERSION,
      target_build: TARGET_BUILD,
      submissions: submissions,
    )
  end

  def active_submission(overrides = {})
    {
      state: "WAITING_FOR_REVIEW",
      version: TARGET_VERSION,
      build: TARGET_BUILD,
      version_state: "WAITING_FOR_REVIEW",
      release_type: "AFTER_APPROVAL",
    }.merge(overrides)
  end

  def test_submits_when_no_review_is_active
    decision = decide([])

    assert_predicate decision, :submit?
  end

  def test_skips_matching_waiting_review
    decision = decide([active_submission])

    assert_predicate decision, :skip?
    assert_includes decision.message, "already WAITING_FOR_REVIEW"
  end

  def test_skips_matching_review_that_apple_is_actively_reviewing
    decision = decide([
      active_submission(state: "IN_REVIEW", version_state: "IN_REVIEW"),
    ])

    assert_predicate decision, :skip?
  end

  def test_fails_for_a_different_marketing_version
    decision = decide([active_submission(version: "0.2.12")])

    assert_predicate decision, :fail?
    assert_includes decision.message, "but this release is #{TARGET_VERSION}"
  end

  def test_fails_for_a_different_build
    decision = decide([active_submission(build: "999")])

    assert_predicate decision, :fail?
    assert_includes decision.message, "but this release is #{TARGET_VERSION}"
  end

  def test_fails_closed_for_unresolved_or_canceling_reviews
    %w[UNRESOLVED_ISSUES CANCELING].each do |state|
      decision = decide([active_submission(state: state)])

      assert_predicate decision, :fail?, state
      assert_includes decision.message, state
    end
  end

  def test_fails_when_automatic_release_is_not_preserved
    decision = decide([active_submission(release_type: "MANUAL")])

    assert_predicate decision, :fail?
    assert_includes decision.message, "not configured for automatic release"
  end

  def test_fails_on_inconsistent_or_incomplete_api_state
    inconsistent = decide([
      active_submission(version_state: "PREPARE_FOR_SUBMISSION"),
    ])
    incomplete = decide([active_submission(build: nil)])

    assert_predicate inconsistent, :fail?
    assert_predicate incomplete, :fail?
    assert_includes incomplete.message, "missing build"
  end

  def test_fails_if_apple_returns_multiple_active_reviews
    decision = decide([active_submission, active_submission])

    assert_predicate decision, :fail?
    assert_includes decision.message, "2 active review submissions"
  end
end
