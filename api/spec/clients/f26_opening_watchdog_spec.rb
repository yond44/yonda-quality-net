# frozen_string_literal: true

require 'rails_helper'

# Audit F26: the server asks the AI to open the interview once, and until the AI
# answers it treats the AI as speaking, so the candidate's microphone stays muted.
# When the AI never answered (seen live, and in 1 of 6 direct tries), the candidate
# was stuck in silence forever: nothing retried, nothing gave the turn back.
RSpec.describe 'F26: an interview whose opening the AI never answers does not hang', type: :service do
  # Stands in for the Gemini WebSocket: records what the client sends.
  let(:socket_class) do
    Class.new do
      attr_reader :sent, :handlers

      def initialize
        @sent = []
        @handlers = {}
      end

      def on(event, &handler) = @handlers[event] = handler
      def send(message) = @sent << JSON.parse(message)
      def close; end
    end
  end
  let(:socket) { socket_class.new }
  let(:timers) { [] } # timers the client schedules, fired by the test instead of waiting

  before do
    allow(Faye::WebSocket::Client).to receive(:new).and_return(socket)
    allow(EM::Timer).to receive(:new) { |_seconds, &block| timers << block && double('timer', cancel: nil) }
    allow(EM::PeriodicTimer).to receive(:new).and_return(double('periodic timer', cancel: nil))
  end

  def ready_client(**callbacks)
    client = Gemini::LiveClient.new(system_prompt: 'prompt', api_key: 'test-key', model: 'test-model', **callbacks)
    client.connect
    gemini_says('setupComplete' => {})
    client
  end

  def gemini_says(message) = socket.handlers[:message].call(double('event', data: message.to_json))
  def openings_sent = socket.sent.count { |m| m.dig('realtimeInput', 'text').to_s.match?(/greet|start/i) }
  def fire_next_timer = timers.shift&.call

  it 'asks the AI again when it has not answered the opening in time' do
    client = ready_client
    client.trigger_opening

    fire_next_timer

    expect(openings_sent).to eq(2)
  end

  it 'gives the turn back after the retry also goes unanswered, so the candidate can speak' do
    unanswered = []
    client = ready_client(on_opening_unanswered: -> { unanswered << :called })
    client.trigger_opening

    2.times { fire_next_timer }

    expect(unanswered).to eq([:called])
  end

  it 'does nothing once the AI starts talking (control)' do
    client = ready_client
    client.trigger_opening
    gemini_says('serverContent' => { 'modelTurn' => { 'parts' => [{ 'inlineData' => { 'data' => Base64.strict_encode64('pcm') } }] } })

    fire_next_timer until timers.empty?

    expect(openings_sent).to eq(1)
  end
end
