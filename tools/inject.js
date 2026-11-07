// Adds AlarmLock.dylib to the owner's own decrypted copy of an app, on their own PC.
// Usage: node inject.js <your-app.ipa> <AlarmLock.dylib> <out.ipa>
//
// It puts the dylib in the app's Frameworks folder and adds one weak "load this library" entry to
// the app's main file, so the app still opens if the add-on can't load. Everything else in the
// IPA is copied byte for byte. TrollStore re-signs the app on install.
const fs = require("fs");
const zlib = require("zlib");

const [ipaPath, dylibPath, outPath] = process.argv.slice(2);
if (!ipaPath || !dylibPath || !outPath) {
  console.error("usage: node inject.js <your-app.ipa> <AlarmLock.dylib> <out.ipa>");
  process.exit(2);
}
const DYLIB_NAME = "AlarmLock.dylib";
const LOAD_PATH = "@rpath/" + DYLIB_NAME;

// ---- zip reading -------------------------------------------------------------------------
const zip = fs.readFileSync(ipaPath);
function findEOCD(b) {
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) {
    if (b.readUInt32LE(i) === 0x06054b50) return i;
  }
  throw new Error("not a zip file");
}
const eocd = findEOCD(zip);
let entryCount = zip.readUInt16LE(eocd + 10);
let cdSize = zip.readUInt32LE(eocd + 12);
let cdOffset = zip.readUInt32LE(eocd + 16);
// Large-file (zip64) archives keep the real numbers in a second end record.
if (eocd >= 20 && zip.readUInt32LE(eocd - 20) === 0x07064b50) {
  const z64 = Number(zip.readBigUInt64LE(eocd - 20 + 8));
  if (zip.readUInt32LE(z64) !== 0x06064b50) throw new Error("bad zip64 end record");
  entryCount = Number(zip.readBigUInt64LE(z64 + 32));
  cdSize = Number(zip.readBigUInt64LE(z64 + 40));
  cdOffset = Number(zip.readBigUInt64LE(z64 + 48));
}

const entries = [];
let p = cdOffset;
for (let i = 0; i < entryCount; i++) {
  if (zip.readUInt32LE(p) !== 0x02014b50) throw new Error("bad central directory");
  const e = {
    versionMadeBy: zip.readUInt16LE(p + 4),
    versionNeeded: zip.readUInt16LE(p + 6),
    flags: zip.readUInt16LE(p + 8),
    method: zip.readUInt16LE(p + 10),
    time: zip.readUInt16LE(p + 12),
    date: zip.readUInt16LE(p + 14),
    crc: zip.readUInt32LE(p + 16),
    csize: zip.readUInt32LE(p + 20),
    usize: zip.readUInt32LE(p + 24),
    internalAttr: zip.readUInt16LE(p + 36),
    externalAttr: zip.readUInt32LE(p + 38),
    localOffset: zip.readUInt32LE(p + 42),
  };
  const nameLen = zip.readUInt16LE(p + 28), extraLen = zip.readUInt16LE(p + 30), commentLen = zip.readUInt16LE(p + 32);
  e.nameBytes = zip.subarray(p + 46, p + 46 + nameLen);
  e.name = e.nameBytes.toString("utf8");
  // Sizes and offsets too big for 32 bits are in the zip64 extra field, in this order.
  let x = p + 46 + nameLen;
  const extraEnd = x + extraLen;
  while (x + 4 <= extraEnd) {
    const id = zip.readUInt16LE(x), len = zip.readUInt16LE(x + 2);
    if (id === 0x0001) {
      let y = x + 4;
      if (e.usize === 0xffffffff) { e.usize = Number(zip.readBigUInt64LE(y)); y += 8; }
      if (e.csize === 0xffffffff) { e.csize = Number(zip.readBigUInt64LE(y)); y += 8; }
      if (e.localOffset === 0xffffffff) { e.localOffset = Number(zip.readBigUInt64LE(y)); y += 8; }
    }
    x += 4 + len;
  }
  if (e.csize === 0xffffffff || e.usize === 0xffffffff || e.localOffset === 0xffffffff) throw new Error("missing zip64 sizes for " + e.name);
  if (e.usize > 0xfffffffe || e.csize > 0xfffffffe) throw new Error("a file over 4 GB isn't supported: " + e.name);
  entries.push(e);
  p += 46 + nameLen + extraLen + commentLen;
}

