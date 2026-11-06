{
  lib,
  pkgs,
  omarchyShell,
  marketplaceSrc ? null,
  turboLean ? null,
  receiptGate ? null,
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
    pkgs.procps
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
      check [--flake <dir>] [--json]      Validate flake formatting/eval, plugin manifests, and runtime state
      audit [--path <dir>] [--pubkey <hex>] [--allow-empty] [--json]
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

      if (( ''${#seen_real[@]} == 0 )) && [[ -d "$target" ]]; then
        while IFS= read -r rf; do
          [[ -n "$rf" ]] && add_file "$rf"
        done < <(find -L "$target" -maxdepth 4 -type f -name '*.receipt.json' 2>/dev/null | sort)
      fi
    }

    cmd_audit() {
      local target="/run/current-system"
      local verify_pubkey=""
      local allow_empty=0
      local want_json=0
      while (( $# > 0 )); do
        case "$1" in
          --path)
            target="''${2:-}"
            shift 2
            ;;
          --pubkey | --verify-pubkey)
            verify_pubkey="''${2:-}"
            shift 2
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
              exit 1
            fi
            ;;
        esac
      done

      if ! command -v turbo-lean >/dev/null 2>&1 || ! command -v omarchnix-receipt-gate >/dev/null 2>&1; then
        echo "omarchnix audit: turbo-lean and omarchnix-receipt-gate are required in PATH" >&2
        exit 1
      fi

      if [[ ! -e "$target" ]]; then
        if (( want_json )); then
          jq -nc --arg target "$target" '{ok: false, target: $target, error: "target_not_found", verified_count: 0, receipts: []}'
        else
          echo "omarchnix audit: target '$target' does not exist" >&2
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
        if (( allow_empty )); then
          empty_ok="true"
        fi
        if (( want_json )); then
          jq -nc --argjson ok "$empty_ok" --arg target "$target" '{ok: $ok, target: $target, verified_count: 0, receipts: []}'
        else
          echo "omarchnix audit: 0 receipts found under $target (ok=$empty_ok)"
        fi
        [[ "$empty_ok" == "true" ]]
        return
      fi

      local all_ok=true
      local results=()
      local rf
      for rf in "''${receipt_files[@]}"; do
        local pkg_name bin_path recorded_pubkey effective_pubkey actual_blake3
        pkg_name="$(jq -r '.omarchnix_package // ""' "$rf" 2>/dev/null || true)"
        bin_path="$(jq -r '.binary_path // ""' "$rf" 2>/dev/null || true)"
        recorded_pubkey="$(jq -r '.ed25519_pubkey // ""' "$rf" 2>/dev/null || true)"
        effective_pubkey="$recorded_pubkey"
        if [[ -n "$verify_pubkey" ]]; then
          effective_pubkey="$verify_pubkey"
        fi

        actual_blake3="missing"
        local rel_bin
        rel_bin="$(dirname "$(dirname "$(dirname "$(dirname "$rf")")")")/bin/$pkg_name"
        if [[ -n "$pkg_name" && -f "$rel_bin" ]]; then
          bin_path="$rel_bin"
          actual_blake3="$(b3sum --no-names "$bin_path" 2>/dev/null || printf 'error')"
        elif [[ "$rf" == /nix/store/* && -n "$bin_path" && -f "$bin_path" ]]; then
          actual_blake3="$(b3sum --no-names "$bin_path" 2>/dev/null || printf 'error')"
        fi

        local tl_args=(
          --json
          verify-receipt
          --no-daemon
          --no-telemetry
          --cache-dir "$tmp_state/cache"
          --receipt "$rf"
          --require-signature
        )
        if [[ -n "$effective_pubkey" ]]; then
          tl_args+=(--verify-pubkey "$effective_pubkey")
        fi

        local crypto_ok="0"
        local tl_out="{}"
        if tl_out="$(TURBO_LEAN_STATE_DIR="$tmp_state/state" turbo-lean "''${tl_args[@]}" 2>/dev/null)"; then
          if jq -e '.status == "receipt_verified" and .schema_version == 2 and .signature_verified == true and .forbidden_constructs_found == 0' <<<"$tl_out" >/dev/null 2>&1 \
            && jq -e --arg binKey "BuildArtifacts/BinaryBlake3_''${actual_blake3}.lean" '.per_file_interfaces | has($binKey)' "$rf" >/dev/null 2>&1; then
            crypto_ok="1"
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

        if [[ "$gate_ok" != "true" ]]; then
          all_ok=false
        fi

        local entry_json
        entry_json="$(jq -nc \
          --arg package "$pkg_name" \
          --arg receipt "$rf" \
          --arg binary "$bin_path" \
          --arg actualBlake3 "$actual_blake3" \
          --arg pubkey "$effective_pubkey" \
          --argjson ok "$gate_ok" \
          --argjson gate "$(if [[ -n "$gate_out" ]] && jq -e . <<<"$gate_out" >/dev/null 2>&1; then printf '%s' "$gate_out"; else printf '{}'; fi)" \
          '{
            package: $package,
            ok: $ok,
            receipt: $receipt,
            binary_path: $binary,
            actual_binary_blake3: $actualBlake3,
            signer_pubkey: $pubkey,
            gate: $gate
          }')"
        results+=("$entry_json")
      done

      local results_json
      results_json="$(printf '%s\n' "''${results[@]}" | jq -s .)"
      local verified_count
      verified_count="$(jq '[.[] | select(.ok == true)] | length' <<<"$results_json")"

      if (( want_json )); then
        jq -nc \
          --argjson ok "$all_ok" \
          --arg target "$target" \
          --argjson verifiedCount "$verified_count" \
          --argjson totalCount "''${#receipt_files[@]}" \
          --argjson receipts "$results_json" \
          '{
            ok: $ok,
            target: $target,
            verified_count: $verifiedCount,
            total_count: $totalCount,
            receipts: $receipts
          }'
      else
        jq -r '.[] | "[\(if .ok then "VERIFIED" else "FAILED" end)] \(.package) (\(.binary_path)) blake3=\(.actual_binary_blake3[0:16])..."' <<<"$results_json"
        echo "Summary: $verified_count/''${#receipt_files[@]} proof-carrying binary receipt(s) verified (ok=$all_ok)"
      fi

      [[ "$all_ok" == "true" ]]
    }

    cmd_check() {
      local flake_dir=""
      local want_json=0
      while (( $# > 0 )); do
        case "$1" in
          --flake)
            flake_dir="''${2:-}"
            shift 2
            ;;
          --json)
            want_json=1
            shift
            ;;
          *)
            echo "omarchnix check: unknown option: $1" >&2
            exit 1
            ;;
        esac
      done

      local ok=true
      local checks=()

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

      local checks_json
      checks_json="$(printf '%s\n' "''${checks[@]}" | jq -R . | jq -s .)"

      if (( want_json )); then
        jq -nc --argjson ok "$ok" --argjson checks "$checks_json" '{ ok: $ok, checks: $checks }'
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
          omarchy-plugin-validate "$@"
          ;;
        *)
          echo "Unknown plugin subcommand: $sub" >&2
          exit 1
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
