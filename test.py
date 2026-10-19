"""
code.py - Raspberry Pi Pico (CircuitPython) as the pixel sender.

CircuitPython port of use_this.py (the MicroPython original).
Draws on the Spartan-7 VGA display through the 24-wire bus
(vga_bus_top.v + the NEW vga.xdc / vga_bus.xdc must be loaded in the FPGA).

Wiring - plug in order:
  GP0  .. GP15  -> J5 pin5 .. pin20        (bus_d[0..15])
  GP16 .. GP21  -> LCD connector D0 .. D5  (bus_d[16..21])
  GP22          -> LCD connector D6        (parity)
  GP26          -> LCD connector D7        (strobe)
  GND           -> J5 pin4                 (common ground, REQUIRED)
(bus_d[8:0] = X, bus_d[16:9] = Y, bus_d[21:17] = colour.)
LCD E and RS are not used.  The FPGA lights board LED 15 when it rejects a word.

Words go out through an RP2040 PIO state machine (BACKEND = "pio"): GP0..GP22 carry
the 23-bit word and GP26 is the strobe, so the hardware reproduces the protocol at
~0.5 us per pixel.  Python only builds the words, one row at a time.
BACKEND = "digitalio" is the old (very slow) pin-by-pin path, kept as a fallback.

Saving this file as code.py on CIRCUITPY runs it automatically.
Edit the settings just below to change colour, size, or to run the wiring tests.
"""
import time
import array
import board

# ------------------------------------------------------------------ settings
GAME        = True       # True = bouncing-squares speed test (only redraws what changes); wins over DEMO
DEMO        = True       # True = cycle forever through full-screen scenes and print the timing
BACKEND     = "pio"      # "pio" (fast) or "digitalio" (slow fallback; also forced by SLOW)
CPU_HZ      = None       # e.g. 250_000_000 to overclock the Pico (faster word building); None = leave
SCALE       = 5          # font scale (6 is the maximum)
COLOUR      = None       # None = rainbow, or one colour 0..31 ({R[1:0],G,B[1:0]}, 31 = white)
CLEAR_FIRST = False      # True = black out the whole picture first
DO_FRAME    = False      # True = draw a white frame instead of text (wiring check)
DO_CHART    = True       # True = draw the 32-colour chart instead of text (colour wiring check)
SLOW        = False      # True = write all 23 bits every pixel and hold each step 1 ms (timing test)

# PIO timing: setup / hold / gap in PIO clock cycles at PIO_HZ (receiver needs >=50 / >=100 / >=50 ns)
PIO_HZ    = 20_000_000   # 50 ns per cycle
PIO_SETUP = 4            # 200 ns data stable before the strobe rises
PIO_HOLD  = 4            # 200 ns strobe high
PIO_GAP   = 2            # 100 ns strobe low before the next word

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

# ----------------------------------------------------------------- backends
if CPU_HZ:
    import microcontroller
    microcontroller.cpu.frequency = CPU_HZ

if SLOW:
    BACKEND = "digitalio"

_sm = None
if BACKEND == "pio":
    try:
        import rp2pio
        # out pins,23 side 0 [setup] / nop side 1 [hold] / nop side 0 [gap]
        _prog = array.array("H", (
            0x6017 | ((PIO_SETUP - 1) << 8),
            0xA042 | (1 << 12) | ((PIO_HOLD - 1) << 8),
            0xA042 | ((PIO_GAP - 1) << 8),
        ))
        _sm = rp2pio.StateMachine(
            _prog, frequency=PIO_HZ,
            first_out_pin=board.GP0, out_pin_count=23,
            first_sideset_pin=board.GP26, sideset_pin_count=1,
            auto_pull=True, pull_threshold=23, out_shift_right=True,
        )
    except Exception as e:                       # fall back to the slow path
        print("PIO init failed (%r), using digitalio" % (e,))
        _sm = None
if _sm is None:
    BACKEND = "digitalio"
    import digitalio

    def _output(pin):
        p = digitalio.DigitalInOut(pin)
        p.direction = digitalio.Direction.OUTPUT
        p.value = False
        return p

    # bit k of the 23-bit bus word is on GPk for k = 0..22
    BUS    = [_output(getattr(board, "GP%d" % i)) for i in range(23)]
    STROBE = _output(board.GP26)
    _prev = 0            # last value driven on the 23 bus pins (all low at start)


def send(words):
    """Send an array('L') of ready 23-bit words (data + parity) to the FPGA."""
    global _prev
    if _sm is not None:
        _sm.write(words)
        return
    for full in words:
        if SLOW:
            for k in range(23):
                BUS[k].value = bool((full >> k) & 1)
            _prev = full
            time.sleep(0.001)
            STROBE.value = True
            time.sleep(0.001)
            STROBE.value = False
            time.sleep(0.001)
            continue
        diff = full ^ _prev
        if diff:                                         # only touch pins that change
            for k in range(23):
                if (diff >> k) & 1:
                    BUS[k].value = bool((full >> k) & 1)
            _prev = full
        STROBE.value = True
        STROBE.value = False


# -------------------------------------------------------------- word building
def _parity(v):
    v ^= v >> 16
    v ^= v >> 8
    v ^= v >> 4
    v ^= v >> 2
    v ^= v >> 1
    return v & 1

# parity(word) = parity(colour) ^ parity(y) ^ parity(x), so a row is  base ^ XL[x]
XL = [x | (_parity(x) << 22) for x in range(WIDTH)]
_row = array.array("L", [0]) * WIDTH


