
import base64
import os
import sys

from Crypto.Cipher import AES


def main():

    key = os.environ["EGOV_SECRET_PASSCODE"]
    print(key)
    print(len(key))
    decryptor = AES.new(key, AES.MODE_ECB)
    print decryptor.decrypt(base64.b64decode(sys.argv[1])).strip()


if __name__ == "__main__":
    main()
