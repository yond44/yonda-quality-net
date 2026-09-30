# frozen_string_literal: true

class Session < ApplicationRecord
  include TenantScoped

  STATUSES   = %w[pending active ended failed].freeze
  # partial_coverage: ended before every skill was covered (audit F6).
  END_REASONS = %w[manual_candidate manual_assessor all_covered partial_coverage time_ceiling error].freeze

  belongs_to :assessment
  has_many :transcript_turns, dependent: :destroy
  has_many :coverage_maps, dependent: :destroy
  has_one  :portfolio, dependent: :destroy

  validates :invite_token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :end_reason, inclusion: { in: END_REASONS }, allow_nil: true

  before_validation :generate_invite_token, on: :create

  scope :active,  -> { where(status: 'active') }
  scope :pending, -> { where(status: 'pending') }
  scope :ended,   -> { where(status: 'ended') }

  # How long past its time limit an `active` interview can still be resuming.
  ABANDONED_AFTER_LIMIT = 15.minutes

  def active?  = status == 'active'
  def ended?   = status == 'ended'
  def pending? = status == 'pending'

  # The candidate opens the interview page of the web app (web/src/App.tsx,
  # "/interview/:token"), not the API, so the link uses the web app's address (audit F3).
  def invite_url
    base = ENV.fetch('WEB_BASE_URL', 'http://localhost:5173').chomp('/')
    "#{base}/interview/#{invite_token}"
  end

  # The time-limit check only runs while the live connection is open, so an interview
  # whose candidate dropped off stayed `active` forever (audit F25). Past its time
  # limit (plus a grace period to resume), it can't be live: end it as an error, at
  # the time it was last active. Called wherever a session is read for display.
  def end_if_abandoned!
    return self unless abandoned?

    last_activity = transcript_turns.maximum(:created_at) || started_at
    Sessions::EndHandler.new(self).call(reason: 'error', ended_at: last_activity)
    self
  end

  def abandoned?(now = Time.current)
    return false unless active? && started_at

    time_limit = Assessment.unscoped.where(id: assessment_id).pick(:time_limit_min)
    time_limit.present? && now > started_at + time_limit.minutes + ABANDONED_AFTER_LIMIT
  end

  private

  def generate_invite_token
    self.invite_token ||= SecureRandom.hex(32)
  end
end
