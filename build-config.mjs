// Runs at deploy time on Vercel. Reads the Supabase connection from environment
// variables and writes config.js, which the page loads so every device
// auto-connects. The key never lives in the repo — only in Vercel's env settings.
import { writeFileSync } from "node:fs";

const url = process.env.SUPABASE_URL || "";
const key = process.env.SUPABASE_ANON_KEY || "";

const body = `window.WT_CONFIG = ${JSON.stringify({ url, key })};\n`;
writeFileSync("config.js", body);

console.log(
  url && key
    ? "build-config: wrote config.js with Supabase connection"
    : "build-config: wrote empty config.js (SUPABASE_URL / SUPABASE_ANON_KEY not set)"
);
