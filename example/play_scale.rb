# Play a C-major scale up and back down using MML.

require 'midi'
require 'midi-mml'
require 'sam2695'

device = MIDI::Device.new(SAM2695.new(17, 18))
device.program_change(0)            # Acoustic Grand Piano

seq = MIDI::MML::Sequence.new("o4 l4 cdefgab>cba<gfedc", channel: 0, velocity: 100)
player = MIDI::MML::Player.new(device, seq, loop: false)

MIDI.start!(bpm: 120, output: device, subdivisions: 24) do |clock|
  player.tick(clock)
end
