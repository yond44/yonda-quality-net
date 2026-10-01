# frozen_string_literal: true

module Portfolios
  # N10: Generates a structured skill portfolio from the full transcript
  # and final coverage map using Gemini Pro.
  # Runs post-session as a background job.
  class Generator
    class UnreadableLevel < StandardError; end
    class SkillMismatch < StandardError; end

    LEVEL_TEXT = /\A\s*L?\s*([1-5])\s*\z/i # "3", "L3", "l 3"

    def initialize(session:, gemini_client: nil)
      @session = session
      @gemini_client = gemini_client || Gemini::HttpClient.new(
        model:   ENV.fetch('GEMINI_PRO_MODEL', 'gemini-2.0-pro-001'),
        timeout: 180  # up to 3 minutes for large transcripts
      )
    end

    # Returns the Portfolio record with skills populated.
    def call
      portfolio = @session.portfolio || @session.create_portfolio!(
        candidate_id:      @session.candidate_id,
        generation_status: 'pending'
      )

      portfolio.update!(generation_status: 'generating')

      if candidate_answered?
        response = @gemini_client.generate_content(build_prompt, temperature: 0.2)
        save_skills(portfolio, response)
      else
        # Nothing to grade: don't ask the AI to invent levels (audit F28).
        replace_skills(portfolio, not_assessed_rows('the candidate gave no answers in this interview.'))
      end
      portfolio.update!(generation_status: 'complete', generated_at: Time.current, generation_error: nil)

      Rails.logger.info("[N10] Portfolio generated for session #{@session.id}")
      portfolio
    rescue => e
      portfolio&.update!(generation_status: 'failed', generation_error: e.message)
      Rails.logger.error("[N10] Portfolio generation failed for session #{@session.id}: #{e.class} #{e.message}")
      raise
    end

    private

    def build_prompt
      assessment       = @session.assessment
      configured_skills = assessment.assessment_skills.order(:display_order).to_a
      coverage_maps     = @session.coverage_maps.order(:id)
      turns             = @session.transcript_turns.ordered

      skills_text = configured_skills.map { |s| skill_definition_block(s) }.join("\n\n")

      coverage_json = {
        skills:     coverage_maps.reject(&:is_discovered).map { |m| coverage_json(m, configured_skills) },
        discovered: coverage_maps.select(&:is_discovered).map { |m| coverage_json(m, configured_skills) }
      }.to_json

      transcript_text = turns.map { |t| "[#{t.speaker.upcase}]: #{t.text}" }.join("\n")

      <<~PROMPT
        You are evaluating a completed skills assessment interview to produce a structured skill portfolio.

        ROLE BEING ASSESSED: #{assessment.name}

        SKILL DEFINITIONS AND BEHAVIORAL ANCHORS:
        #{skills_text}

        UNIVERSAL L1-L5 ANCHORS (use for discovered skills):
        L1 — Executes with explicit guidance and close review. Understands conceptually but cannot apply independently.
        L2 — Executes independently on routine scope. Uses known patterns. Handles common cases but not edge cases.
        L3 — Executes complex, ambiguous scope. Makes tradeoffs. Handles edge cases. Can teach L1-L2.
        L4 — Defines standards and creates reusable systems. Resolves systemic problems. Cross-team impact.
        L5 — Org-level authority. Shapes how the skill is practiced. Rare.

        FINAL COVERAGE MAP:
        #{coverage_json}

        FULL INTERVIEW TRANSCRIPT:
        #{transcript_text}

        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        TASK
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        For EACH skill in the coverage map (both configured and discovered):

        1. FIND THE EVIDENCE
           Read all transcript turns where this skill was discussed.
           Identify the 2-3 most revealing quotes from the CANDIDATE (not the AI).
           A quote is revealing if it shows HOW they think, not just WHAT they know.

        2. ASSIGN A LEVEL
           Compare the candidate's actual behavior to the L1-L5 anchors.
           Assign the highest level where you see CONSISTENT evidence, not just one strong moment.
           If evidence is mixed (mostly L2 with one L3 moment), assign L2.
           If the transcript gives no real evidence for a skill (it wasn't discussed, or the
           candidate couldn't say anything about it), set "level" to "not_assessed" and say
           why in competency_summary. Never guess a level without evidence.

        3. WRITE THE COMPETENCY SUMMARY
           2-3 sentences. Focus on patterns, not individual answers.
           What does this person reliably do at this skill? What's the ceiling? What's missing?

        4. ASSIGN CONFIDENCE
           high — probe_count >= 3 AND state = covered
           medium — probe_count = 2 OR state = partial
           low — probe_count <= 1 OR state = initiated

        Answer for EVERY configured skill above, exactly once. For each one, copy the ID in
        brackets after "SKILL:" into "skill_id" exactly as written (for example "S12").

        OUTPUT (JSON only, no prose):
        {
          "configured_skills": [
            {
              "skill_id": "S12",
              "skill_label": "React / Frontend Development",
              "level": 3,
              "confidence": "high",
              "evidence": ["quote 1", "quote 2", "quote 3"],
              "competency_summary": "2-3 sentence summary"
            }
          ],
          "discovered_skills": [
            {
              "skill_label": "Micro-frontend Architecture",
              "level": 2,
              "confidence": "low",
              "evidence": ["quote 1"],
              "competency_summary": "2-3 sentence summary"
            }
          ]
        }
      PROMPT
    end

    def skill_definition_block(skill)
      lines = ["━━━━━━━━━━━━━━━"]
      lines << "SKILL: #{skill.skill_label} (#{skill_ref(skill)})"
      lines << "SCOPE: #{skill.scope_include}" if skill.scope_include.present?
      lines << ""
      lines << "L1 — #{skill.l1_anchor}"
      lines << "L2 — #{skill.l2_anchor}"
      lines << "L3 — #{skill.l3_anchor}"
      lines << "L4 — #{skill.l4_anchor}"
      lines << "L5 — #{skill.l5_anchor}"
      lines.join("\n")
    end

    def coverage_json(map, configured_skills)
      {
        id:          coverage_id(map, configured_skills),
        label:       map.skill_label,
        state:       map.state,
        probe_count: map.probe_count,
        is_discovered: map.is_discovered
      }
    end

    # One id per skill across the whole prompt: a configured skill's coverage entry uses the
    # same reference as the skill list ("S12"), so whichever one the AI copies maps back
    # to the skill (audit F30). Discovered skills aren't configured and keep their own id.
    def coverage_id(map, configured_skills)
      unless map.is_discovered
        skill = configured_skills.find do |s|
          (map.skill_id.present? && s.skill_id == map.skill_id) || s.skill_label.casecmp?(map.skill_label)
        end
        return skill_ref(skill) if skill
      end

      map.skill_id || map.skill_label.downcase.gsub(/\s+/, '-')
    end

    def save_skills(portfolio, response)
      data = response.is_a?(Hash) ? response : JSON.parse(response)

      # Read and check every skill before touching the saved ones, then replace them in
      # one transaction: a bad answer never leaves a half-saved portfolio (audit F5).
      rows = configured_rows(data['configured_skills'] || []) +
             (data['discovered_skills'] || []).map { |skill_data| skill_row(skill_data, discovered: true) }

      replace_skills(portfolio, rows)
    end

    def replace_skills(portfolio, rows)
      PortfolioSkill.transaction do
        portfolio.portfolio_skills.destroy_all # idempotent regeneration
        rows.each { |row| portfolio.portfolio_skills.create!(row) }
      end
    end

    def candidate_answered?
      @session.transcript_turns.where(speaker: 'candidate').exists?
    end

    # Every configured skill, with no level: nothing in the interview to grade it on (audit F28).
    def not_assessed_rows(reason)
      @session.assessment.assessment_skills.order(:display_order).map do |skill|
        { skill_id: skill.skill_id, skill_label: skill.skill_label, is_discovered: false,
          ai_level: nil, ai_confidence: nil, evidence: [], competency_summary: "Not assessed: #{reason}" }
      end
    end

    # Each configured skill gets a unique reference in the prompt ("S" + its row ID),
    # because many skills have no catalogue ID and the AI's wording of a name varies.
    def skill_ref(skill) = "S#{skill.id}"

    # Ties each answer back to the configured skill through the reference the prompt
    # gave it, and stores the skill's configured name and ID, never the AI's wording.
    # A configured skill the AI left out, or an answer for an unknown or repeated
    # reference, fails generation loudly instead of disappearing (audit F7).
    def configured_rows(answers)
      configured = @session.assessment.assessment_skills.index_by { |skill| skill_ref(skill) }
      answered = {}

      answers.each do |skill_data|
        ref = skill_data['skill_id'].to_s.strip
        skill = configured[ref]
        raise SkillMismatch, "AI answered for an unknown skill: #{skill_data['skill_label'].inspect} (#{ref.inspect})" unless skill
        raise SkillMismatch, "AI answered twice for '#{skill.skill_label}'" if answered.key?(ref)

        answered[ref] = skill_row(skill_data, discovered: false, configured_skill: skill)
      end

      missing = configured.except(*answered.keys).values.map(&:skill_label)
      raise SkillMismatch, "AI's answer is missing configured skills: #{missing.join(', ')}" if missing.any?

      answered.values
    end

    def skill_row(skill_data, discovered:, configured_skill: nil)
      level = parse_level(skill_data)
      {
        skill_id:           configured_skill&.skill_id,
        skill_label:        configured_skill&.skill_label || skill_data['skill_label'],
        is_discovered:      discovered,
        ai_level:           level,
        ai_confidence:      level && skill_data['confidence'],
        evidence:           Array(skill_data['evidence']).first(3),
        competency_summary: skill_data['competency_summary'].presence ||
                            (level ? nil : 'Not assessed: there was no evidence for this skill in the interview.')
      }
    end

    # The AI's level as an integer 1-5. Accepts 3, 3.0, "3" and "L3". Anything else
    # (missing, 0, 7, 3.5, "high") raises, so generation fails loudly instead of the
    # old `to_i.clamp(1, 5)`, which turned "L3" and nil into L1 (audit F5).
    #
    # "not_assessed" is the one non-number answer allowed: no evidence for the skill.
    # It returns nil, which is stored as "not assessed", never as a level (audit F28).
    def parse_level(skill_data)
      raw = skill_data['level']
      return nil if raw.is_a?(String) && raw.strip.downcase.tr(' ', '_') == 'not_assessed'

      level = case raw
              when Integer then raw
              when Float   then raw.to_i if raw == raw.floor
              when String  then raw[LEVEL_TEXT, 1]&.to_i
              end
      return level if level&.between?(1, 5)

      raise UnreadableLevel, "Unreadable level for '#{skill_data['skill_label']}': #{raw.inspect}"
    end
  end
end
