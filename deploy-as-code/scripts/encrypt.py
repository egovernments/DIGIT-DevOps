
import base64
import os
import sys
import math

from Crypto.Cipher import AES


def main():
    # Because kubernetes expects the values in secrets to be base64 encoded
    b64_encodedtext = base64.b64encode(sys.argv[1])
    padding_length = len(b64_encodedtext)
    if padding_length % 16 != 0 :
        padding_length = padding_length + (16 - padding_length % 16)

    key = os.environ["EGOV_SECRET_PASSCODE"]
    encryptor = AES.new(key, AES.MODE_ECB)
    print base64.b64encode(encryptor.encrypt(b64_encodedtext.rjust(padding_length)))


if __name__ == "__main__":
    main()
