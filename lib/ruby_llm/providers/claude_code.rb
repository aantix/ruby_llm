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

        raise Error.new(nil, "Claude CLI failed: #{output}") unless status.success?

        parse_cli_response(output)
      ensure
        cleanup_temp_files
      end

      def stream_with_cli(messages, tools:, temperature:, model:, &block)
        prompt = build_prompt(messages, tools:, temperature:, model:)
        execute_claude_cli_streaming(prompt, &block)
      ensure
        cleanup_temp_files
      end

      def build_prompt(messages, tools:, temperature:, model:)
        # Convert messages to a prompt string
        # Extract attachments separately for CLI --attachment flags
        @message_attachments = []

        prompt_parts = messages.map do |msg|
          content_text = extract_content_and_attachments(msg)

          case msg.role
          when :system
            "System: #{content_text}"
          when :user
            "User: #{content_text}"
          when :assistant
            "Assistant: #{content_text}"
          else
            "#{msg.role}: #{content_text}"
          end
        end

        prompt_parts.join("\n\n")
      end

      # Extract text content and include inline @ references for attachments
      def extract_content_and_attachments(msg)
        content = msg.content

        # Handle Content objects with attachments
        if content.is_a?(RubyLLM::Content)
          # Build inline @ references for attachments
          attachment_refs = content.attachments.map do |attachment|
            # Still collect for temp file tracking
            @message_attachments << attachment

            # Get the path and return @ reference
            attachment_path = get_attachment_path(attachment)
            attachment_path ? "@#{attachment_path}" : nil
          end.compact

          # Combine text with @ references
          text_part = content.text || ''
          if attachment_refs.any?
            "#{text_part} #{attachment_refs.join(' ')}"
          else
            text_part
          end
        else
          # Plain string content
          content.to_s
        end
      end

      def execute_claude_cli(prompt, stream: false)
        cmd = build_cli_command(prompt, stream:)
        Rails.logger.debug("Executing Claude CLI command: #{cmd}")

        # Build environment variables from config credentials
        env = build_env_vars
        Rails.logger.debug("ClaudeCode: Environment vars: #{env.keys.join(', ')}") if env.any?

        # Execute from working directory if configured
        options = {}
        if @config.working_directory
          options[:chdir] = @config.working_directory
          Rails.logger.info("ClaudeCode: Executing in working directory: #{@config.working_directory}")
        else
          Rails.logger.warn("ClaudeCode: No working_directory configured, executing in current directory")
        end

        stdout, stderr, status = Open3.capture3(env, cmd, options)

        Rails.logger.debug("Claude CLI stdout: #{stdout}")
        Rails.logger.debug("Claude CLI stderr: #{stderr}")
        Rails.logger.debug("Claude CLI status: #{status.exitstatus}")

        output = stream ? stdout : stdout
        [output, status]
      end

      def execute_claude_cli_streaming(prompt, &block)
        cmd = build_cli_command(prompt, stream: true)

        # Build environment variables from config credentials
        env = build_env_vars

        # Execute from working directory if configured
        options = {}
        if @config.working_directory
          options[:chdir] = @config.working_directory
          Rails.logger.info("ClaudeCode (streaming): Executing in working directory: #{@config.working_directory}")
        else
          Rails.logger.warn("ClaudeCode (streaming): No working_directory configured, executing in current directory")
        end

        Open3.popen2e(env, cmd, options) do |_stdin, stdout_stderr, wait_thr|
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
          raise Error.new(nil, "Claude CLI failed with status #{status.exitstatus}") unless status.success?
        end
      end

      def build_cli_command(prompt, stream:)
        # Escape the prompt for shell - single quotes need to be handled specially
        # We end the string, add an escaped quote, and start a new string: 'text'\''more'
        escaped_prompt = prompt.gsub("'", "'\\\\''")
        cli_path = @config.cli_path || 'claude'

        # Build base command
        cmd_parts = [cli_path]

        # Add output format for streaming
        cmd_parts << "--output-format stream-json" if stream

        # Add the prompt last (attachments are now referenced inline with @ syntax)
        cmd_parts << "'#{escaped_prompt}'"
        cmd_parts.join(' ')
      end

      # Build environment variables hash from config credentials
      # Claude Code CLI reads credentials from environment variables
      def build_env_vars
        env = {}

        # Anthropic API key
        if config_value_present?(:anthropic_api_key)
          env['ANTHROPIC_API_KEY'] = @config.anthropic_api_key
        end

        # AWS Bedrock credentials
        if config_value_present?(:bedrock_api_key)
          env['AWS_ACCESS_KEY_ID'] = @config.bedrock_api_key
        end

        if config_value_present?(:bedrock_secret_key)
          env['AWS_SECRET_ACCESS_KEY'] = @config.bedrock_secret_key
        end

        if config_value_present?(:bedrock_region)
          env['AWS_REGION'] = @config.bedrock_region
        end

        if config_value_present?(:bedrock_session_token)
          env['AWS_SESSION_TOKEN'] = @config.bedrock_session_token
        end

        env
      end

      # Check if a config value is present (not nil and not empty)
      # Uses standard Ruby to avoid ActiveSupport dependency
      def config_value_present?(attr)
        return false unless @config.respond_to?(attr)

        value = @config.send(attr)
        !value.nil? && !value.to_s.strip.empty?
      end

      # Get the file path for an attachment
      # Returns the path if it's a file path, otherwise creates a temporary file
      def get_attachment_path(attachment)
        if attachment.path?
          # Already a file path, use it directly
          attachment.source
        elsif attachment.active_storage?
          # For ActiveStorage, we need to create a temporary file
          create_temp_file_for_attachment(attachment)
        elsif attachment.url?
          # URLs are not supported for CLI attachments
          RubyLLM.logger.warn "URL attachments are not supported for Claude CLI: #{attachment.source}"
          nil
        elsif attachment.io_like?
          # Create a temporary file from IO content
          create_temp_file_for_attachment(attachment)
        else
          RubyLLM.logger.warn "Unsupported attachment type: #{attachment.source.class}"
          nil
        end
      end

      # Create a temporary file for an attachment
      def create_temp_file_for_attachment(attachment)
        require 'tempfile'

        # Track temporary files for cleanup
        @temp_files ||= []

        # Create a temporary file with the proper extension
        ext = File.extname(attachment.filename)
        temp_file = Tempfile.new(['attachment', ext])
        temp_file.binmode
        temp_file.write(attachment.content)
        temp_file.flush
        temp_file.close

        @temp_files << temp_file
        temp_file.path
      end

      # Clean up temporary files created for attachments
      def cleanup_temp_files
        return unless @temp_files

        @temp_files.each do |temp_file|
          temp_file.unlink rescue nil
        end
        @temp_files = []
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
