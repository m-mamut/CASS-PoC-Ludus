# Ludus-Claude-info.md
Summary of problems encountered and fixes applied while converting the DSP lab (CASS-PoC) into a Ludus range using the `/dsp-to-ludus` skill. Kept roughly chronological; each entry includes the problem, the fix, and why it worked.

---

## 1. Initial request: translating the DSP lab directly

**Problem:** First request was to translate the whole CASS-PoC DSP archive (docker-compose + Dockerfiles) directly into a Ludus lab.

**Resolution:** Declined to translate the exploit-specific content (a live XSS/session-hijack payload, a PHP webshell `helloshell.php`, cracked credential/hash files). Agreed instead to convert only the **topology** — network layout, VM roles, service skeletons — leaving exploit content as placeholders for the user to fill in themselves. This scoping held for the rest of the conversation; every time an uploaded zip still contained `files/solution/` exploit content, the same line was held and only the benign parts of the role were reviewed/fixed.

---

## 2. Building the `/dsp-to-ludus` skill and early schema fixes

A skill was created/edited to encode the Docker→Ludus translation rules. Over the course of the conversation it was updated repeatedly as new systemic issues surfaced. Key schema-level fixes baked into the skill:

- **`vm_name`/`hostname` character restrictions:** Ludus requires `vm_name`/`hostname` to be 1–63 chars of letters, digits, `.`, `-`, starting with a letter/digit. Docker service names commonly use `snake_case` (underscores), which Ludus rejects. **Fix:** convert every Docker-derived name to `kebab-case` once, and reuse that same name for `vm_name`, `hostname`, the Ansible role directory, and the `roles:` list entry (a "global naming convention" to avoid the bug recurring piecemeal, since the first attempt fixed `vm_name` but forgot `hostname`).
- **`vlan_id`/`role` (singular) are invalid keys:** the real schema keys are `vlan` (int) and `roles` (list). Error message was `Additional property ... is not allowed`.
- **OS-type field was the trickiest schema bug:** initially guessed `windows: false` → schema rejected ("windows is required"). Then guessed `windows: {}` for all OSes → this made Ludus treat **Linux VMs as Windows**, causing deploys to hang waiting for WinRM (port 5986) instead of SSH. **Final correct answer, confirmed against Ludus's own schema docs:** `linux: true` (boolean) for Linux VMs, and `windows: {}` (object, subkeys optional) reserved **only** for actual Windows VMs. The presence of the `windows:` key — not its value — is what tells Ludus "this is a Windows machine."
- **Templates (OS images):**
  - Linux → `debian-12-x64-server-template`
  - Kali → `kali-x64-desktop-template` (fallback: `debian-12-x64-server-template`)
  - Windows → `win11-22h2-x64-enterprise-template`
  - Always verify with `ludus templates list` before assuming a name exists/is built.

---

## 3. Debian 11 router template failure (not a bug in our config)

**Problem:** Ludus's own **default router VM** failed to build because its hardcoded fallback template is `debian-11-x64-server-template`, and Debian 11 (Bullseye) has reached end of normal LTS support — its netinst installer fails at "Select and install software" because package repos have moved to the archive mirror tree. This was confirmed as a known, previously-reported issue (GOAD/Ludus tracker), not something caused by our range-config.

**Fix:** Added a `router:` override block to `range-config.yml` to point the router at the already-built `debian-12-x64-server-template` instead of fixing/building Debian 11:
```yaml
router:
  template: debian-12-x64-server-template
```

---

## 4. Per-service role bugs (RedHat/Fedora → Debian package & path mismatches)

The original DSP lab's Dockerfiles were based on Fedora/RedHat-family images, so many package names, paths, and service-account names baked into the generated Ansible roles were RedHat conventions that don't exist on Debian. Each was root-caused and fixed individually; the skill was updated with a new section ("Distro-compatibility check for deployed config content") so future conversions catch these as a class of bug instead of one at a time. The general pattern **report → ask whether to apply the fix or let the user do it → only then edit** was established here and used consistently afterward.

