import socket
import struct

# Configuration matching your script
HOST = '127.0.0.1'
PORT = 5433
USER = 'tester'
DB = 'testdb'
TOKEN = 'fake_token_for_testing'

def test_oauth_handshake():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((HOST, PORT))

    # 1. Send StartupMessage
    user_part = b"user\0" + USER.encode() + b"\0"
    db_part = b"database\0" + DB.encode() + b"\0\0"
    protocol_version = struct.pack('!I', 196608) # 3.0
    payload = protocol_version + user_part + db_part
    packet = struct.pack('!I', len(payload) + 4) + payload
    s.sendall(packet)

    # 2. Receive Auth Request
    response = s.recv(1024)
    if response[0:1] == b'R':
        print("Server requested authentication.")
        if b'OAUTHBEARER' in response:
            print("✅ Success: Server is advertising OAUTHBEARER!")
            
            # 3. Send SASLInitialResponse (KAG-8343 implementation)
            # This follows RFC 7628
            mechanism = b"OAUTHBEARER\0"
            sasl_payload = f"n,,auth=Bearer {TOKEN}\x01\x01".encode()
            
            # p + msg_len + mech_name + payload_len + payload
            p_msg = mechanism + struct.pack('!I', len(sasl_payload)) + sasl_payload
            final_packet = b'p' + struct.pack('!I', len(p_msg) + 4) + p_msg
            
            print(f"Sending RFC 7628 payload: {sasl_payload}")
            s.sendall(final_packet)
            
            # 4. Final Result
            result = s.recv(1024)
            print(f"Final Server Response: {result}")
        else:
            print("❌ Failure: OAUTHBEARER not in SASL list. Check pg_hba.conf.")
    
    s.close()

test_oauth_handshake()
