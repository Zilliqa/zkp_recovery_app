// Terminal ceremony contribution tool. Run on a clean machine (ideally offline).
// Takes the ceremony's current key (you download it manually), mixes in fresh randomness,
// writes the next key for you to upload, and prints your contribution hash for the transcript.
// usage (via contribute.sh): node contribute.js [inputKey=current.zkey] [outputKey=contribution.zkey]
const snarkjs = require('snarkjs');
const crypto = require('crypto');
const readline = require('readline');
const fs = require('fs');

const IN = process.argv[2] || 'current.zkey';
const OUT = process.argv[3] || 'contribution.zkey';

// Gather name + entropy text. Interactive at a terminal; if stdin is piped/redirected
// (scripted), read it in one shot (line 1 = name, line 2 = entropy) — this avoids a readline
// EOF race that would otherwise exit before the contribution runs.
async function gather() {
  if (process.stdin.isTTY) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const ask = q => new Promise(r => rl.question(q, r));
    const name = await ask('Your name / handle (public, appears in the transcript; blank = anonymous): ');
    const text = await ask('Type some random text for extra entropy, then press Enter: ');
    rl.close();
    return { name: name.trim(), text: text.trim() };
  }
  let data = ''; try { data = fs.readFileSync(0, 'utf8'); } catch (e) {}
  const lines = data.split(/\r?\n/);
  console.log('(non-interactive stdin: line 1 = name, line 2 = entropy text)');
  return { name: (lines[0] || '').trim(), text: (lines[1] || '').trim() };
}

(async () => {
  if (!fs.existsSync(IN)) {
    console.error(`ERROR: input key '${IN}' not found.`);
    console.error(`Download the ceremony's current key into this folder as '${IN}' (or pass its path as the first argument).`);
    process.exit(1);
  }
  const sizeMB = (fs.statSync(IN).size / 1048576).toFixed(1);
  console.log(`\nCeremony contribution`);
  console.log(`  input key : ${IN} (${sizeMB} MB)`);
  console.log(`  output    : ${OUT}\n`);

  const gathered = await gather();
  const name = gathered.name || 'anonymous';
  const text = gathered.text;

  // Entropy = your text + 64 bytes from the OS cryptographic RNG.
  // The CSPRNG is what actually secures your contribution; the typed text is supplementary.
  const entropy = text + ' ' + crypto.randomBytes(64).toString('hex');

  console.log('\nContributing — mixing your randomness into the key. This can take a few minutes');
  console.log('and needs several GB of RAM; do not interrupt.\n');
  let last = Date.now();
  const beat = () => { if (Date.now() - last > 4000) { process.stdout.write('.'); last = Date.now(); } };
  const logger = { info: beat, debug: beat, warn: () => {}, error: (...a) => console.error('\n[snarkjs] ' + a.join(' ')) };

  const hash = await snarkjs.zKey.contribute(IN, OUT, name, entropy, logger);
  const hex = Buffer.from(hash).toString('hex');

  console.log('\n\n================= CONTRIBUTION COMPLETE =================');
  console.log('New key written : ' + OUT + '   <-- UPLOAD THIS FILE to the coordinator');
  console.log('Contributor     : ' + name);
  console.log('Your contribution hash (report this so it can be checked against the public transcript):');
  console.log('  ' + hex.replace(/(.{8})/g, '$1 ').trim());
  console.log('========================================================\n');
  console.log('Next steps:');
  console.log('  1. Upload ' + OUT + ' to the coordinator (manual).');
  console.log('  2. Send the contribution hash above to the ceremony operator.');
  console.log('  3. Reboot / wipe this machine\'s memory so your entropy does not linger.\n');
  process.exit(0);
})().catch(e => { console.error('\nERROR: ' + (e && e.message || e)); process.exit(1); });
