#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="Sakura Launcher GUI"
APP_ID="io.github.PiDanShouRouZhouXD.SakuraLauncherGUI"
PACKAGE_NAME="sakura-launcher-gui"
EXECUTABLE_NAME="SakuraLauncher"
MAINTAINER="Sakura Launcher GUI Contributors <noreply@example.com>"
HOMEPAGE="https://github.com/PiDanShouRouZhouXD/Sakura_Launcher_GUI"
DESCRIPTION="GUI launcher for Sakura LLM and llama.cpp"
PYTHON_BIN="${PYTHON_BIN:-python}"

BUILD_ROOT="$PROJECT_ROOT/build/linux"
ARTIFACT_DIR="$PROJECT_ROOT/dist/linux"
PYINSTALLER_APP_DIR="$PROJECT_ROOT/dist/$EXECUTABLE_NAME"
DESKTOP_FILE="$PROJECT_ROOT/packaging/linux/$APP_ID.desktop"
METAINFO_FILE="$PROJECT_ROOT/packaging/linux/$APP_ID.metainfo.xml"
LAUNCHER_FILE="$PROJECT_ROOT/packaging/linux/$PACKAGE_NAME"
APPRUN_FILE="$PROJECT_ROOT/packaging/linux/AppRun"

usage() {
    cat <<'EOF'
Usage: packaging/linux/build_packages.sh [--skip-pyinstaller] [--formats appimage,deb,rpm]

Builds Linux AppImage, deb, and rpm packages from the PyInstaller output.

Environment:
  PYTHON_BIN       Python executable used to run PyInstaller. Default: python
  APPIMAGETOOL    Path to appimagetool. If unset, the script downloads it.
EOF
}

SKIP_PYINSTALLER=0
FORMATS="appimage,deb,rpm"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-pyinstaller)
            SKIP_PYINSTALLER=1
            shift
            ;;
        --formats)
            FORMATS="${2:-}"
            if [ -z "$FORMATS" ]; then
                echo "Missing value for --formats" >&2
                exit 2
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

get_version() {
    "$PYTHON_BIN" - <<'PY'
import ast
from pathlib import Path

tree = ast.parse(Path("src/common.py").read_text(encoding="utf-8"))
for node in tree.body:
    if isinstance(node, ast.Assign):
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id == "SAKURA_LAUNCHER_GUI_VERSION":
                print(ast.literal_eval(node.value))
                raise SystemExit
raise SystemExit("SAKURA_LAUNCHER_GUI_VERSION not found")
PY
}

sanitize_file_part() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

VERSION_RAW="$(cd "$PROJECT_ROOT" && get_version)"
VERSION_BASE="${VERSION_RAW#v}"
DEB_VERSION="$VERSION_BASE"
if [[ "$DEB_VERSION" == *-* ]]; then
    DEB_VERSION="${DEB_VERSION%%-*}~${DEB_VERSION#*-}"
fi
RPM_VERSION="$VERSION_BASE"
RPM_RELEASE="1"
if [[ "$RPM_VERSION" == *-* ]]; then
    RPM_RELEASE="${RPM_VERSION#*-}.1"
    RPM_VERSION="${RPM_VERSION%%-*}"
fi
RPM_RELEASE="$(sanitize_file_part "$RPM_RELEASE")"
FILE_VERSION="$(sanitize_file_part "$VERSION_RAW")"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64|amd64)
        DEB_ARCH="amd64"
        APPIMAGE_ARCH="x86_64"
        RPM_ARCH="x86_64"
        ;;
    aarch64|arm64)
        DEB_ARCH="arm64"
        APPIMAGE_ARCH="aarch64"
        RPM_ARCH="aarch64"
        ;;
    *)
        DEB_ARCH="$HOST_ARCH"
        APPIMAGE_ARCH="$HOST_ARCH"
        RPM_ARCH="$HOST_ARCH"
        ;;
esac

need_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