- **`dnsmasq` package name:** `bind-utils` (RedHat) → `dnsutils`/`bind9-host` (Debian).
- **LDAP packages:** removed `ldapsearch` (not a real Debian package; functionality is in `ldap-utils`) and `libsasl2-modules-dovecot` (not a real package; Postfix↔Dovecot SASL is wired via `smtpd_sasl_type=dovecot` + socket in config, not an apt package).
- **SSL cert paths:** `/etc/pki/tls/certs/...` (RedHat) → `/etc/ssl/certs/...` and `/etc/ssl/private/...` (Debian).
- **LDAP service account:** `ldap`/`ldap` (RedHat) → `openldap`/`openldap` (Debian) — confirmed via Debian's own `slapd` package README.Debian, which explicitly states slapd runs as user/group `openldap`.
- **OpenLDAP config backend:** Debian's `slapd` defaults to the `cn=config` (OLC) directory-based backend, which silently ignores a flat-file `slapd.conf`. Reverted to legacy mode: stop `slapd`, delete `/etc/ldap/slapd.d`, set `SLAPD_CONF=/etc/ldap/slapd.conf` in `/etc/default/slapd`.
- **OpenLDAP schema path:** `slapd.conf`'s `include` lines pointed at `/etc/openldap/schema/...` (RedHat path) → changed to `/etc/ldap/schema/...` (confirmed correct via Debian package file-listing + `slapd.conf(5)` man page for bookworm/Debian 12).
- **OpenLDAP `mdb` backend module:** legacy `slapd.conf` mode needs an explicit module load for non-static backends. Added `modulepath /usr/lib/ldap` and `moduleload back_mdb.la` before the `database mdb` line (path confirmed via Debian package file listing for bookworm).
- **`ldap`→`openldap` directory ownership:** `/var/lib/ldap` and `DB_CONFIG` tasks needed `owner: openldap, group: openldap` instead of `ldap`/`ldap`.

---

## 5. Other non-distro Ansible/systemd bugs found along the way

- **VS Code Microsoft GPG key install (both developer roles):** `ansible.builtin.copy` with `src: /tmp/packages.microsoft.gpg` tried to read that path from the **Ansible controller**, not the remote host (Ansible `copy` defaults to a local source). Also, the key as downloaded is ASCII-armored and needs dearmoring for `apt`'s `signed-by=`. **Fix:** `get_url` → `/tmp/packages.microsoft.asc`, then `gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg /tmp/packages.microsoft.asc`.
- **WordPress Playwright pip install:** Debian 12's Python (PEP 668, "externally managed environment") blocks plain `pip install` into system Python. **Fix:** added `--break-system-packages` to the `pip3 install playwright==...` command (matches Debian's own suggested override; a cleaner but larger alternative — a dedicated venv — was offered but not used).
- **WordPress init systemd service, two separate bugs found via `journalctl`:**
  1. **Missing `Environment=` lines:** the `.service.j2` template declared no environment variables at all, so `init.sh`'s required-variable checks (`: "${WORDPRESS_DB_NAME:?missing}"`) failed immediately. **Fix:** added `Environment=` lines for all 9 variables the script needs, sourced from the role's own `defaults/main.yml` via Jinja2 (`{{ wordpress_db_name }}`, etc.) rather than hardcoding values, so there's one source of truth.
  2. **Wrong `Type=`:** unit used `Type=oneshot` + `RemainAfterExit=yes`, but `init.sh` ends in `tail -f .../error.log` (never exits). **Fix:** `Type=simple`, dropped `RemainAfterExit` (meaningless for `simple`), added `Restart=on-failure`.
  - This whole category (systemd unit template correctness + cross-file credential consistency) was folded into the skill as a new section with explicit guidance: enumerate every variable a launched script needs before writing the template, and check `Type=` against whether the script actually exits.
