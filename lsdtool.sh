#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C.UTF-8

if [[ $EUID -eq 0 ]]; then
    echo "Error: Don't run this as root, please." >&2
    exit 1
fi

SOURCE="$(realpath "${0}")"
SCRIPT_DIR="$(dirname "${SOURCE}")"

JDK_URL="https://gitlab.com/alelec/mib2-lsd-patching/-/raw/main/ibm-java-ws-sdk-pxi3260sr4ifx.zip"

CONTAINER_IMAGE_ID="${SCRIPT_DIR}/utils/.container-image-id"
CONTAINER_IMAGE_RECIPIE="${SCRIPT_DIR}/Dockerfile"

has_long_params() {
     [[ "$(getopt -o h --long help --name test -- --help 2>/dev/null | tr -d ' ')" == "--help--" ]]
}

print_help() {
    echo "Usage: $0 [OPTIONS] [SOURCE] [DESTINATION] [CLASSPATH]"
    echo

    if ! has_long_params; then
        echo "NOTICE! Only short flags are supported on your OS!"
        echo
    fi

    cat <<EOF
Options:
  -h, --help             Show this help message
  -x, --jxe              Convert lsd.jxe to lsd.jar and decompile it
       [SOURCE]          Source java file. Default lsd.jxe
       [DESTINATION]     Destination folder, default ./lsd_java
  -a, --jar              Decompile lsd.jar to destination
       [SOURCE]          Source java file. Default lsd.jar
       [DESTINATION]     Destination folder, default ./lsd_java

  -b, --build            Build JAR patch file
       [SOURCE]          Source patch data, default ./patch
       [DESTINATION]     Target patch file, default [SOURCE].jar
       [CLASSPATH]       Original jar file, default lsd.jar
  -n, --nocleanup        Skip cleanup during build (may cause build failure)
  -i, --install          lsdtool can be portable, but it can also be installed
  -d, --docker           run the toolchain inside docker - default on mac, not available on windows, optional on linux
EOF
}

has_command() {
    local cmd="${1:-}"
    local advice="${2:-}"

    if [[ -z "${cmd}" ]]; then
        echo "Error: empty command name" >&2
        return 1
    fi

    if ! which "${cmd}" >/dev/null; then
        echo "Error: ${cmd} not found in PATH! ${advice}"
        return 1
    fi
}

f_exists() {
    local target="${1:-}"
    if [[ -z "${target}" ]]; then
        echo "Error: empty path provided" >&2
        return 1
    fi

    if [[ ! -f "${target}" ]]; then
        echo "Error: file not found: ${target}" >&2
        return 1
    fi
}

d_exists() {
    local target="${1:-}"
    if [[ -z "${target}" ]]; then
        echo "Error: empty path provided" >&2
        return 1
    fi

    if [[ ! -d "${target}" ]]; then
        echo "Error: directory not found: ${target}" >&2
        return 1
    fi
}

# TODO add support for apple containers
container_prepare() {
    has_command docker
    if [[ -e "${CONTAINER_IMAGE_ID}" ]] && [[ "${CONTAINER_IMAGE_RECIPIE}" -ot "${CONTAINER_IMAGE_ID}" ]]; then
        return 0
    fi

    docker build --platform linux/amd64 -f "${CONTAINER_IMAGE_RECIPIE}" --iidfile "${CONTAINER_IMAGE_ID}" .
}

x86() {
    # Takes parameters as "paths to map" until '--' and treats rest like a command
    local -a paths=()
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--" ]]; then
            shift
            break
        else
            paths+=("-v ${1}:${1}")
            shift
        fi
    done

    if "${CONTENERIZED}"; then
        docker run --platform linux/amd64 --rm -it ${paths[*]} -v "${SCRIPT_DIR}":/opt/lsdtool --workdir /opt/lsdtool "$(cat "${CONTAINER_IMAGE_ID}")" "${@}"
    else
        "${@}"
    fi
}