function rawData(e) {
  const lo = e.localOffset;
  if (zip.readUInt32LE(lo) !== 0x04034b50) throw new Error("bad local header for " + e.name);
  const start = lo + 30 + zip.readUInt16LE(lo + 26) + zip.readUInt16LE(lo + 28);
  return zip.subarray(start, start + e.csize);
}
function inflate(e) {
  const raw = rawData(e);
  if (e.method === 0) return Buffer.from(raw);
  if (e.method === 8) return zlib.inflateRawSync(raw);
  throw new Error("unsupported compression " + e.method + " for " + e.name);
}

// ---- find the app and its main file ------------------------------------------------------
const appDir = entries.map(e => e.name.match(/^(Payload\/[^/]+\.app)\//)).find(Boolean);
if (!appDir) throw new Error("no Payload/*.app in this IPA");
const app = appDir[1];
const exeName = app.slice("Payload/".length, -".app".length);
const exeEntry = entries.find(e => e.name === `${app}/${exeName}`);
if (!exeEntry) throw new Error(`main file ${app}/${exeName} not found`);
if (entries.some(e => e.name === `${app}/Frameworks/${DYLIB_NAME}`)) throw new Error("this IPA already has the add-on; use the original copy");

// ---- add the load command ----------------------------------------------------------------
const exe = inflate(exeEntry);
if (exe.readUInt32LE(0) !== 0xfeedfacf) throw new Error("expected a thin 64-bit main file");
const ncmds = exe.readUInt32LE(16), sizeofcmds = exe.readUInt32LE(20);
let firstData = Infinity, q = 32;
for (let i = 0; i < ncmds; i++) {
  const cmd = exe.readUInt32LE(q), size = exe.readUInt32LE(q + 4);
  if (cmd === 0xc || cmd === 0x80000018) {
    const name = exe.toString("utf8", q + exe.readUInt32LE(q + 8), q + size).replace(/\0.*$/s, "");
    if (name === LOAD_PATH) throw new Error("the main file already loads the add-on");
  }
  if (cmd === 0x19) {
    const nsects = exe.readUInt32LE(q + 64);
    for (let k = 0; k < nsects; k++) {
      const so = q + 72 + k * 80, off = exe.readUInt32LE(so + 48);
      const flags = exe.readUInt32LE(so + 64), type = flags & 0xff;
      if (off > 0 && type !== 0x1 && type !== 0xc) firstData = Math.min(firstData, off); // skip zerofill
    }
  }
  q += size;
}
const nameBuf = Buffer.from(LOAD_PATH + "\0", "utf8");
const cmdSize = Math.ceil((24 + nameBuf.length) / 8) * 8;
const at = 32 + sizeofcmds;
if (at + cmdSize > firstData) throw new Error("no room in the main file's header");
if (exe.subarray(at, at + cmdSize).some(x => x !== 0)) throw new Error("header space isn't empty");
const lc = Buffer.alloc(cmdSize);
lc.writeUInt32LE(0x80000018, 0); // LC_LOAD_WEAK_DYLIB
lc.writeUInt32LE(cmdSize, 4);
lc.writeUInt32LE(24, 8); // name offset
lc.writeUInt32LE(2, 12); // timestamp
lc.writeUInt32LE(0x10000, 16); // current version 1.0.0
lc.writeUInt32LE(0x10000, 20); // compatibility version 1.0.0
nameBuf.copy(lc, 24);
lc.copy(exe, at);
exe.writeUInt32LE(ncmds + 1, 16);
exe.writeUInt32LE(sizeofcmds + cmdSize, 20);

// ---- write the new zip -------------------------------------------------------------------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function dosTime(d) {
  return {
    time: (d.getHours() << 11) | (d.getMinutes() << 5) | Math.floor(d.getSeconds() / 2),
    date: ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate(),
  };
}

const out = [];
let offset = 0;
const central = [];
function writeEntry(e, data) {
  const flags = e.flags & ~0x0008; // sizes go in the local header, so no data descriptor
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(e.versionNeeded, 4);
  local.writeUInt16LE(flags, 6);
  local.writeUInt16LE(e.method, 8);
  local.writeUInt16LE(e.time, 10);
  local.writeUInt16LE(e.date, 12);
  local.writeUInt32LE(e.crc, 14);
  local.writeUInt32LE(data.length, 18);
  local.writeUInt32LE(e.usize, 22);
  local.writeUInt16LE(e.nameBytes.length, 26);
  local.writeUInt16LE(0, 28);
  out.push(local, e.nameBytes, data);
  const c = Buffer.alloc(46);
  c.writeUInt32LE(0x02014b50, 0);
  c.writeUInt16LE(e.versionMadeBy, 4);
  c.writeUInt16LE(e.versionNeeded, 6);
  c.writeUInt16LE(flags, 8);
  c.writeUInt16LE(e.method, 10);
  c.writeUInt16LE(e.time, 12);
  c.writeUInt16LE(e.date, 14);
  c.writeUInt32LE(e.crc, 16);
  c.writeUInt32LE(data.length, 20);
  c.writeUInt32LE(e.usize, 24);
  c.writeUInt16LE(e.nameBytes.length, 28);
  c.writeUInt16LE(0, 30);
  c.writeUInt16LE(0, 32);
  c.writeUInt16LE(0, 34);
  c.writeUInt16LE(e.internalAttr, 36);
  c.writeUInt32LE(e.externalAttr >>> 0, 38);
  c.writeUInt32LE(offset, 42);
  central.push(c, e.nameBytes);
  offset += 30 + e.nameBytes.length + data.length;
  if (offset > 0xffffffff) throw new Error("output too large for a plain zip");
}

for (const e of entries) {
  if (e === exeEntry) {
    const data = zlib.deflateRawSync(exe, { level: 9 });
    writeEntry({ ...e, method: 8, crc: crc32(exe), usize: exe.length, versionNeeded: 20 }, data);
  } else {
    writeEntry(e, rawData(e));
  }
}
const dylib = fs.readFileSync(dylibPath);
if (dylib.readUInt32LE(0) !== 0xfeedfacf) throw new Error("the add-on isn't a 64-bit Mach-O");
const stamp = dosTime(new Date());
writeEntry({
  versionMadeBy: (3 << 8) | 20, versionNeeded: 20, flags: 0, method: 8, time: stamp.time, date: stamp.date,
  crc: crc32(dylib), usize: dylib.length, internalAttr: 0, externalAttr: (0o100755 << 16) >>> 0,
  nameBytes: Buffer.from(`${app}/Frameworks/${DYLIB_NAME}`, "utf8"),
}, zlib.deflateRawSync(dylib, { level: 9 }));

const cd = Buffer.concat(central);
const end = Buffer.alloc(22);
end.writeUInt32LE(0x06054b50, 0);
end.writeUInt16LE(entries.length + 1, 8);
end.writeUInt16LE(entries.length + 1, 10);
end.writeUInt32LE(cd.length, 12);
end.writeUInt32LE(offset, 16);
fs.writeFileSync(outPath, Buffer.concat([...out, cd, end]));
console.log(`wrote ${outPath}: ${entries.length + 1} files, add-on at ${app}/Frameworks/${DYLIB_NAME}, weak load of ${LOAD_PATH}`);
