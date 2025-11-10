# frozen_string_literal: true

require 'open3'
require 'json'

module RubyLLM
  module Providers
    # Claude Code CLI integration.
    # This provider shells out to the `claude` CLI instead of making HTTP requests.
    class ClaudeCode < Provider
      include ClaudeCode::Chat
      include ClaudeCode::Embeddings
      include ClaudeCode::Media
      include ClaudeCode::Models
      include ClaudeCode::Streaming
      include ClaudeCode::Tools

      def api_base
        # Not used for CLI-based provider
        nil
      end

      def headers
        {}
      end

      # Override the complete method to use CLI instead of HTTP
      def complete(messages, tools:, temperature:, model:, params: {}, headers: {}, schema: nil, &block)
        normalized_temperature = maybe_normalize_temperature(temperature, model)

        if block_given?
          stream_with_cli(messages, tools:, temperature: normalized_temperature, model:, &block)
        else
          sync_with_cli(messages, tools:, temperature: normalized_temperature, model:)
        end
      end

      class << self
        def capabilities
          ClaudeCode::Capabilities
        end

        def configuration_requirements
          # No API key required - uses local CLI
          # Optional: config.claude_code_cli_path can be set if 'claude' is not in PATH
          []
        end

        def local?
          true
        end
      end

      private

      def sync_with_cli(messages, tools:, temperature:, model:)
        prompt = build_prompt(messages, tools:, temperature:, model:)
        output, status = execute_claude_cli(prompt, stream: false)

        raise Error, "Claude CLI failed: #{output}" unless status.success?

        parse_cli_response(output)
      end

      def stream_with_cli(messages, tools:, temperature:, model:, &block)
        prompt = build_prompt(messages, tools:, temperature:, model:)
        execute_claude_cli_streaming(prompt, &block)
      end

      def build_prompt(messages, tools:, temperature:, model:)
        # Convert messages to a prompt string
        prompt_parts = messages.map do |msg|
          case msg.role
          when :system
            "System: #{msg.content}"
          when :user
            "User: #{msg.content}"
          when :assistant
            "Assistant: #{msg.content}"
          else
            "#{msg.role}: #{msg.content}"
          end
        end

        prompt_parts.join("\n\n")
      end

      def execute_claude_cli(prompt, stream: false)
        cmd = build_cli_command(prompt, stream:)
        stdout, stderr, status = Open3.capture3(cmd)

        output = stream ? stdout : stdout
        [output, status]
      end

      def execute_claude_cli_streaming(prompt, &block)
        cmd = build_cli_command(prompt, stream: true)

        Open3.popen2e(cmd) do |_stdin, stdout_stderr, wait_thr|
          stdout_stderr.each_line do |line|
            next if line.strip.empty?

            begin
              data = JSON.parse(line)
              chunk = build_chunk(data)
              block.call(chunk) if chunk
            rescue JSON::ParserError => e
              RubyLLM.logger.warn("Failed to parse CLI output: #{e.message}")
            end
          end

          status = wait_thr.value
          raise Error, "Claude CLI failed with status #{status.exitstatus}" unless status.success?
        end
      end

      def build_cli_command(prompt, stream:)
        # Escape the prompt for shell
        escaped_prompt = prompt.gsub("'", "'\\''")
        cli_path = @config.claude_code_cli_path || 'claude'

        if stream
          "#{cli_path} -p --output-format stream-json '#{escaped_prompt}'"
        else
          "#{cli_path} -p '#{escaped_prompt}'"
        end
      end

      def parse_cli_response(output)
        # Parse the CLI output and convert to a Message
        Message.new(
          role: :assistant,
          content: output.strip,
          tool_calls: nil,
          input_tokens: nil,
          output_tokens: nil,
          cached_tokens: nil,
          cache_creation_tokens: nil,
          model_id: nil,
          raw: output
        )
      end
    end
  end
end
