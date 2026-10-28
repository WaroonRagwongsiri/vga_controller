import time
import board
import digitalio

# GP0..GP22 are the 23 data/parity pins. GP26 is the Strobe (clock) pin.
bus_pins = []
for i in range(23):
	pin = digitalio.DigitalInOut(getattr(board, f"GP{i}"))
	pin.direction = digitalio.Direction.OUTPUT
	bus_pins.append(pin)

strobe_pin = digitalio.DigitalInOut(board.GP26)
strobe_pin.direction = digitalio.Direction.OUTPUT
strobe_pin.value = False

def calc_parity(value):
	"""Returns 1 if the number of '1' bits is odd, 0 if even."""
	parity = 0
	while value:
		parity ^= (value & 1)
		value >>= 1
	return parity

def put_pixel(x, y, colour):
	"""Packs (x, y, colour) into a 23-bit word and pulses the strobe pin."""

	# Pack data: X (bits 0-8), Y (bits 9-16), Colour (bits 17-21)
	data = (x & 0x1FF) | ((y & 0xFF) << 9) | ((colour & 0x1F) << 17)

	# Calculate parity bit and place it at bit 22
	parity = calc_parity(data)
	word = data | (parity << 22)

	# Step 1 (SETUP): Set all 23 data pins BEFORE raising the strobe
	for bit_index in range(23):
		bus_pins[bit_index].value = bool((word >> bit_index) & 1)

	# Step 2 (HOLD): Pulse Strobe HIGH so the FPGA reads the pins
	strobe_pin.value = True

	# Step 3 (GAP): Pull Strobe LOW to finish the pixel transfer
	strobe_pin.value = False

# ------------------------------------------------------------------ 3. Draw Example
RED   = 0b11000
GREEN = 0b00100
WHITE = 0b11111

# Draw a red diagonal line
for i in range(180):
	put_pixel(i, i, RED)

# Draw a white dot in the center
put_pixel(160, 90, WHITE)