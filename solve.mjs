import scryptJs from 'scrypt-js';
import crypto from 'crypto';

const { scrypt } = scryptJs;

const puzzleId = 10;
const blob = '452ce95d84bfdaee7d7922fc79685455397e8b7fb2305a99256ed106727ed025bbd97862f0710804db80de7098471f1beb4a3b09b8c93dd91f586088f098cb461f1de4bdd76983168935c4a578bde34865f7eccd4d3d53b6d04dc16645fe05290913ee3b8e8ef3db452177ab00e2bacade70e2adf7584e29ce8781d09d72796f2db0dc094bb5e7f740394b45914071bcffa1e9e665e8904cea4991583ef3bb2cb99ae115f9ac4e19094a95f91efbf66894a827b55961e0f81abc325275d10103d5165919a9a7fdd983b3d21d93caa391d002e6623725de55b72c488db7e42664dcd7d00448787eeff92265bc83c9af0058b86895dac7ef9dfce29c47de03132ae9eadcb7ce78174ac5d975554eb2b46e703ded4a30894a964b4c4f4940b46f939d3f410ac50f0c8484d383876260c24c05f96d24f095fae5bea5d435f42ec6f6eede29d421b0255815817204c7f085f12af0f4acef2f6ab4e43cbdddbc9d402cb67f88e3bdad07deadc824238587f1ca55c22f9088632809c90513555325cc6b98d59f1898e32cb1be1be1bb65ca50f167bec54782d7e4f72592f4bda99123cb6329de73b22a94c30c4e0c4b8650b1a3438c2831430aca6e20a7927240383294b9d0a835c1f51af0591379148d78c0e9d84803f9afe083c641d43391e20bc22f58293c944789e7853a43b604e1f8315b16e2e1559779acaa0f44f1ff3f893cbe94e2b335c5ebbd8aed467138382e953d275fb1e99e121319a831d707f33220693de22d4be0778d49c0426dcec70404e01e45d76c9b5a78f0072e4af82f39290b161f6d13b396ef264ba67e9b79ee05ebeebb61c2364f13bbd5d17ec3436e89f612b492f0d4b85673b5c62b5e9e75a06287d679a98238dde04e020812e02958b149482d924d22d23e0298e8f7506857b74b8fe33d1814805d56e90bb6d9ce629acad0055ca01d9c3694ba4301c5614802f21b46e8c29447cd7bff2fab2716c2d83c8d45be73988da0ab81fd8ce713c2ca7866c187fb3c13c91e9052a96da3ef73ee29354d05efffc24b0232b282a3ad40212b91a3fb259890486f3cdc2244d7aab5583c974d720d4b4cb19ac04fbbd9d00068fde3893c7230db7dd46b8f4fae90c249495c604692158fcbd8fd334020d867a803ab7d99ecdbcb64394a99994ce43a33e5aa7c02ef2fbf029c0f8b565ad29241067d0899686f41da57d5d65e1b88132b69f2d883a4919649eaa2e36e606c54f46acb19dd21f58f5b129092d42d960b60ffae297800d82087dd4e529b6866e4385c5903596e72d063abac77e685f28bb0a9cdd4f06d47ef0ddefe69e4ee93479ab248e6be7fd8fbad08bd1d4102b53e3f89b73cd951ae4dac8033dc31526e624ba5dc033ec90f';
const nonce = 'da019ae062763e51f89f39b6';
const tag = '49efa8eb6f2f47cd752f8190ff7f5a39';

function normalize(s) {
  return s.toLowerCase().replace(/[^a-z0-9 ]/g, '').replace(/\s+/g, ' ').trim();
}

async function tryDecrypt(guess) {
  const normalized = normalize(guess);
  console.log(`Trying: "${normalized}"`);
  
  const salt = `ecash-v3-${puzzleId}`;
  const key = await scrypt(
    Buffer.from(normalized, 'utf8'),
    Buffer.from(salt, 'utf8'),
    131072, 8, 1, 32
  );
  
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    Buffer.from(key),
    Buffer.from(nonce, 'hex')
  );
  decipher.setAuthTag(Buffer.from(tag, 'hex'));
  
  try {
    const decrypted = Buffer.concat([
      decipher.update(Buffer.from(blob, 'hex')),
      decipher.final()
    ]);
    console.log('SUCCESS! Decrypted:', decrypted.toString('utf8'));
    return true;
  } catch (e) {
    return false;
  }
}

const guesses = [
  'black hole',
  'blackhole',
  'event horizon',
  'singularity',
  'absorption',
  'dark matter',
  'gravity well',
  'gravitational collapse',
  'photon sphere',
  'schwarzschild',
  'hawking radiation'
];

for (const guess of guesses) {
  const success = await tryDecrypt(guess);
  if (success) process.exit(0);
}
console.log('None matched');
