import serial


# -----------------------------
# Config
# -----------------------------
PORT = "COM3"
BAUD = 31250

# -----------------------------
# LUT
# -----------------------------
LAG_TO_NOTE = {
    925: "G#1",
    873: "A1",
    824: "A#1",
    778: "B1",
    734: "C2",
    693: "C#2",
    654: "D2",
    617: "D#2",
    582: "E2",
    550: "F2",
    519: "F#2",
    490: "G2",
    462: "G#2",
    436: "A2",
    412: "A#2",
    389: "B2",
    367: "C3",
    346: "C#3",
    327: "D3",
    309: "D#3",
    291: "E3",
    275: "F3",
    259: "F#3",
    245: "G3",
    231: "G#3",
    218: "A3",
    206: "A#3",
    194: "B3",
    183: "C4",
    173: "C#4",
    163: "D4",
    154: "D#4",
    146: "E4",
    137: "F4",
    130: "F#4",
    122: "G4",
    116: "G#4",
    109: "A4",
    103: "A#4",
    97:  "B4",
    92:  "C5",
    87:  "C#5",
    82:  "D5",
    77:  "D#5",
    73:  "E5",
    69:  "F5",
    65:  "F#5",
    61:  "G5",
    58:  "G#5",
    55:  "A5",
    51:  "A#5",
    49:  "B5",
    46:  "C6",
    43:  "C#6",
    41:  "D6",
    39:  "D#6",
    36:  "E6",
    34:  "F6",
    32:  "F#6",
    31:  "G6",
    29:  "G#6",
    27:  "A6",
    26:  "A#6",
    24:  "B6",
}

def nearest_note_from_lag(lag: int):
    best_lag = min(LAG_TO_NOTE.keys(), key=lambda x: abs(x - lag))
    return best_lag, LAG_TO_NOTE[best_lag]

class Parser:
    def __init__(self):
        self.buf = []

    def parse_byte(self, byte):
        is_start = (byte & 0x80) != 0

        if len(self.buf) == 0:
            if not is_start:
                return
            self.buf.append(byte)
        else:
            if is_start:
                self.buf = [byte]
                return

            self.buf.append(byte)

            if len(self.buf) == 4:
                self.process_packet(self.buf)
                self.buf = []

    def process_packet(self, buf):
        valid = (buf[0] >> 6) & 1
        if not valid:
            return

        period_q = (
            ((buf[0] & 0x3F) << 21) |
            ((buf[1] & 0x7F) << 14) |
            ((buf[2] & 0x7F) << 7)  |
             (buf[3] & 0x7F)
        )

        # Use 10 LSBs for lag
        lag = period_q & 0x3FF

        if lag == 0:
            return

        best_lag, note = nearest_note_from_lag(lag)
        print(f"lag={lag:4d} -> {note}")

def main():
    print(f"Opening {PORT} @ {BAUD} baud")
    ser = serial.Serial(PORT, BAUD, timeout=1)
    parser = Parser()

    try:
        while True:
            data = ser.read(64)
            for b in data:
                parser.parse_byte(b)
    except KeyboardInterrupt:
        print("Stopping...")
        ser.close()

if __name__ == "__main__":
    main()