- **Router/firewall role, three bugs found in one file review:**
  1. `iptables-save > /etc/iptables/rules.v4` used `ansible.builtin.command`, which doesn't support shell redirection (`>` gets passed as a literal arg). **Fix:** switched to `ansible.builtin.shell`.
  2. Missing `/etc/iptables` directory (not created by default on Debian without the `iptables-persistent` package, which this role doesn't install). **Fix:** added an explicit `ansible.builtin.file` directory-creation task.
  3. The embedded systemd unit's `ExecStart=/sbin/iptables-restore < rules.v4` has the same redirection problem — `ExecStart=` has no shell, so `<` doesn't work there either. **Fix:** used `iptables-restore`'s own `-f` flag instead: `ExecStart=/sbin/iptables-restore -f /etc/iptables/rules.v4`.
  4. Hardcoded internet-facing interface name `eth3` in the iptables script, which doesn't match Debian's actual interface naming (confirmed via `ip a`: the VM's real interface is `ens18`). **Fix:** replaced the hardcoded name with a dynamically-discovered `wan_interface` fact (`ansible_default_ipv4.interface`) set in a new task and passed into the Jinja2 template.

---

## 6. Ludus CLI / workflow mechanics covered along the way
(not bugs, just operational notes worth keeping)

- `ludus source sync <id>` / `ludus source update <id>` — update a registered source (git vs. upload type respectively) instead of remove+re-add.
- `ludus blueprint apply <source>/<blueprint-id>` stages a range-config from a registered blueprint but does **not** deploy — still need `ludus range deploy` after.
- `ludus range config get` — view the currently-applied range config.
- `ludus range abort` — cancel an in-progress deploy; doesn't delete already-created VMs (`ludus range rm -f` for a clean teardown).
- `ludus templates build -n <name>` — build a specific template; `ludus templates list` shows built/not-built status.

---

## Interesting information (not actionable fixes, but worth remembering)

- Anthropic suspended public access to Claude Fable 5/Mythos 5 from 2026-06-12 to 2026-07-01 due to U.S. Dept. of Commerce export controls (lifted 2026-06-30, access restored 2026-07-01) — mentioned only because it came up as model/product context, unrelated to the Ludus work itself.
- A transient `json.decoder.JSONDecodeError: Expecting value` during a Ludus deploy turned out to be an unrelated Proxmox API hiccup (empty response to a rapid status-check call) — resolved by simply retrying `ludus range deploy`, not a config bug.
- Debian's `/sbin` is a symlink to `/usr/sbin` (merged-usr) on modern Debian 12/Ubuntu 22.04+, so `shell: /sbin/nologin` in user-creation tasks resolves fine despite being technically a RedHat-style path — this did **not** need fixing, unlike the other RedHat-path issues in this conversation.

---

## Problems for the future

### The router-firewall multi-homing limitation

**Unresolved by design, not by bug fix — needs a decision later.**

The original DSP lab's `router-firewall` service was a Docker container attached to **multiple Docker networks simultaneously**, acting as an internal multi-homed router/firewall between `network_0`, `network_1`, `network_2`, and the internet.

**Ludus does not support this.** A Ludus `ludus:` VM entry takes exactly one `vlan:` integer — there is no array/list syntax, and no valid field (`nics`, `multi_nic` were tried and explicitly rejected by the schema validator) lets a single VM join more than one VLAN. Inter-VLAN and internet routing in Ludus is handled entirely by **Ludus's own separate, built-in router VM**, which is automatically multi-homed across every VLAN in the range — this is core Ludus architecture, not a per-VM setting.

Current state: **kept as Option 2** — `router-firewall` remains single-VLAN (VLAN 10 only), and its role's interface-detection fix (`wan_interface` via `ansible_default_ipv4.interface`) means it no longer errors out, but its forwarding/NAT logic is effectively a no-op since it only ever sees one network interface (`ens18`).

**If multi-network routing/firewalling behavior is actually needed later**, the real options are:
1. Drop the custom `router-firewall` VM/role entirely and reproduce the intended traffic rules using Ludus's **native `network:` block** (`vlan_src`/`vlan_dst`/`protocol`/`ports`/`action` rules) in `range-config.yml`, plus custom roles attached to Ludus's own `router:` key if additional packages/config are needed on the router itself.
2. Leave `router-firewall` as a single-purpose, single-VLAN VM and formally strip the now-dead inter-network forwarding/masquerade rules from its role (currently just inert, not removed).

This was deliberately deferred — not fixed — and flagged in the `/dsp-to-ludus` skill so any *future* multi-homed Docker service in a DSP conversion gets this same question asked **before** a non-functional role is generated, rather than being debugged after the fact like this one was.

### VM credentials

**Ignored for now as the goal was to get to a point where the lab starts**

I am unsure how container users and passwords were resolved before, but currently in Ludus, each vm has been assigned a username and password combo that mirrors the Linux distro running on it (debian where Debain is installed and kali where Kali is installed). THere are multiple questions here:
- Where there user names and passwords defined before?
- What should they be (either exactly or format-wise)?
- Should they be generated dynamically or should they just be fixed?