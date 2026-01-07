import sys

def clean_byte(b):
    # Keep printable ASCII (except DEL)
    if b >= 0x20 and b != 0x7F:
        return bytes([b])
    
    # Escape common control chars for JSON
    if b == 0x0D: return b'\\r'
    if b == 0x0A: return b'\\n'
    if b == 0x09: return b'\\t'
    
    # Drop other non-printable chars
    return b''

try:
    data = sys.stdin.buffer.read()
    # Process byte by byte
    out = b''.join(clean_byte(b) for b in data)
    sys.stdout.buffer.write(out)
except Exception as e:
    sys.stderr.write(f"Sanitizer Error: {e}\n")
