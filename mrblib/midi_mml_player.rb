# MIDI MML Player
#
# Plays MML sequences in sync with bpm_loop
# IMPORTANT: Use subdivisions=24 in bpm_loop for accurate timing

module MIDI
  module MML
    # MML Player - plays a sequence at clock ticks
    class Player
      attr_reader :sequence, :playing

      # @param device [MIDI::Device] MIDI output device
      # @param sequence [Sequence] MML sequence to play
      # @param loop [Boolean] Loop playback (default: true)
      def initialize(device, sequence, loop: true)
        @device = device
        @sequence = sequence
        @loop = loop
        @playing = true
        @last_seq_clock = -1
        @active_notes = []  # Track active notes for cleanup
      end

      # Process events at the given clock position
      # Call this from bpm_loop block with subdivisions=24 for accurate timing
      # @param clock [Integer] Current clock count from bpm_loop
      def tick(clock)
        return unless @playing
        return if @sequence.total_length == 0

        # Calculate position within sequence
        seq_clock = clock % @sequence.total_length

        # Detect loop boundary and reset
        if @loop && @last_seq_clock >= 0 && seq_clock < @last_seq_clock
          # Process events at total_length before wrap (for final note_off)
          process_events_at(@sequence.total_length)
          # Turn off any lingering notes
          all_notes_off
        end

        # Process events at current clock position only
        # (subdivisions in bpm_loop controls timing resolution)
        process_events_at(seq_clock)

        @last_seq_clock = seq_clock

        # Check if we've finished (non-looping mode)
        if !@loop && clock >= @sequence.total_length
          all_notes_off
          @playing = false
        end
      end

      # Stop playback and turn off all notes
      def stop
        all_notes_off
        @playing = false
      end

      # Resume playback
      def start
        @playing = true
      end

      # Reset to beginning
      def reset
        all_notes_off
        @last_seq_clock = -1
        @playing = true
      end

      # Turn off all active notes
      def all_notes_off
        @active_notes.each do |note|
          @device.note_off(note, channel: @sequence.channel)
        end
        @active_notes = []  # mrubyc doesn't have Array#clear
      end

      private

      def process_events_at(clock)
        events = @sequence.events_at(clock)
        return if events.length == 0

        events.each do |event|
          case event[:type]
          when :note_on
            @device.note_on(event[:note], event[:velocity], channel: @sequence.channel)
            add_to_active_notes(event[:note])
          when :note_off
            @device.note_off(event[:note], channel: @sequence.channel)
            remove_from_active_notes(event[:note])
          end
        end
      end

      # Add note to active_notes if not already present (mrubyc doesn't have Array#include?)
      def add_to_active_notes(note)
        found = false
        @active_notes.each do |n|
          if n == note
            found = true
            break
          end
        end
        @active_notes << note unless found
      end

      # Remove note from active_notes (mrubyc doesn't have Array#delete)
      def remove_from_active_notes(note)
        new_notes = []
        @active_notes.each do |n|
          new_notes << n unless n == note
        end
        @active_notes = new_notes
      end
    end

    # Combined Player - plays multiple sequences simultaneously
    # Events at the same clock are sent together, note_offs first
    class CombinedPlayer
      attr_reader :playing

      # @param device [MIDI::Device] MIDI output device
      # @param loop [Boolean] Loop playback (default: true)
      def initialize(device, loop: true)
        @device = device
        @loop = loop
        @playing = true
        @last_seq_clock = -1
        @sequence_entries = []  # {sequence: seq, enabled: true}
        @active_notes = []  # [channel, note] pairs
        @longest_length = 0
      end

      # Add a sequence to play
      # @param sequence [Sequence] MML sequence to add
      # @param enabled [Boolean] Initial enabled state (default: true)
      def add_sequence(sequence, enabled: true)
        @sequence_entries << {sequence: sequence, enabled: enabled}
        if sequence.total_length > @longest_length
          @longest_length = sequence.total_length
        end
      end

      # Enable a sequence by index
      # @param index [Integer] Index of the sequence (0-based)
      def enable_sequence(index)
        if index >= 0 && index < @sequence_entries.length
          @sequence_entries[index][:enabled] = true
        end
      end

      # Disable a sequence by index (turns off active notes)
      # @param index [Integer] Index of the sequence (0-based)
      def disable_sequence(index)
        if index >= 0 && index < @sequence_entries.length
          entry = @sequence_entries[index]
          entry[:enabled] = false
          # Turn off notes for this channel
          turn_off_channel_notes(entry[:sequence].channel)
        end
      end

      # Set enabled state of a sequence
      # @param index [Integer] Index of the sequence (0-based)
      # @param enabled [Boolean] Enable or disable
      def set_sequence_enabled(index, enabled)
        if enabled
          enable_sequence(index)
        else
          disable_sequence(index)
        end
      end

      # Process all sequences at the given clock position
      # All note_offs at this clock go out before any note_on, so a note
      # re-struck on the same clock is not cut. Note offs come only from
      # the sequences' note_off events (clock-based), so they follow the
      # tempo of the loop driving tick
      # @param clock [Integer] Current clock count from bpm_loop
      def tick(clock)
        return unless @playing
        return if @longest_length == 0

        # Calculate position within sequence
        seq_clock = clock % @longest_length

        # Detect loop boundary
        if @loop && @last_seq_clock >= 0 && seq_clock < @last_seq_clock
          # Process events at boundary for all enabled sequences
          process_events_at(@longest_length)
          all_notes_off
        end

        process_events_at(seq_clock)

        @last_seq_clock = seq_clock

        # Check if finished (non-looping)
        if !@loop && clock >= @longest_length
          all_notes_off
          @playing = false
        end
      end

      # Stop playback and turn off all notes
      def stop
        all_notes_off
        @playing = false
      end

      # Resume playback
      def start
        @playing = true
      end

      # Reset to beginning
      def reset
        all_notes_off
        @last_seq_clock = -1
        @playing = true
      end

      # Turn off all active notes
      def all_notes_off
        @active_notes.each do |note_info|
          @device.note_off(note_info[:note], channel: note_info[:channel])
        end
        @active_notes = []
      end

      # Turn off active notes for a specific channel
      def turn_off_channel_notes(channel)
        notes_to_remove = []
        @active_notes.each do |note_info|
          if note_info[:channel] == channel
            @device.note_off(note_info[:note], channel: channel)
            notes_to_remove << note_info
          end
        end
        # Remove turned off notes
        notes_to_remove.each do |note_to_remove|
          new_notes = []
          @active_notes.each do |note_info|
            unless note_info[:channel] == note_to_remove[:channel] && note_info[:note] == note_to_remove[:note]
              new_notes << note_info
            end
          end
          @active_notes = new_notes
        end
      end

      private

      # Send the events of all enabled sequences at clock: every note_off
      # first, then every note_on (in sequence order)
      def process_events_at(clock)
        @sequence_entries.each do |entry|
          if entry[:enabled]
            channel = entry[:sequence].channel
            entry[:sequence].events_at(clock).each do |event|
              if event[:type] == :note_off
                @device.note_off(event[:note], channel: channel)
                remove_active_note(channel, event[:note])
              end
            end
          end
        end
        @sequence_entries.each do |entry|
          if entry[:enabled]
            channel = entry[:sequence].channel
            entry[:sequence].events_at(clock).each do |event|
              if event[:type] == :note_on
                @device.note_on(event[:note], event[:velocity] || 100, channel: channel)
                add_active_note(channel, event[:note])
              end
            end
          end
        end
      end

      # Add note to active_notes tracking
      def add_active_note(channel, note)
        # Check if already active (mrubyc doesn't have Array#any?)
        found = false
        @active_notes.each do |info|
          if info[:channel] == channel && info[:note] == note
            found = true
            break
          end
        end
        @active_notes << {channel: channel, note: note} unless found
      end

      # Remove note from active_notes tracking
      def remove_active_note(channel, note)
        new_notes = []
        @active_notes.each do |info|
          unless info[:channel] == channel && info[:note] == note
            new_notes << info
          end
        end
        @active_notes = new_notes
      end
    end
  end
end
