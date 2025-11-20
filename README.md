# IMXZIG

Very unserious project to get some Zig running on the NXP IMXRT1064 chip. Specifically, I've been using the IMXRT1064DVJ6B, on a custom board that belongs to my employer :)

## Building

Use the right Zig version (currently 0.16.0-dev.1334+06d08daba) and run `zig build`. You can flash zig-out/bin/imxzig.bin to 0x70000000.

## Library

The library itself is in the libIMXRT1064 directory. The outer program is just my non-generic silly stuff I've been writing. Be aware that some stuff that should be made generic is not yet, because I'm still in the discovery process.