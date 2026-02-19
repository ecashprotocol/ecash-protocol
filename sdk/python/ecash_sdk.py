"""
eCash Protocol v3 SDK (Python)

Utility functions for solving puzzles on the eCash protocol.

Installation:
    pip install scrypt pycryptodome eth-abi web3

Usage:
    from ecash_sdk import normalize, try_decrypt, compute_commit_hash
"""

import re
import json
import hashlib
import secrets
from typing import Optional, Dict, Any, Tuple

import scrypt
from Crypto.Cipher import AES
from eth_abi.packed import encode_packed
from web3 import Web3

# Scrypt parameters (MUST match contract)
SCRYPT_N = 131072  # 2^17
SCRYPT_R = 8
SCRYPT_P = 1
SCRYPT_KEY_LEN = 32


def normalize(answer: str) -> str:
    """
    Normalize an answer to match the contract's normalization.
    - Lowercase
    - Strip non-ASCII and punctuation (keep only a-z, 0-9, space)
    - Collapse multiple spaces
    - Trim
    """
    result = answer.lower()
    result = re.sub(r'[^a-z0-9 ]', '', result)
    result = re.sub(r'\s+', ' ', result)
    return result.strip()


def derive_key(puzzle_id: int, guess: str) -> bytes:
    """
    Derive scrypt key from a guess for a specific puzzle.
    """
    salt = f"ecash-v3-{puzzle_id}"
    key = scrypt.hash(
        guess.encode('utf-8'),
        salt.encode('utf-8'),
        N=SCRYPT_N,
        r=SCRYPT_R,
        p=SCRYPT_P,
        buflen=SCRYPT_KEY_LEN
    )
    return key


def try_decrypt(puzzle_id: int, guess: str, blob_data: Dict[str, str]) -> Dict[str, Any]:
    """
    Try to decrypt a puzzle's blob with a guess.
    Returns the decrypted data if successful, None otherwise.

    Args:
        puzzle_id: The puzzle ID
        guess: The raw guess (will be normalized)
        blob_data: Object with { blob, nonce, tag }

    Returns:
        Dict with success, data (if successful), and normalized answer
    """
    normalized = normalize(guess)

    try:
        key = derive_key(puzzle_id, normalized)

        ciphertext = bytes.fromhex(blob_data['blob'])
        nonce = bytes.fromhex(blob_data['nonce'])
        tag = bytes.fromhex(blob_data['tag'])

        cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
        decrypted = cipher.decrypt_and_verify(ciphertext, tag)

        data = json.loads(decrypted.decode('utf-8'))

        return {
            'success': True,
            'data': data,
            'normalized': normalized
        }
    except Exception as e:
        return {
            'success': False,
            'normalized': normalized,
            'error': str(e)
        }


def compute_commit_hash(answer: str, salt: str, secret: str, address: str) -> str:
    """
    Compute the commit hash for the commit-reveal scheme.

    Args:
        answer: The normalized answer
        salt: The puzzle salt (bytes32 hex)
        secret: User's secret (bytes32 hex)
        address: User's address

    Returns:
        The commit hash (bytes32 hex)
    """
    # keccak256(abi.encodePacked(answer, salt, secret, msg.sender))
    packed = encode_packed(
        ['string', 'bytes32', 'bytes32', 'address'],
        [answer, bytes.fromhex(salt[2:]), bytes.fromhex(secret[2:]), address]
    )
    return '0x' + Web3.keccak(packed).hex()


def generate_secret() -> str:
    """
    Generate a random secret for commit-reveal.
    """
    return '0x' + secrets.token_hex(32)


# Example usage when run directly
if __name__ == '__main__':
    print('eCash SDK v3 (Python) - Example Usage\n')

    # Example: Normalize an answer
    raw = "  Hello World!  "
    normalized = normalize(raw)
    print(f'Normalize: "{raw}" -> "{normalized}"')

    # Example: Generate a secret
    secret = generate_secret()
    print(f'\nGenerated secret: {secret}')

    # Example: Compute commit hash
    answer = "example answer"
    salt = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    address = "0x1234567890123456789012345678901234567890"
    commit_hash = compute_commit_hash(answer, salt, secret, address)
    print(f'\nCommit hash: {commit_hash}')

    print('\n✓ SDK loaded successfully')