getjdk() {
    local target="${1:-}"
    if [[ -z "${target}" ]]; then
        echo "Error: empty JDK target path" >&2
        return 1
    fi

    local target_jdk="${target}/utils/jdk"
    local target_bin="${target_jdk}/bin"
    if [[ -e "${target_bin}/java" ]] && [[ -e "${target_bin}/javac" ]] && [[ -e "${target_bin}/jar" ]]; then
        return 0
    fi

    if ! "${CONTENERIZED}"; then
        has_command patchelf
    fi
    has_command curl
    has_command unzip

    local tmp_jdk
    tmp_jdk="$(mktemp)"
    trap "rm -f '${tmp_jdk}'" RETURN EXIT SIGINT

    echo "Downloading 32-bit JDK..."
    if ! curl -fSL "${JDK_URL}" -o "${tmp_jdk}"; then
        echo "Error: Download failed!"
        return 1
    fi

    mkdir -p "${target_jdk}"
    if ! unzip -q "${tmp_jdk}" -d "${target_jdk}"; then
        echo "Error: Couldn't extract JDK!"
        return 1
    fi

    echo "Patching java..."
    x86 "${target_jdk}" -- \
      patchelf --clear-execstack "${target_jdk}/jre/lib/i386/j9vm/libjvm.so"
    x86 "${target_jdk}" -- \
      patchelf --clear-execstack "${target_jdk}/jre/lib/i386"/*.so

    echo "Done!"
}

#   sanitize_path <path> [extension]
sanitize_path() {
    local input="${1:-}"

    # Strip trailing slashes for normalization
    input="${input%/}"

    # Validate non-empty
    if [[ -z "${input}" ]]; then
        echo "Error: empty path" >&2
        return 1
    fi

    # Reject Windows-style backslashes
    if [[ "${input}" == *\\* ]]; then
        echo "Error: invalid character '\\' in path: ${input}" >&2
        return 1
    fi

    # TODO: can we finish here?

    # Reject wildcards (* ? [ ])
    if [[ "${input}" == *[\*\?\[]* ]]; then
        echo "Error: wildcards are not allowed in path: ${input}" >&2
        return 1
    fi

    # Normalize absolute vs relative
    local path
    if [[ "${input}" = /* ]]; then
        path="${input}"
    else
        path="./${input}"
    fi

    echo "$path"
}

#   confirm_overwrite <file>
confirm_overwrite() {
    local target="$1"

    if [[ -f "${target}" ]]; then
        read -p "File '${target}' already exists. Overwrite? [y/N]: " answer
        case "${answer}" in
            [Yy]*) return 0 ;;
            *)
                echo "Aborting." >&2
                exit 1
                ;;
        esac
    elif [[ -d "${target}" ]]; then
        read -p "Directory '${target}' already exists. Overwrite? [y/N]: " answer
        case "${answer}" in
            [Yy]*) : ;;
            *)
                echo "Aborting." >&2
                exit 1
                ;;
        esac

        read -p "Should I delete it? [Y/n]: " answer
        case "${answer}" in
            [Nn]*) return 0 ;;
            *)
                [[ -n "${target}" ]] && [[ "${target}" != "/" ]] && [[ -d "${target}" ]] && rm -rf "${target}"
                return 0
                ;;
        esac
    fi
    return 0
}

#   cleanup_java <java file>
cleanup_java() {
    local java_file="$1"

    echo "Cleanup $java_file"
    sed -i 's: final : /*final*/ :g' "$java_file"
    sed -r -i 's:  @Override: // @Override:g' "$java_file"
    perl -0777 -npi -e 's:    default (.*)\{\n    \}:    /*default*/ \1;:g' "$java_file"
}

is_wsl() {
    # Kernel identifiers
    if grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null; then
        return 0
    fi
    if grep -qi 'microsoft' /proc/version 2>/dev/null; then
        return 0
    fi

    # Env hints set by WSL
    if [[ -n "${WSL_INTEROP:-}" || -n "${WSL_DISTRO_NAME:-}" ]]; then
        return 0
    fi
    return 1
}

### Defaults ###
CONTENERIZED=false
if [ "$(uname -s)" == "Darwin" ]; then
    # Enable docker mode by default on MacOS
    CONTENERIZED=true
fi
CLEANUP=true
MODE=""

### Params processing ###
PARAMS_SHORT="hxabnid"
PARAMS_LONG="help,jxe,jar,build,nocleanup,install,docker"
if has_long_params; then
    PARAMS=$(getopt -o "${PARAMS_SHORT}" --long "${PARAMS_LONG}" -n "$0" -- "$@")
