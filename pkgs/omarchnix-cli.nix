{
  lib,
  pkgs,
  omarchyShell,
  marketplaceSrc ? null,
  turboLean ? null,
  receiptGate ? null,
  trustedReceiptKeys ? [ ],
  requiredReceiptPackages ? [ ],
}:
let
  registryPath = if marketplaceSrc != null then "${marketplaceSrc}/registry.json" else "";
in
pkgs.writeShellApplication {
  name = "omarchnix";
  runtimeInputs = [
    omarchyShell
    pkgs.b3sum
    pkgs.bash
    pkgs.coreutils
    pkgs.curl
    pkgs.findutils
    pkgs.gawk
    pkgs.git
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jq
    pkgs.lean4
    pkgs.nix
    pkgs.openssl
    pkgs.procps
    pkgs.python3
    pkgs.systemd
    pkgs.wayland-utils
  ]
  ++ lib.optional (turboLean != null) turboLean
  ++ lib.optional (receiptGate != null) receiptGate;
  text = ''
    set -euo pipefail

    export OMARCHY_PATH="''${OMARCHY_PATH:-${omarchyShell.sharePath}}"
    export TURBO_LEAN_BIN="''${TURBO_LEAN_BIN:-${pkgs.lean4}/bin/lean}"
    MARKETPLACE_REGISTRY_DEFAULT="${registryPath}"
    MARKETPLACE_REGISTRY_URL="https://raw.githubusercontent.com/omacom/omarchy-plugin-marketplace/main/registry.json"

    usage() {
      cat <<'EOF'
    Usage: omarchnix <command> [args...]

    Agent-first declarative NixOS & Omarchy workstation CLI.

    Commands:
      status [--json]                     Inspect current theme, shell backend, plugins, receipts, and agent skills
      check [--flake <dir>] [--candidate <path>] [--pubkey <hex>] [--trusted-keys-file <file>]
            [--require-package <name>] [--required-packages-file <file>] [--attestations-dir <dir>]
            [--require-attestations] [--allow-dev-keys] [--json]
                                          Validate runtime state or pre-switch audit a candidate closure
      audit [--path <dir>] [--pubkey <hex>] [--trusted-keys-file <file>] [--require-package <name>]
            [--required-packages-file <file>] [--attestations-dir <dir>] [--require-attestations]
            [--allow-dev-keys] [--allow-empty] [--json]
                                          Offline-verify Schema v2 BLAKE3 + Ed25519 receipts for proof-carrying binaries
      theme list [--json]                 List all available Omarchy themes (bundled + user)
      theme current                       Print the active Omarchy theme
      theme set <name> [--offline]        Live-switch the active Omarchy theme across shell, foot, Hyprland, and agents
      theme palette <name> [--json]       Resolve semantic & ANSI palette for any Omarchy theme
      plugin registry [query] [--json]    Search the plugins.omarchy.org marketplace registry
      plugin install <id|url> [--enable]  Install a plugin from plugins.omarchy.org or git URL (non-interactive --yes supported)
      plugin list [--json]                List discovered first-party and third-party Omarchy shell plugins
      plugin enable <id> [placement...]   Enable an installed Omarchy shell plugin
      plugin disable <id>                 Disable an Omarchy shell plugin
      plugin validate <dir>               Validate a plugin folder against Omarchy manifest schema v1
      sandbox check --backend <bwrap|nixos-container> --roots <a,b> --mounts <src:ro,src:rw> [--allow <caps>]
                                          Verify sandbox mount non-interference through omarchnix-receipt-gate
    EOF
    }

    resolve_registry_file() {
      local cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/omarchnix"
      local cached="$cache_dir/plugins-registry.json"
      if [[ -f "$cached" ]]; then
        printf '%s\n' "$cached"
        return 0
      fi
      if [[ -n "$MARKETPLACE_REGISTRY_DEFAULT" && -f "$MARKETPLACE_REGISTRY_DEFAULT" ]]; then
        printf '%s\n' "$MARKETPLACE_REGISTRY_DEFAULT"
        return 0
      fi
      if [[ -f "$OMARCHY_PATH/marketplace/registry.json" ]]; then
        printf '%s\n' "$OMARCHY_PATH/marketplace/registry.json"
        return 0
      fi
      mkdir -p "$cache_dir"
      curl -fsSL "$MARKETPLACE_REGISTRY_URL" -o "$cached"
      printf '%s\n' "$cached"
    }

    cmd_status() {
      local want_json=0
      if [[ "''${1:-}" == "--json" ]]; then
        want_json=1
      fi

      local theme_name="unknown"
      if [[ -f "$HOME/.local/state/omarchy/current/theme.name" ]]; then
        theme_name="$(tr -d '\n' < "$HOME/.local/state/omarchy/current/theme.name")"
      fi

      local shell_running="false"
      if omarchy-shell -q shell ping >/dev/null 2>&1 && [[ "$(omarchy-shell shell ping 2>/dev/null || true)" != "" ]]; then
        shell_running="true"
      elif pgrep -x quickshell >/dev/null 2>&1; then
        shell_running="true"
      fi

      local waybar_running="false"
      if pgrep -x waybar >/dev/null 2>&1; then
        waybar_running="true"
      fi

      local plugins_dir="$HOME/.config/omarchy/plugins"
      local installed_third_party="[]"
      if [[ -d "$plugins_dir" ]]; then
        installed_third_party="$(
          find "$plugins_dir" -mindepth 2 -maxdepth 2 -type f -name manifest.json ! -path "$plugins_dir/.*/*" 2>/dev/null \
            | sort \
            | xargs -r jq -sc '[.[] | {id: .id, name: .name, version: .version, kinds: .kinds}]'
        )"
      fi

      local skills_present=()
      for d in \
        "$HOME/.agents/skills/omarchnix" \
        "$HOME/.claude/skills/omarchnix" \
        "$HOME/.codex/skills/omarchnix" \
        "$HOME/.hermes/skills/omarchnix"; do
        if [[ -f "$d/SKILL.md" ]]; then
          skills_present+=("$d")
        fi
      done
      local skills_json
      if (( ''${#skills_present[@]} == 0 )); then
        skills_json="[]"
      else
        skills_json="$(printf '%s\n' "''${skills_present[@]}" | jq -R . | jq -s .)"
      fi

      local receipt_count=0
      if [[ -d "/run/current-system/sw/share/omarchnix/receipts" ]]; then
        receipt_count="$(find -L "/run/current-system/sw/share/omarchnix/receipts" -maxdepth 1 -type f -name '*.receipt.json' 2>/dev/null | wc -l | tr -d ' ')"
      fi

      if (( want_json )); then
        jq -nc \
          --arg theme "$theme_name" \
          --arg omarchyPath "$OMARCHY_PATH" \
          --argjson shellRunning "$shell_running" \
          --argjson waybarRunning "$waybar_running" \
          --argjson thirdPartyPlugins "$installed_third_party" \
          --argjson verifiedReceipts "$receipt_count" \
          --argjson agentSkills "$skills_json" \
          '{
            theme: $theme,
            omarchyPath: $omarchyPath,
            shellRunning: $shellRunning,
            waybarRunning: $waybarRunning,
            thirdPartyPlugins: $thirdPartyPlugins,
            verifiedReceipts: $verifiedReceipts,
            agentSkills: $agentSkills
          }'
      else
        echo "Theme:          $theme_name"
        echo "OMARCHY_PATH:   $OMARCHY_PATH"
        echo "omarchy-shell:  $shell_running"
        echo "waybar:         $waybar_running"
        echo "3rd-party:      $(jq -r 'map(.id) | if length == 0 then "none" else join(", ") end' <<<"$installed_third_party")"
        echo "Proof receipts: $receipt_count"
        echo "Agent skills:   $(jq -r 'length' <<<"$skills_json") installed"
      fi
    }

    collect_receipts_for_target() {
      local target="$1"
      local seen_real=()
      add_file() {
        local logical real
        logical="$(realpath --no-symlinks "$1" 2>/dev/null || printf '%s' "$1")"
        real="$(readlink -f "$1" 2>/dev/null || printf '%s' "$logical")"
        [[ -f "$real" ]] || return 0
        local s
        for s in "''${seen_real[@]}"; do
          [[ "$s" == "$real" ]] && return 0
        done
        seen_real+=("$real")
        printf '%s\n' "$logical"
      }

      if [[ -f "$target" ]]; then
        add_file "$target"
        return 0
      fi

      local d
      for d in \
        "$target/share/omarchnix/receipts" \
        "$target/sw/share/omarchnix/receipts"; do
        if [[ -d "$d" ]]; then
          while IFS= read -r rf; do
            [[ -n "$rf" ]] && add_file "$rf"
          done < <(find -L "$d" -maxdepth 1 -type f -name '*.receipt.json' 2>/dev/null | sort)
        fi
      done

      if command -v nix-store >/dev/null 2>&1; then
        local closure_paths
        if closure_paths="$(nix-store -qR "$target" 2>/dev/null)"; then
          local sp
          while IFS= read -r sp; do
            [[ -n "$sp" && -d "$sp/share/omarchnix/receipts" ]] || continue
            while IFS= read -r rf; do
              [[ -n "$rf" ]] && add_file "$rf"
            done < <(find -L "$sp/share/omarchnix/receipts" -maxdepth 1 -type f -name '*.receipt.json' 2>/dev/null | sort)
          done <<<"$closure_paths"
        fi
      fi

      if [[ -d "$target" ]]; then
        while IFS= read -r rf; do
          [[ -n "$rf" ]] && add_file "$rf"
        done < <(find -L "$target" -maxdepth 5 -type f -name '*.receipt.json' 2>/dev/null | sort)
      fi
    }

    strip_line_comment() {
      local raw="$1"
      python3 -c 'import sys; print(sys.argv[1].split(chr(35), 1)[0].strip())' "$raw"
    }

    normalize_hex64() {
      local raw="$1"
      local lower
      lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
      [[ "$lower" =~ ^[0-9a-f]{64}$ ]] || return 1
      printf '%s\n' "$lower"
    }

    verify_external_attestation() {
      local att_file="$1"
      local expected_pkg="$2"
      local expected_receipt_b3="$3"
      local expected_bin_b3="$4"
      local tmp_dir="$5"
      shift 5
      local keys=("$@")

      [[ -f "$att_file" ]] || return 1
      jq -e \
        --arg pkg "$expected_pkg" \
        --arg rb3 "$expected_receipt_b3" \
        --arg bb3 "$expected_bin_b3" \
        '
          type == "object"
          and .schema == "omarchnix-receipt-attestation-v1"
          and .package == $pkg
          and (.receipt_blake3 | ascii_downcase) == ($rb3 | ascii_downcase)
          and (.binary_blake3 | ascii_downcase) == ($bb3 | ascii_downcase)
          and .signature_alg == "ed25519-v1"
          and (.signer_pubkey | type == "string")
          and (.ed25519_signature | type == "string")
        ' "$att_file" >/dev/null 2>&1 || return 1

      local signer_raw signer_norm sig_raw sig_norm
      signer_raw="$(jq -r '.signer_pubkey' "$att_file" 2>/dev/null || true)"
      sig_raw="$(jq -r '.ed25519_signature' "$att_file" 2>/dev/null || true)"
      signer_norm="$(normalize_hex64 "$signer_raw" 2>/dev/null || true)"
      sig_norm="$(printf '%s' "$sig_raw" | tr '[:upper:]' '[:lower:]')"
      [[ -n "$signer_norm" && "$sig_norm" =~ ^[0-9a-f]{128}$ ]] || return 1

      local matched_key=""
      local k
      for k in "''${keys[@]}"; do
        if [[ "$k" == "$signer_norm" ]]; then
          matched_key="$k"
          break
        fi
      done
      [[ -n "$matched_key" ]] || return 1

      python3 - "$matched_key" "$sig_norm" "$tmp_dir/att_pub.der" "$tmp_dir/att_sig.bin" <<'PY' || return 1
    import binascii
    import pathlib
    import sys

    pub_hex, sig_hex, pub_out, sig_out = sys.argv[1:]
    pathlib.Path(pub_out).write_bytes(binascii.unhexlify("302a300506032b6570032100" + pub_hex))
    pathlib.Path(sig_out).write_bytes(binascii.unhexlify(sig_hex))
    PY
      openssl pkey -pubin -inform DER -in "$tmp_dir/att_pub.der" -out "$tmp_dir/att_pub.pem" >/dev/null 2>&1 || return 1
      printf 'omarchnix-receipt-attestation-v1\npackage=%s\nreceipt_blake3=%s\nbinary_blake3=%s\n' \
        "$expected_pkg" \
        "$(printf '%s' "$expected_receipt_b3" | tr '[:upper:]' '[:lower:]')" \
        "$(printf '%s' "$expected_bin_b3" | tr '[:upper:]' '[:lower:]')" \
        > "$tmp_dir/att_msg.txt"
      openssl pkeyutl -verify -pubin -inkey "$tmp_dir/att_pub.pem" -rawin \
        -in "$tmp_dir/att_msg.txt" -sigfile "$tmp_dir/att_sig.bin" >/dev/null 2>&1 || return 1
      printf '%s\n' "$matched_key"
    }

    collect_binaries_for_target() {
      local target="$1"
      local pkg_name="$2"
      local seen_real=()
      add_bin() {
        local logical real
        logical="$(realpath --no-symlinks "$1" 2>/dev/null || printf '%s' "$1")"
        real="$(readlink -f "$1" 2>/dev/null || printf '%s' "$logical")"
        [[ -f "$real" && -x "$real" ]] || return 0
        local s
        for s in "''${seen_real[@]}"; do
          [[ "$s" == "$real" ]] && return 0
        done
        seen_real+=("$real")
        printf '%s\n' "$logical"
      }

      if [[ -f "$target" ]]; then
        if [[ "$target" == *.receipt.json ]]; then
          local rel_tbin
          rel_tbin="$(dirname "$(dirname "$(dirname "$(dirname "$target")")")")/bin/$pkg_name"
          if [[ -e "$rel_tbin" ]]; then
            add_bin "$rel_tbin"
          else
            local rec_tbin
            rec_tbin="$(jq -r '.binary_path // ""' "$target" 2>/dev/null || true)"
            if [[ "$target" == /nix/store/* && -n "$rec_tbin" && -e "$rec_tbin" ]]; then
              add_bin "$rec_tbin"
            fi
          fi
        elif [[ "$(basename "$target")" == "$pkg_name" ]]; then
          add_bin "$target"
        fi
        return 0
      fi

      local b
      for b in \
        "$target/bin/$pkg_name" \
        "$target/sw/bin/$pkg_name"; do
        [[ -e "$b" ]] && add_bin "$b"
      done

      if command -v nix-store >/dev/null 2>&1; then
        local closure_paths
        if closure_paths="$(nix-store -qR "$target" 2>/dev/null)"; then
          local sp
          while IFS= read -r sp; do
            [[ -n "$sp" && -e "$sp/bin/$pkg_name" ]] || continue
            add_bin "$sp/bin/$pkg_name"
          done <<<"$closure_paths"
        fi
      fi

      if [[ -d "$target" ]]; then
        while IFS= read -r bf; do
          [[ -n "$bf" ]] && add_bin "$bf"
        done < <(find -L "$target" -maxdepth 5 -type f -path "*/bin/$pkg_name" 2>/dev/null | sort)
      fi
    }

    cmd_audit() {
      local target="/run/current-system"
      local cli_pubkeys=()
      local trusted_keys_raw=(${lib.escapeShellArgs trustedReceiptKeys})
      local trusted_keys_files=()
      local required_packages_raw=(${lib.escapeShellArgs requiredReceiptPackages})
      local required_packages_files=()
      local attestations_dir="''${OMARCHNIX_RECEIPT_ATTESTATIONS_DIR:-/etc/omarchnix/receipt-attestations}"
      local explicit_attestations_dir=0
      local require_attestations=0
      local allow_dev_keys=0
      local allow_empty=0
      local want_json=0
      while (( $# > 0 )); do
        case "$1" in
          --path)
            if [[ $# -lt 2 || -z "''${2:-}" ]]; then
              echo "omarchnix audit: --path requires a value" >&2
              exit 2
            fi
            target="$2"
            shift 2
            ;;
          --pubkey | --verify-pubkey)
            if [[ $# -lt 2 || -z "''${2:-}" ]]; then
              echo "omarchnix audit: $1 requires a 64-char hex Ed25519 public key" >&2
              exit 2
            fi
            cli_pubkeys+=("$2")
            shift 2
            ;;
          --trusted-keys-file)
            if [[ $# -lt 2 || -z "''${2:-}" ]]; then
              echo "omarchnix audit: --trusted-keys-file requires a path" >&2
              exit 2
            fi
            trusted_keys_files+=("$2")
            shift 2
            ;;
          --allow-dev-keys)
            allow_dev_keys=1
            shift
            ;;
          --require-package)
            if [[ $# -lt 2 || ! "''${2:-}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]; then
              echo "omarchnix audit: --require-package requires a valid package name" >&2
              exit 2
            fi
            required_packages_raw+=("$2")
            shift 2
            ;;
          --required-packages-file)
            if [[ $# -lt 2 || -z "''${2:-}" ]]; then
              echo "omarchnix audit: --required-packages-file requires a path" >&2
              exit 2
            fi
            required_packages_files+=("$2")
            shift 2
            ;;
          --attestations-dir)
            if [[ $# -lt 2 || -z "''${2:-}" ]]; then
              echo "omarchnix audit: --attestations-dir requires a directory" >&2
              exit 2
            fi
            attestations_dir="$2"
            explicit_attestations_dir=1
            shift 2
            ;;
          --require-attestations)
            require_attestations=1
            shift
            ;;
          --allow-empty)
            allow_empty=1
            shift
            ;;
          --json)
            want_json=1
            shift
            ;;
          *)
            if [[ "$1" != -* && "$target" == "/run/current-system" ]]; then
              target="$1"
              shift
            else
              echo "omarchnix audit: unknown option: $1" >&2
              exit 2
            fi
            ;;
        esac
      done

      if ! command -v turbo-lean >/dev/null 2>&1 || ! command -v omarchnix-receipt-gate >/dev/null 2>&1; then
        echo "omarchnix audit: turbo-lean and omarchnix-receipt-gate are required in PATH" >&2
        exit 1
      fi

      if [[ -n "''${OMARCHNIX_TRUSTED_RECEIPT_KEYS_FILE:-}" ]]; then
        if [[ ! -f "$OMARCHNIX_TRUSTED_RECEIPT_KEYS_FILE" ]]; then
          echo "omarchnix audit: OMARCHNIX_TRUSTED_RECEIPT_KEYS_FILE '$OMARCHNIX_TRUSTED_RECEIPT_KEYS_FILE' does not exist" >&2
          exit 1
        fi
        trusted_keys_files+=("$OMARCHNIX_TRUSTED_RECEIPT_KEYS_FILE")
      elif [[ ''${#cli_pubkeys[@]} -eq 0 && ''${#trusted_keys_raw[@]} -eq 0 && ''${#trusted_keys_files[@]} -eq 0 && -f /etc/omarchnix/trusted-receipt-keys ]]; then
        trusted_keys_files+=("/etc/omarchnix/trusted-receipt-keys")
      fi

      local kf line
      for kf in "''${trusted_keys_files[@]}"; do
        if [[ ! -f "$kf" ]]; then
          echo "omarchnix audit: trusted keys file '$kf' does not exist" >&2
          exit 1
        fi
        while IFS= read -r line || [[ -n "$line" ]]; do
          line="$(strip_line_comment "$line")"
          line="$(printf '%s' "$line" | tr -d '[:space:]')"
          [[ -n "$line" ]] && trusted_keys_raw+=("$line")
        done < "$kf"
      done

      if [[ -n "''${OMARCHNIX_REQUIRED_RECEIPT_PACKAGES_FILE:-}" ]]; then
        if [[ ! -f "$OMARCHNIX_REQUIRED_RECEIPT_PACKAGES_FILE" ]]; then
          echo "omarchnix audit: OMARCHNIX_REQUIRED_RECEIPT_PACKAGES_FILE '$OMARCHNIX_REQUIRED_RECEIPT_PACKAGES_FILE' does not exist" >&2
          exit 1
        fi
        required_packages_files+=("$OMARCHNIX_REQUIRED_RECEIPT_PACKAGES_FILE")
      elif [[ ''${#required_packages_raw[@]} -eq 0 && ''${#required_packages_files[@]} -eq 0 && -f /etc/omarchnix/required-receipt-packages ]]; then
        required_packages_files+=("/etc/omarchnix/required-receipt-packages")
      fi

      local pf
      for pf in "''${required_packages_files[@]}"; do
        if [[ ! -f "$pf" ]]; then
          echo "omarchnix audit: required packages file '$pf' does not exist" >&2
          exit 1
        fi
        while IFS= read -r line || [[ -n "$line" ]]; do
          line="$(strip_line_comment "$line")"
          line="$(printf '%s' "$line" | tr -d '[:space:]')"
          if [[ -n "$line" ]]; then
            if [[ ! "$line" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]; then
              echo "omarchnix audit: invalid package name '$line' in '$pf'" >&2
              exit 1
            fi
            required_packages_raw+=("$line")
          fi
        done < "$pf"
      done

      local active_trusted_keys=()
      local raw_k norm_k existing_k dup
      if (( ''${#cli_pubkeys[@]} > 0 )); then
        for raw_k in "''${cli_pubkeys[@]}"; do
          if ! norm_k="$(normalize_hex64 "$raw_k")"; then
            if (( want_json )); then
              jq -nc --arg target "$target" --arg key "$raw_k" '{ok: false, target: $target, error: "invalid_trusted_pubkey", invalid_pubkey: $key, verified_count: 0, receipts: []}'
            else
              echo "omarchnix audit: invalid Ed25519 public key '$raw_k' (expected 64 hex chars)" >&2
            fi
            exit 1
          fi
          dup=0
          for existing_k in "''${active_trusted_keys[@]}"; do
            [[ "$existing_k" == "$norm_k" ]] && dup=1 && break
          done
          (( dup == 0 )) && active_trusted_keys+=("$norm_k")
        done
      else
        for raw_k in "''${trusted_keys_raw[@]}"; do
          if ! norm_k="$(normalize_hex64 "$raw_k")"; then
            if (( want_json )); then
              jq -nc --arg target "$target" --arg key "$raw_k" '{ok: false, target: $target, error: "invalid_trusted_pubkey", invalid_pubkey: $key, verified_count: 0, receipts: []}'
            else
              echo "omarchnix audit: invalid configured trusted Ed25519 public key '$raw_k' (expected 64 hex chars)" >&2
            fi
            exit 1
          fi
          dup=0
          for existing_k in "''${active_trusted_keys[@]}"; do
            [[ "$existing_k" == "$norm_k" ]] && dup=1 && break
          done
          (( dup == 0 )) && active_trusted_keys+=("$norm_k")
        done
      fi

      local required_packages=()
      local rp existing_rp
      for rp in "''${required_packages_raw[@]}"; do
        [[ -n "$rp" ]] || continue
        dup=0
        for existing_rp in "''${required_packages[@]}"; do
          [[ "$existing_rp" == "$rp" ]] && dup=1 && break
        done
        (( dup == 0 )) && required_packages+=("$rp")
      done

      local req_pkgs_json="[]"
      if (( ''${#required_packages[@]} > 0 )); then
        req_pkgs_json="$(printf '%s\n' "''${required_packages[@]}" | jq -R . | jq -s .)"
      fi

      local trust_mode="untrusted_missing_keys"
      if (( ''${#active_trusted_keys[@]} > 0 )); then
        trust_mode="pinned_trusted_keys"
      elif (( allow_dev_keys )); then
        trust_mode="dev_keys_unauthenticated"
      fi

      if [[ ! -e "$target" ]]; then
        if (( want_json )); then
          jq -nc --arg target "$target" --arg trustMode "$trust_mode" --argjson requiredPackages "$req_pkgs_json" \
            '{ok: false, target: $target, trust_mode: $trustMode, error: "target_not_found", required_packages: $requiredPackages, missing_packages: $requiredPackages, verified_count: 0, receipts: []}'
        else
          echo "omarchnix audit: target '$target' does not exist" >&2
        fi
        exit 1
      fi

      if (( ''${#active_trusted_keys[@]} == 0 && ! allow_dev_keys )); then
        if (( want_json )); then
          jq -nc --arg target "$target" --arg trustMode "$trust_mode" --argjson requiredPackages "$req_pkgs_json" \
            '{ok: false, target: $target, trust_mode: $trustMode, error: "no_trusted_receipt_keys", required_packages: $requiredPackages, missing_packages: $requiredPackages, verified_count: 0, total_count: 0, receipts: []}'
        else
          echo "omarchnix audit: fail-closed: no externally pinned trusted receipt public keys configured (pass --pubkey <hex64>, configure security.omarchnix.trustedReceiptKeys, or pass --allow-dev-keys for unauthenticated dev/test seeds)" >&2
        fi
        exit 1
      fi

      if (( explicit_attestations_dir )) && [[ ! -d "$attestations_dir" ]]; then
        if (( want_json )); then
          jq -nc --arg target "$target" --arg trustMode "$trust_mode" --arg dir "$attestations_dir" \
            '{ok: false, target: $target, trust_mode: $trustMode, error: "attestations_dir_not_found", attestations_dir: $dir, verified_count: 0, receipts: []}'
        else
          echo "omarchnix audit: attestations directory '$attestations_dir' does not exist" >&2
        fi
        exit 1
      fi

      local tmp_state
      tmp_state="$(mktemp -d)"
      trap 'rm -rf "$tmp_state"' RETURN

      local receipt_files=()
      while IFS= read -r rf; do
        [[ -n "$rf" ]] && receipt_files+=("$rf")
      done < <(collect_receipts_for_target "$target")

      if (( ''${#receipt_files[@]} == 0 )); then
        local empty_ok="false"
        local empty_err="no_receipts_found"
        if (( allow_empty && ''${#required_packages[@]} == 0 && ! require_attestations )); then
          empty_ok="true"
          empty_err=""
        elif (( ''${#required_packages[@]} > 0 )); then
          empty_err="missing_required_packages"
        fi
        if (( want_json )); then
          jq -nc \
            --argjson ok "$empty_ok" \
            --arg target "$target" \
            --arg trustMode "$trust_mode" \
            --arg err "$empty_err" \
            --argjson requiredPackages "$req_pkgs_json" \
            '{
              ok: $ok,
              target: $target,
              trust_mode: $trustMode,
              required_packages: $requiredPackages,
              missing_packages: $requiredPackages,
              verified_count: 0,
              total_count: 0,
              receipts: []
            } + (if $err == "" then {} else {error: $err} end)'
        else
          echo "omarchnix audit: 0 receipts found under $target (ok=$empty_ok, trust_mode=$trust_mode)"
        fi
        [[ "$empty_ok" == "true" ]]
        return
      fi

      local all_ok=true
      local results=()
      local verified_pkg_bins=()
      local rf
      for rf in "''${receipt_files[@]}"; do
        local pkg_name bin_path recorded_pubkey recorded_pubkey_norm receipt_blake3 actual_blake3 real_bin
        pkg_name="$(jq -r '.omarchnix_package // ""' "$rf" 2>/dev/null || true)"
        bin_path="$(jq -r '.binary_path // ""' "$rf" 2>/dev/null || true)"
        recorded_pubkey="$(jq -r '.ed25519_pubkey // ""' "$rf" 2>/dev/null || true)"
        recorded_pubkey_norm="$(normalize_hex64 "$recorded_pubkey" 2>/dev/null || true)"
        receipt_blake3="$(jq -r '.receipt_blake3 // ""' "$rf" 2>/dev/null || true)"

        actual_blake3="missing"
        real_bin=""
        local rel_bin
        rel_bin="$(dirname "$(dirname "$(dirname "$(dirname "$rf")")")")/bin/$pkg_name"
        if [[ -n "$pkg_name" && -f "$rel_bin" ]]; then
          bin_path="$rel_bin"
          real_bin="$(readlink -f "$bin_path" 2>/dev/null || printf '%s' "$bin_path")"
          actual_blake3="$(b3sum --no-names "$bin_path" 2>/dev/null || printf 'error')"
        elif [[ "$rf" == /nix/store/* && -n "$bin_path" && -f "$bin_path" ]]; then
          real_bin="$(readlink -f "$bin_path" 2>/dev/null || printf '%s' "$bin_path")"
          actual_blake3="$(b3sum --no-names "$bin_path" 2>/dev/null || printf 'error')"
        fi

        local crypto_ok="0"
        local trust_source="untrusted"
        local matched_trusted_pubkey=""
        local attestation_verified="false"
        local tl_out="{}"

        if (( ''${#active_trusted_keys[@]} > 0 )); then
          local candidate_key
          for candidate_key in "''${active_trusted_keys[@]}"; do
            local tl_args=(
              --json
              verify-receipt
              --no-daemon
              --no-telemetry
              --cache-dir "$tmp_state/cache"
              --receipt "$rf"
              --require-signature
              --verify-pubkey "$candidate_key"
            )
            if tl_out="$(TURBO_LEAN_STATE_DIR="$tmp_state/state" turbo-lean "''${tl_args[@]}" 2>/dev/null)"; then
              if jq -e '.status == "receipt_verified" and .schema_version == 2 and .signature_verified == true and .forbidden_constructs_found == 0' <<<"$tl_out" >/dev/null 2>&1 \
                && jq -e --arg binKey "BuildArtifacts/BinaryBlake3_''${actual_blake3}.lean" '.per_file_interfaces | has($binKey)' "$rf" >/dev/null 2>&1; then
                if (( ! require_attestations )); then
                  crypto_ok="1"
                  trust_source="direct_receipt_signature"
                  matched_trusted_pubkey="$candidate_key"
                  break
                fi
              fi
            fi
          done

          if [[ "$crypto_ok" != "1" && -n "$recorded_pubkey_norm" && -d "$attestations_dir" ]]; then
            local self_args=(
              --json
              verify-receipt
              --no-daemon
              --no-telemetry
              --cache-dir "$tmp_state/cache"
              --receipt "$rf"
              --require-signature
              --verify-pubkey "$recorded_pubkey_norm"
            )
            if tl_out="$(TURBO_LEAN_STATE_DIR="$tmp_state/state" turbo-lean "''${self_args[@]}" 2>/dev/null)"; then
              if jq -e '.status == "receipt_verified" and .schema_version == 2 and .signature_verified == true and .forbidden_constructs_found == 0' <<<"$tl_out" >/dev/null 2>&1 \
                && jq -e --arg binKey "BuildArtifacts/BinaryBlake3_''${actual_blake3}.lean" '.per_file_interfaces | has($binKey)' "$rf" >/dev/null 2>&1; then
                local att_candidates=(
                  "$attestations_dir/''${pkg_name}.''${receipt_blake3}.attestation.json"
                  "$attestations_dir/''${receipt_blake3}.attestation.json"
                  "$attestations_dir/''${pkg_name}.attestation.json"
                )
                local att_cand att_signer
                for att_cand in "''${att_candidates[@]}"; do
                  [[ -f "$att_cand" ]] || continue
                  if att_signer="$(verify_external_attestation "$att_cand" "$pkg_name" "$receipt_blake3" "$actual_blake3" "$tmp_state" "''${active_trusted_keys[@]}")"; then
                    crypto_ok="1"
                    trust_source="external_attestation"
                    matched_trusted_pubkey="$att_signer"
                    attestation_verified="true"
                    break
                  fi
                done
              fi
            fi
          fi
        elif (( allow_dev_keys )) && [[ -n "$recorded_pubkey_norm" ]]; then
          local dev_args=(
            --json
            verify-receipt
            --no-daemon
            --no-telemetry
            --cache-dir "$tmp_state/cache"
            --receipt "$rf"
            --require-signature
            --verify-pubkey "$recorded_pubkey_norm"
          )
          if tl_out="$(TURBO_LEAN_STATE_DIR="$tmp_state/state" turbo-lean "''${dev_args[@]}" 2>/dev/null)"; then
            if jq -e '.status == "receipt_verified" and .schema_version == 2 and .signature_verified == true and .forbidden_constructs_found == 0' <<<"$tl_out" >/dev/null 2>&1 \
              && jq -e --arg binKey "BuildArtifacts/BinaryBlake3_''${actual_blake3}.lean" '.per_file_interfaces | has($binKey)' "$rf" >/dev/null 2>&1; then
              crypto_ok="1"
              trust_source="dev_self_declared"
              matched_trusted_pubkey="$recorded_pubkey_norm"
            fi
          fi
        fi

        local gate_out="{}"
        local gate_ok=false
        if gate_out="$(omarchnix-receipt-gate check-receipt \
          --receipt "$rf" \
          --actual-binary-blake3 "$actual_blake3" \
          --crypto-sig-ok "$crypto_ok" \
          --json 2>/dev/null)"; then
          if jq -e '.admitted == true' <<<"$gate_out" >/dev/null 2>&1; then
            gate_ok=true
          fi
        fi

        if [[ "$gate_ok" == "true" && -n "$pkg_name" && -n "$real_bin" ]]; then
          verified_pkg_bins+=("$pkg_name|$real_bin")
        else
          all_ok=false
        fi

        local reported_pubkey="$recorded_pubkey"
        if [[ -n "$matched_trusted_pubkey" ]]; then
          reported_pubkey="$matched_trusted_pubkey"
        elif (( ''${#active_trusted_keys[@]} == 1 )); then
          reported_pubkey="''${active_trusted_keys[0]}"
        fi

        local entry_json
        entry_json="$(jq -nc \
          --arg package "$pkg_name" \
          --arg receipt "$rf" \
          --arg binary "$bin_path" \
          --arg actualBlake3 "$actual_blake3" \
          --arg pubkey "$reported_pubkey" \
          --arg recordedPubkey "$recorded_pubkey" \
          --arg trustSource "$trust_source" \
          --argjson attestationVerified "$attestation_verified" \
          --argjson ok "$gate_ok" \
          --argjson gate "$(if [[ -n "$gate_out" ]] && jq -e . <<<"$gate_out" >/dev/null 2>&1; then printf '%s' "$gate_out"; else printf '{}'; fi)" \
          '{
            package: $package,
            ok: $ok,
            receipt: $receipt,
            binary_path: $binary,
            actual_binary_blake3: $actualBlake3,
            signer_pubkey: $pubkey,
            receipt_pubkey: $recordedPubkey,
            trust_source: $trustSource,
            attestation_verified: $attestationVerified,
            gate: $gate
          }')"
        results+=("$entry_json")
      done

      local missing_packages=()
      local uncovered_binaries=()
      local req_pkg
      for req_pkg in "''${required_packages[@]}"; do
        local pkg_has_verified=0
        local vpb
        for vpb in "''${verified_pkg_bins[@]}"; do
          if [[ "''${vpb%%|*}" == "$req_pkg" ]]; then
            pkg_has_verified=1
            break
          fi
        done

        local discovered_bins=()
        while IFS= read -r db; do
          [[ -n "$db" ]] && discovered_bins+=("$db")
        done < <(collect_binaries_for_target "$target" "$req_pkg")

        if (( pkg_has_verified == 0 || ''${#discovered_bins[@]} == 0 )); then
          missing_packages+=("$req_pkg")
          all_ok=false
        fi

        local dbin dreal bin_covered
        for dbin in "''${discovered_bins[@]}"; do
          dreal="$(readlink -f "$dbin" 2>/dev/null || printf '%s' "$dbin")"
          bin_covered=0
          for vpb in "''${verified_pkg_bins[@]}"; do
            if [[ "$vpb" == "$req_pkg|$dreal" ]]; then
              bin_covered=1
              break
            fi
          done
          if (( bin_covered == 0 )); then
            uncovered_binaries+=("$dbin")
            all_ok=false
          fi
        done
      done

      local missing_pkgs_json="[]"
      if (( ''${#missing_packages[@]} > 0 )); then
        missing_pkgs_json="$(printf '%s\n' "''${missing_packages[@]}" | jq -R . | jq -s .)"
      fi
      local uncovered_bins_json="[]"
      if (( ''${#uncovered_binaries[@]} > 0 )); then
        uncovered_bins_json="$(printf '%s\n' "''${uncovered_binaries[@]}" | jq -R . | jq -s .)"
      fi

      local results_json
      results_json="$(printf '%s\n' "''${results[@]}" | jq -s .)"
      local verified_count
      verified_count="$(jq '[.[] | select(.ok == true)] | length' <<<"$results_json")"

      local top_error=""
      if [[ "$all_ok" != "true" ]]; then
        if (( verified_count < ''${#receipt_files[@]} )); then
          top_error="receipt_verification_failed"
        elif (( ''${#uncovered_binaries[@]} > 0 )); then
          top_error="uncovered_required_binaries"
        elif (( ''${#missing_packages[@]} > 0 )); then
          top_error="missing_required_packages"
        else
          top_error="receipt_verification_failed"
        fi
      fi

      if (( want_json )); then
        jq -nc \
          --argjson ok "$all_ok" \
          --arg target "$target" \
          --arg trustMode "$trust_mode" \
          --arg topError "$top_error" \
          --argjson verifiedCount "$verified_count" \
          --argjson totalCount "''${#receipt_files[@]}" \
          --argjson requiredPackages "$req_pkgs_json" \
          --argjson missingPackages "$missing_pkgs_json" \
          --argjson uncoveredBinaries "$uncovered_bins_json" \
          --argjson receipts "$results_json" \
          '{
            ok: $ok,
            target: $target,
            trust_mode: $trustMode,
            verified_count: $verifiedCount,
            total_count: $totalCount,
            required_packages: $requiredPackages,
            missing_packages: $missingPackages,
            uncovered_binaries: $uncoveredBinaries,
            receipts: $receipts
          } + (if $topError == "" then {} else {error: $topError} end)'
      else
        jq -r '.[] | "[\(if .ok then "VERIFIED" else "FAILED" end)] \(.package) (\(.binary_path)) trust=\(.trust_source) blake3=\(.actual_binary_blake3[0:16])..."' <<<"$results_json"
        if (( ''${#missing_packages[@]} > 0 )); then
          echo "Missing required receipt package(s): ''${missing_packages[*]}" >&2
        fi
        if (( ''${#uncovered_binaries[@]} > 0 )); then
          echo "Uncovered required binary path(s): ''${uncovered_binaries[*]}" >&2
        fi
        echo "Summary: $verified_count/''${#receipt_files[@]} proof-carrying binary receipt(s) verified (ok=$all_ok, trust_mode=$trust_mode)"
      fi

      [[ "$all_ok" == "true" ]]
    }

    cmd_check() {
      local flake_dir=""
      local candidate_path=""
      local candidate_audit_args=()
      local want_json=0
      while (( $# > 0 )); do
        case "$1" in
          --flake)
            if [[ $# -lt 2 || -z "''${2:-}" ]]; then
              echo "omarchnix check: --flake requires a directory" >&2
              exit 2
            fi
            flake_dir="$2"
            shift 2
            ;;
          --candidate)
            if [[ $# -lt 2 || -z "''${2:-}" ]]; then
              echo "omarchnix check: --candidate requires a closure path" >&2
              exit 2
            fi
            candidate_path="$2"
            shift 2
            ;;
          --pubkey | --verify-pubkey | --trusted-keys-file | --require-package | --required-packages-file | --attestations-dir)
            if [[ $# -lt 2 || -z "''${2:-}" ]]; then
              echo "omarchnix check: $1 requires a value" >&2
              exit 2
            fi
            candidate_audit_args+=("$1" "$2")
            shift 2
            ;;
          --allow-dev-keys | --require-attestations)
            candidate_audit_args+=("$1")
            shift
            ;;
          --json)
            want_json=1
            shift
            ;;
          *)
            echo "omarchnix check: unknown option: $1" >&2
            exit 2
            ;;
        esac
      done

      local ok=true
      local checks=()
      local candidate_audit_json="null"

      if [[ -f "$OMARCHY_PATH/shell/shell.qml" ]]; then
        checks+=("shell_qml:ok")
      else
        checks+=("shell_qml:missing")
        ok=false
      fi

      local theme_count
      theme_count="$(find "$OMARCHY_PATH/themes" -mindepth 2 -maxdepth 2 -name colors.toml 2>/dev/null | wc -l | tr -d ' ')"
      if (( theme_count >= 23 )); then
        checks+=("bundled_themes:$theme_count")
      else
        checks+=("bundled_themes_insufficient:$theme_count")
        ok=false
      fi

      if [[ -d "$HOME/.config/omarchy/plugins" ]]; then
        while IFS= read -r pdir; do
          [[ -n "$pdir" ]] || continue
          if omarchy-plugin-validate "$pdir" >/dev/null 2>&1; then
            checks+=("plugin:$(basename "$pdir"):ok")
          else
            checks+=("plugin:$(basename "$pdir"):invalid")
            ok=false
          fi
        done < <(find "$HOME/.config/omarchy/plugins" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
      fi

      if [[ -n "$flake_dir" ]]; then
        if nix --extra-experimental-features 'nix-command flakes' flake metadata "$flake_dir" >/dev/null 2>&1; then
          checks+=("flake_metadata:ok")
        else
          checks+=("flake_metadata:failed")
          ok=false
        fi
      fi

      if [[ -n "$candidate_path" ]]; then
        local audit_args=(--path "$candidate_path" "''${candidate_audit_args[@]}" --json)
        local cand_out=""
        if cand_out="$(cmd_audit "''${audit_args[@]}")"; then
          candidate_audit_json="$cand_out"
          checks+=("candidate_closure_receipts:ok")
        else
          if [[ -n "$cand_out" ]] && jq -e . <<<"$cand_out" >/dev/null 2>&1; then
            candidate_audit_json="$cand_out"
          else
            candidate_audit_json="$(jq -nc --arg target "$candidate_path" '{ok: false, target: $target, error: "candidate_audit_failed"}')"
          fi
          checks+=("candidate_closure_receipts:failed")
          ok=false
        fi
      fi

      local checks_json
      checks_json="$(printf '%s\n' "''${checks[@]}" | jq -R . | jq -s .)"

      if (( want_json )); then
        jq -nc \
          --argjson ok "$ok" \
          --argjson checks "$checks_json" \
          --argjson candidateAudit "$candidate_audit_json" \
          '{ ok: $ok, checks: $checks } + (if $candidateAudit == null then {} else { scope: "candidate", candidate_audit: $candidateAudit } end)'
      else
        printf '%s\n' "''${checks[@]}"
      fi

      [[ "$ok" == "true" ]]
    }

    cmd_theme() {
      local sub="''${1:-list}"
      shift || true
      case "$sub" in
        list)
          if [[ "''${1:-}" == "--json" ]]; then
            {
              if [[ -d "$HOME/.config/omarchy/themes" ]]; then
                find "$HOME/.config/omarchy/themes" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -printf '%f\n'
              fi
              find "$OMARCHY_PATH/themes" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
            } | sort -u | jq -R . | jq -s .
          else
            omarchy-theme-list
          fi
          ;;
        current)
          omarchy-theme-current
          ;;
        set)
          local name=""
          local offline=0
          while (( $# > 0 )); do
            case "$1" in
              --offline | --headless)
                offline=1
                shift
                ;;
              *)
                if [[ -z "$name" ]]; then
                  name="$1"
                else
                  name="$name $1"
                fi
                shift
                ;;
            esac
          done
          [[ -n "$name" ]] || { echo "Usage: omarchnix theme set <name> [--offline]" >&2; exit 1; }
          if (( offline )); then
            OMARCHY_THEME_OFFLINE=1 OMARCHY_THEME_SKIP_BACKGROUND=1 omarchy-theme-set "$name"
          else
            OMARCHY_THEME_WAIT=1 omarchy-theme-set "$name"
          fi
          ;;
        palette)
          local raw_name="''${1:-}"
          [[ -n "$raw_name" ]] || { echo "Usage: omarchnix theme palette <name> [--json]" >&2; exit 1; }
          shift
          local slug
          slug="$(printf '%s' "$raw_name" | tr '[:upper:]' '[:lower:]' | tr ' _' '--')"
          local colors_file="$HOME/.config/omarchy/themes/$slug/colors.toml"
          if [[ ! -f "$colors_file" ]]; then
            colors_file="$OMARCHY_PATH/themes/$slug/colors.toml"
          fi
          [[ -f "$colors_file" ]] || { echo "Unknown theme '$raw_name'" >&2; exit 1; }
          if [[ "''${1:-}" == "--json" ]]; then
            omarchy-theme-color --file "$colors_file" --all | jq -Rn '
              [inputs | split("\t") | select(length == 2) | {key: .[0], value: .[1]}] | from_entries
            '
          else
            omarchy-theme-color --file "$colors_file" --all
          fi
          ;;
        *)
          echo "Unknown theme subcommand: $sub" >&2
          exit 1
          ;;
      esac
    }

    cmd_plugin() {
      local sub="''${1:-list}"
      shift || true
      case "$sub" in
        registry | search)
          local query=""
          local want_json=0
          while (( $# > 0 )); do
            case "$1" in
              --json)
                want_json=1
                shift
                ;;
              --refresh)
                mkdir -p "''${XDG_CACHE_HOME:-$HOME/.cache}/omarchnix"
                curl -fsSL "$MARKETPLACE_REGISTRY_URL" -o "''${XDG_CACHE_HOME:-$HOME/.cache}/omarchnix/plugins-registry.json"
                shift
                ;;
              *)
                query="$1"
                shift
                ;;
            esac
          done
          local reg
          reg="$(resolve_registry_file)"
          local filtered
          filtered="$(jq -c --arg q "$query" '
            [
              .sources[]
              | select(.type == "plugin-source" or .type == "suite")
              | . as $src
              | (
                  if ($src.plugins? | type) == "object" then
                    ($src.plugins | keys)
                  elif ($src.catalog.id? != null) then
                    [$src.catalog.id]
                  else
                    []
                  end
                ) as $ids
              | {
                  ids: $ids,
                  type: $src.type,
                  repo: $src.repo,
                  commit: ($src.listingValidatedCommit // ""),
                  branch: ($src.listingValidatedBranch // "")
                }
              | select(
                  $q == ""
                  or (.repo | ascii_downcase | contains($q | ascii_downcase))
                  or any(.ids[]; ascii_downcase | contains($q | ascii_downcase))
                )
            ]
          ' "$reg")"
          if (( want_json )); then
            printf '%s\n' "$filtered"
          else
            jq -r '.[] | "\((.ids | join(",")))\t\(.type)\t\(.repo)\t\(.commit[0:12])"' <<<"$filtered"
          fi
          ;;
        install | add)
          local target=""
          local extra_args=()
          while (( $# > 0 )); do
            case "$1" in
              --enable | --yes | -y)
                extra_args+=("$1")
                shift
                ;;
              *)
                if [[ -z "$target" ]]; then
                  target="$1"
                else
                  extra_args+=("$1")
                fi
                shift
                ;;
            esac
          done
          [[ -n "$target" ]] || { echo "Usage: omarchnix plugin install <plugin-id|git-url> [--enable] [--yes]" >&2; exit 1; }

          local url="$target"
          local pinned_commit=""
          if [[ "$target" != *"://"* && "$target" != *@* && ! -d "$target" ]]; then
            local reg
            reg="$(resolve_registry_file)"
            local resolved
            resolved="$(jq -r --arg id "$target" '
              [
                .sources[]
                | select(.type == "plugin-source" or .type == "suite")
                | select(
                    ((.plugins? | type) == "object" and (.plugins | has($id)))
                    or (.catalog.id? == $id)
                  )
              ][0] // empty
              | if . == "" then "" else "\(.repo)\t\(.listingValidatedCommit // "")" end
            ' "$reg")"
            if [[ -z "$resolved" ]]; then
              echo "omarchnix plugin install: plugin '$target' not found in plugins.omarchy.org registry" >&2
              exit 1
            fi
            IFS=$'\t' read -r url pinned_commit <<<"$resolved"
          fi

          if [[ -n "$pinned_commit" ]]; then
            local tmpdir
            tmpdir="$(mktemp -d)"
            trap 'rm -rf "$tmpdir"' EXIT
            git clone --quiet "$url" "$tmpdir/repo"
            git -C "$tmpdir/repo" checkout --quiet "$pinned_commit"
            if [[ -f "$tmpdir/repo/manifest.json" ]]; then
              omarchy-plugin-add "$tmpdir/repo" "''${extra_args[@]}"
            elif [[ -d "$tmpdir/repo/$target" && -f "$tmpdir/repo/$target/manifest.json" ]]; then
              omarchy-plugin-add "$tmpdir/repo/$target" "''${extra_args[@]}"
            else
              local sub_manifest
              sub_manifest="$(find "$tmpdir/repo" -mindepth 2 -maxdepth 3 -name manifest.json -exec jq -r --arg id "$target" 'select(.id == $id) | input_filename' {} + | head -n1)"
              if [[ -n "$sub_manifest" ]]; then
                omarchy-plugin-add "$(dirname "$sub_manifest")" "''${extra_args[@]}"
              else
                omarchy-plugin-add "$tmpdir/repo" "''${extra_args[@]}"
              fi
            fi
          else
            omarchy-plugin-add "$url" "''${extra_args[@]}"
          fi
          ;;
        list)
          omarchy-plugin-list "$@"
          ;;
        enable)
          omarchy-plugin-enable "$@"
          ;;
        disable)
          omarchy-plugin-disable "$@"
          ;;
        remove | rm)
          omarchy-plugin-remove "$@"
          ;;
        validate)
          local pdir="''${1:-}"
          if [[ -n "$pdir" && -f "$pdir/manifest.json" ]] && command -v omarchnix-receipt-gate >/dev/null 2>&1; then
            local pschema pid peps
            pschema="$(jq -r '.schemaVersion // 0' "$pdir/manifest.json")"
            pid="$(jq -r '.id // ""' "$pdir/manifest.json")"
            peps="$(jq -r '(.entryPoints // {} | to_entries | map(.value | tostring) | join(","))' "$pdir/manifest.json")"
            omarchnix-receipt-gate check-plugin --schema "$pschema" --id "$pid" --entrypoints "$peps" >/dev/null
          fi
          omarchy-plugin-validate "$@"
          ;;
        *)
          echo "Unknown plugin subcommand: $sub" >&2
          exit 1
          ;;
      esac
    }

    cmd_sandbox() {
      local sub="''${1:-check}"
      shift || true
      case "$sub" in
        check)
          command -v omarchnix-receipt-gate >/dev/null 2>&1 || {
            echo "omarchnix sandbox: omarchnix-receipt-gate is not installed" >&2
            exit 1
          }
          local backend="" roots="" mounts="" allow="none"
          while (( $# > 0 )); do
            case "$1" in
              --backend)
                backend="''${2:-}"
                shift 2
                ;;
              --roots)
                roots="''${2:-}"
                shift 2
                ;;
              --mounts)
                mounts="''${2:-}"
                shift 2
                ;;
              --allow)
                allow="''${2:-none}"
                shift 2
                ;;
              *)
                echo "omarchnix sandbox check: unknown flag '$1'" >&2
                exit 2
                ;;
            esac
          done
          omarchnix-receipt-gate check-sandbox --backend "$backend" --roots "$roots" --mounts "$mounts" --allow "$allow"
          ;;
        *)
          echo "Unknown sandbox subcommand: $sub" >&2
          exit 2
          ;;
      esac
    }

    cmd="''${1:-help}"
    shift || true
    case "$cmd" in
      status)
        cmd_status "$@"
        ;;
      check)
        cmd_check "$@"
        ;;
      audit)
        cmd_audit "$@"
        ;;
      theme)
        cmd_theme "$@"
        ;;
      plugin)
        cmd_plugin "$@"
        ;;
      sandbox)
        cmd_sandbox "$@"
        ;;
      -h | --help | help)
        usage
        ;;
      *)
        echo "omarchnix: unknown command '$cmd'" >&2
        usage >&2
        exit 1
        ;;
    esac
  '';
}
