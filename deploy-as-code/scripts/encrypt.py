
import base64
import os
import sys
import math
import argparse

from Crypto.Cipher import AES


parser = argparse.ArgumentParser()

def parse_args():
    parser.add_argument("-f", "--file", help="File to be encrypted")
    args, unknown = parser.parse_known_args()

    return args

def main():
    args = parse_args()
    if args.file :
        file_to_encrypt = args.file.decode('utf-8','ignore').strip()
        f = open(file_to_encrypt, "r+")
        text_to_encrypt = f.read()  
    else :
        text_to_encrypt = sys.argv[1]

    # Because kubernetes expects the values in secrets to be base64 encoded
    # text_to_encrypt = sys.argv[1]
    text_to_encrypt = base64.b64encode(text_to_encrypt)
    padding_length = len(text_to_encrypt)
    if padding_length % 16 != 0 :
        padding_length = padding_length + (16 - padding_length % 16)

    key = os.environ["EGOV_SECRET_PASSCODE"]
    encryptor = AES.new(key, AES.MODE_ECB)
    print base64.b64encode(encryptor.encrypt(text_to_encrypt.rjust(padding_length)))


if __name__ == "__main__":
    main()
