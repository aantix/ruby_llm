# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::ClaudeCode do
  describe '#build_env_vars' do
    it 'returns empty hash when no credentials configured' do
      config = RubyLLM::Configuration.new
      provider = described_class.new(config)

      env = provider.send(:build_env_vars)

      expect(env).to eq({})
    end

    it 'includes ANTHROPIC_API_KEY when anthropic_api_key is set' do
      config = RubyLLM::Configuration.new
      config.anthropic_api_key = 'sk-ant-test-key'
      provider = described_class.new(config)

      env = provider.send(:build_env_vars)

      expect(env['ANTHROPIC_API_KEY']).to eq('sk-ant-test-key')
    end

    it 'includes AWS credentials when bedrock keys are set' do
      config = RubyLLM::Configuration.new
      config.bedrock_api_key = 'AKIATEST123'
      config.bedrock_secret_key = 'secret123'
      config.bedrock_region = 'us-west-2'
      provider = described_class.new(config)

      env = provider.send(:build_env_vars)

      expect(env['AWS_ACCESS_KEY_ID']).to eq('AKIATEST123')
      expect(env['AWS_SECRET_ACCESS_KEY']).to eq('secret123')
      expect(env['AWS_REGION']).to eq('us-west-2')
    end

    it 'includes AWS_SESSION_TOKEN when bedrock_session_token is set' do
      config = RubyLLM::Configuration.new
      config.bedrock_api_key = 'AKIATEST123'
      config.bedrock_secret_key = 'secret123'
      config.bedrock_session_token = 'session-token-123'
      provider = described_class.new(config)

      env = provider.send(:build_env_vars)

      expect(env['AWS_SESSION_TOKEN']).to eq('session-token-123')
    end

    it 'can include both Anthropic and Bedrock credentials' do
      config = RubyLLM::Configuration.new
      config.anthropic_api_key = 'sk-ant-test-key'
      config.bedrock_api_key = 'AKIATEST123'
      config.bedrock_secret_key = 'secret123'
      provider = described_class.new(config)

      env = provider.send(:build_env_vars)

      expect(env['ANTHROPIC_API_KEY']).to eq('sk-ant-test-key')
      expect(env['AWS_ACCESS_KEY_ID']).to eq('AKIATEST123')
      expect(env['AWS_SECRET_ACCESS_KEY']).to eq('secret123')
    end
  end
end
