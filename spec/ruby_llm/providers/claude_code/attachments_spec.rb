# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::ClaudeCode do
  let(:config) { RubyLLM.config }
  let(:provider) { described_class.new(config) }
  let(:text_path) { File.join('spec', 'fixtures', 'ruby.txt') }
  let(:pdf_path) { File.join('spec', 'fixtures', 'sample.pdf') }

  describe 'file attachments' do
    describe '#extract_content_and_attachments' do
      it 'extracts text from plain string content' do
        message = RubyLLM::Message.new(role: :user, content: 'Hello')

        text = provider.send(:extract_content_and_attachments, message)

        expect(text).to eq('Hello')
      end

      it 'extracts text and collects attachments from Content objects' do
        content = RubyLLM::Content.new('Summarize this file', text_path)
        message = RubyLLM::Message.new(role: :user, content: content)

        # Reset attachments before test
        provider.instance_variable_set(:@message_attachments, [])

        text = provider.send(:extract_content_and_attachments, message)
        attachments = provider.instance_variable_get(:@message_attachments)

        expect(text).to eq('Summarize this file')
        expect(attachments.length).to eq(1)
        expect(attachments.first).to be_a(RubyLLM::Attachment)
        expect(attachments.first.filename).to eq('ruby.txt')
      end

      it 'handles Content with only attachments (no text)' do
        content = RubyLLM::Content.new(nil, text_path)
        message = RubyLLM::Message.new(role: :user, content: content)

        # Reset attachments before test
        provider.instance_variable_set(:@message_attachments, [])

        text = provider.send(:extract_content_and_attachments, message)
        attachments = provider.instance_variable_get(:@message_attachments)

        expect(text).to eq('')
        expect(attachments.length).to eq(1)
      end

      it 'collects multiple attachments' do
        content = RubyLLM::Content.new('Process these files', [text_path, pdf_path])
        message = RubyLLM::Message.new(role: :user, content: content)

        # Reset attachments before test
        provider.instance_variable_set(:@message_attachments, [])

        text = provider.send(:extract_content_and_attachments, message)
        attachments = provider.instance_variable_get(:@message_attachments)

        expect(text).to eq('Process these files')
        expect(attachments.length).to eq(2)
        expect(attachments.map(&:filename)).to contain_exactly('ruby.txt', 'sample.pdf')
      end
    end

    describe '#get_attachment_path' do
      it 'returns the path for file-based attachments' do
        attachment = RubyLLM::Attachment.new(text_path)

        path = provider.send(:get_attachment_path, attachment)

        expect(path).to be_a(Pathname)
        expect(path.to_s).to eq(text_path)
      end

      it 'creates a temporary file for IO-like attachments' do
        io = StringIO.new('test content')
        attachment = RubyLLM::Attachment.new(io, filename: 'test.txt')

        path = provider.send(:get_attachment_path, attachment)

        expect(path).to be_a(String)
        expect(File.exist?(path)).to be true
        expect(File.read(path)).to eq('test content')

        # Cleanup
        File.unlink(path) if File.exist?(path)
      end

      it 'returns nil for URL-based attachments' do
        attachment = double('Attachment', path?: false, active_storage?: false, url?: true, io_like?: false, source: 'http://example.com/file.txt')

        path = provider.send(:get_attachment_path, attachment)

        expect(path).to be_nil
      end
    end

    describe '#build_cli_command' do
      it 'builds a simple command without attachments' do
        provider.instance_variable_set(:@message_attachments, [])

        cmd = provider.send(:build_cli_command, 'Hello Claude', stream: false)

        expect(cmd).to eq("claude 'Hello Claude'")
      end

      it 'builds a command with a single attachment' do
        attachment = RubyLLM::Attachment.new(text_path)
        provider.instance_variable_set(:@message_attachments, [attachment])

        cmd = provider.send(:build_cli_command, 'Summarize this', stream: false)

        expect(cmd).to include("claude")
        expect(cmd).to include("--attachment '#{text_path}'")
        expect(cmd).to include("'Summarize this'")
      end

      it 'builds a command with multiple attachments' do
        attachments = [
          RubyLLM::Attachment.new(text_path),
          RubyLLM::Attachment.new(pdf_path)
        ]
        provider.instance_variable_set(:@message_attachments, attachments)

        cmd = provider.send(:build_cli_command, 'Compare these', stream: false)

        expect(cmd).to include("claude")
        expect(cmd).to include("--attachment '#{text_path}'")
        expect(cmd).to include("--attachment '#{pdf_path}'")
        expect(cmd).to include("'Compare these'")
      end

      it 'builds a streaming command with attachments' do
        attachment = RubyLLM::Attachment.new(text_path)
        provider.instance_variable_set(:@message_attachments, [attachment])

        cmd = provider.send(:build_cli_command, 'Stream this', stream: true)

        expect(cmd).to include("claude")
        expect(cmd).to include("--attachment '#{text_path}'")
        expect(cmd).to include("--output-format stream-json")
        expect(cmd).to include("'Stream this'")
      end

      it 'escapes special characters in file paths' do
        # Create a mock attachment with a path containing a single quote
        attachment = double('Attachment',
                           path?: true,
                           source: Pathname.new("/path/with'quote/file.txt"))
        provider.instance_variable_set(:@message_attachments, [attachment])

        cmd = provider.send(:build_cli_command, 'Test', stream: false)

        # The single quote in the path should be escaped using the '\'' pattern
        # This ends the string, adds an escaped quote, and starts a new string
        expect(cmd).to include("--attachment '/path/with'\\''quote/file.txt'")
      end
    end

    describe '#cleanup_temp_files' do
      it 'removes temporary files created for attachments' do
        io = StringIO.new('test content')
        attachment = RubyLLM::Attachment.new(io, filename: 'test.txt')

        # Create temp file
        path = provider.send(:get_attachment_path, attachment)
        expect(File.exist?(path)).to be true

        # Cleanup
        provider.send(:cleanup_temp_files)

        expect(File.exist?(path)).to be false
      end

      it 'handles cleanup when no temp files were created' do
        provider.instance_variable_set(:@temp_files, nil)

        expect { provider.send(:cleanup_temp_files) }.not_to raise_error
      end
    end

    describe 'integration with build_prompt' do
      it 'extracts attachments from multiple messages' do
        messages = [
          RubyLLM::Message.new(role: :system, content: 'You are helpful'),
          RubyLLM::Message.new(
            role: :user,
            content: RubyLLM::Content.new('First file', text_path)
          ),
          RubyLLM::Message.new(
            role: :user,
            content: RubyLLM::Content.new('Second file', pdf_path)
          )
        ]

        prompt = provider.send(:build_prompt, messages, tools: nil, temperature: 1.0, model: 'claude')
        attachments = provider.instance_variable_get(:@message_attachments)

        expect(prompt).to include('System: You are helpful')
        expect(prompt).to include('User: First file')
        expect(prompt).to include('User: Second file')
        expect(attachments.length).to eq(2)
        expect(attachments.map(&:filename)).to contain_exactly('ruby.txt', 'sample.pdf')
      end

      it 'resets attachments for each build_prompt call' do
        messages1 = [
          RubyLLM::Message.new(
            role: :user,
            content: RubyLLM::Content.new('First', text_path)
          )
        ]
        messages2 = [
          RubyLLM::Message.new(
            role: :user,
            content: RubyLLM::Content.new('Second', pdf_path)
          )
        ]

        # First call
        provider.send(:build_prompt, messages1, tools: nil, temperature: 1.0, model: 'claude')
        attachments1 = provider.instance_variable_get(:@message_attachments).dup

        # Second call should reset attachments
        provider.send(:build_prompt, messages2, tools: nil, temperature: 1.0, model: 'claude')
        attachments2 = provider.instance_variable_get(:@message_attachments)

        expect(attachments1.length).to eq(1)
        expect(attachments1.first.filename).to eq('ruby.txt')

        expect(attachments2.length).to eq(1)
        expect(attachments2.first.filename).to eq('sample.pdf')
      end
    end
  end
end
