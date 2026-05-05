# Two-part round: melody on channel 0, bass on channel 1.

require 'midi'
require 'midi-mml'
require 'sam2695'

device = MIDI::Device.new(SAM2695.new(17, 18))
device.program_change(0,  channel: 0)   # Piano on melody channel
device.program_change(32, channel: 1)   # Acoustic Bass on bass channel

melody = MIDI::MML::Sequence.new("o5 l4 cegegegc",   channel: 0, velocity: 90)
bass   = MIDI::MML::Sequence.new("o3 l2 c   g   c",  channel: 1, velocity: 80)

combined = MIDI::MML::CombinedPlayer.new(device, loop: true)
combined.add_sequence(melody)
combined.add_sequence(bass)
combined.start

MIDI.start!(bpm: 100, output: device, subdivisions: 24) do |clock|
  combined.tick(clock)
end
