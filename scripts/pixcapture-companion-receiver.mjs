#!/usr/bin/env node
import { createHash } from "node:crypto";
import { createWriteStream, promises as fs } from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";

const port = Number.parseInt(process.env.PIXCAPTURE_COMPANION_PORT || "8080", 10);
const host = process.env.PIXCAPTURE_COMPANION_HOST || "0.0.0.0";
const pairingCode = (process.env.PIXCAPTURE_COMPANION_CODE || "").trim();
const outputDir = process.env.PIXCAPTURE_COMPANION_DIR
  || path.join(os.homedir(), "Downloads", "PixCapture Companion");

function json(res, status, payload) {
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

function safeFilename(value, fallback) {
  const raw = String(value || fallback || "pixcapture-package.pixcapturepkg");
  const basename = path.basename(raw).replace(/[^a-zA-Z0-9._-]/g, "_");
  return basename.toLowerCase().endsWith(".pixcapturepkg")
    ? basename
    : `${basename}.pixcapturepkg`;
}

function localAddresses() {
  const interfaces = os.networkInterfaces();
  const addresses = [];
  for (const entries of Object.values(interfaces)) {
    for (const entry of entries || []) {
      if (entry.family === "IPv4" && !entry.internal) {
        addresses.push(entry.address);
      }
    }
  }
  return addresses;
}

async function receivePackage(req, res) {
  if (pairingCode && req.headers["x-pixcapture-pairing-code"] !== pairingCode) {
    json(res, 401, { error: "Invalid pairing code" });
    req.resume();
    return;
  }

  await fs.mkdir(outputDir, { recursive: true });

  const packageId = String(req.headers["x-pixcapture-package-id"] || `pkg_${Date.now()}`);
  const keyId = String(req.headers["x-pixcapture-key-id"] || "");
  const filename = safeFilename(req.headers["x-pixcapture-filename"], `${packageId}.pixcapturepkg`);
  const expectedSha256 = String(req.headers["x-pixcapture-sha256"] || "");
  const finalPath = path.join(outputDir, filename);
  const tempPath = `${finalPath}.part`;
  const hash = createHash("sha256");
  let sizeBytes = 0;

  const writer = createWriteStream(tempPath, { flags: "w" });
  req.on("data", chunk => {
    sizeBytes += chunk.length;
    hash.update(chunk);
  });
  req.pipe(writer);

  writer.on("error", error => {
    json(res, 500, { error: error.message });
  });

  writer.on("finish", async () => {
    const sha256 = hash.digest("hex");
    const warnings = [];
    if (expectedSha256 && expectedSha256 !== sha256) {
      warnings.push(`sha256_mismatch:${expectedSha256}:${sha256}`);
    }

    const metadata = {
      schema: "pixcapture-companion-receipt-v1",
      received_at: new Date().toISOString(),
      package_id: packageId,
      key_id: keyId || null,
      filename,
      size_bytes: sizeBytes,
      sha256,
      expected_sha256: expectedSha256 || null,
      motif_count: Number.parseInt(req.headers["x-pixcapture-motif-count"] || "0", 10) || null,
      technical_file_count: Number.parseInt(req.headers["x-pixcapture-technical-file-count"] || "0", 10) || null,
      source_total_bytes: Number.parseInt(req.headers["x-pixcapture-source-total-bytes"] || "0", 10) || null,
      warnings,
    };

    await fs.rename(tempPath, finalPath);
    await fs.writeFile(`${finalPath}.meta.json`, JSON.stringify(metadata, null, 2));

    json(res, warnings.length ? 202 : 200, {
      accepted: true,
      package_id: packageId,
      filename,
      size_bytes: sizeBytes,
      sha256,
      stored_path: finalPath,
      warnings,
    });
  });
}

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    json(res, 200, {
      ok: true,
      service: "pixcapture-companion-receiver",
      output_dir: outputDir,
      pairing_required: Boolean(pairingCode),
    });
    return;
  }

  if (req.method === "POST" && req.url === "/packages") {
    receivePackage(req, res).catch(error => {
      json(res, 500, { error: error.message });
    });
    return;
  }

  json(res, 404, { error: "Not found" });
});

server.listen(port, host, () => {
  console.log(`PixCapture Companion Receiver listening on ${host}:${port}`);
  console.log(`Output: ${outputDir}`);
  for (const address of localAddresses()) {
    console.log(`Phone URL: http://${address}:${port}`);
  }
  if (pairingCode) {
    console.log("Pairing code: required");
  } else {
    console.log("Pairing code: not required");
  }
});