format_enabled() {
    case ",$FORMATS," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

make_icon() {
    local dest="$1"
    mkdir -p "$(dirname "$dest")"

    if command -v magick >/dev/null 2>&1; then
        magick "$PROJECT_ROOT/icon.ico[0]" -resize 256x256 "$dest"
        return
    fi

    if command -v convert >/dev/null 2>&1; then
        convert "$PROJECT_ROOT/icon.ico[0]" -resize 256x256 "$dest"
        return
    fi

    ICON_SRC="$PROJECT_ROOT/icon.ico" ICON_DEST="$dest" "$PYTHON_BIN" - <<'PY'
import os
from PIL import Image

src = os.environ["ICON_SRC"]
dest = os.environ["ICON_DEST"]
with Image.open(src) as image:
    image.seek(0)
    image = image.convert("RGBA")
    image.thumbnail((256, 256))
    image.save(dest)
PY
}

run_pyinstaller() {
    echo "==> Building PyInstaller Linux onedir"
    (cd "$PROJECT_ROOT" && "$PYTHON_BIN" -m PyInstaller --clean --noconfirm main.spec)
}

stage_root() {
    local root="$1"
    rm -rf "$root"
    mkdir -p \
        "$root/usr/bin" \
        "$root/usr/lib/$PACKAGE_NAME" \
        "$root/usr/share/applications" \
        "$root/usr/share/icons/hicolor/256x256/apps" \
        "$root/usr/share/licenses/$PACKAGE_NAME" \
        "$root/usr/share/metainfo" \
        "$root/usr/share/doc/$PACKAGE_NAME"

    if [ ! -d "$PYINSTALLER_APP_DIR" ]; then
        echo "PyInstaller output not found: $PYINSTALLER_APP_DIR" >&2
        echo "Run this script without --skip-pyinstaller first." >&2
        exit 1
    fi

    cp -a "$PYINSTALLER_APP_DIR/." "$root/usr/lib/$PACKAGE_NAME/"
    install -m 0755 "$LAUNCHER_FILE" "$root/usr/bin/$PACKAGE_NAME"
    install -m 0644 "$DESKTOP_FILE" "$root/usr/share/applications/$APP_ID.desktop"
    install -m 0644 "$METAINFO_FILE" "$root/usr/share/metainfo/$APP_ID.appdata.xml"
    install -m 0644 "$PROJECT_ROOT/LICENSE" "$root/usr/share/licenses/$PACKAGE_NAME/LICENSE"
    install -m 0644 "$PROJECT_ROOT/README.md" "$root/usr/share/doc/$PACKAGE_NAME/README.md"
    make_icon "$root/usr/share/icons/hicolor/256x256/apps/$PACKAGE_NAME.png"
}

build_appimage() {
    need_command curl

    local appdir="$BUILD_ROOT/AppDir"
    local output="$ARTIFACT_DIR/Sakura_Launcher_GUI_${FILE_VERSION}_linux_${APPIMAGE_ARCH}.AppImage"
    local tool="${APPIMAGETOOL:-}"

    echo "==> Building AppImage"
    stage_root "$appdir"
    install -m 0755 "$APPRUN_FILE" "$appdir/AppRun"
    cp "$appdir/usr/share/applications/$APP_ID.desktop" "$appdir/$APP_ID.desktop"
    cp "$appdir/usr/share/icons/hicolor/256x256/apps/$PACKAGE_NAME.png" "$appdir/$PACKAGE_NAME.png"

    if [ -z "$tool" ]; then
        if command -v appimagetool >/dev/null 2>&1; then
            tool="$(command -v appimagetool)"
        else
            mkdir -p "$BUILD_ROOT/tools"
            tool="$BUILD_ROOT/tools/appimagetool-$APPIMAGE_ARCH.AppImage"
            if [ ! -x "$tool" ]; then
                curl -L \
                    "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$APPIMAGE_ARCH.AppImage" \
                    -o "$tool"
                chmod +x "$tool"
            fi
        fi
    fi

    rm -f "$output"
    ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$tool" "$appdir" "$output"
    chmod +x "$output"
}

build_deb() {
    local root="$BUILD_ROOT/deb-root"
    local output="$ARTIFACT_DIR/Sakura_Launcher_GUI_${FILE_VERSION}_linux_${DEB_ARCH}.deb"
    local installed_size

    echo "==> Building deb"
    stage_root "$root"
    mkdir -p "$root/DEBIAN"
    installed_size="$(du -sk "$root/usr" | cut -f1)"

    cat > "$root/DEBIAN/control" <<EOF
Package: $PACKAGE_NAME
Version: $DEB_VERSION
Section: utils
Priority: optional
Architecture: $DEB_ARCH
Maintainer: $MAINTAINER
Installed-Size: $installed_size
Homepage: $HOMEPAGE
Depends: libc6, libgl1, libxcb-cursor0, libxkbcommon-x11-0
Description: $DESCRIPTION
 A PySide6 desktop launcher for running Sakura models with llama.cpp.
EOF

    rm -f "$output"
    if command -v dpkg-deb >/dev/null 2>&1; then
        if command -v fakeroot >/dev/null 2>&1; then
            fakeroot dpkg-deb --build "$root" "$output"
        else
            dpkg-deb --build "$root" "$output"
        fi
    else
        need_command ar
        local tmp="$BUILD_ROOT/deb-archive"
        rm -rf "$tmp"
        mkdir -p "$tmp"
        printf '2.0\n' > "$tmp/debian-binary"
        tar --owner=0 --group=0 --numeric-owner -C "$root/DEBIAN" -czf "$tmp/control.tar.gz" .
        tar --owner=0 --group=0 --numeric-owner --exclude='./DEBIAN' -C "$root" -czf "$tmp/data.tar.gz" .
        (cd "$tmp" && ar rcs "$output" debian-binary control.tar.gz data.tar.gz)
    fi
}

build_rpm() {
    need_command rpmbuild

    local topdir="$BUILD_ROOT/rpmbuild"
    local source_dir="$topdir/SOURCES/$PACKAGE_NAME-$RPM_VERSION"
    local spec_file="$topdir/SPECS/$PACKAGE_NAME.spec"
    local output="$ARTIFACT_DIR/Sakura_Launcher_GUI_${FILE_VERSION}_linux_${RPM_ARCH}.rpm"
    local built_rpm

    echo "==> Building rpm"
    rm -rf "$topdir"
    mkdir -p "$topdir/BUILD" "$topdir/RPMS" "$topdir/SOURCES" "$topdir/SPECS" "$topdir/SRPMS"
    stage_root "$source_dir"
    tar -C "$topdir/SOURCES" -czf "$topdir/SOURCES/$PACKAGE_NAME-$RPM_VERSION.tar.gz" "$PACKAGE_NAME-$RPM_VERSION"

    cat > "$spec_file" <<EOF
%global debug_package %{nil}

Name:           $PACKAGE_NAME
Version:        $RPM_VERSION
Release:        $RPM_RELEASE%{?dist}
Summary:        $DESCRIPTION
License:        GPL-3.0-only
URL:            $HOMEPAGE
Source0:        $PACKAGE_NAME-$RPM_VERSION.tar.gz
AutoReqProv:    no
Requires:       glibc

%description
A PySide6 desktop launcher for running Sakura models with llama.cpp.

%prep
%setup -q

%build

%install
mkdir -p %{buildroot}
cp -a . %{buildroot}/

%files
%license /usr/share/licenses/$PACKAGE_NAME/LICENSE
%doc /usr/share/doc/$PACKAGE_NAME/README.md
/usr/bin/$PACKAGE_NAME
/usr/lib/$PACKAGE_NAME
/usr/share/applications/$APP_ID.desktop
/usr/share/icons/hicolor/256x256/apps/$PACKAGE_NAME.png
/usr/share/metainfo/$APP_ID.appdata.xml

%changelog
* Fri Sep 04 2026 Sakura Launcher GUI Contributors <noreply@example.com> - $RPM_VERSION-$RPM_RELEASE
- Package Linux build
EOF

    rpmbuild --define "_topdir $topdir" --target "$RPM_ARCH" -bb "$spec_file"
    built_rpm="$(find "$topdir/RPMS" -type f -name '*.rpm' | sort | head -n 1)"
    rm -f "$ARTIFACT_DIR/$PACKAGE_NAME-"*.rpm
    cp -f "$built_rpm" "$output"
}

main() {
    mkdir -p "$BUILD_ROOT" "$ARTIFACT_DIR"

    if [ "$SKIP_PYINSTALLER" -eq 0 ]; then
        run_pyinstaller
    fi

    if format_enabled appimage; then
        build_appimage
    fi
    if format_enabled deb; then
        build_deb
    fi
    if format_enabled rpm; then
        build_rpm
    fi

    echo "==> Linux packages:"
    find "$ARTIFACT_DIR" -maxdepth 1 -type f | sort
}

main "$@"
