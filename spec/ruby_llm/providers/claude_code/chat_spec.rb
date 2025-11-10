# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::ClaudeCode::Chat do
  describe '.parse_completion_response' do
    it 'parses a string response' do
      response = 'Hello from Claude Code!'

      message = described_class.parse_completion_response(response)

      expect(message).to be_a(RubyLLM::Message)
      expect(message.role).to eq(:assistant)
      expect(message.content).to eq('Hello from Claude Code!')
      expect(message.model_id).to eq('claude-code')
    end

    it 'returns a Message object unchanged' do
      original_message = RubyLLM::Message.new(
        role: :assistant,
        content: 'Test content'
      )

      message = described_class.parse_completion_response(original_message)

      expect(message).to eq(original_message)
    end
  end

  describe '.format_message' do
    it 'formats a basic user message' do
      msg = RubyLLM::Message.new(role: :user, content: 'Hello')

      formatted = described_class.format_message(msg)

      expect(formatted[:role]).to eq('user')
      expect(formatted[:content]).to eq('Hello')
    end

    it 'formats a system message' do
      msg = RubyLLM::Message.new(role: :system, content: 'You are a helpful assistant')

      formatted = described_class.format_message(msg)

      expect(formatted[:role]).to eq('system')
      expect(formatted[:content]).to eq('You are a helpful assistant')
    end

    it 'formats an assistant message' do
      msg = RubyLLM::Message.new(role: :assistant, content: 'I can help!')

      formatted = described_class.format_message(msg)

      expect(formatted[:role]).to eq('assistant')
      expect(formatted[:content]).to eq('I can help!')
    end
  end

  describe '.convert_role' do
    it 'converts user role' do
      expect(described_class.convert_role(:user)).to eq('user')
    end

    it 'converts tool role to user' do
      expect(described_class.convert_role(:tool)).to eq('user')
    end

    it 'converts system role' do
      expect(described_class.convert_role(:system)).to eq('system')
    end

    it 'converts assistant role' do
      expect(described_class.convert_role(:assistant)).to eq('assistant')
    end
  end
end
