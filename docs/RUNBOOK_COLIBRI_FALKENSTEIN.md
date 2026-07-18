# RUNBOOK: colibrì on the Falkenstein dedicated box

**Status: box ACTIVATED 2026-07-18. Steps 1-5 DONE. Step 6 (wire minds)
PENDING A DECISION — latency gate result below.**

**Step 5 latency gate (2026-07-18, default `--policy quality`, `--ram 48`):**
- Serving OK: `glm-5.2-colibri` on :8000, MTP speculative decode (draft=3),
  RAM cap raised 8→21 GB (peak ~47 GB, under 56 GB MemoryMax).
- Cold smoke: "Brussels" correct, 70 s for 7 tokens.
- **Warm throughput: ~0.25 tok/s (~4.0 s/token)**; 151 tokens in 600 s.
- 16× faster than the SATA dev box (~64 s/tok) — RAID0 delivered — **but still
  seconds-per-token**: a 150-tok reply ≈ 10 min; a full mind turn (200-500 tok +
  large context) ≈ 13-33 min. Output QUALITY is excellent.
- **Verdict: usable-but-slow.** Fine for a slow contemplative society (minds
  post every ~20-30 min); too slow for a lively agora or as a drop-in melious
  replacement without cutting MAX_TOKENS and raising timeouts hard.

**Step 5b — tuning (2026-07-18):** `--policy experimental-fast --ram 52
--repin 64`, MemoryMax 58G/MemoryHigh 54G. Result **~3.5 s/token (0.28 tok/s)**,
146 tok in 517 s — only ~11% over baseline. Startup traceback is BENIGN
(inference returns clean HTTP 200). **Conclusion: software policy won't close the
~10× gap; the i7-6700 CPU + MoE model is the floor.** colibrì's slowness is a
structural fit for SLOW-τ meta-cognition (Liquid-Conglomerate L1/L2, synthesis),
NOT fast-τ per-turn agora chatter — see the faber×Spartan design discussion.
**Box: i7-6700 (4c/8t, AVX2), 64 GB DDR4, 2×512 GB M.2 NVMe, Falkenstein FSN1**

Goal: a sovereign GLM-5.2 brain serving OpenAI-compatible `/v1/chat/completions`,
so athena + saga reason for free (no melious, no US provider). At €0.10/hr,
cancel-anytime: if warm latency is unusable, tear it down and you've lost ~€2.50.

