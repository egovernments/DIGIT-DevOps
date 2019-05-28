
import base64
import os
import sys
import math

from Crypto.Cipher import AES


def main():
    # Because kubernetes expects the values in secrets to be base64 encoded
    text_to_encrypt = sys.argv[1]
    text_to_encrypt = base64.b64encode(text_to_encrypt)
    padding_length = len(text_to_encrypt)
    if padding_length % 16 != 0 :
        padding_length = padding_length + (16 - padding_length % 16)

    key = os.environ["EGOV_SECRET_PASSCODE"]
    encryptor = AES.new(key, AES.MODE_ECB)
    print base64.b64encode(encryptor.encrypt(text_to_encrypt.rjust(padding_length)))


if __name__ == "__main__":
    main()
