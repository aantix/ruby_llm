# frozen_string_literal: true

module RubyLLM
  module Providers
    class ClaudeCode
      # Chat methods for the Claude Code CLI integration
      module Chat
        module_function

        def completion_url
          # Not used for CLI-based provider
          nil
        end

        def render_payload(messages, tools:, temperature:, model:, stream: false, schema: nil) # rubocop:disable Metrics/ParameterLists,Lint/UnusedMethodArgument
          # For CLI, we don't need to render a payload in the traditional sense
          # The prompt will be built in the main provider class
          {
            messages: messages,
            tools: tools,
            temperature: temperature,
            model: model,
            stream: stream
          }
        end

        def parse_completion_response(response)
          # Parse CLI output
          # The response for CLI is just a string, not a structured HTTP response
          if response.is_a?(String)
            content = response.strip

            Message.new(
              role: :assistant,
              content: content,
              tool_calls: nil,
              input_tokens: nil,
              output_tokens: nil,
              cached_tokens: nil,
              cache_creation_tokens: nil,
              model_id: 'claude-code',
              raw: response
            )
          else
            # If it's already a Message object, return it
            response
          end
        end

        def format_message(msg)
          # Format message for CLI prompt building
          content = if msg.content.is_a?(RubyLLM::Content)
                      msg.content.text || ''
                    else
                      msg.content.to_s
                    end

          {
            role: convert_role(msg.role),
            content: content
          }
        end

        def convert_role(role)
          case role
          when :tool, :user then 'user'
          when :system then 'system'
          else 'assistant'
          end
        end
      end
    end
  end
end
