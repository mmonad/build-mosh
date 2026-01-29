# libmosh - Mosh iOS Library

Build system for compiling [Mosh](https://github.com/mobile-shell/mosh) as a static library for iOS.

This is a fork of [blinksh/build-mosh](https://github.com/blinksh/build-mosh), modernized for current iOS development:

- **iOS 17.0+** deployment target
- **arm64** device and **arm64/x86_64** simulator support
- **xcframework** output format
- Self-contained Protobuf build

## Requirements

```bash
brew install automake autoconf libtool
```

## Building (Self-Contained)

```bash
git submodule update --init --recursive

# Build protobuf first
./build-protobuf/build.sh

# Build mosh
./build.sh
```

## Building (From Wispy Repo)

```bash
# From Wispy root:
./scripts/build-protobuf.sh
./scripts/build-mosh.sh
```

## Output

- `build-protobuf/Protobuf.xcframework` - Protobuf for iOS
- `mosh.xcframework` - Mosh for iOS

When run from Wispy repo, frameworks are also installed to `Wispy/Frameworks/`.

## API

The library exposes a single entry point for the iOS client:

```c
int mosh_main(
    FILE *f_in, FILE *f_out, struct winsize *window_size,
    void (*state_callback)(const void *, const void *, size_t),
    void *state_callback_context,
    const char *ip, const char *port, const char *key, const char *predict_mode,
    const char *encoded_state_buffer, size_t encoded_state_size,
    const char *predict_overwrite
);
```

## Submodules

- `mosh/` - [blinksh/mosh](https://github.com/blinksh/mosh) (mosh-1.4 branch) - Mosh with iOS modifications

## Credits

- Original [Mosh](https://github.com/mobile-shell/mosh) by Keith Winstein
- iOS port by [Blink Shell](https://github.com/blinksh/mosh)
