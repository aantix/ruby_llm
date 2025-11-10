# frozen_string_literal: true

module RubyLLM
  module Providers
    class ClaudeCode
      # Embeddings methods for the Claude Code CLI integration
      # Claude Code doesn't support embeddings, so we raise an error
      module Embeddings
        private

        def embed
          raise Error "Claude Code doesn't support embeddings"
        end

        alias render_embedding_payload embed
        alias embedding_url embed
        alias parse_embedding_response embed
      end
    end
  end
end
