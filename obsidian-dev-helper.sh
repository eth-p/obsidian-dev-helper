#!/usr/bin/env bash
# Obsidian plugin development script.
#
# Copyright (C) 2023 eth-p <https://github.com/eth-p>
# MIT License
#
# ------------------------------------------------------------------------------
# .TH {{0}} 1 "(C) 2023 eth-p" Mac/Linux "Obsidian Plugin Development Helper"
#
# .SH NAME
# {{0}} - a helper script to make testing Obsidian plugins easier
#
# .SH SYNOPSIS
# .B {{0}} [options] --vault
# .I path-to-vault
# .B
#
# .SH COPYRIGHT
# {{0}} is Copyright (C) 2023 by eth-p, and licensed under the MIT license.
# https://github.com/eth-p/
#
# .SH DESCRIPTION
# Automatically builds an Obsidian plugin, installs it to a vault, and reloads
# it.
#
# .SH OPTIONS
# .IP --no-auto-reload
# Do not automatically reload the plugin.
#
# .IP "--build-command \fIcommand\fP"
# Specify the watch-based build command. This is usually either
# \fBnpm\ run\ dev\fP or \fByarn\ dev\fP. Defaults to "\fBnpm\ run\ dev\fP".
#
# .IP "--build-delay \fIseconds\fP"
# Specify the number of seconds to wait before installing a plugin after it's
# built. This is intended to prevent the plugin from being installed while it
# is still building.
#
# .IP "--build-directory \fIdirectory\fP"
# Specify the build's output directory. This is where the \fBmain.js\fP,
# \fBstyles.css\fP, and \fBmanifest.json\fP files are located.
# Defaults to the current directory.
#
# .IP "--plugin-manifest \fIfile\fP"
# Specify the plugin manifest file.
# Defaults to \fBmanifest.json\fP inside the build directory.
#
# .IP "--help"
# Prints this help page and exits.
#
# .SH CAVEATS
# On MacOS systems, Obsidian will steal the window focus whenever it receives
# an "obsidian:" URL event. You may wish to use \fB--no-auto-reload\fP on these
# systems.
#
# ------------------------------------------------------------------------------
set -euo pipefail
errorexit() { printf "\x1B[31merror: ${1}\x1B[0m\n" "${@:2}"; exit 1; }

# Check for required utilities.
needs_command() {
	if command -v entr &>/dev/null; then return 0; fi
	errorexit "requires '%s' utility. %s" "$1" "$2"
}

needs_command entr "https://github.com/eradman/entr"
needs_command jq "https://github.com/stedolan/jq"

# Functions:
pids=()
debounce_pid=

workers_kill() {
	local signal="$1"
	local pids=("${@:2}")
	for pid in "${pids[@]}"; do
		if [ -n "$pid" ]; then
			kill "$signal" "$pid" &>/dev/null
			if [ $? -eq 0 ] && [ "$1" = "-0" ]; then
				return 0
			fi
		fi
	done
}

debounce() {
	if [ -n "$debounce_pid" ]; then
		kill -TERM "$debounce_pid" &>/dev/null
	fi

	( sleep "$1"; "${@:2}" ) &
	debounce_pid=$!
}

create_plugin_directory() {
	local install_dir

	install_dir="${ARG_DESTINATION_VAULT}/.obsidian/plugins/$1"
	if ! [ -d "$install_dir" ]; then
		mkdir -p "$install_dir"
	fi

	echo "$install_dir"
}

install_plugin() {
	local plugin_id plugin_version install_dir
	plugin_id="$(jq -r '.id' "$PLUGIN_MANIFEST_FILE")"
	plugin_version="$(jq -r '.version' "$PLUGIN_MANIFEST_FILE")"
	printf "\x1B[45;37m instl \x1B[0m Installing %s v%s\n" "$plugin_id" "$plugin_version"

	# Create the plugin directory.
	install_dir="$(create_plugin_directory "$plugin_id")"
	cp "$PLUGIN_MANIFEST_FILE" "${install_dir}/manifest.json"
	cp "$PLUGIN_SCRIPT_FILE" "${install_dir}/main.js"
	cp "$PLUGIN_STYLE_FILE" "${install_dir}/styles.css"

	# Reload the plugin.
	if "$ARG_AUTO_RELOAD"; then
		local reload_url="obsidian://devtool-reload?plugin=${plugin_id}"
		{
			xdg-open "$reload_url" \
			|| open "$reload_url"
		} &>/dev/null
	fi
}

