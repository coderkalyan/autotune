# import mido

# print(mido.get_input_names())

# port_name = mido.get_input_names()[0]   # replace with the one you want

# with mido.open_input(port_name) as inport:
#     print(f"Listening on {port_name}")
#     for msg in inport:
#     # Only trigger on initial key press
#         if msg.type == 'note_on' and msg.velocity > 0:
#             print("RAW:", msg.bytes())
#             print("HEX:", msg.hex())
#             print("MSG:", msg)
#             print("-" * 40)

import serial
import mido

SERIAL_PORT = 'COM4'   # <-- change if needed
BAUD_RATE = 31250

ser = serial.Serial(SERIAL_PORT, BAUD_RATE)

print("Available MIDI inputs:")
print(mido.get_input_names())

PORT_NAME = mido.get_input_names()[0]  # pick one

with mido.open_input(PORT_NAME) as inport:
    print(f"Listening on {PORT_NAME}")
    print("Sending MIDI to FPGA...\n")

    for msg in inport:
        ser.write(msg.bytes())
        print(f"Sent to FPGA: {msg.hex()}")