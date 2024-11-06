# System dependencies
## Zig
This repo is currently built on zig 0.13.0.

The recommended way to manage Zig installations is using [zigup](https://github.com/marler8997/zigup).
Once zigup is installed, the following command will install 0.13.0 and set it as your default zig verison.
```sh
zigup 0.13.0
```

# Quickstart
## Simfiles
Simfiles are stored in the `./simfiles` directory.
Assuming the song you want to play is called `mysong`, zig-step expects the directory structure to look like:
```
# project root
- src
- ...
- simfiles
  |- mysong
    |- mysong.sm
    |- mysong.ogg

```

## Run
For now, player settings and song settings are hard coded in `main.zig`.
Edit the variables as desired and run the program:
```sh
zig build run
```

# Missing features and Bugs
Expect many missing features and bugs.
See [`TODO.md`](./TODO.md) for what's on the roadmap and roughly where they sit in terms of prioritisation.
