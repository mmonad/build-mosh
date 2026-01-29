# libmosh - Mosh iOS Library

Build system for compiling [Mosh](https://github.com/mobile-shell/mosh) as a static library for iOS.

This is a fork of [blinksh/build-mosh](https://github.com/blinksh/build-mosh), modernized for current iOS development:

- **iOS 17.0+** deployment target
- **arm64** device and **arm64/x86_64** simulator support
- **xcframework** output format
- Uses existing Protobuf framework from Wispy project

## Requirements

```bash
brew install automake autoconf libtool pkg-config protobuf@21
```

Note: protobuf@21 is required to match the Protobuf_C_.xcframework version (3.21.x).

## Building

```bash
git submodule update --init --recursive
./build.sh
```

This will:
1. Build mosh for iOS arm64 (device)
2. Build mosh for iOS Simulator (arm64 + x86_64)
3. Create `mosh.xcframework`
4. Install to `../Frameworks/mosh.xcframework`

## Output

- `mosh.xcframework` - Universal xcframework for iOS
- Installed to `Wispy/Frameworks/mosh.xcframework`

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
- `build-protobuf/` - Protobuf build scripts (not used - we use existing xcframework)

## Credits

- Original [Mosh](https://github.com/mobile-shell/mosh) by Keith Winstein
- iOS port by [Blink Shell](https://github.com/blinksh/mosh)
