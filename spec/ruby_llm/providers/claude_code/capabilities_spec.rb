# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::ClaudeCode::Capabilities do
  describe '.determine_context_window' do
    it 'returns 200,000 for all models' do
      expect(described_class.determine_context_window('claude-code-sonnet')).to eq(200_000)
      expect(described_class.determine_context_window('claude-code-haiku')).to eq(200_000)
    end
  end

  describe '.determine_max_tokens' do
    it 'returns 8,192 for Sonnet models' do
      expect(described_class.determine_max_tokens('claude-code-sonnet')).to eq(8_192)
      expect(described_class.determine_max_tokens('sonnet-4-5')).to eq(8_192)
    end

    it 'returns 4,096 for other models' do
      expect(described_class.determine_max_tokens('claude-code-opus')).to eq(4_096)
    end
  end

  describe '.supports_vision?' do
    it 'returns true for Claude 3+ models' do
      expect(described_class.supports_vision?('claude-code-sonnet')).to be true
      expect(described_class.supports_vision?('claude-code-haiku')).to be true
    end

    it 'returns false for Claude 1-2 models' do
      expect(described_class.supports_vision?('claude-1')).to be false
      expect(described_class.supports_vision?('claude-2')).to be false
    end
  end

  describe '.supports_functions?' do
    it 'returns true for Claude 3+ models' do
      expect(described_class.supports_functions?('claude-code-sonnet')).to be true
      expect(described_class.supports_functions?('sonnet')).to be true
    end
  end

  describe '.model_family' do
    it 'identifies sonnet family' do
      expect(described_class.model_family('claude-code-sonnet')).to eq('claude-3-7-sonnet')
      expect(described_class.model_family('sonnet-4-5')).to eq('claude-3-7-sonnet')
    end

    it 'identifies haiku family' do
      expect(described_class.model_family('claude-code-haiku')).to eq('claude-3-5-haiku')
      expect(described_class.model_family('haiku')).to eq('claude-3-5-haiku')
    end

    it 'identifies opus family' do
      expect(described_class.model_family('claude-code-opus')).to eq('claude-3-opus')
      expect(described_class.model_family('opus')).to eq('claude-3-opus')
    end
  end

  describe '.capabilities_for' do
    it 'includes streaming for all models' do
      capabilities = described_class.capabilities_for('claude-code-sonnet')
      expect(capabilities).to include('streaming')
    end

    it 'includes function calling for Claude 3+ models' do
      capabilities = described_class.capabilities_for('claude-code-sonnet')
      expect(capabilities).to include('function_calling')
      expect(capabilities).to include('batch')
    end
  end

  describe '.pricing_for' do
    it 'returns pricing structure for sonnet' do
      pricing = described_class.pricing_for('claude-code-sonnet')

      expect(pricing[:text_tokens][:standard][:input_per_million]).to eq(3.0)
      expect(pricing[:text_tokens][:standard][:output_per_million]).to eq(15.0)
    end

    it 'includes batch pricing' do
      pricing = described_class.pricing_for('claude-code-haiku')

      expect(pricing[:text_tokens][:batch][:input_per_million]).to eq(0.40)
      expect(pricing[:text_tokens][:batch][:output_per_million]).to eq(2.0)
    end
  end
end
