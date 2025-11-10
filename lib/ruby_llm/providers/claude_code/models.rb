# frozen_string_literal: true

module RubyLLM
  module Providers
    class ClaudeCode
      # Models methods for the Claude Code CLI integration
      module Models
        module_function

        def models_url
          # Not used for CLI-based provider
          nil
        end

        def parse_list_models_response(response, slug, capabilities)
          # For Claude Code CLI, we define a static list of available models
          # since we can't query the CLI for available models
          default_models(slug, capabilities)
        end

        def default_models(slug, capabilities)
          [
            build_model_info('sonnet', slug, capabilities),
            build_model_info('haiku', slug, capabilities),
            build_model_info('opus', slug, capabilities)
          ]
        end

        def build_model_info(model_name, slug, capabilities)
          model_id = "claude-code-#{model_name}"

          Model::Info.new(
            id: model_id,
            name: "Claude Code #{model_name.capitalize}",
            provider: slug,
            family: capabilities.model_family(model_id),
            created_at: Time.now,
            context_window: capabilities.determine_context_window(model_id),
            max_output_tokens: capabilities.determine_max_tokens(model_id),
            modalities: capabilities.modalities_for(model_id),
            capabilities: capabilities.capabilities_for(model_id),
            pricing: capabilities.pricing_for(model_id),
            metadata: {}
          )
        end

        def extract_model_id(data)
          data.dig('message', 'model') || 'claude-code'
        end

        def extract_input_tokens(data)
          data.dig('message', 'usage', 'input_tokens')
        end

        def extract_output_tokens(data)
          data.dig('message', 'usage', 'output_tokens') || data.dig('usage', 'output_tokens')
        end

        def extract_cached_tokens(data)
          data.dig('message', 'usage', 'cache_read_input_tokens') || data.dig('usage', 'cache_read_input_tokens')
        end

        def extract_cache_creation_tokens(data)
          direct = data.dig('message', 'usage',
                            'cache_creation_input_tokens') || data.dig('usage', 'cache_creation_input_tokens')
          return direct if direct

          breakdown = data.dig('message', 'usage', 'cache_creation') || data.dig('usage', 'cache_creation')
          return unless breakdown.is_a?(Hash)

          breakdown.values.compact.sum
        end
      end
    end
  end
end
