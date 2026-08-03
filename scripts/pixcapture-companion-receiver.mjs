#!/usr/bin/env node
import { createHash, randomInt, timingSafeEqual } from "node:crypto";
import { createWriteStream, promises as fs, readFileSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import os from "node:os";
import path from "node:path";
import { pipeline } from "node:stream/promises";

const port = Number.parseInt(process.env.PIXCAPTURE_COMPANION_PORT || "8080", 10);
const host = process.env.PIXCAPTURE_COMPANION_HOST || "127.0.0.1";
const configuredPairingCode = (process.env.PIXCAPTURE_COMPANION_CODE || "").trim();
const pairingCode = configuredPairingCode || String(randomInt(100000, 1000000));
const outputDir = process.env.PIXCAPTURE_COMPANION_DIR
  || path.join(os.homedir(), "Downloads", "PixCapture Companion");
const tlsCertificatePath = (process.env.PIXCAPTURE_COMPANION_TLS_CERT || "").trim();
const tlsKeyPath = (process.env.PIXCAPTURE_COMPANION_TLS_KEY || "").trim();
const allowInsecureLan = process.env.PIXCAPTURE_COMPANION_ALLOW_INSECURE_HTTP === "1";
const tlsEnabled = Boolean(tlsCertificatePath && tlsKeyPath);

if (Boolean(tlsCertificatePath) !== Boolean(tlsKeyPath)) {
  throw new Error("Both PIXCAPTURE_COMPANION_TLS_CERT and PIXCAPTURE_COMPANION_TLS_KEY are required");
}
if (!tlsEnabled && host !== "127.0.0.1" && host !== "::1" && host !== "localhost" && !allowInsecureLan) {
  throw new Error(
    "Refusing an unencrypted LAN listener. Configure TLS or explicitly set PIXCAPTURE_COMPANION_ALLOW_INSECURE_HTTP=1",
  );
}

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

function pairingCodeMatches(value) {
  const received = Buffer.from(String(value || ""), "utf8");
  const expected = Buffer.from(pairingCode, "utf8");
  return received.length === expected.length && timingSafeEqual(received, expected);
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
  if (!pairingCodeMatches(req.headers["x-pixcapture-pairing-code"])) {
    json(res, 401, { error: "Invalid pairing code" });
    req.resume();
    return;
  }

  await fs.mkdir(outputDir, { recursive: true });

  const packageId = String(req.headers["x-pixcapture-package-id"] || `pkg_${Date.now()}`);
  const keyId = String(req.headers["x-pixcapture-key-id"] || "");
  const filename = safeFilename(req.headers["x-pixcapture-filename"], `${packageId}.pixcapturepkg`);
  const expectedSha256 = String(req.headers["x-pixcapture-sha256"] || "");
  const expectedSizeBytes = Number.parseInt(req.headers["content-length"] || "", 10);
  if (!/^[a-f0-9]{64}$/i.test(expectedSha256) || !Number.isSafeInteger(expectedSizeBytes) || expectedSizeBytes < 1) {
    json(res, 400, { accepted: false, error: "SHA-256 and Content-Length are required" });
    req.resume();
    return;
  }
  const finalPath = path.join(outputDir, filename);
  const tempPath = `${finalPath}.part-${process.pid}-${Date.now()}`;
  const hash = createHash("sha256");
  let sizeBytes = 0;

  let aborted = false;
  req.on("data", chunk => {
    sizeBytes += chunk.length;
    hash.update(chunk);
  });
  req.on("aborted", () => {
    aborted = true;
  });

  try {
    await pipeline(req, createWriteStream(tempPath, { flags: "wx" }));
    if (aborted || !req.complete) {
      throw new Error("Upload was aborted before the complete request body arrived");
    }

    const sha256 = hash.digest("hex");
    if (sizeBytes !== expectedSizeBytes || expectedSha256.toLowerCase() !== sha256) {
      await fs.rm(tempPath, { force: true });
      json(res, 422, {
        accepted: false,
        package_id: packageId,
        size_bytes: sizeBytes,
        sha256,
        error: sizeBytes !== expectedSizeBytes ? "size_mismatch" : "sha256_mismatch",
      });
      return;
    }

    const metadata = {
      schema: "pixcapture-companion-receipt-v1",
      received_at: new Date().toISOString(),
      package_id: packageId,
      key_id: keyId || null,
      filename,
      size_bytes: sizeBytes,
      sha256,
      expected_sha256: expectedSha256,
      motif_count: Number.parseInt(req.headers["x-pixcapture-motif-count"] || "0", 10) || null,
      technical_file_count: Number.parseInt(req.headers["x-pixcapture-technical-file-count"] || "0", 10) || null,
      source_total_bytes: Number.parseInt(req.headers["x-pixcapture-source-total-bytes"] || "0", 10) || null,
      warnings: [],
    };

    await fs.rename(tempPath, finalPath);
    await fs.writeFile(`${finalPath}.meta.json`, JSON.stringify(metadata, null, 2));

    json(res, 200, {
      accepted: true,
      package_id: packageId,
      filename,
      size_bytes: sizeBytes,
      sha256,
      stored_path: finalPath,
      warnings: [],
    });
  } catch (error) {
    await fs.rm(tempPath, { force: true }).catch(() => undefined);
    if (!res.headersSent && !res.destroyed) {
      json(res, aborted ? 400 : 500, { accepted: false, error: error.message });
    }
  }
}

const requestHandler = (req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    json(res, 200, {
      ok: true,
      service: "pixcapture-companion-receiver",
      output_dir: outputDir,
      pairing_required: true,
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
};

const server = tlsEnabled
  ? https.createServer(
    {
      cert: readFileSync(tlsCertificatePath),
      key: readFileSync(tlsKeyPath),
      minVersion: "TLSv1.2",
    },
    requestHandler,
  )
  : http.createServer(requestHandler);

server.listen(port, host, () => {
  const scheme = tlsEnabled ? "https" : "http";
  console.log(`PixCapture Companion Receiver listening on ${scheme}://${host}:${port}`);
  console.log(`Output: ${outputDir}`);
  const loopbackOnly = host === "127.0.0.1" || host === "::1" || host === "localhost";
  if (loopbackOnly) {
    console.log("Phone access is disabled by the safe localhost default.");
    console.log("For LAN use, configure TLS and set PIXCAPTURE_COMPANION_HOST explicitly.");
  } else {
    for (const address of localAddresses()) {
      console.log(`Phone URL: ${scheme}://${address}:${port}`);
    }
  }
  console.log(`Pairing code: ${pairingCode}`);
  if (!tlsEnabled) {
    console.warn("TLS is disabled. Only use this listener on localhost or an explicitly trusted test network.");
  }
});