install_helper() {
	local install_dir
	local helper_plugin_id="obsidian-dev-helper"
	install_dir="$(create_plugin_directory "$helper_plugin_id")"

	printf "\x1B[45;37m instl \x1B[0m Installing helper plugin.\n"
	cat >"${install_dir}/manifest.json" <<-EOF
		{
			"id": "${helper_plugin_id}",
			"name": "Reload Helper (Developer Tool)",
			"version": "0.0.0",
			"minAppVersion": "1.0.0",
			"description": "Registers a helper URL to reload a plugin.",
			"author": "eth-p",
			"authorUrl": "https://github.com/eth-p/obsidian-dev-helper",
			"isDesktopOnly": true
		}
	EOF

	cat >"${install_dir}/main.js" <<-'EOF'
		const obsidian = require("obsidian")
		module.exports = {
			__esModule: true,
			default: class extends obsidian.Plugin {
				doReloadPlugin(id) {
					this.app.plugins.disablePlugin(id);
					this.app.plugins.enablePlugin(id);
				}
				
				onload() {
					// Protocol handler.
					this.registerObsidianProtocolHandler("devtool-reload", (args) => {
						if ('plugin' in args) {
							this.doReloadPlugin(args.plugin);
							console.log("Requested to reload plugin:", args.plugin);
						}
					})

					// Commands for hotkeys.
					for (const plugin of Object.values(this.app.plugins.manifests)) {
						this.addCommand({
							id: `reload-plugin-${plugin.id}`,
							name: `Reload Plugin: ${plugin.name}`,
							callback: () => {
								this.doReloadPlugin(plugin.id);
							}
						});
					}
				}
			}
		}
	EOF

	touch "${install_dir}/styles.css"
}

# Parse arguments.
ARG_DESTINATION_VAULT=""
ARG_BUILD_COMMAND="npm run dev"
ARG_BUILD_DEBOUNCE=1
ARG_BUILD_OUTDIR="."
ARG_AUTO_RELOAD=true

while [ $# -gt 0 ]; do case "$1" in
	--build-command)   ARG_BUILD_COMMAND="$2";     shift; shift;;
	--build-delay)     ARG_BUILD_DEBOUNCE="$2";    shift; shift;;
	--build-directory) ARG_BUILD_OUTDIR="$2";      shift; shift;;
	--plugin-manifest) ARG_PLUGIN_MANIFEST="$2";   shift; shift;;
	--vault)           ARG_DESTINATION_VAULT="$2"; shift; shift;;
	--auto-reload)     ARG_AUTO_RELOAD=true;       shift;;
	--no-auto-reload)  ARG_AUTO_RELOAD=false;      shift;;
	--help) {
			grep "^# " < "$0" \
				| awk '/^# -----/{p=p+1;next}{if(p==1){print}}' \
				| sed 's/^# //' \
				| sed "s/{{0}}/$(basename -- "${0}")/" \
				| mandoc -a
			exit
		};;
	*) printf "\x1B[31merror: unknown argument: %s\x1B[0m\n" "$1"; exit;;
esac; done

PLUGIN_MANIFEST_FILE="${ARG_BUILD_OUTDIR}/manifest.json"
PLUGIN_SCRIPT_FILE="${ARG_BUILD_OUTDIR}/main.js"
PLUGIN_STYLE_FILE="${ARG_BUILD_OUTDIR}/styles.css"

if [ -n "$ARG_PLUGIN_MANIFEST" ]; then
	PLUGIN_MANIFEST_FILE="$ARG_PLUGIN_MANIFEST"
fi

# Validate arguments.
if [ -z "$ARG_DESTINATION_VAULT" ]; then
 	errorexit "argument '--vault' is required"
fi

if ! [ -d "${ARG_DESTINATION_VAULT}/.obsidian" ]; then
	errorexit "could not find Obsidian vault at %s" "$ARG_DESTINATION_VAULT"
fi

# Install the helper.
install_helper

# Worker: Watcher
({
	trap 'exit 1' INT
	while true; do
		entr -npz true <<-FILES
			${PLUGIN_MANIFEST_FILE}
			${PLUGIN_SCRIPT_FILE}
			${PLUGIN_STYLE_FILE}
		FILES

		debounce "$ARG_BUILD_DEBOUNCE" install_plugin || true
	done
}) &
pids+=($!)

# Worker: Builder
bash -c "$ARG_BUILD_COMMAND" 0>&- 2>&1 | sed -u $'s/^/\x1B[44;37m build \x1B[0m /' &
pids+=($!)

# Wait for interrupt.
trap 'workers_kill -INT "${pids[@]}" "$debounce_pid"' INT EXIT
while workers_kill -0 "${pid[@]}" "$debounce_pid"; do
	sleep 1
done

# Cleanup.
workers_kill -INT "${pids[@]}" "$debounce_pid"
