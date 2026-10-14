#!/usr/bin/env python3
import poplib
import email
import os
import stat
import subprocess
import time
from email import policy
from email.parser import BytesParser

# POP3 konfiguracija
POP3_SERVER = '10.11.1.6'
POP3_PORT = 110
USERNAME = 'admin01@tq.dev'
PASSWORD = 'adminpass'

# Folder gdje će se spremati .sh fajlovi
SAVE_DIR = '/home/vmail/admin01/mail_sh'
os.makedirs(SAVE_DIR, exist_ok=True)

CHECK_INTERVAL = 30  # sekunde

while True:
    try:
        # Spoji se na POP3
        mail_server = poplib.POP3(POP3_SERVER, POP3_PORT)
        mail_server.user(USERNAME)
        mail_server.pass_(PASSWORD)

        num_messages = len(mail_server.list()[1])
        print(f"Found {num_messages} messages")

        automat_found = False

        for i in range(num_messages):
            response, lines, octets = mail_server.retr(i + 1)
            msg_data = b"\n".join(lines)
            msg = BytesParser(policy=policy.default).parsebytes(msg_data)

            for part in msg.iter_attachments():
                filename = part.get_filename()
                if filename == 'automat.sh':  # Sprema samo ovaj fajl
                    filepath = os.path.join(SAVE_DIR, filename)
                    with open(filepath, 'wb') as f:
                        f.write(part.get_payload(decode=True))
                    # Postavi executable
                    os.chmod(filepath, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP)
                    print(f"Saved and made executable: {filename}")
                    automat_found = True

        mail_server.quit()
        print("Done checking mail.")

        # Ako fajl postoji, runni ga i završi loop
        automat_path = os.path.join(SAVE_DIR, 'automat.sh')
        if automat_found and os.path.exists(automat_path):
            print(f"Running {automat_path}...")
            subprocess.run([automat_path])
            print("Execution finished.")
            break  # izađi iz loopa kad se izvrši

    except Exception as e:
        print(f"Error: {e}")

    print(f"Waiting {CHECK_INTERVAL} seconds before next check...")
    time.sleep(CHECK_INTERVAL)
