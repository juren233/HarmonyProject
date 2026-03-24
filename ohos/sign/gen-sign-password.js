const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const materialDir = path.resolve(__dirname, 'material');
const component = Buffer.from([49, 243, 9, 115, 214, 175, 91, 184, 211, 190, 177, 88, 101, 131, 192, 119]);

function readSingleFileBytes(dir) {
  const entries = fs.readdirSync(dir).filter((name) => name !== '.DS_Store');
  if (entries.length !== 1) {
    throw new Error(`Expected exactly one file in ${dir}`);
  }
  return fs.readFileSync(path.join(dir, entries[0]));
}

function readFd(dir) {
  const entries = fs.readdirSync(dir).filter((name) => name !== '.DS_Store').sort();
  if (entries.length !== 3) {
    throw new Error(`Expected exactly three subdirectories in ${dir}`);
  }
  return entries.map((name) => readSingleFileBytes(path.join(dir, name)));
}

function xor(a, b) {
  if (a.length !== b.length) {
    throw new Error('xor length mismatch');
  }
  const out = Buffer.alloc(a.length);
  for (let i = 0; i < a.length; i += 1) {
    out[i] = a[i] ^ b[i];
  }
  return out;
}

function decrypt(key, payload) {
  const encryptedAndTagLen = payload.readUInt32BE(0);
  const ivLen = payload.length - 4 - encryptedAndTagLen;
  const iv = payload.subarray(4, 4 + ivLen);
  const encrypted = payload.subarray(4 + ivLen, payload.length - 16);
  const tag = payload.subarray(payload.length - 16);
  const decipher = crypto.createDecipheriv('aes-128-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]);
}

function getKey() {
  const fdParts = readFd(path.join(materialDir, 'fd'));
  const salt = readSingleFileBytes(path.join(materialDir, 'ac'));
  const workMaterial = readSingleFileBytes(path.join(materialDir, 'ce'));
  let rootMaterial = xor(fdParts[0], fdParts[1]);
  rootMaterial = xor(rootMaterial, fdParts[2]);
  rootMaterial = xor(rootMaterial, component);
  const rootKey = crypto.pbkdf2Sync(rootMaterial.toString(), salt, 10000, 16, 'sha256');
  return decrypt(rootKey, workMaterial);
}

function encrypt(key, text) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-128-gcm', key, iv);
  const encrypted = Buffer.concat([cipher.update(Buffer.from(text, 'utf8')), cipher.final()]);
  const tag = cipher.getAuthTag();
  const encryptedAndTagLen = Buffer.alloc(4);
  encryptedAndTagLen.writeUInt32BE(encrypted.length + tag.length, 0);
  return Buffer.concat([encryptedAndTagLen, iv, encrypted, tag]).toString('hex');
}

const password = process.argv[2] || '123456';
const key = getKey();

console.log(JSON.stringify({
  storePassword: encrypt(key, password),
  keyPassword: encrypt(key, password),
}, null, 2));
