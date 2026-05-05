# picoruby-midi-mml

MML (Music Macro Language) parser and player for `picoruby-midi`.

Parses MS-style MML strings into a sequence of MIDI events that can be
played back through a `MIDI::Device` synced to a `MIDI::Clock`. Supports
multi-track playback via `CombinedPlayer`.

## Usage

```ruby
require 'midi'
require 'midi-mml'
require 'sam2695'

device = MIDI::Device.new(SAM2695.new(17, 18))

# Single sequence
seq = MIDI::MML::Sequence.new("t120 cdefgab>c", channel: 0, velocity: 100)
player = MIDI::MML::Player.new(device, seq, loop: false)

MIDI.start!(bpm: 120, output: device, subdivisions: 24) do |clock|
  player.tick(clock)
end
```

Multiple tracks together:

```ruby
combined = MIDI::MML::CombinedPlayer.new(device)
combined.add_sequence(MIDI::MML::Sequence.new("o4 cdefg",  channel: 0))
combined.add_sequence(MIDI::MML::Sequence.new("o3 c4r4c4r4", channel: 1))
combined.start

MIDI.start!(bpm: 120, output: device, subdivisions: 24) do |clock|
  combined.tick(clock)
end
```

## Supported MML Syntax

| Token | Meaning |
|---|---|
| `cdefgab`     | Notes (case-insensitive) |
| `+`, `#`, `-` | Sharp / flat (e.g. `c+`, `d-`) |
| `<`, `>`      | Octave down / up |
| `o<n>`        | Set octave (default 4) |
| `l<n>`        | Set default note length (`l4` = quarter note) |
| `t<n>`        | (Parsed; tempo is owned by `MIDI.start!`) |
| `r`           | Rest |
| `.`           | Dotted (extend by half) |
| `<n>`         | Length suffix on a note (`c8` = eighth-note C) |
| `[ ... ]<n>`  | Loop block N times (defaults to 2 if N omitted) |

## API

### `MIDI::MML::Sequence`

- `Sequence.new(mml_string, channel: 0, velocity: 100)`
- `events_at(clock)` -> `[[type, note], ...]` events for the given clock

### `MIDI::MML::Player`

- `Player.new(device, sequence, loop: true)`
- `tick(clock)` - Call from a `MIDI.start!` block
- `start` / `stop` / `reset`
- `all_notes_off` - Force-off all currently active notes

### `MIDI::MML::CombinedPlayer`

- `CombinedPlayer.new(device, loop: true)`
- `add_sequence(sequence, enabled: true)`
- `enable_sequence(index)` / `disable_sequence(index)` /
  `set_sequence_enabled(index, enabled)`
- `tick(clock)` / `start` / `stop` / `reset` / `all_notes_off`

## Notes

- Tempo (`t`) is parsed but ignored — the gem assumes the host loop owns
  BPM. Set BPM on `MIDI.start!` instead.
- The player runs off the same clock that `MIDI.start!` exposes, so MML
  playback stays in sync with anything else triggered from the same loop.