YB = [(y << 9) | (_parity(y) << 22) for y in range(HEIGHT)]
CB = [(c << 17) | (_parity(c) << 22) for c in range(32)]


def base(y, colour):
    """Word bits that do not depend on x, parity bit included."""
    return YB[y] ^ CB[colour]


def send_run(x, y, w, colour):
    """Send w pixels of one colour starting at (x, y), left to right."""
    b = base(y, colour)
    send(array.array("L", [b ^ v for v in XL[x:x + w]]))


def send_row(y, segs):
    """Send row y; segs = [(x_end, colour), ...] covering x = 0..WIDTH-1 left to right."""
    x0 = 0
    for x1, colour in segs:
        b = base(y, colour)
        _row[x0:x1] = array.array("L", [b ^ v for v in XL[x0:x1]])
        x0 = x1
    send(_row)


def _run(words, y, xa, xb, colour):
    """Append the words for pixels xa..xb-1 of row y to the list."""
    if xb > xa:
        b = base(y, colour)
        words += [b ^ v for v in XL[xa:xb]]


def draw_sprite(ox, oy, nx, ny, size, colour):
    """Move a size x size square from (ox, oy) to (nx, ny), sending only the pixels that
    change (black on the trailing edge, colour on the leading edge) in one send()."""
    words = []
    for y in range(min(oy, ny), max(oy, ny) + size):
        in_old = oy <= y < oy + size
        in_new = ny <= y < ny + size
        if in_old and in_new:
            if nx > ox:
                _run(words, y, ox, min(nx, ox + size), BLACK)
                _run(words, y, max(nx, ox + size), nx + size, colour)
            elif nx < ox:
                _run(words, y, max(nx + size, ox), ox + size, BLACK)
                _run(words, y, nx, min(ox, nx + size), colour)
        elif in_old:
            _run(words, y, ox, ox + size, BLACK)
        elif in_new:
            _run(words, y, nx, nx + size, colour)
    if words:
        send(array.array("L", words))


def fill_rect(x, y, w, h, colour):
    for yy in range(y, y + h):
        send_run(x, yy, w, colour)


# -------------------------------------------------------------------- scenes
def draw_clear(colour=BLACK):
    for y in range(HEIGHT):
        send_run(0, y, WIDTH, colour)


def draw_frame():
    for y in range(HEIGHT):
        if y == 0 or y == HEIGHT - 1:
            send_row(y, [(WIDTH, WHITE)])
        else:
            send_row(y, [(1, WHITE), (WIDTH - 1, BLACK), (WIDTH, WHITE)])


def draw_chart():
    rows = [[(c * 40 + 40, r * 8 + c) for c in range(8)] for r in range(4)]
    for y in range(HEIGHT):
        send_row(y, rows[y // 45])


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


SCENES = [
    ("chart",  draw_chart),
    ("red",    lambda: draw_clear(RED)),
    ("green",  lambda: draw_clear(GREEN)),
    ("blue",   lambda: draw_clear(BLUE)),
    ("frame",  draw_frame),
]


def demo():
    print("backend=%s  %d x %d" % (BACKEND, WIDTH, HEIGHT))
    while True:
        for name, scene in SCENES:
            t0 = time.monotonic_ns()
            scene()
            ms = (time.monotonic_ns() - t0) / 1e6
            print("%-6s %8.1f ms  %6.2f fps" % (name, ms, 1000 / ms))


def game():
    size = 24
    # [x, y, dx, dy, colour]
    sprites = [
        [10,  20,  1,  2, RED],
        [100, 80, -2,  1, GREEN],
        [200, 40,  3, -1, YELLOW],
        [250, 120, -1, -3, CYAN],
    ]
    print("backend=%s  game: %d squares %dx%d" % (BACKEND, len(sprites), size, size))
    draw_clear()
    for s in sprites:
        fill_rect(s[0], s[1], size, size, s[4])
    frames = 0
    t_start = time.monotonic_ns()
    while True:
        for s in sprites:
            ox, oy = s[0], s[1]
            nx, ny = ox + s[2], oy + s[3]
            if nx < 0 or nx > WIDTH - size:
                s[2] = -s[2]
                nx = ox + s[2]
            if ny < 0 or ny > HEIGHT - size:
                s[3] = -s[3]
                ny = oy + s[3]
            s[0], s[1] = nx, ny
            draw_sprite(ox, oy, nx, ny, size, s[4])
        frames += 1
        now = time.monotonic_ns()
        if now - t_start >= 1_000_000_000:
            ms = (now - t_start) / 1e6
            print("%d fps  %.2f ms/frame" % (frames, ms / frames))
            frames = 0
            t_start = now


def main():
    t0 = time.monotonic()
    if CLEAR_FIRST:
        draw_clear()
    if DO_FRAME:
        draw_frame()
    if DO_CHART:
        draw_chart()
    if not DO_FRAME and not DO_CHART:
        colours = RAINBOW if COLOUR is None else [COLOUR & 31]
        draw_text("Connected", max(1, min(SCALE, 6)), colours)
    print("done in %d ms" % int((time.monotonic() - t0) * 1000))


if GAME:
    game()
elif DEMO:
    demo()

# redraw forever so the FPGA catches the picture whenever it becomes ready
while True:
    main()
    time.sleep(2)
