"""
code.py - Raspberry Pi Pico (CircuitPython) as the pixel sender.

CircuitPython port of use_this.py (the MicroPython original).
Draws the word "Connected" on the Spartan-7 VGA display through the 24-wire bus
(vga_bus_top.v + the NEW vga.xdc / vga_bus.xdc must be loaded in the FPGA).

Wiring - plug in order:
  GP0  .. GP15  -> J5 pin5 .. pin20        (bus_d[0..15])
  GP16 .. GP21  -> LCD connector D0 .. D5  (bus_d[16..21])
  GP22          -> LCD connector D6        (parity)
  GP26          -> LCD connector D7        (strobe)
  GND           -> J5 pin4                 (common ground, REQUIRED)
(bus_d[8:0] = X, bus_d[16:9] = Y, bus_d[21:17] = colour.)
LCD E and RS are not used.  The FPGA lights board LED 15 when it rejects a word.

Saving this file as code.py on CIRCUITPY runs it automatically.
Edit the settings just below to change colour, size, or to run the wiring tests.
"""
import time
import board
import digitalio

# ------------------------------------------------------------------ settings
SCALE       = 5          # font scale (6 is the maximum)
COLOUR      = None       # None = rainbow, or one colour 0..31 ({R[1:0],G,B[1:0]}, 31 = white)
CLEAR_FIRST = False      # True = black out the whole picture first (slower)
DO_FRAME    = False   # True = draw a white frame instead of text (wiring check)
DO_CHART    = False      # True = draw the 32-colour chart instead of text (colour wiring check)
SLOW        = True       # True = write all 23 bits every pixel and hold each step 1 ms (timing test)

# --------------------------------------------------------------------- pins
def _output(pin):
    p = digitalio.DigitalInOut(pin)
    p.direction = digitalio.Direction.OUTPUT
    p.value = False
    return p

# bit k of the 23-bit bus word is on GPk for k = 0..21; bit 22 (parity) is on GP22
BUS    = [_output(getattr(board, "GP%d" % i)) for i in range(23)]
STROBE = _output(board.GP26)

WIDTH, HEIGHT = 320, 180

BLACK, BLUE, GREEN, CYAN = 0b00000, 0b00011, 0b00100, 0b00111
RED, MAGENTA, YELLOW, WHITE = 0b11000, 0b11011, 0b11100, 0b11111
RAINBOW = [RED, YELLOW, GREEN, CYAN, BLUE, MAGENTA]

# 5x7 font, only the letters needed for "Connected"; bit 4 = leftmost pixel
FONT = {
    "C": [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
    "o": [0b00000, 0b00000, 0b01110, 0b10001, 0b10001, 0b10001, 0b01110],
    "n": [0b00000, 0b00000, 0b10110, 0b11001, 0b10001, 0b10001, 0b10001],
    "e": [0b00000, 0b00000, 0b01110, 0b10001, 0b11111, 0b10000, 0b01110],
    "c": [0b00000, 0b00000, 0b01110, 0b10001, 0b10000, 0b10001, 0b01110],
    "t": [0b01000, 0b01000, 0b11100, 0b01000, 0b01000, 0b01001, 0b00110],
    "d": [0b00001, 0b00001, 0b01101, 0b10011, 0b10001, 0b10011, 0b01101],
}

_prev = 0            # last value driven on the 23 bus pins (all low at start)


def put(x, y, colour):
    """Write one pixel: data + parity, then a strobe pulse."""
    global _prev
    word = (colour << 17) | (y << 9) | x                 # 22 data bits
    p = word
    p ^= p >> 16
    p ^= p >> 8
    p ^= p >> 4
    p ^= p >> 2
    p ^= p >> 1
    full = word | ((p & 1) << 22)                        # + even parity bit
    if SLOW:
        for k in range(23):
            BUS[k].value = bool((full >> k) & 1)
        _prev = full
        time.sleep(0.001)
        STROBE.value = True
        time.sleep(0.001)
        STROBE.value = False
        time.sleep(0.001)
        return
    diff = full ^ _prev
    if diff:                                             # only touch pins that change
        for k in range(23):
            if (diff >> k) & 1:
                BUS[k].value = bool((full >> k) & 1)
        _prev = full
    STROBE.value = True
    STROBE.value = False


def fill_rect(x, y, w, h, colour):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            put(xx, yy, colour)


def clear():
    for y in range(HEIGHT):
        for x in range(WIDTH):
            put(x, y, BLACK)


def draw_frame():
    for x in range(WIDTH):
        put(x, 0, WHITE)
        put(x, HEIGHT - 1, WHITE)
    for y in range(HEIGHT):
        put(0, y, WHITE)
        put(WIDTH - 1, y, WHITE)


def draw_chart():
    for r in range(4):
        for c in range(8):
            fill_rect(c * 40, r * 45, 40, 45, r * 8 + c)


def draw_text(text, scale, colours):
    width = len(text) * 6 * scale - scale
    x0 = (WIDTH - width) // 2
    y0 = (HEIGHT - 7 * scale) // 2
    x = x0
    for i, ch in enumerate(text):
        colour = colours[i % len(colours)]
        for ry, row in enumerate(FONT[ch]):
            for rx in range(5):
                if (row >> (4 - rx)) & 1:
                    fill_rect(x + rx * scale, y0 + ry * scale, scale, scale, colour)
        x += 6 * scale


def main():
    t0 = time.monotonic()
    if CLEAR_FIRST:
        clear()
    if DO_FRAME:
        draw_frame()
    if DO_CHART:
        draw_chart()
    if not DO_FRAME and not DO_CHART:
        colours = RAINBOW if COLOUR is None else [COLOUR & 31]
        draw_text("Connected", max(1, min(SCALE, 6)), colours)
    STROBE.value = False
    print("done in %d ms" % int((time.monotonic() - t0) * 1000))


# redraw forever so the FPGA catches the picture whenever it becomes ready
while True:
    main()
    time.sleep(2)
