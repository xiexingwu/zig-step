# Generic
- [ ] Song offset
- [ ] Audio/Visual offset
- [ ] Holds
- [ ] Jumps
- [ ] Shocks
- [ ] Auto-generate ghost steps for stops
  - Consider adding a ghost-step []Note and process it when a stop is encountered while timing notes
- [ ] Accurate judgment

# Doubles
- [ ] Judgment (key press detection)

# Tech debt
## Robustness
- [ ] test note array is null-terminated after parsing

## Optimisation
- [ ] Don't load all notes textures at once

## Readability
- [ ] `fn timeNotes` is pretty long. Consider splitting out the note/gimmick logic into smaller functions that pass around a .{time, beatPrev, bpm} state.
- [ ] Should `Summary.gimms` include the inital BPM setting if it's not technically a Gimmick?
- [ ] Migrate `Summary.gimms` to `Chart.gimms` for ssc files.
