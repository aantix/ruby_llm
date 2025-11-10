# frozen_string_literal: true

module RubyLLM
  module Providers
    class ClaudeCode
      # Streaming methods for the Claude Code CLI integration
      module Streaming
        private

        def stream_url
          # Not used for CLI-based provider
          nil
        end

        def build_chunk(data)
          # Parse the stream-json output from Claude CLI
          # The CLI outputs JSON lines with streaming data

          return nil unless data.is_a?(Hash)

          case data['type']
          when 'content_block_delta'
            build_content_chunk(data)
          when 'message_start'
            build_start_chunk(data)
          when 'message_delta'
            build_delta_chunk(data)
          else
            nil
          end
        end

        def build_content_chunk(data)
          Chunk.new(
            role: :assistant,
            model_id: extract_model_id(data),
            content: data.dig('delta', 'text'),
            input_tokens: nil,
            output_tokens: nil,
            cached_tokens: nil,
            cache_creation_tokens: nil,
            tool_calls: extract_tool_calls(data)
          )
        end

        def build_start_chunk(data)
          Chunk.new(
            role: :assistant,
            model_id: extract_model_id(data),
            content: nil,
            input_tokens: extract_input_tokens(data),
            output_tokens: nil,
            cached_tokens: extract_cached_tokens(data),
            cache_creation_tokens: extract_cache_creation_tokens(data),
            tool_calls: nil
          )
        end

        def build_delta_chunk(data)
          Chunk.new(
            role: :assistant,
            model_id: extract_model_id(data),
            content: nil,
            input_tokens: nil,
            output_tokens: extract_output_tokens(data),
            cached_tokens: nil,
            cache_creation_tokens: nil,
            tool_calls: nil
          )
        end

        def json_delta?(data)
          data['type'] == 'content_block_delta' && data.dig('delta', 'type') == 'input_json_delta'
        end

        def parse_streaming_error(data)
          error_data = JSON.parse(data)
          return unless error_data['type'] == 'error'

          case error_data.dig('error', 'type')
          when 'overloaded_error'
            [529, error_data['error']['message']]
          else
            [500, error_data['error']['message']]
          end
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
