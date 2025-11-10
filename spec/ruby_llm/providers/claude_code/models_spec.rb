# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::ClaudeCode::Models do
  let(:capabilities) { RubyLLM::Providers::ClaudeCode::Capabilities }
  let(:slug) { 'claude_code' }

  describe '.default_models' do
    it 'returns three default models' do
      models = described_class.default_models(slug, capabilities)

      expect(models.length).to eq(3)
      expect(models.map(&:name)).to include('Claude Code Sonnet', 'Claude Code Haiku', 'Claude Code Opus')
    end

    it 'sets correct provider slug' do
      models = described_class.default_models(slug, capabilities)

      expect(models.all? { |m| m.provider == slug }).to be true
    end
  end

  describe '.build_model_info' do
    it 'builds a complete model info object' do
      model = described_class.build_model_info('sonnet', slug, capabilities)

      expect(model).to be_a(RubyLLM::Model::Info)
      expect(model.id).to eq('claude-code-sonnet')
      expect(model.name).to eq('Claude Code Sonnet')
      expect(model.provider).to eq(slug)
      expect(model.context_window).to eq(200_000)
      expect(model.max_output_tokens).to eq(8_192)
    end

    it 'includes modalities' do
      model = described_class.build_model_info('haiku', slug, capabilities)

      # Modalities is a Model::Modalities object, not a Hash
      expect(model.modalities).not_to be_nil
    end

    it 'includes capabilities' do
      model = described_class.build_model_info('opus', slug, capabilities)

      expect(model.capabilities).to include('streaming')
    end
  end

  describe '.extract_model_id' do
    it 'extracts model ID from nested message data' do
      data = { 'message' => { 'model' => 'claude-sonnet-4-5' } }
      expect(described_class.extract_model_id(data)).to eq('claude-sonnet-4-5')
    end

    it 'returns default when no model ID present' do
      data = {}
      expect(described_class.extract_model_id(data)).to eq('claude-code')
    end
  end

  describe '.extract_input_tokens' do
    it 'extracts input tokens from usage data' do
      data = { 'message' => { 'usage' => { 'input_tokens' => 42 } } }
      expect(described_class.extract_input_tokens(data)).to eq(42)
    end
  end

  describe '.extract_output_tokens' do
    it 'extracts output tokens from nested usage' do
      data = { 'message' => { 'usage' => { 'output_tokens' => 100 } } }
      expect(described_class.extract_output_tokens(data)).to eq(100)
    end

    it 'extracts output tokens from top-level usage' do
      data = { 'usage' => { 'output_tokens' => 150 } }
      expect(described_class.extract_output_tokens(data)).to eq(150)
    end
  end

  describe '.extract_cached_tokens' do
    it 'extracts cached tokens' do
      data = { 'message' => { 'usage' => { 'cache_read_input_tokens' => 21 } } }
      expect(described_class.extract_cached_tokens(data)).to eq(21)
    end
  end
end