else
    PARAMS=$(getopt "${PARAMS_SHORT}" "$@")
fi

eval set -- "${PARAMS}"
while true; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -x|--jxe)
            MODE="jxe"
            shift
            ;;
        -a|--jar)
            MODE="jar"
            shift
            ;;
        -b|--build)
            MODE="build"
            shift
            ;;
        -n|--nocleanup)
            CLEANUP=false
            shift
            ;;
        -i|--install)
            MODE="install"
            shift
            ;;
        -d|--docker)
            if is_wsl; then
                echo "Docker mode is not available on WSL!" >&2
                exit 1
            fi
            CONTENERIZED=true
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unexpected option: $1"
            exit 64
            ;;
    esac
done

if [[ -z "${MODE}" ]]; then
    print_help
    exit 64
fi

### Install ###
if [[ "${MODE}" == "install" ]]; then # TODO extract to install.sh?
    INSTALL_DIR="$HOME/.local/share/lsdtool"
    SYMLINK="$HOME/.local/bin/lsdtool"
    echo "Installing lsdtool to $INSTALL_DIR"
    if [[ -e "$INSTALL_DIR" ]]; then
        read -rp "Installation directory already exists. Proceed anyway? [Y/n] " reply
        if [[ "$reply" =~ ^[nN] ]]; then
            echo "Aborting..."
            exit 1
        fi
    fi
    mkdir -p "$INSTALL_DIR"
    cp $SCRIPT_DIR/lsdtool.sh $INSTALL_DIR/lsdtool.sh
    echo "Making symlink at $SYMLINK"
    cp -aT $SCRIPT_DIR/utils $INSTALL_DIR/utils
    rm -f $SYMLINK
    ln -s "$INSTALL_DIR/lsdtool.sh" "$SYMLINK"
    chmod +x "$SYMLINK" # TODO: should be covered by permissions on lsdtool.sh
    chmod +x "$INSTALL_DIR/utils/JXE2JAR" # TODO: should be sorted out by git itslef and `-a` flag for cp
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        echo "Warning: ~/.local/bin is not in your PATH."
        shell_rc="$HOME/.bashrc"
        if [ -n "${ZSH_VERSION:-}" ]; then shell_rc="$HOME/.zshrc"; fi
        read -rp "Append export PATH=\"\$HOME/.local/bin:\$PATH\" to $shell_rc? [Y/n] " reply
        case "$reply" in
            [nN]*) echo "Skipping PATH modification." ;;
            *) echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_rc"
               echo "Added to $shell_rc. Restart your shell or run 'source $shell_rc'." ;;
        esac
    fi

    getjdk "${INSTALL_DIR}"
    exit 0
fi

### Preflight checks ###
if "${CONTENERIZED}"; then
    container_prepare
fi

getjdk "${SCRIPT_DIR}"

if ! "${CONTENERIZED}"; then
    has_command java "Please install JDK."
    has_command jar "Please install JDK, JRE is nice, but not sufficient."
    has_command ldd
    has_command file
fi
has_command perl "Please install perl."


export JAVA_HOME="${SCRIPT_DIR}/utils/jdk"
export PATH="${JAVA_HOME}/bin:${PATH}"

NEEDED_EXECUTABLES=(
    "${JAVA_HOME}/bin/java"
    "${JAVA_HOME}/bin/javac"
    "${JAVA_HOME}/bin/jar"
    "${SCRIPT_DIR}/utils/JXE2JAR"
)

# Check all files exist
for f in "${NEEDED_EXECUTABLES[@]}"; do
    if [[ ! -f "${f}" ]]; then
        echo "Missing required file: ${f}"
        exit 1
    fi
done

# Check if any executable bit is missing
MISSING_X=()
for f in "${NEEDED_EXECUTABLES[@]}"; do
    [[ -x "${f}" ]] || MISSING_X+=("${f}")
done

