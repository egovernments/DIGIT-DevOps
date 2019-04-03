import base64
import os
import sys

from Crypto.Cipher import AES


def main():
    # Because kubernetes expects the values in secrets to be base64 encoded
    key = os.environ["EGOV_SECRET_PASSCODE"]
    decryptor = AES.new(key, AES.MODE_ECB)
    print(decryptor.decrypt(base64.b64decode(sys.argv[1])).strip())


if __name__ == "__main__":
    main()
