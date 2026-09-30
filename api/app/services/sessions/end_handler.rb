# frozen_string_literal: true

module Sessions
  # Handles session termination: closes the session record, creates the portfolio,
  # and enqueues the portfolio generation job (N10).
  # Called on: manual end, all_covered auto-end, time_ceiling, or error.
  class EndHandler
    VALID_REASONS = Session::END_REASONS

    def initialize(session)
      @session = session
    end

    # ended_at: when the interview really stopped. Defaults to now; an abandoned
    # interview passes its last activity so its duration isn't inflated (audit F25).
    def call(reason: 'manual_assessor', ended_at: Time.current)
      # Allow upgrading end_reason from 'error' to a manual reason (candidate/assessor ended cleanly)
      if @session.ended?
        manual = %w[manual_candidate manual_assessor]
        if manual.include?(reason.to_s) && @session.end_reason == 'error'
          @session.update_column(:end_reason, reason.to_s)
        end
        return @session
      end

      reason = 'manual_assessor' unless VALID_REASONS.include?(reason.to_s)

      # "all_covered" is a claim about the interview's data, so it has to be true. The
      # AI saying goodbye, or a call to audio_complete, is not proof (audit F6).
      reason = 'partial_coverage' if reason.to_s == 'all_covered' && !Coverage::MapInjector.new(@session).all_covered?

      ActiveRecord::Base.transaction do
        duration = @session.started_at ? (ended_at - @session.started_at).to_i : nil

        @session.update!(
          status:           'ended',
          end_reason:       reason.to_s,
          ended_at:         ended_at,
          duration_seconds: duration
        )

        create_portfolio
      end

      enqueue_portfolio_generation
      publish_status_update
      Rails.logger.info("[N9/EndHandler] Session #{@session.id} ended (reason=#{reason})")

      @session
    end

    private

    def publish_status_update
      redis = ::Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
      redis.publish("coverage:#{@session.id}", { type: 'session_status', status: @session.status, end_reason: @session.end_reason }.to_json)
    rescue => e
      Rails.logger.error("[EndHandler] Failed to publish status update: #{e.message}")
    ensure
      redis&.close
    end

    def create_portfolio
      # Idempotent — only create if one doesn't exist yet
      return if @session.portfolio.present?

      @session.create_portfolio!(
        candidate_id:      @session.candidate_id,
        generation_status: 'pending'
      )
    end

    def enqueue_portfolio_generation
      portfolio = @session.reload.portfolio
      return unless portfolio

      PortfolioGeneratorWorker.perform_async(@session.id)
      Rails.logger.info("[N9/EndHandler] Enqueued N10 for session #{@session.id}")
    end
  end
end