# If some files need +x, prompt once
if [[ ${#MISSING_X[@]} -gt 0 ]]; then
    echo "The following required files are not executable:"
    for f in "${MISSING_X[@]}"; do
        echo "    ${f}"
    done

    read -p "Attempt to fix permissions for all required files with chmod +x? [Y/n]: " answer
    case "${answer}" in
        [Nn]* ) echo "Aborting."; exit 1 ;;
        * )
            # Attempt as current user, fallback to sudo if needed
            chmod +x "${NEEDED_EXECUTABLES[@]}" 2>/dev/null || sudo chmod +x "${NEEDED_EXECUTABLES[@]}"
            echo "Permissions fixed."
            ;;
    esac
fi

if ! file "${JAVA_HOME}/bin/javac" | grep -q "32-bit"; then
    echo "Error: cannot recognize javac binary"
    exit 1
fi

if ! "${CONTENERIZED}" && ! ldd "${JAVA_HOME}/bin/javac" >/dev/null 2>&1; then
    echo "Error: Cannot execute 32-bit javac. Make sure lib32-gcc-libs is installed:"
    ldd "${JAVA_HOME}/bin/javac" || true
    exit 1
fi

### Execute ###
if [[ "${MODE}" == "jxe" ]]; then
    SOURCE="$(sanitize_path "${1:-lsd.jxe}")"
    DESTINATION="$(sanitize_path "${2:-lsd_java}")"
    SOURCE_JAR="${SOURCE%.*}.jar"
    SOURCE_DIR="$(dirname "${SOURCE}")"

    #TODO check/ensure SOURCE_DIR & DESTINATION exists?
    f_exists "${SOURCE}"
    confirm_overwrite "${SOURCE_JAR}"
    confirm_overwrite "${DESTINATION}"

    echo "Converting ${SOURCE} -> ${SOURCE_JAR}"
    x86 "${SOURCE_DIR}" -- \
      "${SCRIPT_DIR}/utils/JXE2JAR" "${SOURCE}" "${SOURCE_JAR}"

    echo "Decompiling ${SOURCE_JAR} -> ${DESTINATION}"
    x86 "${SOURCE_DIR}" "${DESTINATION}" -- \
      "${JAVA_HOME}/bin/java" -Xmx6g -jar "${SCRIPT_DIR}/utils/cfr-0.152.jar" --previewfeatures false --switchexpression false --outputdir "${DESTINATION}" "${SOURCE_JAR}"
elif [[ "${MODE}" == "jar" ]]; then
    SOURCE="$(sanitize_path "${1:-lsd.jar}")"
    DESTINATION="$(sanitize_path "${2:-lsd_java}")"
    SOURCE_DIR="$(dirname "${SOURCE}")"

    #TODO check/ensure SOURCE_DIR & DESTINATION exists?
    f_exists "${SOURCE}"
    confirm_overwrite "${DESTINATION}"

    echo "Decompiling ${SOURCE} -> ${DESTINATION}"
    x86 "${SOURCE_DIR}" "${DESTINATION}" -- \
      "${JAVA_HOME}/bin/java" -Xmx6g -jar "${SCRIPT_DIR}/utils/cfr-0.152.jar" --previewfeatures false --switchexpression false --outputdir "${DESTINATION}" "${SOURCE}"
elif [[ "${MODE}" == "build" ]]; then
    SOURCE="$(sanitize_path "${1:-patch}")"
    DESTINATION="$(sanitize_path "${2:-$SOURCE.jar}")"
    CLASSPATH="$(sanitize_path "${3:-lsd.jar}")"

    d_exists "${SOURCE}"
    f_exists "${CLASSPATH}"
    confirm_overwrite "${DESTINATION}"

    FILES=()
    for file in "${SOURCE}"/**/*.java; do
        FILES+=("${file}")
    done

    if "${CLEANUP}"; then
        for f in "${FILES[@]}"; do
            cleanup_java "${f}"
        done
    fi

    for f in "${FILES[@]}"; do
        echo "Compiling ${f}"
        x86 "${SOURCE}" "$(dirname "${CLASSPATH}")" -- \
          "${JAVA_HOME}/bin/javac" -source 1.2 -target 1.2 -cp ".:${CLASSPATH}" "${f}"
    done

    CLASSES=()
    for f in "${FILES[@]}"; do
        CLASSES+=("${f%.java}.class")
    done

    x86 "${SOURCE}" "$(dirname "${DESTINATION}")" -- \
      "${JAVA_HOME}/bin/jar" cvf "${DESTINATION}" "${CLASSES[@]}"
fi