**Live values (2026-07-18):**
- `BOX_IP` = `88.99.93.145` (IPv6 `2a01:4f8:10a:1dd0::2`)
- DNS: `colibri.macula.io` → `88.99.93.145` (Linode A, TTL 300)
- `HOME_PUB_IP` (beams' egress) = `91.182.125.182`
- SSH: `ssh -i ~/.ssh/id_hetzner root@88.99.93.145` (key `rl@host00.lab`)
- RAID0 root `/dev/md2` 928 GB; /boot mirrored (md0); 8 GB swap (md1)
- `COLI_API_KEY`: generated at provisioning, held out-of-band (scratchpad /
  beam env), NOT committed here.

---

## 1. OS + RAID0 (max NVMe bandwidth)

Boot the box into Hetzner **rescue** (Robot panel → server → Rescue → Linux),
reboot, `ssh root@BOX_IP`. Then `installimage`:

- Distro: **Ubuntu 24.04 LTS** (recent gcc + glibc; colibrì builds native).
- In the config editor: set software RAID **level 0** across both NVMe
  (`SWRAID 1`, `SWRAIDLEVEL 0`), one big `/` (ext4). The model is
  re-downloadable, so no redundancy needed — stripe both for ~7 GB/s.
- Save → it installs → `reboot`.

RAID0 gives ~1 TB at ~7 GB/s: 384 GB model + OS + room. (This is the whole point
vs the SATA dev box — cold decode drops from ~20 s/token toward ~1.6 s/token.)

## 2. Harden + toolchain

```bash
ssh root@BOX_IP
# ssh key only, firewall: SSH + colibrì :8000 ONLY from the beams' egress
apt-get update && apt-get install -y build-essential cmake python3 python3-venv git ufw curl
ufw allow OpenSSH
ufw allow from HOME_PUB_IP to any port 8000 proto tcp   # colibrì, beams only
ufw --force enable
```

## 3. Build colibrì

```bash
git clone https://github.com/rgfaber/colibri.git /opt/colibri
cd /opt/colibri/c && ./setup.sh          # checks gcc/OpenMP, builds glm, self-test
```

## 4. Fetch the model onto the NVMe (~384 GB, ~1 h over 1 Gbit)

```bash
mkdir -p /opt/models/glm52-colibri-int4
python3 -m venv /opt/models/.hf && /opt/models/.hf/bin/pip -q install huggingface_hub
HF_XET_HIGH_PERFORMANCE=1 /opt/models/.hf/bin/hf download \
  mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp \
  --local-dir /opt/models/glm52-colibri-int4
# verify int8 MTP heads: 3527131672 / 5366238584 / 1065950496
ls -l /opt/models/glm52-colibri-int4/out-mtp-*
```

## 5. Serve — bounded, dedicated box so a BIG warm cache is the point

Dedicated single-purpose box: unlike the shared dev box (where we forced
`CAP_RAISE=0` → 8 GB), here we WANT a large cache to keep hot experts resident.
Budget ~48 GB (leaves ~14 GB for OS/KV/working set), hard-capped by systemd so it
can never OOM the box.

```bash
# native under a systemd unit with a hard MemoryMax (simpler than a container on a
# dedicated box, direct NVMe, still cgroup-capped — the container was only to
# protect the SHARED dev box).
cat >/etc/systemd/system/colibri.service <<'EOF'
[Unit]
Description=colibri GLM-5.2 sovereign inference
After=network-online.target
[Service]
Environment=COLI_MODEL=/opt/models/glm52-colibri-int4
Environment=COLI_API_KEY=REPLACE_WITH_LONG_RANDOM_TOKEN
Environment=RAM=48
MemoryMax=56G
MemoryHigh=50G
ExecStart=/opt/colibri/c/coli serve --host 0.0.0.0 --port 8000
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now colibri
journalctl -u colibri -f    # wait for "listening on http://0.0.0.0:8000/v1"
```

Smoke it (model id is `glm-5.2-colibri`, from the dir):
```bash
curl -s http://127.0.0.1:8000/v1/chat/completions -H 'content-type: application/json' \
  -H 'authorization: Bearer REPLACE_WITH_LONG_RANDOM_TOKEN' \
  -d '{"model":"glm-5.2-colibri","messages":[{"role":"user","content":"In one sentence, what is the capital of Belgium?"}],"max_tokens":24}'
```
**Decision gate:** time a ~150-token reasoning warm. Usable in a few minutes →
wire the minds. Still minutes-per-token → cancel the box, ~€2.50 spent.

## 6. Wire athena + saga to colibrì (drops melious)

In `macula-demo/infrastructure/scripts/docker-compose.spartan.yml`, pass the
colibrì env through to the container (add to the `spartan` service `environment:`):
```yaml
      - COLIBRI_URL=${COLIBRI_URL:-}
      - COLIBRI_MODEL=${COLIBRI_MODEL:-glm-5.2-colibri}
      - COLIBRI_API_KEY=${COLIBRI_API_KEY:-}
```
In `beam00.lab/hecate-spartan.env` and `beam01.lab/hecate-spartan.env`:
```
A_PROVIDERS=colibri
COLIBRI_URL=http://BOX_IP:8000/v1/chat/completions
COLIBRI_MODEL=glm-5.2-colibri
COLIBRI_API_KEY=REPLACE_WITH_LONG_RANDOM_TOKEN
```
Also raise the mind's HTTP patience for slow CPU inference: bump
`?TIMEOUT_MS` in `spartan_mind_llm.erl` (120000 → e.g. 300000) and drop
`?MAX_TOKENS` (500 → ~200) so a reasoning fits the window. Commit both repos,
push. Then un-pause:
```bash
ssh rl@beam00.lab 'systemctl --user start hecate-reconcile.timer'
ssh rl@beam01.lab 'systemctl --user start hecate-reconcile.timer'   # reconcile restarts the minds on the new config
```

## Security notes
- `:8000` is firewalled to the beams' egress AND bearer-gated by `COLI_API_KEY`.
  Never expose it open — it's an unmetered LLM anyone could drain.
- Long term, the sovereign path is over the mesh via `hecate-llm` (advertises
  `hecate-llm.chat`, no public port); this direct-IP wiring is the fast trial.
