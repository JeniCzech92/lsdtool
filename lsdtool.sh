#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C.UTF-8

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

print_help() {
    cat <<EOF
Usage: $0 [OPTIONS] [SOURCE] [DESTINATION] [CLASSPATH]

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
EOF
}

#   sanitize_path <path> [extension] [folder-mode]
sanitize_path() {
    local input="$1"
    local ext="${2:-}"               # optional extension
    local folder_mode="${3:-false}"  # treat path as folder

    # Strip trailing slashes for normalization
    input="${input%/}"

    # Validate non-empty
    if [[ -z "$input" ]]; then
        echo "Error: empty path" >&2
        exit 1
    fi

    # Reject Windows-style backslashes
    if [[ "$input" == *\\* ]]; then
        echo "Error: invalid character '\\' in path: $input" >&2
        exit 1
    fi

    # Reject wildcards (* ? [ ])
    if [[ "$input" == *[\*\?\[]* ]]; then
        echo "Error: wildcards are not allowed in path: $input" >&2
        exit 1
    fi

    # Normalize absolute vs relative
    local path=""
    if [[ "$input" = /* ]]; then
        path="$input"
    else
        path="./$input"
    fi

    # Append extension if provided
    local filename=$(basename "$path")
    if [[ -n "$ext" && "$path" != *"$ext" && "$filename" != *.* ]]; then
        path="$path$ext"
    fi

    echo "$path"
}

#   confirm_overwrite <file>
confirm_overwrite() {
    local file="$1"
    if [[ -f "$file" ]]; then
        read -p "File '$file' already exists. Overwrite? [y/N]: " answer
        case "$answer" in
            [Yy]* ) return 0 ;;
            * ) echo "Aborting." >&2; exit 1 ;;
        esac
    elif [[ -d "$file" ]]; then
        read -p "Directory '$file' already exists. Overwrite? [y/N]: " answer
        case "$answer" in
            [Yy]* ) : ;;
            * ) echo "Aborting." >&2; exit 1 ;;
        esac
        read -p "Should I delete it? [Y/n]: " answer
        case "$answer" in
            [Nn]* ) return 0 ;;
            * )
                [ -n "$file" ] && [ "$file" != "/" ] && [ -d "$file" ] && rm -rf "$file"
                return 0 ;;
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

getjdk() {
    if [ ! -e "$1/utils/jdk/bin/javac" ]; then
        if ! command --version patchelf >/dev/null 2>&1; then
            echo "Downloading 32-bit JDK..."
            mkdir -p "$1/utils/jdk"
            pushd "$1/utils/jdk" >/dev/null || exit 1

            JDK_ZIP="ibm-java-ws-sdk-pxi3260sr4ifx.zip"
            JDK_URL="https://gitlab.com/alelec/mib2-lsd-patching/-/raw/main/${JDK_ZIP}"

            if ! curl -fSL "$JDK_URL" -o "$JDK_ZIP"; then
                echo "Error: Download failed!"
                popd >/dev/null
                exit 1
            fi

            if command -v unzip >/dev/null 2>&1; then
                unzip -q "$JDK_ZIP"
            else
                echo "Error: unzip command not found, cannot extract JDK!" >&2
                popd >/dev/null
                exit 1
            fi
            rm -f "$JDK_ZIP"
            echo "Patching java..."
            patchelf --clear-execstack ./jre/lib/i386/j9vm/libjvm.so
            patchelf --clear-execstack ./jre/lib/i386/*.so
            popd >/dev/null || exit 1
        else
            echo "Error: 32-bit JDK not found, we will need patchelf, but we don't have it."
            exit 1
        fi
    fi
}

f_exists() { [[ -f "$1" ]] || { echo "Error: file not found: $1" >&2; exit 1; }; }
d_exists()  { [[ -d "$1" ]] || { echo "Error: directory not found: $1" >&2; exit 1; }; }

if [[ $EUID -eq 0 ]]; then
    echo "Error: Don't run this as root, please." >&2
    exit 1
fi

PARAMS=$(getopt -o hxabni \
    --long help,jxe,jar,build,nocleanup,install \
    -n "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1
fi

if [[ $# -eq 0 ]]; then
    print_help
    exit 64
fi

eval set -- "$PARAMS"
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

if [[ "$MODE" == "install" ]]; then
    INSTALL_DIR="$HOME/.local/share/lsdtool"
    SYMLINK="$HOME/.local/bin/lsdtool"
    echo "Installing lsdtool to $INSTALL_DIR"
    if [ -e "$INSTALL_DIR" ]; then
        read -rp "Installation directory already exists. Proceed anyway? [Y/n] " reply
        if [[ "$reply" =~ ^[nN] ]]; then
            echo "Aborting..."
            exit 1
        fi
    fi
    mkdir -p "$INSTALL_DIR"
    cp $SCRIPT_DIR/lsdtool.sh $INSTALL_DIR/lsdtool.sh
    echo "Making symlink at $SYMLINK"
    cp -rT $SCRIPT_DIR/utils $INSTALL_DIR/utils
    rm -f $SYMLINK
    ln -s "$INSTALL_DIR/lsdtool.sh" "$SYMLINK"
    chmod +x "$SYMLINK"
    chmod +x "$INSTALL_DIR/utils/JXE2JAR"
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
    getjdk $INSTALL_DIR
    exit 0
fi

if ! command -v java >/dev/null 2>&1; then
    echo "Error: java not found in PATH. Please install JDK." >&2
    exit 1
fi

if ! command -v jar >/dev/null 2>&1; then
    echo "Error: jar not found in PATH. Please install JDK, JRE is nice, but not sufficient." >&2
    exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
    echo "Error: perl not found in PATH. Please install perl." >&2
    exit 1
fi

getjdk $SCRIPT_DIR

NEEDED_EXECUTABLES=(
    "$SCRIPT_DIR/utils/jdk/bin/javac"
    "$SCRIPT_DIR/utils/JXE2JAR"
)

# Check all files exist
for f in "${NEEDED_EXECUTABLES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "Missing required file: $f"
        exit 1
    fi
done

# Check if any executable bit is missing
MISSING_X=()
for f in "${NEEDED_EXECUTABLES[@]}"; do
    [[ -x "$f" ]] || MISSING_X+=("$f")
done

# If some files need +x, prompt once
if [[ ${#MISSING_X[@]} -gt 0 ]]; then
    echo "The following required files are not executable:"
    for f in "${MISSING_X[@]}"; do
        echo "    $f"
    done
    read -p "Attempt to fix permissions for all required files with chmod +x? [Y/n]: " answer
    case "$answer" in
        [Nn]* ) echo "Aborting."; exit 1 ;;
        * )
            # Attempt as current user, fallback to sudo if needed
            chmod +x "${NEEDED_EXECUTABLES[@]}" 2>/dev/null || sudo chmod +x "${NEEDED_EXECUTABLES[@]}"
            echo "Permissions fixed."
            ;;
    esac
fi

if file "$SCRIPT_DIR/utils/jdk/bin/javac" | grep -q "32-bit"; then
    if ! ldd "$SCRIPT_DIR/utils/jdk/bin/javac" >/dev/null 2>&1; then
        echo "Error: Cannot execute 32-bit javac. Make sure lib32-gcc-libs is installed:"
        ldd "$SCRIPT_DIR/utils/jdk/bin/javac"
        exit 1
    fi
else
    echo "Error: cannot recognize javac binary"
    exit 1
fi

CLEANUP=true

if [[ "$MODE" == "jxe" ]]; then
    SOURCE="$(sanitize_path "${1:-lsd.jxe}" ".jxe")"
    DESTINATION="$(sanitize_path "${2:-lsd_java}" "" true)"
    f_exists "$SOURCE"
    confirm_overwrite "${SOURCE%.*}.jar"
    confirm_overwrite "$DESTINATION"
    echo "Converting $SOURCE -> ${SOURCE%.*}.jar"
    $SCRIPT_DIR/utils/JXE2JAR "$SOURCE" "${SOURCE%.*}.jar"
    echo "Decompiling ${SOURCE%.*}.jar -> $DESTINATION"
    java -Xmx6g -jar $SCRIPT_DIR/utils/cfr-0.152.jar --previewfeatures false --switchexpression false --outputdir $DESTINATION ${SOURCE%.*}.jar
elif [[ "$MODE" == "jar" ]]; then
    SOURCE="$(sanitize_path "${1:-lsd.jar}" ".jar")"
    DESTINATION="$(sanitize_path "${2:-lsd_java}" "" true)"
    f_exists "$SOURCE"
    confirm_overwrite "$DESTINATION"
    echo "Decompiling $SOURCE -> $DESTINATION"
    java -Xmx6g -jar $SCRIPT_DIR/utils/cfr-0.152.jar --previewfeatures false --switchexpression false --outputdir $DESTINATION $SOURCE
elif [[ "$MODE" == "build" ]]; then
    SOURCE="$(sanitize_path "${1:-patch}" "" true)"
    DESTINATION="$(sanitize_path "${2:-$SOURCE.jar}" ".jar")"
    CLASSPATH="$(sanitize_path "${3:-lsd.jar}" ".jar")"
    d_exists "$SOURCE"
    f_exists "$CLASSPATH"
    confirm_overwrite "$DESTINATION"
    FILES=()
    CLASSES=()
    while IFS= read -r file; do
        FILES+=("$file")
    done < <(find "$SOURCE" -type f -name '*.java')
    if [[ "${CLEANUP:-true}" == true ]]; then
        for f in "${FILES[@]}"; do
            cleanup_java "$f"
        done
    fi
    for f in "${FILES[@]}"; do
        echo "Compiling $f"
        $SCRIPT_DIR/utils/jdk/bin/javac -source 1.2 -target 1.2 -cp ".:${CLASSPATH}" "$f"
    done
    for f in "${FILES[@]}"; do
        CLASSES+=("${f%.java}.class")
    done
    jar cvf "$DESTINATION" "${CLASSES[@]}"
fi
